---
name: loop-on-ci
description: Use when watching a dispatched PR until gh pr checks are green. Do not merge.
---

# Loop on CI

`gh pr checks` is the source of truth (not `gh run list`).

1. Resolve the PR.
2. If failed, diagnose those failures first.
3. If pending, `gh pr checks --watch --fail-fast`.
4. Fix the failure on this branch. No `--no-verify`.
5. Re-run `gh pr checks` after every push.

Never merge. If flake, retry once and report evidence. If it is clearly already fixed on main, merge main into the branch instead of bloating the PR.
