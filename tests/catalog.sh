#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

need_text() {
  local file="$1" pat="$2"
  grep -q -- "$pat" "$ROOT/$file" || fail "$file missing /$pat/"
}

SHA1="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
SHA2="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

pin="$ROOT/scripts/pin-grok-catalog.py"
[[ -x "$pin" ]] || fail "missing executable scripts/pin-grok-catalog.py"

empty_catalog() {
  local dest="$1"
  mkdir -p "$(dirname "$dest")"
  printf '%s\n' '{"name":"xai-official","owner":{"name":"xAI"},"plugins":[]}' >"$dest"
}

plugin_count() {
  python3 -c 'import json,sys; print(sum(1 for p in json.load(open(sys.argv[1])).get("plugins",[]) if p.get("name")=="software-factory"))' "$1"
}

plugin_sha() {
  python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
found=[p for p in d.get("plugins",[]) if p.get("name")=="software-factory"]
print(found[0]["source"]["sha"] if found else "")' "$1"
}

cat1="$TMP/marketplace.json"
empty_catalog "$cat1"
"$pin" "$cat1" "$SHA1" "https://github.com/Kripu77/software-factory.git" || fail "first pin should add the listing"
[[ "$(plugin_count "$cat1")" == "1" ]] || fail "first listing should add exactly one software-factory entry"
[[ "$(plugin_sha "$cat1")" == "$SHA1" ]] || fail "first listing should pin the tag SHA, not main"
python3 - "$cat1" "$SHA1" <<'PY' || fail "first listing is not a remote url pin"
import json, sys
path, sha = sys.argv[1], sys.argv[2]
p = next(x for x in json.load(open(path))["plugins"] if x["name"] == "software-factory")
src = p["source"]
if src.get("source") != "url":
    raise SystemExit(f"source.source should be url, got {src}")
if src.get("url") != "https://github.com/Kripu77/software-factory.git":
    raise SystemExit(f"unexpected url {src.get('url')}")
if src.get("sha") != sha:
    raise SystemExit(f"sha {src.get('sha')} != {sha}")
if src.get("sha") in ("main", "master"):
    raise SystemExit("must not pin main")
if "type" in src and src["type"] == "local":
    raise SystemExit("official catalog entry must not be a local vendor")
PY

python3 - "$cat1" <<'PY' || fail "could not dirty the first listing source"
import json, sys
path = sys.argv[1]
data = json.load(open(path))
for plugin in data["plugins"]:
    if plugin.get("name") == "software-factory":
        plugin["source"]["type"] = "local"
        plugin["source"]["path"] = "./"
        plugin["source"]["extra"] = "nope"
json.dump(data, open(path, "w"), indent=2)
open(path, "a").write("\n")
PY
"$pin" "$cat1" "$SHA2" "https://github.com/Kripu77/software-factory.git" || fail "second pin should bump the SHA"
[[ "$(plugin_count "$cat1")" == "1" ]] || fail "second tag must bump SHA, not add a duplicate first-listing"
[[ "$(plugin_sha "$cat1")" == "$SHA2" ]] || fail "second tag should pin the new tag SHA"
python3 - "$cat1" "$SHA2" <<'PY' || fail "second pin should assign the url pin, not convert leftover source keys"
import json, sys
path, sha = sys.argv[1], sys.argv[2]
p = next(x for x in json.load(open(path))["plugins"] if x["name"] == "software-factory")
want = {
    "source": "url",
    "url": "https://github.com/Kripu77/software-factory.git",
    "sha": sha,
}
if p["source"] != want:
    raise SystemExit(f"expected {want}, got {p['source']}")
PY

set +e
"$pin" "$cat1" "main" "https://github.com/Kripu77/software-factory.git" >"$TMP/out" 2>"$TMP/err"
code=$?
set -e
[[ $code -ne 0 ]] || fail "pinning main should fail"
[[ "$(plugin_sha "$cat1")" == "$SHA2" ]] || fail "rejected pin must leave the catalog SHA alone"

set +e
"$pin" "$cat1" "abc" "https://github.com/Kripu77/software-factory.git" >"$TMP/out" 2>"$TMP/err"
code=$?
set -e
[[ $code -ne 0 ]] || fail "short SHA should fail"

