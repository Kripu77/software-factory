#!/usr/bin/env python3
import json
import re
import sys

SHA_RE = re.compile(r"^[0-9a-f]{40}$")
NAME = "software-factory"
DEFAULT_URL = "https://github.com/Kripu77/software-factory.git"


def pin(catalog_path: str, sha: str, url: str) -> None:
    if not SHA_RE.match(sha):
        raise SystemExit(f"sha {sha!r} is not a 40-character lowercase hex commit")
    with open(catalog_path, encoding="utf-8") as fh:
        data = json.load(fh)
    plugins = data.setdefault("plugins", [])
    if not isinstance(plugins, list):
        raise SystemExit("marketplace.json plugins must be a list")
    found = None
    for plugin in plugins:
        if plugin.get("name") == NAME:
            if found is not None:
                raise SystemExit("duplicate software-factory listing")
            found = plugin
    source = {"source": "url", "url": url, "sha": sha}
    if found is None:
        plugins.append(
            {
                "name": NAME,
                "description": "Lanes, tickets, and a human merge. Skills and slash commands for Grok Build.",
                "category": "development",
                "source": source,
                "homepage": "https://github.com/Kripu77/software-factory",
                "keywords": [
                    "software-factory",
                    "tdd",
                    "review",
                    "telemetry",
                    "unslop",
                    "poteto-mode",
                ],
            }
        )
    else:
        current = found.get("source")
        if not isinstance(current, dict):
            found["source"] = source
        else:
            current["source"] = "url"
            current["url"] = url
            current["sha"] = sha
            current.pop("type", None)
            if current.get("path") in (None, "./", "."):
                current.pop("path", None)
    with open(catalog_path, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")


def main() -> None:
    if len(sys.argv) < 3:
        raise SystemExit("usage: pin-grok-catalog.py marketplace.json SHA [url]")
    catalog_path = sys.argv[1]
    sha = sys.argv[2]
    url = sys.argv[3] if len(sys.argv) > 3 else DEFAULT_URL
    pin(catalog_path, sha, url)


if __name__ == "__main__":
    main()
