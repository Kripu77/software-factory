#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FACTORY="$ROOT/factory.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export FACTORY_MEMORY_DB="$TMP/memory/factory.db"
unset FACTORY_RUNNER
unset FACTORY_SKIP_TICKET_COMMENT

fail() { echo "FAIL: $*" >&2; exit 1; }

WS="$TMP/workspace"
mkdir -p "$WS/widgets"
git -C "$WS/widgets" init -q
git -C "$WS/widgets" remote add origin "https://github.com/acme/widgets.git"

DUMP="$TMP/dump"
mkdir -p "$DUMP" "$TMP/bin"

cat > "$TMP/bin/runner" << 'EOF'
#!/usr/bin/env bash
dump="${FAKE_DUMP:?}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p) printf '%s\n' "$2" > "$dump/prompt"; shift 2 ;;
    --rules) printf '%s\n' "$2" > "$dump/rules"; shift 2 ;;
    *) shift ;;
  esac
done
exit 0
EOF
chmod +x "$TMP/bin/runner"

cat > "$TMP/bin/gh" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TMP/bin/gh"

run_lane() {
  local lane="$1"
  PATH="$TMP/bin:$PATH" \
    FAKE_DUMP="$DUMP" \
    FACTORY_WORKSPACE="$WS" \
    FACTORY_OWNER=acme \
    FACTORY_RUNNER=runner FACTORY_HARNESS=claude \
    "$FACTORY" "$lane" --repo widgets --issue 6 >/dev/null 2>&1
}

# Missing conventions file: the generic skill-check instruction is still injected
run_lane feature
[[ -f "$DUMP/rules" ]] || fail "feature should run without conventions file"
grep -q "Check for relevant skills before writing code" "$DUMP/rules" || fail "missing file must still inject the generic skill-check instruction"
grep -q "This repo enables these skills" "$DUMP/rules" && fail "missing file must not inject a skill list"

# Conventions file: skill entries with context and repo context reach every implementing lane
mkdir -p "$WS/widgets/.factory"
cat > "$WS/widgets/.factory/conventions" << 'CONV'
# tooling notes
go-style: services and migrations
web-style: web frontends
never add jest tests; never raw HTML
CONV
for lane in feature bug docs; do
  rm -rf "$DUMP"
  mkdir -p "$DUMP"
  run_lane "$lane"
  grep -q "/go-style: services and migrations" "$DUMP/rules" || fail "$lane rules missing go-style with its context"
  grep -q "/web-style: web frontends" "$DUMP/rules" || fail "$lane rules missing web-style with its context"
  grep -q "never add jest tests; never raw HTML" "$DUMP/rules" || fail "$lane rules missing repo context line"
  grep -qi "invoke" "$DUMP/rules" || fail "$lane rules missing invoke instruction"
  grep -q "tooling notes" "$DUMP/rules" && fail "$lane rules must not include comment lines"
done

# Reading the file excludes .factory/ from source control
grep -qxF ".factory/" "$WS/widgets/.git/info/exclude" || fail ".factory/ missing from .git/info/exclude"
run_lane feature
[[ "$(grep -cxF '.factory/' "$WS/widgets/.git/info/exclude")" == "1" ]] || fail ".factory/ excluded more than once"

# Blank lines are skipped and a bare skill name needs no context
printf '\nsql-style\n\n' > "$WS/widgets/.factory/conventions"
rm -rf "$DUMP"
mkdir -p "$DUMP"
run_lane feature
grep -q "/sql-style" "$DUMP/rules" || fail "rules missing bare skill sql-style"

# Empty file behaves like a missing file
: > "$WS/widgets/.factory/conventions"
rm -rf "$DUMP"
mkdir -p "$DUMP"
run_lane feature
grep -q "Check for relevant skills before writing code" "$DUMP/rules" || fail "empty file must still inject the generic skill-check instruction"
grep -q "This repo enables these skills" "$DUMP/rules" && fail "empty conventions file must not inject a skill list"

# README documents the file
grep -q ".factory/conventions" "$ROOT/README.md" || fail "README missing .factory/conventions"
grep -qi "repo context" "$ROOT/README.md" || fail "README missing repo-context format"

echo "ok conventions"
