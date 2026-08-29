---
name: bug
description: Reproduce then TDD-fix a ready-for-agent bug ticket in this checkout. Web bugs get a browser repro first.
---

Read `lanes/bug.md` and `AGENTS.md`. Ask Telemetry for evidence if the ticket has none. Web app bugs: /browser-use first, then /tdd. Use /mermaid when you write a PR.

At start, factory.sh mem read for this issue (or project if no issue). Write started only if that read shows no in-progress bug run: factory.sh mem write --lane bug --status started --harness <claude|cursor|codex|grok> --issue <n>. At the end, factory.sh mem write --lane bug --status done|blocked|failed --harness <claude|cursor|codex|grok> --issue <n> --summary "<one sentence>" --evidence <url-or-path> --next-steps "<what should happen next>". Missing memory: warn once and continue.

Need a GitHub issue. New branch off main. Open a PR. Print the URL. Do not merge.
