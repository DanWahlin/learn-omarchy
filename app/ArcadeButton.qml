pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

Button {
  id: root
  required property var arcade
  property bool primary: false
  property bool navigationSelected: false
  property bool square: false
  property string accessibleName: text
  property color highlightColor: arcade.modeAccent
  readonly property color highlightInk: arcade.inkForColor(highlightColor)

  implicitWidth: square ? implicitHeight : Math.max(92, label.implicitWidth + 30)
  implicitHeight: Math.max(42, label.implicitHeight + 22)
  padding: square ? 8 : 12
  hoverEnabled: true
  focusPolicy: Qt.StrongFocus
  Keys.forwardTo: [arcade]
  onActiveFocusChanged: if (activeFocus) arcade.focusNavigationControl(root)
  Accessible.name: accessibleName
  Accessible.role: Accessible.Button

  contentItem: Text {
    id: label
    text: root.text
    color: root.primary ? root.arcade.textOnColor(root.highlightColor) : root.arcade.foregroundColor
    font.pixelSize: (root.square ? 19 : 13) * root.arcade.fontScale
    font.weight: Font.Bold
    font.family: "monospace"
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    wrapMode: Text.WordWrap
  }
  background: Rectangle {
    radius: 2
    color: root.primary ? (root.down ? Qt.darker(root.highlightColor, 1.12)
      : root.hovered ? Qt.lighter(root.highlightColor, 1.06) : root.highlightColor)
      : root.down || root.hovered ? root.arcade.raisedColor : root.arcade.surfaceColor
    border.color: root.activeFocus || root.navigationSelected
      ? root.highlightInk : root.primary ? root.highlightColor : root.arcade.lineColor
    border.width: 2
    opacity: root.enabled ? 1 : 0.45
    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: 3
      height: root.down ? 1 : 4
      color: root.primary ? root.arcade.surfaceColor : root.highlightInk
      opacity: root.primary ? 0.35 : 0.25
    }
    Rectangle {
      objectName: "arcadeFocusRing"
      anchors.fill: parent
      anchors.margins: -4
      radius: 2
      color: "transparent"
      border.color: root.highlightInk
      visible: root.activeFocus || root.navigationSelected
    }
  }
}
