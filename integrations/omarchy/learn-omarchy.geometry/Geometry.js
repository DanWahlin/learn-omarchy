function finite(value) {
  return typeof value === "number" && isFinite(value)
}

function requireCapability(condition, message) {
  if (!condition) throw new Error(message)
}

function windowOrigin(bar, window) {
  var screen = window && window.screen
  requireCapability(screen && typeof screen.name === "string" && screen.name.length > 0
    && finite(screen.width) && screen.width > 0 && finite(screen.height) && screen.height > 0,
    "bar window has no logical screen geometry")
  requireCapability(finite(window.width) && window.width > 0 && finite(window.height) && window.height > 0,
    "bar window has no usable size")
  var vertical = bar.position === "left" || bar.position === "right"
  var anchors = window.anchors
  var margins = window.margins
  requireCapability(anchors && margins
    && anchors.top === (bar.position === "top" || vertical)
    && anchors.bottom === (bar.position === "bottom" || vertical)
    && anchors.left === (bar.position === "left" || !vertical)
    && anchors.right === (bar.position === "right" || !vertical),
    "unsupported bar anchors")
  requireCapability(vertical ? window.height === screen.height && window.width < screen.width
    : window.width === screen.width && window.height < screen.height, "unsupported bar window shape")
  var edges = ["top", "bottom", "left", "right"]
  for (var i = 0; i < edges.length; i++) {
    var edge = edges[i]
    var expected = bar.barHidden && edge === bar.position ? -(vertical ? window.width : window.height) : 0
    requireCapability(margins[edge] === expected, "unsupported bar margins")
  }
  // mapToItem(null, ...) is WINDOW-local, not monitor-local.
  return {
    x: bar.position === "right" ? screen.width - window.width - margins.right : margins.left,
    y: bar.position === "bottom" ? screen.height - window.height - margins.bottom : margins.top
  }
}

function bounds(item, origin) {
  requireCapability(item && typeof item.mapToItem === "function"
    && finite(item.width) && finite(item.height), "widget geometry API unavailable")
  var topLeft = item.mapToItem(null, 0, 0)
  var topRight = item.mapToItem(null, item.width, 0)
  var bottomLeft = item.mapToItem(null, 0, item.height)
  var bottomRight = item.mapToItem(null, item.width, item.height)
  requireCapability(finite(topLeft.x) && finite(topLeft.y)
    && finite(bottomRight.x) && finite(bottomRight.y)
    && Math.abs(topRight.y - topLeft.y) < 0.01 && Math.abs(bottomLeft.x - topLeft.x) < 0.01
    && Math.abs(bottomRight.x - topRight.x) < 0.01 && Math.abs(bottomRight.y - bottomLeft.y) < 0.01
    && bottomRight.x >= topLeft.x && bottomRight.y >= topLeft.y, "unsupported widget transform")
  return { x: origin.x + topLeft.x, y: origin.y + topLeft.y,
    width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y }
}

function itemVisible(item) {
  for (var current = item; current; current = current.parent) {
    if (current.visible === false || current.opacity === 0) return false
  }
  return item.visible === true
}

function record(item, id, origin, visible, activeItem) {
  var result = bounds(item, origin)
  result.id = id
  result.itemVisible = itemVisible(activeItem)
  result.visible = visible && itemVisible(item) && result.itemVisible && result.width > 0 && result.height > 0
  return result
}

function workspaceCells(widget) {
  // Stock workspace buttons expose their actual Repeater modelData. The grid
  // and delegates are public children; never infer cells from index or spacing.
  if (typeof widget.workspaceIds !== "function" || typeof widget.workspaceById !== "function") return []
  var found = []
  var pending = [widget]
  var visited = 0
  while (pending.length && visited++ < 512) {
    var item = pending.shift()
    if (item !== widget && Number.isInteger(item.modelData) && item.modelData > 0
      && item.workspace !== undefined && typeof item.pressed === "function"
      && typeof item.mapToItem === "function") {
      found.push({ item: item, id: item.modelData })
    } else {
      var children = item.children || []
      for (var i = 0; i < children.length; i++) pending.push(children[i])
    }
  }
  if (pending.length) return []
  var ids = {}
  for (var j = 0; j < found.length; j++) {
    if (ids[found[j].id]) return []
    ids[found[j].id] = true
  }
  return found
}

