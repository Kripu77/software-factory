#!/usr/bin/env bash
set -euo pipefail

FACTORY="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE="${FACTORY_WORKSPACE:-$PWD}"
OWNER="${FACTORY_OWNER:-}"
RUNNER="${FACTORY_RUNNER:-}"

usage() {
  cat <<EOF
Usage:
  factory.sh feature|bug|docs --repo <name> --issue <n> [--owner org] [--runner claude|codex|grok] [--yes]
  factory.sh review|ci        --repo <name> --pr <n>     [--owner org] [--runner claude|codex|grok] [--yes]
  factory.sh floor|ship       --repo <name> --issue <n> [--owner org] [--runner ...] [--yes] [--url <app>]
  factory.sh lead             --issue <n> [--repo <name>] [--yes]
  factory.sh telemetry        --question "<what broke>" [--yes]
  factory.sh qa               --repo <name> --pr <n> [--url <app>]
  factory.sh qa               --url <app>
  factory.sh mem read         [--issue <n>] [--pr <n>] [--project owner/name] [--limit n]
  factory.sh mem write        --lane <lane> --status started|done|blocked|failed [--harness claude|codex|cursor|grok] [--issue <n>] [--pr <n>] [--project owner/name] [--summary s] [--next-steps s] [--evidence url-or-json]
  factory.sh close-linked     --pr <n> [--repo name] [--owner org]

Never merges. A person merges.
Workspace defaults to this directory. Owner and repo default from git remote origin. FACTORY_RUNNER if more than one of claude, codex, grok is on PATH.
Memory: FACTORY_MEMORY_DB (default ~/.factory/memory/factory.db). Optional. Missing db warns and continues.
EOF
  exit 1
}

