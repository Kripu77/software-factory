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

# Writing GFM lives in HARD and AGENTS.md. Review fail rules live in the review lane.
for f in factory.sh AGENTS.md; do
  need_text "$f" "short paragraphs"
  need_text "$f" "blank line before any list or fence"
  need_text "$f" "starts with #n"
  need_text "$f" "markdown link"
done

for f in factory.sh AGENTS.md skills/implement/SKILL.md; do
  need_text "$f" "at most 3 sentences"
  need_text "$f" "then mermaid"
done

need_text factory.sh "docs tree"
need_text factory.sh "missing architecture page"
need_text factory.sh "persist only the corrected after-state"
need_text lanes/review.md "Request changes"
need_text lanes/review.md "wall of text"
need_text lanes/review.md "mermaid"
need_text lanes/review.md "missing"
need_text lanes/review.md "after-state belongs in docs"
need_text lanes/review.md "review summary may use headings"
need_text AGENTS.md "review summary may use headings"

# Ledger ticket_comment shape is unchanged
need_text factory.sh 'body="$SUMMARY"'
grep -F '[PR ${PR}]' "$ROOT/factory.sh" >/dev/null || fail "factory.sh missing ledger [PR n] link"

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

assert_gfm_rules() {
  local lane="$1"
  shift
  rm -rf "$DUMP"
  mkdir -p "$DUMP"
  run_factory "$lane" "$@"
  [[ -f "$DUMP/rules" ]] || fail "$lane did not dump rules"
  grep -q "at most 3 sentences" "$DUMP/rules" || fail "$lane rules missing 3-sentence cap"
  grep -q "then mermaid" "$DUMP/rules" || fail "$lane rules missing mermaid-after-prose"
  grep -q "short paragraphs" "$DUMP/rules" || fail "$lane rules missing short paragraphs"
  grep -q "blank line before any list or fence" "$DUMP/rules" || fail "$lane rules missing blank-line-before-list-or-fence"
  grep -q "starts with #n" "$DUMP/rules" || fail "$lane rules missing #n heading ban"
  grep -q "markdown link" "$DUMP/rules" || fail "$lane rules missing markdown ticket link"
  grep -q "docs tree" "$DUMP/rules" || fail "$lane rules missing persist-into-docs"
}

assert_gfm_rules feature --issue 6
assert_gfm_rules bug --issue 6
assert_gfm_rules docs --issue 6

rm -rf "$DUMP"
mkdir -p "$DUMP"
run_factory review --pr 6
[[ -f "$DUMP/rules" ]] || fail "review did not dump rules"
grep -q "at most 3 sentences" "$DUMP/rules" || fail "review rules missing 3-sentence cap"
grep -q "then mermaid" "$DUMP/rules" || fail "review rules missing mermaid-after-prose"
grep -q "short paragraphs" "$DUMP/rules" || fail "review rules missing short paragraphs"
grep -q "blank line before any list or fence" "$DUMP/rules" || fail "review rules missing blank-line-before-list-or-fence"
grep -q "starts with #n" "$DUMP/rules" || fail "review rules missing #n heading ban"
grep -q "markdown link" "$DUMP/rules" || fail "review rules missing markdown ticket link"
grep -q "Request changes" "$DUMP/rules" || fail "review rules missing request-changes"
grep -q "wall of text" "$DUMP/rules" || fail "review rules missing wall-of-text"
grep -q "missing" "$DUMP/rules" || fail "review rules missing diagrams-missing"
grep -q "after-state belongs in docs" "$DUMP/rules" || fail "review rules missing persist request-changes"
grep -q "review summary may use headings" "$DUMP/rules" || fail "review rules missing review-summary-headings"
grep -q "Never merge" "$DUMP/rules" || fail "review rules must still say never merge"

echo "ok github-markdown"