echo "ok catalog pin"

ship="$ROOT/scripts/ship-grok-catalog.sh"
[[ -x "$ship" ]] || fail "missing executable scripts/ship-grok-catalog.sh"

if grep -q "gh pr merge" "$ship" || grep -q "gh merge" "$ship"; then
  fail "catalog ship must not merge"
fi
if grep -q "\.env" "$ship"; then
  fail "catalog ship must not touch .env"
fi
if grep -q "XAI_MARKETPLACE_DIR" "$ship"; then
  fail "catalog ship must not skip clone and push via XAI_MARKETPLACE_DIR"
fi
if grep -E -q 'echo +"\$\{?(token|TOKEN|GH_TOKEN|XAI_MARKETPLACE_TOKEN)' "$ship"; then
  fail "catalog ship must not print the token"
fi

export TMPDIR="$TMP"
hid="$TMP/bin"
mkdir -p "$hid"
fork="$TMP/fork.git"
upstream="$TMP/upstream.git"

cat >"$hid/gh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "gh \$*" >>"$TMP/gh.log"
case "\${1:-}" in
  api)
    echo "testuser"
    exit 0
    ;;
  repo)
    if [[ "\${2:-}" == "clone" ]]; then
      dest="\${4:-}"
      [[ -n "\$dest" ]] || exit 1
      git clone --depth 1 "$fork" "\$dest"
      git -C "\$dest" remote add upstream "$upstream"
      exit 0
    fi
    exit 0
    ;;
  pr)
    if [[ "\${2:-}" == "merge" ]]; then
      echo "must not merge" >&2
      exit 2
    fi
    if [[ "\${2:-}" == "list" ]]; then
      if [[ -f "$TMP/open-pr" ]]; then
        echo "1"
      else
        echo "0"
      fi
      exit 0
    fi
    if [[ "\${2:-}" == "create" ]]; then
      printf '%s\n' "\$*" >>"$TMP/pr-create.log"
      echo "https://github.com/xai-org/plugin-marketplace/pull/99"
      echo "1" >"$TMP/open-pr"
      exit 0
    fi
    exit 0
    ;;
esac
exit 0
EOF
chmod +x "$hid/gh"

init_catalog_repo() {
  local dest="$1"
  mkdir -p "$dest/.grok-plugin" "$dest/scripts"
  printf '%s\n' '{"name":"xai-official","owner":{"name":"xAI"},"plugins":[]}' >"$dest/.grok-plugin/marketplace.json"
  cat >"$dest/scripts/generate-plugin-index.py" <<'PY'
#!/usr/bin/env python3
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
market = json.loads((root / ".grok-plugin" / "marketplace.json").read_text())
index = []
for plugin in market.get("plugins", []):
    source = plugin.get("source") or {}
    index.append({"name": plugin.get("name"), "sha": source.get("sha"), "url": source.get("url")})
(root / ".grok-plugin" / "plugin-index.json").write_text(json.dumps({"plugins": index}, indent=2) + "\n")
PY
  (
    cd "$dest"
    git init -q -b main
    git config user.email "factory@example.com"
    git config user.name "factory"
    git add .grok-plugin/marketplace.json scripts/generate-plugin-index.py
    git commit -q -m "initial catalog"
  )
}

branch_file() {
  git --git-dir="$fork" show "software-factory:$1"
}

branch_plugin_count() {
  branch_file .grok-plugin/marketplace.json | python3 -c 'import json,sys; print(sum(1 for p in json.load(sys.stdin).get("plugins",[]) if p.get("name")=="software-factory"))'
}

branch_plugin_sha() {
  branch_file .grok-plugin/marketplace.json | python3 -c 'import json,sys
found=[p for p in json.load(sys.stdin).get("plugins",[]) if p.get("name")=="software-factory"]
print(found[0]["source"]["sha"] if found else "")'
}

branch_index_sha() {
  branch_file .grok-plugin/plugin-index.json | python3 -c 'import json,sys
found=[p for p in json.load(sys.stdin).get("plugins",[]) if p.get("name")=="software-factory"]
print(found[0].get("sha","") if found else "")'
}

