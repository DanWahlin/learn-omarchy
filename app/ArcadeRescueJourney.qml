pragma ComponentBehavior: Bound

import QtQuick

Rectangle {
  id: root
  required property var arcade
  property int completedActions: arcade.rescueCompleted
  property int totalSteps: arcade.runTarget
  property bool showBurst: true
  readonly property var mission: arcade.rescueMission
  readonly property string callsign: mission ? mission.callsign : "RESCUE FLIGHT"
  readonly property string destination: mission ? mission.destination : "DESTINATION"
  readonly property bool motionEnabled: !arcade.reducedMotion
  readonly property bool arrivalReached: totalSteps > 0 && completedActions >= totalSteps
  readonly property real shipProgress: totalSteps > 0
    ? Math.max(0, Math.min(1, completedActions / totalSteps)) : 0
  readonly property real routeStart: arcade.compactLayout ? 34 : 48
  readonly property real routeEnd: width - (arcade.compactLayout ? 48 : 66)
  readonly property real routeY: height * 0.67
  readonly property real planetWidth: arcade.compactLayout ? 48 : 58
  readonly property real planetHeight: arcade.compactLayout ? 34 : 42
  readonly property real shipWidth: arcade.compactLayout ? 52 : 64
  readonly property real shipHeight: arcade.compactLayout ? 30 : 38
  readonly property real shipX: arrivalReached
    ? routeEnd - (shipWidth + planetWidth) / 2 + 4
    : routeStart + shipProgress * (routeEnd - routeStart)
  readonly property string burstText: arcade.lastAwardedPoints > 0
    ? "+" + arcade.lastAwardedPoints : "PRACTICE"
  property real starShift: 0
  property real burstOpacity: 0
  property real burstLift: 0
  implicitHeight: arcade.compactLayout ? 66 : 78
  radius: 12
  color: Qt.tint(arcade.surfaceColor,
    Qt.rgba(arcade.modeAccent.r, arcade.modeAccent.g, arcade.modeAccent.b, 0.08))
  border.color: Qt.tint(arcade.surfaceColor,
    Qt.rgba(arcade.modeAccent.r, arcade.modeAccent.g, arcade.modeAccent.b, 0.38))
  clip: true
  Accessible.role: Accessible.ProgressBar
  Accessible.name: callsign + " to " + destination
  Accessible.description: completedActions + " of " + totalSteps + " systems complete"

  function wrappedStar(position) {
    var value = position - starShift
    return value - Math.floor(value)
  }

  onCompletedActionsChanged: {
    if (!showBurst || completedActions <= 0) return
    burstAnimation.restart()
  }

  Repeater {
    model: 18
    Rectangle {
      required property int index
      readonly property real depth: index % 3 === 0 ? 1 : index % 3 === 1 ? 0.62 : 0.38
      x: root.wrappedStar(((index * 47) % 101) / 101) * root.width
      y: 8 + ((index * 29) % 71) / 71 * Math.max(1, root.height - 22)
      width: depth > 0.8 ? 2.5 : depth > 0.5 ? 2 : 1.5
      height: width
      radius: width / 2
      color: root.arcade.modeAccent
      opacity: 0.08 + depth * 0.18
    }
  }

  Text {
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.leftMargin: 14
    anchors.topMargin: 9
    text: root.callsign
    color: root.arcade.modeInk
    font.family: "monospace"
    font.pixelSize: 9 * root.arcade.fontScale
    font.weight: Font.Bold
    font.letterSpacing: 0.8
    elide: Text.ElideRight
  }

  Text {
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.rightMargin: 14
    anchors.topMargin: 9
    text: root.destination + " · " + root.completedActions + "/" + root.totalSteps
    color: root.arrivalReached ? root.arcade.modeInk : root.arcade.mutedColor
    font.pixelSize: 9 * root.arcade.fontScale
    font.weight: Font.Bold
    elide: Text.ElideLeft
  }

  Rectangle {
    id: route
    x: root.routeStart
    y: root.routeY
    width: Math.max(0, root.routeEnd - root.routeStart)
    height: 2
    radius: 1
    color: root.arcade.lineColor

    Rectangle {
      width: root.shipProgress * parent.width
      height: parent.height
      radius: 1
      color: root.arcade.modeAccent
      opacity: 0.72
      Behavior on width {
        enabled: root.motionEnabled
        NumberAnimation { duration: 520; easing.type: Easing.InOutCubic }
      }
    }
  }

  Repeater {
    model: Math.max(0, root.totalSteps - 1)
    Rectangle {
      id: checkpoint
      required property int index
      readonly property bool completed: root.completedActions > index
      x: root.routeStart + (index + 1) / root.totalSteps
        * (root.routeEnd - root.routeStart) - width / 2
      y: root.routeY - height / 2 + 1
      width: root.arcade.compactLayout ? 9 : 11
      height: width
      radius: width / 2
      color: completed ? root.arcade.modeAccent : root.arcade.surfaceColor
      border.color: completed ? root.arcade.modeInk : root.arcade.lineColor
      border.width: completed ? 2 : 1
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.bottom
        anchors.topMargin: 3
        text: String(checkpoint.index + 1)
        color: checkpoint.completed ? root.arcade.modeInk : root.arcade.mutedColor
        font.family: "monospace"
        font.pixelSize: 7 * root.arcade.fontScale
      }
    }
  }

  Item {
    id: planet
    objectName: "rescueDestinationPlanet"
    x: root.routeEnd - width / 2
    y: root.routeY - height / 2
    width: root.planetWidth
    height: root.planetHeight
    scale: root.arrivalReached ? 1.08 : 1

    Rectangle {
      anchors.centerIn: parent
      width: parent.height * 0.82
      height: width
      radius: width / 2
      color: Qt.tint(root.arcade.surfaceColor,
        Qt.rgba(root.arcade.modeAccent.r, root.arcade.modeAccent.g, root.arcade.modeAccent.b, 0.32))
      opacity: root.arrivalReached ? 0.72 : 0.42
    }
    Image {
      id: planetImage
      objectName: "rescuePlanetImage"
      anchors.fill: parent
      source: root.arcade.arcadeAssetUrl("rescue-planet.png")
      fillMode: Image.PreserveAspectFit
      smooth: true
      mipmap: true
    }

    Behavior on scale {
      enabled: root.motionEnabled
      NumberAnimation { duration: 320; easing.type: Easing.OutBack }
    }
  }

  Item {
    id: ship
    objectName: "rescueShip"
    x: root.shipX - width / 2
    y: root.routeY - height / 2
    width: root.shipWidth
    height: root.shipHeight
    z: 3

    Rectangle {
      anchors.left: parent.left
      anchors.leftMargin: 2
      anchors.verticalCenter: parent.verticalCenter
      width: root.arcade.responsePending && !root.arrivalReached ? 17 : 10
      height: 8
      radius: 4
      color: root.arcade.modeAccent
      opacity: root.arcade.responsePending && !root.arrivalReached ? 0.28 : 0.12
      Behavior on width {
        enabled: root.motionEnabled
        NumberAnimation { duration: 120 }
      }
    }
    Image {
      id: shipImage
      objectName: "rescueShipImage"
      anchors.fill: parent
      source: root.arcade.arcadeAssetUrl("rescue-ship.png")
      fillMode: Image.PreserveAspectFit
      smooth: true
      mipmap: true
    }

    Behavior on x {
      enabled: root.motionEnabled
      NumberAnimation { duration: 520; easing.type: Easing.InOutCubic }
    }
  }

  Text {
    objectName: "rescueScoreBurst"
    x: Math.max(8, Math.min(root.width - width - 8, ship.x + ship.width / 2 - width / 2))
    y: ship.y - 8 + root.burstLift
    text: root.burstText
    color: root.arcade.modeInk
    font.family: "monospace"
    font.pixelSize: 10 * root.arcade.fontScale
    font.weight: Font.Bold
    opacity: root.burstOpacity
    z: 4
  }

  NumberAnimation on starShift {
    from: 0
    to: 1
    duration: 28000
    loops: Animation.Infinite
    running: root.visible && root.motionEnabled
  }

  SequentialAnimation {
    id: burstAnimation
    PropertyAction { target: root; property: "burstOpacity"; value: 1 }
    PropertyAction { target: root; property: "burstLift"; value: 0 }
    PauseAnimation { duration: root.motionEnabled ? 120 : 420 }
    ParallelAnimation {
      NumberAnimation {
        target: root
        property: "burstLift"
        to: -16
        duration: root.motionEnabled ? 620 : 1
        easing.type: Easing.OutCubic
      }
      NumberAnimation {
        target: root
        property: "burstOpacity"
        to: 0
        duration: root.motionEnabled ? 620 : 1
        easing.type: Easing.InCubic
      }
    }
  }
}
