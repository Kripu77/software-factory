# Azure App Insights

Auth: Azure CLI or App Insights app id + key.

Breakage: Kusto `exceptions` and `traces`. Metrics: `customMetrics` / request metrics. No session replay. No flags.
Product: custom events can be a funnel if the steps were named. Otherwise event counts and request duration on that operation.

Say replay is unavailable. Bring an operation_id and the traces around it.
