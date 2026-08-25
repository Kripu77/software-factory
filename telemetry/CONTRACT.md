# Telemetry contract

The Telemetry lane does not own a vendor. It brings evidence for two jobs: something is broken, or something in the product is underperforming.

It does not classify. Drop-off on a path might be a bug or a feature. CTO decides.

## Questions

**Breakage**
1. What is failing? (errors)
2. What did the system say? (logs)
3. What did the user do? (sessions. Replay if the vendor has it.)

**Product performance**
4. Where do people drop? (funnels on any instrumented path, not one screen)
5. Is this feature doing its job? (adoption, completion, time-to-value, error rate on that path)
6. Did a flag or metric move? (flags, metrics)

A funnel is any sequence you care about. Signup is one. So is onboarding, first value, the core loop, invite, checkout, a new feature's happy path. Name the path, the step that dies, the volume, and the window. Do not stop at "conversion is down."

Feature performance is the same idea for one capability: shipped, used, finished, fast enough. A flag at 100% with almost no completions is evidence.

## Adapter

An adapter lives in `telemetry/adapters/<vendor>/README.md`. Auth, which project or app, and one example of breakage plus one of a funnel or feature path.

If the vendor cannot session-replay, say so and return logs plus errors. Do not invent a replay.
If the vendor cannot do product funnels, say so and bring the closest event counts or metrics. Do not invent a funnel.

New vendors are a new adapter folder. Same questions. No new lane.

## Wired adapters

| Vendor | Replay | Errors | Logs | Metrics | Flags | Funnels |
| --- | --- | --- | --- | --- | --- | --- |
| PostHog | yes | yes | yes | yes | yes | yes |
| Datadog | RUM session | yes | yes | yes | no (experiments) | RUM / product analytics if on |
| Azure App Insights | no | yes | yes | yes | no | custom events, if you named the steps |
| AWS CloudWatch | no | yes (Logs Insights / X-Ray) | yes | yes | no | no (counts and latency only) |

CTO asks Telemetry before dispatching a Bug when production data exists, and when a Feature might be a performance or drop-off problem rather than a request. Telemetry never merges and never implements product code.
