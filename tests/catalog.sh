#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

need_text() {
  local file="$1" pat="$2"
  grep -q -- "$pat" "$ROOT/$file" || fail "$file missing /$pat/"
}

SHA1="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
SHA2="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

pin="$ROOT/scripts/pin-grok-catalog.py"
[[ -x "$pin" ]] || fail "missing executable scripts/pin-grok-catalog.py"

empty_catalog() {
  local dest="$1"
  mkdir -p "$(dirname "$dest")"
  printf '%s\n' '{"name":"xai-official","owner":{"name":"xAI"},"plugins":[]}' >"$dest"
}

plugin_count() {
  python3 -c 'import json,sys; print(sum(1 for p in json.load(open(sys.argv[1])).get("plugins",[]) if p.get("name")=="software-factory"))' "$1"
}

plugin_sha() {
  python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
found=[p for p in d.get("plugins",[]) if p.get("name")=="software-factory"]
print(found[0]["source"]["sha"] if found else "")' "$1"
}

cat1="$TMP/marketplace.json"
empty_catalog "$cat1"
"$pin" "$cat1" "$SHA1" "https://github.com/Kripu77/software-factory.git" || fail "first pin should add the listing"
[[ "$(plugin_count "$cat1")" == "1" ]] || fail "first listing should add exactly one software-factory entry"
[[ "$(plugin_sha "$cat1")" == "$SHA1" ]] || fail "first listing should pin the tag SHA, not main"
python3 - "$cat1" "$SHA1" <<'PY' || fail "first listing is not a remote url pin"
import json, sys
path, sha = sys.argv[1], sys.argv[2]
p = next(x for x in json.load(open(path))["plugins"] if x["name"] == "software-factory")
src = p["source"]
if src.get("source") != "url":
    raise SystemExit(f"source.source should be url, got {src}")
if src.get("url") != "https://github.com/Kripu77/software-factory.git":
    raise SystemExit(f"unexpected url {src.get('url')}")
if src.get("sha") != sha:
    raise SystemExit(f"sha {src.get('sha')} != {sha}")
if src.get("sha") in ("main", "master"):
    raise SystemExit("must not pin main")
if "type" in src and src["type"] == "local":
    raise SystemExit("official catalog entry must not be a local vendor")
PY

"$pin" "$cat1" "$SHA2" "https://github.com/Kripu77/software-factory.git" || fail "second pin should bump the SHA"
[[ "$(plugin_count "$cat1")" == "1" ]] || fail "second tag must bump SHA, not add a duplicate first-listing"
[[ "$(plugin_sha "$cat1")" == "$SHA2" ]] || fail "second tag should pin the new tag SHA"

set +e
"$pin" "$cat1" "main" "https://github.com/Kripu77/software-factory.git" >"$TMP/out" 2>"$TMP/err"
code=$?
set -e
[[ $code -ne 0 ]] || fail "pinning main should fail"
[[ "$(plugin_sha "$cat1")" == "$SHA2" ]] || fail "rejected pin must leave the catalog SHA alone"

set +e
"$pin" "$cat1" "abc" "https://github.com/Kripu77/software-factory.git" >"$TMP/out" 2>"$TMP/err"
code=$?
set -e
[[ $code -ne 0 ]] || fail "short SHA should fail"

echo "ok catalog pin"

ship="$ROOT/scripts/ship-grok-catalog.sh"
[[ -x "$ship" ]] || fail "missing executable scripts/ship-grok-catalog.sh"

if grep -q "gh pr merge" "$ship" || grep -q "gh merge" "$ship"; then
  fail "catalog ship must not merge"
fi
if grep -q "\.env" "$ship"; then
  fail "catalog ship must not touch .env"
fi
if grep -E -q 'echo +"\$\{?(token|TOKEN|GH_TOKEN|XAI_MARKETPLACE_TOKEN)' "$ship"; then
  fail "catalog ship must not print the token"
fi

hid="$TMP/bin"
mkdir -p "$hid"
for cmd in bash mkdir ln rm echo grep command cat cp python3 mv chmod mkdir; do
  src="$(command -v "$cmd" || true)"
  [[ -n "$src" ]] && ln -sf "$src" "$hid/$cmd"
done
real_git="$(command -v git)"
[[ -n "$real_git" ]] || fail "git required for catalog ship tests"
cat >"$hid/git" <<EOF
#!/usr/bin/env bash
set -euo pipefail
for arg in "\$@"; do
  if [[ "\$arg" == "push" ]]; then
    printf '%s\n' "git \$*" >>"$TMP/git.log"
    exit 0
  fi
