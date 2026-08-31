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
  var sections = ["left", "center", "right"]
  for (var s = 0; s < sections.length; s++) {
    var entries = layout && layout[sections[s]]
    if (!Array.isArray(entries)) continue
    for (var i = 0; i < entries.length; i++) {
      if (entryId(entries[i]) === id) return true
    }
  }
  return false
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

if (typeof module !== "undefined") {
  module.exports = {
    itemNamed: itemNamed,
    entryId: entryId,
    layoutHasWidget: layoutHasWidget,
    ownedByOmarchy: ownedByOmarchy,
    drawerAcceptsInput: drawerAcceptsInput,
    setDescendantClickable: setDescendantClickable
  }
}
