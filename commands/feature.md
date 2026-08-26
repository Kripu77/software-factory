---
name: feature
description: Implement a ready-for-agent feature ticket in this checkout. Do not expand the ask.
---

Read `lanes/feature.md` and `AGENTS.md`. Follow /tdd, /implement, /unslop.

At start, factory.sh mem read for this issue. Write started only if that read shows no in-progress feature run: factory.sh mem write --lane feature --status started --harness <claude|cursor|codex|grok> --issue <n>. At the end, factory.sh mem write --lane feature --status done|blocked|failed --harness <claude|cursor|codex|grok> --issue <n> --summary "<one sentence>" --evidence <url-or-path> --next-steps "<what should happen next>". That write comments on the GitHub issue. started does not. Missing memory or a comment failure: warn once and continue.

Need a GitHub issue (owner/repo#n or --repo and --issue). New branch off main. Open a PR. Print the URL. Do not merge.
