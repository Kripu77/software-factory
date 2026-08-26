---
name: telemetry
description: Pull breakage or product-performance evidence. Funnels, feature completion, errors. Do not implement.
---

Read `lanes/telemetry.md` and `telemetry/CONTRACT.md`. Answer the question with evidence only. Name the adapter. Do not classify. Do not invent replays or funnels. Do not merge.

At start, factory.sh mem read for this issue if one was given. Write started only if none in progress: factory.sh mem write --lane telemetry --status started --harness <claude|cursor|codex|grok> --issue <n>. At the end, factory.sh mem write --lane telemetry --status done|blocked|failed --harness <claude|cursor|codex|grok> --issue <n> --summary "<one sentence>" --evidence <url-or-path> --next-steps "<what should happen next>". That write comments on the GitHub issue when an issue is set. started does not. Missing memory or a comment failure: warn once and continue.
