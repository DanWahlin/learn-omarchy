function intersects(a, b, gap) {
  return b && a.x < b.x + b.width + gap && a.x + a.width + gap > b.x &&
    a.y < b.y + b.height + gap && a.y + a.height + gap > b.y
}

function panelWidth(viewportWidth, viewportHeight, preferred, target) {
  var width = Math.min(preferred, Math.max(1, viewportWidth - 48))
  if (!target || target.y + target.height < viewportHeight * 0.65) return width
  var left = (viewportWidth - width) / 2
  if (left + width <= target.x - 24 || left >= target.x + target.width + 24) return width
  var space = Math.max(target.x - 48, viewportWidth - target.x - target.width - 48)
  return space >= 340 ? Math.min(width, space) : width
}

function position(viewportWidth, viewportHeight, width, height, target) {
  var bottom = Math.max(24, viewportHeight - height - 30)
  var centered = { x: (viewportWidth - width) / 2, y: bottom }
  if (!target) return centered
  var candidates = [
    centered,
    { x: 24, y: bottom },
    { x: viewportWidth - width - 24, y: bottom },
    { x: centered.x, y: target.y - height - 24 },
    { x: centered.x, y: target.y + target.height + 24 }
  ]
  for (var i = 0; i < candidates.length; i++) {
    var candidate = candidates[i]
    if (candidate.x < 12 || candidate.y < 40 || candidate.x + width > viewportWidth - 12 ||
        candidate.y + height > viewportHeight - 12) continue
    if (!intersects({ x: candidate.x, y: candidate.y, width: width, height: height }, target, 16))
      return candidate
  }
  return centered
}

function besideBar(viewportWidth, viewportHeight, width, height, target) {
  var distances = [target.y, viewportHeight - target.y - target.height,
    target.x, viewportWidth - target.x - target.width]
  var knownEdge = ["top", "bottom", "left", "right"].indexOf(target.edge)
  var edge = knownEdge >= 0 ? knownEdge : target.height > target.width
    ? (distances[2] <= distances[3] ? 2 : 3)
    : (distances[0] <= distances[1] ? 0 : 1)
  var gap = 64
  var x = target.x + target.width / 2 - width / 2
  var y = target.y + target.height / 2 - height / 2
  if (edge === 0) y = target.y + target.height + gap
  else if (edge === 1) y = target.y - height - gap
  else if (edge === 2) x = target.x + target.width + gap
  else x = target.x - width - gap
  return {
    x: Math.max(18, Math.min(viewportWidth - width - 18, x)),
    y: Math.max(50, Math.min(viewportHeight - height - 28, y)),
    edge: ["top", "bottom", "left", "right"][edge]
  }
}
