#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FACTORY="$ROOT/factory.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export FACTORY_MEMORY_DB="$TMP/memory/factory.db"
unset FACTORY_RUNNER
unset FACTORY_SKIP_TICKET_COMMENT

fail() { echo "FAIL: $*" >&2; exit 1; }

need_text() {
  local file="$1" pat="$2"
  grep -q -- "$pat" "$ROOT/$file" || fail "$file missing /$pat/"
}

bytes_under() {
  local file="$1" max="$2" n
  n="$(wc -c < "$ROOT/$file" | tr -d ' ')"
  [[ "$n" -lt "$max" ]] || fail "$file is $n bytes, stay under $max"
}

fn_body() {
  local name="$1"
  awk -v n="$name" '
    $0 ~ "^" n "\\(\\)" {on=1}
    on {print}
    on && /^}$/ {exit}
  ' "$ROOT/factory.sh"
}

playbook() {
  local lane="$1" cmd="$2"
  need_text "lanes/${lane}.md" "mem read"
  need_text "lanes/${lane}.md" "mem write"
  need_text "lanes/${lane}.md" "started"
  need_text "lanes/${lane}.md" "done"
  need_text "lanes/${lane}.md" "blocked"
  need_text "lanes/${lane}.md" "failed"
  need_text "lanes/${lane}.md" "warn once"
  need_text "lanes/${lane}.md" "Tech lead"
  need_text "lanes/${lane}.md" "Do not dispatch"
  need_text "lanes/${lane}.md" "in-progress"
  need_text "commands/${cmd}.md" "mem read"
  need_text "commands/${cmd}.md" "mem write"
  need_text "commands/${cmd}.md" "started"
  need_text "commands/${cmd}.md" "done"
  need_text "commands/${cmd}.md" "--harness"
  need_text "commands/${cmd}.md" "--summary"
  need_text "commands/${cmd}.md" "--evidence"
  need_text "commands/${cmd}.md" "--next-steps"
  need_text "commands/${cmd}.md" "comment"
  bytes_under "lanes/${lane}.md" 1000
  bytes_under "commands/${cmd}.md" 1000
  if grep -q -- "--summary" "$ROOT/lanes/${lane}.md"; then
    fail "put mem flags in /${cmd}, not ${lane} lane"
  fi
}

if grep -q "disable-model-invocation: true" "$ROOT/skills/thermo-nuclear-review/SKILL.md"; then
  fail "review lane mandates /thermo-nuclear-code-quality-review but the skill blocks model invocation"
fi

playbook feature feature
playbook docs docs
playbook qa qa
playbook review review
playbook ci ci
playbook telemetry telemetry

if grep -Eq "bug_mem_start|bug_mem_finish|bug_mem_write|bug_latest_status" "$ROOT/factory.sh"; then
  fail "fold bug into run_mem_lane"
fi

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
own=()
if [[ -z "${AGENT_NO_OWNER:-}" ]]; then
  own=(--owner acme --repo widgets)
fi
if [[ -n "${AGENT_MEM_START:-}" ]]; then
  "${FACTORY_SH:?}" mem write --lane "${AGENT_LANE:?}" --status started --harness grok ${AGENT_ISSUE:+--issue "$AGENT_ISSUE"} ${AGENT_PR:+--pr "$AGENT_PR"} --project acme/widgets "${own[@]}" >/dev/null
fi
if [[ -n "${AGENT_MEM_STATUS:-}" ]]; then
  "${FACTORY_SH:?}" mem write --lane "${AGENT_LANE:?}" --status "$AGENT_MEM_STATUS" --harness grok ${AGENT_ISSUE:+--issue "$AGENT_ISSUE"} ${AGENT_PR:+--pr "$AGENT_PR"} --project acme/widgets "${own[@]}" --summary "${AGENT_SUMMARY:-Lane finished}" --evidence "${AGENT_EVIDENCE:-https://github.com/acme/widgets/issues/6}" --next-steps "${AGENT_NEXT:-Tech lead dispatches the next lane}" >/dev/null
fi
exit "${AGENT_EXIT:-0}"
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
if [[ "${GH_FAIL:-}" == 1 && "$cmd1" == "issue" && "$cmd2" == "comment" ]]; then
  echo "comment failed" >&2
  exit 1
fi
exit 0
EOF
chmod +x "$TMP/bin/gh"

run_env() {
  PATH="$TMP/bin:$PATH" \
    FAKE_DUMP="$DUMP" \
    FACTORY_SH="$FACTORY" \
    FACTORY_WORKSPACE="$WS" \
    FACTORY_OWNER=acme \
    FACTORY_RUNNER=runner FACTORY_HARNESS=claude \
    "$@"
}

