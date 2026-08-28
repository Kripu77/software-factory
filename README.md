# Software factory

One agent doing the whole job is an intern with admin. A factory is lanes, a ticket, and a human who merges.

Classify the work. Cut tracer-bullet tickets. Implement on the checkout. Smoke it in a browser. Review like you hate the PR. Watch CI until green. A person merges. Agents never merge.

The runner is a plug. Grok, Claude Code, Codex, Cursor. Same `AGENTS.md`, same skills.

Telemetry is a plug too. Not an error inbox. It answers whether a path broke or a feature died: signup, onboarding, checkout, invite, the core loop, a shipped screen nobody finishes. PostHog, Datadog, Azure App Insights, and CloudWatch all speak [`telemetry/CONTRACT.md`](telemetry/CONTRACT.md). Swap the vendor. Keep the questions.


![Software factory](docs/factory.png)


## How it runs

Open one CLI. `/lead` or `factory.sh lead` classifies, quizzes, and tickets. It does not write product code. After tickets exist it starts `factory.sh floor`. If the lead session implements, reviews, or watches CI, that run failed.

Floor is bash. It starts one isolated `factory.sh` lane, waits, then starts the next. Each worker is a new process with that lane's rules. Floor does not implement. Floor does not merge.

Order is implement (feature, bug, or docs), then QA if you passed a URL, else skip QA, then review, then CI. Telemetry runs first when the ticket looks like breakage or drop-off and nobody has pulled evidence yet. Stop when a person should merge, or a lane reports `blocked` or `failed`.

Lanes report back. They do not dispatch the next lane. Tech lead or floor does.

Cursor is a slash-command door, not a `factory.sh --runner`. `/lead` in Cursor starts `factory.sh`, which needs Claude, Codex, or Grok on PATH. Two of those installed means you set `FACTORY_RUNNER` or `--runner`. One installed means `factory.sh` uses it. It does not prefer Grok.

## Handoff and hand back

Two ledgers. Keep them apart.

**Local.** `factory.sh mem write` and `mem read` hit `~/.factory/memory/factory.db`. The next `/bug` or `factory.sh feature` reads those rows at start. A worker writes `started` only if nothing is in progress, then `done`, `blocked`, or `failed`. If the db is missing, warn once and continue. Optional. Best-effort. Not git. Never `.env`.

**GitHub.** On `done`, `blocked`, or `failed` (not `started`), the write leaves one GitHub comment. The body is the one-sentence summary. When a PR exists, a blank line, then a markdown link `[PR n](url)`. That comment is the public ledger. Tech lead reads GitHub when local memory has no rows. Memory is a hint, not a lock.

Floor asks GitHub whether there is a PR, a review, and green checks. It asks local memory for `blocked` / `failed` and for "QA was skipped, no URL."

## Lanes

| Lane | Job |
| --- | --- |
| Tech lead | Classify. Quiz. Ticket. Dispatch via `factory.sh` (usually floor). Do not implement. |
| Telemetry | Breakage and product performance. Funnels, feature completion, errors, logs, sessions. Evidence only. Never implements. |
| Bug | Reproduce from evidence. Web bugs: browser first, then TDD fix. |
| Feature | Do not expand the ask. TDD, implement, unslop. |
| Docs | Docs only. |
| Review | Harsh maintainability review. Comments, not patches. |
| CI | `gh pr checks` until green. Failures only. |
| QA | Smoke or browser-walk a running app. Report only. |

## Install

Add this GitHub repo as a marketplace and install software-factory at the Release tag. Not main.

Claude Code:

```
/plugin marketplace add Kripu77/software-factory@v1.1.1
/plugin install software-factory@software-factory
```

Grok Build:

```
grok plugin install Kripu77/software-factory@v1.1.1 --trust
```

Or add this repo as a marketplace at tag `v1.1.1`, then install software-factory.

Codex:

```
codex plugin marketplace add Kripu77/software-factory@v1.1.1
codex plugin add software-factory@software-factory
```

Cursor:

Add GitHub marketplace `Kripu77/software-factory` at tag `v1.1.1`, then install software-factory.

`/lead` loads. So do the other factory commands. Codex gets the skills.

Clone plus `./install.sh` is the from-source path:

```bash
git clone https://github.com/Kripu77/software-factory.git
cd software-factory
./install.sh
```

That creates `~/.factory/memory`, installs the plugin, and puts `factory` on `~/.local/bin`. Codex: `./install.sh /path/to/your-checkout` also writes `AGENTS.md` there. Then:

```bash
cd /path/to/your-checkout
factory setup
grok          # or claude
/lead
```

The versioned pack is on GitHub Releases. Set plugin versions in `.claude-plugin/plugin.json`, `.cursor-plugin/plugin.json`, `.grok-plugin/plugin.json`, and `.codex-plugin/plugin.json` to the tag without the `v`, then:

```bash
git tag v1.1.1
git push origin v1.1.1
```

