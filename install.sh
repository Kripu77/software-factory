#!/usr/bin/env bash
set -euo pipefail

FACTORY="$(cd "$(dirname "$0")" && pwd)"

link_skills() {
  local dest_root="$1"
  local label="$2"
  mkdir -p "$dest_root"
  local skill dest
  for skill in tdd implement unslop to-tickets thermo-nuclear-review loop-on-ci poteto-mode run-smoke-tests browser-use; do
    dest="$dest_root/factory-${skill}"
    rm -rf "$dest"
    ln -s "$FACTORY/skills/${skill}" "$dest"
    echo "linked $label $dest"
  done
}

echo "Factory: $FACTORY"

mkdir -p "${HOME}/.factory/memory"
echo "memory ${HOME}/.factory/memory"

bindir="${HOME}/.local/bin"
mkdir -p "$bindir"
ln -sfn "$FACTORY/factory.sh" "$bindir/factory"
echo "cli $bindir/factory"

# Grok Build plugin (skills + commands). Copies into ~/.grok/installed-plugins.
if command -v grok >/dev/null 2>&1; then
  if grok plugin list 2>/dev/null | grep -q "software-factory"; then
    grok plugin update software-factory
    echo "updated grok plugin software-factory"
  elif grok plugin install "$FACTORY" --trust; then
    echo "installed grok plugin software-factory"
  else
    echo "grok plugin install failed" >&2
  fi
  link_skills "${HOME}/.grok/skills" "grok"
elif [[ -d "${HOME}/.grok" ]]; then
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
fi

echo
echo "Next: cd into the product repo, open grok (or claude), /lead"
echo "Owner and repo come from git remote. Workspace is that directory."
case ":${PATH}:" in
  *":${HOME}/.local/bin:"*) ;;
  *) echo "Put ${HOME}/.local/bin on PATH so \`factory lead\` works." ;;
esac
echo "If more than one of claude, codex, grok is on PATH, set FACTORY_RUNNER."