run_feature() { run_env "$FACTORY" feature --repo widgets --issue 6; }

gh_count() {
  if [[ -f "$DUMP/gh" ]]; then
    grep -c "comment" "$DUMP/gh" || true
  else
    echo 0
  fi
}

last_comment() {
  if [[ -f "$DUMP/comment-body" ]]; then
    cat "$DUMP/comment-body"
  fi
}

assert_news_body() {
  local body line
  body="$(last_comment)"
  [[ -n "$body" ]] || fail "comment body empty"
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      done|blocked|failed) fail "comment has status word: $body" ;;
    esac
    case "$line" in
      \#*) fail "comment has # heading: $body" ;;
    esac
    case "$line" in
      *'/issues/'*) fail "comment has issue self-link: $body" ;;
    esac
    case "$line" in
      '['*']('*) ;;
      '['*) fail "comment has JSON evidence: $body" ;;
    esac
    case "$line" in
      *'Tech lead dispatches'*|*'A person merges'*) fail "comment has factory liturgy: $body" ;;
    esac
  done <<< "$body"
}

# started does not comment
rm -rf "$DUMP" "$TMP/memory"
mkdir -p "$DUMP"
run_env "$FACTORY" mem write --lane feature --status started --harness grok --issue 6 --owner acme --repo widgets --project acme/widgets --summary "Start feature" >/dev/null
[[ "$(gh_count)" == "0" ]] || fail "started must not comment: $(cat "$DUMP/gh")"

# Terminal done comments once: summary, blank line, markdown PR link
run_env "$FACTORY" mem write --lane feature --status done --harness grok --issue 6 --owner acme --repo widgets --project acme/widgets --summary "Shipped the list" --evidence "https://github.com/acme/widgets/pull/40" --next-steps "Review the PR" >/dev/null
[[ "$(gh_count)" == "1" ]] || fail "done should comment once, got $(gh_count): $(cat "$DUMP/gh")"
grep -q "issue comment 6" "$DUMP/gh" || fail "done should gh issue comment: $(cat "$DUMP/gh")"
assert_news_body
want=$'Shipped the list\n\n[PR 40](https://github.com/acme/widgets/pull/40)'
got="$(last_comment)"
[[ "$got" == "$want" ]] || fail "comment body want $(printf %q "$want") got $(printf %q "$got")"
pr="$(sqlite3 "$FACTORY_MEMORY_DB" "SELECT pr FROM runs WHERE issue = '6' ORDER BY id DESC LIMIT 1;")"
[[ "$pr" == "40" ]] || fail "write should lift pull evidence into pr, got $pr"

# --project fills owner/repo; pull evidence fills PR; comment uses pr_url
rm -rf "$DUMP" "$TMP/memory"
mkdir -p "$DUMP"
PATH="$TMP/bin:$PATH" \
  FAKE_DUMP="$DUMP" \
  FACTORY_SH="$FACTORY" \
  FACTORY_WORKSPACE="$WS" \
  FACTORY_RUNNER=runner FACTORY_HARNESS=claude \
  "$FACTORY" mem write --lane feature --status done --harness grok --issue 8 --project acme/widgets \
    --summary "Shipped from project" --evidence "https://github.com/acme/widgets/pull/40" >/dev/null
assert_news_body
want=$'Shipped from project\n\n[PR 40](https://github.com/acme/widgets/pull/40)'
got="$(last_comment)"
[[ "$got" == "$want" ]] || fail "project-only comment want $(printf %q "$want") got $(printf %q "$got")"
pr="$(sqlite3 "$FACTORY_MEMORY_DB" "SELECT pr FROM runs WHERE issue = '8';")"
[[ "$pr" == "40" ]] || fail "project-only write should lift pr, got $pr"

# Bug writes do not comment
rm -f "$DUMP/gh" "$DUMP/comment-body"
run_env "$FACTORY" mem write --lane bug --status done --harness grok --issue 6 --owner acme --repo widgets --project acme/widgets --summary "Fixed it" --evidence "https://github.com/acme/widgets/issues/6" >/dev/null
[[ "$(gh_count)" == "0" ]] || fail "bug must not comment: $(cat "$DUMP/gh")"