Tag and push. A push to main does not cut a Release.

Owner and repo come from `git remote`. Workspace is this directory. Put `~/.local/bin` on PATH if `factory` is missing. Two of claude, codex, grok on PATH: set `FACTORY_RUNNER`.

| Harness | How it loads |
| --- | --- |
| Cursor | GitHub marketplace at the Release tag, or local plugin at `~/.cursor/plugins/local/software-factory` |
| Claude Code | marketplace plugin at the Release tag, or skills + slash commands under `~/.claude` |
| Grok Build | GitHub shorthand at the Release tag, or `grok plugin install . --trust` from a clone |
| Codex | marketplace plugin at the Release tag, or skills under `~/.codex/skills` plus `AGENTS.md` |

## Run

Start at lead:

- `/lead` with owner/repo#issue

Or one lane, still one ticket:

- `/feature` with owner/repo#issue
- `/bug` with owner/repo#issue
- `/review` with owner/repo#pr
- `/ci` with owner/repo#pr
- `/qa` with a URL or owner/repo#pr
- `/telemetry` with the question
- `/unslop` on any writing

Headless. Never merges.

```bash
./factory.sh lead   --repo api --issue 12
./factory.sh floor  --repo api --issue 12
./factory.sh feature --repo api --issue 12
./factory.sh bug     --repo api --issue 13
./factory.sh review  --repo api --pr 40
./factory.sh ci      --repo api --pr 40
./factory.sh telemetry --question "login 500s last 24h"
./factory.sh qa --repo frontend --pr 12 --url http://localhost:3000
./factory.sh mem write --lane feature --status started --issue 12 --harness grok --summary "Add the memory store"
./factory.sh mem read --issue 12
./factory.sh setup
./factory.sh config tracker linear --team ABC
./factory.sh config skills "euc-go: Go services" "euc-sql: migrations"
./factory.sh config
```

`factory setup` is the human path. From a product checkout it walks tracker and skills one stage at a time, shows a review, then writes through the same files as `factory.sh config`. Existing config is detected so you can update or keep it. Skip a section to keep the default. Cancel at the review leaves files unchanged. It needs a terminal; `NO_COLOR` or a dumb terminal stays usable without color or animation. No TTY: it prints the current config and exits. `--yes` is for workers, not this wizard.

`factory.sh config` is the scriptable writer. `config tracker github|linear [--team <linear-team-key>]` stores the issue tracker in `.factory/config`; github is the default when no config exists, and linear requires a team key. `config skills "<skill-name>: <when it applies>" [more...]` replaces `.factory/conventions` with those entries, one per line. `config` with no arguments prints the current tracker and skills. It targets `--repo <name>` under the workspace, or the checkout you run it from. Both files live under `.factory/`, which factory.sh adds to the checkout's `.git/info/exclude` so they stay out of source control.

`factory.sh ship` is an alias of `floor`. QA URL is `--url` or `FACTORY_QA_URL`. `--yes` is for workers. Lead stays interactive for quiz and for `blocked`.

Per-repo conventions: feature, bug, and docs lanes are always told to check for relevant skills before writing code. To steer them, author `.factory/conventions` in the target checkout. Each line is one of: `# comment`, `skill-name: when it applies` (a skill entry with context, e.g. `euc-go: Go services and migrations`), a bare `skill-name`, or any other text, injected verbatim as repo context (e.g. `never add jest tests; never raw HTML`). Any skill available to the runner can be listed; the lane is told to invoke each one that applies. The review lane gets the same list when the file exists and flags every convention violation as a review comment. factory.sh adds `.factory/` to the checkout's `.git/info/exclude` when it reads the file, which keeps an untracked file from being committed.

## What this pack will not do

A person still quizzes before tickets, logs in for a protected browser, and merges.

Telemetry adapters in this repo are vendor notes and a contract. They do not pull production data. `/telemetry` only works if the product checkout already has an adapter wired.

We used these lanes to build this factory. That does not mean they have been walked on your app. `./install.sh`, cd into a repo you own, `/lead`, and you merge.

`./install.sh` does not make every CLI a factory.

## Hard rules

- Never merge. A person merges.
- Never `git commit --no-verify`.
- Never read or send `.env` / `.env.local`. Never store `.env` in factory memory.
- Never attribute factory code to other products.
- Only the ticket or PR you were given.
- Issues live on the owning service, not a catch-all.
- PR title: `Type/<issue.number>/<short description>` (`Feat`, `Bug`, `Arch`, `Chore`, `Refactor`, `General`).

## Telemetry

See [`telemetry/CONTRACT.md`](telemetry/CONTRACT.md). Funnels are any instrumented path, not one screen. Session replay is optional. If the vendor cannot replay or cannot funnel, say so. Do not invent either. This pack does not ship a live PostHog, Datadog, App Insights, or CloudWatch client. Wire the adapter in the product. Then ask `/telemetry`.