done
exec "$real_git" "\$@"
EOF
chmod +x "$hid/git"

cat >"$hid/gh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "gh \$*" >>"$TMP/gh.log"
case "\${1:-}" in
  api)
    echo "testuser"
    exit 0
    ;;
  repo)
    exit 0
    ;;
  pr)
    if [[ "\${2:-}" == "merge" ]]; then
      echo "must not merge" >&2
      exit 2
    fi
    if [[ "\${2:-}" == "list" ]]; then
      if [[ -f "$TMP/open-pr" ]]; then
        echo "1"
      else
        echo "0"
      fi
      exit 0
    fi
    if [[ "\${2:-}" == "create" ]]; then
      printf '%s\n' "\$*" >>"$TMP/pr-create.log"
      echo "https://github.com/xai-org/plugin-marketplace/pull/99"
      echo "1" >"$TMP/open-pr"
      exit 0
    fi
    exit 0
    ;;
esac
exit 0
EOF
chmod +x "$hid/gh"

init_catalog_repo() {
  local dest="$1"
  mkdir -p "$dest/.grok-plugin"
  printf '%s\n' '{"name":"xai-official","owner":{"name":"xAI"},"plugins":[]}' >"$dest/.grok-plugin/marketplace.json"
  (
    cd "$dest"
    "$real_git" init -q
    "$real_git" config user.email "factory@example.com"
    "$real_git" config user.name "factory"
    "$real_git" add .grok-plugin/marketplace.json
    "$real_git" commit -q -m "initial catalog"
  )
}

export PATH="$hid:$PATH"
unset XAI_MARKETPLACE_TOKEN
unset GH_TOKEN
catalog_repo="$TMP/marketplace"
init_catalog_repo "$catalog_repo"

set +e
XAI_MARKETPLACE_DIR="$catalog_repo" "$ship" v1.0.0 "$SHA1" >"$TMP/ship-out" 2>"$TMP/ship-err"
code=$?
set -e
[[ $code -ne 0 ]] || fail "missing token should fail so a person stores it"
grep -q "XAI_MARKETPLACE_TOKEN" "$TMP/ship-err" || fail "missing token should name XAI_MARKETPLACE_TOKEN: $(cat "$TMP/ship-err")"

: >"$TMP/gh.log"
: >"$TMP/git.log"
rm -f "$TMP/pr-create.log" "$TMP/open-pr"
export XAI_MARKETPLACE_TOKEN="test-token-not-a-secret-value"
export XAI_MARKETPLACE_DIR="$catalog_repo"
export XAI_MARKETPLACE_REPO="xai-org/plugin-marketplace"
"$ship" v1.0.0 "$SHA1" >"$TMP/ship-out" 2>"$TMP/ship-err" || fail "first listing should open a catalog PR: $(cat "$TMP/ship-err")"
[[ "$(plugin_count "$catalog_repo/.grok-plugin/marketplace.json")" == "1" ]] || fail "first listing should add software-factory"
[[ "$(plugin_sha "$catalog_repo/.grok-plugin/marketplace.json")" == "$SHA1" ]] || fail "first listing should pin $SHA1"
[[ -f "$TMP/pr-create.log" ]] || fail "first listing should gh pr create"
grep -qi "Add" "$TMP/pr-create.log" || fail "first listing PR should be an add, not a SHA bump: $(cat "$TMP/pr-create.log")"
if grep -q "gh pr merge" "$TMP/gh.log" || grep -q "gh merge" "$TMP/gh.log"; then
  fail "first listing must not merge"
fi
if grep -q "test-token-not-a-secret-value" "$catalog_repo/.grok-plugin/marketplace.json"; then
  fail "token must not land in the catalog"
fi
"$real_git" -C "$catalog_repo" log -1 --pretty=%B | grep -q "software-factory" || fail "catalog commit should mention software-factory"

"$ship" v1.1.0 "$SHA2" >"$TMP/ship-out2" 2>"$TMP/ship-err2" || fail "open first-listing PR should update the pin: $(cat "$TMP/ship-err2")"
[[ "$(plugin_count "$catalog_repo/.grok-plugin/marketplace.json")" == "1" ]] || fail "updating the open PR must not duplicate the listing"
[[ "$(plugin_sha "$catalog_repo/.grok-plugin/marketplace.json")" == "$SHA2" ]] || fail "open PR should move to the new tag SHA"

