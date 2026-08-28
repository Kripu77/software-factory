#!/usr/bin/env bash

TRACKER="github"
TRACKER_CMD=""
TICKET_ID=""
TICKET_TITLE=""
TICKET_URL=""
TICKET_STATUS=""
TICKET_LABELS=""
TICKET_BODY=""

load_tracker() {
  local dir="" line
  TRACKER="github"
  TRACKER_CMD="${FACTORY_TRACKER_CMD:-}"
  if [[ -n "${REPO:-}" && -d "$WORKSPACE/$REPO" ]]; then
    dir="$(git -C "$WORKSPACE/$REPO" rev-parse --show-toplevel 2>/dev/null || true)"
  fi
  if [[ -z "$dir" ]]; then
    dir="$(git rev-parse --show-toplevel 2>/dev/null || git -C "$WORKSPACE" rev-parse --show-toplevel 2>/dev/null || true)"
  fi
  [[ -n "$dir" && -f "$dir/.factory/config" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      tracker=*) TRACKER="${line#tracker=}" ;;
    esac
  done < "$dir/.factory/config"
}

parse_ticket_record() {
  local in_body=0 line
  TICKET_ID=""
  TICKET_TITLE=""
  TICKET_URL=""
  TICKET_STATUS=""
  TICKET_LABELS=""
  TICKET_BODY=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$in_body" -eq 1 ]]; then
      if [[ -n "$TICKET_BODY" ]]; then
        TICKET_BODY+=$'\n'"$line"
      else
        TICKET_BODY="$line"
      fi
      continue
    fi
    case "$line" in
      id=*) TICKET_ID="${line#id=}" ;;
      title=*) TICKET_TITLE="${line#title=}" ;;
      url=*) TICKET_URL="${line#url=}" ;;
      status=*) TICKET_STATUS="${line#status=}" ;;
      labels=*)
        TICKET_LABELS="${line#labels=}"
        TICKET_LABELS="${TICKET_LABELS%,}"
        ;;
      body:*)
        in_body=1
        TICKET_BODY="${line#body:}"
        TICKET_BODY="${TICKET_BODY# }"
        ;;
    esac
  done <<< "$1"
}

github_ticket_get() {
  command -v gh >/dev/null 2>&1 || return 1
  [[ -n "${OWNER:-}" && -n "${REPO:-}" && -n "${ISSUE:-}" ]] || return 1
  gh issue view "$ISSUE" -R "${OWNER}/${REPO}" --json number,title,body,labels,url,state --template $'id={{.number}}\ntitle={{.title}}\nurl={{.url}}\nstatus={{.state}}\nlabels={{range .labels}}{{.name}},{{end}}\nbody:\n{{.body}}\n'
}

ticket_get_failed() {
  local err="$1" msg
  msg="$(cat "$err")"
  rm -f "$err"
  [[ -n "$msg" ]] || msg="tracker get failed for ${ISSUE:-}"
  printf '%s\n' "$msg" >&2
  return 1
}

ticket_get() {
  local raw="" err code
  TICKET_ID=""
  TICKET_TITLE=""
  TICKET_URL=""
  TICKET_STATUS=""
  TICKET_LABELS=""
  TICKET_BODY=""
  [[ -n "${ISSUE:-}" ]] || return 1
  load_tracker
  if [[ -n "$TRACKER_CMD" ]]; then
    err="$(mktemp)"
    set +e
    raw="$("$TRACKER_CMD" get "$ISSUE" 2>"$err")"
    code=$?
    set -e
    if [[ $code -ne 0 || -z "$raw" ]]; then
      ticket_get_failed "$err"
      return 1
    fi
    rm -f "$err"
  elif [[ "$TRACKER" == github ]]; then
    err="$(mktemp)"
    set +e
    raw="$(github_ticket_get 2>"$err")"
    code=$?
    set -e
    if [[ $code -ne 0 || -z "$raw" ]]; then
      ticket_get_failed "$err"
      return 1
    fi
    rm -f "$err"
  else
    TICKET_ID="$ISSUE"
    return 0
  fi
  parse_ticket_record "$raw"
  if [[ -z "$TICKET_ID" ]]; then
    printf '%s\n' "tracker get failed for $ISSUE" >&2
    return 1
  fi
}

ticket_context() {
  ticket_get || true
  local out=""
  out="id: ${TICKET_ID:-${ISSUE:-}}"
  [[ -z "$TICKET_TITLE" ]] || out+=$'\n'"title: $TICKET_TITLE"
  [[ -z "$TICKET_URL" ]] || out+=$'\n'"url: $TICKET_URL"
  [[ -z "$TICKET_STATUS" ]] || out+=$'\n'"status: $TICKET_STATUS"
  [[ -z "$TICKET_LABELS" ]] || out+=$'\n'"labels: $TICKET_LABELS"
  [[ -z "$TICKET_BODY" ]] || out+=$'\n\n'"$TICKET_BODY"
  printf '%s\n' "$out"
}

ticket_issue_comment() {
  local body="$1" err="$2"
  load_tracker
  if [[ -n "$TRACKER_CMD" ]]; then
    "$TRACKER_CMD" comment "$ISSUE" --body "$body" >/dev/null 2>"$err"
    return $?
  fi
  if [[ "$TRACKER" == github ]]; then
    [[ -n "${OWNER:-}" && -n "${REPO:-}" ]] || return 0
    command -v gh >/dev/null 2>&1 || { warn_mem "gh not installed"; return 0; }
    gh issue comment "$ISSUE" -R "${OWNER}/${REPO}" --body "$body" >/dev/null 2>"$err"
    return $?
  fi
  warn_mem "Need FACTORY_TRACKER_CMD to comment on tracker $TRACKER"
  return 0
}
