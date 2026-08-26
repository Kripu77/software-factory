#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FACTORY="$ROOT/factory.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export FACTORY_MEMORY_DB="$TMP/memory/factory.db"
unset FACTORY_RUNNER

fail() { echo "FAIL: $*" >&2; exit 1; }

need_text() {
  local file="$1" pat="$2"
  grep -q -- "$pat" "$ROOT/$file" || fail "$file missing /$pat/"
}

bytes_under() {
  local file="$1" max="$2" n
  n="$(wc -c < "$ROOT/$file" | tr -d ' ')"
  [[ "$n" -lt "$max" ]] || fail "$file is $n bytes, stay under $max"
}

fn_body() {
  local name="$1"
  awk -v n="$name" '
    $0 ~ "^" n "\\(\\)" {on=1}
    on {print}
    on && /^}$/ {exit}
  ' "$ROOT/factory.sh"
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
    -p) printf '%s\n' "$2" > "$dump/prompt"; shift 2 ;;
    --rules) printf '%s\n' "$2" > "$dump/rules"; shift 2 ;;
    *) shift ;;
  esac
done
: > "$dump/ran"
if command -v sqlite3 >/dev/null 2>&1 && [[ -f "${FACTORY_MEMORY_DB:-}" ]]; then
  sqlite3 "$FACTORY_MEMORY_DB" "SELECT status FROM runs WHERE lane = 'bug' ORDER BY id DESC LIMIT 1;" > "$dump/status-at-start" || true
else
  : > "$dump/status-at-start"
fi
if [[ -n "${AGENT_MEM_START:-}" ]]; then
  "${FACTORY_SH:?}" mem write --lane bug --status started --harness grok --issue 5 --project acme/widgets >/dev/null
fi
if [[ -n "${AGENT_MEM_STATUS:-}" ]]; then
  "${FACTORY_SH:?}" mem write --lane bug --status "$AGENT_MEM_STATUS" --harness grok --issue 5 --project acme/widgets --summary "${AGENT_SUMMARY:-Lane finished}" --evidence "${AGENT_EVIDENCE:-https://github.com/acme/widgets/issues/5}" --next-steps "${AGENT_NEXT:-Tech lead dispatches the next lane}" >/dev/null
fi
exit "${AGENT_EXIT:-0}"
EOF
chmod +x "$TMP/bin/runner"

run_bug() {
  PATH="$TMP/bin:$PATH" \
    FAKE_DUMP="$DUMP" \
    FACTORY_SH="$FACTORY" \
    FACTORY_WORKSPACE="$WS" \
    FACTORY_OWNER=acme \
    FACTORY_RUNNER=runner FACTORY_HARNESS=claude \
    "$FACTORY" bug --repo widgets --issue 5
}

status_for() {
  sqlite3 "$FACTORY_MEMORY_DB" "SELECT status FROM runs WHERE issue = '5' AND lane = 'bug' ORDER BY id DESC LIMIT 1;"
}

count_runs() {
  sqlite3 "$FACTORY_MEMORY_DB" "SELECT COUNT(*) FROM runs WHERE issue = '5' AND lane = 'bug';"
}

count_status() {
  sqlite3 "$FACTORY_MEMORY_DB" "SELECT COUNT(*) FROM runs WHERE issue = '5' AND lane = 'bug' AND status = '$1';"
}

field_for() {
  sqlite3 "$FACTORY_MEMORY_DB" "SELECT $1 FROM runs WHERE issue = '5' AND lane = 'bug' ORDER BY id DESC LIMIT 1;"
}

# Lane and /bug command wire mem read/write
need_text lanes/bug.md "mem read"
need_text lanes/bug.md "mem write"
need_text lanes/bug.md "started"
need_text lanes/bug.md "done"
need_text lanes/bug.md "blocked"
need_text lanes/bug.md "failed"
need_text lanes/bug.md "warn once"
need_text lanes/bug.md "Tech lead"
need_text lanes/bug.md "Do not dispatch"
need_text lanes/bug.md "in-progress"
need_text commands/bug.md "mem read"
need_text commands/bug.md "mem write"
need_text commands/bug.md "started"
need_text commands/bug.md "done"
need_text commands/bug.md "blocked"
need_text commands/bug.md "failed"
need_text commands/bug.md "warn once"
need_text commands/bug.md "in-progress"
need_text commands/bug.md "--harness"
need_text commands/bug.md "--summary"
need_text commands/bug.md "--evidence"
need_text commands/bug.md "--next-steps"
bytes_under lanes/bug.md 1000
bytes_under commands/bug.md 1000
grep -q -- "--summary" "$ROOT/lanes/bug.md" && fail "put mem flags in /bug or the injected prompt, not a second dump in the lane"

