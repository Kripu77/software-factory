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

DUMP="$TMP/dump"
mkdir -p "$DUMP" "$TMP/bin" "$TMP/workspace"

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
EOF
chmod +x "$TMP/bin/grok"

run_lead() {
  PATH="$TMP/bin:$PATH" \
    FAKE_DUMP="$DUMP" \
    FACTORY_WORKSPACE="$TMP/workspace" \
    FACTORY_OWNER=acme \
    FACTORY_RUNNER=grok \
    "$FACTORY" lead --issue 7 --repo widgets
}

# Lane and /lead command read memory, still dispatch, still do not implement
need_text lanes/tech-lead.md "mem read"
need_text lanes/tech-lead.md "hint"
need_text lanes/tech-lead.md "Do not implement"
need_text lanes/tech-lead.md "Dispatch"
need_text lanes/tech-lead.md "Do not let a lane chain"
need_text commands/lead.md "mem read"
need_text commands/lead.md "Do not implement"

# Missing DB: warn once, lead still runs, no write
rm -rf "$DUMP" "$TMP/memory"
mkdir -p "$DUMP"
set +e
run_lead >"$TMP/out" 2>"$TMP/err"
code=$?
set -e
[[ $code -eq 0 ]] || fail "missing db lead exit $code err=$(cat "$TMP/err")"
[[ -f "$DUMP/ran" ]] || fail "missing db should still run lead"
warns="$(grep -c "factory.db\|factory memory" "$TMP/err" || true)"
[[ "$warns" == "1" ]] || fail "missing db should warn once, got $warns: $(cat "$TMP/err")"
[[ ! -f "$FACTORY_MEMORY_DB" ]] || fail "lead must not create memory on read"

# Rows for the issue are in the prompt. Lead does not write a run.
"$FACTORY" mem write --harness grok --project acme/widgets --lane feature --status done --issue 7 --pr 40 --summary "Add widgets list" --next-steps "QA the PR" --evidence "https://github.com/acme/widgets/pull/40" >/dev/null
before="$(sqlite3 "$FACTORY_MEMORY_DB" "SELECT COUNT(*) FROM runs;")"
rm -rf "$DUMP"
mkdir -p "$DUMP"
run_lead >"$TMP/out2" 2>"$TMP/err2"
[[ -f "$DUMP/ran" ]] || fail "lead with rows should run"
grep -q "acme/widgets" "$DUMP/prompt" || fail "lead prompt missing project: $(cat "$DUMP/prompt")"
grep -q "status = done" "$DUMP/prompt" || fail "lead prompt missing status: $(cat "$DUMP/prompt")"
grep -q "Add widgets list" "$DUMP/prompt" || fail "lead prompt missing summary: $(cat "$DUMP/prompt")"
grep -q "QA the PR" "$DUMP/prompt" || fail "lead prompt missing next_steps: $(cat "$DUMP/prompt")"
after="$(sqlite3 "$FACTORY_MEMORY_DB" "SELECT COUNT(*) FROM runs;")"
[[ "$before" == "$after" ]] || fail "lead must not write runs, before=$before after=$after"

# sqlite3 missing: warn once, lead still succeeds
hid="$TMP/nosqlite"
mkdir -p "$hid"
for cmd in bash mkdir date sed git grep dirname cat rm mktemp printf; do
  src="$(command -v "$cmd" || true)"
  [[ -n "$src" ]] && ln -sf "$src" "$hid/$cmd"
done
cp "$TMP/bin/grok" "$hid/grok"
rm -rf "$DUMP"
mkdir -p "$DUMP"
set +e
PATH="$hid" FAKE_DUMP="$DUMP" FACTORY_WORKSPACE="$TMP/workspace" FACTORY_OWNER=acme FACTORY_RUNNER=grok \
  "$FACTORY" lead --issue 7 --repo widgets >"$TMP/nout" 2>"$TMP/nerr"
ncode=$?
set -e
[[ $ncode -eq 0 ]] || fail "missing sqlite3 should not fail lead, exit $ncode err=$(cat "$TMP/nerr")"
[[ -f "$DUMP/ran" ]] || fail "missing sqlite3 should still run lead"
nwarns="$(grep -c "factory.db\|factory memory\|sqlite3" "$TMP/nerr" || true)"
[[ "$nwarns" == "1" ]] || fail "missing sqlite3 should warn once, got $nwarns: $(cat "$TMP/nerr")"

echo "ok lead"
