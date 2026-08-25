# Software factory

One agent doing the whole job is an intern with admin. A factory is lanes, a ticket, and a human who merges.

Build software this way: classify the work, cut tracer-bullet tickets, implement on the checkout, smoke it in a browser, review like you hate the PR, watch CI until green. Then a person merges. Agents never merge.

The runner is a plug. Grok, Claude Code, Codex, Cursor. Same `AGENTS.md`, same skills.

Telemetry is a plug too. It is not an error inbox. It watches breakage and whether the product is actually working: funnels on any path, feature completion, time-to-value. Signup drop-off is one signal. So is onboarding, checkout, invite, the core loop, or a shipped feature nobody finishes. PostHog, Datadog, Azure App Insights, CloudWatch speak the same contract. Swap the vendor. Keep the questions.

![Software factory](docs/factory.png)

Editable source: [`docs/factory.excalidraw`](docs/factory.excalidraw).

## Lanes

| Lane | Job |
| --- | --- |
| Tech lead | Classify. Quiz. Ticket on the owning repo. Dispatch. Do not implement. |
| Telemetry | Breakage and product performance. Funnels, feature completion, errors, logs, sessions. Evidence only. Never implements. |
| Bug | Reproduce from evidence. Web bugs: browser first, then TDD fix. |
| Feature | Do not expand the ask. TDD, implement, unslop. |
| Docs | Docs only. |
| Review | Harsh maintainability review. Comments, not patches. |
| CI | `gh pr checks` until green. Failures only. |
| QA | Smoke or browser-walk a running app. Report only. |

## Install

```bash
git clone https://github.com/Kripu77/software-factory.git
cd software-factory
./install.sh
```

One pack. Four harnesses.

| Harness | How it loads |
| --- | --- |
| Cursor | local plugin at `~/.cursor/plugins/local/software-factory` |
| Claude Code | skills + slash commands under `~/.claude` |
| Grok Build | plugin at `~/.grok/plugins/software-factory` (`grok plugin install . --trust`) |
| Codex | skills under `~/.codex/skills` plus `AGENTS.md` in the checkout |

Then set the product checkout:

```bash
export FACTORY_WORKSPACE=/path/to/your/checkout
export FACTORY_OWNER=your-github-org
```

## Run

In Cursor, Claude, Grok, or Codex, invoke the lane:

- `/feature` with owner/repo#issue
- `/bug` with owner/repo#issue
- `/review` with owner/repo#pr
- `/ci` with owner/repo#pr
- `/qa` with a URL or owner/repo#pr
- `/telemetry` with the question
- `/lead` to classify and ticket
- `/unslop` on any writing
- `/poteto-mode` for the writing and playbook style

Headless / CI still uses the script (never merges):

```bash
./factory.sh feature --repo api --issue 12
./factory.sh bug     --repo api --issue 13
./factory.sh review  --repo api --pr 40
./factory.sh ci      --repo api --pr 40
./factory.sh telemetry --question "login 500s last 24h"
./factory.sh telemetry --question "where does onboarding die, last 7d"
./factory.sh qa --repo frontend --pr 12 --url http://localhost:3000
```

## Hard rules

- Never merge. A person merges.
- Never `git commit --no-verify`.
- Never read or send `.env` / `.env.local`.
- Only the ticket or PR you were given.
- Issues live on the owning service, not a catch-all.
- PR title: `Type/<issue.number>/<short description>` (`Feat`, `Bug`, `Arch`, `Chore`, `Refactor`, `General`).

## Telemetry

See [`telemetry/CONTRACT.md`](telemetry/CONTRACT.md). Breakage and product performance. Funnels are any instrumented path, not one screen. Session replay is optional. If the vendor cannot replay or cannot funnel, say so. Do not invent either.
