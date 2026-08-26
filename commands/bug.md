---
name: bug
description: Reproduce then TDD-fix a ready-for-agent bug ticket in this checkout. Web bugs get a browser repro first.
---

Read `lanes/bug.md` and `AGENTS.md`. Ask Telemetry for evidence if the ticket has none. Web app bugs: /browser-use first, then /tdd.

At start, factory.sh mem read for this issue (or project if no issue). Near the beginning, factory.sh mem write --lane bug --status started. At the end, factory.sh mem write --lane bug --status done, blocked, or failed from the outcome. Missing memory: warn once and continue.

Need a GitHub issue. New branch off main. Open a PR. Print the URL. Do not merge.
