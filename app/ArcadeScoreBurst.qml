pragma ComponentBehavior: Bound

import QtQuick

Item {
  id: root
  required property var arcade
  objectName: "arcadeScoreBurst"
  readonly property bool motionEnabled: !arcade.reducedMotion
  readonly property bool animationRunning: burstAnimation.running
  property string burstText: ""
  property real burstScale: 1
  property real burstLift: 0
  property real sparkTravel: 0
  width: Math.max(190 * arcade.textScale, burstLabel.implicitWidth + 52 * arcade.textScale)
  height: 62 * arcade.textScale
  opacity: 0
  scale: burstScale
  transform: Translate { y: root.burstLift }
  z: 8

  function showBurst() {
    if (!arcade.running || !arcade.responsePending) return
    burstAnimation.stop()
    reducedTimer.stop()
    burstText = arcade.lastAwardedPoints > 0 ? "+" + arcade.lastAwardedPoints + " POINTS" : "PRACTICE"
    sparkTravel = 0
    burstLift = 0
    burstScale = 1
    if (!motionEnabled) {
      opacity = 1
      reducedTimer.start()
      return
    }
    burstScale = 0.68
    opacity = 0
    burstAnimation.start()
  }

  function hideBurst() {
    burstAnimation.stop()
    reducedTimer.stop()
    opacity = 0
    burstScale = 1
    burstLift = 0
  }

  Connections {
    target: root.arcade
    function onResponsePendingChanged() {
      if (root.arcade.responsePending) root.showBurst()
      else root.hideBurst()
    }
    function onScreenChanged() { if (!root.arcade.running) root.hideBurst() }
    function onSessionIdChanged() { root.hideBurst() }
    function onReducedMotionChanged() { root.hideBurst() }
  }

  Rectangle {
    anchors.centerIn: parent
    width: parent.width + 20 * root.arcade.textScale
    height: parent.height + 20 * root.arcade.textScale
    radius: 2
    color: root.arcade.modeAccent
    opacity: 0.12
  }

  Rectangle {
    anchors.fill: parent
    radius: 2
    color: root.arcade.surfaceColor
    border.color: root.arcade.modeInk
    border.width: 2
  }

  Repeater {
    model: root.motionEnabled ? 8 : 0
    Rectangle {
      required property int index
      width: 5
      height: 5
      color: root.arcade.modeInk
      opacity: 1 - root.sparkTravel
      x: root.width / 2 + Math.cos(index * Math.PI / 4)
        * (root.width / 2 + root.sparkTravel * 42)
      y: root.height / 2 + Math.sin(index * Math.PI / 4)
        * (root.height / 2 + root.sparkTravel * 30)
    }
  }
  ArcadePixelText {
    id: burstLabel
    objectName: "arcadeScoreBurstLabel"
    anchors.centerIn: parent
    text: root.burstText
    color: root.arcade.modeInk
    font.pixelSize: (root.arcade.compactLayout ? 22 : 28) * root.arcade.fontScale
  }

  Timer {
    id: reducedTimer
    interval: Math.min(650, root.arcade.responseDwellMs)
    onTriggered: root.opacity = 0
  }

  SequentialAnimation {
    id: burstAnimation
    ParallelAnimation {
      NumberAnimation {
        target: root
        property: "sparkTravel"
        to: 1
        duration: 170
        easing.type: Easing.OutCubic
      }
      NumberAnimation {
        target: root
        property: "opacity"
        to: 1
        duration: 90
        easing.type: Easing.OutCubic
      }
      NumberAnimation {
        target: root
        property: "burstScale"
        to: 1.16
        duration: 170
        easing.type: Easing.OutBack
      }
    }
    NumberAnimation {
      target: root
      property: "burstScale"
      to: 1
      duration: 100
      easing.type: Easing.OutCubic
    }
    PauseAnimation { duration: 180 }
    ParallelAnimation {
      NumberAnimation {
        target: root
        property: "burstLift"
        to: -28
        duration: 240
        easing.type: Easing.OutCubic
      }
      NumberAnimation {
        target: root
        property: "opacity"
        to: 0
        duration: 240
        easing.type: Easing.InCubic
      }
    }
  }
}
