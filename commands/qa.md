---
name: qa
description: Smoke or browser-walk a running app. Report only. Do not implement. Do not merge.
---

Read `lanes/qa.md` and `AGENTS.md`. Prefer /run-smoke-tests when a suite exists. Otherwise /browser-use. Report findings. Do not implement. Do not merge.

At start, factory.sh mem read for this issue or PR. Write started only if none in progress: factory.sh mem write --lane qa --status started --harness <claude|cursor|codex|grok> --issue <n>. At the end, factory.sh mem write --lane qa --status done|blocked|failed --harness <claude|cursor|codex|grok> --issue <n> --summary "<one sentence>" --evidence <url-or-path> --next-steps "<what should happen next>". That write comments on the GitHub issue. started does not. Missing memory or a comment failure: warn once and continue.
