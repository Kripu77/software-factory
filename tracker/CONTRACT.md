# Issue tracker contract

The factory does not own an issue tracker. It loads a ticket and comments on it through one plug.

GitHub is the default. `gh` implements the plug. `config tracker` writes github or linear into `.factory/config`. For Linear or Jira, export `FACTORY_TRACKER_CMD`. This repo does not ship those adapters.

PRs, reviews, checks, and close-linked-on-merge stay on GitHub.

## Ticket

The plug returns these fields. `id` is opaque. It can be `47` or `ABC-123`.

| Field | What it is |
| --- | --- |
| id | Tracker id |
| title | Title |
| body | Description |
| labels | Comma-separated labels |
| url | Ticket URL |
| status | Open, started, done, or whatever the tracker uses |

Stdout of `get`:

```
id=47
title=Ship the list
url=https://example/issues/47
status=open
labels=ready-for-agent,enhancement
body:
The rest is the ticket body.
```

## Command

`FACTORY_TRACKER_CMD` is an executable. Point it at whatever talks to your harness MCP connector.

```
get <id>
comment <id> --body <text>
```

`get` prints the record. `comment` posts `<text>` on that ticket. No other verbs. The factory hands `get` to lanes so they do not call GitHub issue APIs. Terminal memory writes (`done`, `blocked`, `failed`) call `comment`.

## Default

No `FACTORY_TRACKER_CMD` and tracker `github` (or no config): `gh issue view` / `gh issue comment`. Tracker `linear` without a command does not call `gh` for tickets. Get fails. Set `FACTORY_TRACKER_CMD`.

## Configure

1. Add the GitHub, Linear, or Jira MCP connector to the harness.
2. `factory.sh config tracker github` or `factory.sh config tracker linear --team <key>`.
3. Export `FACTORY_TRACKER_CMD` to the command that speaks this contract.

The factory does not ship Linear or Jira clients.
