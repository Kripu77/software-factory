#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
tag="${1:-}"
sha="${2:-}"
[[ -n "$tag" && -n "$sha" ]] || {
  echo "usage: ship-grok-catalog.sh vX.Y.Z SHA" >&2
  exit 1
}

token="${XAI_MARKETPLACE_TOKEN:-}"
if [[ -z "$token" ]]; then
  echo "A person stores XAI_MARKETPLACE_TOKEN in this repo's GitHub Actions secrets for the xAI catalog PR." >&2
  exit 1
fi

export GH_TOKEN="$token"
export GH_PROMPT_DISABLED=1

repo="${XAI_MARKETPLACE_REPO:-xai-org/plugin-marketplace}"
branch="software-factory"
if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
  plugin_url="https://github.com/${GITHUB_REPOSITORY}.git"
else
  plugin_url="https://github.com/Kripu77/software-factory.git"
fi

catalog="${XAI_MARKETPLACE_DIR:-}"
if [[ -z "$catalog" ]]; then
  login="$(gh api user --jq .login)"
  gh repo fork "$repo" --clone=false --default-branch-only >/dev/null
  catalog="$(mktemp -d)"
  gh repo clone "${login}/plugin-marketplace" "$catalog" -- --depth 1
  git -C "$catalog" remote add upstream "https://github.com/${repo}.git" 2>/dev/null || true
  git -C "$catalog" fetch -q upstream main
  git -C "$catalog" checkout -B "$branch" upstream/main
else
  login="$(gh api user --jq .login)"
  git -C "$catalog" checkout -B "$branch"
fi

market="$catalog/.grok-plugin/marketplace.json"
[[ -f "$market" ]] || {
  echo "missing $market" >&2
  exit 1
}

existed="$(python3 -c 'import json,sys; print("yes" if any(p.get("name")=="software-factory" for p in json.load(open(sys.argv[1])).get("plugins",[])) else "no")' "$market")"

python3 "$ROOT/scripts/pin-grok-catalog.py" "$market" "$sha" "$plugin_url"

if [[ -f "$catalog/scripts/generate-plugin-index.py" ]]; then
  (cd "$catalog" && python3 scripts/generate-plugin-index.py)
fi

if ! git -C "$catalog" config user.email >/dev/null; then
  git -C "$catalog" config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  git -C "$catalog" config user.name "github-actions[bot]"
fi

git -C "$catalog" add -- .grok-plugin/marketplace.json
if [[ -f "$catalog/.grok-plugin/plugin-index.json" ]]; then
  git -C "$catalog" add -- .grok-plugin/plugin-index.json
fi

if git -C "$catalog" diff --cached --quiet; then
  echo "catalog already pinned to $sha"
  exit 0
fi

if [[ "$existed" == "yes" ]]; then
  title="Bump software-factory SHA for ${tag}"
  msg="Bump software-factory to ${tag} (${sha})."
else
  title="Add software-factory"
  msg="Add software-factory at ${tag} (${sha})."
fi

git -C "$catalog" commit -q -m "$msg"
git -C "$catalog" push --force-with-lease -u origin "$branch"

open_count="$(gh pr list --repo "$repo" --head "${login}:${branch}" --state open --json number --jq 'length')"
if [[ "${open_count:-0}" != "0" ]]; then
  echo "updated open catalog PR for ${tag}"
  exit 0
fi

body="Pin software-factory to ${tag} commit ${sha}, not main. Do not merge from this workflow."
gh pr create --repo "$repo" --head "${login}:${branch}" --base main --title "$title" --body "$body"