function popupCards(widget, bar, screen, namespaceForWindow) {
  if (widget.opened !== true || typeof namespaceForWindow !== "function") return []
  var pending = [widget]
  var visited = []
  var cards = []
  while (pending.length && visited.length < 512) {
    var object = pending.shift()
    if (!object || visited.indexOf(object) !== -1) continue
    visited.push(object)
    if (object.cardOrigin !== undefined) {
      // The stock KeyboardPanel is fullscreen; its painted BorderSurface binds
      // directly to these public properties. Its window bounds are NOT its card.
      var anchors = object.anchors
      var margins = object.margins
      var origin = object.cardOrigin
      if (object.bar === bar && object.open === true && object.visible === true
        && object.screen && object.screen.name === screen.name
        && object.screen.width === screen.width && object.screen.height === screen.height
        && object.width === screen.width && object.height === screen.height
        && anchors && anchors.top === true && anchors.bottom === true && anchors.left === true && anchors.right === true
        && margins && margins.top === 0 && margins.bottom === 0 && margins.left === 0 && margins.right === 0
        && origin && finite(origin.x) && finite(origin.y)
        && finite(object.contentWidth) && object.contentWidth > 0 && finite(object.contentHeight) && object.contentHeight > 0
        && origin.x >= 0 && origin.y >= 0
        && origin.x + object.contentWidth <= screen.width && origin.y + object.contentHeight <= screen.height
        && namespaceForWindow(object) === "omarchy-keyboard-panel") {
        cards.push({ id: "panel:omarchy-keyboard-panel", x: origin.x, y: origin.y,
          width: object.contentWidth, height: object.contentHeight, visible: true, itemVisible: true })
      }
      continue
    }
    if (object.item) pending.push(object.item)
    var data = object.data || []
    for (var i = 0; i < data.length; i++) pending.push(data[i])
  }
  return pending.length ? [] : cards
}

function snapshot(bar, namespaceForWindow, activeBarId) {
  // The host can construct the stock bar before manifest discovery finishes.
  // Its active ID remains authoritative even when bar.manifest is still null.
  var barId = activeBarId === undefined ? bar && bar.manifest && bar.manifest.id : activeBarId
  requireCapability(bar && barId === "omarchy.bar" && (!bar.manifest || bar.manifest.id === "omarchy.bar"),
    "only the stock Omarchy bar is supported")
  requireCapability(["top", "bottom", "left", "right"].indexOf(bar.position) !== -1
    && typeof bar.barHidden === "boolean" && bar.moduleSlots
    && typeof bar.moduleSlots.length === "number" && typeof bar.slotWindow === "function",
    "public bar geometry API unavailable")
  var result = { version: 1, screens: [] }
  for (var i = 0; i < bar.moduleSlots.length; i++) {
    var slot = bar.moduleSlots[i]
    if (!slot || !slot.activeItem) continue
    requireCapability(typeof slot.moduleName === "string" && slot.moduleName.length > 0, "widget has no module identity")
    var window = bar.slotWindow(slot)
    var origin = windowOrigin(bar, window)
    var screen = null
    for (var s = 0; s < result.screens.length; s++) {
      if (result.screens[s].name === window.screen.name) screen = result.screens[s]
    }
    if (!screen) {
      screen = { name: window.screen.name, width: window.screen.width, height: window.screen.height, widgets: [] }
      result.screens.push(screen)
    }
    requireCapability(screen.width === window.screen.width && screen.height === window.screen.height,
      "inconsistent screen dimensions")
    var visible = !bar.barHidden && window.visible === true
    screen.widgets.push(record(slot, slot.moduleName, origin, visible, slot.activeItem))
    if (slot.moduleName === "omarchy.workspaces") {
      var cells = workspaceCells(slot.activeItem)
      for (var c = 0; c < cells.length; c++) {
        var cell = record(cells[c].item, slot.moduleName, origin, visible && itemVisible(slot), cells[c].item)
        cell.workspaceId = cells[c].id
        screen.widgets.push(cell)
      }
    }
    // Optional popup capabilities must never invalidate working bar geometry.
    try {
      var cards = popupCards(slot.activeItem, bar, screen, namespaceForWindow)
      for (var p = 0; p < cards.length; p++) screen.widgets.push(cards[p])
    } catch (error) {
      console.warn("learnGeometry: popup measurement unavailable:", error)
    }
  }
  requireCapability(result.screens.length > 0, "no live bar slots")
  return result
}
