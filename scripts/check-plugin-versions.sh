#!/usr/bin/env bash
set -euo pipefail

tag="${1:-}"
root="${2:-$(cd "$(dirname "$0")/.." && pwd)}"
[[ -n "$tag" ]] || { echo "usage: check-plugin-versions.sh vX.Y.Z [root]" >&2; exit 1; }
want="${tag#v}"

plugin_version() {
  awk -F'"' '/"version"/ { print $4; exit }' "$1"
}

for f in .claude-plugin/plugin.json .cursor-plugin/plugin.json .grok-plugin/plugin.json; do
  path="$root/$f"
  [[ -f "$path" ]] || { echo "missing $f" >&2; exit 1; }
  got="$(plugin_version "$path")"
  [[ "$got" == "$want" ]] || { echo "$f version $got does not match $tag" >&2; exit 1; }
done
