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
  grep -q "$pat" "$ROOT/$file" || fail "$file missing /$pat/"
}

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
    -p)
      if [[ ! -f "$dump/prompt" ]]; then
        printf '%s\n' "$2" > "$dump/prompt"
      fi
      shift 2
      ;;
    --rules)
      if [[ ! -f "$dump/rules" ]]; then
        printf '%s\n' "$2" > "$dump/rules"
      fi
      shift 2
      ;;
    *) shift ;;
  esac
done
: > "$dump/ran"
case "${FACTORY_LANE:-}" in
  feature|bug|docs)
    : > "$dump/after-feature"
    printf 'grok\n' >> "$dump/dispatched"
    ;;
  review)
    : > "$dump/after-review"
    printf 'grok\n' >> "$dump/dispatched"
    ;;
  ci)
    : > "$dump/after-ci"
    printf 'grok\n' >> "$dump/dispatched"
    ;;
esac
exit "${AGENT_EXIT:-0}"
EOF
chmod +x "$TMP/bin/runner"

cat > "$TMP/bin/gh" << 'EOF'
#!/usr/bin/env bash
dump="${FAKE_DUMP:?}"
printf '%s\n' "$*" >> "$dump/gh"
n=0
if [[ -f "$dump/dispatched" ]]; then
  n="$(wc -l < "$dump/dispatched" | tr -d ' ')"
fi
case "$1 $2" in
  "issue view")
    printf '%s\n' 'ready-for-agent'
    printf '%s\n' 'enhancement'
    ;;
  "pr view")
    if [[ "$*" == *reviews* ]]; then
      if [[ -f "$dump/after-review" ]]; then printf '%s\n' 1; else printf '%s\n' 0; fi
    else
      if [[ -f "$dump/after-feature" ]]; then printf '%s\n' 40; fi
    fi
    ;;
  "pr checks")
    if [[ -f "$dump/after-ci" ]]; then exit 0; else exit 1; fi
    ;;
esac
exit 0
EOF
chmod +x "$TMP/bin/gh"

run_lead() {
  PATH="$TMP/bin:$PATH" \
    FAKE_DUMP="$DUMP" \
    FACTORY_SH="$FACTORY" \
    FACTORY_WORKSPACE="$WS" \
    FACTORY_OWNER=acme \
    FACTORY_RUNNER=runner FACTORY_HARNESS=claude \
    "$FACTORY" lead --issue 7 --repo widgets
}

need_text lanes/tech-lead.md "mem read"
need_text lanes/tech-lead.md "hint"
need_text lanes/tech-lead.md "Do not implement"
need_text lanes/tech-lead.md "factory.sh"
need_text lanes/tech-lead.md "floor"
need_text lanes/tech-lead.md "failed run"
need_text lanes/tech-lead.md "Do not let a lane chain"
need_text commands/lead.md "mem read"
need_text commands/lead.md "Do not implement"
need_text commands/lead.md "factory.sh"
need_text commands/lead.md "floor"
need_text commands/lead.md "failed run"
need_text commands/lead.md "Cursor"

# Missing DB: lead still runs, then starts floor. Lead does not write a run.
rm -rf "$DUMP" "$TMP/memory"
mkdir -p "$DUMP"
set +e
run_lead >"$TMP/out" 2>"$TMP/err"
code=$?
set -e
[[ $code -eq 0 ]] || fail "missing db lead exit $code err=$(cat "$TMP/err")"
[[ -f "$DUMP/ran" ]] || fail "missing db should still run lead"
grep -q "dispatch factory.sh floor" "$TMP/out" || fail "lead should start floor: $(cat "$TMP/out")"
grep -q "dispatch feature" "$TMP/out" || fail "floor after lead should dispatch feature: $(cat "$TMP/out")"
grep -q "a person merges" "$TMP/out" || fail "floor after lead should reach merge: $(cat "$TMP/out")"
warns="$(grep -c "factory.db\|factory memory" "$TMP/err" || true)"
[[ "$warns" -ge 1 ]] || fail "missing db should warn, got $warns: $(cat "$TMP/err")"
lead_rows="$(sqlite3 "$FACTORY_MEMORY_DB" "SELECT COUNT(*) FROM runs WHERE lane = 'lead';")"
[[ "$lead_rows" == "0" ]] || fail "lead must not write runs, got $lead_rows"

