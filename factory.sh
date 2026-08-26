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
  factory.sh qa               --repo <name> --pr <n> [--url <app>]
  factory.sh qa               --url <app>
  factory.sh mem read         [--issue <n>] [--project owner/name] [--limit n]
  factory.sh mem write        --lane <lane> --status started|done|blocked|failed [--harness grok|claude|codex|cursor] [--issue <n>] [--pr <n>] [--project owner/name] [--summary s] [--next-steps s] [--evidence url-or-json]

Never merges. A person merges.
FACTORY_WORKSPACE, FACTORY_OWNER, FACTORY_RUNNER can be set instead of flags.
Memory: FACTORY_MEMORY_DB (default ~/.factory/memory/factory.db).
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
MEM_CMD=""
REPO=""
ISSUE=""
PR=""
URL=""
QUESTION=""
YES=0
HARNESS=""
RUN_LANE=""
PROJECT=""
STATUS=""
SUMMARY=""
NEXT_STEPS=""
EVIDENCE=""
LIMIT=""

if [[ "$LANE" == "mem" ]]; then
  MEM_CMD="${1:-}"
  case "$MEM_CMD" in
    read|write) shift ;;
    *) usage ;;
  esac
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --issue) ISSUE="${2:-}"; shift 2 ;;
      --pr) PR="${2:-}"; shift 2 ;;
      --owner) OWNER="${2:-}"; shift 2 ;;
      --repo) REPO="${2:-}"; shift 2 ;;
      --runner|--harness) HARNESS="${2:-}"; shift 2 ;;
      --lane) RUN_LANE="${2:-}"; shift 2 ;;
      --project) PROJECT="${2:-}"; shift 2 ;;
      --status) STATUS="${2:-}"; shift 2 ;;
      --summary) SUMMARY="${2:-}"; shift 2 ;;
      --next-steps) NEXT_STEPS="${2:-}"; shift 2 ;;
      --evidence) EVIDENCE="${2:-}"; shift 2 ;;
      --limit) LIMIT="${2:-}"; shift 2 ;;
      -h|--help) usage ;;
      *) echo "Unknown arg: $1" >&2; usage ;;
    esac
  done
else
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo) REPO="${2:-}"; shift 2 ;;
      --issue) ISSUE="${2:-}"; shift 2 ;;
      --pr) PR="${2:-}"; shift 2 ;;
      --url) URL="${2:-}"; shift 2 ;;
      --owner) OWNER="${2:-}"; shift 2 ;;
      --runner) RUNNER="${2:-}"; shift 2 ;;
      --question) QUESTION="${2:-}"; shift 2 ;;
      --yes) YES=1; shift ;;
      -h|--help) usage ;;
      *) echo "Unknown arg: $1" >&2; usage ;;
    esac
  done
  detect_runner
fi

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

sql_quote() {
  local s="$1"
  s=${s//"'"/"''"}
  printf "'%s'" "$s"
}

sql_nullable() {
  if [[ -z "${1:-}" ]]; then
    printf 'NULL'
  else
    sql_quote "$1"
  fi
}

json_quote() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '"%s"' "$s"
}

memory_db() {
  printf '%s\n' "${FACTORY_MEMORY_DB:-$HOME/.factory/memory/factory.db}"
}

need_sqlite() {
  command -v sqlite3 >/dev/null 2>&1 || { echo "sqlite3 not installed" >&2; exit 1; }
}

