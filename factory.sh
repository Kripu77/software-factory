#!/usr/bin/env bash
set -euo pipefail

FACTORY="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE="${FACTORY_WORKSPACE:-$PWD}"
OWNER="${FACTORY_OWNER:-}"
RUNNER="${FACTORY_RUNNER:-}"

usage() {
  cat <<EOF
Usage:
  factory.sh feature|bug|docs --repo <name> --issue <n> [--owner org] [--runner grok|claude|codex] [--yes]
  factory.sh review|ci        --repo <name> --pr <n>     [--owner org] [--runner ...] [--yes]
  factory.sh ship             --repo <name> --issue <n> --pr <n> [--yes]
  factory.sh lead             --issue <n> [--repo <name>] [--yes]
  factory.sh telemetry        --question "<what broke>" [--yes]

Never merges. A person merges.
FACTORY_WORKSPACE, FACTORY_OWNER, FACTORY_RUNNER can be set instead of flags.
EOF
  exit 1
}

detect_runner() {
  if [[ -n "$RUNNER" ]]; then
    return
  fi
  if command -v grok >/dev/null 2>&1; then RUNNER=grok; return; fi
  if command -v claude >/dev/null 2>&1; then RUNNER=claude; return; fi
  if command -v codex >/dev/null 2>&1; then RUNNER=codex; return; fi
  echo "No runner. Install grok, claude, or codex, or set FACTORY_RUNNER." >&2
  exit 1
}

LANE="${1:-}"
[[ -n "$LANE" ]] || usage
shift || usage
REPO=""
ISSUE=""
PR=""
QUESTION=""
YES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --issue) ISSUE="${2:-}"; shift 2 ;;
    --pr) PR="${2:-}"; shift 2 ;;
    --owner) OWNER="${2:-}"; shift 2 ;;
    --runner) RUNNER="${2:-}"; shift 2 ;;
    --question) QUESTION="${2:-}"; shift 2 ;;
    --yes) YES=1; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1" >&2; usage ;;
  esac
done

detect_runner

need_owner() { [[ -n "$OWNER" ]] || { echo "Need --owner or FACTORY_OWNER" >&2; exit 1; }; }
need_issue() { [[ -n "$ISSUE" ]] || { echo "Need --issue <n>" >&2; exit 1; }; }
need_pr() { [[ -n "$PR" ]] || { echo "Need --pr <n>" >&2; exit 1; }; }
need_question() { [[ -n "$QUESTION" ]] || { echo "Need --question" >&2; exit 1; }; }

repo_dir() {
  [[ -n "$REPO" ]] || { echo "Need --repo <name>" >&2; exit 1; }
  if [[ -d "$WORKSPACE/$REPO/.git" ]]; then
    printf '%s\n' "$WORKSPACE/$REPO"
  elif [[ -d "$WORKSPACE/.git" ]]; then
    printf '%s\n' "$WORKSPACE"
  else
    echo "No git checkout for $REPO under $WORKSPACE" >&2
    exit 1
  fi
}

run_agent() {
  local cwd="$1"
  local rules="$2"
  local prompt="$3"
  case "$RUNNER" in
    grok)
      local extra=(--no-auto-update --no-alt-screen)
      [[ "$YES" -eq 1 ]] && extra+=(--always-approve)
      ( cd "$cwd" && grok "${extra[@]}" --rules "$rules" -p "$prompt" )
      ;;
    claude)
      local extra=(-p --append-system-prompt "$rules")
      [[ "$YES" -eq 1 ]] && extra+=(--dangerously-skip-permissions)
      ( cd "$cwd" && claude "${extra[@]}" "$prompt" )
      ;;
    codex)
      local extra=(exec)
      [[ "$YES" -eq 1 ]] && extra+=(--full-auto)
      ( cd "$cwd" && codex "${extra[@]}" "$prompt"$'\n\n'"$rules" )
      ;;
    *)
      echo "Unknown runner: $RUNNER (grok|claude|codex)" >&2
      exit 1
      ;;
  esac
}