detect_runner() {
  local found="" name
  if [[ -n "$RUNNER" ]]; then
    if [[ "$RUNNER" == "cursor" ]]; then
      echo "Cursor is a slash-command door, not a factory.sh --runner." >&2
      exit 1
    fi
    command -v "$RUNNER" >/dev/null 2>&1 || { echo "No runner '$RUNNER' on PATH. Set FACTORY_RUNNER or --runner." >&2; exit 1; }
    return 0
  fi
  for name in claude codex grok; do
    if command -v "$name" >/dev/null 2>&1; then
      found="${found:+$found }$name"
    fi
  done
  set -- $found
  if [[ $# -eq 1 ]]; then
    RUNNER="$1"
    return 0
  fi
  if [[ $# -eq 0 ]]; then
    echo "No runner on PATH. Install claude, codex, or grok, or set FACTORY_RUNNER / --runner." >&2
    exit 1
  fi
  echo "Multiple runners on PATH: $found. Set FACTORY_RUNNER or --runner." >&2
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
fi

infer_github() {
  [[ -n "$OWNER" && -n "$REPO" ]] && return 0
  local url="" project=""
  url="$(git -C "$WORKSPACE" remote get-url origin 2>/dev/null || true)"
  if [[ -z "$url" ]]; then
    url="$(git remote get-url origin 2>/dev/null || true)"
  fi
  [[ -n "$url" ]] || return 0
  project="$(github_owner_repo "$url")" || return 0
  [[ -n "$OWNER" ]] || OWNER="${project%%/*}"
  [[ -n "$REPO" ]] || REPO="${project##*/}"
}

need_owner() { [[ -n "$OWNER" ]] || { echo "Need --owner, FACTORY_OWNER, or a github origin remote" >&2; exit 1; }; }
need_issue() { [[ -n "$ISSUE" ]] || { echo "Need --issue <n>" >&2; exit 1; }; }
need_pr() { [[ -n "$PR" ]] || { echo "Need --pr <n>" >&2; exit 1; }; }
need_question() { [[ -n "$QUESTION" ]] || { echo "Need --question" >&2; exit 1; }; }
need_repo() { [[ -n "$REPO" ]] || { echo "Need --repo <name>" >&2; exit 1; }; }

close_linked_issues() {
  need_pr
  need_owner
  need_repo
  command -v gh >/dev/null 2>&1 || { echo "gh not installed" >&2; exit 1; }
  local num
  while IFS= read -r num; do
    [[ "$num" =~ ^[0-9]+$ ]] || continue
    gh issue close "$num" -R "${OWNER}/${REPO}"
  done <<< "$(gh pr view "$PR" -R "${OWNER}/${REPO}" --json mergedAt,baseRefName,closingIssuesReferences --template '{{if .mergedAt}}{{if eq .baseRefName "main"}}{{range .closingIssuesReferences}}{{.number}}{{"\n"}}{{end}}{{end}}{{end}}')"
}

record_harness() {
  case "${RUNNER:-}" in
    claude|cursor|codex|grok) printf '%s\n' "$RUNNER"; return 0 ;;
  esac
  case "${FACTORY_HARNESS:-}" in
    claude|cursor|codex|grok) printf '%s\n' "$FACTORY_HARNESS"; return 0 ;;
  esac
  return 1
}

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

conventions_rules() {
  local dir="$1" file="$1/.factory/conventions" line skills=""
  [[ -f "$file" ]] || return 0
  if [[ -d "$dir/.git" ]] && ! grep -qxF '.factory/' "$dir/.git/info/exclude" 2>/dev/null; then
    mkdir -p "$dir/.git/info"
    printf '.factory/\n' >> "$dir/.git/info/exclude"
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line//[[:space:]]/}"
    [[ -n "$line" ]] || continue
    skills="${skills:+$skills, }/$line"
  done < "$file"
  [[ -n "$skills" ]] || return 0
  printf 'This repo has conventions. Before writing code invoke each of these skills and follow its conventions: %s.\n' "$skills"
}

run_agent() {
  local cwd="$1"
  local rules="$2"
  local prompt="$3"
  detect_runner
  case "$RUNNER" in
    grok)
      local extra=(--no-auto-update --no-alt-screen)
      [[ "$YES" -eq 1 ]] && extra+=(--always-approve)
      ( cd "$cwd" && FACTORY_LANE="$LANE" grok "${extra[@]}" --rules "$rules" -p "$prompt" )
      ;;
    claude)
      local extra=(-p --append-system-prompt "$rules")
      [[ "$YES" -eq 1 ]] && extra+=(--dangerously-skip-permissions)
      ( cd "$cwd" && FACTORY_LANE="$LANE" claude "${extra[@]}" "$prompt" )
      ;;
    codex)
      local extra=(exec)
      [[ "$YES" -eq 1 ]] && extra+=(--full-auto)
      ( cd "$cwd" && FACTORY_LANE="$LANE" codex "${extra[@]}" "$prompt"$'\n\n'"$rules" )
      ;;
    *)
      command -v "$RUNNER" >/dev/null 2>&1 || { echo "No runner '$RUNNER' on PATH." >&2; exit 1; }
      if [[ "$YES" -eq 1 ]]; then
        ( cd "$cwd" && FACTORY_LANE="$LANE" "$RUNNER" --yes --rules "$rules" -p "$prompt" )
      else
        ( cd "$cwd" && FACTORY_LANE="$LANE" "$RUNNER" --rules "$rules" -p "$prompt" )
      fi
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

github_owner_repo() {
  local raw="$1" project
  [[ -n "$raw" ]] || return 1
  if owner_name "$raw"; then
    printf '%s\n' "$raw"
    return 0
  fi
  project="$(printf '%s' "$raw" | sed -E -e 's#^[a-zA-Z0-9+.-]+://##' -e 's#^.*@##' -e 's#^[^:/]+(:[0-9]+)?[:/]##' -e 's#\.git$##' -e 's#/$##')"
  owner_name "$project" || return 1
  printf '%s\n' "$project"
}