# Review comments on the PR
rm -f "$DUMP/gh" "$DUMP/comment-body"
run_env "$FACTORY" mem write --lane review --status done --harness grok --pr 40 --owner acme --repo widgets --project acme/widgets --summary "Left review comments" --evidence "https://github.com/acme/widgets/pull/40" --next-steps "CI" >/dev/null
grep -q "pr comment 40" "$DUMP/gh" || fail "review should gh pr comment: $(cat "$DUMP/gh")"
assert_news_body
want=$'Left review comments\n\n[PR 40](https://github.com/acme/widgets/pull/40)'
got="$(last_comment)"
[[ "$got" == "$want" ]] || fail "review comment body want $(printf %q "$want") got $(printf %q "$got")"

# Missing DB: feature still runs, finish writes done and comments
rm -rf "$DUMP" "$TMP/memory"
mkdir -p "$DUMP"
set +e
run_feature >"$TMP/out" 2>"$TMP/err"
code=$?
set -e
[[ $code -eq 0 ]] || fail "missing db feature exit $code err=$(cat "$TMP/err")"
[[ -f "$DUMP/ran" ]] || fail "missing db should still run feature"
grep -q "recently-merged example" "$DUMP/rules" || fail "feature rules missing ratify-off-example rule"
warns="$(grep -c "factory.db\|factory memory" "$TMP/err" || true)"
[[ "$warns" == "1" ]] || fail "missing db should warn once, got $warns: $(cat "$TMP/err")"
status="$(sqlite3 "$FACTORY_MEMORY_DB" "SELECT status FROM runs WHERE lane = 'feature' ORDER BY id DESC LIMIT 1;")"
[[ "$status" == "done" ]] || fail "feature finish should be done, got $status"
[[ "$(gh_count)" == "1" ]] || fail "feature finish should comment once, got $(gh_count)"
grep -q "acme/widgets" "$DUMP/prompt" || true

# Second feature run sees prior memory
rm -rf "$DUMP"
mkdir -p "$DUMP"
run_feature >"$TMP/out2" 2>"$TMP/err2"
grep -q "status = done" "$DUMP/prompt" || fail "second feature should see first run: $(cat "$DUMP/prompt")"

# Agent started then blocked: one row, one comment, no extra done
rm -rf "$DUMP" "$TMP/memory"
mkdir -p "$DUMP"
AGENT_LANE=feature AGENT_ISSUE=6 AGENT_MEM_START=1 AGENT_MEM_STATUS=blocked AGENT_SUMMARY="Need a human" \
  run_feature >"$TMP/bout" 2>"$TMP/berr"
status="$(sqlite3 "$FACTORY_MEMORY_DB" "SELECT status FROM runs WHERE lane = 'feature' ORDER BY id DESC LIMIT 1;")"
count="$(sqlite3 "$FACTORY_MEMORY_DB" "SELECT COUNT(*) FROM runs WHERE lane = 'feature';")"
[[ "$status" == "blocked" ]] || fail "blocked should stick, got $status"
[[ "$count" == "1" ]] || fail "started then blocked should be one row, count=$count"
[[ "$(gh_count)" == "1" ]] || fail "blocked should comment once, got $(gh_count): $(cat "$DUMP/gh" 2>/dev/null || true)"
assert_news_body
[[ "$(last_comment)" == "Need a human" ]] || fail "blocked comment should be the summary, got $(last_comment)"

# Agent done without --owner still comments once from finish
rm -rf "$DUMP" "$TMP/memory"
mkdir -p "$DUMP"
AGENT_LANE=feature AGENT_ISSUE=6 AGENT_MEM_STATUS=done AGENT_NO_OWNER=1 AGENT_SUMMARY="Shipped without owner flags" \
  run_feature >"$TMP/nout" 2>"$TMP/nerr"
[[ "$(gh_count)" == "1" ]] || fail "finish should comment when agent omitted owner, got $(gh_count): $(cat "$DUMP/gh" 2>/dev/null || true)"
grep -q "issue comment 6" "$DUMP/gh" || fail "finish comment should be issue comment: $(cat "$DUMP/gh")"
assert_news_body

# factory.sh review writes memory and comments on the PR
rm -rf "$DUMP" "$TMP/memory"
mkdir -p "$DUMP"
AGENT_LANE=review AGENT_PR=40 run_env "$FACTORY" review --repo widgets --pr 40 >"$TMP/rout" 2>"$TMP/rerr"
rstatus="$(sqlite3 "$FACTORY_MEMORY_DB" "SELECT status FROM runs WHERE lane = 'review' ORDER BY id DESC LIMIT 1;")"
[[ "$rstatus" == "done" ]] || fail "review finish should be done, got $rstatus"
grep -q "pr comment 40" "$DUMP/gh" || fail "review finish should gh pr comment: $(cat "$DUMP/gh" 2>/dev/null || true)"
grep -q "recently-merged example" "$DUMP/rules" || fail "review rules missing ratify-off-example rule"

