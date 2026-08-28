#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FACTORY="$ROOT/factory.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export FACTORY_MEMORY_DB="$TMP/memory/factory.db"
unset FACTORY_RUNNER
unset FACTORY_SKIP_TICKET_COMMENT
unset FACTORY_TRACKER_CMD

fail() { echo "FAIL: $*" >&2; exit 1; }

fn_body() {
  local name="$1"
  awk -v n="$name" '
    $0 ~ "^" n "\\(\\)" {on=1}
    on {print}
    on && /^}$/ {exit}
  ' "$ROOT/factory.sh"
}

WS="$TMP/workspace"
mkdir -p "$WS/widgets"
git -C "$WS/widgets" init -q
git -C "$WS/widgets" remote add origin "https://github.com/acme/widgets.git"

DUMP="$TMP/dump"
mkdir -p "$DUMP" "$TMP/bin"

cat > "$TMP/bin/runner" << 'EOF'
#!/usr/bin/env bash
dump="${FAKE_DUMP:?}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p) printf '%s\n' "$2" > "$dump/prompt"; shift 2 ;;
    --rules) printf '%s\n' "$2" > "$dump/rules"; shift 2 ;;
    *) shift ;;
  esac
done
: > "$dump/ran"
exit 0
EOF
chmod +x "$TMP/bin/runner"

cat > "$TMP/bin/gh" << 'EOF'
#!/usr/bin/env bash
dump="${FAKE_DUMP:?}"
printf '%s\n' "$*" >> "$dump/gh"
cmd1="${1:-}"
cmd2="${2:-}"
body=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --body) body="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
if [[ -n "$body" ]]; then
  printf '%s\n' "$body" > "$dump/comment-body"
fi
case "$cmd1 $cmd2" in
  "issue view")
    printf '%s\n' 'id=6'
    printf '%s\n' 'title=Add widgets list'
    printf '%s\n' 'url=https://github.com/acme/widgets/issues/6'
    printf '%s\n' 'status=open'
    printf '%s\n' 'labels=enhancement,ready-for-agent'
    printf '%s\n' 'body:'
    printf '%s\n' 'Ship a list of widgets.'
    ;;
esac
exit 0
EOF
chmod +x "$TMP/bin/gh"

cat > "$TMP/bin/mcp-ticket" << 'EOF'
#!/usr/bin/env bash
dump="${FAKE_DUMP:?}"
printf '%s\n' "$*" >> "$dump/mcp"
cmd="${1:-}"
id="${2:-}"
body=""
shift $(( $# > 0 ? 1 : 0 )) || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --body) body="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
case "$cmd" in
  get)
    printf '%s\n' "id=$id"
    printf '%s\n' 'title=MCP tracked ticket'
    printf '%s\n' 'url=https://linear.app/acme/issue/ABC-123'
    printf '%s\n' 'status=started'
    printf '%s\n' 'labels=bug,ready-for-agent'
    printf '%s\n' 'body:'
    printf '%s\n' 'Fix the checkout drop-off.'
    ;;
  comment)
    printf '%s\n' "$body" > "$dump/mcp-comment"
    ;;
esac
exit 0
EOF
chmod +x "$TMP/bin/mcp-ticket"

run_env() {
  PATH="$TMP/bin:$PATH" \
    FAKE_DUMP="$DUMP" \
    FACTORY_SH="$FACTORY" \
    FACTORY_WORKSPACE="$WS" \
    FACTORY_OWNER=acme \
    FACTORY_RUNNER=runner FACTORY_HARNESS=claude \
    "$@"
}

reset_dump() {
  rm -rf "$DUMP" "$TMP/memory"
  mkdir -p "$DUMP"
}

