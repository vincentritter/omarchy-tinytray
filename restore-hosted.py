#!/usr/bin/env python3
import json
import subprocess
import sys

DEFAULT_HOSTED = ["omarchy.bluetooth", "omarchy.network", "omarchy.monitor"]


def load_shell(path):
    with open(path, encoding="utf-8") as fh:
        cfg = json.load(fh)
    if not isinstance(cfg, dict):
        raise ValueError("shell.json is not an object")
    return cfg


def layout_entries(cfg):
    layout = (cfg.get("bar") or {}).get("layout") or {}
    entries = []
    for name in ("left", "center", "right"):
        for entry in layout.get(name) or []:
            entries.append(entry)
    return entries


def entry_ids(cfg):
    ids = []
    for entry in layout_entries(cfg):
        key = entry.get("id") if isinstance(entry, dict) else entry
        if key:
            ids.append(str(key))
    return ids


def hosted_widget_ids(cfg, tray):
    for entry in layout_entries(cfg):
        if not isinstance(entry, dict) or str(entry.get("id") or "") != tray:
            continue
        if "extraWidgets" not in entry:
            return list(DEFAULT_HOSTED)
        return [str(x) for x in (entry.get("extraWidgets") or []) if x]
    raise KeyError(tray)


def main(argv):
    dry = False
    force = False
    print_hosted = False
    args = list(argv[1:])
    while args and args[0].startswith("--"):
        flag = args.pop(0)
        if flag == "--dry-run":
            dry = True
        elif flag == "--force":
            force = True
        elif flag == "--print-hosted":
            print_hosted = True
        else:
            return 1
    if print_hosted:
        if len(args) < 2:
            return 1
        try:
            ids = hosted_widget_ids(load_shell(args[0]), args[1])
        except (OSError, json.JSONDecodeError, UnicodeError, ValueError, KeyError):
            return 1
        if ids:
            sys.stdout.write("\n".join(ids) + "\n")
        return 0
    if len(args) < 2:
        return 1
    shell_path, tray = args[0], args[1]
    ids = args[2:]
    try:
        cfg = load_shell(shell_path)
    except (OSError, json.JSONDecodeError, UnicodeError, ValueError):
        return 1
    present = entry_ids(cfg)
    if tray in present and not force:
        return 0
    place = ["--before", "omarchy.audio"] if "omarchy.audio" in present else ["--section", "right"]
    for widget_id in ids:
        if not widget_id or widget_id == tray or widget_id in present:
            continue
        cmd = ["omarchy", "plugin", "enable", widget_id] + place
        if dry:
            sys.stdout.write(" ".join(cmd) + "\n")
        else:
            subprocess.call(cmd)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
