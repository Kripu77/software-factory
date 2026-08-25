#!/usr/bin/env bash
set -euo pipefail

FACTORY="$(cd "$(dirname "$0")" && pwd)"

link_skills() {
  local dest_root="$1"
  [[ -n "$dest_root" ]] || return 0
  mkdir -p "$dest_root"
  local skill dest
  for skill in tdd implement deslop to-tickets thermo-nuclear-review loop-on-ci; do
    dest="$dest_root/factory-${skill}"
    rm -rf "$dest"
    ln -s "$FACTORY/skills/${skill}" "$dest"
    echo "linked $dest"
  done
}

echo "Factory: $FACTORY"

if [[ -d "${HOME}/.grok" ]] || command -v grok >/dev/null 2>&1; then
  link_skills "${HOME}/.grok/skills"
fi
if [[ -d "${HOME}/.claude" ]] || command -v claude >/dev/null 2>&1; then
  link_skills "${HOME}/.claude/skills"
fi

WORKSPACE="${FACTORY_WORKSPACE:-}"
if [[ -n "$WORKSPACE" && -d "$WORKSPACE" ]]; then
  target="$WORKSPACE/AGENTS.md"
  if [[ -f "$target" ]] && grep -q "Software factory" "$target"; then
    echo "keep $target"
  elif [[ -f "$target" ]]; then
    {
      echo ""
      echo "## Software factory"
      echo ""
      cat "$FACTORY/AGENTS.md"
    } >> "$target"
    echo "append $target"
  else
    cp "$FACTORY/AGENTS.md" "$target"
    echo "wrote $target"
  fi
else
  echo "Set FACTORY_WORKSPACE to drop AGENTS.md into a product checkout."
fi

echo
echo "Set FACTORY_OWNER, FACTORY_WORKSPACE, FACTORY_RUNNER=grok|claude|codex"
echo "Then: $FACTORY/factory.sh feature --repo <name> --issue N"