# GitHub default: factory fetches ticket context and hands it to the lane
reset_dump
run_env "$FACTORY" feature --repo widgets --issue 6 >"$TMP/out" 2>"$TMP/err"
[[ -f "$DUMP/ran" ]] || fail "github default should still run feature, err=$(cat "$TMP/err")"
grep -q "issue view" "$DUMP/gh" || fail "github default should fetch the ticket through gh: $(cat "$DUMP/gh")"
for field in 'id: 6' 'title: Add widgets list' 'url: https://github.com/acme/widgets/issues/6' 'status: open' 'labels: enhancement,ready-for-agent' 'Ship a list of widgets.'; do
  grep -Fq "$field" "$DUMP/prompt" || fail "github default prompt missing $field: $(cat "$DUMP/prompt")"
done
grep -q "gh issue" "$DUMP/prompt" && fail "lanes must not be told to call gh issue APIs: $(cat "$DUMP/prompt")"
grep -q "Implement GitHub issue" "$DUMP/prompt" && fail "prompt should hand ticket context, not a GitHub issue URL to fetch: $(cat "$DUMP/prompt")"

# GitHub default comments still go through gh issue comment
grep -q "issue comment 6" "$DUMP/gh" || fail "github default comments should use gh issue comment: $(cat "$DUMP/gh")"

# MCP connector: factory receives the ticket from FACTORY_TRACKER_CMD, not gh
reset_dump
FACTORY_TRACKER_CMD="$TMP/bin/mcp-ticket" run_env "$FACTORY" feature --repo widgets --issue ABC-123 >"$TMP/out" 2>"$TMP/err"
[[ -f "$DUMP/ran" ]] || fail "mcp tracker should still run feature, err=$(cat "$TMP/err")"
grep -q "get ABC-123" "$DUMP/mcp" || fail "factory should get the ticket from the MCP command: $(cat "$DUMP/mcp" 2>/dev/null || true)"
if [[ -f "$DUMP/gh" ]] && grep -q "issue view" "$DUMP/gh"; then
  fail "mcp tracker must not call gh issue view: $(cat "$DUMP/gh")"
fi
for field in 'id: ABC-123' 'title: MCP tracked ticket' 'url: https://linear.app/acme/issue/ABC-123' 'status: started' 'labels: bug,ready-for-agent' 'Fix the checkout drop-off.'; do
  grep -Fq "$field" "$DUMP/prompt" || fail "mcp prompt missing $field: $(cat "$DUMP/prompt")"
done
grep -q "gh issue" "$DUMP/prompt" && fail "mcp prompt must not tell lanes to call gh issue: $(cat "$DUMP/prompt")"

# MCP comments go through the plug, not gh issue comment
grep -q "comment ABC-123" "$DUMP/mcp" || fail "ticket comments should go through the MCP command: $(cat "$DUMP/mcp")"
[[ -f "$DUMP/mcp-comment" ]] || fail "MCP comment body missing"
if [[ -f "$DUMP/gh" ]] && grep -q "issue comment" "$DUMP/gh"; then
  fail "mcp tracker must not gh issue comment: $(cat "$DUMP/gh")"
fi

# mem write done with MCP still comments through the plug
reset_dump
FACTORY_TRACKER_CMD="$TMP/bin/mcp-ticket" run_env "$FACTORY" mem write \
  --lane feature --status done --harness grok --issue ABC-123 --owner acme --repo widgets \
  --project acme/widgets --summary "Shipped the list" >/dev/null
grep -q "comment ABC-123" "$DUMP/mcp" || fail "mem write comments should use the plug: $(cat "$DUMP/mcp" 2>/dev/null || true)"
if [[ -f "$DUMP/gh" ]] && grep -q "issue comment" "$DUMP/gh"; then
  fail "mem write with MCP must not gh issue comment: $(cat "$DUMP/gh")"
fi
[[ "$(cat "$DUMP/mcp-comment")" == "Shipped the list" ]] || fail "plug comment body want Shipped the list got $(cat "$DUMP/mcp-comment")"

# Review comments stay on GitHub PRs even when the ticket plug is MCP
reset_dump
FACTORY_TRACKER_CMD="$TMP/bin/mcp-ticket" run_env "$FACTORY" mem write \
  --lane review --status done --harness grok --pr 40 --owner acme --repo widgets \
  --project acme/widgets --summary "Left review comments" >/dev/null