project_from_remote() {
  local project
  project="$(github_owner_repo "$1")" || { echo "Need --project owner/name" >&2; exit 1; }
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
  OWNER="${PROJECT%%/*}"
  REPO="${PROJECT##*/}"
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

lift_pr_from_item() {
  local item="$1" rest n
  [[ -z "${PR:-}" ]] || return 0
  case "$item" in
    https://github.com/*/*/pull/[0-9]*)
      rest="${item##*/pull/}"
      n="${rest%%[!0-9]*}"
      [[ "$n" =~ ^[0-9]+$ ]] && PR="$n"
      ;;
  esac
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
    lift_pr_from_item "$item"
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
  lift_pr_from_item "$EVIDENCE"
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
  if [[ -n "$PR" ]]; then
    if [[ -n "$where" ]]; then
      where="$where AND pr = $(sql_quote "$PR")"
    else
      where="pr = $(sql_quote "$PR")"
    fi
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
  (SELECT id FROM runs WHERE issue = $(sql_quote "$ISSUE") AND lane = $(sql_quote "$RUN_LANE") ORDER BY id DESC LIMIT 1)
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
  if [[ "${FACTORY_SKIP_TICKET_COMMENT:-}" != 1 ]]; then
    ticket_comment
  fi
}

MEM_WARNED=0
MEM_CONTEXT=""

warn_mem() {
  [[ "${MEM_WARNED}" -eq 0 ]] || return 0
  MEM_WARNED=1
  [[ -n "${1:-}" ]] || return 0
  printf '%s\n' "$1" >&2
}

ticket_comment() {
  local body err code lane="${1:-${RUN_LANE:-$LANE}}"
  case "$lane" in
    feature|docs|qa|review|ci|telemetry) ;;
    *) return 0 ;;
  esac
  case "${STATUS:-}" in
    done|blocked|failed) ;;
    *) return 0 ;;
  esac
  [[ -n "${SUMMARY:-}" ]] || return 0
  [[ -n "${OWNER:-}" && -n "${REPO:-}" ]] || return 0
  [[ -n "${ISSUE:-}" || -n "${PR:-}" ]] || return 0
  command -v gh >/dev/null 2>&1 || { warn_mem "gh not installed"; return 0; }
  body="$SUMMARY"
  if [[ -n "${PR:-}" ]]; then
    body+=$'\n\n'"[PR ${PR}]($(pr_url "$PR"))"
  fi
  err="$(mktemp)"
  set +e
  if [[ -n "${ISSUE:-}" ]]; then
    gh issue comment "$ISSUE" -R "${OWNER}/${REPO}" --body "$body" >/dev/null 2>"$err"
  else
    gh pr comment "$PR" -R "${OWNER}/${REPO}" --body "$body" >/dev/null 2>"$err"
  fi
  code=$?
  set -e
  if [[ $code -ne 0 ]]; then
    warn_mem "$(cat "$err")"
  fi
  rm -f "$err"
}

mem_read_context() {
  local err code args=()
  MEM_WARNED=0
  MEM_CONTEXT=""
  if [[ -n "${ISSUE:-}" ]]; then
    args+=(--issue "$ISSUE")
  elif [[ -n "${PR:-}" ]]; then
    args+=(--pr "$PR")
  else
    return 0
  fi
  err="$(mktemp)"
  set +e
  MEM_CONTEXT="$("$FACTORY/factory.sh" mem read "${args[@]}" 2>"$err")"
  code=$?
  set -e
  if [[ $code -ne 0 || -s "$err" ]]; then
    warn_mem "$(cat "$err")"
  fi
  rm -f "$err"
}

lane_mem_write() {
  local lane="$1" status="$2" err code h
  shift 2
  h="$(record_harness)" || { warn_mem "Need FACTORY_HARNESS or --runner claude|codex|cursor|grok to record memory"; return 0; }
  err="$(mktemp)"
  set +e
  "$FACTORY/factory.sh" mem write \
    --lane "$lane" \
    --status "$status" \
    --harness "$h" \
    ${ISSUE:+--issue "$ISSUE"} \
    ${PR:+--pr "$PR"} \
    ${OWNER:+--owner "$OWNER"} \
    ${REPO:+--repo "$REPO"} \
    "$@" \
    >/dev/null 2>"$err"
  code=$?
  set -e
  if [[ $code -ne 0 || -s "$err" ]]; then
    warn_mem "$(cat "$err")"
  fi
  rm -f "$err"
}

