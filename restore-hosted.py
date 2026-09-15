#!/usr/bin/env python3
import json
import os
import shutil
import stat
import subprocess
import sys
import time
from pathlib import Path

DEFAULT_HOSTED = ["omarchy.bluetooth", "omarchy.network", "omarchy.monitor"]
TINYTRAY_KEYS = ("extraWidgets", "chevron", "hidden", "pinned")
TRAY_ID = "vincentritter.tinytray"
STOCK_TRAY = "omarchy.tray"
HELPER_NAME = "tinytray-restore"


def load_shell(path):
    with open(path, encoding="utf-8") as fh:
        cfg = json.load(fh)
    if not isinstance(cfg, dict):
        raise ValueError("shell.json is not an object")
    return cfg


def save_shell(path, cfg):
    cfg["version"] = 1
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(cfg, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    os.replace(tmp, path)


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


def leaked_extra_widgets(cfg):
    for entry in layout_entries(cfg):
        if not isinstance(entry, dict) or str(entry.get("id") or "") != STOCK_TRAY:
            continue
        if "extraWidgets" not in entry:
            return None
        return [str(x) for x in (entry.get("extraWidgets") or []) if x]
    return None


def ids_to_restore(cfg, tray, cli_ids):
    if cli_ids:
        return [str(x) for x in cli_ids if x]
    try:
        return hosted_widget_ids(cfg, tray)
    except KeyError:
        leaked = leaked_extra_widgets(cfg)
        return leaked if leaked is not None else []


def restore_anchor(present, tray):
    if STOCK_TRAY in present:
        return STOCK_TRAY
    if tray in present:
        return tray
    return None


def enable_commands(present, tray, ids):
    cmds = []
    seen = list(present)
    anchor = restore_anchor(seen, tray)
    for widget_id in ids:
        if not widget_id or widget_id == tray:
            continue
        if widget_id in seen:
            anchor = widget_id
            continue
        place = ["--after", anchor] if anchor else ["--section", "right"]
        cmds.append(["omarchy", "plugin", "enable", widget_id] + place)
        seen.append(widget_id)
        anchor = widget_id
    return cmds


def strip_tinytray_keys(cfg):
    changed = False
    for entry in layout_entries(cfg):
        if not isinstance(entry, dict) or str(entry.get("id") or "") != STOCK_TRAY:
            continue
        for key in TINYTRAY_KEYS:
            if key in entry:
                del entry[key]
                changed = True
    return changed


def persist_stripped(path):
    for _ in range(12):
        cfg = load_shell(path)
        if not strip_tinytray_keys(cfg):
            return 0
        save_shell(path, cfg)
        time.sleep(0.15)
    cfg = load_shell(path)
    if not strip_tinytray_keys(cfg):
        return 0
    save_shell(path, cfg)
    return 1


def helper_path():
    return Path.home() / ".config/omarchy" / HELPER_NAME


def install_helper():
    dest = helper_path()
    dest.parent.mkdir(parents=True, exist_ok=True)
    try:
        shutil.copy2(__file__, dest)
    except shutil.SameFileError:
        pass
    dest.chmod(dest.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    return 0


def main(argv):
    dry = False
    force = False
    print_hosted = False
    do_install = False
    args = list(argv[1:])
    while args and args[0].startswith("--"):
        flag = args.pop(0)
        if flag == "--dry-run":
            dry = True
        elif flag == "--force":
            force = True
        elif flag == "--print-hosted":
            print_hosted = True
        elif flag == "--install-helper":
            do_install = True
        else:
            return 1
    if do_install:
        return install_helper()
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
    if len(args) == 0:
        shell_path = str(Path.home() / ".config/omarchy/shell.json")
        tray = TRAY_ID
        cli_ids = []
    elif len(args) < 2:
        return 1
    else:
        shell_path, tray = args[0], args[1]
        cli_ids = args[2:]
    try:
        cfg = load_shell(shell_path)
    except (OSError, json.JSONDecodeError, UnicodeError, ValueError):
        return 1
    present = entry_ids(cfg)
    if tray in present and not force:
        return 0
    ids = ids_to_restore(cfg, tray, cli_ids)
    for cmd in enable_commands(present, tray, ids):
        if dry:
            sys.stdout.write(" ".join(cmd) + "\n")
        else:
            subprocess.call(cmd)
    if dry:
        if strip_tinytray_keys(cfg):
            sys.stdout.write("strip omarchy.tray\n")
        return 0
    try:
        return persist_stripped(shell_path)
    except (OSError, json.JSONDecodeError, UnicodeError, ValueError):
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
