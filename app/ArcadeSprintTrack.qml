pragma ComponentBehavior: Bound

import QtQuick

Item {
  id: root
  required property var arcade
  objectName: "arcadeSprintTrack"
  clip: true

  readonly property int ghostCount: {
    if (!arcade.previousBest || !Array.isArray(arcade.previousBest.splits)) return 0
    var count = 0
    for (var i = 0; i < arcade.previousBest.splits.length; i++) {
      if (arcade.previousBest.splits[i] <= arcade.elapsedMs) count++
    }
    return count
  }
  readonly property int trackMaximum: Math.max(12, arcade.previousBest.splits.length,
    arcade.deck.length ? Math.min(20, arcade.deck.length) : 0)
  function lapFor(count) { return Math.floor(Math.max(0, count - 1) / trackMaximum) + 1 }
  function progressFor(count) { return count > 0 ? ((count - 1) % trackMaximum + 1) / trackMaximum : 0 }
  readonly property real playerProgress: progressFor(arcade.answeredCount)
  readonly property real ghostProgress: progressFor(ghostCount)
  readonly property int paceDelta: arcade.answeredCount - ghostCount
  readonly property bool activeMotion: arcade.screen === "sprint" && arcade.active
    && !arcade.reducedMotion
  readonly property string paceStatus: !arcade.competitive ? "PRACTICE RUN"
    : !arcade.previousBest.plays ? "SETTING YOUR FIRST PACE"
    : paceDelta === 0 ? "EVEN WITH BEST"
    : Math.abs(paceDelta) + (paceDelta > 0 ? " AHEAD" : " BEHIND")
  readonly property string ghostStatus: arcade.previousBest.plays
    ? "BEST PACE · " + ghostCount + " BY NOW"
    : arcade.competitive ? "SET YOUR FIRST GHOST" : "NO GHOST · PRACTICE RUN"

  component Racer: Item {
    required property color racerColor
    property bool ghost: false
    property string racerName: ""
    objectName: racerName
    width: 38
    height: 20

    Rectangle {
      anchors.centerIn: parent
      width: parent.width + 10
      height: parent.height + 10
      radius: height / 2
      color: racerColor
      opacity: ghost ? 0.06 : 0.13
    }
    Rectangle {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: 18
      height: 4
      radius: 2
      color: racerColor
      opacity: ghost ? 0.18 : 0.58
    }
    Rectangle {
      anchors.right: parent.right
      anchors.rightMargin: 5
      anchors.verticalCenter: parent.verticalCenter
      width: 25
      height: 12
      radius: 4
      color: racerColor
      opacity: ghost ? 0.5 : 1
      border.color: ghost ? root.arcade.mutedColor : root.arcade.foregroundColor
      border.width: 1
    }
    Rectangle {
      anchors.right: parent.right
      anchors.rightMargin: 9
      anchors.verticalCenter: parent.verticalCenter
      width: 8
      height: 7
      radius: 4
      color: root.arcade.surfaceColor
      opacity: ghost ? 0.4 : 0.82
    }
    Rectangle {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: 9
      height: 9
      radius: 2
      rotation: 45
      color: racerColor
      opacity: ghost ? 0.5 : 1
    }
  }

  component FinishGate: Item {
    property string gateName: ""
    objectName: gateName
    width: 8
    height: 18
    Repeater {
      model: 8
      Rectangle {
        required property int index
        x: (index % 2) * 4
        y: Math.floor(index / 2) * parent.height / 4
        width: 4
        height: parent.height / 4
        color: index % 3 === 0 ? root.arcade.modeInk : root.arcade.surfaceColor
        opacity: 0.72
      }
    }
  }

  ArcadeVectorField {
    anchors.fill: parent
    objectName: "arcadeSprintVectorGrid"
    arcade: root.arcade
  }

  Text {
    anchors.left: parent.left
    anchors.leftMargin: 20
    y: 16
    text: "SPRINT // RECALL CIRCUIT"
    color: root.arcade.modeInk
    font.family: "monospace"
    font.pixelSize: 10 * root.arcade.fontScale
    font.weight: Font.Bold
    font.letterSpacing: 0.8
  }
  Text {
    anchors.right: parent.right
    anchors.rightMargin: 20
    y: 16
    text: root.paceStatus
    color: root.arcade.competitive && root.paceDelta > 0
      ? root.arcade.modeInk : root.arcade.mutedColor
    font.pixelSize: 10 * root.arcade.fontScale
    font.weight: Font.Bold
    font.letterSpacing: 0.5
  }

  Rectangle {
    id: raceConsole
    objectName: "arcadeSprintRaceConsole"
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: 18
    height: root.arcade.compactLayout ? 126 : 146
    radius: 2
    color: Qt.tint(root.arcade.raisedColor,
      Qt.rgba(root.arcade.modeAccent.r, root.arcade.modeAccent.g, root.arcade.modeAccent.b, 0.08))
    border.color: Qt.tint(root.arcade.lineColor,
      Qt.rgba(root.arcade.modeAccent.r, root.arcade.modeAccent.g, root.arcade.modeAccent.b, 0.3))

    Text {
      anchors.left: parent.left
      anchors.leftMargin: 16
      anchors.top: parent.top
      anchors.topMargin: 10
      text: "LIVE RACE"
      color: root.arcade.modeInk
      font.pixelSize: 9 * root.arcade.fontScale
      font.weight: Font.Bold
      font.letterSpacing: 1
    }
    Text {
      anchors.right: parent.right
      anchors.rightMargin: 16
      anchors.top: parent.top
      anchors.topMargin: 10
      text: root.ghostStatus
      color: root.arcade.mutedColor
      font.pixelSize: 9 * root.arcade.fontScale
      font.weight: Font.DemiBold
    }

    Item {
      id: playerLane
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: 38
      height: 32
      Text {
        width: 48
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        text: "YOU" + (root.lapFor(root.arcade.answeredCount) > 1
          ? "\nLAP " + root.lapFor(root.arcade.answeredCount) : "")
        color: root.arcade.foregroundColor
        font.pixelSize: 10 * root.arcade.fontScale
        font.weight: Font.Bold
      }
      Rectangle {
        id: playerRail
        anchors.left: parent.left
        anchors.leftMargin: 72
        anchors.right: playerCount.left
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        height: 3
        radius: 2
        color: root.arcade.lineColor
        Repeater {
          model: 10
          Rectangle {
            required property int index
            x: (playerRail.width - width) * index / 9
            anchors.verticalCenter: parent.verticalCenter
            width: 5
            height: 5
            radius: 3
            color: index / 9 <= root.playerProgress ? root.arcade.modeAccent : root.arcade.lineColor
          }
        }
        Racer {
          id: playerRacer
          racerName: "arcadeSprintPlayerRacer"
          racerColor: root.arcade.modeAccent
          x: Math.max(-width / 2, Math.min(parent.width - width / 2,
            root.playerProgress * parent.width - width / 2))
          z: 1
          anchors.verticalCenter: parent.verticalCenter
          Behavior on x {
            enabled: root.activeMotion && targetValue > -playerRacer.width / 2
            NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
          }
        }
        FinishGate {
          gateName: "arcadeSprintPlayerFinish"
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
        }
      }
      Text {
        id: playerCount
        width: 38
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        text: String(root.arcade.answeredCount)
        color: root.arcade.modeInk
        font.family: "monospace"
        font.pixelSize: 18 * root.arcade.fontScale
        font.weight: Font.Bold
        horizontalAlignment: Text.AlignRight
      }
    }

    Item {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: playerLane.bottom
      height: 32
      opacity: root.arcade.previousBest.plays ? 1 : 0.45
      Text {
        width: 48
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        text: "BEST" + (root.lapFor(root.ghostCount) > 1 ? "\nLAP " + root.lapFor(root.ghostCount) : "")
        color: root.arcade.mutedColor
        font.pixelSize: 10 * root.arcade.fontScale
        font.weight: Font.Bold
      }
      Rectangle {
        id: ghostRail
        anchors.left: parent.left
        anchors.leftMargin: 72
        anchors.right: ghostCountLabel.left
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        height: 2
        radius: 1
        color: root.arcade.lineColor
        Racer {
          id: ghostRacer
          racerName: "arcadeSprintGhostRacer"
          visible: root.arcade.previousBest.plays > 0
          racerColor: root.arcade.modeInk
          ghost: true
          x: Math.max(-width / 2, Math.min(parent.width - width / 2,
            root.ghostProgress * parent.width - width / 2))
          z: 1
          anchors.verticalCenter: parent.verticalCenter
          Behavior on x {
            enabled: root.activeMotion && targetValue > -ghostRacer.width / 2
            NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
          }
        }
        FinishGate {
          gateName: "arcadeSprintGhostFinish"
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          opacity: root.arcade.previousBest.plays ? 0.72 : 0.3
        }
      }
      Text {
        id: ghostCountLabel
        width: 38
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        text: root.arcade.previousBest.plays ? String(root.ghostCount) : "—"
        color: root.arcade.mutedColor
        font.family: "monospace"
        font.pixelSize: 17 * root.arcade.fontScale
        font.weight: Font.Bold
        horizontalAlignment: Text.AlignRight
      }
    }

    Text {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.leftMargin: 16
      anchors.rightMargin: 16
      anchors.bottomMargin: 9
      text: root.arcade.previousBest.plays ? "Same deck. Race your best." : "Complete shortcuts to move your racer."
      color: root.arcade.mutedColor
      font.pixelSize: 10 * root.arcade.fontScale
      wrapMode: Text.WordWrap
      horizontalAlignment: Text.AlignHCenter
    }
  }

  Rectangle {
    anchors.fill: parent
    radius: 2
    color: root.arcade.modeAccent
    opacity: root.arcade.responsePending ? 0.1 : 0
    Behavior on opacity { NumberAnimation { duration: 180 } }
  }
}
