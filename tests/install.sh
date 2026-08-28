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
need_text README.md "FACTORY_RUNNER"
need_text README.md "slash-command"
need_text AGENTS.md "attribute"
need_text AGENTS.md ".env"
need_text AGENTS.md "Never merge"
need_text AGENTS.md "recently-merged example"
need_text factory.sh "recently-merged example"
need_text skills/implement/SKILL.md "recently-merged example"
need_text rules/factory.mdc "attribute"
need_text rules/factory.mdc ".env"
need_text factory.sh "mem read"
need_text factory.sh "mem write"
need_text README.md "/lead"
need_text README.md "~/.local/bin"
need_text README.md "git remote"
need_text README.md "AGENTS.md"

if grep -qi poteto "$ROOT/AGENTS.md" "$ROOT/README.md" "$ROOT/install.sh"; then
  fail "poteto-mode is not a factory skill"
fi
[[ ! -e "$ROOT/skills/poteto-mode" ]] || fail "skills/poteto-mode should not exist"
[[ ! -e "$ROOT/commands/poteto-mode.md" ]] || fail "commands/poteto-mode.md should not exist"
[[ ! -e "$ROOT/playbooks" ]] || fail "playbooks/ is not part of this pack"
if grep -qi gstack "$ROOT/skills/browser-use/SKILL.md"; then
  fail "browser-use must not name other products"
fi
while IFS= read -r skill; do
  [[ -f "$ROOT/skills/$skill/SKILL.md" ]] || fail "install.sh links missing skill $skill"
done < <(sed -n 's/.*for skill in \(.*\); do/\1/p' "$ROOT/install.sh" | tr ' ' '\n')

hid="$TMP/bin"
mkdir -p "$hid"
for cmd in bash mkdir ln rm echo grep command cat cp; do
  src="$(command -v "$cmd" || true)"
  [[ -n "$src" ]] && ln -sf "$src" "$hid/$cmd"
done

HOME="$TMP" PATH="$hid" "$ROOT/install.sh" >"$TMP/out" 2>"$TMP/err" || fail "install exit $? err=$(cat "$TMP/err")"
[[ -d "$TMP/.factory/memory" ]] || fail "install should create ~/.factory/memory"
[[ -L "$TMP/.local/bin/factory" ]] || fail "install should put factory on ~/.local/bin"
[[ "$(readlink "$TMP/.local/bin/factory")" == "$ROOT/factory.sh" ]] || fail "factory symlink should point at factory.sh"
grep -q "memory " "$TMP/out" || fail "install should mention memory: $(cat "$TMP/out")"
grep -qi "lead" "$TMP/out" || fail "install should tell you to /lead: $(cat "$TMP/out")"
[[ ! -e "$TMP/.claude-mem" ]] || fail "install must not create other plugin dirs"
[[ ! -e "$TMP/.cursor-mem" ]] || fail "install must not create other plugin dirs"

prod="$TMP/product"
mkdir -p "$prod"
HOME="$TMP" PATH="$hid" "$ROOT/install.sh" "$prod" >"$TMP/out2" 2>"$TMP/err2" || fail "install with checkout exit $? err=$(cat "$TMP/err2")"
[[ -f "$prod/AGENTS.md" ]] || fail "install.sh <checkout> should write AGENTS.md"
grep -q "Software factory" "$prod/AGENTS.md" || fail "AGENTS.md should be the factory house rules"

echo "ok install"
