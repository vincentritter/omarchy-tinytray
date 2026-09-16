# Tinytray

<img src="logo.svg" width="64" height="64" alt="">

Tinytray is an opinionated hover drawer for the Omarchy bar. App icons such as 1Password sit in the drawer, and other bar widgets can sit next to them instead of taking a permanent slot on the right.

Stock Omarchy only draws tray apps. Bluetooth, Network, and Display are bar widgets, so they stay on the bar unless something hosts them. Tinytray replaces `omarchy.tray` and hosts those three in the drawer on first run. Pin an app icon to keep it visible. Hide one to take it off the bar.

![Tinytray drawer](screenshots/drawer.png)

## Install

```bash
omarchy plugin add https://github.com/vincentritter/omarchy-tinytray.git --enable
```

Enabling Tinytray swaps the built-in tray for it. Audio and Power stay on the bar unless you host them. Dropbox, Tailscale, and other widgets on this side can move into the drawer from the manage menu.

## Use

Hover the chevron to open the drawer. These shots use the dot. Click it to host or return bar widgets, and to pin or hide app icons. Hidden icons come back from that same menu.

![Tinytray manage menu](preview.png)

The menu lists widgets on this side of the bar, and installed widgets that are not on the bar. It does not take anything off the other side. A switch on hosts the widget in the tray and removes it from this side. A switch off puts it back. Widgets that are installed but missing from the layout are marked not on the bar.

LocalSend is left out. Its tray item has no state, its click does nothing, and it picks a new id every launch, so hiding it by hand would not stick. Dropbox’s native tray icon is hidden while the Omarchy Dropbox widget is on the bar or in the drawer, so you do not get two Dropbox marks.

The gear opens settings, including which chevron to show.

![Tinytray settings](screenshots/settings.png)

## Update

```bash
omarchy plugin update vincentritter.tinytray --yes
```

## Remove

```bash
omarchy plugin remove vincentritter.tinytray --yes
```

The built-in tray comes back. Hosted widgets return after it, in the order they were hosted. Tinytray’s settings are not left on that tray entry.

If the shell was not running, run `~/.config/omarchy/tinytray-restore`. The copy in the plugin directory still does both steps: `~/.config/omarchy/plugins/vincentritter.tinytray/uninstall`.

Tinytray is [MIT](LICENSE) licensed. It needs Omarchy. Catalog scan and restore use Python 3.

Built by [Vincent Ritter](https://vincentritter.com).
