---
name: docs
description: Docs-only change for a ready-for-agent ticket. No application code.
---

Read `lanes/docs.md` and `AGENTS.md`. Need a GitHub issue. Open a PR. Use /mermaid when you write a PR. Do not merge.

At start, factory.sh mem read for this issue. Write started only if that read shows no in-progress docs run: factory.sh mem write --lane docs --status started --harness <claude|cursor|codex|grok> --issue <n>. At the end, factory.sh mem write --lane docs --status done|blocked|failed --harness <claude|cursor|codex|grok> --issue <n> --summary "<one sentence>" --evidence <url-or-path> --next-steps "<what should happen next>". That write comments on the GitHub issue. started does not. Missing memory or a comment failure: warn once and continue.
