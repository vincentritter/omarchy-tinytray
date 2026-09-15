const test = require("node:test")
const assert = require("node:assert/strict")
const { spawnSync } = require("node:child_process")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const TrayModel = require("./TrayModel.js")
const restoreScript = path.join(__dirname, "restore-hosted.py")

function writeShell(layout) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "tinytray-"))
  const file = path.join(dir, "shell.json")
  fs.writeFileSync(file, JSON.stringify({ bar: { layout } }))
  return file
}

function dryRestore(shell, tray, ids, extraFlags) {
  const flags = extraFlags || []
  return spawnSync("python3", [restoreScript].concat(flags, ["--dry-run", shell, tray], ids), {
    encoding: "utf8"
  })
}

function clickable(target) {
  return !!(
    target
    && target.visible !== false
    && target.opacity !== 0
    && target.interactive !== false
    && target.pressable !== false
    && target.concealed !== true
    && typeof target.triggerPress === "function"
  )
}

function applyConcealedOpacity(node) {
  node.opacity = node.concealed ? 0 : 1
}

function panelPressable(target) {
  return !!(target && target.triggerPress && target.visible !== false && target.opacity !== 0)
}

function pressTargetAt(targets) {
  for (var i = targets.length - 1; i >= 0; i--) {
    if (panelPressable(targets[i])) return targets[i]
  }
  return null
}

function button(overrides) {
  return Object.assign({
    triggerPress: function () {},
    interactive: true,
    pressable: true,
    visible: true,
    opacity: 1,
    concealed: false,
    children: []
  }, overrides)
}

test("drawer rejects input when collapsed", () => {
  assert.equal(TrayModel.drawerAcceptsInput(false, false), false)
})

test("drawer accepts input while expanded or a hosted panel is open", () => {
  assert.equal(TrayModel.drawerAcceptsInput(true, false), true)
  assert.equal(TrayModel.drawerAcceptsInput(false, true), true)
})

test("collapsed drawer buttons are skipped by bar click dispatch", () => {
  const bluetooth = button()
  const panel = { children: [bluetooth] }
  assert.equal(clickable(bluetooth), true)

  TrayModel.setDescendantClickable(panel, false)

  assert.equal(bluetooth.interactive, false)
  assert.equal(bluetooth.pressable, false)
  assert.equal(bluetooth.concealed, true)
  assert.equal(clickable(bluetooth), false)
})

test("open panel click on battery does not fire overlapping wifi", () => {
  const network = button()
  const power = button()
  TrayModel.setDescendantClickable({ children: [network] }, false)
  applyConcealedOpacity(network)
  applyConcealedOpacity(power)
  assert.equal(panelPressable(network), false)
  assert.equal(pressTargetAt([power, network]), power)
})

test("collapsed drawer buttons leave the panel click list immediately", () => {
  const targets = []
  const bar = {
    clickTargets: targets,
    registerClickTarget: function (t) { if (targets.indexOf(t) === -1) targets.push(t) },
    unregisterClickTarget: function (t) {
      var i = targets.indexOf(t)
      if (i !== -1) targets.splice(i, 1)
    }
  }
  const power = button({ bar: bar })
  const network = button({ bar: bar })
  bar.registerClickTarget(power)
  bar.registerClickTarget(network)
  TrayModel.setDescendantClickable({ children: [network] }, false)
  assert.equal(targets.indexOf(network), -1)
  assert.equal(pressTargetAt(targets), power)
  TrayModel.setDescendantClickable({ children: [network] }, true)
  assert.notEqual(targets.indexOf(network), -1)
})

test("pinned or revealed drawer buttons stay dispatchable", () => {
  const bluetooth = button({ interactive: false, pressable: false, concealed: true, opacity: 0 })
  TrayModel.setDescendantClickable({ children: [bluetooth] }, true)
  applyConcealedOpacity(bluetooth)
  assert.equal(bluetooth.concealed, false)
  assert.equal(clickable(bluetooth), true)
  assert.equal(panelPressable(bluetooth), true)
})

test("walker returns 0 until a pressable child exists", () => {
  const panel = { children: [] }
  assert.equal(TrayModel.setDescendantClickable(panel, false), 0)
  panel.children = [button()]
  assert.equal(TrayModel.setDescendantClickable(panel, false), 1)
})

test("non-button descendants are left alone", () => {
  const label = { interactive: true, children: [] }
  TrayModel.setDescendantClickable({ children: [label] }, false)
  assert.equal(label.interactive, true)
})

