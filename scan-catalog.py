#!/usr/bin/env python3
import json
import sys
from pathlib import Path


def entry(source_dir):
    path = source_dir / "manifest.json"
    if not path.is_file():
        return None
    try:
        manifest = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError, UnicodeError):
        return None
    if not isinstance(manifest, dict):
        return None
    kinds = manifest.get("kinds") or []
    if "bar-widget" not in kinds:
        return None
    ep = (manifest.get("entryPoints") or {}).get("barWidget")
    if not isinstance(ep, str) or not ep or ".." in ep.split("/"):
        return None
    widget_id = str(manifest.get("id") or "")
    if not widget_id:
        return None
    qml = source_dir / ep
    if not qml.is_file():
        return None
    meta = manifest.get("barWidget") if isinstance(manifest.get("barWidget"), dict) else {}
    title = str(meta.get("displayName") or manifest.get("name") or widget_id)
    return {"id": widget_id, "title": title, "url": qml.resolve().as_uri()}


def main():
    found = []
    seen = set()
    for root in sys.argv[1:]:
        base = Path(root)
        if not base.is_dir():
            continue
        for child in sorted(base.iterdir()):
            if not child.is_dir():
                continue
            item = entry(child)
            if not item or item["id"] in seen:
                continue
            seen.add(item["id"])
            found.append(item)
    json.dump(found, sys.stdout)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