creates="$(wc -l <"$TMP/pr-create.log" | tr -d ' ')"
[[ "$creates" == "1" ]] || fail "open first-listing PR should be updated, not created again: $(cat "$TMP/pr-create.log")"

rm -f "$TMP/open-pr" "$TMP/pr-create.log"
"$ship" v1.2.0 "$SHA1" >"$TMP/ship-out3" 2>"$TMP/ship-err3" || fail "later tag with no open PR should open a SHA bump: $(cat "$TMP/ship-err3")"
[[ "$(plugin_count "$catalog_repo/.grok-plugin/marketplace.json")" == "1" ]] || fail "SHA bump must not add a second listing"
[[ "$(plugin_sha "$catalog_repo/.grok-plugin/marketplace.json")" == "$SHA1" ]] || fail "SHA bump should pin the later tag"
[[ -f "$TMP/pr-create.log" ]] || fail "merged first listing then a later tag should open a bump PR"
grep -qi "Bump" "$TMP/pr-create.log" || fail "later tag PR should be a SHA bump: $(cat "$TMP/pr-create.log")"
if grep -qi "Add software-factory" "$TMP/pr-create.log"; then
  fail "later tag must not open a duplicate first-listing"
fi
if grep -q "gh pr merge" "$TMP/gh.log"; then
  fail "SHA bump must not merge"
fi

echo "ok catalog ship"

rel="$ROOT/.github/workflows/release.yml"
need_text .github/workflows/release.yml "ship-grok-catalog.sh"
need_text .github/workflows/release.yml "XAI_MARKETPLACE_TOKEN"
need_text .github/workflows/release.yml "GITHUB_SHA"
need_text .github/workflows/release.yml "GITHUB_REF_NAME"
need_text .github/workflows/release.yml "re-index"
grep -q "secrets.XAI_MARKETPLACE_TOKEN" "$rel" || fail "release should read XAI_MARKETPLACE_TOKEN from GitHub secrets"
if grep -qi "schedule:" "$rel" || grep -qi "cron:" "$rel"; then
  fail "catalog pin should ship on the tag, not wait for a daily cron"
fi
if grep -q "gh pr merge" "$rel" || grep -q "gh merge" "$rel"; then
  fail "release workflow must not merge"
fi
if grep -q "\.env" "$rel"; then
  fail "release workflow must not touch .env"
fi
if grep -q "main" "$rel" && grep -E 'ship-grok-catalog.sh.*main' "$rel"; then
  fail "catalog pin must use the tag SHA, not main"
fi
python3 - "$rel" <<'PY' || fail "release notes should tell a person to request Cursor re-index"
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text()
if "re-index" not in text:
    raise SystemExit("missing re-index")
if "cursor.com/api" in text or "POST" in text:
    raise SystemExit("do not invent a Cursor publish API")
PY

extras="$(grep -oE 'secrets\.[A-Za-z0-9_]+' "$rel" | grep -v 'secrets.XAI_MARKETPLACE_TOKEN' || true)"
if [[ -n "$extras" ]]; then
  fail "unexpected secrets in release workflow: $extras"
fi

readme="$ROOT/README.md"
need_text README.md "XAI_MARKETPLACE_TOKEN"
need_text README.md "xai-org/plugin-marketplace"
need_text README.md "re-index"
python3 - "$readme" <<'PY' || fail "README must describe official catalogs without filling person-only forms"
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text()
lower = text.lower()
if "official" not in lower or "catalog" not in lower:
    raise SystemExit("README needs an official catalogs section")
if "claude" not in lower:
    raise SystemExit("README must cover Claude official directory")
if "form" not in lower:
    raise SystemExit("README must say a person submits the Claude, Cursor, and Codex forms")
if "cursor" not in lower or "re-index" not in lower:
    raise SystemExit("README must say a person requests Cursor re-index")
if "codex" not in lower:
    raise SystemExit("README must cover Codex")
if "does not fill" not in lower and "do not fill" not in lower and "agent does not" not in lower:
    raise SystemExit("README must say the agent does not fill those forms")
if "follow github" not in lower and "follows github" not in lower:
    raise SystemExit("README must say Claude later tags follow GitHub")
PY

for f in scripts/pin-grok-catalog.py scripts/ship-grok-catalog.sh .github/workflows/release.yml README.md; do
  if grep -qiE 'cursor.com/api|publish.cursor|claude.ai/api|openai.com/v1/plugins' "$ROOT/$f"; then
    fail "$f must not invent a catalog publish API"
  fi
done

echo "ok catalog docs"
