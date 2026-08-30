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

need_text() {
  local file="$1" pat="$2"
  grep -q -- "$pat" "$ROOT/$file" || fail "$file missing /$pat/"
}

# Worker commit rule lives in HARD, AGENTS.md, and implement. Review fail rules live in the review lane.
for f in factory.sh AGENTS.md skills/implement/SKILL.md; do
  need_text "$f" "one complete thought"
  need_text "$f" "names that thought"
  need_text "$f" "Keep the diff small"
  need_text "$f" "split the ticket"
  need_text "$f" "No line-count cap"
done

need_text lanes/review.md "Request changes"
need_text lanes/review.md "one commit that is the whole ticket"
need_text AGENTS.md "one commit that is the whole ticket"
need_text AGENTS.md "Whole-ticket dump"

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

run_factory() {
  PATH="$TMP/bin:$PATH" \
    FAKE_DUMP="$DUMP" \
    FACTORY_WORKSPACE="$WS" \
    FACTORY_OWNER=acme \
    FACTORY_RUNNER=runner FACTORY_HARNESS=claude \
    "$FACTORY" "$@" --repo widgets >/dev/null 2>&1
}

assert_commit_rules() {
  local lane="$1"
  shift
  rm -rf "$DUMP"
  mkdir -p "$DUMP"
  run_factory "$lane" "$@"
  [[ -f "$DUMP/rules" ]] || fail "$lane did not dump rules"
  grep -q "one complete thought" "$DUMP/rules" || fail "$lane rules missing one complete thought"
  grep -q "names that thought" "$DUMP/rules" || fail "$lane rules missing names that thought"
  grep -q "Keep the diff small" "$DUMP/rules" || fail "$lane rules missing Keep the diff small"
  grep -q "split the ticket" "$DUMP/rules" || fail "$lane rules missing split the ticket"
  grep -q "No line-count cap" "$DUMP/rules" || fail "$lane rules missing No line-count cap"
}

assert_commit_rules feature --issue 6
assert_commit_rules bug --issue 6
assert_commit_rules docs --issue 6

rm -rf "$DUMP"
mkdir -p "$DUMP"
run_factory review --pr 6
[[ -f "$DUMP/rules" ]] || fail "review did not dump rules"
grep -q "one complete thought" "$DUMP/rules" || fail "review rules missing one complete thought"
grep -q "names that thought" "$DUMP/rules" || fail "review rules missing names that thought"
grep -q "Keep the diff small" "$DUMP/rules" || fail "review rules missing Keep the diff small"
grep -q "split the ticket" "$DUMP/rules" || fail "review rules missing split the ticket"
grep -q "No line-count cap" "$DUMP/rules" || fail "review rules missing No line-count cap"
grep -q "Request changes" "$DUMP/rules" || fail "review rules missing request-changes"
grep -q "one commit that is the whole ticket" "$DUMP/rules" || fail "review rules missing whole-ticket bulk definition"
grep -q "Never merge" "$DUMP/rules" || fail "review rules must still say never merge"

echo "ok atomic-commits"
