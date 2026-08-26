#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FACTORY="$ROOT/factory.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export FACTORY_MEMORY_DB="$TMP/memory/factory.db"
unset FACTORY_OWNER
unset FACTORY_RUNNER

fail() { echo "FAIL: $*" >&2; exit 1; }

WS="$TMP/widgets"
mkdir -p "$WS"
git -C "$WS" init -q
git -C "$WS" remote add origin "https://github.com/acme/widgets.git"

DUMP="$TMP/dump"
mkdir -p "$DUMP" "$TMP/bin"
cat > "$TMP/bin/runner" << 'EOF'
#!/usr/bin/env bash
dump="${FAKE_DUMP:?}"
: > "$dump/ran"
exit 0
EOF
chmod +x "$TMP/bin/runner"

PATH="$TMP/bin:$PATH" FAKE_DUMP="$DUMP" FACTORY_WORKSPACE="$WS" FACTORY_RUNNER=runner FACTORY_HARNESS=claude \
  "$FACTORY" feature --issue 12 >"$TMP/out" 2>"$TMP/err"
[[ -f "$DUMP/ran" ]] || fail "should infer owner/repo from origin and run, err=$(cat "$TMP/err")"
grep -q "Need --owner" "$TMP/err" && fail "should not demand FACTORY_OWNER when origin is github: $(cat "$TMP/err")"
grep -q "Need --repo" "$TMP/err" && fail "should not demand --repo when origin is github: $(cat "$TMP/err")"

echo "ok infer"
