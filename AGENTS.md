# Tinytray

This file is for someone changing Tinytray. How to install and use it lives in [README.md](README.md).

Tinytray is an Omarchy bar plugin. It replaces `omarchy.tray`, hosts chosen bar widgets in a hover drawer, and keeps Status Notifier app icons there too. Work in this checkout. Do not create a git worktree.

## Layout

`Tray.qml` is the bar widget. Decisions that can be tested without Quickshell belong in `TrayModel.js`. `TinytrayIcon.qml` draws the manage-hero mark as a `Shape`, not a rasterized SVG. `scan-catalog.py` lists installed bar widgets. `restore-hosted.py` and `uninstall` put hosted widgets back on the bar after Tinytray is removed.

The live copy Omarchy loads is `~/.config/omarchy/plugins/vincentritter.tinytray`. Copy changed files there and run `omarchy restart shell`. Plugin hot reload of QML is unreliable; a restart is the check that counts.

## Tests

```bash
node --test TrayModel.test.js
```

A new decision (catalog membership, hosting, persist merge, status copy, chevron ids) belongs in `TrayModel.js` with a test that fails if that decision flips. QML is not unit-tested. Prove UI by using it in the running shell.

Hosting something that is already on this side of the bar must disable that bar copy (`setBarEnabled: false`). Hosting something that is not on the bar must not (`setBarEnabled: null`). Pin, hide, and extra-widget writes must go through `mergeSettings` so they do not drop `chevron` or other keys.

## UI

Match the built-in Omarchy panels so the widget feels native: `PanelHero`, `PanelSectionHeader`, `PanelSeparator`, `ToggleSwitch`, `CursorSurface`, `PanelActionButton`. Do not invent form chrome (Add/Remove text buttons, parenthetical titles).

The bar glyph is the chevron picker (`chevron`, `caret`, `angle`, `arrow`, `double`, `dot`). The manage hero uses `TinytrayIcon`. Do not put the logo on the bar; the picker would then be pointless.

Keep comments out of QML and JS unless the code cannot express a constraint. The submenu stack in `Tray.qml` is one of those: platform menus do not work because the Omarchy shell is not a `QApplication`.

## Persistence

Settings live on the `vincentritter.tinytray` layout entry in `~/.config/omarchy/shell.json`. `extraWidgets` is the hosted list: missing means Bluetooth, Network, and Display; an empty list means none. `chevron` is the bar mark. Always merge into the existing entry. Assigning `root.settings` before `updateEntryInline` is how the bar updates before the file reload.

Omarchy’s bar already lets you drag widgets to reorder them. Dropping a widget on Tinytray parks it next to Tinytray, not in the drawer. `PluginBarApi` has no drag hook. Do not walk the QML parent chain to snoop `barDragSource`.

## Screenshots

`preview.png` is the manage card. `screenshots/` has the drawer, manage, and settings shots. Recapture on an empty workspace so the terminal is not in the crop. Do not commit a `Tray.qml` that opens settings on every manage click; that is only a local capture trick.

## Git

Atomic commits. One coherent change per commit. Do not attribute commits to a tool.
