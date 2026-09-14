pragma ComponentBehavior: Bound

import QtQuick

Rectangle {
  id: root
  required property var arcade
  required property string mode
  objectName: "arcadeModePreview-" + mode
  readonly property color modeColor: arcade.colorForMode(mode)
  readonly property color modeInk: arcade.inkForColor(modeColor)
  implicitHeight: 76
  radius: 2
  color: Qt.tint(arcade.surfaceColor, Qt.rgba(modeColor.r, modeColor.g, modeColor.b, 0.11))
  border.color: Qt.tint(arcade.surfaceColor, Qt.rgba(modeColor.r, modeColor.g, modeColor.b, 0.3))
  Accessible.ignored: true

  component MiniRacer: Item {
    required property color racerColor
    property bool ghost: false
    width: 46
    height: 24

    Rectangle {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: 18
      height: 5
      radius: 3
      color: racerColor
      opacity: ghost ? 0.16 : 0.55
    }
    Rectangle {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: 31
      height: 16
      radius: 5
      color: racerColor
      opacity: ghost ? 0.55 : 1
      border.color: ghost ? root.arcade.lineColor : root.arcade.foregroundColor
      border.width: 1
    }
    Rectangle {
      anchors.right: parent.right
      anchors.rightMargin: 5
      anchors.verticalCenter: parent.verticalCenter
      width: 10
      height: 9
      radius: 5
      color: root.arcade.surfaceColor
      opacity: ghost ? 0.45 : 0.85
    }
    Rectangle {
      anchors.right: parent.right
      anchors.rightMargin: -3
      anchors.verticalCenter: parent.verticalCenter
      width: 10
      height: 10
      radius: 2
      rotation: 45
      color: racerColor
      opacity: ghost ? 0.55 : 1
    }
  }

  Item {
    anchors.fill: parent
    anchors.margins: 8
    visible: root.mode === "sprint"
    Rectangle {
      anchors.fill: parent
      radius: 7
      color: Qt.tint(root.arcade.surfaceColor,
        Qt.rgba(root.modeColor.r, root.modeColor.g, root.modeColor.b, 0.1))
      border.color: root.modeColor
      opacity: 0.8
    }
    Text {
      anchors.left: parent.left
      anchors.leftMargin: 10
      anchors.top: parent.top
      anchors.topMargin: 7
      text: "TIME TRIAL"
      color: root.modeInk
      font.pixelSize: 9 * root.arcade.fontScale
      font.weight: Font.Bold
      font.letterSpacing: 0.8
    }
    Rectangle {
      anchors.right: parent.right
      anchors.rightMargin: 9
      anchors.top: parent.top
      anchors.topMargin: 6
      width: timerText.implicitWidth + 12
      height: timerText.implicitHeight + 4
      radius: 4
      color: root.arcade.raisedColor
      border.color: root.modeColor
      Text {
        id: timerText
        anchors.centerIn: parent
        text: "1:00"
        color: root.modeInk
        font.family: "monospace"
        font.pixelSize: 10 * root.arcade.fontScale
        font.weight: Font.Bold
      }
    }
    Item {
      anchors.left: parent.left
      anchors.right: finishLine.left
      anchors.leftMargin: 10
      anchors.rightMargin: 5
      anchors.top: parent.top
      anchors.topMargin: 29
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 7
      Repeater {
        model: 2
        Rectangle {
          required property int index
          x: 0
          y: index * parent.height * 0.56 + 9
          width: parent.width
          height: 2
          radius: 1
          color: root.arcade.lineColor
        }
      }
      Repeater {
        model: 5
        Rectangle {
          required property int index
          x: 18 + index * Math.max(26, (parent.width - 50) / 5)
          y: 1 + index % 2 * 24
          width: 23
          height: 2
          radius: 1
          color: root.modeColor
          opacity: 0.22
        }
      }
      MiniRacer {
        objectName: "sprintPreviewPlayer"
        x: parent.width * 0.57
        y: 0
        racerColor: root.modeColor
      }
      MiniRacer {
        objectName: "sprintPreviewGhost"
        x: parent.width * 0.31
        y: parent.height * 0.55
        racerColor: root.modeInk
        ghost: true
      }
    }
    Item {
      id: finishLine
      objectName: "sprintPreviewFinish"
      anchors.right: parent.right
      anchors.rightMargin: 9
      anchors.top: parent.top
      anchors.topMargin: 31
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 8
      width: 14
      Repeater {
        model: 8
        Rectangle {
          required property int index
          x: (index % 2) * 7
          y: Math.floor(index / 2) * parent.height / 4
          width: 7
          height: parent.height / 4
          color: index % 3 === 0 ? root.modeInk : root.arcade.surfaceColor
          opacity: 0.85
        }
      }
    }
  }
  Item {
    anchors.fill: parent
    anchors.margins: 10
    visible: root.mode === "rescue"
    Image {
      objectName: "rescuePreviewShip"
      anchors.left: parent.left
      anchors.leftMargin: Math.max(8, parent.width * 0.08)
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(88 * root.arcade.textScale, parent.width * 0.42)
      height: parent.height * 0.82
      source: root.arcade.arcadeAssetUrl("rescue-ship.png")
      fillMode: Image.PreserveAspectFit
      smooth: true
      mipmap: true
    }
    Image {
      objectName: "rescuePreviewPlanet"
      anchors.right: parent.right
      anchors.rightMargin: Math.max(6, parent.width * 0.06)
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(78 * root.arcade.textScale, parent.width * 0.36)
      height: parent.height * 0.9
      source: root.arcade.arcadeAssetUrl("rescue-planet.png")
      fillMode: Image.PreserveAspectFit
      smooth: true
      mipmap: true
    }
  }
  Item {
    anchors.fill: parent
    anchors.margins: 8
    visible: root.mode === "keyfall"
    Rectangle {
      anchors.fill: parent
      radius: 7
      color: Qt.tint(root.arcade.surfaceColor,
        Qt.rgba(root.modeColor.r, root.modeColor.g, root.modeColor.b, 0.1))
      border.color: root.modeColor
      opacity: 0.8
    }
    Repeater {
      model: 5
      Rectangle {
        required property int index
        x: parent.width * (index + 1) / 6
        y: 5
        width: 1
        height: parent.height - 20
        color: root.modeColor
        opacity: index === 2 ? 0.26 : 0.11
      }
    }
    Rectangle {
      x: 15
      y: 15
      width: 34
      height: 20
      radius: 4
      color: root.arcade.raisedColor
      border.color: root.modeColor
      opacity: 0.55
      Text {
        anchors.centerIn: parent
        text: "H"
        color: root.modeInk
        font.pixelSize: 8 * root.arcade.fontScale
        font.weight: Font.Bold
      }
    }
    Rectangle {
      x: parent.width - 48
      y: 31
      width: 29
      height: 20
      radius: 4
      color: root.arcade.raisedColor
      border.color: root.modeColor
      opacity: 0.4
    }
    Rectangle {
      id: fallingShortcut
      objectName: "keyfallPreviewShortcut"
      anchors.horizontalCenter: parent.horizontalCenter
      y: 9
      width: Math.min(parent.width * 0.66, 190 * root.arcade.textScale)
      height: Math.min(48, parent.height * 0.48)
      radius: 7
      color: root.arcade.surfaceColor
      border.color: root.modeColor
      border.width: 2
      Row {
        anchors.centerIn: parent
        spacing: 6
        Repeater {
          model: ["SUPER", "2"]
          Rectangle {
            required property string modelData
            width: keyLabel.implicitWidth + 12
            height: keyLabel.implicitHeight + 8
            radius: 4
            color: root.arcade.raisedColor
            border.color: root.modeColor
            Text {
              id: keyLabel
              anchors.centerIn: parent
              text: modelData
              color: root.modeInk
              font.family: "monospace"
              font.pixelSize: 9 * root.arcade.fontScale
              font.weight: Font.Bold
            }
          }
        }
      }
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: fallingShortcut.bottom
      anchors.topMargin: 1
      text: "↓"
      color: root.modeInk
      font.pixelSize: 13 * root.arcade.fontScale
      font.weight: Font.Bold
    }
    Rectangle {
      id: keyfallCatch
      objectName: "keyfallPreviewCatch"
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.leftMargin: 8
      anchors.rightMargin: 8
      anchors.bottomMargin: 6
      height: 13
      radius: 7
      color: root.modeColor
      opacity: 0.78
      Rectangle {
        anchors.centerIn: parent
        width: parent.width * 0.48
        height: parent.height + 7
        radius: height / 2
        color: "transparent"
        border.color: root.modeInk
        opacity: 0.7
      }
    }
  }
}
