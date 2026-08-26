#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FACTORY="$ROOT/factory.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export FACTORY_MEMORY_DB="$TMP/memory/factory.db"
unset FACTORY_RUNNER

fail() { echo "FAIL: $*" >&2; exit 1; }

grep -q "factory.sh floor" "$FACTORY" || fail "usage should list floor"
if grep -q "Ship lane done" "$FACTORY"; then
  fail "ship should be an alias of floor, not the old chain"
fi
fn="$(awk '/^floor_run\(\)/{on=1} on{print} on && /^}$/{exit}' "$FACTORY")"
echo "$fn" | grep -q run_agent && fail "floor must not call run_agent"
grep -q "gh pr list" "$FACTORY" || fail "PR capture should use gh pr list, not runner stdout"

WS="$TMP/workspace"
mkdir -p "$WS/widgets"
git -C "$WS/widgets" init -q
git -C "$WS/widgets" remote add origin "https://github.com/acme/widgets.git"

DUMP="$TMP/dump"
mkdir -p "$DUMP" "$TMP/bin"

cat > "$TMP/bin/grok" << 'EOF'
#!/usr/bin/env bash
dump="${FAKE_DUMP:?}"
: > "$dump/after-feature"
printf 'grok\n' >> "$dump/dispatched"
exit "${GROK_EXIT:-0}"
EOF
chmod +x "$TMP/bin/grok"

cat > "$TMP/bin/gh" << 'EOF'
#!/usr/bin/env bash
dump="${FAKE_DUMP:?}"
printf '%s\n' "$*" >> "$dump/gh"
case "$1 $2" in
  "issue view")
    printf '%s\n' '{"labels":[{"name":"ready-for-agent"},{"name":"enhancement"}]}'
    ;;
  "pr list")
    if [[ -f "$dump/after-feature" ]]; then
      printf '%s\n' $'40\tFeat/12/widgets'
    fi
    ;;
  "pr checks")
    exit "${GH_CHECKS:-0}"
    ;;
  "pr view")
    printf '%s\n' '40'
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
    FACTORY_RUNNER=grok \
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
pr="$(sqlite3 "$FACTORY_MEMORY_DB" "SELECT pr FROM runs WHERE issue = '12' AND pr IS NOT NULL AND pr != '' ORDER BY id DESC LIMIT 1;")"
[[ "$pr" == "40" ]] || fail "memory should have pr=40 after feature, got $pr"

# Blocked implement stops. No review or CI.
rm -rf "$DUMP" "$TMP/memory"
mkdir -p "$DUMP"
GROK_EXIT=1 run_floor >"$TMP/bout" 2>"$TMP/berr" || true
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
PATH="$TMP/bin:$PATH" FAKE_DUMP="$DUMP" FACTORY_WORKSPACE="$WS" FACTORY_OWNER=acme FACTORY_RUNNER=grok \
  "$FACTORY" ship --repo widgets --issue 12 >"$TMP/sout" 2>"$TMP/serr"
grep -q "a person merges" "$TMP/sout" || fail "ship should run the floor: $(cat "$TMP/sout")"

echo "ok floor"
