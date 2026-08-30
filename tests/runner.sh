#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FACTORY="$ROOT/factory.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export FACTORY_MEMORY_DB="$TMP/memory/factory.db"

fail() { echo "FAIL: $*" >&2; exit 1; }

if grep -R --exclude='runner.sh' -n 'bin/grok\|FACTORY_RUNNER=grok\|GROK_' "$ROOT/tests"; then
  fail "tests still stub a grok binary or GROK_* env as the factory runner"
fi
if grep -n 'if command -v grok' "$FACTORY"; then
  fail "detect_runner must not prefer grok"
fi
grep -q "claude|codex|grok" "$FACTORY" || fail "usage should list claude, codex, grok without a preferred first"
grep -q "slash-command door" "$FACTORY" || fail "cursor --runner should be rejected in detect_runner"
grep -q "FACTORY_RUNNER" "$ROOT/README.md" || fail "README should tell people to set FACTORY_RUNNER when more than one CLI is installed"
grep -q "slash-command" "$ROOT/README.md" || fail "README should say Cursor is a slash-command door"

BIN="$TMP/bin"
mkdir -p "$BIN"
for cmd in bash mkdir date sed git grep dirname cat rm mktemp printf sqlite3 ln; do
  src="$(command -v "$cmd" || true)"
  [[ -n "$src" ]] && ln -sf "$src" "$BIN/$cmd"
done

stub() {
  local name="$1"
  cat > "$BIN/$name" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$BIN/$name"
}

cat > "$BIN/gh" << 'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "issue view")
    printf '%s\n' 'id=1'
    printf '%s\n' 'title=Add widgets list'
    printf '%s\n' 'url=https://github.com/acme/widgets/issues/1'
    printf '%s\n' 'status=open'
    printf '%s\n' 'labels=enhancement,ready-for-agent'
    printf '%s\n' 'body:'
    printf '%s\n' 'Ship a list of widgets.'
    ;;
esac
exit 0
EOF
chmod +x "$BIN/gh"

# No worker CLI
set +e
PATH="$BIN" FACTORY_RUNNER= "$FACTORY" feature --repo widgets --issue 1 >"$TMP/out" 2>"$TMP/err"
code=$?
set -e
[[ $code -ne 0 ]] || fail "no runner should fail"
grep -qi "No runner" "$TMP/err" || fail "no runner message: $(cat "$TMP/err")"

# Two CLIs: must not pick grok
stub grok
stub claude
set +e
PATH="$BIN" FACTORY_RUNNER= "$FACTORY" feature --repo widgets --issue 1 >"$TMP/out2" 2>"$TMP/err2"
code=$?
set -e
[[ $code -ne 0 ]] || fail "two runners should fail without FACTORY_RUNNER"
grep -qi "Multiple runners" "$TMP/err2" || fail "two runners message: $(cat "$TMP/err2")"

# Cursor is not a factory.sh runner
set +e
PATH="$BIN" FACTORY_RUNNER=cursor "$FACTORY" feature --repo widgets --issue 1 >"$TMP/out3" 2>"$TMP/err3"
code=$?
set -e
[[ $code -ne 0 ]] || fail "cursor --runner should fail"
grep -qi "slash-command" "$TMP/err3" || fail "cursor message: $(cat "$TMP/err3")"

# Only claude on PATH: use it
rm -f "$BIN/grok" "$BIN/codex"
WS="$TMP/workspace"
mkdir -p "$WS/widgets"
git -C "$WS/widgets" init -q
git -C "$WS/widgets" remote add origin "https://github.com/acme/widgets.git"
DUMP="$TMP/dump"
mkdir -p "$DUMP"
cat > "$BIN/claude" << 'EOF'
#!/usr/bin/env bash
dump="${FAKE_DUMP:?}"
: > "$dump/ran"
exit 0
EOF
chmod +x "$BIN/claude"
PATH="$BIN" FAKE_DUMP="$DUMP" FACTORY_WORKSPACE="$WS" FACTORY_OWNER=acme FACTORY_RUNNER= \
  "$FACTORY" feature --repo widgets --issue 1 >"$TMP/out4" 2>"$TMP/err4"
[[ -f "$DUMP/ran" ]] || fail "sole claude on PATH should be used, err=$(cat "$TMP/err4")"

# Explicit generic runner
cat > "$BIN/runner" << 'EOF'
#!/usr/bin/env bash
dump="${FAKE_DUMP:?}"
: > "$dump/generic"
exit 0
EOF
chmod +x "$BIN/runner"
rm -rf "$DUMP" "$TMP/memory"
mkdir -p "$DUMP"
PATH="$BIN" FAKE_DUMP="$DUMP" FACTORY_WORKSPACE="$WS" FACTORY_OWNER=acme FACTORY_RUNNER=runner \
  "$FACTORY" feature --repo widgets --issue 1 >"$TMP/out5" 2>"$TMP/err5"
[[ -f "$DUMP/generic" ]] || fail "FACTORY_RUNNER=runner should invoke runner, err=$(cat "$TMP/err5")"
h="$(sqlite3 "$FACTORY_MEMORY_DB" "SELECT harness FROM runs ORDER BY id DESC LIMIT 1;" 2>/dev/null || true)"
[[ -z "$h" ]] || fail "unknown runner must not write a harness row, got $h"

rm -rf "$TMP/memory" "$DUMP"
mkdir -p "$DUMP"
PATH="$BIN" FAKE_DUMP="$DUMP" FACTORY_WORKSPACE="$WS" FACTORY_OWNER=acme FACTORY_RUNNER=runner FACTORY_HARNESS=grok \
  "$FACTORY" feature --repo widgets --issue 1 >"$TMP/out6" 2>"$TMP/err6"
h="$(sqlite3 "$FACTORY_MEMORY_DB" "SELECT harness FROM runs ORDER BY id DESC LIMIT 1;")"
[[ "$h" == "grok" ]] || fail "FACTORY_HARNESS=grok should record grok, got $h"

echo "ok runner"
