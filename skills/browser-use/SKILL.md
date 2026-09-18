---
name: browser-use
description: Drive a real browser to QA a running app. Screenshots, clicks, forms, evidence. Use when there is no Playwright suite, or when a human flow must be walked.
---

# Browser use

## Trigger

Need to test a running web app by actually using it. No smoke suite, or the suite does not cover this flow.

Navigate, click, fill, screenshot, assert. Use the harness browser.

## How to drive the browser

Pick the door the runner actually has, in this order:

1. A first-party browser tool on this harness (Grok Bot browserUse, Grok Build browser, Claude computer use, Claude-in-Chrome MCP).
2. Headed Playwright against the given URL, if Playwright is already in the checkout.
3. Bootstrap headed Playwright in a throwaway directory outside the checkout (`npm init -y && npm i playwright && npx playwright install chromium`) and drive the given URL from a script there. Nothing lands in the product repo.
4. Stop and say the harness has no browser.

Do not run headless when a headed browser is available. Do not scrape cookies out of a profile to skip login.

## Workflow

1. Resolve the target URL (dispatched, or local app for the repo). Confirm it is up before clicking.
2. Walk the flow as a user. One path. Screenshot each meaningful step.
3. Record the primary flow as a GIF or video when the harness can (Claude gif_creator, Playwright `recordVideo`). Capture frames before and after each action so playback reads smoothly. One recording per flow, named for the flow it shows.
4. Assert what the user would see: copy, state, error, navigation.
5. If login or 2FA is required, stop and hand that step to a human. Never ask for a password in chat. Never read `.env`.
6. Post the screenshots and recording on the PR (or issue) as a comment. Then report: repro, evidence links, what broke, what was fine.

## Guardrails

- Report only. Do not patch product code.
- Prefer a real click over injecting JS.
- Deterministic waits for visible state, not sleep.
- Stay on the dispatched flow. Do not wander the whole site.
- Never merge.

## Output

- Flow walked
- Screenshots of every changed screen, posted on the PR or issue
- A screen recording of the primary flow, when the harness can capture one
- Failures with repro steps
- Anything that could not be tested (auth wall, downed app, no recording support)
