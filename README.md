# Tinytray

Tinytray is an Omarchy bar tray. Status Notifier apps sit in a hover drawer, and other bar widgets can sit next to them instead of taking a permanent slot on the right.

Stock Omarchy only draws tray apps such as 1Password. Bluetooth, Network, and Display are bar widgets, so they live on the bar unless something hosts them. Tinytray replaces `omarchy.tray` and hosts those widgets in the drawer. Pin an app icon to keep it visible. Hide one to take it off the bar.

![Tinytray on the Omarchy bar](preview.png)

## Install

```bash
omarchy plugin add https://github.com/vincentritter/omarchy-tinytray.git --enable
```

Enabling Tinytray swaps the built-in tray for it. Bluetooth, Network, and Display move into the drawer on first run. Audio and Power stay on the bar. Right-click the chevron to add or remove other widgets, including Dropbox and Tailscale.

## Use

Hover the chevron to open the drawer. Right-click it to add or remove bar widgets, or to pin and hide app icons. Hidden icons come back from that same menu.

The menu offers widgets on the same side of the bar as the tray, and widgets that are not on the bar. It does not pull anything off the other side. Add hosts a widget in the tray and takes it off this side of the bar if it is there. Remove puts it back.

LocalSend is filtered out on purpose. Dropbox’s native tray icon is hidden while the Omarchy Dropbox widget is hosted, so you do not get two Dropbox marks.

The hosted list is `extraWidgets` on the `vincentritter.tinytray` layout entry in `~/.config/omarchy/shell.json`. If the key is missing, Bluetooth, Network, and Display are hosted. An empty list means none.

## Update

```bash
omarchy plugin update vincentritter.tinytray --yes
```

## Remove

```bash
omarchy plugin remove vincentritter.tinytray --yes
```

Removal restores the built-in tray.

## Tests

```bash
node --test TrayModel.test.js
```
