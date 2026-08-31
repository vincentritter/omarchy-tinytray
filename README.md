# vincent.tray

An Omarchy bar tray that keeps Status Notifier apps in a hover drawer and hosts Bluetooth, Network, Display, Dropbox, and Tailscale next to them. Pin an icon to keep it on the bar. Hide one to take it off the bar without dropping its panel hotkey.

This is a clone of `omarchy.tray`. Stock Omarchy only draws tray apps such as 1Password. The extra icons are bar widgets, so they live on the right of the bar unless this plugin hosts them.

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

Hover the chevron to open the drawer. Right-click the chevron to pin or hide an icon. Pinned icons stay visible. Hidden icons stay loaded so Super+Ctrl panel hotkeys still find them.

LocalSend is filtered out on purpose. Dropbox’s native tray icon is hidden while the Omarchy Dropbox widget is hosted, so you do not get two Dropbox marks.

## Tests

```bash
node --test TrayModel.test.js
```

## Update

```bash
omarchy plugin update vincent.tray --yes
```
