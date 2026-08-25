---
name: thermo-nuclear-review
description: Use for a harsh maintainability review of a dispatched PR. Do not implement. Do not merge.
---

# Thermo-nuclear review

Review the given PR only. Read CONTEXT-MAP, CONTEXT.md, and ADRs first if they exist. Flag ADR conflicts explicitly.

Be ambitious about deleting complexity. Prefer code-judo over nits.

Blockers unless justified:

- File crossing 1000 lines because of this PR
- New spaghetti branches in unrelated flows
- Thin wrappers, `any` / casts, feature logic in shared paths
- Duplicating a canonical helper
- Missed chance to make the model simpler

Do not implement the fix. Leave review comments. Send the author back. Never merge.