grep -q "pr comment 40" "$DUMP/gh" || fail "review comments must stay on GitHub: $(cat "$DUMP/gh" 2>/dev/null || true)"
if [[ -f "$DUMP/mcp" ]] && grep -q comment "$DUMP/mcp"; then
  fail "review must not comment through the issue tracker plug: $(cat "$DUMP/mcp")"
fi

# Tracker linear without an MCP command must not call gh for ticket context
reset_dump
mkdir -p "$WS/widgets/.factory"
printf 'tracker=linear\nteam=ABC\n' > "$WS/widgets/.factory/config"
run_env "$FACTORY" feature --repo widgets --issue ABC-123 >"$TMP/out" 2>"$TMP/err"
[[ -f "$DUMP/ran" ]] || fail "linear name without MCP should still run, err=$(cat "$TMP/err")"
if [[ -f "$DUMP/gh" ]] && grep -q "issue view" "$DUMP/gh"; then
  fail "tracker linear must not gh issue view: $(cat "$DUMP/gh")"
fi
grep -q "ABC-123" "$DUMP/prompt" || fail "linear name should still pass the ticket id: $(cat "$DUMP/prompt")"

# Lead still publishes GitHub issues; ticket_context is extra context only
reset_dump
cat > "$TMP/bin/runner" << 'EOF'
#!/usr/bin/env bash
dump="${FAKE_DUMP:?}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p)
      if [[ ! -f "$dump/prompt" ]]; then
        printf '%s\n' "$2" > "$dump/prompt"
      fi
      shift 2
      ;;
    --rules)
      if [[ ! -f "$dump/rules" ]]; then
        printf '%s\n' "$2" > "$dump/rules"
      fi
      shift 2
      ;;
    *) shift ;;
  esac
done
: > "$dump/ran"
exit 0
EOF
chmod +x "$TMP/bin/runner"
run_env "$FACTORY" lead --repo widgets --issue ABC-123 >"$TMP/lout" 2>"$TMP/lerr" || true
[[ -f "$DUMP/prompt" ]] || fail "lead should still run on tracker linear, err=$(cat "$TMP/lerr")"
grep -q "Publish new tickets on the configured tracker" "$DUMP/prompt" && fail "lead must not change ticket publish workflow: $(cat "$DUMP/prompt")"
grep -q "ABC-123" "$DUMP/prompt" || fail "lead should still receive ticket context: $(cat "$DUMP/prompt")"
grep -q "Publish new tickets on the configured tracker" "$FACTORY" && fail "lead must not tell the agent to publish on the configured tracker"
cat > "$TMP/bin/runner" << 'EOF'
#!/usr/bin/env bash
dump="${FAKE_DUMP:?}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p) printf '%s\n' "$2" > "$dump/prompt"; shift 2 ;;
    --rules) printf '%s\n' "$2" > "$dump/rules"; shift 2 ;;
    *) shift ;;
  esac
done
: > "$dump/ran"
exit 0
EOF
chmod +x "$TMP/bin/runner"
rm -rf "$WS/widgets/.factory"

# Dead FACTORY_TRACKER_CMD must fail closed: no lane, no fabricated ticket
reset_dump
cat > "$TMP/bin/dead-tracker" << 'EOF'
#!/usr/bin/env bash
echo "tracker down" >&2
exit 1
EOF
chmod +x "$TMP/bin/dead-tracker"
set +e
FACTORY_TRACKER_CMD="$TMP/bin/dead-tracker" run_env "$FACTORY" feature --repo widgets --issue ABC-123 >"$TMP/out" 2>"$TMP/err"
dead_code=$?
set -e
[[ $dead_code -ne 0 ]] || fail "dead tracker get should fail the lane, err=$(cat "$TMP/err")"
grep -q "tracker down" "$TMP/err" || fail "dead tracker get should warn with the plug error: $(cat "$TMP/err")"
[[ ! -f "$DUMP/ran" ]] || fail "dead tracker must not start the lane"
if [[ -f "$DUMP/prompt" ]]; then
  fail "dead get should not hand the lane a ticket: $(cat "$DUMP/prompt")"
