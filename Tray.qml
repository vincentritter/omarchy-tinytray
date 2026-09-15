import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell.Services.SystemTray
import qs.Commons
import qs.Ui
import "TrayModel.js" as TrayModel

BarWidget {
  id: root
  moduleName: "vincentritter.tinytray"

  property bool expanded: false
  property bool managePopupOpen: false
  property bool settingsOpen: false
  property bool pendingSettingsOpen: false
  property bool trayMenuOpen: false
  property var activeTrayItem: null
  property var activeTrayAnchor: null
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var pinnedIds: settings.pinned instanceof Array ? settings.pinned : []
  readonly property var hiddenIds: settings.hidden instanceof Array ? settings.hidden : []
  readonly property var defaultExtraWidgets: TrayModel.defaultExtraWidgetIds()
  property var extraWidgetOverride: null
  readonly property var extraWidgetIds: extraWidgetOverride !== null
    ? extraWidgetOverride
    : TrayModel.extraWidgetIdsFromSettings(settings, defaultExtraWidgets)
  readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
  readonly property string catalogScript: String(Qt.resolvedUrl("scan-catalog.py")).replace(/^file:\/\//, "")
  property var widgetCatalog: []
  readonly property var widgetCatalogRows: {
    var _c = widgetCatalog
    var _e = extraWidgetIds
    var layout = root.bar && root.bar.layoutConfig ? root.bar.layoutConfig : null
    return TrayModel.catalogRows(_c, _e, layout, root.moduleName)
  }
  readonly property var hostedWidgetIds: TrayModel.hostedIds(extraWidgetIds, root.bar ? root.bar.layoutConfig : null)
  readonly property var hostedPinnedIds: TrayModel.hostedIdsIn(hostedWidgetIds, pinnedIds, hiddenIds, "pinned")
  readonly property var hostedDrawerIds: TrayModel.hostedIdsIn(hostedWidgetIds, pinnedIds, hiddenIds, "drawer")
  readonly property var hostedHiddenIds: TrayModel.hostedIdsIn(hostedWidgetIds, pinnedIds, hiddenIds, "hidden")
  readonly property var pinnedItems: bucket("pinned")
  readonly property var drawerItems: bucket("drawer")
  readonly property var allItems: bucket("all")
  readonly property var manageItems: allItems
  readonly property bool hasDrawer: allItems.length > 0 || hostedWidgetIds.length > 0
  readonly property int drawerCount: drawerItems.length + hostedDrawerIds.length
  readonly property int trayItemExtent: Style.bar.iconSlot
  readonly property int trayItemGap: 0
  readonly property int trayJoinGap: 0
  readonly property int drawerExtent: drawerCount > 0 ? drawerCount * trayItemExtent + (drawerCount - 1) * trayItemGap : 0
  // Match Waybar's group/tray-expander drawer transition-duration.
  readonly property int animationDuration: 600
  readonly property bool hostedPanelOpen: TrayModel.hostedPanelIsOpen(root.bar)
  readonly property bool drawerAcceptsInput: TrayModel.drawerAcceptsInput(expanded, hostedPanelOpen)
  property real revealProgress: (expanded || hostedPanelOpen) ? 1 : 0
  readonly property real revealExtent: drawerExtent * revealProgress

  // Submenu drill-down state. QsMenuEntry.display() renders a *platform* menu,
  // which Quickshell refuses unless the shell root sets `//@ pragma
  // UseQApplication` - omarchy's shell.qml does not, so every submenu click was
  // a silent no-op ("Cannot display PlatformMenuEntry as quickshell was not
  // started in QApplication mode" in the shell log) and apps whose whole UI is
  // submenus, e.g. radiotray-ng's station list, were unusable. QsMenuEntry
  // inherits QsMenuHandle, so a child entry can feed a nested QsMenuOpener and
  // render inside this popup instead of going through the platform. Each level
  // keeps its own live opener: a child entry is owned by its parent opener's
  // model, so collapsing the stack to a single opener would destroy the very
  // entry being displayed (submenu turns up empty).
  property var submenuStack: []
  readonly property int submenuDepth: submenuStack.length
  readonly property string currentTitle: submenuDepth > 0 ? submenuStack[submenuDepth - 1].title : ""
  readonly property var currentChildren: submenuDepth > 0
    ? submenuStack[submenuDepth - 1].opener.children
    : trayMenuOpener.children

  // Changing level rebuilds the row delegates synchronously, so the next
  // row lands under a cursor that hasn't moved. Submenu clicks used to be
  // silent no-ops, which trained users to click them twice, and that second
  // click would now fire whatever entry took the spot. Ignore row clicks for
  // a beat after each level change; a deliberate follow-up click is slower.
  property bool menuLevelSettling: false

  Component {
    id: submenuOpenerComponent
    QsMenuOpener {}
  }

  Timer {
    id: menuLevelSettleTimer
    interval: 250
    onTriggered: root.menuLevelSettling = false
  }

  function settleMenuLevel() {
    menuLevelSettling = true
    menuLevelSettleTimer.restart()
  }

  function resetTrayMenu() {
    menuLevelSettling = false
    menuLevelSettleTimer.stop()
    // Flickable keeps its offset across a model swap whenever the new content
    // is still tall enough to hold it, so a menu dismissed while scrolled
    // would otherwise reopen part-way down with its first entries off screen.
    trayMenuFlick.contentY = 0
    // Clear the reactive stack before tearing anything down, so no binding can
    // read a partially-destroyed opener while this runs. Then destroy deepest
    // first: an inner opener's menu entry is owned by its parent's children
    // model, so destroying a parent first would invalidate an entry a still-
    // live child opener references.
    var openers = submenuStack
    submenuStack = []
    for (var i = openers.length - 1; i >= 0; i--) openers[i].opener.destroy()
  }

  function enterSubmenu(entry, title) {
    var opener = submenuOpenerComponent.createObject(root, { menu: entry })
    if (!opener) return
    var stack = submenuStack.slice()
    stack.push({ opener: opener, title: title })
    submenuStack = stack
    settleMenuLevel()
  }

  function leaveSubmenu() {
    if (submenuStack.length === 0) return
    var stack = submenuStack.slice()
    var top = stack.pop()
    submenuStack = stack
    top.opener.destroy()
    settleMenuLevel()
  }

  function close() {
    managePopupOpen = false
    trayMenuOpen = false
  }

  function openTrayMenu(item, anchorItem, mouse) {
    if (!item || !item.menu) {
      var point = anchorItem.QsWindow.contentItem.mapFromItem(anchorItem, mouse.x, mouse.y)
      item.display(anchorItem.QsWindow.window, point.x, point.y)
      return
    }

    // Reset before switching items: trayMenuOpener.menu binds to
    // activeTrayItem.menu, so assigning a new item invalidates the old root's
    // children immediately, before any nested opener referencing them would
    // otherwise get torn down.
    resetTrayMenu()
    activeTrayItem = item
    activeTrayAnchor = anchorItem
    trayMenuOpen = true
  }

  function trayIconSource(icon) {
    // Quickshell already resolves the tray icon into a ready-to-use image://
    // URL, including a "?path=" fallback search dir for apps that ship their
    // tray icon outside a standard theme (e.g. Steam's flat public/ dir). Hand
    // it straight to IconImage; guessing a theme sub-directory here only broke
    // apps whose layout didn't match the guess.
    return String(icon || "")
  }

  // Symbolic icons ship a fixed fill (often near-white) that the host is meant
  // to recolor to its foreground; detect them by the freedesktop "-symbolic"
  // name suffix so they can be tinted instead of rendered as-is.
  function iconIsSymbolic(icon) {
    var name = String(icon || "").split("?")[0]
    return name.slice(-9) === "-symbolic"
  }

  function trayTooltip(item) {
    return item.tooltipTitle || item.title || item.id || ""
  }

  function classifyItem(item) {
    var iid = String(item.id || "")
    if (hiddenIds.indexOf(iid) !== -1) return "hidden"
    if (pinnedIds.indexOf(iid) !== -1) return "pinned"
    return "drawer"
  }

  function ownedByOmarchy(item) {
    var layout = root.bar && root.bar.layoutConfig ? root.bar.layoutConfig : null
    return TrayModel.ownedByOmarchy(item, layout, extraWidgetIds)
  }

  function bucket(category) {
    var values = SystemTray.items.values
    var result = []
    for (var i = 0; i < values.length; i++) {
      var item = values[i]
      if (item.status === Status.Passive) continue
      if (ownedByOmarchy(item)) continue
      if (category === "all") {
        result.push(item)
        continue
      }
      if (classifyItem(item) === category) result.push(item)
    }
    return result
  }

  function persistTrayState(pinned, hidden, extras) {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    var id = root.moduleName || "vincentritter.tinytray"
    root.bar.shell.updateEntryInline(id, {
      id: id,
      pinned: pinned,
      hidden: hidden,
      extraWidgets: extras !== undefined ? extras : extraWidgetIds
    })
  }

  property var barWidgetQueue: []

  function setBarWidgetEnabled(id, enabled) {
    if (!id) return
    var next = barWidgetQueue.slice()
    next.push({ id: String(id), enabled: !!enabled })
    barWidgetQueue = next
    root.runBarWidgetQueue()
  }

  function runBarWidgetQueue() {
    if (barWidgetCtl.running) return
    if (!barWidgetQueue.length) return
    var next = barWidgetQueue.slice()
    var job = next.shift()
    barWidgetQueue = next
    barWidgetCtl.command = ["omarchy", "plugin", job.enabled ? "enable" : "disable", job.id]
    barWidgetCtl.running = true
  }

  function reconcileHostedBarWidgets() {
    var layout = root.bar && root.bar.layoutConfig
    var ids = extraWidgetIds
    for (var i = 0; i < ids.length; i++) {
      var id = String(ids[i] || "")
      if (!id || id === root.moduleName) continue
      if (TrayModel.layoutHasWidget(layout, id)) root.setBarWidgetEnabled(id, false)
    }
  }

  function toggleExtraWidget(iid) {
    var onBar = TrayModel.layoutHasWidget(root.bar && root.bar.layoutConfig, iid)
    var plan = TrayModel.extraWidgetTogglePlan(extraWidgetIds, iid, onBar)
    var extras = plan.extras
    var p = pinnedIds.slice(), h = hiddenIds.slice()
    if (!plan.adding) {
      var pi = p.indexOf(iid)
      if (pi !== -1) p.splice(pi, 1)
      var hi = h.indexOf(iid)
      if (hi !== -1) h.splice(hi, 1)
    }
    extraWidgetOverride = extras
    if (plan.adding) {
      persistTrayState(p, h, extras)
      if (plan.setBarEnabled === false) root.setBarWidgetEnabled(iid, false)
    } else {
      if (plan.setBarEnabled === true) root.setBarWidgetEnabled(iid, true)
      persistTrayState(p, h, extras)
    }
  }

  function applyCatalog(raw) {
    try {
      var parsed = JSON.parse(raw || "[]")
      root.widgetCatalog = Array.isArray(parsed) ? parsed : []
    } catch (e) {
      root.widgetCatalog = []
    }
  }

  function rescanCatalog() {
    catalogScan.running = false
    catalogScan.running = true
  }

  function togglePin(iid) {
    var p = pinnedIds.slice(), h = hiddenIds.slice()
    var idx = p.indexOf(iid)
    if (idx !== -1) p.splice(idx, 1)
    else {
      p.push(iid)
      var hi = h.indexOf(iid)
      if (hi !== -1) h.splice(hi, 1)
    }
    persistTrayState(p, h)
  }

  function toggleHide(iid) {
    var p = pinnedIds.slice(), h = hiddenIds.slice()
    var idx = h.indexOf(iid)
    if (idx !== -1) h.splice(idx, 1)
    else {
      h.push(iid)
      var pi = p.indexOf(iid)
      if (pi !== -1) p.splice(pi, 1)
    }
    persistTrayState(p, h)
  }

  visible: pinnedItems.length > 0 || hostedPinnedIds.length > 0 || drawerCount > 0 || hasDrawer
  clip: false
  implicitWidth: root.vertical ? root.barSize : trayContent.implicitWidth
  implicitHeight: root.vertical ? trayContent.implicitHeight : root.barSize

  Process {
    id: barWidgetCtl
    onExited: function(code) {
      if (code !== 0) console.warn("tinytray bar widget toggle failed", code, barWidgetCtl.command)
      Qt.callLater(root.runBarWidgetQueue)
    }
  }

  Process {
    id: catalogScan
    command: [
      "python3",
      root.catalogScript,
      root.omarchyPath + "/shell/plugins/panels",
      (Quickshell.env("HOME") || "") + "/.config/omarchy/plugins"
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyCatalog(text)
    }
    onExited: function(code) {
      if (code !== 0) console.warn("tinytray catalog scan failed", code, root.catalogScript)
    }
  }

  Component.onCompleted: {
    root.rescanCatalog()
    Qt.callLater(root.reconcileHostedBarWidgets)
  }
  function showSettings(open) {
    var next = open === true
    if (settingsOpen === next || pageFlip.running) return
    pendingSettingsOpen = next
    pageFlip.restart()
  }

  onManagePopupOpenChanged: {
    if (!managePopupOpen) {
      pageFlip.stop()
      cardRotation.angle = 0
      pendingSettingsOpen = false
      settingsOpen = false
      return
    }
    root.rescanCatalog()
    if (manageFlick) manageFlick.contentY = 0
  }

  SequentialAnimation {
    id: pageFlip
    NumberAnimation {
      target: cardRotation
      property: "angle"
      from: 0
      to: 90
      duration: 130
      easing.type: Easing.InQuad
    }
    ScriptAction {
      script: {
        root.settingsOpen = root.pendingSettingsOpen
        cardRotation.angle = -90
        if (manageFlick) manageFlick.contentY = 0
      }
    }
    NumberAnimation {
      target: cardRotation
      property: "angle"
      from: -90
      to: 0
      duration: 170
      easing.type: Easing.OutQuad
    }
  }

  Behavior on revealProgress {
    NumberAnimation { duration: root.animationDuration; easing.type: Easing.OutCubic }
  }

  Loader {
    id: trayContent
    anchors.fill: parent
    sourceComponent: root.vertical ? verticalTray : horizontalTray
  }

  Component {
    id: horizontalTray

    Item {
      id: horizontalTrayRoot

      readonly property int pinnedWidth: pinnedRow.implicitWidth
      readonly property int drawerBlockWidth: root.hasDrawer ? expandIcon.implicitWidth + root.drawerExtent : 0

      implicitWidth: pinnedWidth + drawerBlockWidth
      implicitHeight: root.barSize

      // Mask out the empty area the collapsed drawer reserves for its slide-in,
      // so hovering it doesn't trigger expand and clicks pass through.
      containmentMask: QtObject {
        function contains(point: point): bool {
          if (point.y < 0 || point.y > horizontalTrayRoot.height) return false
          // Drawer reveals leftward; chevron sits at the right end when collapsed
          // and slides left as it opens. The visible region starts at the chevron.
          var chevronX = root.drawerExtent - root.revealExtent
          if (point.x >= chevronX && point.x <= horizontalTrayRoot.drawerBlockWidth) return true
          // Pinned items, placed to the right of the drawer block.
          var pinnedStart = horizontalTrayRoot.drawerBlockWidth
          return point.x >= pinnedStart && point.x <= horizontalTrayRoot.implicitWidth
        }
      }

      Item {
        id: drawerArea
        x: 0
        width: horizontalTrayRoot.drawerBlockWidth
        height: root.barSize
        visible: root.hasDrawer

        HoverHandler {
          onHoveredChanged: root.expanded = hovered
        }

        BarIconButton {
          id: expandIcon
          bar: root.bar
          width: implicitWidth
          height: implicitHeight
          x: root.drawerExtent - root.revealExtent
          text: "\uf053"
          onPressed: function(button) {
            if (button === Qt.RightButton) root.managePopupOpen = !root.managePopupOpen
          }
        }

        Item {
          id: trayClip
          x: expandIcon.width
          anchors.verticalCenter: parent.verticalCenter
          width: root.drawerExtent
          height: root.barSize
          clip: true

          Row {
            id: trayIcons
            x: root.drawerExtent - root.revealExtent
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.trayItemGap
            layer.enabled: true

            Repeater {
              model: root.drawerItems
              TrayItem { acceptInput: root.drawerAcceptsInput }
            }

            Repeater {
              model: root.hostedDrawerIds
              HostedWidget { acceptInput: root.drawerAcceptsInput }
            }
          }
        }
      }

      Row {
        id: pinnedRow
        x: drawerArea.x + horizontalTrayRoot.drawerBlockWidth
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.trayItemGap
        leftPadding: (root.pinnedItems.length > 0 || root.hostedPinnedIds.length > 0) && root.hasDrawer ? root.trayJoinGap : 0
        Repeater {
          model: root.pinnedItems
          TrayItem {}
        }
        Repeater {
          model: root.hostedPinnedIds
          HostedWidget {}
        }
      }
    }
  }

  Component {
    id: verticalTray

    Item {
      id: verticalTrayRoot

      readonly property int pinnedHeight: pinnedCol.implicitHeight
      readonly property int drawerBlockHeight: root.hasDrawer ? expandIcon.implicitHeight + root.drawerExtent : 0

      implicitWidth: root.barSize
      implicitHeight: pinnedHeight + drawerBlockHeight

      containmentMask: QtObject {
        function contains(point: point): bool {
          if (point.x < 0 || point.x > verticalTrayRoot.width) return false
          var chevronY = root.drawerExtent - root.revealExtent
          if (point.y >= chevronY && point.y <= verticalTrayRoot.drawerBlockHeight) return true
          var pinnedStart = verticalTrayRoot.drawerBlockHeight
          return point.y >= pinnedStart && point.y <= verticalTrayRoot.implicitHeight
        }
      }

      Item {
        id: drawerArea
        y: 0
        width: root.barSize
        height: verticalTrayRoot.drawerBlockHeight
        visible: root.hasDrawer

        HoverHandler {
          onHoveredChanged: root.expanded = hovered
        }

        BarIconButton {
          id: expandIcon
          bar: root.bar
          width: implicitWidth
          height: implicitHeight
          y: root.drawerExtent - root.revealExtent
          text: "\uf053"
          textRotation: 90
          onPressed: function(button) {
            if (button === Qt.RightButton) root.managePopupOpen = !root.managePopupOpen
          }
        }

        Item {
          id: trayClip
          y: expandIcon.height
          anchors.horizontalCenter: parent.horizontalCenter
          width: root.barSize
          height: root.drawerExtent
          clip: true

          Column {
            id: trayIcons
            y: root.drawerExtent - root.revealExtent
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: root.trayItemGap
            layer.enabled: true

            Repeater {
              model: root.drawerItems
              TrayItem { acceptInput: root.drawerAcceptsInput }
            }

            Repeater {
              model: root.hostedDrawerIds
              HostedWidget { acceptInput: root.drawerAcceptsInput }
            }
          }
        }
      }

      Column {
        id: pinnedCol
        y: drawerArea.y + verticalTrayRoot.drawerBlockHeight
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: root.trayItemGap
        topPadding: (root.pinnedItems.length > 0 || root.hostedPinnedIds.length > 0) && root.hasDrawer ? root.trayJoinGap : 0
        Repeater {
          model: root.pinnedItems
          TrayItem {}
        }
        Repeater {
          model: root.hostedPinnedIds
          HostedWidget {}
        }
      }
    }
  }

  PopupCard {
    id: managePopup
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.managePopupOpen
    contentWidth: managePopup.fittedContentWidth(Style.space(320))
    contentHeight: managePopup.fittedContentHeight(
      manageHeader.implicitHeight + Style.space(8) + manageColumn.implicitHeight,
      Style.space(480)
    )

    Item {
      id: pageCard
      anchors.fill: parent
      transform: Rotation {
        id: cardRotation
        origin.x: pageCard.width / 2
        origin.y: pageCard.height / 2
        axis.x: 0
        axis.y: 1
        axis.z: 0
      }

    Item {
      id: managePage
      visible: !root.settingsOpen
      anchors.fill: parent

    Column {
      id: manageHeader
      width: parent.width
      spacing: Style.space(8)

      Item {
        width: parent.width
        implicitHeight: Math.max(manageTitle.implicitHeight, settingsButton.implicitHeight)

        Text {
          id: manageTitle
          anchors.left: parent.left
          anchors.right: settingsButton.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: "Tinytray"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }

        PanelActionButton {
          id: settingsButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰒓"
          tooltipText: "Tinytray settings"
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.showSettings(true)
        }
      }
    }

    Flickable {
      id: manageFlick
      anchors.top: manageHeader.bottom
      anchors.topMargin: Style.space(8)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      contentWidth: width
      contentHeight: manageColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      flickableDirection: Flickable.VerticalFlick

      Column {
        id: manageColumn
        width: manageFlick.width
        spacing: Style.space(8)

      Text {
        visible: root.widgetCatalogRows.length > 0
        text: "Bar widgets"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }

      Repeater {
        model: root.widgetCatalogRows
        delegate: Item {
          id: extraRow
          required property var modelData
          required property int index
          width: manageColumn.width
          implicitHeight: 28

          readonly property string itemId: String(modelData.id || "")
          readonly property bool inTray: extraRow.modelData.inTray === true
          readonly property bool onBar: extraRow.modelData.onBar === true

          Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: extraAddBtn.left
            anchors.rightMargin: Style.space(8)
            text: extraRow.modelData.title + (extraRow.onBar ? " (on the bar)" : "")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          Button {
            id: extraAddBtn
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            text: extraRow.inTray ? "Remove" : "Add"
            foreground: root.foreground
            horizontalPadding: 8
            verticalPadding: 3
            fontSize: Style.font.bodySmall
            onClicked: root.toggleExtraWidget(extraRow.itemId)
          }
        }
      }

      Text {
        visible: root.manageItems.length === 0 && root.widgetCatalogRows.length === 0
        text: "No tray items reporting."
        color: Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.italic: true
      }

      Text {
        visible: root.manageItems.length > 0
        text: "App icons"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }

      Repeater {
        model: root.manageItems
        delegate: Item {
          id: rowRoot
          required property var modelData
          required property int index
          width: manageColumn.width
          implicitHeight: 28

          readonly property string itemId: String(modelData.id || "")
          readonly property string displayName: {
            var t = String(modelData.title || "").trim()
            if (t) return t
            var tt = String(modelData.tooltipTitle || "").trim()
            if (tt) return tt
            var id = String(modelData.id || "")
            var slash = id.lastIndexOf("/")
            return slash !== -1 ? id.substring(slash + 1) : (id || "Unknown")
          }
          readonly property bool isPinned: root.pinnedIds.indexOf(itemId) !== -1
          readonly property bool isHidden: root.hiddenIds.indexOf(itemId) !== -1
          readonly property bool hasIcon: String(modelData.icon || "") !== ""

          TrayIcon {
            id: rowIcon
            visible: rowRoot.hasIcon
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            width: 16
            height: 16
            icon: rowRoot.modelData.icon
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: rowRoot.hasIcon ? Style.space(26) : 0
            anchors.right: rowHideBtn.left
            anchors.rightMargin: Style.space(8)
            text: rowRoot.displayName
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          Button {
            id: rowPinBtn
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            iconText: "\uf08d"
            text: rowRoot.isPinned ? "Unpin" : "Pin"
            foreground: root.foreground
            horizontalPadding: 8
            verticalPadding: 3
            iconSize: Style.font.bodySmall
            fontSize: Style.font.bodySmall
            onClicked: root.togglePin(rowRoot.itemId)
          }

          Button {
            id: rowHideBtn
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: rowPinBtn.left
            anchors.rightMargin: Style.space(6)
            iconText: "\uf06e"
            text: rowRoot.isHidden ? "Show" : "Hide"
            foreground: root.foreground
            horizontalPadding: 8
            verticalPadding: 3
            iconSize: Style.font.bodySmall
            fontSize: Style.font.bodySmall
            onClicked: root.toggleHide(rowRoot.itemId)
          }
        }
      }
      }
    }
    }

    Column {
      id: settingsPage
      visible: root.settingsOpen
      width: parent.width
      spacing: Style.space(12)

      Item {
        width: parent.width
        implicitHeight: Math.max(settingsBackButton.implicitHeight, settingsTitle.implicitHeight)

        PanelActionButton {
          id: settingsBackButton
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰁍"
          tooltipText: "Back"
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.showSettings(false)
        }

        Text {
          id: settingsTitle
          anchors.left: settingsBackButton.right
          anchors.leftMargin: Style.space(10)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: "Settings"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }
      }

      Text {
        width: parent.width
        text: "Tinytray is a hover drawer for Status Notifier apps and other bar widgets. Add takes a widget off this side of the bar into the tray. Remove puts it back. Widgets on the other side stay there."
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Text {
        width: parent.width
        text: "Pin keeps an app icon on the bar. Hide takes it off; it comes back from this menu."
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Text {
        id: credit
        width: parent.width
        text: "Built by Vincent Ritter"
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: Util.execArgv(["xdg-open", "https://vincentritter.com"])
        }
      }
    }
    }
  }

  QsMenuOpener {
    id: trayMenuOpener
    menu: root.activeTrayItem ? root.activeTrayItem.menu : null
  }

  PopupCard {
    id: trayMenuPopup
    anchorItem: root.activeTrayAnchor || root
    owner: root
    bar: root.bar
    open: root.trayMenuOpen
    // The card fades out over 140ms (visible stays true for that whole time --
    // see PopupCard's own visible: open || card.opacity > 0), so resetting on
    // "open" would swap a live submenu for the root menu mid-fade: a visible
    // flash, and a resize/reposition if the two have different geometry. Wait
    // for the fade to actually finish. Switching to a different tray item
    // still resets immediately, from openTrayMenu() itself.
    onVisibleChanged: if (!visible) root.resetTrayMenu()
    padding: Style.space(8)
    borderColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.45)
    contentWidth: trayMenuPopup.fittedContentWidth(Style.space(232))
    contentHeight: trayMenuPopup.fittedContentHeight(menuHeaderHeight + trayMenuColumn.implicitHeight, Style.space(420))

    // Column skips invisible children but keeps reporting their height, so
    // read the header's extent through its own visibility.
    readonly property int menuHeaderHeight: menuHeader.visible ? menuHeader.implicitHeight : 0

    Column {
      id: trayMenuLayout
      anchors.fill: parent
      spacing: 0

      // Header for a drilled-into submenu: names where we are and walks back
      // out. Pinned above the Flickable rather than scrolling with the rows,
      // so the way back stays reachable in a submenu taller than the card.
      // Only present below the root level, so the root menu is unchanged.
      Column {
        id: menuHeader
        visible: root.submenuDepth > 0
        width: trayMenuLayout.width
        spacing: 0

        Item {
          id: menuBackRow
          width: menuHeader.width
          implicitHeight: Style.space(30)

          Rectangle {
            anchors.fill: parent
            radius: Math.max(2, Style.cornerRadius)
            color: backMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.foreground) : "transparent"
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            width: Style.space(22)
            horizontalAlignment: Text.AlignHCenter
            text: "\u2039"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Style.space(28)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            text: root.currentTitle
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          MouseArea {
            id: backMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (root.menuLevelSettling) return
              // Reset before the model swap so the parent level shows from
              // the top (same ordering as the row delegate below).
              trayMenuFlick.contentY = 0
              root.leaveSubmenu()
            }
          }
        }

        Item {
          width: menuHeader.width
          implicitHeight: Style.space(11)

          Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(10)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            height: 1
            color: Color.popups.border
            opacity: 0.45
          }
        }
      }

      Flickable {
        id: trayMenuFlick
        width: trayMenuLayout.width
        height: trayMenuLayout.height - trayMenuPopup.menuHeaderHeight
        contentWidth: width
        contentHeight: trayMenuColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: trayMenuColumn
          width: trayMenuFlick.width
          spacing: 0

          Repeater {
            model: root.currentChildren

            delegate: Item {
              id: menuRow
              required property var modelData
              required property int index

              readonly property string rowText: String(modelData.text || "")
              readonly property string activeTitle: root.activeTrayItem ? String(root.activeTrayItem.title || root.activeTrayItem.id || "") : ""
              // Both only ever describe the root menu; inside a submenu the first
              // rows are real entries and must not be swallowed.
              readonly property bool atRoot: root.submenuDepth === 0
              readonly property bool rootTitleEntry: atRoot && index === 0 && modelData.hasChildren && rowText.toLowerCase() === activeTitle.toLowerCase()
              readonly property bool leadingSeparator: atRoot && modelData.isSeparator && index <= 1
              readonly property bool hiddenRow: rootTitleEntry || leadingSeparator

              visible: !hiddenRow
              width: trayMenuColumn.width
              implicitHeight: hiddenRow ? 0 : (modelData.isSeparator ? Style.space(11) : Style.space(30))
              opacity: modelData.enabled ? 1.0 : 0.45

              Rectangle {
                visible: menuRow.modelData.isSeparator
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                height: 1
                color: Color.popups.border
                opacity: 0.45
              }

              Rectangle {
                visible: !menuRow.modelData.isSeparator
                anchors.fill: parent
                radius: Math.max(2, Style.cornerRadius)
                color: rowMouse.containsMouse && menuRow.modelData.enabled ? Style.hoverFillFor(root.foreground, root.foreground) : "transparent"
              }

              Text {
                visible: !menuRow.modelData.isSeparator && menuRow.modelData.buttonType !== QsMenuButtonType.None
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                width: Style.space(22)
                horizontalAlignment: Text.AlignHCenter
                text: menuRow.modelData.checkState === Qt.Checked ? "\uf00c" : ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Image {
                id: menuIcon
                visible: !menuRow.modelData.isSeparator && String(menuRow.modelData.icon || "") !== ""
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Style.space(24)
                width: Style.space(16)
                height: Style.space(16)
                fillMode: Image.PreserveAspectFit
                // Decode at physical pixels: IconImage uses the logical size,
                // which leaves PNG icons upscaled and blurry on HiDPI displays.
                sourceSize.width: width * Screen.devicePixelRatio
                sourceSize.height: height * Screen.devicePixelRatio
                source: menuRow.modelData.icon
              }

              Text {
                visible: !menuRow.modelData.isSeparator
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: menuIcon.visible ? Style.space(46) : Style.space(28)
                anchors.right: submenuGlyph.left
                anchors.rightMargin: Style.space(8)
                text: menuRow.rowText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              Text {
                id: submenuGlyph
                visible: !menuRow.modelData.isSeparator && menuRow.modelData.hasChildren
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                text: "\u203a"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: !menuRow.modelData.isSeparator && menuRow.modelData.enabled
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                  if (root.menuLevelSettling) return
                  if (menuRow.modelData.hasChildren) {
                    // Reset scroll BEFORE swapping the model: the swap destroys
                    // this delegate synchronously and ids stop resolving after.
                    trayMenuFlick.contentY = 0
                    root.enterSubmenu(menuRow.modelData, menuRow.rowText)
                  } else {
                    menuRow.modelData.triggered()
                    root.close()
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  // Renders a tray icon, recoloring symbolic icons to the bar foreground so
  // they stay visible on any theme (a raw symbolic icon keeps its baked-in
  // fill and disappears against a matching background).
  component TrayIcon: Item {
    id: trayIconRoot
    required property var icon
    readonly property bool symbolic: root.iconIsSymbolic(icon)

    Image {
      id: trayIconImage
      anchors.fill: parent
      fillMode: Image.PreserveAspectFit
      // Decode at physical pixels: IconImage uses the logical size,
      // which leaves PNG icons upscaled and blurry on HiDPI displays.
      sourceSize.width: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
      sourceSize.height: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
      source: root.trayIconSource(trayIconRoot.icon)
      // Kept as a hidden layer so the effect can sample it as a texture.
      visible: !trayIconRoot.symbolic
      layer.enabled: trayIconRoot.symbolic
    }

    MultiEffect {
      anchors.fill: trayIconImage
      source: trayIconImage
      visible: trayIconRoot.symbolic
      colorization: 1.0
      colorizationColor: root.foreground
    }
  }

  // Hosts an Omarchy bar widget inside the tray drawer so it can sit next to
  // app tray icons (1Password) instead of taking a permanent slot on the bar.
  // 4.0.3 gives plugins PluginBarApi, which has no widget registry, so these
  // load first-party Panel.qml by path and take the plugin bar facade.
  component HostedWidget: Item {
    id: hostedRoot

    required property var modelData
    required property int index
    property bool acceptInput: true
    property int clickableSyncTries: 0

    readonly property string widgetId: String(modelData || "")
    readonly property var barInstance: root.bar
    readonly property string widgetUrl: TrayModel.hostedWidgetUrl(root.omarchyPath, widgetId, root.widgetCatalog)

    implicitWidth: extraLoader.item && extraLoader.item.visible !== false
      ? extraLoader.item.implicitWidth
      : (widgetUrl !== "" ? root.trayItemExtent : 0)
    implicitHeight: extraLoader.item && extraLoader.item.visible !== false
      ? extraLoader.item.implicitHeight
      : (widgetUrl !== "" ? root.trayItemExtent : 0)
    width: implicitWidth
    height: implicitHeight

    Loader {
      id: extraLoader
      active: hostedRoot.widgetUrl !== ""
      source: hostedRoot.widgetUrl
      onLoaded: hostedRoot.injectProps()
      onStatusChanged: if (status === Loader.Error)
        console.warn("tinytray failed to load", hostedRoot.widgetId, hostedRoot.widgetUrl)
    }

    function injectProps() {
      var item = extraLoader.item
      if (!item) return
      if ("bar" in item) item.bar = hostedRoot.barInstance
      if ("moduleName" in item) item.moduleName = hostedRoot.widgetId
      if ("settings" in item) item.settings = ({})
      hostedRoot.syncClickable()
    }

    function syncClickable() {
      var n = TrayModel.setDescendantClickable(extraLoader.item, hostedRoot.acceptInput)
      if (n > 0) {
        hostedRoot.clickableSyncTries = 0
        return
      }
      if (!extraLoader.item || hostedRoot.clickableSyncTries >= 8) {
        hostedRoot.clickableSyncTries = 0
        return
      }
      hostedRoot.clickableSyncTries += 1
      Qt.callLater(hostedRoot.syncClickable)
    }

    onBarInstanceChanged: injectProps()
    onAcceptInputChanged: syncClickable()
  }

  // Hidden hosted widgets stay loaded so their panels can still open from IPC.
  Item {
    width: 0
    height: 0
    visible: false
    Repeater {
      model: root.hostedHiddenIds
      HostedWidget { acceptInput: false }
    }
  }

  component TrayItem: Item {
    id: trayItemRoot

    required property var modelData
    property bool acceptInput: true

    visible: modelData.status !== Status.Passive
    implicitWidth: visible ? root.trayItemExtent : 0
    implicitHeight: visible ? root.trayItemExtent : 0

    function displayMenu(mouse) {
      root.openTrayMenu(trayItemRoot.modelData, trayItemRoot, mouse)
    }

    TrayIcon {
      anchors.centerIn: parent
      width: Style.space(12)
      height: Style.space(12)
      icon: trayItemRoot.modelData.icon
    }

    MouseArea {
      id: mouseArea
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      enabled: trayItemRoot.acceptInput
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: if (root.bar) root.bar.showTooltip(trayItemRoot, root.trayTooltip(modelData))
      onExited: if (root.bar) root.bar.hideTooltip(trayItemRoot)
      onPressed: function(mouse) {
        if (mouse.button === Qt.RightButton) {
          trayItemRoot.displayMenu(mouse)
          mouse.accepted = true
        }
      }
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) {
          mouse.accepted = true
        } else if (mouse.button === Qt.MiddleButton) {
          trayItemRoot.modelData.secondaryActivate()
        } else if (trayItemRoot.modelData.onlyMenu) {
          trayItemRoot.displayMenu(mouse)
        } else {
          trayItemRoot.modelData.activate()
        }
      }
      onWheel: function(wheel) {
        trayItemRoot.modelData.scroll(wheel.angleDelta.y, false)
      }
    }

    readonly property bool tooltipHovered: visible && opacity > 0 && mouseArea.containsMouse
  }
}