test("hosted omarchy panels resolve to first-party Panel.qml urls", () => {
  assert.equal(
    TrayModel.hostedWidgetUrl("/usr/share/omarchy", "omarchy.bluetooth"),
    "file:///usr/share/omarchy/shell/plugins/panels/bluetooth/Panel.qml"
  )
  assert.equal(
    TrayModel.hostedWidgetUrl("/usr/share/omarchy/", "omarchy.network"),
    "file:///usr/share/omarchy/shell/plugins/panels/network/Panel.qml"
  )
})

test("hosted widget urls ignore unknown or non-omarchy ids", () => {
  assert.equal(TrayModel.hostedWidgetUrl("/usr/share/omarchy", "vincentritter.tinytray"), "")
  assert.equal(TrayModel.hostedWidgetUrl("/usr/share/omarchy", ""), "")
  assert.equal(TrayModel.hostedWidgetUrl("/usr/share/omarchy", "omarchy"), "")
})

test("hosted panel open ignores a foreign popout on the plugin bar facade", () => {
  const foreign = { foreign: true }
  assert.equal(TrayModel.hostedPanelIsOpen({ activePopout: null, foreignPopoutMarker: foreign }), false)
  assert.equal(TrayModel.hostedPanelIsOpen({ activePopout: foreign, foreignPopoutMarker: foreign }), false)
  assert.equal(TrayModel.hostedPanelIsOpen({ activePopout: { opened: true }, foreignPopoutMarker: foreign }), true)
})

test("missing extraWidgets keeps the default list, an empty array means none", () => {
  const fallback = ["omarchy.bluetooth"]
  assert.deepEqual(TrayModel.extraWidgetIdsFromSettings({}, fallback), ["omarchy.bluetooth"])
  assert.deepEqual(TrayModel.extraWidgetIdsFromSettings({ extraWidgets: [] }, fallback), [])
  assert.deepEqual(
    TrayModel.extraWidgetIdsFromSettings({ extraWidgets: ["omarchy.audio"] }, fallback),
    ["omarchy.audio"]
  )
  const like = { 0: "omarchy.audio", 1: "omarchy.power", length: 2 }
  assert.deepEqual(TrayModel.extraWidgetIdsFromSettings({ extraWidgets: like }, fallback), ["omarchy.audio", "omarchy.power"])
})

test("default hosted widgets are bluetooth, network, and display", () => {
  assert.deepEqual(TrayModel.defaultExtraWidgetIds(), ["omarchy.bluetooth", "omarchy.network", "omarchy.monitor"])
  assert.deepEqual(TrayModel.extraWidgetIdsFromSettings({}), ["omarchy.bluetooth", "omarchy.network", "omarchy.monitor"])
})

test("toggleId adds a missing widget and removes one that is already listed", () => {
  assert.deepEqual(TrayModel.toggleId(["omarchy.bluetooth"], "omarchy.audio"), ["omarchy.bluetooth", "omarchy.audio"])
  assert.deepEqual(TrayModel.toggleId(["omarchy.bluetooth", "omarchy.audio"], "omarchy.bluetooth"), ["omarchy.audio"])
  assert.deepEqual(TrayModel.toggleId(["omarchy.bluetooth"], ""), ["omarchy.bluetooth"])
})

test("adding a bar widget takes it off the bar so the tray can host it", () => {
  const add = TrayModel.extraWidgetTogglePlan(["omarchy.bluetooth"], "omarchy.audio", true)
  assert.deepEqual(add.extras, ["omarchy.bluetooth", "omarchy.audio"])
  assert.equal(add.adding, true)
  assert.equal(add.setBarEnabled, false)

  const remove = TrayModel.extraWidgetTogglePlan(["omarchy.bluetooth", "omarchy.audio"], "omarchy.audio", false)
  assert.deepEqual(remove.extras, ["omarchy.bluetooth"])
  assert.equal(remove.adding, false)
  assert.equal(remove.setBarEnabled, true)
})

test("hostedIds skips widgets that are still on the bar", () => {
  assert.deepEqual(
    TrayModel.hostedIds(["omarchy.audio", "omarchy.bluetooth"], { right: [{ id: "omarchy.audio" }] }),
    ["omarchy.bluetooth"]
  )
})