fi

# Unstructured gh output is not a ticket record
reset_dump
cat > "$TMP/bin/gh" << 'EOF'
#!/usr/bin/env bash
dump="${FAKE_DUMP:?}"
printf '%s\n' "$*" >> "$dump/gh"
case "$1 $2" in
  "issue view")
    printf '%s\n' 'ready-for-agent'
    printf '%s\n' 'enhancement'
    ;;
  "issue comment") exit 0 ;;
esac
exit 0
EOF
chmod +x "$TMP/bin/gh"
set +e
run_env "$FACTORY" feature --repo widgets --issue 6 >"$TMP/out" 2>"$TMP/err"
unstruct_code=$?
set -e
[[ $unstruct_code -ne 0 ]] || fail "unstructured gh must fail closed, err=$(cat "$TMP/err")"
[[ ! -f "$DUMP/ran" ]] || fail "unstructured gh must not start the lane"
if [[ -f "$DUMP/prompt" ]]; then
  fail "unstructured gh must not hand the lane a ticket: $(cat "$DUMP/prompt")"
fi
cat > "$TMP/bin/gh" << 'EOF'
#!/usr/bin/env bash
dump="${FAKE_DUMP:?}"
printf '%s\n' "$*" >> "$dump/gh"
cmd1="${1:-}"
cmd2="${2:-}"
body=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --body) body="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
if [[ -n "$body" ]]; then
  printf '%s\n' "$body" > "$dump/comment-body"
fi
case "$cmd1 $cmd2" in
  "issue view")
    printf '%s\n' 'id=6'
    printf '%s\n' 'title=Add widgets list'
    printf '%s\n' 'url=https://github.com/acme/widgets/issues/6'
    printf '%s\n' 'status=open'
    printf '%s\n' 'labels=enhancement,ready-for-agent'
    printf '%s\n' 'body:'
    printf '%s\n' 'Ship a list of widgets.'
    ;;
esac
exit 0
EOF
chmod +x "$TMP/bin/gh"

# Floor classification uses plug labels, not a raw gh issue call, when MCP is set
reset_dump
cat > "$TMP/bin/runner" << 'EOF'
#!/usr/bin/env bash
dump="${FAKE_DUMP:?}"
: > "$dump/after-feature"
printf 'grok\n' >> "$dump/dispatched"
exit 0
EOF
chmod +x "$TMP/bin/runner"
set +e
FACTORY_TRACKER_CMD="$TMP/bin/mcp-ticket" run_env "$FACTORY" floor --repo widgets --issue ABC-123 >"$TMP/fout" 2>"$TMP/ferr"
set -e
grep -q "dispatch bug" "$TMP/fout" || fail "floor should classify from plug labels, got: $(cat "$TMP/fout")"
if [[ -f "$DUMP/gh" ]] && grep -q "issue view" "$DUMP/gh"; then
  fail "floor must not gh issue view when MCP is set: $(cat "$DUMP/gh")"
fi
grep -q "pr view" "$DUMP/gh" || fail "PRs stay on GitHub: $(cat "$DUMP/gh" 2>/dev/null || true)"

# Floor must not dispatch when get fails
reset_dump
set +e
FACTORY_TRACKER_CMD="$TMP/bin/dead-tracker" run_env "$FACTORY" floor --repo widgets --issue ABC-123 >"$TMP/fout" 2>"$TMP/ferr"
floor_dead=$?
set -e
[[ $floor_dead -ne 0 ]] || fail "dead get must fail floor, err=$(cat "$TMP/ferr")"
if grep -q "dispatch " "$TMP/fout"; then
  fail "dead get must not dispatch a lane: $(cat "$TMP/fout")"
fi
grep -q "tracker down" "$TMP/ferr" || fail "floor dead get should surface the plug error: $(cat "$TMP/ferr")"

