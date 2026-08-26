#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

fail() { echo "FAIL: $*" >&2; exit 1; }

need_text() {
  local file="$1" pat="$2"
  grep -q -- "$pat" "$ROOT/$file" || fail "$file missing /$pat/"
}

need_file() {
  local file="$1"
  [[ -f "$ROOT/$file" ]] || fail "missing $file"
}

plugin_version() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$1"
}

assert_claude_marketplace() {
  need_file ".claude-plugin/marketplace.json"
  python3 - "$ROOT/.claude-plugin/marketplace.json" <<'PY' || fail ".claude-plugin/marketplace.json is not a Claude marketplace"
import json, sys

path = sys.argv[1]
data = json.load(open(path))
if not isinstance(data, dict):
    raise SystemExit(f"{path} must be a JSON object")
if data.get("name") != "software-factory":
    raise SystemExit(f"{path} name must be software-factory")
owner = data.get("owner") or {}
if not owner.get("name"):
    raise SystemExit(f"{path} needs owner.name")
plugins = data.get("plugins")
if not isinstance(plugins, list) or not plugins:
    raise SystemExit(f"{path} needs a plugins list")
found = next((p for p in plugins if p.get("name") == "software-factory"), None)
if found is None:
    raise SystemExit(f"{path} must list plugin software-factory")
if found.get("source") != "./":
    raise SystemExit(f"{path} software-factory source must be the relative path ./")
if "version" in found:
    raise SystemExit(f"{path} must not set plugin version; .claude-plugin/plugin.json is canonical")
PY
}

assert_grok_marketplace() {
  need_file ".grok-plugin/marketplace.json"
  python3 - "$ROOT/.grok-plugin/marketplace.json" <<'PY' || fail ".grok-plugin/marketplace.json is not a Grok marketplace"
import json, sys

path = sys.argv[1]
data = json.load(open(path))
if not isinstance(data, dict):
    raise SystemExit(f"{path} must be a JSON object")
if data.get("name") != "software-factory":
    raise SystemExit(f"{path} name must be software-factory")
owner = data.get("owner") or {}
if not owner.get("name"):
    raise SystemExit(f"{path} needs owner.name")
plugins = data.get("plugins")
if not isinstance(plugins, list) or not plugins:
    raise SystemExit(f"{path} needs a plugins list")
found = next((p for p in plugins if p.get("name") == "software-factory"), None)
if found is None:
    raise SystemExit(f"{path} must list plugin software-factory")
source = found.get("source")
if not (isinstance(source, dict) and source.get("type") == "local" and source.get("path") == "./"):
    raise SystemExit(f"{path} software-factory source must be {{type: local, path: ./}}")
if "version" in found:
    raise SystemExit(f"{path} must not set plugin version; .grok-plugin/plugin.json is canonical")
PY
}

assert_cursor_marketplace() {
  need_file ".cursor-plugin/marketplace.json"
  python3 - "$ROOT/.cursor-plugin/marketplace.json" <<'PY' || fail ".cursor-plugin/marketplace.json is not a Cursor marketplace"
import json, sys

path = sys.argv[1]
data = json.load(open(path))
if not isinstance(data, dict):
    raise SystemExit(f"{path} must be a JSON object")
if data.get("name") != "software-factory":
    raise SystemExit(f"{path} name must be software-factory")
owner = data.get("owner") or {}
if not owner.get("name"):
    raise SystemExit(f"{path} needs owner.name")
plugins = data.get("plugins")
if not isinstance(plugins, list) or not plugins:
    raise SystemExit(f"{path} needs a plugins list")
found = next((p for p in plugins if p.get("name") == "software-factory"), None)
if found is None:
    raise SystemExit(f"{path} must list plugin software-factory")
allowed = {"name", "source", "description", "minClientVersions"}
extra = set(found) - allowed
if extra:
    raise SystemExit(f"{path} plugin entries may only have {sorted(allowed)}; extra {sorted(extra)}")
if found.get("source") != "./":
    raise SystemExit(f"{path} software-factory source must be ./")
PY
}

