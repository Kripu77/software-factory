#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

fail() { echo "FAIL: $*" >&2; exit 1; }

wf="$ROOT/.github/workflows/tests.yml"
[[ -f "$wf" ]] || fail "missing .github/workflows/tests.yml"

grep -q "pull_request" "$wf" || fail "workflow should run on pull_request"
if grep -q "pull_request_target" "$wf"; then
  fail "use pull_request, not pull_request_target"
fi
grep -q "push" "$wf" || fail "workflow should run on push"
grep -q "main" "$wf" || fail "push should include main"
grep -q "ubuntu-latest" "$wf" || fail "should use GitHub-hosted ubuntu-latest"
if grep -qi "self-hosted" "$wf"; then
  fail "must use GitHub-hosted runners"
fi
grep -q "tests/\*\.sh" "$wf" || fail "should run tests/*.sh"
grep -q "sqlite3" "$wf" || fail "job should provide sqlite3"
grep -q "bash" "$wf" || fail "job should provide bash"
grep -q "git" "$wf" || fail "job should provide git"

if grep -q "gh pr merge" "$wf" || grep -q "gh merge" "$wf"; then
  fail "workflow must not merge"
fi
if grep -q "\.env" "$wf"; then
  fail "workflow must not touch .env"
fi
if grep -qi "secrets" "$wf"; then
  fail "workflow must not use secrets"
fi
if grep -E "continue-on-error:[[:space:]]*true" "$wf"; then
  fail "failing tests must fail the check"
fi
if grep -E 'tests/\*\.sh.*\|\|[[:space:]]*true' "$wf"; then
  fail "failing tests must fail the check"
fi

echo "ok actions"
