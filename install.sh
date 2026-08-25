#!/usr/bin/env bash
set -euo pipefail

FACTORY="$(cd "$(dirname "$0")" && pwd)"

link_skills() {
  local dest_root="$1"
  local label="$2"
  mkdir -p "$dest_root"
  local skill dest
  for skill in tdd implement deslop to-tickets thermo-nuclear-review loop-on-ci; do
    dest="$dest_root/factory-${skill}"
    rm -rf "$dest"
    ln -s "$FACTORY/skills/${skill}" "$dest"
    echo "linked $label $dest"
  done
}

echo "Factory: $FACTORY"

# Grok Build CLI
if [[ -d "${HOME}/.grok" ]] || command -v grok >/dev/null 2>&1; then
  link_skills "${HOME}/.grok/skills" "grok"
fi

# Claude Code
if [[ -d "${HOME}/.claude" ]] || command -v claude >/dev/null 2>&1; then
  link_skills "${HOME}/.claude/skills" "claude"
  mkdir -p "${HOME}/.claude/commands"
  for cmd in "$FACTORY"/commands/*.md; do
    ln -sfn "$cmd" "${HOME}/.claude/commands/$(basename "$cmd")"
    echo "linked claude command $(basename "$cmd")"
  done
fi

# Codex
if [[ -d "${HOME}/.codex" ]] || command -v codex >/dev/null 2>&1; then
  link_skills "${HOME}/.codex/skills" "codex"
fi

# Cursor: local plugin (this repo)
if [[ -d "${HOME}/.cursor" ]]; then
  mkdir -p "${HOME}/.cursor/plugins/local"
  dest="${HOME}/.cursor/plugins/local/software-factory"
  rm -rf "$dest"
  ln -s "$FACTORY" "$dest"
  echo "linked cursor plugin $dest"
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
  echo "Set FACTORY_WORKSPACE to drop AGENTS.md into a product checkout (Codex and friends read it there)."
fi

echo
echo "Cursor:  /feature /bug /review /ci /telemetry /lead"
echo "Claude:  same slash commands after restart"
echo "Grok:    grok, then /tdd /implement or paste a ticket"
echo "Codex:   AGENTS.md in the checkout"
echo "CI door: $FACTORY/factory.sh feature --repo <name> --issue N"