export PATH="$hid:$PATH"
unset XAI_MARKETPLACE_TOKEN
unset GH_TOKEN
unset XAI_MARKETPLACE_DIR
catalog_work="$TMP/catalog-src"
init_catalog_repo "$catalog_work"
git clone --bare -q "$catalog_work" "$upstream"
git clone --bare -q "$catalog_work" "$fork"

set +e
"$ship" v1.0.0 "$SHA1" >"$TMP/ship-out" 2>"$TMP/ship-err"
code=$?
set -e
[[ $code -ne 0 ]] || fail "missing token should fail so a person stores it"
grep -q "XAI_MARKETPLACE_TOKEN" "$TMP/ship-err" || fail "missing token should name XAI_MARKETPLACE_TOKEN: $(cat "$TMP/ship-err")"

: >"$TMP/gh.log"
rm -f "$TMP/pr-create.log" "$TMP/open-pr"
export XAI_MARKETPLACE_TOKEN="test-token-not-a-secret-value"
export XAI_MARKETPLACE_REPO="xai-org/plugin-marketplace"
"$ship" v1.0.0 "$SHA1" >"$TMP/ship-out" 2>"$TMP/ship-err" || fail "first listing should open a catalog PR: $(cat "$TMP/ship-err")"
[[ "$(branch_plugin_count)" == "1" ]] || fail "first listing should add software-factory on the origin branch"
[[ "$(branch_plugin_sha)" == "$SHA1" ]] || fail "first listing should pin $SHA1 on origin"
[[ "$(branch_index_sha)" == "$SHA1" ]] || fail "first listing should regenerate plugin-index.json to $SHA1"
[[ -f "$TMP/pr-create.log" ]] || fail "first listing should gh pr create"
grep -qi "Add" "$TMP/pr-create.log" || fail "first listing PR should be an add, not a SHA bump: $(cat "$TMP/pr-create.log")"
if grep -q "gh pr merge" "$TMP/gh.log" || grep -q "gh merge" "$TMP/gh.log"; then
  fail "first listing must not merge"
fi
if branch_file .grok-plugin/marketplace.json | grep -q "test-token-not-a-secret-value"; then
  fail "token must not land in the catalog"
fi

"$ship" v1.1.0 "$SHA2" >"$TMP/ship-out2" 2>"$TMP/ship-err2" || fail "open first-listing PR should update the pin: $(cat "$TMP/ship-err2")"
[[ "$(branch_plugin_count)" == "1" ]] || fail "updating the open PR must not duplicate the listing"
[[ "$(branch_plugin_sha)" == "$SHA2" ]] || fail "open PR should move origin to the new tag SHA"
[[ "$(branch_index_sha)" == "$SHA2" ]] || fail "open PR should regenerate plugin-index.json to $SHA2"

creates="$(wc -l <"$TMP/pr-create.log" | tr -d ' ')"
[[ "$creates" == "1" ]] || fail "open first-listing PR should be updated, not created again: $(cat "$TMP/pr-create.log")"

git clone -q "$upstream" "$TMP/upstream-main"
python3 "$ROOT/scripts/pin-grok-catalog.py" "$TMP/upstream-main/.grok-plugin/marketplace.json" "$SHA2" "https://github.com/Kripu77/software-factory.git"
(
  cd "$TMP/upstream-main"
  python3 scripts/generate-plugin-index.py
  git add .grok-plugin/marketplace.json .grok-plugin/plugin-index.json
  git config user.email "factory@example.com"
  git config user.name "factory"
  git commit -q -m "merge first listing"
)
git --git-dir="$upstream" fetch -q "$TMP/upstream-main" main:main
rm -f "$TMP/open-pr" "$TMP/pr-create.log"
"$ship" v1.2.0 "$SHA1" >"$TMP/ship-out3" 2>"$TMP/ship-err3" || fail "later tag with no open PR should open a SHA bump: $(cat "$TMP/ship-err3")"
[[ "$(branch_plugin_count)" == "1" ]] || fail "SHA bump must not add a second listing"
[[ "$(branch_plugin_sha)" == "$SHA1" ]] || fail "SHA bump should pin the later tag on origin"
[[ "$(branch_index_sha)" == "$SHA1" ]] || fail "SHA bump should regenerate plugin-index.json to $SHA1"
[[ -f "$TMP/pr-create.log" ]] || fail "merged first listing then a later tag should open a bump PR"
grep -qi "Bump" "$TMP/pr-create.log" || fail "later tag PR should be a SHA bump: $(cat "$TMP/pr-create.log")"
if grep -qi "Add software-factory" "$TMP/pr-create.log"; then
  fail "later tag must not open a duplicate first-listing"
