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

## Shipping

- New branch off `main`. Do not wreck other local branches or worktrees.
- PR title: `Type/<issue.number>/<short description>` where Type is Feat, Bug, Arch, Chore, Refactor, or General.
- PR description: human, at most 3 sentences. Reference the ticket. Do not `Closes` until every slice has landed.
- Never merge. Never `gh pr merge`. Never `--no-verify`.
- Never read `.env` or `.env.local`.
- Only the ticket or PR you were given. No sweeping other people's PRs.

## Lanes

- Tech lead: classify, quiz, ticket, dispatch. Do not implement.
- Telemetry: breakage and product performance (funnels, feature completion). Evidence only. Do not implement product code. Do not classify.
- Feature: do not expand the ask.
- Bug: reproduce, then TDD fix.
- Docs: docs only, no application code.
- Review: do not implement the fix. Send comments. Do not merge.
- CI: fix check failures only. Do not merge.
