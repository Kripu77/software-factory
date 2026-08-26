---
name: review
description: Harsh maintainability review of one PR. Comments, not patches. Do not merge.
---

Read `lanes/review.md` and `AGENTS.md`. Run /thermo-nuclear-code-quality-review on the given PR only. Leave GitHub review comments. Do not implement. Do not merge.

At start, factory.sh mem read for this PR. Write started only if none in progress: factory.sh mem write --lane review --status started --harness <claude|cursor|codex|grok> --pr <n>. At the end, factory.sh mem write --lane review --status done|blocked|failed --harness <claude|cursor|codex|grok> --pr <n> --summary "<one sentence>" --evidence <url-or-path> --next-steps "<what should happen next>". That write comments on the GitHub issue or PR. started does not. Missing memory or a comment failure: warn once and continue.
