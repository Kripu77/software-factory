#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FACTORY="$ROOT/factory.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export FACTORY_MEMORY_DB="$TMP/memory/factory.db"
unset FACTORY_RUNNER
unset FACTORY_SKIP_TICKET_COMMENT

fail() { echo "FAIL: $*" >&2; exit 1; }

WS="$TMP/workspace"
mkdir -p "$WS/widgets"
git -C "$WS/widgets" init -q
git -C "$WS/widgets" remote add origin "https://github.com/acme/widgets.git"

cfg() {
  FACTORY_WORKSPACE="$WS" "$FACTORY" config --repo widgets "$@"
}

# No config yet: github is the default tracker
out="$(cfg)"
grep -q "tracker github" <<< "$out" || fail "default tracker should be github, got: $out"

# tracker linear requires a team key
cfg tracker linear >/dev/null 2>&1 && fail "tracker linear without --team must fail"
out="$(cfg tracker linear 2>&1 || true)"
grep -qi "team" <<< "$out" || fail "linear without team should print a usage message, got: $out"

# Invalid tracker fails with a usage message
cfg tracker jira >/dev/null 2>&1 && fail "tracker jira must fail"
out="$(cfg tracker jira 2>&1 || true)"
grep -qi "github or linear" <<< "$out" || fail "invalid tracker should print a usage message, got: $out"

# tracker linear --team ABC then config shows tracker linear, team ABC
cfg tracker linear --team ABC >/dev/null
out="$(cfg)"
grep -q "tracker linear" <<< "$out" || fail "config should show tracker linear, got: $out"
grep -q "team ABC" <<< "$out" || fail "config should show team ABC, got: $out"
[[ -f "$WS/widgets/.factory/config" ]] || fail "tracker should be stored in .factory/config"

# tracker github switches back and drops the team
cfg tracker github >/dev/null
out="$(cfg)"
grep -q "tracker github" <<< "$out" || fail "config should show tracker github, got: $out"
grep -q "team" <<< "$out" && fail "github tracker should not show a team, got: $out"

# config skills writes entries to .factory/conventions in the #35 line format
cfg skills "euc-go: Go services" "euc-sql: migrations" >/dev/null
grep -qxF "euc-go: Go services" "$WS/widgets/.factory/conventions" || fail "conventions missing euc-go entry"
grep -qxF "euc-sql: migrations" "$WS/widgets/.factory/conventions" || fail "conventions missing euc-sql entry"
out="$(cfg)"
grep -q "euc-go: Go services" <<< "$out" || fail "config should list euc-go skill, got: $out"
grep -q "euc-sql: migrations" <<< "$out" || fail "config should list euc-sql skill, got: $out"

# config skills with no entries fails with a usage message
cfg skills >/dev/null 2>&1 && fail "config skills without entries must fail"

# Rerunning skills replaces the list instead of appending duplicates
cfg skills "euc-go: Go services" >/dev/null
[[ "$(grep -cxF 'euc-go: Go services' "$WS/widgets/.factory/conventions")" == "1" ]] || fail "rerun must not duplicate entries"
grep -q "euc-sql" "$WS/widgets/.factory/conventions" && fail "rerun should replace the skill list"

# .factory/ stays out of source control via .git/info/exclude
grep -qxF ".factory/" "$WS/widgets/.git/info/exclude" || fail ".factory/ missing from .git/info/exclude"
cfg tracker github >/dev/null
[[ "$(grep -cxF '.factory/' "$WS/widgets/.git/info/exclude")" == "1" ]] || fail ".factory/ excluded more than once"

# config runs against the checkout itself when it is the workspace
out="$(cd "$WS/widgets" && "$FACTORY" config)"
grep -q "tracker github" <<< "$out" || fail "config should work from inside a checkout, got: $out"

# With FACTORY_WORKSPACE set, config without --repo targets the cwd checkout,
# not the workspace sibling named after the origin remote
mkdir -p "$WS/widgets-fork"
git -C "$WS/widgets-fork" init -q
git -C "$WS/widgets-fork" remote add origin "https://github.com/acme/widgets.git"
before="$(cat "$WS/widgets/.factory/config")"
(cd "$WS/widgets-fork" && FACTORY_WORKSPACE="$WS" "$FACTORY" config tracker linear --team FRK >/dev/null)
grep -qxF "team=FRK" "$WS/widgets-fork/.factory/config" || fail "config from a checkout must write that checkout's .factory/config"
[[ "$(cat "$WS/widgets/.factory/config")" == "$before" ]] || fail "config from widgets-fork must not touch widgets"

# Explicit --repo still wins over the cwd
(cd "$WS/widgets-fork" && FACTORY_WORKSPACE="$WS" "$FACTORY" config --repo widgets tracker github >/dev/null)
grep -qxF "tracker=github" "$WS/widgets/.factory/config" || fail "--repo must target the named checkout"
grep -qxF "team=FRK" "$WS/widgets-fork/.factory/config" || fail "--repo widgets must not touch widgets-fork"

# Appending .factory/ must not glue onto an exclude file missing its trailing newline
printf 'node_modules' > "$WS/widgets-fork/.git/info/exclude"
(cd "$WS/widgets-fork" && FACTORY_WORKSPACE="$WS" "$FACTORY" config tracker github >/dev/null)
grep -qxF "node_modules" "$WS/widgets-fork/.git/info/exclude" || fail "existing exclude patterns must survive the append"
grep -qxF ".factory/" "$WS/widgets-fork/.git/info/exclude" || fail ".factory/ missing after newline-less append"
(cd "$WS/widgets-fork" && FACTORY_WORKSPACE="$WS" "$FACTORY" config tracker github >/dev/null)
[[ "$(grep -cxF '.factory/' "$WS/widgets-fork/.git/info/exclude")" == "1" ]] || fail ".factory/ appended twice after newline fix"

# Skills entries must be one line in the "<skill-name>: <when>" format
cfg skills "no-colon-entry" >/dev/null 2>&1 && fail "skills entry without ': ' must fail"
cfg skills $'euc-go: one\nnot-an-entry' >/dev/null 2>&1 && fail "skills entry with a newline must fail"
grep -qxF "euc-go: Go services" "$WS/widgets/.factory/conventions" || fail "rejected entries must not overwrite conventions"

# README documents the subcommand
grep -q "factory.sh config" "$ROOT/README.md" || fail "README missing factory.sh config"

echo "ok config"
