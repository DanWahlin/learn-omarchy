pragma ComponentBehavior: Bound

import QtQuick

Item {
  id: root
  property string text: ""
  property color color: "white"
  property font font: Qt.font({ pixelSize: 28 })
  property int horizontalAlignment: Text.AlignLeft
  readonly property real cell: Math.max(1, font.pixelSize / 7)
  readonly property int columns: Math.max(1, Math.floor((width + cell) / (6 * cell) + 0.001))
  readonly property var lines: {
    var result = []
    var line = ""
    var words = text.toUpperCase().split(" ")
    for (var word of words) {
      if (line && line.length + word.length + 1 > columns) {
        result.push(line)
        line = ""
      }
      line += (line ? " " : "") + word
    }
    if (line) result.push(line)
    return result
  }
  implicitWidth: Math.max(0, text.length * 6 - 1) * cell
  implicitHeight: Math.max(1, lines.length) * 10 * cell - 3 * cell
  Accessible.role: Accessible.StaticText
  Accessible.name: text

  // Original five-column display glyphs; body text stays in the user's UI font.
  readonly property var glyphs: ({
    A: "01110/10001/10001/11111/10001/10001/10001",
    B: "11110/10001/10001/11110/10001/10001/11110",
    C: "01111/10000/10000/10000/10000/10000/01111",
    D: "11110/10001/10001/10001/10001/10001/11110",
    E: "11111/10000/10000/11110/10000/10000/11111",
    F: "11111/10000/10000/11110/10000/10000/10000",
    G: "01111/10000/10000/10111/10001/10001/01111",
    H: "10001/10001/10001/11111/10001/10001/10001",
    I: "11111/00100/00100/00100/00100/00100/11111",
    J: "00111/00010/00010/00010/10010/10010/01100",
    K: "10001/10010/10100/11000/10100/10010/10001",
    L: "10000/10000/10000/10000/10000/10000/11111",
    M: "10001/11011/10101/10101/10001/10001/10001",
    N: "10001/11001/10101/10011/10001/10001/10001",
    O: "01110/10001/10001/10001/10001/10001/01110",
    P: "11110/10001/10001/11110/10000/10000/10000",
    Q: "01110/10001/10001/10001/10101/10010/01101",
    R: "11110/10001/10001/11110/10100/10010/10001",
    S: "01111/10000/10000/01110/00001/00001/11110",
    T: "11111/00100/00100/00100/00100/00100/00100",
    U: "10001/10001/10001/10001/10001/10001/01110",
    V: "10001/10001/10001/10001/10001/01010/00100",
    W: "10001/10001/10001/10101/10101/10101/01010",
    X: "10001/10001/01010/00100/01010/10001/10001",
    Y: "10001/10001/01010/00100/00100/00100/00100",
    Z: "11111/00001/00010/00100/01000/10000/11111",
    "0": "01110/10001/10011/10101/11001/10001/01110",
    "1": "00100/01100/00100/00100/00100/00100/01110",
    "2": "01110/10001/00001/00010/00100/01000/11111",
    "3": "11110/00001/00001/01110/00001/00001/11110",
    "4": "00010/00110/01010/10010/11111/00010/00010",
    "5": "11111/10000/10000/11110/00001/00001/11110",
    "6": "01110/10000/10000/11110/10001/10001/01110",
    "7": "11111/00001/00010/00100/01000/01000/01000",
    "8": "01110/10001/10001/01110/10001/10001/01110",
    "9": "01110/10001/10001/01111/00001/00001/01110",
    "+": "00000/00100/00100/11111/00100/00100/00000",
    "-": "00000/00000/00000/11111/00000/00000/00000",
    ":": "00000/00100/00100/00000/00100/00100/00000",
    "'": "00100/00100/00000/00000/00000/00000/00000",
    "/": "00001/00010/00010/00100/01000/01000/10000",
    "!": "00100/00100/00100/00100/00100/00000/00100",
    ".": "00000/00000/00000/00000/00000/00100/00100"
  })

  onLinesChanged: lettering.requestPaint()
  onColorChanged: lettering.requestPaint()
  onFontChanged: lettering.requestPaint()
  onHorizontalAlignmentChanged: lettering.requestPaint()
  Canvas {
    id: lettering
    anchors.fill: parent
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      ctx.fillStyle = root.color
      root.lines.forEach(function(line, row) {
        var lineWidth = (line.length * 6 - 1) * root.cell
        var left = root.horizontalAlignment === Text.AlignHCenter ? (width - lineWidth) / 2
          : root.horizontalAlignment === Text.AlignRight ? width - lineWidth : 0
        for (var i = 0; i < line.length; i++) {
          var glyph = root.glyphs[line[i]]
          if (!glyph) continue
          glyph.split("/").forEach(function(bits, y) {
            for (var x = 0; x < 5; x++) {
              if (bits[x] === "1") ctx.fillRect(
                Math.round(left + (i * 6 + x) * root.cell),
                Math.round((row * 10 + y) * root.cell),
                Math.ceil(root.cell), Math.ceil(root.cell))
            }
          })
        }
      })
    }
  }
}
