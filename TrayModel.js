function text(value) {
  return String(value || "").toLowerCase()
}

function itemNamed(item, name) {
  if (!item) return false
  return text(item.id).indexOf(name) !== -1
    || text(item.title).indexOf(name) !== -1
    || text(item.tooltipTitle).indexOf(name) !== -1
}

function entryId(entry) {
  if (typeof entry === "string") return entry
  if (entry && typeof entry === "object") {
    var id = entry.id
    if (id !== undefined && id !== null && String(id) !== "") return String(id)
  }
  return ""
}

function layoutHasWidget(layout, id) {
  return layoutSectionFor(layout, id) !== ""
}

function layoutSectionFor(layout, id) {
  var key = String(id || "")
  if (!key) return ""
  var sections = ["left", "center", "right"]
  for (var s = 0; s < sections.length; s++) {
    var name = sections[s]
    var entries = layout && layout[name]
    if (!Array.isArray(entries)) continue
    for (var i = 0; i < entries.length; i++) {
      if (entryId(entries[i]) === key) return name
    }
  }
  return ""
}

// LocalSend's item shows no state, offers only Open and Quit, and its primary
// click is a no-op, so Share > Receive is the whole surface. Hiding it by hand
// doesn't stick either: LocalSend picks a fresh tray id every launch.
// Dropbox's native SNI is suppressed whenever the Omarchy Dropbox widget is
// either on the bar or hosted inside this tray drawer.
function ownedByOmarchy(item, layout, extraIds) {
  extraIds = extraIds || []
  var dropboxHosted = layoutHasWidget(layout, "omarchy.dropbox")
    || extraIds.indexOf("omarchy.dropbox") !== -1
  return itemNamed(item, "localsend")
    || (dropboxHosted && itemNamed(item, "dropbox"))
}

function drawerAcceptsInput(expanded, hostedPanelOpen) {
  return !!(expanded || hostedPanelOpen)
}

function setDescendantClickable(node, on) {
  if (!node) return 0
  var count = 0
  if (typeof node.triggerPress === "function") {
    if (typeof node.interactive !== "undefined") node.interactive = !!on
    if (typeof node.pressable !== "undefined") node.pressable = !!on
    if (typeof node.concealed !== "undefined") node.concealed = !on
    var bar = node.bar
    if (bar) {
      if (on && typeof bar.registerClickTarget === "function") bar.registerClickTarget(node)
      if (!on && typeof bar.unregisterClickTarget === "function") bar.unregisterClickTarget(node)
    }
    count++
  }
  var kids = node.children
  if (!kids || !kids.length) return count
  for (var i = 0; i < kids.length; i++) count += setDescendantClickable(kids[i], on)
  return count
}

function defaultExtraWidgetIds() {
  return ["omarchy.bluetooth", "omarchy.network", "omarchy.monitor"]
}

function extraWidgetIdsFromSettings(settings, fallback) {
  var raw = settings ? settings.extraWidgets : undefined
  if (raw && typeof raw !== "string" && typeof raw.length === "number") {
    var out = []
    for (var i = 0; i < raw.length; i++) out.push(raw[i])
    return out
  }
  return Array.isArray(fallback) ? fallback.slice() : defaultExtraWidgetIds()
}

function toggleId(ids, id) {
  var key = String(id || "")
  var list = Array.isArray(ids) ? ids : []
  if (!key) return list.slice()
  var next = []
  var found = false
  for (var i = 0; i < list.length; i++) {
    if (String(list[i]) === key) {
      found = true
      continue
    }
    next.push(list[i])
  }
  if (!found) next.push(key)
  return next
}

function extraWidgetTogglePlan(currentIds, id, onBar, trayId) {
  var extras = toggleId(currentIds, id)
  var key = String(id || "")
  var adding = extras.indexOf(key) !== -1
  return {
    extras: extras,
    adding: adding,
    setBarEnabled: adding ? (onBar ? false : null) : true,
    placeAfter: adding ? "" : String(trayId || "")
  }
}

function barWidgetCommand(id, enabled, placeAfter) {
  var key = String(id || "")
  if (!key) return []
  if (!enabled) return ["omarchy", "plugin", "disable", key]
  var cmd = ["omarchy", "plugin", "enable", key]
  var after = String(placeAfter || "")
  if (after) {
    cmd.push("--after")
    cmd.push(after)
  } else {
    cmd.push("--section")
    cmd.push("right")
  }
  return cmd
}