latest_lane_status() {
  local want="$1" rec_lane="" rec_st=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      *"lane = "*) rec_lane="${line##* = }" ;;
      *"status = "*) rec_st="${line##* = }" ;;
      "")
        if [[ "$rec_lane" == "$want" ]]; then
          printf '%s\n' "$rec_st"
          return 0
        fi
        rec_lane=""
        rec_st=""
        ;;
    esac
  done
  if [[ "$rec_lane" == "$want" ]]; then
    printf '%s\n' "$rec_st"
  fi
}

lane_mem_finish() {
  local lane="$1" code="$2" status latest err rec_status args=() extra
  err="$(mktemp)"
  if [[ -n "${ISSUE:-}" ]]; then
    args+=(--issue "$ISSUE")
  elif [[ -n "${PR:-}" ]]; then
    args+=(--pr "$PR")
  fi
  set +e
  if [[ ${#args[@]} -gt 0 ]]; then
    latest="$("$FACTORY/factory.sh" mem read "${args[@]}" 2>"$err")"
  else
    latest=""
  fi
  set -e
  if [[ -s "$err" ]]; then
    warn_mem "$(cat "$err")"
  fi
  rm -f "$err"
  rec_status="$(printf '%s\n' "$latest" | latest_lane_status "$lane")"
  case "$rec_status" in
    blocked|done|failed) return 0 ;;
    *)
      if [[ "$code" -eq 0 ]]; then
        status=done
      else
        status=failed
      fi
      extra=(--summary "${lane} lane ${status}.")
      if [[ -n "$OWNER" && -n "$REPO" && -n "$ISSUE" ]]; then
        extra+=(--evidence "https://github.com/${OWNER}/${REPO}/issues/${ISSUE}")
      elif [[ -n "$OWNER" && -n "$REPO" && -n "$PR" ]]; then
        extra+=(--evidence "https://github.com/${OWNER}/${REPO}/pull/${PR}")
      fi
      lane_mem_write "$lane" "$status" "${extra[@]}"
      ;;
  esac
}

run_mem_lane() {
  local lane="$1" dir="$2" rules="$3" prompt="$4" code
  detect_runner
  mem_read_context
  prompt+=$'\n'"Memory writes: factory.sh mem write --lane $lane --harness $RUNNER ${ISSUE:+--issue $ISSUE }${PR:+--pr $PR }--summary '<one sentence>' --evidence <url-or-path> --next-steps '<next>'."
  if [[ -n "${MEM_CONTEXT:-}" ]]; then
    prompt+=$'\n\n'"Factory memory:"$'\n'"$MEM_CONTEXT"
  fi
  unset FACTORY_SKIP_TICKET_COMMENT
  set +e
  run_agent "$dir" "$rules" "$prompt"
  code=$?
  set -e
  lane_mem_finish "$lane" "$code"
  return "$code"
}

floor_classify() {
  local name
  command -v gh >/dev/null 2>&1 || { printf '%s\n' feature; return 0; }
  [[ -n "$OWNER" && -n "$REPO" ]] || { printf '%s\n' feature; return 0; }
  while IFS= read -r name; do
    case "$name" in
      bug) printf '%s\n' bug; return 0 ;;
      documentation|docs) printf '%s\n' docs; return 0 ;;
    esac
  done < <(gh issue view "$ISSUE" -R "${OWNER}/${REPO}" --json labels --template '{{range .labels}}{{.name}}{{"\n"}}{{end}}' 2>/dev/null || true)
  printf '%s\n' feature
}

floor_mem() {
  "$FACTORY/factory.sh" mem read --issue "$ISSUE" 2>/dev/null || true
}

