#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FACTORY="$ROOT/factory.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export FACTORY_MEMORY_DB="$TMP/memory/factory.db"
unset FACTORY_RUNNER
unset FACTORY_SKIP_TICKET_COMMENT
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"

fail() { echo "FAIL: $*" >&2; exit 1; }

write() {
  "$FACTORY" mem write --harness grok --project test/repo "$@"
}

stored_project() {
  sqlite3 "$FACTORY_MEMORY_DB" "SELECT project FROM runs ORDER BY id DESC LIMIT 1;"
}

write_from_origin() {
  local url="$1"
  local gitdir="$TMP/origin"
  rm -rf "$gitdir"
  mkdir -p "$gitdir"
  git -C "$gitdir" init -q
  git -C "$gitdir" remote add origin "$url"
  unset FACTORY_OWNER
  FACTORY_WORKSPACE="$gitdir" "$FACTORY" mem write --harness grok --lane feature --status started --issue 80 --summary "Detect project from origin" >"$TMP/pw"
}

reject_write() {
  local why="$1"
  shift
  set +e
  write "$@" >"$TMP/out" 2>"$TMP/err"
  code=$?
  set -e
  [[ $code -ne 0 ]] || fail "should reject $why: $(cat "$TMP/out") $(cat "$TMP/err")"
}

