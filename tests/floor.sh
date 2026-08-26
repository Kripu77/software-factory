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

grep -q "factory.sh floor" "$FACTORY" || fail "usage should list floor"
if grep -q "Ship lane done" "$FACTORY"; then
  fail "ship should be an alias of floor, not the old chain"
fi
fn="$(awk '/^floor_run\(\)/{on=1} on{print} on && /^}$/{exit}' "$FACTORY")"
echo "$fn" | grep -q run_agent && fail "floor must not call run_agent"
grep -q "gh pr view" "$FACTORY" || fail "PR capture should use gh pr view, not runner stdout"
if grep -q '*\[Bb\]ug\*' "$FACTORY"; then
  fail "classify must not glob raw JSON for bug"
fi
grep -q -- "--template" "$FACTORY" || fail "classify and pr view should use gh --template"

WS="$TMP/workspace"
mkdir -p "$WS/widgets"
git -C "$WS/widgets" init -q
git -C "$WS/widgets" remote add origin "https://github.com/acme/widgets.git"

DUMP="$TMP/dump"
mkdir -p "$DUMP" "$TMP/bin"

cat > "$TMP/bin/runner" << 'EOF'
#!/usr/bin/env bash
dump="${FAKE_DUMP:?}"
: > "$dump/after-feature"
printf 'grok\n' >> "$dump/dispatched"
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
      if [[ "$n" -ge 2 ]]; then printf '%s\n' 1; else printf '%s\n' 0; fi
    else
      if [[ -f "$dump/after-feature" ]]; then printf '%s\n' 40; fi
    fi
    ;;
  "pr checks")
    if [[ "$n" -ge 3 ]]; then exit 0; else exit 1; fi
    ;;
esac
exit 0
EOF
chmod +x "$TMP/bin/gh"

run_floor() {
  PATH="$TMP/bin:$PATH" \
    FAKE_DUMP="$DUMP" \
    FACTORY_SH="$FACTORY" \
    FACTORY_WORKSPACE="$WS" \
    FACTORY_OWNER=acme \
    FACTORY_RUNNER=runner FACTORY_HARNESS=claude \
    "$FACTORY" floor --repo widgets --issue 12 "$@"
}

# Feature → Review → CI, PR captured, person merges
rm -rf "$DUMP" "$TMP/memory"
mkdir -p "$DUMP"
run_floor >"$TMP/out" 2>"$TMP/err"
grep -q "dispatch feature" "$TMP/out" || fail "floor should dispatch feature: $(cat "$TMP/out")"
grep -q "dispatch review" "$TMP/out" || fail "floor should dispatch review: $(cat "$TMP/out")"
grep -q "dispatch ci" "$TMP/out" || fail "floor should dispatch ci: $(cat "$TMP/out")"
if grep -q "dispatch qa" "$TMP/out"; then
  fail "no QA URL should skip qa process: $(cat "$TMP/out")"
fi
grep -q "a person merges" "$TMP/out" || fail "floor should stop at human merge: $(cat "$TMP/out")"
grep -q "pull/40" "$TMP/out" || fail "merge line should include PR URL: $(cat "$TMP/out")"
pr="$(sqlite3 "$FACTORY_MEMORY_DB" "SELECT pr FROM runs WHERE issue = '12' AND lane = 'feature' ORDER BY id DESC LIMIT 1;")"
[[ "$pr" == "40" ]] || fail "memory should have pr=40 after feature, got $pr"
fcount="$(sqlite3 "$FACTORY_MEMORY_DB" "SELECT COUNT(*) FROM runs WHERE issue = '12' AND lane = 'feature';")"
[[ "$fcount" == "1" ]] || fail "pr should land on the feature run, not a second row, count=$fcount"

# Blocked implement stops. No review or CI.
rm -rf "$DUMP" "$TMP/memory"
mkdir -p "$DUMP"
AGENT_EXIT=1 run_floor >"$TMP/bout" 2>"$TMP/berr" || true
grep -q "dispatch feature" "$TMP/bout" || fail "blocked path should still dispatch feature"
if grep -q "dispatch review" "$TMP/bout"; then
  fail "blocked must not dispatch review: $(cat "$TMP/bout")"
fi
if grep -q "dispatch ci" "$TMP/bout"; then
  fail "blocked must not dispatch ci: $(cat "$TMP/bout")"
fi
grep -q "blocked\|failed" "$TMP/bout" || fail "blocked path should stop: $(cat "$TMP/bout")"
if grep -q "a person merges" "$TMP/bout"; then
  fail "blocked must not ask a person to merge: $(cat "$TMP/bout")"
fi

# ship is floor
rm -rf "$DUMP" "$TMP/memory"
mkdir -p "$DUMP"
PATH="$TMP/bin:$PATH" FAKE_DUMP="$DUMP" FACTORY_WORKSPACE="$WS" FACTORY_OWNER=acme FACTORY_RUNNER=runner FACTORY_HARNESS=claude \
  "$FACTORY" ship --repo widgets --issue 12 >"$TMP/sout" 2>"$TMP/serr"
grep -q "a person merges" "$TMP/sout" || fail "ship should run the floor: $(cat "$TMP/sout")"

# Missing sqlite: GitHub still drives Feature → Review → CI
hid="$TMP/nosqlite"
mkdir -p "$hid"
for cmd in bash mkdir date sed git grep dirname cat rm mktemp printf tr wc; do
  src="$(command -v "$cmd" || true)"
  [[ -n "$src" ]] && ln -sf "$src" "$hid/$cmd"
done
cp "$TMP/bin/runner" "$hid/runner"
cp "$TMP/bin/gh" "$hid/gh"
rm -rf "$DUMP" "$TMP/memory"
mkdir -p "$DUMP"
PATH="$hid" FAKE_DUMP="$DUMP" FACTORY_WORKSPACE="$WS" FACTORY_OWNER=acme FACTORY_RUNNER=runner FACTORY_HARNESS=claude \
  "$FACTORY" floor --repo widgets --issue 12 >"$TMP/nout" 2>"$TMP/nerr"
grep -q "dispatch feature" "$TMP/nout" || fail "no-sqlite should dispatch feature: $(cat "$TMP/nout")"
grep -q "dispatch review" "$TMP/nout" || fail "no-sqlite should dispatch review: $(cat "$TMP/nout")"
grep -q "dispatch ci" "$TMP/nout" || fail "no-sqlite should dispatch ci: $(cat "$TMP/nout")"
grep -q "a person merges" "$TMP/nout" || fail "no-sqlite should still merge from GitHub: $(cat "$TMP/nout") err=$(cat "$TMP/nerr")"

echo "ok floor"