floor_pr_from_mem() {
  local line val
  while IFS= read -r line; do
    case "$line" in
      *"pr = "*)
        val="${line##* = }"
        if [[ -n "$val" ]]; then
          printf '%s\n' "$val"
          return 0
        fi
        ;;
    esac
  done <<< "$(floor_mem)"
  return 0
}

floor_pr_from_gh() {
  local head num
  command -v gh >/dev/null 2>&1 || return 0
  [[ -n "$OWNER" && -n "$REPO" ]] || return 0
  head="$(git -C "$(repo_dir 2>/dev/null || echo "$WORKSPACE")" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [[ -n "$head" && "$head" != "main" && "$head" != "master" ]]; then
    num="$(gh pr view --head "$head" -R "${OWNER}/${REPO}" --json number --template '{{.number}}' 2>/dev/null || true)"
  else
    num="$(gh pr view -R "${OWNER}/${REPO}" --json number --template '{{.number}}' 2>/dev/null || true)"
  fi
  [[ -n "$num" ]] && printf '%s\n' "$num"
  return 0
}

floor_review_count() {
  command -v gh >/dev/null 2>&1 || { printf '%s\n' 0; return 0; }
  [[ -n "${PR:-}" && -n "$OWNER" && -n "$REPO" ]] || { printf '%s\n' 0; return 0; }
  gh pr view "$PR" -R "${OWNER}/${REPO}" --json reviews --template '{{len .reviews}}' 2>/dev/null || printf '%s\n' 0
}

floor_capture_pr() {
  local lane="$1" num h
  num="$(floor_pr_from_mem)"
  [[ -n "$num" ]] || num="$(floor_pr_from_gh)"
  [[ -n "$num" ]] || return 0
  PR="$num"
  h="$(record_harness)" || return 0
  FACTORY_SKIP_TICKET_COMMENT=1 "$FACTORY/factory.sh" mem write \
    --lane "$lane" --status done --harness "$h" --issue "$ISSUE" --pr "$num" \
    ${OWNER:+--owner "$OWNER"} ${REPO:+--repo "$REPO"} \
    --summary "Opened PR ${num}." --next-steps "QA, review, CI" >/dev/null 2>/dev/null || true
}

floor_cmd() {
  if [[ "$YES" -eq 1 ]]; then
    "$FACTORY/factory.sh" "$@" --yes
  else
    "$FACTORY/factory.sh" "$@"
  fi
}

floor_dispatch() {
  local lane="$1" qaurl="${URL:-${FACTORY_QA_URL:-}}"
  echo "dispatch $lane"
  case "$lane" in
    feature|bug|docs)
      floor_cmd "$lane" --repo "$REPO" --issue "$ISSUE" --owner "$OWNER" --runner "$RUNNER"
      ;;
    review|ci)
      floor_cmd "$lane" --repo "$REPO" --pr "$PR" --issue "$ISSUE" --owner "$OWNER" --runner "$RUNNER"
      ;;
    qa)
      floor_cmd qa --repo "$REPO" --pr "$PR" --issue "$ISSUE" --url "$qaurl" --owner "$OWNER" --runner "$RUNNER"
      ;;
    telemetry)
      floor_cmd telemetry --question "evidence for issue ${ISSUE}" --repo "$REPO" --owner "$OWNER" --runner "$RUNNER"
      ;;
  esac
}

