---
name: implement
description: Use when implementing a spec or GitHub ticket in this checkout.
---

# Implement

Implement only the ticket you were given.

1. Read CONTEXT-MAP, this repo CONTEXT.md, ADRs, docs/agents if they exist.
2. Find a similar, recently-merged example in this repo (a file or PR doing the same kind of thing) and match its patterns. If none exists, say so in the PR description.
3. Use `/tdd` at pre-agreed seams.
4. Typecheck often. Run focused tests often. Full suite once at the end.
5. `/unslop` against main.
6. Open or update a PR. Do not merge.
7. Stop and ask for `/thermo-nuclear-code-quality-review` then `/loop-on-ci`.

## Extra rules

- No code comments
- Small focused changes
- Do not refactor adjacent code unless the ticket says so
- No type assertions; follow local TypeScript/Go practice
- PR title: `Type/<issue.number>/<short description>` (Feat, Bug, Arch, Chore, Refactor, General)
- PR description: human, at most 3 sentences
- Never merge. A person merges.