# Rows for the issue are in the lead prompt.
rm -rf "$DUMP" "$TMP/memory"
mkdir -p "$DUMP"
"$FACTORY" mem write --harness grok --project acme/widgets --lane feature --status done --issue 7 --pr 40 --summary "Add widgets list" --next-steps "QA the PR" --evidence "https://github.com/acme/widgets/pull/40" >/dev/null
run_lead >"$TMP/out2" 2>"$TMP/err2"
[[ -f "$DUMP/ran" ]] || fail "lead with rows should run"
grep -q "acme/widgets" "$DUMP/prompt" || fail "lead prompt missing project: $(cat "$DUMP/prompt")"
grep -q "status = done" "$DUMP/prompt" || fail "lead prompt missing status: $(cat "$DUMP/prompt")"
grep -q "Add widgets list" "$DUMP/prompt" || fail "lead prompt missing summary: $(cat "$DUMP/prompt")"
grep -q "QA the PR" "$DUMP/prompt" || fail "lead prompt missing next_steps: $(cat "$DUMP/prompt")"
grep -q "factory.sh floor" "$DUMP/prompt" || fail "lead prompt must start floor via factory.sh: $(cat "$DUMP/prompt")"
grep -q "failed run" "$DUMP/prompt" || fail "lead prompt must call implementing a failed run: $(cat "$DUMP/prompt")"
lead_rows="$(sqlite3 "$FACTORY_MEMORY_DB" "SELECT COUNT(*) FROM runs WHERE lane = 'lead';")"
[[ "$lead_rows" == "0" ]] || fail "lead must not write runs, got $lead_rows"

# Issue rows from another project still reach lead.
rm -rf "$DUMP" "$TMP/memory"
mkdir -p "$DUMP"
"$FACTORY" mem write --harness grok --project other/repo --lane feature --status done --issue 7 --summary "Shipped on other remote" --evidence "https://github.com/other/repo/issues/7" >/dev/null
run_lead >"$TMP/out3" 2>"$TMP/err3"
grep -q "Shipped on other remote" "$DUMP/prompt" || fail "lead should see issue 7 from another project: $(cat "$DUMP/prompt")"

# sqlite3 missing: lead still starts floor; GitHub drives the table
hid="$TMP/nosqlite"
mkdir -p "$hid"
for cmd in bash mkdir date sed git grep dirname cat rm mktemp printf tr wc; do
  src="$(command -v "$cmd" || true)"
  [[ -n "$src" ]] && ln -sf "$src" "$hid/$cmd"
done
cp "$TMP/bin/runner" "$hid/runner"
cp "$TMP/bin/gh" "$hid/gh"
rm -rf "$DUMP"
mkdir -p "$DUMP"
set +e
PATH="$hid" FAKE_DUMP="$DUMP" FACTORY_WORKSPACE="$WS" FACTORY_OWNER=acme FACTORY_RUNNER=runner FACTORY_HARNESS=claude \
  "$FACTORY" lead --issue 7 --repo widgets >"$TMP/nout" 2>"$TMP/nerr"
ncode=$?
set -e
[[ $ncode -eq 0 ]] || fail "missing sqlite3 should not fail lead, exit $ncode err=$(cat "$TMP/nerr")"
[[ -f "$DUMP/ran" ]] || fail "missing sqlite3 should still run lead"
grep -q "dispatch factory.sh floor" "$TMP/nout" || fail "missing sqlite3 should still start floor: $(cat "$TMP/nout")"
grep -q "a person merges" "$TMP/nout" || fail "missing sqlite3 floor should still merge: $(cat "$TMP/nout") err=$(cat "$TMP/nerr")"
nwarns="$(grep -c "factory.db\|factory memory\|sqlite3" "$TMP/nerr" || true)"
[[ "$nwarns" -ge 1 ]] || fail "missing sqlite3 should warn, got $nwarns: $(cat "$TMP/nerr")"

echo "ok lead"