floor_next() {
  local raw impl s lane pr nrev qaurl="${URL:-${FACTORY_QA_URL:-}}"
  raw="$(floor_mem)"
  for lane in feature bug docs qa review ci telemetry; do
    s="$(printf '%s\n' "$raw" | latest_lane_status "$lane")"
    case "$s" in
      blocked) printf '%s\n' stop:blocked; return 0 ;;
      failed) printf '%s\n' stop:failed; return 0 ;;
    esac
  done
  impl="$(floor_classify)"
  if [[ "$impl" == bug ]]; then
    s="$(printf '%s\n' "$raw" | latest_lane_status telemetry)"
    if [[ -z "$s" && -z "${FLOOR_DID_TEL:-}" ]]; then
      printf '%s\n' telemetry
      return 0
    fi
  fi
  pr="$(floor_pr_from_mem)"
  [[ -n "$pr" ]] || pr="$(floor_pr_from_gh)"
  if [[ -z "$pr" ]]; then
    printf '%s\n' "$impl"
    return 0
  fi
  PR="$pr"
  s="$(printf '%s\n' "$raw" | latest_lane_status qa)"
  if [[ -n "$qaurl" ]]; then
    if [[ -z "$s" && -z "${FLOOR_DID_QA:-}" ]]; then
      printf '%s\n' qa
      return 0
    fi
  else
    if [[ -z "$s" && -z "${FLOOR_QA_SKIPPED:-}" ]]; then
      printf '%s\n' skip-qa
      return 0
    fi
  fi
  nrev="$(floor_review_count)"
  if [[ "${nrev:-0}" -eq 0 && -z "${FLOOR_DID_REVIEW:-}" ]]; then
    printf '%s\n' review
    return 0
  fi
  if command -v gh >/dev/null 2>&1 && gh pr checks "$PR" -R "${OWNER}/${REPO}" >/dev/null 2>&1; then
    printf '%s\n' merge
    return 0
  fi
  if [[ -n "${FLOOR_DID_CI:-}" ]]; then
    printf '%s\n' stop:failed
    return 0
  fi
  printf '%s\n' ci
}

floor_run() {
  local next i h
  FLOOR_QA_SKIPPED=""
  FLOOR_DID_QA=""
  FLOOR_DID_REVIEW=""
  FLOOR_DID_CI=""
  FLOOR_DID_TEL=""
  need_issue
  [[ -n "$REPO" ]] || { echo "Need --repo <name>" >&2; exit 1; }
  need_owner
  detect_runner
  for i in 1 2 3 4 5 6 7 8; do
    pr="$(floor_pr_from_mem)"
    [[ -n "$pr" ]] || pr="$(floor_pr_from_gh)"
    [[ -n "$pr" ]] && PR="$pr"
    next="$(floor_next)"
    case "$next" in
      stop:blocked)
        echo "blocked. stop."
        return 0
        ;;
      stop:failed)
        echo "failed. stop."
        return 1
        ;;
      merge)
        echo "a person merges. $(pr_url "$PR")"
        return 0
        ;;
      skip-qa)
        FLOOR_QA_SKIPPED=1
        h="$(record_harness)" || h=""
        if [[ -n "$h" ]]; then
          FACTORY_SKIP_TICKET_COMMENT=1 "$FACTORY/factory.sh" mem write \
            --lane qa --status done --harness "$h" --issue "$ISSUE" ${PR:+--pr "$PR"} \
            ${OWNER:+--owner "$OWNER"} ${REPO:+--repo "$REPO"} \
            --summary "QA skipped, no URL." --next-steps "Review the PR" >/dev/null 2>/dev/null || true
        fi
        continue
        ;;
      feature|bug|docs|qa|review|ci|telemetry)
        set +e
        floor_dispatch "$next"
        set -e
        case "$next" in
          feature|bug|docs)
            s="$(printf '%s\n' "$(floor_mem)" | latest_lane_status "$next")"
            case "$s" in
              blocked|failed) ;;
              *) floor_capture_pr "$next" ;;
            esac
            ;;
          qa) FLOOR_DID_QA=1 ;;
          review) FLOOR_DID_REVIEW=1 ;;
          ci) FLOOR_DID_CI=1 ;;
          telemetry) FLOOR_DID_TEL=1 ;;
        esac
        ;;
      *)
        echo "floor: unknown next $next" >&2
        return 1
        ;;
    esac
  done
  echo "floor: too many steps" >&2
  return 1
}

infer_github

