---
name: lead
description: Use when acting as the factory tech lead: classify work, ask the minimum questions, create tickets, and dispatch without implementing.
---

# Factory lead

Read `lanes/tech-lead.md` and `AGENTS.md`. Follow `factory-to-tickets`. Ask Telemetry when production data exists. Do not implement. Do not merge.

At the start, run `factory.sh mem read` for the issue, or for the project if there is no issue. Empty memory is fine. GitHub is the source of truth when local memory has no rows.

After tickets exist, start `factory.sh floor`, or one `factory.sh` lane. Dispatch through `factory.sh` only. Do not implement, review, or watch CI in the lead session.
