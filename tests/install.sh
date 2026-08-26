#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

need_text() {
  local file="$1" pat="$2"
  grep -q -- "$pat" "$ROOT/$file" || fail "$file missing /$pat/"
}

need_text README.md "factory.db"
grep -qi -- "best-effort" "$ROOT/README.md" || fail "README.md missing /best-effort/"
need_text README.md "Handoff"
need_text README.md "factory.sh floor"
need_text README.md "/lead"
need_text README.md "public ledger"
need_text README.md "hint"
need_text AGENTS.md "attribute"
need_text AGENTS.md ".env"
need_text AGENTS.md "Never merge"
need_text rules/factory.mdc "attribute"
need_text rules/factory.mdc ".env"
need_text factory.sh "mem read"
need_text factory.sh "mem write"

hid="$TMP/bin"
mkdir -p "$hid"
for cmd in bash mkdir ln rm echo grep command cat; do
  src="$(command -v "$cmd" || true)"
  [[ -n "$src" ]] && ln -sf "$src" "$hid/$cmd"
done

HOME="$TMP" PATH="$hid" "$ROOT/install.sh" >"$TMP/out" 2>"$TMP/err" || fail "install exit $? err=$(cat "$TMP/err")"
[[ -d "$TMP/.factory/memory" ]] || fail "install should create ~/.factory/memory"
grep -q "memory " "$TMP/out" || fail "install should mention memory: $(cat "$TMP/out")"
[[ ! -e "$TMP/.claude-mem" ]] || fail "install must not create other plugin dirs"
[[ ! -e "$TMP/.cursor-mem" ]] || fail "install must not create other plugin dirs"

echo "ok install"
