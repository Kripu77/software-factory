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
  grep -q "$pat" "$ROOT/$file" || fail "$file missing /$pat/"
}

WS="$TMP/workspace"
mkdir -p "$WS/widgets"
git -C "$WS/widgets" init -q
git -C "$WS/widgets" remote add origin "https://github.com/acme/widgets.git"

DUMP="$TMP/dump"
mkdir -p "$DUMP" "$TMP/bin"

cat > "$TMP/bin/grok" << 'EOF'
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
fi
if [[ -n "${GROK_MEM_STATUS:-}" ]]; then
  "${FACTORY_SH:?}" mem write --lane bug --status "$GROK_MEM_STATUS" --harness grok --issue 5 --project acme/widgets --summary "${GROK_SUMMARY:-Lane finished}" --evidence "${GROK_EVIDENCE:-https://github.com/acme/widgets/issues/5}" >/dev/null
fi
exit "${GROK_EXIT:-0}"
EOF
chmod +x "$TMP/bin/grok"

run_bug() {
  PATH="$TMP/bin:$PATH" \
    FAKE_DUMP="$DUMP" \
    FACTORY_SH="$FACTORY" \
    FACTORY_WORKSPACE="$WS" \
    FACTORY_OWNER=acme \
    FACTORY_RUNNER=grok \
    "$FACTORY" bug --repo widgets --issue 5
}

status_for() {
  sqlite3 "$FACTORY_MEMORY_DB" "SELECT status FROM runs WHERE issue = '5' AND lane = 'bug' ORDER BY id DESC LIMIT 1;"
}

count_runs() {
  sqlite3 "$FACTORY_MEMORY_DB" "SELECT COUNT(*) FROM runs WHERE issue = '5' AND lane = 'bug';"
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
need_text commands/bug.md "mem read"
need_text commands/bug.md "mem write"
need_text commands/bug.md "started"
need_text commands/bug.md "done"
need_text commands/bug.md "blocked"
need_text commands/bug.md "failed"
need_text commands/bug.md "warn once"

# Missing DB: warn once, lane still succeeds, started is written
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
[[ -f "$FACTORY_MEMORY_DB" ]] || fail "started write should create db"
[[ "$(status_for)" == "done" ]] || fail "successful lane should finish done, got $(status_for)"
[[ "$(cat "$DUMP/status-at-start")" == "started" ]] || fail "started should be written before the runner: $(cat "$DUMP/status-at-start")"

# Second run sees the first in context
rm -rf "$DUMP"
mkdir -p "$DUMP"
run_bug >"$TMP/out2" 2>"$TMP/err2"
grep -q "acme/widgets" "$DUMP/prompt" || fail "second run should see prior memory: $(cat "$DUMP/prompt")"
grep -q "status = done" "$DUMP/prompt" || fail "second run should see first run status: $(cat "$DUMP/prompt")"

# Agent can write blocked; factory does not overwrite with done
rm -rf "$DUMP" "$TMP/memory"
mkdir -p "$DUMP"
GROK_MEM_STATUS=blocked GROK_SUMMARY="Need a human login" run_bug >"$TMP/bout" 2>"$TMP/berr"
[[ "$(status_for)" == "blocked" ]] || fail "blocked outcome should stick, got $(status_for)"
[[ "$(count_runs)" == "1" ]] || fail "blocked should finish the started row, count=$(count_runs)"

# Agent can write failed
rm -rf "$DUMP" "$TMP/memory"
mkdir -p "$DUMP"
set +e
GROK_MEM_STATUS=failed GROK_SUMMARY="Tests did not pass" GROK_EXIT=1 run_bug >"$TMP/fout" 2>"$TMP/ferr"
fcode=$?
set -e
[[ $fcode -ne 0 ]] || fail "failed runner should fail the lane"
[[ "$(status_for)" == "failed" ]] || fail "failed outcome should stick, got $(status_for)"

# sqlite3 missing: warn once, lane still succeeds
hid="$TMP/nosqlite"
mkdir -p "$hid"
for cmd in bash mkdir date sed git grep dirname cat rm mktemp printf; do
  src="$(command -v "$cmd" || true)"
  [[ -n "$src" ]] && ln -sf "$src" "$hid/$cmd"
done
cp "$TMP/bin/grok" "$hid/grok"
rm -rf "$DUMP" "$TMP/memory"
mkdir -p "$DUMP"
set +e
PATH="$hid" FAKE_DUMP="$DUMP" FACTORY_SH="$FACTORY" FACTORY_WORKSPACE="$WS" FACTORY_OWNER=acme FACTORY_RUNNER=grok \
  "$FACTORY" bug --repo widgets --issue 5 >"$TMP/nout" 2>"$TMP/nerr"
ncode=$?
set -e
[[ $ncode -eq 0 ]] || fail "missing sqlite3 should not fail the lane, exit $ncode err=$(cat "$TMP/nerr")"
[[ -f "$DUMP/ran" ]] || fail "missing sqlite3 should still run the bug lane"
nwarns="$(grep -c "factory.db\|factory memory\|sqlite3" "$TMP/nerr" || true)"
[[ "$nwarns" == "1" ]] || fail "missing sqlite3 should warn once, got $nwarns: $(cat "$TMP/nerr")"

echo "ok bug"