function hostedIds(extraIds, layout) {
  var ids = extraIds && typeof extraIds.length === "number" ? extraIds : []
  var result = []
  for (var i = 0; i < ids.length; i++) {
    var id = String(ids[i] || "")
    if (!id) continue
    if (layoutHasWidget(layout, id)) continue
    result.push(id)
  }
  return result
}

function hostedIdsIn(hosted, pinned, hidden, category) {
  var ids = hosted && typeof hosted.length === "number" ? hosted : []
  var p = pinned && typeof pinned.length === "number" ? pinned : []
  var h = hidden && typeof hidden.length === "number" ? hidden : []
  var result = []
  for (var i = 0; i < ids.length; i++) {
    var id = ids[i]
    var bucketName = "drawer"
    if (h.indexOf(id) !== -1) bucketName = "hidden"
    else if (p.indexOf(id) !== -1) bucketName = "pinned"
    if (bucketName === category) result.push(id)
  }
  return result
}

function layoutWithoutWidget(layout, id) {
  var key = String(id || "")
  var next = { left: [], center: [], right: [] }
  var sections = ["left", "center", "right"]
  for (var s = 0; s < sections.length; s++) {
    var name = sections[s]
    var entries = layout && layout[name]
    var out = []
    if (Array.isArray(entries)) {
      for (var i = 0; i < entries.length; i++) {
        if (entryId(entries[i]) === key) continue
        out.push(entries[i])
      }
    }
    next[name] = out
  }
  return next
}

function catalogEntryFromManifest(sourceDir, manifest) {
  if (!manifest || typeof manifest !== "object") return null
  var kinds = manifest.kinds
  if (!Array.isArray(kinds) || kinds.indexOf("bar-widget") === -1) return null
  var ep = manifest.entryPoints && manifest.entryPoints.barWidget
  if (!ep || typeof ep !== "string") return null
  if (ep.indexOf("..") !== -1) return null
  var id = String(manifest.id || "")
  if (!id) return null
  var dir = String(sourceDir || "").replace(/\/+$/, "")
  if (!dir) return null
  var meta = manifest.barWidget && typeof manifest.barWidget === "object" ? manifest.barWidget : {}
  var title = String(meta.displayName || manifest.name || id)
  return {
    id: id,
    title: title,
    url: "file://" + dir + "/" + ep.replace(/^\/+/, "")
  }
}

function catalogRows(entries, extraIds, layout, trayId) {
  var skip = { "vincentritter.tinytray": true, "vincent.tray": true, "omarchy.tray": true }
  var extras = Array.isArray(extraIds) ? extraIds : []
  var traySection = layoutSectionFor(layout, trayId || "vincentritter.tinytray")
  var rows = []
  var seen = {}
  var list = Array.isArray(entries) ? entries : []
  for (var i = 0; i < list.length; i++) {
    var entry = list[i]
    if (!entry || skip[entry.id] || !entry.url) continue
    var inTray = extras.indexOf(entry.id) !== -1
    var section = layoutSectionFor(layout, entry.id)
    var onBar = section !== ""
    if (!inTray && traySection === "") continue
    if (!inTray && onBar && section !== traySection) continue
    seen[entry.id] = true
    rows.push({
      id: entry.id,
      title: String(entry.title || entry.id),
      url: entry.url,
      inTray: inTray,
      onBar: onBar
    })
  }
  for (var j = 0; j < extras.length; j++) {
    var extraId = String(extras[j] || "")
    if (!extraId || skip[extraId] || seen[extraId]) continue
    seen[extraId] = true
    rows.push({
      id: extraId,
      title: extraId,
      url: "",
      inTray: true,
      onBar: layoutHasWidget(layout, extraId)
    })
  }
  rows.sort(function (a, b) {
    return String(a.title).toLowerCase().localeCompare(String(b.title).toLowerCase())
  })
  return rows
}

function hostedWidgetUrl(omarchyPath, id, catalog) {
  var key = String(id || "")
  var list = Array.isArray(catalog) ? catalog : []
  for (var i = 0; i < list.length; i++) {
    if (list[i] && list[i].id === key && list[i].url) return String(list[i].url)
  }
  var prefix = "omarchy."
  if (key.indexOf(prefix) !== 0) return ""
  var name = key.slice(prefix.length)
  if (!name || name.indexOf(".") !== -1 || name.indexOf("/") !== -1) return ""
  var base = String(omarchyPath || "/usr/share/omarchy").replace(/\/+$/, "")
  if (!base) return ""
  return "file://" + base + "/shell/plugins/panels/" + name + "/Panel.qml"
}

