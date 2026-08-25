# Telemetry contract

The Telemetry lane does not own a vendor. It answers four questions:

1. What is failing? (errors)
2. What did the system say? (logs)
3. What did the user do? (sessions. Replay if the vendor has it.)
4. Did a flag or metric move? (flags, metrics)

## Adapter

An adapter lives in `telemetry/adapters/<vendor>/README.md`. It says how to auth, which project or app, and one example of each question it can answer.

If the vendor cannot session-replay, the adapter says so and returns logs plus errors. Do not invent a replay.

New vendors are a new adapter folder. Same questions. No new lane.

## Wired adapters

| Vendor | Replay | Errors | Logs | Metrics | Flags |
| --- | --- | --- | --- | --- | --- |
| PostHog | yes | yes | yes | yes | yes |
| Datadog | RUM session | yes | yes | yes | no (use experiments) |
| Azure App Insights | no | yes | yes | yes | no |
| AWS CloudWatch | no | yes (Logs Insights / X-Ray) | yes | yes | no |

CTO asks Telemetry before a Bug dispatch when production data exists. Feature may ask for funnels or flag exposure. Telemetry never merges and never implements product code.
