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

need_text() {
  local file="$1" pat="$2"
  grep -q -- "$pat" "$ROOT/$file" || fail "$file missing /$pat/"
}

need_file() {
  local file="$1"
  [[ -f "$ROOT/$file" ]] || fail "missing $file"
}

# Vendored 1-1 from WH-2099/mermaid-skill@982d903, including references
need_file skills/mermaid/SKILL.md
need_text skills/mermaid/SKILL.md "name: mermaid"
need_text skills/mermaid/SKILL.md "allowed-tools: Read Write Edit"
need_text skills/mermaid/SKILL.md "Mermaid Diagram Generator"
need_text skills/mermaid/SKILL.md 'User requirements: $ARGUMENTS'
[[ -d "$ROOT/skills/mermaid/references" ]] || fail "missing skills/mermaid/references"
refs=0
for f in architecture.md block.md c4.md classDiagram.md config-configuration.md \
  config-directives.md config-layouts.md config-math.md config-theming.md \
  config-tidy-tree.md cynefin.md entityRelationshipDiagram.md eventmodeling.md \
  examples.md flowchart.md gantt.md gitgraph.md ishikawa.md kanban.md mindmap.md \
  packet.md pie.md quadrantChart.md radar.md railroad.md requirementDiagram.md \
  sankey.md sequenceDiagram.md stateDiagram.md swimlanes.md timeline.md \
  treeView.md treemap.md userJourney.md venn.md wardley.md xyChart.md zenuml.md
do
  need_file "skills/mermaid/references/$f"
  refs=$((refs + 1))
done
[[ "$refs" == "38" ]] || fail "expected 38 mermaid reference files, got $refs"
got_refs="$(find "$ROOT/skills/mermaid/references" -type f | wc -l | tr -d ' ')"
[[ "$got_refs" == "38" ]] || fail "mermaid references must stay 1-1, extra files=$got_refs"

# Install exposes mermaid the same way it exposes implement
install_skills="$(sed -n 's/.*for skill in \(.*\); do/\1/p' "$ROOT/install.sh")"
echo "$install_skills" | grep -qw implement || fail "install.sh must list implement"
echo "$install_skills" | grep -qw mermaid || fail "install.sh must list mermaid like implement"

hid="$TMP/bin"
mkdir -p "$hid" "$TMP/.claude"
for cmd in bash mkdir ln rm echo grep command cat cp; do
  src="$(command -v "$cmd" || true)"
  [[ -n "$src" ]] && ln -sf "$src" "$hid/$cmd"
done
HOME="$TMP" PATH="$hid" "$ROOT/install.sh" >"$TMP/iout" 2>"$TMP/ierr" || fail "install exit $? err=$(cat "$TMP/ierr")"
[[ -L "$TMP/.claude/skills/factory-implement" ]] || fail "install should link factory-implement"
[[ -L "$TMP/.claude/skills/factory-mermaid" ]] || fail "install should link factory-mermaid like implement"
[[ "$(readlink "$TMP/.claude/skills/factory-mermaid")" == "$ROOT/skills/mermaid" ]] || fail "factory-mermaid should point at skills/mermaid"

# Plugin manifests expose mermaid the same way they expose implement: the skills directory
python3 - "$ROOT" <<'PY' || fail "plugin manifests must expose skills/mermaid like implement"
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
assert (root / "skills/mermaid/SKILL.md").is_file()
assert (root / "skills/implement/SKILL.md").is_file()
for rel in (".cursor-plugin/plugin.json", ".codex-plugin/plugin.json"):
    data = json.loads((root / rel).read_text())
    if data.get("skills") != "./skills/":
        raise SystemExit(f"{rel} skills must be ./skills/, got {data.get('skills')}")
PY

# PR prose stays at most 3 sentences; mermaid is extra
need_text AGENTS.md "at most 3 sentences"
need_text AGENTS.md "then mermaid"
need_text factory.sh "at most 3 sentences"
need_text factory.sh "then mermaid"
need_text skills/implement/SKILL.md "at most 3 sentences"
need_text skills/implement/SKILL.md "then mermaid"
if grep -q "at most 3 sentences, then mermaid, then" "$ROOT/factory.sh"; then
  fail "mermaid is extra, not a license to write an essay"