case "$LANE" in
  mem)
    case "$MEM_CMD" in
      read) mem_read ;;
      write) mem_write ;;
      *) usage ;;
    esac
    ;;
  close-linked)
    close_linked_issues
    ;;
  feature|bug|docs)
    need_issue
    DIR="$(repo_dir)"
    RULES="$(cat "$FACTORY/lanes/${LANE}.md")"$'\n'"$HARD"
    CONVENTIONS="$(conventions_rules "$DIR")"
    [[ -z "$CONVENTIONS" ]] || RULES+=$'\n'"$CONVENTIONS"
    run_mem_lane "$LANE" "$DIR" "$RULES" "Implement GitHub issue $(issue_url "$ISSUE") in the ${REPO} checkout. Open a PR against main. Print the PR URL. Do not merge."
    exit $?
    ;;
  review)
    need_pr
    DIR="$(repo_dir)"
    run_mem_lane review "$DIR" "$(cat "$FACTORY/lanes/review.md")"$'\n'"$HARD" "Review $(pr_url "$PR") only. Use /thermo-nuclear-code-quality-review. Do not implement. Do not merge."
    exit $?
    ;;
  ci)
    need_pr
    need_owner
    DIR="$(repo_dir)"
    command -v gh >/dev/null 2>&1 || { echo "gh not installed" >&2; exit 1; }
    echo "Checks before:"
    gh pr checks "$PR" -R "${OWNER}/${REPO}" || true
    run_mem_lane ci "$DIR" "$(cat "$FACTORY/lanes/ci.md")"$'\n'"$HARD" "Watch $(pr_url "$PR") with gh pr checks until green. Fix failures on this branch. Do not merge."
    code=$?
    echo "Checks after:"
    gh pr checks "$PR" -R "${OWNER}/${REPO}" || true
    exit "$code"
    ;;
  floor|ship)
    floor_run
    exit $?
    ;;
  lead|tech-lead|cto)
    need_issue
    mem_read_context
    prompt="Ticket or update work for issue ${ISSUE}. Follow /to-tickets. Owning repo: ${REPO:-unknown}. Owner: ${OWNER:-unknown}. After tickets exist, start factory.sh floor --repo ${REPO:-<repo>} --issue ${ISSUE} (or one factory.sh lane). Dispatch is factory.sh only. Writing product code, leaving a review, or watching CI in this session is a failed run."
    if [[ -n "${MEM_CONTEXT:-}" ]]; then
      prompt+=$'\n\n'"Factory memory:"$'\n'"$MEM_CONTEXT"
    fi
    run_agent "$WORKSPACE" "$(cat "$FACTORY/lanes/tech-lead.md")"$'\n'"$HARD" "$prompt"
    if [[ -n "${REPO:-}" && -n "${OWNER:-}" ]]; then
      echo "dispatch factory.sh floor"
      floor_cmd floor --repo "$REPO" --issue "$ISSUE" --owner "$OWNER" --runner "$RUNNER"
      exit $?
    fi
    ;;
  telemetry)
    need_question
    run_mem_lane telemetry "$WORKSPACE" "$(cat "$FACTORY/lanes/telemetry.md")"$'\n'"$HARD"$'\n'"$(cat "$FACTORY/telemetry/CONTRACT.md")" "Answer this with evidence only: ${QUESTION}. Name the adapter you used. Do not implement product code. Do not merge."
    exit $?
    ;;
  qa)
    [[ -n "$URL" || -n "$PR" ]] || { echo "Need --url <app> or --pr <n>" >&2; exit 1; }
    if [[ -n "$REPO" ]]; then
      DIR="$(repo_dir)"
    else
      DIR="$WORKSPACE"
    fi
    run_mem_lane qa "$DIR" "$(cat "$FACTORY/lanes/qa.md")"$'\n'"$HARD" "QA the running app. URL: ${URL:-from the PR / local}. PR: ${PR:-none}. Prefer /run-smoke-tests if a suite exists, else /browser-use. Report only. Do not implement. Do not merge."
    exit $?
    ;;
  *)
    usage
    ;;
esac