memory_init() {
  local db
  db="$(memory_db)"
  mkdir -p "$(dirname "$db")"
  need_sqlite
  sqlite3 "$db" >/dev/null <<'SQL'
PRAGMA journal_mode=WAL;
PRAGMA busy_timeout=5000;
CREATE TABLE IF NOT EXISTS schema_versions (
  id INTEGER PRIMARY KEY,
  version INTEGER UNIQUE NOT NULL,
  applied_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS runs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  harness TEXT NOT NULL CHECK(harness IN ('claude', 'cursor', 'codex', 'grok')),
  lane TEXT NOT NULL,
  project TEXT NOT NULL,
  issue TEXT,
  pr TEXT,
  status TEXT NOT NULL CHECK(status IN ('started', 'done', 'blocked', 'failed')),
  summary TEXT,
  next_steps TEXT,
  evidence TEXT NOT NULL DEFAULT '[]',
  started_at TEXT NOT NULL,
  started_at_epoch INTEGER NOT NULL,
  completed_at TEXT,
  completed_at_epoch INTEGER
);
CREATE INDEX IF NOT EXISTS idx_runs_project_time ON runs(project, started_at_epoch DESC);
CREATE INDEX IF NOT EXISTS idx_runs_issue_time ON runs(issue, started_at_epoch DESC);
CREATE INDEX IF NOT EXISTS idx_runs_status ON runs(status);
INSERT OR IGNORE INTO schema_versions (version, applied_at)
VALUES (1, strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
SQL
}

sqlite_tx() {
  local db="$1"
  sqlite3 "$db" <<SQL
.output /dev/null
PRAGMA busy_timeout=5000;
.output stdout
BEGIN IMMEDIATE;
$2
COMMIT;
SQL
}

owner_name() {
  [[ "$1" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]
}

project_from_remote() {
  local raw="$1"
  local project
  [[ -n "$raw" ]] || { echo "Need --project owner/name" >&2; exit 1; }
  if owner_name "$raw"; then
    PROJECT="$raw"
    return
  fi
  project="$(printf '%s' "$raw" | sed -E -e 's#^[a-zA-Z0-9+.-]+://##' -e 's#^.*@##' -e 's#^[^:/]+(:[0-9]+)?[:/]##' -e 's#\.git$##' -e 's#/$##')"
  owner_name "$project" || { echo "Need --project owner/name" >&2; exit 1; }
  PROJECT="$project"
}

detect_project() {
  if [[ -z "${PROJECT:-}" ]]; then
    if [[ -n "$OWNER" && -n "$REPO" ]]; then
      PROJECT="$OWNER/$REPO"
    else
      local url=""
      url="$(git -C "$WORKSPACE" remote get-url origin 2>/dev/null || true)"
      if [[ -z "$url" ]]; then
        url="$(git remote get-url origin 2>/dev/null || true)"
      fi
      [[ -n "$url" ]] || { echo "Need --project owner/name" >&2; exit 1; }
      PROJECT="$url"
    fi
  fi
  project_from_remote "$PROJECT"
}

looks_like_secret() {
  local s="$1"
  case "$s" in
    *-----BEGIN*|*"BEGIN PEM"*|*ghp_*|*gho_*|*ghu_*|*ghs_*|*ghr_*|*github_pat_*|*xoxb-*|*xoxp-*|*xoxa-*|*xoxs-*|*sk-ant-*|*password=*|*token=*|*api_key=*|*secret=*) return 0 ;;
  esac
  if printf '%s' "$s" | grep -Eq 'AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9]{20,}'; then
    return 0
  fi
  return 1
}

is_url_or_path() {
  local s="$1"
  [[ -n "$s" ]] || return 1
  case "$s" in
    *$'\n'*|*$'\r'*|*' '*) return 1 ;;
  esac
  case "$s" in
    http://*|https://*|/*|./*|../*|*/*) return 0 ;;
  esac
  return 1
}