# Comment failure does not fail the lane
rm -rf "$DUMP" "$TMP/memory"
mkdir -p "$DUMP"
run_env "$FACTORY" mem write --lane feature --status started --harness grok --issue 6 --owner acme --repo widgets --project acme/widgets >/dev/null
rm -rf "$DUMP"
mkdir -p "$DUMP"
set +e
GH_FAIL=1 run_feature >"$TMP/fout" 2>"$TMP/ferr"
fcode=$?
set -e
[[ $fcode -eq 0 ]] || fail "comment failure should not fail feature, exit $fcode err=$(cat "$TMP/ferr")"
[[ -f "$DUMP/ran" ]] || fail "comment failure should still run feature"
grep -qi "comment" "$TMP/ferr" || fail "comment failure should warn: $(cat "$TMP/ferr")"

# Telemetry without issue: mem write, no comment
rm -rf "$DUMP" "$TMP/memory"
mkdir -p "$DUMP"
run_env "$FACTORY" telemetry --question "where does signup die" --repo widgets >"$TMP/tout" 2>"$TMP/terr"
tstatus="$(sqlite3 "$FACTORY_MEMORY_DB" "SELECT status FROM runs WHERE lane = 'telemetry' ORDER BY id DESC LIMIT 1;")"
[[ "$tstatus" == "done" ]] || fail "telemetry should finish done, got $tstatus"
[[ "$(gh_count)" == "0" ]] || fail "telemetry without issue must not comment: $(cat "$DUMP/gh" 2>/dev/null || true)"

# Empty summary: no comment
rm -rf "$DUMP" "$TMP/memory"
mkdir -p "$DUMP"
run_env "$FACTORY" mem write --lane feature --status done --harness grok --issue 6 --owner acme --repo widgets --project acme/widgets >/dev/null
[[ "$(gh_count)" == "0" ]] || fail "empty summary must not comment: $(cat "$DUMP/gh")"

# Wrapper does not comment again after the lane already wrote a terminal status
rm -rf "$DUMP" "$TMP/memory"
mkdir -p "$DUMP"
AGENT_LANE=feature AGENT_ISSUE=6 AGENT_MEM_STATUS=done AGENT_SUMMARY="Shipped the list" \
  AGENT_EVIDENCE="https://github.com/acme/widgets/pull/40" AGENT_NEXT="Tech lead dispatches the next lane" \
  run_feature >"$TMP/wout" 2>"$TMP/werr"
[[ "$(gh_count)" == "1" ]] || fail "agent finish should comment once, got $(gh_count): $(cat "$DUMP/gh" 2>/dev/null || true)"
assert_news_body
want=$'Shipped the list\n\n[PR 40](https://github.com/acme/widgets/pull/40)'
got="$(last_comment)"
[[ "$got" == "$want" ]] || fail "wrapper must not replace the agent comment, want $(printf %q "$want") got $(printf %q "$got")"

# Default --next-steps is not dispatch or merge liturgy
grep -q "Tech lead dispatches the next lane" "$ROOT/factory.sh" && fail "default --next-steps still says Tech lead dispatches"
grep -n -- "--next-steps" "$ROOT/factory.sh" | grep -q "A person merges" && fail "default --next-steps still says A person merges"

# README public ledger is the comment, not status-plus-next-steps
grep -q "status, URL, evidence, what next" "$ROOT/README.md" && fail "README still describes status-plus-next-steps as the ledger"
grep -qiE 'your device|this device|another device' "$ROOT/README.md" && fail "README still says device"
grep -qF '**Local.**' "$ROOT/README.md" || fail "README should call sqlite local memory"
grep -qF '**GitHub.**' "$ROOT/README.md" || fail "README should call the GitHub comment the public ledger"

fn_body ticket_comment | grep -q 'PROJECT%%' && fail "ticket_comment must not split PROJECT"
fn_body ticket_comment | grep -q grep && fail "ticket_comment must not grep evidence"
fn_body ticket_comment | grep -q 'local .*pr_url' && fail "ticket_comment must not shadow pr_url"
fn_body detect_project | grep -q 'OWNER=.*PROJECT' || fail "detect_project should fill OWNER from PROJECT"
fn_body detect_project | grep -q 'REPO=.*PROJECT' || fail "detect_project should fill REPO from PROJECT"
fn_body lane_mem_finish | grep -q FACTORY_SKIP_TICKET_COMMENT && fail "lane_mem_finish leftover skip unset"

echo "ok lanes"
