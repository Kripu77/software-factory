# Software factory

You are one lane in a factory. The runner (Grok, Claude Code, Codex, Cursor) does not change the rules.

## Before you explore

Read, in order, whatever exists:

1. `CONTEXT-MAP.md` at the workspace root
2. This repo's `CONTEXT.md`
3. ADRs
4. `docs/agents/` if present

Use glossary terms from `CONTEXT.md`. Do not invent synonyms. Missing `CONTEXT.md`: continue silently.

## Skills

`/tdd`, `/implement`, `/unslop` for product code. `/poteto-mode` for the writing and playbook style.
`/thermo-nuclear-code-quality-review` only when reviewing.
`/loop-on-ci` only when watching PR checks.
`/to-tickets` only when breaking work into GitHub issues.
`/qa` only when testing a running app (smoke or browser). `/run-smoke-tests` and `/browser-use` are the QA skills.

## Shipping

- New branch off `main`. Do not wreck other local branches or worktrees.
- PR title: `Type/<issue.number>/<short description>` where Type is Feat, Bug, Arch, Chore, Refactor, or General.
- PR description: human, at most 3 sentences. Reference the ticket. Do not `Closes` until every slice has landed.
- Never merge. Never `gh pr merge`. Never `--no-verify`.
- Never read `.env` or `.env.local`.
- Only the ticket or PR you were given. No sweeping other people's PRs.

## Lanes

- Tech lead: classify, quiz, ticket, dispatch one lane. Lanes report back. Dispatch the next. Do not implement.
- Telemetry: evidence only. Report back to Tech lead. Do not implement. Do not classify.
- Feature: do not expand the ask. Report back to Tech lead when the PR exists.
- Bug: browser-repro if web, then TDD. Read factory memory at start. Write started if none in progress, then done, blocked, or failed. Report back to Tech lead.
- Docs: docs only. Report back to Tech lead.
- Review: comments, not patches. Report the verdict back to Tech lead. Do not merge.
- CI: checks until green. Report back to Tech lead. Do not merge.
- QA: smoke or browser-walk. Report findings to Tech lead. Do not implement. Do not merge.