test("layoutWithoutWidget drops one id and leaves the others", () => {
  const layout = { right: [{ id: "omarchy.audio" }, { id: "vincentritter.tinytray" }] }
  const next = TrayModel.layoutWithoutWidget(layout, "omarchy.audio")
  assert.equal(TrayModel.layoutHasWidget(next, "omarchy.audio"), false)
  assert.equal(TrayModel.layoutHasWidget(next, "vincentritter.tinytray"), true)
})

test("catalog entries require a bar-widget manifest and a qml file url", () => {
  const panel = TrayModel.catalogEntryFromManifest("/usr/share/omarchy/shell/plugins/panels/bluetooth", {
    id: "omarchy.bluetooth",
    name: "Bluetooth",
    kinds: ["bar-widget"],
    entryPoints: { barWidget: "Panel.qml" },
    barWidget: { displayName: "Bluetooth" }
  })
  assert.equal(panel.id, "omarchy.bluetooth")
  assert.equal(panel.title, "Bluetooth")
  assert.equal(panel.url, "file:///usr/share/omarchy/shell/plugins/panels/bluetooth/Panel.qml")

  assert.equal(TrayModel.catalogEntryFromManifest("/tmp/speedtest", {
    id: "omarchy.speedtest",
    kinds: ["panel"],
    entryPoints: { panel: "Panel.qml" }
  }), null)
})

test("catalog rows skip the tray itself and sort by title", () => {
  const rows = TrayModel.catalogRows([
    { id: "vincentritter.tinytray", title: "Tinytray", url: "file:///tmp/Tray.qml" },
    { id: "vincent.tray", title: "My System tray", url: "file:///tmp/old.qml" },
    { id: "omarchy.tray", title: "System tray", url: "file:///tmp/stock.qml" },
    { id: "omarchy.audio", title: "Audio", url: "file:///tmp/audio.qml" },
    { id: "omarchy.bluetooth", title: "Bluetooth", url: "file:///tmp/bt.qml" }
  ], ["omarchy.bluetooth"], {
    right: [
      { id: "omarchy.audio" },
      { id: "vincentritter.tinytray" },
      { id: "vincent.tray" },
      { id: "omarchy.tray" }
    ]
  }, "vincentritter.tinytray")
  assert.equal(rows.length, 2)
  assert.equal(rows[0].id, "omarchy.audio")
  assert.equal(rows[0].onBar, true)
  assert.equal(rows[0].inTray, false)
  assert.equal(rows[1].id, "omarchy.bluetooth")
  assert.equal(rows[1].inTray, true)
  assert.equal(rows[1].onBar, false)
})

test("catalog rows omit widgets that sit on another side of the bar", () => {
  const rows = TrayModel.catalogRows([
    { id: "omarchy.clock", title: "Clock", url: "file:///tmp/clock.qml" },
    { id: "jankeesvw.herdr", title: "Herdr", url: "file:///tmp/herdr.qml" },
    { id: "omarchy.audio", title: "Audio", url: "file:///tmp/audio.qml" },
    { id: "omarchy.bluetooth", title: "Bluetooth", url: "file:///tmp/bt.qml" }
  ], ["omarchy.bluetooth"], {
    left: [{ id: "jankeesvw.herdr" }],
    center: [{ id: "omarchy.clock" }],
    right: [{ id: "vincentritter.tinytray" }, { id: "omarchy.audio" }]
  }, "vincentritter.tinytray")
  assert.deepEqual(rows.map(function (row) { return row.id }), ["omarchy.audio", "omarchy.bluetooth"])
})

test("catalog rows include off-bar dropbox and tailscale so they can be added", () => {
  const rows = TrayModel.catalogRows([
    { id: "omarchy.dropbox", title: "Dropbox", url: "file:///tmp/dropbox.qml" },
    { id: "omarchy.tailscale", title: "Tailscale", url: "file:///tmp/ts.qml" },
    { id: "omarchy.clock", title: "Clock", url: "file:///tmp/clock.qml" }
  ], [], {
    center: [{ id: "omarchy.clock" }],
    right: [{ id: "vincentritter.tinytray" }]
  }, "vincentritter.tinytray")
  assert.deepEqual(rows.map(function (row) { return row.id }), ["omarchy.dropbox", "omarchy.tailscale"])
  assert.equal(rows[0].onBar, false)
  assert.equal(rows[0].inTray, false)
})

test("catalog rows keep extraWidgets that the scan missed so they can be removed", () => {
  const rows = TrayModel.catalogRows([], ["omarchy.dropbox"], {})
  assert.equal(rows.length, 1)
  assert.equal(rows[0].id, "omarchy.dropbox")
  assert.equal(rows[0].inTray, true)
})

