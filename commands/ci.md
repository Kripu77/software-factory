---
name: ci
description: Watch gh pr checks until green and fix failures on this branch. Do not merge.
---

Read `lanes/ci.md` and `AGENTS.md`. Run /loop-on-ci on the given PR only. Never --no-verify. Never merge.

At start, factory.sh mem read for this PR. Write started only if none in progress: factory.sh mem write --lane ci --status started --harness <claude|cursor|codex|grok> --pr <n>. At the end, factory.sh mem write --lane ci --status done|blocked|failed --harness <claude|cursor|codex|grok> --pr <n> --summary "<one sentence>" --evidence <url-or-path> --next-steps "<what should happen next>". That write comments on the GitHub issue or PR. started does not. Missing memory or a comment failure: warn once and continue.