# A label with spaces is not word-split into a fake bug
reset_dump
cat > "$TMP/bin/mcp-spaces" << 'EOF'
#!/usr/bin/env bash
dump="${FAKE_DUMP:?}"
printf '%s\n' "$*" >> "$dump/mcp"
case "${1:-}" in
  get)
    printf '%s\n' "id=${2:-}"
    printf '%s\n' 'title=Not a bug'
    printf '%s\n' 'url=https://example/issues/9'
    printf '%s\n' 'status=open'
    printf '%s\n' 'labels=not a bug,ready-for-agent'
    printf '%s\n' 'body:'
    printf '%s\n' 'Keep the spaces.'
    ;;
  comment) ;;
esac
exit 0
EOF
chmod +x "$TMP/bin/mcp-spaces"
set +e
FACTORY_TRACKER_CMD="$TMP/bin/mcp-spaces" run_env "$FACTORY" floor --repo widgets --issue 9 >"$TMP/sout" 2>"$TMP/serr"
set -e
grep -q "dispatch feature" "$TMP/sout" || fail "label 'not a bug' should classify as feature: $(cat "$TMP/sout")"
if grep -q "dispatch bug" "$TMP/sout"; then
  fail "word-split labels classified 'not a bug' as bug: $(cat "$TMP/sout")"
fi

# close-linked stays GitHub-on-merge
close_fn="$(fn_body close_linked_issues)"
echo "$close_fn" | grep -q 'gh issue close' || fail "close-linked must stay GitHub issue close"
echo "$close_fn" | grep -q 'closingIssuesReferences' || fail "close-linked must stay GitHub-linked issues"

# PRs, reviews, checks stay on GitHub
grep -q 'gh pr checks' "$FACTORY" || fail "CI should still use gh pr checks"
grep -q 'gh pr view' "$FACTORY" || fail "PR capture should still use gh pr view"
grep -q 'gh pr comment' "$FACTORY" || fail "review comments should still use gh pr comment"

# No Linear or Jira adapter code
if [[ -d "$ROOT/tracker/adapters" ]]; then
  fail "this slice must not add tracker adapter folders"
fi
if grep -RIn -E 'linear\.app/api|api\.linear\.app|atlassian\.net|jira\.com/rest' "$ROOT" --exclude-dir .git --exclude 'tracker.sh'; then
  fail "no Linear or Jira API adapter code"
fi
if grep -RIn -E 'LINEAR_API|JIRA_API|JIRA_TOKEN|LINEAR_KEY' "$ROOT" --exclude-dir .git --exclude 'tracker.sh'; then
  fail "no Linear or Jira API secrets or clients"
fi

# README documents how to point at an issue-tracking MCP connector
grep -qi "MCP" "$ROOT/README.md" || fail "README should document issue-tracking MCP connectors"
grep -q "FACTORY_TRACKER_CMD" "$ROOT/README.md" || fail "README should document FACTORY_TRACKER_CMD"
[[ -f "$ROOT/tracker/CONTRACT.md" ]] || fail "tracker/CONTRACT.md should describe the ticket plug"
grep -q 'Jira are names in' "$ROOT/README.md" && fail "config tracker is github|linear; Jira is FACTORY_TRACKER_CMD only"
grep -q 'Jira are names in' "$ROOT/tracker/CONTRACT.md" && fail "config tracker is github|linear; Jira is FACTORY_TRACKER_CMD only"

# Plug runtime lives next to the contract, not in factory.sh
[[ -f "$ROOT/tracker/tracker.sh" ]] || fail "get/parse/comment should live next to tracker/CONTRACT.md"
grep -q 'tracker/tracker.sh' "$FACTORY" || fail "factory.sh should call tracker/tracker.sh"
if grep -q 'parse_ticket_record' "$FACTORY"; then
  fail "ticket parse should live in tracker/tracker.sh, not factory.sh"
fi
if grep -q 'github_ticket_get' "$FACTORY"; then
  fail "github get should live in tracker/tracker.sh, not factory.sh"
fi
if grep -q 'TRACKER_TEAM' "$FACTORY" "$ROOT/tracker/tracker.sh"; then
  fail "TRACKER_TEAM is unused until something reads it"
fi

echo "ok tracker"