assert_codex_marketplace() {
  need_file ".agents/plugins/marketplace.json"
  python3 - "$ROOT/.agents/plugins/marketplace.json" <<'PY' || fail ".agents/plugins/marketplace.json is not a Codex marketplace"
import json, sys

path = sys.argv[1]
data = json.load(open(path))
if not isinstance(data, dict):
    raise SystemExit(f"{path} must be a JSON object")
if data.get("name") != "software-factory":
    raise SystemExit(f"{path} name must be software-factory")
owner = data.get("owner") or {}
if not owner.get("name"):
    raise SystemExit(f"{path} needs owner.name")
plugins = data.get("plugins")
if not isinstance(plugins, list) or not plugins:
    raise SystemExit(f"{path} needs a plugins list")
found = next((p for p in plugins if p.get("name") == "software-factory"), None)
if found is None:
    raise SystemExit(f"{path} must list plugin software-factory")
source = found.get("source")
if not (isinstance(source, dict) and source.get("source") == "local" and source.get("path") == "./"):
    raise SystemExit(f"{path} software-factory source must be {{source: local, path: ./}}")
if "version" in found:
    raise SystemExit(f"{path} must not set plugin version; .codex-plugin/plugin.json is canonical")
policy = found.get("policy") or {}
if not policy.get("installation") or not policy.get("authentication"):
    raise SystemExit(f"{path} software-factory needs policy.installation and policy.authentication")
PY
}

want="$(plugin_version "$ROOT/.claude-plugin/plugin.json")"

assert_claude_marketplace
assert_grok_marketplace
assert_cursor_marketplace
assert_codex_marketplace

need_file ".codex-plugin/plugin.json"
codex_ver="$(plugin_version "$ROOT/.codex-plugin/plugin.json")"
[[ "$codex_ver" == "$want" ]] || fail ".codex-plugin/plugin.json version $codex_ver does not match .claude-plugin/plugin.json $want"
grep -q '"name": "software-factory"' "$ROOT/.codex-plugin/plugin.json" || fail ".codex-plugin/plugin.json name must be software-factory"
grep -q 'skills' "$ROOT/.codex-plugin/plugin.json" || fail ".codex-plugin/plugin.json must point at skills"

check="$ROOT/scripts/check-plugin-versions.sh"
"$check" "v${want}" "$ROOT" || fail "plugin versions should match v${want}"
grep -q '.codex-plugin/plugin.json' "$check" || fail "check-plugin-versions.sh should check .codex-plugin/plugin.json"
if grep -q 'marketplace.json' "$check"; then
  fail "check-plugin-versions.sh should gate plugin.json only, not marketplace catalogs"
fi

need_file "commands/lead.md"
grep -q '^name: lead$' "$ROOT/commands/lead.md" || fail "commands/lead.md should declare /lead"

readme="$ROOT/README.md"
need_text README.md "/plugin marketplace add Kripu77/software-factory@v${want}"
need_text README.md "/plugin install software-factory@software-factory"
need_text README.md "grok plugin install Kripu77/software-factory@v${want}"
need_text README.md "codex plugin marketplace add Kripu77/software-factory@v${want}"
need_text README.md "codex plugin add software-factory@software-factory"
if grep -q "codex plugin install" "$readme"; then
  fail "Codex install command is plugin add, not plugin install"
fi
need_text README.md "git clone"
need_text README.md "./install.sh"
need_text README.md "from-source"

python3 - "$readme" "$want" <<'PY' || fail "README Install must lead with tagged marketplace install, not clone from main"
import sys, re
path, version = sys.argv[1], sys.argv[2]
text = open(path).read()
start = text.find("\n## Install\n")
if start < 0:
    raise SystemExit("README missing ## Install")
rest = text[start + 1:]
nxt = rest.find("\n## ")
section = rest if nxt < 0 else rest[:nxt]
if re.search(r"software-factory@(main|master)\b", section) or re.search(r"--ref main\b", section):
    raise SystemExit("Install section must not use unversioned main")
tag = f"Kripu77/software-factory@v{version}"
if tag not in section:
    raise SystemExit(f"Install section must pin {tag}")
market = section.find(tag)
clone = section.find("git clone")
if market < 0:
    raise SystemExit("Install section must name the tagged GitHub repo")
if clone < 0:
    raise SystemExit("Install section must keep git clone as from-source")
if market > clone:
    raise SystemExit("marketplace one-liners must lead; clone plus ./install.sh follows")
for needle in ("Claude", "Grok", "Codex", "Cursor"):
    if needle.lower() not in section.lower():
        raise SystemExit(f"Install section must cover {needle}")
PY

echo "ok marketplace"