fn_body mem_read_context | grep -Eq 'lane_mem_write started|--status started' && fail "wrapper must not write started"
fn_body lane_mem_finish | grep -q sqlite3 && fail "lane_mem_finish must not call sqlite3"
fn_body lane_mem_finish | grep -q "mem read\|lane_mem_write\|mem write" || fail "lane_mem_finish must go through factory.sh mem"
if grep -Eq "bug_mem_start|bug_mem_finish|bug_mem_write|bug_latest_status" "$ROOT/factory.sh"; then
  fail "fold bug into run_mem_lane"
fi

# Missing DB: warn once, lane still succeeds, finish records done
rm -rf "$DUMP" "$TMP/memory"
mkdir -p "$DUMP"
set +e
run_bug >"$TMP/out" 2>"$TMP/err"
code=$?
set -e
[[ $code -eq 0 ]] || fail "missing db bug lane exit $code err=$(cat "$TMP/err")"
[[ -f "$DUMP/ran" ]] || fail "missing db should still run the bug lane"
warns="$(grep -c "factory.db\|factory memory" "$TMP/err" || true)"
[[ "$warns" == "1" ]] || fail "missing db should warn once, got $warns: $(cat "$TMP/err")"
[[ -f "$FACTORY_MEMORY_DB" ]] || fail "finish write should create db"
[[ "$(status_for)" == "done" ]] || fail "successful lane should finish done, got $(status_for)"
[[ ! -s "$DUMP/status-at-start" ]] || fail "wrapper should not write started before the runner: $(cat "$DUMP/status-at-start")"
[[ -n "$(field_for summary)" ]] || fail "terminal done missing summary"
[[ "$(field_for evidence)" != "[]" ]] || fail "terminal done missing evidence"
[[ -n "$(field_for next_steps)" ]] || fail "terminal done missing next_steps"

# Second run sees the first in context
rm -rf "$DUMP"
mkdir -p "$DUMP"
run_bug >"$TMP/out2" 2>"$TMP/err2"
grep -q "acme/widgets" "$DUMP/prompt" || fail "second run should see prior memory: $(cat "$DUMP/prompt")"
grep -q "status = done" "$DUMP/prompt" || fail "second run should see first run status: $(cat "$DUMP/prompt")"

# Fake runner writes started then blocked; one row, blocked, no extra done
rm -rf "$DUMP" "$TMP/memory"
mkdir -p "$DUMP"
AGENT_MEM_START=1 AGENT_MEM_STATUS=blocked AGENT_SUMMARY="Need a human login" run_bug >"$TMP/bout" 2>"$TMP/berr"
[[ "$(status_for)" == "blocked" ]] || fail "blocked outcome should stick, got $(status_for)"
[[ "$(count_runs)" == "1" ]] || fail "started then blocked should be one row, count=$(count_runs)"
[[ "$(count_status done)" == "0" ]] || fail "finish must not clobber blocked with done"
[[ "$(field_for summary)" == "Need a human login" ]] || fail "blocked summary overwritten: $(field_for summary)"

# Agent can write failed
rm -rf "$DUMP" "$TMP/memory"
mkdir -p "$DUMP"
set +e
AGENT_MEM_STATUS=failed AGENT_SUMMARY="Tests did not pass" AGENT_EXIT=1 run_bug >"$TMP/fout" 2>"$TMP/ferr"
fcode=$?
set -e
[[ $fcode -ne 0 ]] || fail "failed runner should fail the lane"
[[ "$(status_for)" == "failed" ]] || fail "failed outcome should stick, got $(status_for)"
[[ "$(count_runs)" == "1" ]] || fail "failed should be one row, count=$(count_runs)"

# sqlite3 missing: warn once, lane still succeeds
hid="$TMP/nosqlite"
mkdir -p "$hid"
for cmd in bash mkdir date sed git grep dirname cat rm mktemp printf; do
  src="$(command -v "$cmd" || true)"
  [[ -n "$src" ]] && ln -sf "$src" "$hid/$cmd"
done
cp "$TMP/bin/runner" "$hid/runner"
rm -rf "$DUMP" "$TMP/memory"
mkdir -p "$DUMP"
set +e
PATH="$hid" FAKE_DUMP="$DUMP" FACTORY_SH="$FACTORY" FACTORY_WORKSPACE="$WS" FACTORY_OWNER=acme FACTORY_RUNNER=runner FACTORY_HARNESS=claude \
  "$FACTORY" bug --repo widgets --issue 5 >"$TMP/nout" 2>"$TMP/nerr"
ncode=$?
set -e
[[ $ncode -eq 0 ]] || fail "missing sqlite3 should not fail the lane, exit $ncode err=$(cat "$TMP/nerr")"
[[ -f "$DUMP/ran" ]] || fail "missing sqlite3 should still run the bug lane"
nwarns="$(grep -c "factory.db\|factory memory\|sqlite3" "$TMP/nerr" || true)"
[[ "$nwarns" == "1" ]] || fail "missing sqlite3 should warn once, got $nwarns: $(cat "$TMP/nerr")"

echo "ok bug"
