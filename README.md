# vincent.tray

An Omarchy bar tray that keeps Status Notifier apps in a hover drawer and can host other bar widgets next to them. Right-click the chevron to add or remove those widgets. Pin an app icon to keep it on the bar. Hide one to take it off the bar.

This is a clone of `omarchy.tray`. Stock Omarchy only draws tray apps such as 1Password. Extra icons are bar widgets, so they live on the right of the bar unless this plugin hosts them. If `extraWidgets` is missing from the layout entry, the tray starts with Bluetooth, Network, Display, Dropbox, and Tailscale. An empty list means none.

## Install

The repository is private. Add it over SSH:

```bash
omarchy plugin add git@github.com:vincentritter/omarchy-tray.git --enable
```

Take the hosted widgets off the bar so the tray can hold them:

```bash
omarchy plugin disable omarchy.bluetooth
omarchy plugin disable omarchy.network
omarchy plugin disable omarchy.monitor
omarchy plugin disable omarchy.dropbox
omarchy plugin disable omarchy.tailscale
```

Audio and Power stay on the bar.

## Use

Hover the chevron to open the drawer. Right-click the chevron to add or remove bar widgets, or to pin and hide app icons. Pinned icons stay visible. Hidden icons leave the bar and can be shown again from that menu.

The hosted list is `extraWidgets` on the `vincent.tray` layout entry in `~/.config/omarchy/shell.json`. Add takes a widget off the bar so the tray can show it. Remove puts it back on the bar.

LocalSend is filtered out on purpose. Dropbox’s native tray icon is hidden while the Omarchy Dropbox widget is hosted, so you do not get two Dropbox marks.

## Tests

```bash
node --test TrayModel.test.js
```

## Update

```bash
omarchy plugin update vincent.tray --yes
```
