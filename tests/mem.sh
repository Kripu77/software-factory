#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FACTORY="$ROOT/factory.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export FACTORY_MEMORY_DB="$TMP/memory/factory.db"
unset FACTORY_RUNNER

fail() { echo "FAIL: $*" >&2; exit 1; }

write() {
  "$FACTORY" mem write --harness grok --project test/repo "$@"
}

# Missing database: mem read warns and exits 0
set +e
"$FACTORY" mem read --issue 4 >"$TMP/out" 2>"$TMP/err"
code=$?
set -e
[[ $code -eq 0 ]] || fail "missing db read exit $code"
[[ ! -s "$TMP/out" ]] || fail "missing db read should be silent on stdout"
grep -q "factory.db" "$TMP/err" || fail "missing db should warn with path"

# Write creates dir, WAL, schema_versions, runs
write --lane feature --status started --issue 4 --summary "Add the factory memory store" --next-steps "Read it back" --evidence "https://github.com/Kripu77/software-factory/issues/4" >"$TMP/w1"
[[ -f "$FACTORY_MEMORY_DB" ]] || fail "write did not create db"
grep -q 'id=1' "$TMP/w1" || fail "write should print id=1, got $(cat "$TMP/w1")"
grep -q 'status=started' "$TMP/w1" || fail "write should print status=started"

mode="$(sqlite3 "$FACTORY_MEMORY_DB" "PRAGMA journal_mode;")"
[[ "$mode" == "wal" ]] || fail "journal_mode=$mode want wal"
sqlite3 "$FACTORY_MEMORY_DB" "SELECT version FROM schema_versions WHERE version = 1;" | grep -q 1 || fail "schema_versions missing version 1"
cols="$(sqlite3 "$FACTORY_MEMORY_DB" "SELECT sql FROM sqlite_master WHERE name = 'runs';")"
printf '%s' "$cols" | grep -q "harness" || fail "runs table missing"

# Round-trip read
"$FACTORY" mem read --issue 4 >"$TMP/r1"
grep -q "harness = grok" "$TMP/r1" || fail "read missing harness: $(cat "$TMP/r1")"
grep -q "lane = feature" "$TMP/r1" || fail "read missing lane"
grep -q "project = test/repo" "$TMP/r1" || fail "read missing project"
grep -q "issue = 4" "$TMP/r1" || fail "read missing issue"
grep -q "status = started" "$TMP/r1" || fail "read missing status"
grep -q "Add the factory memory store" "$TMP/r1" || fail "read missing summary"
grep -q "Read it back" "$TMP/r1" || fail "read missing next_steps"
grep -q "software-factory/issues/4" "$TMP/r1" || fail "read missing evidence"

# done updates the open run for issue+lane
write --lane feature --status done --issue 4 --summary "Opened the memory PR" --next-steps "Review then CI" --evidence "https://github.com/Kripu77/software-factory/pull/99" >"$TMP/w2"
grep -q 'id=1' "$TMP/w2" || fail "done should finish id=1, got $(cat "$TMP/w2")"
grep -q 'status=done' "$TMP/w2" || fail "done should print status=done"
count="$(sqlite3 "$FACTORY_MEMORY_DB" "SELECT COUNT(*) FROM runs;")"
[[ "$count" == "1" ]] || fail "done should update not insert, count=$count"
"$FACTORY" mem read --issue 4 >"$TMP/r2"
grep -q "status = done" "$TMP/r2" || fail "read after done: $(cat "$TMP/r2")"
grep -q "Opened the memory PR" "$TMP/r2" || fail "updated summary missing"
grep -q "completed_at = 2" "$TMP/r2" || fail "completed_at should be set"

# done with no open run inserts
write --lane feature --status done --issue 4 --summary "Second finish with no open run" >"$TMP/w3"
grep -q 'id=2' "$TMP/w3" || fail "no-open done should insert, got $(cat "$TMP/w3")"
count="$(sqlite3 "$FACTORY_MEMORY_DB" "SELECT COUNT(*) FROM runs;")"
[[ "$count" == "2" ]] || fail "expected 2 runs, count=$count"

# newest first
"$FACTORY" mem read --issue 4 >"$TMP/r3"
awk '/^ *id = /{print $3; exit}' "$TMP/r3" | grep -q 2 || fail "newest id should be first: $(cat "$TMP/r3")"

# --project filter, default limit 10
i=0
while [[ $i -lt 11 ]]; do
  i=$((i + 1))
  write --lane bug --status started --issue 7 --project other/repo --summary "other $i" >/dev/null
done
"$FACTORY" mem read --project other/repo >"$TMP/r4"
n="$(grep -c '^ *id = ' "$TMP/r4" || true)"
[[ "$n" == "10" ]] || fail "default limit 10, got $n"
"$FACTORY" mem read --project other/repo --limit 2 >"$TMP/r5"
n="$(grep -c '^ *id = ' "$TMP/r5" || true)"
[[ "$n" == "2" ]] || fail "limit 2, got $n"
"$FACTORY" mem read --issue 4 >"$TMP/r6"
grep -q "other/repo" "$TMP/r6" && fail "--issue 4 should not include other/repo"
grep -q "test/repo" "$TMP/r6" || fail "--issue 4 lost test/repo"

echo "ok mem"
