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

# Missing conventions file: lane runs, rules untouched
run_lane feature
[[ -f "$DUMP/rules" ]] || fail "feature should run without conventions file"
grep -q "conventions" "$DUMP/rules" && fail "no conventions file must not inject conventions rule"

# Conventions file: each lane gets a must-invoke instruction with every listed skill
mkdir -p "$WS/widgets/.factory"
printf 'euc-go\neuc-react-native\n' > "$WS/widgets/.factory/conventions"
for lane in feature bug docs; do
  rm -rf "$DUMP"
  mkdir -p "$DUMP"
  run_lane "$lane"
  grep -q "euc-go" "$DUMP/rules" || fail "$lane rules missing euc-go"
  grep -q "euc-react-native" "$DUMP/rules" || fail "$lane rules missing euc-react-native"
  grep -qi "invoke" "$DUMP/rules" || fail "$lane rules missing invoke instruction"
done

# Reading the file excludes .factory/ from source control
grep -qxF ".factory/" "$WS/widgets/.git/info/exclude" || fail ".factory/ missing from .git/info/exclude"
run_lane feature
[[ "$(grep -cxF '.factory/' "$WS/widgets/.git/info/exclude")" == "1" ]] || fail ".factory/ excluded more than once"

# Blank lines are skipped
printf '\neuc-sql\n\n' > "$WS/widgets/.factory/conventions"
rm -rf "$DUMP"
mkdir -p "$DUMP"
run_lane feature
grep -q "euc-sql" "$DUMP/rules" || fail "rules missing euc-sql"

# Empty file behaves like a missing file
: > "$WS/widgets/.factory/conventions"
rm -rf "$DUMP"
mkdir -p "$DUMP"
run_lane feature
grep -q "conventions" "$DUMP/rules" && fail "empty conventions file must not inject conventions rule"

# README documents the file
grep -q ".factory/conventions" "$ROOT/README.md" || fail "README missing .factory/conventions"
grep -qi "one skill" "$ROOT/README.md" || fail "README missing one-skill-per-line format"

echo "ok conventions"
