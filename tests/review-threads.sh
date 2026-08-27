#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

fail() { echo "FAIL: $*" >&2; exit 1; }

need_text() {
  local file="$1" pat="$2"
  grep -q -- "$pat" "$ROOT/$file" || fail "$file missing /$pat/"
}

need_text skills/implement/SKILL.md "resolveReviewThread"
need_text skills/implement/SKILL.md "reviewThreads"
need_text skills/implement/SKILL.md "unresolved"
need_text skills/implement/SKILL.md "addPullRequestReviewThreadReply"

echo "ok review-threads"
