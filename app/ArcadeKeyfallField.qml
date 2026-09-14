pragma ComponentBehavior: Bound

import QtQuick

Item {
  id: root
  required property var arcade
  objectName: "arcadeKeyfallField"
  clip: true

  readonly property bool activeMotion: arcade.screen === "keyfall" && arcade.active
    && !arcade.reducedMotion
  readonly property real approach: Math.max(0, Math.min(1, arcade.keyfallProgress))
  readonly property int recalledCount: arcade.cleanAnswers
  readonly property int practiceCount: arcade.answeredCount - arcade.cleanAnswers
    + (arcade.hinted && !arcade.responsePending ? 1 : 0)
  readonly property bool missed: arcade.hinted && arcade.assistanceReason !== "hint"
  readonly property string phaseLabel: missed ? "SIGNAL MISSED · PRACTICE MODE"
    : arcade.hinted ? "LEARNING ASSIST ACTIVE"
    : arcade.challengeElapsedMs < arcade.arrivalDwellMs ? "READ THE SIGNAL"
    : approach < 0.58 ? "RECALL WINDOW OPEN"
    : "CATCH ZONE APPROACH"

  ArcadeVectorField {
    anchors.fill: parent
    arcade: root.arcade
    perspective: false
  }

  Rectangle {
    anchors.horizontalCenter: parent.horizontalCenter
    y: 44
    width: Math.min(430 * root.arcade.textScale, parent.width * 0.42)
    height: parent.height - 120
    radius: 28
    color: root.arcade.modeAccent
    opacity: 0.022 + root.approach * 0.035
    border.color: root.arcade.modeAccent
    border.width: 1
  }

  Repeater {
    model: 5
    Rectangle {
      required property int index
      x: root.width * (index + 1) / 6
      y: 44
      width: 1
      height: root.height - 120
      color: root.arcade.modeAccent
      opacity: index === 2 ? 0.16 : 0.075
    }
  }

  Repeater {
    model: 12
    Rectangle {
      required property int index
      property real laneX: root.width * ((index * 7) % 11 + 1) / 12
      x: laneX
      width: 12 + index % 4 * 7
      height: index % 3 === 0 ? 6 : 3
      radius: 3
      color: root.arcade.modeAccent
      opacity: 0.13 + index % 4 * 0.03
      y: root.arcade.reducedMotion
        ? 66 + (index * 47) % Math.max(80, root.height - 180)
        : -40 - index * 61
      NumberAnimation on y {
        from: -40 - index * 61
        to: root.height - 88
        duration: 3300 + index % 5 * 420
        loops: Animation.Infinite
        running: root.activeMotion
      }
    }
  }

  Text {
    anchors.left: parent.left
    anchors.leftMargin: 20
    y: 16
    text: "KEYFALL // SIGNAL CATCH"
    color: root.arcade.modeInk
    font.family: "monospace"
    font.pixelSize: 10 * root.arcade.fontScale
    font.weight: Font.Bold
    font.letterSpacing: 0.8
  }
  Text {
    objectName: "arcadeKeyfallPhase"
    anchors.right: parent.right
    anchors.rightMargin: 20
    y: 16
    text: root.phaseLabel
    color: root.arcade.hinted || root.approach > 0.58
      ? root.arcade.modeInk : root.arcade.mutedColor
    font.pixelSize: 10 * root.arcade.fontScale
    font.weight: Font.Bold
    font.letterSpacing: 0.45
  }

  Rectangle {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: catchZone.top
    anchors.bottomMargin: -1
    width: Math.min(parent.width * 0.38, 410 * root.arcade.textScale)
    height: 54 + root.approach * 34
    radius: width / 2
    color: root.arcade.modeAccent
    opacity: 0.025 + root.approach * 0.07
  }

  Repeater {
    model: 3
    Rectangle {
      required property int index
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: catchZone.verticalCenter
      width: Math.min(root.width * (0.2 + index * 0.1),
        (190 + index * 92) * root.arcade.textScale)
      height: 32 + index * 22
      radius: height / 2
      color: "transparent"
      border.color: root.arcade.modeAccent
      border.width: 1
      opacity: 0.4 - index * 0.09 + root.approach * 0.18
    }
  }

  Rectangle {
    id: catchZone
    objectName: "arcadeLearnDock"
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: 18
    height: 52
    radius: 2
    color: Qt.tint(root.arcade.raisedColor,
      Qt.rgba(root.arcade.modeAccent.r, root.arcade.modeAccent.g, root.arcade.modeAccent.b,
        0.09 + root.approach * 0.08))
    border.color: root.arcade.hinted || root.approach > 0.65
      ? root.arcade.modeInk : root.arcade.lineColor
    border.width: root.arcade.hinted || root.approach > 0.82 ? 2 : 1

    Row {
      anchors.fill: parent
      anchors.margins: 6
      spacing: 8

      Rectangle {
        id: recalledBay
        objectName: "arcadeKeyfallRecalledBay"
        width: (parent.width - parent.spacing) / 2
        height: parent.height
        radius: 2
        color: Qt.tint(root.arcade.surfaceColor,
          Qt.rgba(root.arcade.modeAccent.r, root.arcade.modeAccent.g,
            root.arcade.modeAccent.b, root.arcade.responsePending
              && root.arcade.lastAwardedPoints > 0 ? 0.24 : 0.08))
        border.color: root.arcade.responsePending && root.arcade.lastAwardedPoints > 0
          ? root.arcade.modeInk : root.arcade.lineColor
        border.width: root.arcade.responsePending && root.arcade.lastAwardedPoints > 0 ? 2 : 1
        ArcadePixelText {
          anchors.centerIn: parent
          text: "RECALLED " + root.recalledCount
          color: root.arcade.responsePending && root.arcade.lastAwardedPoints > 0
            ? root.arcade.modeInk : root.arcade.mutedColor
          font.pixelSize: 10 * root.arcade.fontScale
        }
      }

      Rectangle {
        objectName: "arcadeKeyfallPracticeBay"
        width: (parent.width - parent.spacing) / 2
        height: parent.height
        radius: 2
        color: Qt.tint(root.arcade.surfaceColor,
          Qt.rgba(root.arcade.modeAccent.r, root.arcade.modeAccent.g,
            root.arcade.modeAccent.b, root.arcade.hinted ? 0.24 : 0.08))
        border.color: root.arcade.hinted ? root.arcade.modeInk : root.arcade.lineColor
        border.width: root.arcade.hinted ? 2 : 1
        ArcadePixelText {
          anchors.centerIn: parent
          text: "PRACTICE " + root.practiceCount
          color: root.arcade.hinted ? root.arcade.modeInk : root.arcade.mutedColor
          font.pixelSize: 10 * root.arcade.fontScale
        }
      }
    }
  }

  Rectangle {
    anchors.fill: parent
    radius: 2
    color: root.arcade.modeAccent
    opacity: root.arcade.responsePending ? 0.11 : 0
    Behavior on opacity { NumberAnimation { duration: 180 } }
  }
}