test("hosted widget url prefers a catalog entry over the omarchy panel convention", () => {
  const catalog = [{ id: "omarchy.clock", url: "file:///tmp/BarWidget.qml" }]
  assert.equal(
    TrayModel.hostedWidgetUrl("/usr/share/omarchy", "omarchy.clock", catalog),
    "file:///tmp/BarWidget.qml"
  )
  assert.equal(
    TrayModel.hostedWidgetUrl("/usr/share/omarchy", "omarchy.bluetooth", catalog),
    "file:///usr/share/omarchy/shell/plugins/panels/bluetooth/Panel.qml"
  )
})

test("restore script no-ops while the tray is still in shell.json", () => {
  const shell = writeShell({
    right: [{ id: "vincentritter.tinytray" }, { id: "omarchy.audio" }]
  })
  const result = dryRestore(shell, "vincentritter.tinytray", ["omarchy.bluetooth"])
  assert.equal(result.status, 0)
  assert.equal(result.stdout, "")
})

test("restore script re-enables hosted widgets before audio", () => {
  const shell = writeShell({
    right: [{ id: "omarchy.tray" }, { id: "omarchy.audio" }]
  })
  const result = dryRestore(shell, "vincentritter.tinytray", ["omarchy.bluetooth", "omarchy.network"])
  assert.equal(result.status, 0)
  assert.equal(
    result.stdout,
    "omarchy plugin enable omarchy.bluetooth --before omarchy.audio\n" +
      "omarchy plugin enable omarchy.network --before omarchy.audio\n"
  )
})

test("restore script skips widgets already on the bar and uses the right section without audio", () => {
  const shell = writeShell({
    right: [{ id: "omarchy.tray" }, { id: "omarchy.bluetooth" }]
  })
  const result = dryRestore(shell, "vincentritter.tinytray", ["omarchy.bluetooth", "omarchy.dropbox"])
  assert.equal(result.status, 0)
  assert.equal(result.stdout, "omarchy plugin enable omarchy.dropbox --section right\n")
})

test("restore --force re-enables hosted widgets while Tinytray is still in the layout", () => {
  const shell = writeShell({
    right: [{ id: "vincentritter.tinytray" }, { id: "omarchy.audio" }]
  })
  const skipped = dryRestore(shell, "vincentritter.tinytray", ["omarchy.bluetooth"])
  assert.equal(skipped.status, 0)
  assert.equal(skipped.stdout, "")
  const forced = dryRestore(shell, "vincentritter.tinytray", ["omarchy.bluetooth"], ["--force"])
  assert.equal(forced.status, 0)
  assert.equal(forced.stdout, "omarchy plugin enable omarchy.bluetooth --before omarchy.audio\n")
})

test("print-hosted uses defaults when extraWidgets is missing and none when it is empty", () => {
  const missing = writeShell({
    right: [{ id: "vincentritter.tinytray" }]
  })
  const missingOut = spawnSync("python3", [restoreScript, "--print-hosted", missing, "vincentritter.tinytray"], {
    encoding: "utf8"
  })
  assert.equal(missingOut.status, 0)
  assert.equal(missingOut.stdout, "omarchy.bluetooth\nomarchy.network\nomarchy.monitor\n")

  const empty = writeShell({
    right: [{ id: "vincentritter.tinytray", extraWidgets: [] }]
  })
  const emptyOut = spawnSync("python3", [restoreScript, "--print-hosted", empty, "vincentritter.tinytray"], {
    encoding: "utf8"
  })
  assert.equal(emptyOut.status, 0)
  assert.equal(emptyOut.stdout, "")

  const listed = writeShell({
    right: [{ id: "vincentritter.tinytray", extraWidgets: ["omarchy.dropbox"] }]
  })
  const listedOut = spawnSync("python3", [restoreScript, "--print-hosted", listed, "vincentritter.tinytray"], {
    encoding: "utf8"
  })
  assert.equal(listedOut.status, 0)
  assert.equal(listedOut.stdout, "omarchy.dropbox\n")

  const absent = writeShell({ right: [{ id: "omarchy.tray" }] })
  const absentOut = spawnSync("python3", [restoreScript, "--print-hosted", absent, "vincentritter.tinytray"], {
    encoding: "utf8"
  })
  assert.equal(absentOut.status, 1)
})