reject_global() {
  local flag="$1"
  set +e
  "$FACTORY" feature "$flag" x >"$TMP/out" 2>"$TMP/err"
  code=$?
  set -e
  [[ $code -ne 0 ]] || fail "global parser accepted $flag"
  grep -q "Unknown arg: $flag" "$TMP/err" || fail "global parser still accepts $flag: $(cat "$TMP/err")"
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
grep -Eq "completed_at = 20[0-9]{2}-" "$TMP/r2" || fail "completed_at should be set"

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

write_from_origin "https://github.com/acme/widgets.git"
[[ "$(stored_project)" == "acme/widgets" ]] || fail "https remote: $(stored_project)"

write_from_origin "git@github.com:acme/widgets.git"
[[ "$(stored_project)" == "acme/widgets" ]] || fail "git@ remote: $(stored_project)"

write_from_origin "ssh://git@github.com/acme/widgets.git"
[[ "$(stored_project)" == "acme/widgets" ]] || fail "ssh remote: $(stored_project)"

write_from_origin "https://user:token@github.com/acme/widgets.git"
[[ "$(stored_project)" == "acme/widgets" ]] || fail "credential remote stored $(stored_project)"
[[ "$(stored_project)" != *token* ]] || fail "credential leaked in project"
dump="$(sqlite3 "$FACTORY_MEMORY_DB" .dump)"
printf '%s' "$dump" | grep -q "user:token" && fail "credential leaked into db dump"

write --lane docs --status started --issue 81 --project "https://user:token@github.com/acme/widgets.git" --summary "Project flag is a remote url" >/dev/null
[[ "$(stored_project)" == "acme/widgets" ]] || fail "--project url stored $(stored_project)"

empty="$TMP/noremote"
mkdir -p "$empty"
set +e
(
  cd "$empty"
  unset FACTORY_OWNER
  unset FACTORY_WORKSPACE
  "$FACTORY" mem write --harness grok --lane feature --status started --issue 80 --summary "No project"
) >"$TMP/out" 2>"$TMP/err"
code=$?
set -e
[[ $code -ne 0 ]] || fail "missing project should fail"
grep -q "Need --project" "$TMP/err" || fail "missing project message: $(cat "$TMP/err")"

reject_write "multi-sentence summary" --lane feature --status started --issue 90 --summary "First sentence. Second sentence."
grep -q "one-sentence" "$TMP/err" || fail "multi-sentence message: $(cat "$TMP/err")"
count="$(sqlite3 "$FACTORY_MEMORY_DB" "SELECT COUNT(*) FROM runs WHERE issue = '90';")"
[[ "$count" == "0" ]] || fail "rejected write still persisted, count=$count"

reject_write "newline summary" --lane feature --status started --issue 90 --summary $'Two\nlines'
count="$(sqlite3 "$FACTORY_MEMORY_DB" "SELECT COUNT(*) FROM runs WHERE issue = '90';")"
[[ "$count" == "0" ]] || fail "newline summary persisted"

reject_write "prose evidence" --lane feature --status started --issue 90 --summary "Add a store" --evidence "dumped the response body here"
grep -q "evidence" "$TMP/err" || fail "non path evidence message: $(cat "$TMP/err")"

reject_write "secret evidence" --lane feature --status started --issue 90 --summary "Add a store" --evidence "password=supersecret"
grep -qi "secret" "$TMP/err" || fail "secret evidence message: $(cat "$TMP/err")"

pem="-----BEGIN"
pem="${pem} PRIVATE KEY-----"
reject_write "pem evidence" --lane feature --status started --issue 90 --summary "Add a store" --evidence "$pem"

tok="ghp_"
tok="${tok}notarealgithubtokenvalue"
reject_write "token evidence" --lane feature --status started --issue 90 --summary "Add a store" --evidence "$tok"

reject_write "secret summary" --lane feature --status started --issue 90 --summary "token=abc123"

write --lane feature --status started --issue 91 --summary "It's a one-sentence summary" --evidence "/tmp/factory-evidence.txt" >"$TMP/q1"
grep -q 'id=' "$TMP/q1" || fail "quoted summary should write"
"$FACTORY" mem read --issue 91 >"$TMP/qr"
grep -q "It's a one-sentence summary" "$TMP/qr" || fail "quoted summary round-trip: $(cat "$TMP/qr")"
grep -q "/tmp/factory-evidence.txt" "$TMP/qr" || fail "path evidence missing"

write --lane feature --status done --issue 94 --summary "Lift the pull URL" --evidence "https://github.com/acme/widgets/pull/40" >"$TMP/p1"
pr="$(sqlite3 "$FACTORY_MEMORY_DB" "SELECT pr FROM runs WHERE issue = '94';")"
[[ "$pr" == "40" ]] || fail "pull evidence should set pr, got $pr"

write --lane docs --status done --issue 95 --summary "Lift JSON pull" --evidence '["https://github.com/acme/widgets/pull/41"]' >"$TMP/p2"
pr="$(sqlite3 "$FACTORY_MEMORY_DB" "SELECT pr FROM runs WHERE issue = '95';")"
[[ "$pr" == "41" ]] || fail "JSON pull evidence should set pr, got $pr"

write --lane feature --status done --issue 96 --pr 7 --summary "Keep the given PR" --evidence "https://github.com/acme/widgets/pull/40" >"$TMP/p3"
pr="$(sqlite3 "$FACTORY_MEMORY_DB" "SELECT pr FROM runs WHERE issue = '96';")"
[[ "$pr" == "7" ]] || fail "explicit --pr should win, got $pr"

write --lane feature --status done --issue 97 --summary "First finish with an issue URL" --evidence "https://github.com/acme/widgets/issues/97" >/dev/null
write --lane feature --status done --issue 97 --summary "Second finish with pull evidence" --evidence "https://github.com/acme/widgets/pull/40" >"$TMP/p4"
count="$(sqlite3 "$FACTORY_MEMORY_DB" "SELECT COUNT(*) FROM runs WHERE issue = '97';")"
[[ "$count" == "2" ]] || fail "no-open done with pull evidence should insert, count=$count got $(cat "$TMP/p4")"
latest="$(sqlite3 "$FACTORY_MEMORY_DB" "SELECT summary, pr FROM runs WHERE issue = '97' ORDER BY id DESC LIMIT 1;")"
[[ "$latest" == "Second finish with pull evidence|40" ]] || fail "second finish should keep its summary and pr, got $latest"
first="$(sqlite3 "$FACTORY_MEMORY_DB" "SELECT summary, IFNULL(pr,'') FROM runs WHERE issue = '97' ORDER BY id ASC LIMIT 1;")"
[[ "$first" == "First finish with an issue URL|" ]] || fail "first finish should stay, got $first"
write --lane feature --status done --issue 98 --summary "First finish without a pr" >/dev/null
write --lane feature --status done --issue 98 --pr 12 --summary "Second finish with explicit pr" >"$TMP/p5"
count="$(sqlite3 "$FACTORY_MEMORY_DB" "SELECT COUNT(*) FROM runs WHERE issue = '98';")"
[[ "$count" == "2" ]] || fail "no-open done with --pr should insert, count=$count got $(cat "$TMP/p5")"
latest="$(sqlite3 "$FACTORY_MEMORY_DB" "SELECT summary, pr FROM runs WHERE issue = '98' ORDER BY id DESC LIMIT 1;")"
[[ "$latest" == "Second finish with explicit pr|12" ]] || fail "explicit --pr finish should insert, got $latest"

write --lane bug --status blocked --issue 92 --summary "Need a repro URL" --next-steps "Wait on telemetry" --evidence "https://example.com/repro" >"$TMP/b1"
grep -q 'status=blocked' "$TMP/b1" || fail "blocked write: $(cat "$TMP/b1")"
write --lane bug --status failed --issue 93 --summary "Tests did not pass" --evidence "./tests/mem.sh" >"$TMP/f1"
grep -q 'status=failed' "$TMP/f1" || fail "failed write: $(cat "$TMP/f1")"
"$FACTORY" mem read --issue 92 >"$TMP/br"
grep -q "status = blocked" "$TMP/br" || fail "blocked read: $(cat "$TMP/br")"
"$FACTORY" mem read --issue 93 >"$TMP/fr"
grep -q "status = failed" "$TMP/fr" || fail "failed read: $(cat "$TMP/fr")"

write --lane ci --status started --issue 40 --summary "Hold the db lock" >/dev/null
rm -f "$TMP/locked"
python3 -c "
import sqlite3, time
c = sqlite3.connect('$FACTORY_MEMORY_DB', isolation_level=None, timeout=5)
c.execute('BEGIN EXCLUSIVE')
open('$TMP/locked', 'w').write('1')
time.sleep(1.2)
c.execute('COMMIT')
c.close()
" &
locker=$!
i=0
while [[ $i -lt 20 && ! -f "$TMP/locked" ]]; do
  i=$((i + 1))
  sleep 0.05
done
[[ -f "$TMP/locked" ]] || fail "lock holder did not start"
set +e
write --lane ci --status done --issue 40 --summary "Finish under lock" >"$TMP/lockout" 2>"$TMP/lockerr"
lockcode=$?
set -e
wait "$locker" || true
[[ $lockcode -eq 0 ]] || fail "finish while locked should wait, exit $lockcode err=$(cat "$TMP/lockerr")"
grep -q 'status=done' "$TMP/lockout" || fail "finish under lock: $(cat "$TMP/lockout")"
started="$(sqlite3 "$FACTORY_MEMORY_DB" "SELECT COUNT(*) FROM runs WHERE issue = '40' AND status = 'started';")"
[[ "$started" == "0" ]] || fail "started row still open after finish, count=$started"

reject_global --harness
reject_global --status
reject_global --summary
reject_global --next-steps
reject_global --evidence
reject_global --limit
reject_global --project
reject_global --lane

write --lane docs --status started --issue 41 --summary "Mem flags still parse" --harness grok >/dev/null
"$FACTORY" mem read --issue 41 --limit 1 >"$TMP/mf"
grep -q "lane = docs" "$TMP/mf" || fail "mem flags should still parse: $(cat "$TMP/mf")"

hid="$TMP/nosqlite"
mkdir -p "$hid"
for cmd in bash mkdir date sed git grep dirname; do
  src="$(command -v "$cmd" || true)"
  [[ -n "$src" ]] && ln -sf "$src" "$hid/$cmd"
done
set +e
PATH="$hid" "$FACTORY" mem write --harness grok --project test/repo --lane feature --status started --issue 42 --summary "Missing sqlite" >"$TMP/out" 2>"$TMP/err"
code=$?
set -e
[[ $code -ne 0 ]] || fail "missing sqlite3 should fail"
grep -q "sqlite3 not installed" "$TMP/err" || fail "missing sqlite3 message: $(cat "$TMP/err")"

echo "ok mem"