HARD='Never merge. Never gh pr merge. Never git commit --no-verify. Never read .env or .env.local. Only the given ticket or PR. New branch off main. Do not wreck other local branches. PR title Type/<issue.number>/<short description> with Type in Feat Bug Arch Chore Refactor General. Description human, at most 3 sentences. Read CONTEXT-MAP.md, CONTEXT.md, ADRs, docs/agents before exploring. Missing CONTEXT.md: continue silently.'

YESFLAG=()
if [[ "$YES" -eq 1 ]]; then
  YESFLAG=(--yes)
fi

issue_url() {
  need_owner
  local r="${2:-$REPO}"
  [[ -n "$r" ]] || r="$OWNER"
  printf 'https://github.com/%s/%s/issues/%s\n' "$OWNER" "$r" "$1"
}

pr_url() {
  need_owner
  printf 'https://github.com/%s/%s/pull/%s\n' "$OWNER" "$REPO" "$1"
}

case "$LANE" in
  feature|bug|docs)
    need_issue
    DIR="$(repo_dir)"
    run_agent "$DIR" "$(cat "$FACTORY/lanes/${LANE}.md")"$'\n'"$HARD"       "Implement GitHub issue $(issue_url "$ISSUE") in the ${REPO} checkout. Open a PR against main. Print the PR URL. Do not merge."
    ;;
  review)
    need_pr
    DIR="$(repo_dir)"
    run_agent "$DIR" "$(cat "$FACTORY/lanes/review.md")"$'\n'"$HARD"       "Review $(pr_url "$PR") only. Use /thermo-nuclear-review. Do not implement. Do not merge."
    ;;
  ci)
    need_pr
    need_owner
    DIR="$(repo_dir)"
    command -v gh >/dev/null 2>&1 || { echo "gh not installed" >&2; exit 1; }
    echo "Checks before:"
    gh pr checks "$PR" -R "${OWNER}/${REPO}" || true
    run_agent "$DIR" "$(cat "$FACTORY/lanes/ci.md")"$'\n'"$HARD"       "Watch $(pr_url "$PR") with gh pr checks until green. Fix failures on this branch. Do not merge."
    echo "Checks after:"
    gh pr checks "$PR" -R "${OWNER}/${REPO}" || true
    ;;
  ship)
    need_issue
    "$0" feature --repo "$REPO" --issue "$ISSUE" --owner "$OWNER" --runner "$RUNNER" "${YESFLAG[@]}"
    if [[ -z "$PR" ]]; then
      echo "Implement finished. Pass --pr <n> to continue into review+CI."
      exit 0
    fi
    "$0" review --repo "$REPO" --pr "$PR" --owner "$OWNER" --runner "$RUNNER" "${YESFLAG[@]}"
    "$0" ci --repo "$REPO" --pr "$PR" --owner "$OWNER" --runner "$RUNNER" "${YESFLAG[@]}"
    echo "Ship lane done. A person merges. $(pr_url "$PR")"
    ;;
  lead|tech-lead|cto)
    need_issue
    run_agent "$WORKSPACE" "$(cat "$FACTORY/lanes/tech-lead.md")"$'\n'"$HARD"       "Ticket or update work for issue ${ISSUE}. Follow /to-tickets. Owning repo: ${REPO:-unknown}. Owner: ${OWNER:-unknown}."
    ;;
  telemetry)
    need_question
    run_agent "$WORKSPACE" "$(cat "$FACTORY/lanes/telemetry.md")"$'\n'"$HARD"$'\n'"$(cat "$FACTORY/telemetry/CONTRACT.md")"       "Answer this with evidence only: ${QUESTION}. Name the adapter you used. Do not implement product code. Do not merge."
    ;;
  *)
    usage
    ;;
esac