function hostedPanelIsOpen(bar) {
  if (!bar || !bar.activePopout) return false
  if (bar.foreignPopoutMarker && bar.activePopout === bar.foreignPopoutMarker) return false
  return true
}

function widgetStatusText(inTray, onBar) {
  if (inTray) return "In the tray"
  if (onBar) return "On the bar"
  return "Not on the bar"
}

function appStatusText(isPinned, isHidden) {
  if (isHidden) return "Hidden"
  if (isPinned) return "Pinned"
  return "In the drawer"
}

function heroMeta(drawerCount, pinnedCount) {
  var drawer = Number(drawerCount) || 0
  var pinned = Number(pinnedCount) || 0
  var parts = []
  if (pinned > 0) parts.push(pinned + " pinned")
  if (drawer > 0) parts.push(drawer + " in the drawer")
  if (parts.length === 0) return "Empty drawer"
  return parts.join(" · ")
}

function itemDisplayName(item) {
  if (!item) return "Unknown"
  var title = String(item.title || "").trim()
  if (title) return title
  var tooltip = String(item.tooltipTitle || "").trim()
  if (tooltip) return tooltip
  var id = String(item.id || "")
  var slash = id.lastIndexOf("/")
  return slash !== -1 ? id.substring(slash + 1) : (id || "Unknown")
}

function chevronOptions() {
  return [
    { value: "chevron", label: "Chevron", glyph: "\uf053" },
    { value: "caret", label: "Caret", glyph: "\uf0d9" },
    { value: "angle", label: "Angle", glyph: "\uf104" },
    { value: "arrow", label: "Arrow", glyph: "\uf060" },
    { value: "double", label: "Double", glyph: "\uf100" },
    { value: "dot", label: "Dot", glyph: "\ueb8a" }
  ]
}

function chevronGlyph(id) {
  var key = String(id || "chevron")
  var options = chevronOptions()
  for (var i = 0; i < options.length; i++) {
    if (options[i].value === key) return options[i].glyph
  }
  return options[0].glyph
}

function chevronIdFromSettings(settings) {
  var id = settings && typeof settings.chevron === "string" ? settings.chevron : "chevron"
  var options = chevronOptions()
  for (var i = 0; i < options.length; i++) {
    if (options[i].value === id) return id
  }
  return "chevron"
}

function mergeSettings(settings, moduleName, values) {
  var entry = { id: String(moduleName || "") }
  if (settings && typeof settings === "object") {
    for (var existing in settings) {
      if (existing !== "id") entry[existing] = settings[existing]
    }
  }
  if (values && typeof values === "object") {
    for (var key in values) {
      if (values[key] === undefined) delete entry[key]
      else entry[key] = values[key]
    }
  }
  return entry
}

if (typeof module !== "undefined") {
  module.exports = {
    itemNamed: itemNamed,
    entryId: entryId,
    layoutHasWidget: layoutHasWidget,
    ownedByOmarchy: ownedByOmarchy,
    drawerAcceptsInput: drawerAcceptsInput,
    setDescendantClickable: setDescendantClickable,
    hostedWidgetUrl: hostedWidgetUrl,
    hostedPanelIsOpen: hostedPanelIsOpen,
    extraWidgetIdsFromSettings: extraWidgetIdsFromSettings,
    defaultExtraWidgetIds: defaultExtraWidgetIds,
    layoutSectionFor: layoutSectionFor,
    toggleId: toggleId,
    extraWidgetTogglePlan: extraWidgetTogglePlan,
    barWidgetCommand: barWidgetCommand,
    hostedIds: hostedIds,
    hostedIdsIn: hostedIdsIn,
    layoutWithoutWidget: layoutWithoutWidget,
    catalogEntryFromManifest: catalogEntryFromManifest,
    catalogRows: catalogRows,
    widgetStatusText: widgetStatusText,
    appStatusText: appStatusText,
    heroMeta: heroMeta,
    itemDisplayName: itemDisplayName,
    chevronOptions: chevronOptions,
    chevronGlyph: chevronGlyph,
    chevronIdFromSettings: chevronIdFromSettings,
    mergeSettings: mergeSettings
  }
}
