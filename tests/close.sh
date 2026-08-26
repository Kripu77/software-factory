#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FACTORY="$ROOT/factory.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
unset FACTORY_RUNNER

fail() { echo "FAIL: $*" >&2; exit 1; }

WS="$TMP/workspace"
mkdir -p "$WS/widgets"
git -C "$WS/widgets" init -q
git -C "$WS/widgets" remote add origin "https://github.com/acme/widgets.git"

DUMP="$TMP/dump"
mkdir -p "$DUMP" "$TMP/bin"

cat > "$TMP/bin/gh" << 'EOF'
#!/usr/bin/env bash
dump="${FAKE_DUMP:?}"
printf '%s\n' "$*" >> "$dump/gh"
case "$1 $2" in
  "pr view")
    cat "$dump/pr-view"
    ;;
  "issue close")
    printf '%s\n' "$*" >> "$dump/close"
    ;;
  *)
    echo "unexpected gh $*" >&2
    exit 1
    ;;
esac
exit 0
EOF
chmod +x "$TMP/bin/gh"

run_close() {
  PATH="$TMP/bin:$PATH" \
    FAKE_DUMP="$DUMP" \
    FACTORY_WORKSPACE="$WS/widgets" \
    FACTORY_OWNER=acme \
    "$FACTORY" close-linked --repo widgets --pr 40
}

reset_dump() {
  rm -rf "$DUMP"
  mkdir -p "$DUMP"
}

reset_dump
printf '%s\n' '20' >"$DUMP/pr-view"
run_close >"$TMP/out" 2>"$TMP/err"
[[ -f "$DUMP/close" ]] || fail "merged linked PR should close: gh=$(cat "$DUMP/gh") err=$(cat "$TMP/err")"
grep -q 'issue close 20' "$DUMP/close" || fail "merged linked PR should close issue 20: $(cat "$DUMP/close")"
grep -q closingIssuesReferences "$DUMP/gh" || fail "should ask GitHub which issues the PR links: $(cat "$DUMP/gh")"
grep -q 'pr merge' "$DUMP/gh" && fail "close-linked must not merge: $(cat "$DUMP/gh")"

reset_dump
: >"$DUMP/pr-view"
run_close >"$TMP/out" 2>"$TMP/err"
[[ ! -f "$DUMP/close" ]] || fail "empty links must not close: $(cat "$DUMP/close")"
grep -q 'pr view' "$DUMP/gh" || fail "empty links should still view the PR: $(cat "$DUMP/gh")"
grep -q 'pr merge' "$DUMP/gh" && fail "empty links must not merge: $(cat "$DUMP/gh")"

close_fn="$(awk '/^close_linked_issues\(\)/{on=1} on{print} on && /^}$/{exit}' "$FACTORY")"
echo "$close_fn" | grep -q 'mergedAt' || fail "template should emit numbers only when mergedAt is set"
echo "$close_fn" | grep -q 'eq .baseRefName "main"' || fail "template should emit numbers only for base main"
echo "$close_fn" | grep -q 'closingIssuesReferences' || fail "should close GitHub-linked issues, not mention-only"
if echo "$close_fn" | grep -q 'unmerged'; then
  fail "do not invent a merged/unmerged protocol"
fi

fn_body() {
  local name="$1"
  awk -v n="$name" '
    $0 ~ "^" n "\\(\\)" {on=1}
    on {print}
    on && /^}$/ {exit}
  ' "$FACTORY"
}

parse="$(awk '/^if \[\[ "\$LANE" == "mem" \]\]/,/^infer_github/' "$FACTORY")"
if echo "$parse" | grep -q detect_runner; then
  fail "detect_runner belongs where a runner is used, not while parsing flags"
fi
fn_body run_agent | grep -q detect_runner || fail "run_agent should detect_runner"
fn_body run_mem_lane | grep -q detect_runner || fail "run_mem_lane should detect_runner"
fn_body floor_run | grep -q detect_runner || fail "floor_run should detect_runner"

grep -q 'Do not `Closes` until every slice has landed' "$ROOT/AGENTS.md" || fail "AGENTS.md dropped the last-slice Closes rule"

wf="$ROOT/.github/workflows/close-linked.yml"
[[ -f "$wf" ]] || fail "missing .github/workflows/close-linked.yml"
grep -q "pull_request" "$wf" || fail "workflow should run on pull_request"
grep -q "closed" "$wf" || fail "workflow should run when a PR is closed"
grep -q "github.event.pull_request.merged" "$wf" || fail "job should run only when the PR merged"
grep -q "github.event.pull_request.base.ref == 'main'" "$wf" || fail "job should run only for merge to main"
if grep -q "pull_request_target" "$wf"; then
  fail "use pull_request, not pull_request_target"
fi
grep -q "ubuntu-latest" "$wf" || fail "should use GitHub-hosted ubuntu-latest"
if grep -qi "self-hosted" "$wf"; then
  fail "must use GitHub-hosted runners"
fi
grep -q "close-linked" "$wf" || fail "workflow should run factory.sh close-linked"
grep -q "issues: write" "$wf" || fail "workflow needs issues: write to close"
if grep -q "gh pr merge" "$wf" || grep -q "gh merge" "$wf"; then
  fail "workflow must not merge"
fi
if grep -q "\.env" "$wf"; then
  fail "workflow must not touch .env"
fi
if grep -qi "secrets" "$wf"; then
  fail "workflow must not use secrets"
fi

echo "ok close"