fi

# Feature: before and after when a prior shape exists, after-only when net-new
need_text factory.sh "before and after"
need_text factory.sh "prior shape"
need_text factory.sh "after-only"
need_text AGENTS.md "before and after"
need_text AGENTS.md "after-only"
need_text skills/implement/SKILL.md "before and after"
need_text skills/implement/SKILL.md "after-only"

# Bug: before and after always
need_text factory.sh "Bug: before and after"
need_text AGENTS.md "Bug: before and after"
need_text skills/implement/SKILL.md "Bug: before and after"

# Feature, bug, and docs lanes invoke mermaid when they write a PR
need_text lanes/feature.md "/mermaid"
need_text lanes/bug.md "/mermaid"
need_text lanes/docs.md "/mermaid"
need_text commands/feature.md "/mermaid"
need_text commands/bug.md "/mermaid"
need_text commands/docs.md "/mermaid"
need_text lanes/feature.md "PR"
need_text lanes/bug.md "PR"
need_text lanes/docs.md "PR"

# Review requests changes when required diagrams are missing
need_text lanes/review.md "mermaid"
need_text lanes/review.md "missing"
need_text lanes/review.md "Request changes"
need_text commands/review.md "mermaid"
need_text commands/review.md "missing"
need_text factory.sh "Review requests changes"

WS="$TMP/workspace"
mkdir -p "$WS/widgets"
git -C "$WS/widgets" init -q
git -C "$WS/widgets" remote add origin "https://github.com/acme/widgets.git"

DUMP="$TMP/dump"
mkdir -p "$DUMP"

cat > "$TMP/bin/runner" << 'EOF'
#!/usr/bin/env bash
dump="${FAKE_DUMP:?}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p) printf '%s\n' "$2" > "$dump/prompt"; shift 2 ;;
    --rules) printf '%s\n' "$2" > "$dump/rules"; shift 2 ;;
    *) shift ;;
  esac
done
exit 0
EOF
chmod +x "$TMP/bin/runner"

cat > "$TMP/bin/gh" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TMP/bin/gh"

run_factory() {
  PATH="$TMP/bin:$PATH" \
    FAKE_DUMP="$DUMP" \
    FACTORY_WORKSPACE="$WS" \
    FACTORY_OWNER=acme \
    FACTORY_RUNNER=runner FACTORY_HARNESS=claude \
    "$FACTORY" "$@" --repo widgets >/dev/null 2>&1
}

assert_rules() {
  local lane="$1"
  shift
  rm -rf "$DUMP"
  mkdir -p "$DUMP"
  run_factory "$lane" "$@"
  [[ -f "$DUMP/rules" ]] || fail "$lane did not dump rules"
  grep -q "at most 3 sentences" "$DUMP/rules" || fail "$lane rules missing 3-sentence cap"
  grep -q "then mermaid" "$DUMP/rules" || fail "$lane rules missing mermaid-after-prose"
  grep -q "/mermaid" "$DUMP/rules" || fail "$lane rules missing /mermaid"
}

assert_rules feature --issue 6
assert_rules bug --issue 6
assert_rules docs --issue 6

rm -rf "$DUMP"
mkdir -p "$DUMP"
run_factory review --pr 6
[[ -f "$DUMP/rules" ]] || fail "review did not dump rules"
grep -q "at most 3 sentences" "$DUMP/rules" || fail "review rules missing 3-sentence cap"
grep -q "then mermaid" "$DUMP/rules" || fail "review rules missing mermaid-after-prose"
grep -q "Request changes" "$DUMP/rules" || fail "review rules missing request-changes"
grep -q "missing" "$DUMP/rules" || fail "review rules missing diagrams-missing"
grep -q "Never merge" "$DUMP/rules" || fail "review rules must still say never merge"

echo "ok mermaid"
