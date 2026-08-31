const test = require("node:test")
const assert = require("node:assert/strict")
const TrayModel = require("./TrayModel.js")

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