fi
if grep -q "gh pr merge" "$TMP/gh.log"; then
  fail "SHA bump must not merge"
fi

echo "ok catalog ship"

rel="$ROOT/.github/workflows/release.yml"
need_text .github/workflows/release.yml "ship-grok-catalog.sh"
need_text .github/workflows/release.yml "XAI_MARKETPLACE_TOKEN"
need_text .github/workflows/release.yml "git rev-parse HEAD"
need_text .github/workflows/release.yml "GITHUB_REF_NAME"
if grep -E -q 'ship-grok-catalog\.sh.*GITHUB_SHA' "$rel"; then
  fail "ship the peeled commit from git rev-parse HEAD, not GITHUB_SHA"
fi
grep -q "secrets.XAI_MARKETPLACE_TOKEN" "$rel" || fail "release should read XAI_MARKETPLACE_TOKEN from GitHub secrets"
if grep -qi "schedule:" "$rel" || grep -qi "cron:" "$rel"; then
  fail "catalog pin should ship on the tag, not wait for a daily cron"
fi
if grep -q "gh pr merge" "$rel" || grep -q "gh merge" "$rel"; then
  fail "release workflow must not merge"
fi
if grep -q "\.env" "$rel"; then
  fail "release workflow must not touch .env"
fi
if grep -q "main" "$rel" && grep -E 'ship-grok-catalog.sh.*main' "$rel"; then
  fail "catalog pin must use the tag SHA, not main"
fi
if grep -qi "re-index" "$rel"; then
  fail "release must not announce Cursor re-index"
fi
python3 - "$rel" <<'PY' || fail "release must not invent a Cursor publish API"
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text()
if "cursor.com/api" in text or "POST" in text:
    raise SystemExit("do not invent a Cursor publish API")
PY

extras="$(grep -oE 'secrets\.[A-Za-z0-9_]+' "$rel" | grep -v 'secrets.XAI_MARKETPLACE_TOKEN' || true)"
if [[ -n "$extras" ]]; then
  fail "unexpected secrets in release workflow: $extras"
fi

readme="$ROOT/README.md"
python3 - "$readme" <<'PY' || fail "README install is GitHub marketplace one-liners, not a catalogs runbook"
import pathlib, sys, re
text = pathlib.Path(sys.argv[1]).read_text()
if re.search(r"^## Official catalogs\s*$", text, re.M):
    raise SystemExit("README must not have an Official catalogs runbook")
if "XAI_MARKETPLACE_TOKEN" in text:
    raise SystemExit("README must not name XAI_MARKETPLACE_TOKEN")
if "re-index" in text.lower():
    raise SystemExit("README must not announce Cursor re-index")
if "daily SHA cron" in text or "daily sha cron" in text.lower():
    raise SystemExit("README must not mention the xAI daily SHA cron")
start = text.find("\n## Install\n")
if start < 0:
    raise SystemExit("README missing ## Install")
rest = text[start + 1:]
nxt = rest.find("\n## ")
section = rest if nxt < 0 else rest[:nxt]
if "a person creates the tag" in section.lower():
    raise SystemExit("tag copy must be tag and push, not a person creates the tag")
if "tag and push" not in section.lower():
    raise SystemExit("Install section must say tag and push")
if "the agent" in section.lower():
    raise SystemExit("README install must not talk about the agent")
if not re.search(r"Kripu77/software-factory@v\d+\.\d+\.\d+", section):
    raise SystemExit("Install must keep GitHub marketplace one-liners at the tag")
PY

for f in scripts/pin-grok-catalog.py scripts/ship-grok-catalog.sh .github/workflows/release.yml README.md; do
  if grep -qiE 'cursor.com/api|publish.cursor|claude.ai/api|openai.com/v1/plugins' "$ROOT/$f"; then
    fail "$f must not invent a catalog publish API"
  fi
done

echo "ok catalog docs"
