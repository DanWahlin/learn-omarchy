pragma ComponentBehavior: Bound

import QtQuick

Canvas {
  id: root
  required property color accent
  property bool marquee: false
  Accessible.ignored: true
  onAccentChanged: requestPaint()
  onMarqueeChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()
  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    function outline(inset, cut, color, thickness) {
      ctx.beginPath()
      ctx.moveTo(inset + cut, inset)
      ctx.lineTo(width - inset - cut, inset)
      ctx.lineTo(width - inset, inset + cut)
      ctx.lineTo(width - inset, height - inset - cut)
      ctx.lineTo(width - inset - cut, height - inset)
      ctx.lineTo(inset + cut, height - inset)
      ctx.lineTo(inset, height - inset - cut)
      ctx.lineTo(inset, inset + cut)
      ctx.closePath()
      ctx.strokeStyle = color
      ctx.lineWidth = thickness
      ctx.stroke()
    }
    ctx.globalAlpha = 0.1
    outline(7, 14, root.accent, 14)
    ctx.globalAlpha = 0.8
    outline(7, 14, root.accent, 2)
    ctx.globalAlpha = 0.3
    outline(13, 12, root.accent, 1)
    ctx.globalAlpha = 1
    for (var side = 0; side < 2; side++) {
      var x = side ? width - 10 : 6
      ctx.fillStyle = root.accent
      ctx.fillRect(x, 35, 4, Math.min(48, height * 0.15))
      ctx.fillRect(x, height - 55, 4, 20)
    }
    if (root.marquee) {
      for (var i = 0; i < 9; i++) {
        ctx.globalAlpha = 0.25 + (i % 3) * 0.25
        ctx.fillRect(width / 2 - 62 + i * 15, height - 10, 10, 4)
      }
    }
  }
}
