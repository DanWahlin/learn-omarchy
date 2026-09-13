pragma ComponentBehavior: Bound

import QtQuick

Canvas {
  id: root
  required property var arcade
  property bool perspective: true
  property real travel: 0
  readonly property bool moving: perspective && visible && arcade.running
    && arcade.active && !arcade.reducedMotion
  Accessible.ignored: true
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()
  onTravelChanged: requestPaint()
  onPerspectiveChanged: requestPaint()
  Connections {
    target: root.arcade
    function onModeAccentChanged() { root.requestPaint() }
    function onSurfaceColorChanged() { root.requestPaint() }
  }
  Timer {
    interval: 80
    running: root.moving
    repeat: true
    onTriggered: root.travel = (root.travel + 0.025) % 1
  }
  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    ctx.fillStyle = root.arcade.surfaceColor
    ctx.fillRect(0, 0, width, height)
    var horizon = height * 0.42
    ctx.fillStyle = root.arcade.modeAccent
    for (var i = 0; i < 36; i++) {
      var x = ((i * 73 + 19) % 997) / 997 * width
      var y = ((i * 137 + 31) % 641) / 641 * (root.perspective ? horizon : height)
      var size = i % 4 === 0 ? 3 : 2
      ctx.globalAlpha = 0.15 + (i % 3) * 0.1
      ctx.fillRect(Math.round(x), Math.round(y), size, size)
    }
    ctx.strokeStyle = root.arcade.modeAccent
    ctx.lineWidth = 1
    if (root.perspective) {
      ctx.globalAlpha = 0.23
      for (var ray = -7; ray <= 7; ray++) {
        ctx.beginPath()
        ctx.moveTo(width / 2 + ray * 13, horizon)
        ctx.lineTo(width / 2 + ray * width / 7, height)
        ctx.stroke()
      }
      for (var line = 0; line < 10; line++) {
        var distance = (line + root.travel) / 10
        var lineY = horizon + distance * distance * (height - horizon)
        ctx.globalAlpha = 0.08 + distance * 0.23
        ctx.fillRect(0, Math.round(lineY), width, 1)
      }
      ctx.globalAlpha = 0.5
      ctx.fillRect(0, Math.round(horizon), width, 2)
    }
    // Raster texture stays behind the opaque reading card, never over its text.
    ctx.globalAlpha = 0.035
    for (var scan = 0; scan < height; scan += 5) ctx.fillRect(0, scan, width, 1)
  }
}
