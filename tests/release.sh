#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

check="$ROOT/scripts/check-plugin-versions.sh"
[[ -x "$check" ]] || fail "missing executable scripts/check-plugin-versions.sh"

"$check" v1.0.0 || fail "v1.0.0 should match plugin versions in this checkout"

fx="$TMP/pack"
mkdir -p "$fx/.claude-plugin" "$fx/.cursor-plugin" "$fx/.grok-plugin"
for f in .claude-plugin/plugin.json .cursor-plugin/plugin.json .grok-plugin/plugin.json; do
  cp "$ROOT/$f" "$fx/$f"
done
"$check" v1.0.0 "$fx" || fail "fixture at 1.0.0 should pass v1.0.0"

set +e
"$check" v2.0.0 "$fx" >"$TMP/out" 2>"$TMP/err"
code=$?
set -e
[[ $code -ne 0 ]] || fail "v2.0.0 should fail when plugins are 1.0.0"
grep -q "1.0.0" "$TMP/err" || fail "mismatch should name the plugin version: $(cat "$TMP/err")"

sed 's/"1.0.0"/"1.0.1"/' "$fx/.cursor-plugin/plugin.json" >"$TMP/cursor.json"
mv "$TMP/cursor.json" "$fx/.cursor-plugin/plugin.json"
set +e
"$check" v1.0.0 "$fx" >"$TMP/out" 2>"$TMP/err"
code=$?
set -e
[[ $code -ne 0 ]] || fail "one plugin off the tag should fail"
cp "$ROOT/.cursor-plugin/plugin.json" "$fx/.cursor-plugin/plugin.json"

rm "$fx/.grok-plugin/plugin.json"
set +e
"$check" v1.0.0 "$fx" >"$TMP/out" 2>"$TMP/err"
code=$?
set -e
[[ $code -ne 0 ]] || fail "missing plugin.json should fail"

rel="$ROOT/.github/workflows/release.yml"
[[ -f "$rel" ]] || fail "missing .github/workflows/release.yml"
grep -q "tags:" "$rel" || fail "release workflow should trigger on tags"
grep -q "v\*\.\*\.\*" "$rel" || fail "release workflow should match vX.Y.Z tags"
if grep -q "branches:" "$rel"; then
  fail "release workflow must not run on branch pushes"
fi
if grep -q "pull_request" "$rel"; then
  fail "release workflow must not run on pull_request"
fi
grep -q "ubuntu-latest" "$rel" || fail "should use GitHub-hosted ubuntu-latest"
if grep -qi "self-hosted" "$rel"; then
  fail "must use GitHub-hosted runners"
fi
grep -q "contents: write" "$rel" || fail "creating a Release needs contents: write"
grep -q "gh release create" "$rel" || fail "should create a GitHub Release with gh release create"
if grep -q "gh pr merge" "$rel" || grep -q "gh merge" "$rel"; then
  fail "workflow must not merge"
fi
if grep -q "\.env" "$rel"; then
  fail "workflow must not touch .env"
fi
if grep -qi "secrets" "$rel"; then
  fail "workflow must not use secrets"
fi
if grep -E -- "--notes[[:space:]]+\"\"" "$rel"; then
  fail "Release notes must be non-empty"
fi
if ! grep -q -- "--notes" "$rel" && ! grep -q -- "--generate-notes" "$rel"; then
  fail "Release notes must be non-empty"
fi
grep -q "check-plugin-versions.sh" "$rel" || fail "release should refuse a tag whose plugin versions do not match"

tests="$ROOT/.github/workflows/tests.yml"
grep -q "pull_request" "$tests" || fail "tests workflow should still run on pull_request"
grep -q "push" "$tests" || fail "tests workflow should still run on push"
grep -q "main" "$tests" || fail "tests workflow should still run on main"
grep -q "tests/\*\.sh" "$tests" || fail "tests workflow should still run tests/*.sh"
if grep -q "gh release create" "$tests"; then
  fail "push to main must not create a Release"
fi

need_text() {
  local file="$1" pat="$2"
  grep -q -- "$pat" "$ROOT/$file" || fail "$file missing /$pat/"
}

need_text README.md "git clone"
need_text README.md "./install.sh"
need_text README.md "from-source"
need_text README.md "git tag"
need_text README.md "v1.0.0"
need_text README.md "Releases"

echo "ok release"
