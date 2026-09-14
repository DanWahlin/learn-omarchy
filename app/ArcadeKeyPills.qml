pragma ComponentBehavior: Bound

import QtQuick

Row {
  id: root
  required property var arcade
  property var keys: []
  property bool revealed: false
  spacing: 6

  Repeater {
    model: root.keys
    Rectangle {
      id: pill
      required property string modelData
      readonly property bool held: root.arcade.pressedKeys.indexOf(modelData) !== -1
      width: Math.max(42, keyText.implicitWidth + 20)
      height: keyText.implicitHeight + 14
      radius: 6
      color: held ? root.arcade.modeAccent : root.arcade.raisedColor
      border.color: held || root.revealed ? root.arcade.modeInk : root.arcade.lineColor
      border.width: held ? 2 : 1
      Accessible.role: Accessible.StaticText
      Accessible.name: modelData + (held ? " held" : root.revealed ? " required" : " not held")
      Text {
        id: keyText
        anchors.centerIn: parent
        text: pill.modelData === "RETURN" ? "ENTER" : pill.modelData
        color: pill.held ? root.arcade.modeButtonInk : root.arcade.foregroundColor
        font.family: "monospace"
        font.pixelSize: 12 * root.arcade.fontScale
        font.weight: pill.held ? Font.Bold : Font.Normal
      }
    }
  }
}