validate_summary() {
  [[ -n "${SUMMARY:-}" ]] || return 0
  looks_like_secret "$SUMMARY" && { echo "Refusing secret in mem write" >&2; exit 1; }
  [[ "$SUMMARY" != *$'\n'* && "$SUMMARY" != *$'\r'* ]] || { echo "Need one-sentence --summary" >&2; exit 1; }
  [[ ${#SUMMARY} -le 200 ]] || { echo "Need one-sentence --summary" >&2; exit 1; }
  case "$SUMMARY" in
    *'. '*|*'? '*|*'! '*) echo "Need one-sentence --summary" >&2; exit 1 ;;
  esac
}

validate_next_steps() {
  [[ -n "${NEXT_STEPS:-}" ]] || return 0
  looks_like_secret "$NEXT_STEPS" && { echo "Refusing secret in mem write" >&2; exit 1; }
  [[ "$NEXT_STEPS" != *$'\n'* && "$NEXT_STEPS" != *$'\r'* ]] || { echo "Need one-line --next-steps" >&2; exit 1; }
}

validate_evidence_items() {
  local remain="$1"
  local item
  remain="${remain#"${remain%%[![:space:]]*}"}"
  remain="${remain%"${remain##*[![:space:]]}"}"
  [[ -n "$remain" ]] || return 0
  while [[ -n "$remain" ]]; do
    remain="${remain#"${remain%%[![:space:]]*}"}"
    [[ "$remain" == \"* ]] || { echo "Need --evidence URL or path" >&2; exit 1; }
    remain="${remain#\"}"
    [[ "$remain" == *\"* ]] || { echo "Need --evidence URL or path" >&2; exit 1; }
    item="${remain%%\"*}"
    remain="${remain#*\"}"
    looks_like_secret "$item" && { echo "Refusing secret in mem write" >&2; exit 1; }
    is_url_or_path "$item" || { echo "Need --evidence URL or path" >&2; exit 1; }
    remain="${remain#"${remain%%[![:space:]]*}"}"
    if [[ "$remain" == ,* ]]; then
      remain="${remain#,}"
      continue
    fi
    [[ -z "$remain" ]] || { echo "Need --evidence URL or path" >&2; exit 1; }
  done
}

normalize_evidence() {
  if [[ -z "${EVIDENCE:-}" ]]; then
    EVIDENCE='[]'
    return
  fi
  looks_like_secret "$EVIDENCE" && { echo "Refusing secret in mem write" >&2; exit 1; }
  [[ "$EVIDENCE" != *$'\n'* && "$EVIDENCE" != *$'\r'* ]] || { echo "Need --evidence URL or path" >&2; exit 1; }
  if [[ "$EVIDENCE" == "[]" ]]; then
    return
  fi
  if [[ "$EVIDENCE" == \[* ]]; then
    [[ "$EVIDENCE" == *\] ]] || { echo "Need --evidence URL or path" >&2; exit 1; }
    local inner="${EVIDENCE#\[}"
    inner="${inner%\]}"
    validate_evidence_items "$inner"
    return
  fi
  is_url_or_path "$EVIDENCE" || { echo "Need --evidence URL or path" >&2; exit 1; }
  EVIDENCE="[$(json_quote "$EVIDENCE")]"
}

validate_payload() {
  validate_summary
  validate_next_steps
  normalize_evidence
}

mem_read() {
  local db where sql
  db="$(memory_db)"
  if [[ ! -f "$db" ]]; then
    echo "No factory memory yet at $db" >&2
    exit 0
  fi
  need_sqlite
  LIMIT="${LIMIT:-10}"
  [[ "$LIMIT" =~ ^[0-9]+$ ]] || { echo "Need --limit <n>" >&2; exit 1; }
  where=""
  if [[ -n "$ISSUE" ]]; then
    where="issue = $(sql_quote "$ISSUE")"
  fi
  if [[ -n "$PROJECT" ]]; then
    if [[ -n "$where" ]]; then
      where="$where AND project = $(sql_quote "$PROJECT")"
    else
      where="project = $(sql_quote "$PROJECT")"
    fi
  fi
  sql="SELECT id, harness, lane, project, issue, pr, status, summary, next_steps, evidence, started_at, completed_at FROM runs"
  if [[ -n "$where" ]]; then
    sql="$sql WHERE $where"
  fi
  sql="$sql ORDER BY started_at_epoch DESC, id DESC LIMIT $LIMIT"
  sqlite3 -line "$db" "$sql"
}

mem_write() {
  local db now epoch id completed_at completed_epoch sql
  [[ -n "${RUN_LANE:-}" ]] || { echo "Need --lane <lane>" >&2; exit 1; }
  case "${STATUS:-}" in
    started|done|blocked|failed) ;;
    *) echo "Need --status started|done|blocked|failed" >&2; exit 1 ;;
  esac
  HARNESS="${HARNESS:-$RUNNER}"
  case "$HARNESS" in
    claude|cursor|codex|grok) ;;
    *) echo "Need --harness claude|cursor|codex|grok" >&2; exit 1 ;;
  esac
  detect_project
  validate_payload
  memory_init
  db="$(memory_db)"
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  epoch="$(date +%s)"
  if [[ "$STATUS" != "started" && -n "$ISSUE" ]]; then
    sql="
UPDATE runs SET
  status = $(sql_quote "$STATUS"),
  summary = COALESCE($(sql_nullable "$SUMMARY"), summary),
  next_steps = COALESCE($(sql_nullable "$NEXT_STEPS"), next_steps),
  evidence = CASE WHEN $(sql_quote "$EVIDENCE") = '[]' THEN evidence ELSE $(sql_quote "$EVIDENCE") END,
  pr = COALESCE($(sql_nullable "$PR"), pr),
  completed_at = $(sql_quote "$now"),
  completed_at_epoch = $epoch
WHERE id = (
  SELECT id FROM runs
  WHERE issue = $(sql_quote "$ISSUE") AND lane = $(sql_quote "$RUN_LANE") AND status = 'started'
  ORDER BY started_at_epoch DESC, id DESC
  LIMIT 1
);
INSERT INTO runs (harness, lane, project, issue, pr, status, summary, next_steps, evidence, started_at, started_at_epoch, completed_at, completed_at_epoch)
SELECT $(sql_quote "$HARNESS"), $(sql_quote "$RUN_LANE"), $(sql_quote "$PROJECT"), $(sql_nullable "$ISSUE"), $(sql_nullable "$PR"), $(sql_quote "$STATUS"), $(sql_nullable "$SUMMARY"), $(sql_nullable "$NEXT_STEPS"), $(sql_quote "$EVIDENCE"), $(sql_quote "$now"), $epoch, $(sql_quote "$now"), $epoch
WHERE changes() = 0;
SELECT COALESCE(
  (SELECT last_insert_rowid() WHERE last_insert_rowid() != 0 AND changes() != 0),
  (SELECT id FROM runs WHERE issue = $(sql_quote "$ISSUE") AND lane = $(sql_quote "$RUN_LANE") AND completed_at_epoch = $epoch ORDER BY id DESC LIMIT 1)
);"
  else
    if [[ "$STATUS" == "started" ]]; then
      completed_at="NULL"
      completed_epoch="NULL"
    else
      completed_at="$(sql_quote "$now")"
      completed_epoch="$epoch"
    fi
    sql="
INSERT INTO runs (harness, lane, project, issue, pr, status, summary, next_steps, evidence, started_at, started_at_epoch, completed_at, completed_at_epoch)
VALUES ($(sql_quote "$HARNESS"), $(sql_quote "$RUN_LANE"), $(sql_quote "$PROJECT"), $(sql_nullable "$ISSUE"), $(sql_nullable "$PR"), $(sql_quote "$STATUS"), $(sql_nullable "$SUMMARY"), $(sql_nullable "$NEXT_STEPS"), $(sql_quote "$EVIDENCE"), $(sql_quote "$now"), $epoch, $completed_at, $completed_epoch);
SELECT last_insert_rowid();"
  fi
  id="$(sqlite_tx "$db" "$sql")"
  echo "id=$id status=$STATUS"
}

MEM_WARNED=0
MEM_CONTEXT=""

warn_mem() {
  [[ "${MEM_WARNED}" -eq 0 ]] || return 0
  MEM_WARNED=1
  [[ -n "${1:-}" ]] || return 0
  printf '%s\n' "$1" >&2
}

bug_mem_write() {
  local status="$1" err code
  err="$(mktemp)"
  set +e
  "$FACTORY/factory.sh" mem write \
    --lane bug \
    --status "$status" \
    --harness "$RUNNER" \
    --issue "$ISSUE" \
    ${OWNER:+--owner "$OWNER"} \
    ${REPO:+--repo "$REPO"} \
    >/dev/null 2>"$err"
  code=$?
  set -e
  if [[ $code -ne 0 ]]; then
    warn_mem "$(cat "$err")"
  fi
  rm -f "$err"
}

bug_mem_start() {
  local err code
  MEM_WARNED=0
  MEM_CONTEXT=""
  err="$(mktemp)"
  set +e
  MEM_CONTEXT="$("$FACTORY/factory.sh" mem read --issue "$ISSUE" 2>"$err")"
  code=$?
  set -e
  if [[ $code -ne 0 || -s "$err" ]]; then
    warn_mem "$(cat "$err")"
  fi
  rm -f "$err"
  bug_mem_write started
}

bug_mem_finish() {
  local code="$1" db open status
  db="$(memory_db)"
  [[ -f "$db" ]] || return 0
  command -v sqlite3 >/dev/null 2>&1 || return 0
  set +e
  open="$(sqlite3 "$db" "SELECT COUNT(*) FROM runs WHERE issue = $(sql_quote "$ISSUE") AND lane = 'bug' AND status = 'started';")"
  set -e
  [[ "${open:-0}" -gt 0 ]] || return 0
  if [[ "$code" -eq 0 ]]; then
    status=done
  else
    status=failed
  fi
  bug_mem_write "$status"
}

case "$LANE" in
  mem)
    case "$MEM_CMD" in
      read) mem_read ;;
      write) mem_write ;;
      *) usage ;;
    esac
    ;;
  feature|docs)
    need_issue
    DIR="$(repo_dir)"
    run_agent "$DIR" "$(cat "$FACTORY/lanes/${LANE}.md")"$'\n'"$HARD"       "Implement GitHub issue $(issue_url "$ISSUE") in the ${REPO} checkout. Open a PR against main. Print the PR URL. Do not merge."
    ;;
  bug)
    need_issue
    DIR="$(repo_dir)"
    bug_mem_start
    prompt="Implement GitHub issue $(issue_url "$ISSUE") in the ${REPO} checkout. Open a PR against main. Print the PR URL. Do not merge."
    if [[ -n "${MEM_CONTEXT:-}" ]]; then
      prompt+=$'\n\n'"Factory memory:"$'\n'"$MEM_CONTEXT"
    fi
    set +e
    run_agent "$DIR" "$(cat "$FACTORY/lanes/bug.md")"$'\n'"$HARD" "$prompt"
    code=$?
    set -e
    bug_mem_finish "$code"
    exit "$code"
    ;;
  review)
    need_pr
    DIR="$(repo_dir)"
    run_agent "$DIR" "$(cat "$FACTORY/lanes/review.md")"$'\n'"$HARD"       "Review $(pr_url "$PR") only. Use /thermo-nuclear-code-quality-review. Do not implement. Do not merge."
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
  qa)
    [[ -n "$URL" || -n "$PR" ]] || { echo "Need --url <app> or --pr <n>" >&2; exit 1; }
    if [[ -n "$REPO" ]]; then
      DIR="$(repo_dir)"
    else
      DIR="$WORKSPACE"
    fi
    run_agent "$DIR" "$(cat "$FACTORY/lanes/qa.md")"$'\n'"$HARD"       "QA the running app. URL: ${URL:-from the PR / local}. PR: ${PR:-none}. Prefer /run-smoke-tests if a suite exists, else /browser-use. Report only. Do not implement. Do not merge."
    ;;
  *)
    usage
    ;;
esac
