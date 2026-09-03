import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
  id: root

  readonly property string assetRoot:
    Quickshell.env("HEXON_ASSET_ROOT") || (Quickshell.shellDir + "/../../assets/characters/hexon")
  readonly property var scales: [0.5, 1, 1.5, 2]
  readonly property var demoStates: ["idle", "talk", "fly", "fly-up", "guide"]
  readonly property real pointPoseScale: 1.07

  property string animationState: "idle"
  property int scaleIndex: 1
  property bool movedRight: false
  property bool reducedMotion: false
  property bool demoRunning: false
  property int demoIndex: 0
  property real flightProgress: 0
  property string guidePhase: "approach"
  property real guideProgress: 0
  property real guideBlend: 0
  property real guideArrivalOffset: 0

  function cycleScale() {
    scaleIndex = (scaleIndex + 1) % scales.length
  }

  function moveCharacter() {
    movedRight = !movedRight
  }

  function setAnimationState(name) {
    guideTimeline.stop()
    animationState = name
    if (name === "fly" || name === "fly-up") {
      flightProgress = reducedMotion ? 0.5 : 0
    } else if (name === "guide") {
      guideProgress = reducedMotion ? 1 : 0
      guidePhase = reducedMotion ? "point" : "approach"
      guideBlend = reducedMotion ? 1 : 0
      guideArrivalOffset = 0
      if (!reducedMotion) guideTimeline.start()
    }
  }

  function selectAnimationState(name) {
    demoRunning = false
    demoTimer.stop()
    setAnimationState(name)
  }

  function startDemo() {
    demoRunning = true
    demoIndex = 0
    setAnimationState(demoStates[demoIndex])
    demoTimer.restart()
  }

  function toggleMotion() {
    reducedMotion = !reducedMotion
    if (reducedMotion && (animationState === "fly" || animationState === "fly-up")) {
      flightProgress = 0.5
    } else if (animationState === "guide") {
      setAnimationState("guide")
    }
  }

  Timer {
    id: demoTimer
    interval: root.animationState === "guide"
      ? 5200
      : root.animationState === "fly" || root.animationState === "fly-up"
        ? 4200
        : 2800
    onTriggered: {
      if (root.demoIndex === root.demoStates.length - 1) {
        root.demoRunning = false
        root.setAnimationState("idle")
        return
      }

      root.demoIndex += 1
      root.setAnimationState(root.demoStates[root.demoIndex])
      restart()
    }
  }

  NumberAnimation {
    target: root
    property: "flightProgress"
    from: 0
    to: 1
    duration: 3600
    loops: Animation.Infinite
    running: (root.animationState === "fly" || root.animationState === "fly-up") &&
      !root.reducedMotion
  }

  SequentialAnimation {
    id: guideTimeline
    loops: Animation.Infinite

    ScriptAction {
      script: {
        root.guidePhase = "approach"
        root.guideProgress = 0
        root.guideBlend = 0
        root.guideArrivalOffset = 0
      }
    }
    NumberAnimation {
      target: root
      property: "guideProgress"
      from: 0
      to: 1
      duration: 1600
      easing.type: Easing.OutCubic
    }
    ScriptAction { script: root.guidePhase = "transition" }
    ParallelAnimation {
      NumberAnimation {
        target: root
        property: "guideBlend"
        from: 0
        to: 1
        duration: 520
        easing.type: Easing.InOutCubic
      }
      SequentialAnimation {
        NumberAnimation {
          target: root
          property: "guideArrivalOffset"
          from: 0
          to: 12
          duration: 180
          easing.type: Easing.OutQuad
        }
        NumberAnimation {
          target: root
          property: "guideArrivalOffset"
          from: 12
          to: 0
          duration: 340
          easing.type: Easing.OutBack
        }
      }
    }
    ScriptAction { script: root.guidePhase = "point" }
    PauseAnimation { duration: 2800 }
  }

  IpcHandler {
    target: "hexon-lab"

    function status(): string {
      return JSON.stringify({
        animationState: root.animationState,
        scale: root.scales[root.scaleIndex],
        movedRight: root.movedRight,
        reducedMotion: root.reducedMotion,
        demoRunning: root.demoRunning,
        guidePhase: root.guidePhase,
        guideBlend: root.guideBlend
      })
    }

    function state(name: string): string {
      if (name !== "idle" && name !== "talk" && name !== "fly" &&
          name !== "fly-up" && name !== "guide") {
        return "invalid-state"
      }
      root.selectAnimationState(name)
      return "ok"
    }

    function demo(): string {
      root.startDemo()
      return "ok"
    }

    function move(): string {
      root.moveCharacter()
      return "ok"
    }

    function scale(): string {
      root.cycleScale()
      return "ok"
    }

    function motion(): string {
      root.toggleMotion()
      return "ok"
    }
  }

  component LabButton: Rectangle {
    id: button

    required property string label
    property bool selected: false
    signal activated

    implicitWidth: buttonText.implicitWidth + 28
    implicitHeight: 40
    radius: 7
    color: selected || mouse.containsMouse ? "#26314f" : "#171d30"
    border.color: selected ? "#7aa2f7" : "#3b4261"
    border.width: selected ? 2 : 1

    Text {
      id: buttonText
      anchors.centerIn: parent
      text: button.label
      color: "#c0caf5"
      font.family: "sans-serif"
      font.pixelSize: 14
      font.weight: Font.DemiBold
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: button.activated()
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: PanelWindow {
      id: overlay

      required property var modelData
      readonly property bool isFocusedScreen: {
        var monitor = Hyprland.monitorFor(modelData)
        return monitor && monitor === Hyprland.focusedMonitor
      }

      screen: modelData
      visible: isFocusedScreen
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "hexon-lab"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
      anchors {
        top: true
        bottom: true
        left: true
        right: true
      }
      mask: Region { Region { item: labPanel } }

      Item {
        anchors.fill: parent
        focus: true

        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_1) root.selectAnimationState("idle")
          else if (event.key === Qt.Key_2) root.selectAnimationState("talk")
          else if (event.key === Qt.Key_3) root.selectAnimationState("fly")
          else if (event.key === Qt.Key_4) root.selectAnimationState("fly-up")
          else if (event.key === Qt.Key_5) root.selectAnimationState("guide")
          else if (event.key === Qt.Key_D) root.startDemo()
          else if (event.key === Qt.Key_M) root.moveCharacter()
          else if (event.key === Qt.Key_S) root.cycleScale()
          else if (event.key === Qt.Key_R) root.toggleMotion()
          else if (event.key === Qt.Key_Escape) Qt.quit()
          else return
          event.accepted = true
        }
      }

      Rectangle {
        id: labPanel
        anchors.centerIn: parent
        width: Math.min(960, parent.width - 40)
        height: Math.min(700, parent.height - 40)
        radius: 18
        color: "#111521"
        border.color: "#3b4261"
        border.width: 1

        ColumnLayout {
          anchors {
            fill: parent
            margins: 24
          }
          spacing: 16

          RowLayout {
            Layout.fillWidth: true

            ColumnLayout {
              spacing: 2

              Text {
                text: "HEXON CHARACTER LAB"
                color: "#7aa2f7"
                font.family: "monospace"
                font.pixelSize: 23
                font.weight: Font.Bold
              }

              Text {
                text: "Reactive teaching motions, flight, speech, and expressions"
                color: "#a9b1d6"
                opacity: 0.78
                font.family: "sans-serif"
                font.pixelSize: 14
              }
            }

            Item { Layout.fillWidth: true }

            Text {
              text: "1 Idle  2 Talk  3 Fly  4 Fly up  5 Guide  D Demo"
              color: "#565f89"
              font.family: "monospace"
              font.pixelSize: 12
            }
          }

          Rectangle {
            id: stage
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            radius: 12
            color: "#0b0e17"
            border.color: "#24283b"

            Grid {
              anchors.fill: parent
              columns: Math.ceil(width / 32)

              Repeater {
                model: Math.ceil(stage.width / 32) * Math.ceil(stage.height / 32)

                Rectangle {
                  required property int index
                  width: 32
                  height: 32
                  color: {
                    var columns = Math.ceil(stage.width / 32)
                    return ((index % columns) + Math.floor(index / columns)) % 2 === 0
                      ? "#101522"
                      : "#151b2c"
                  }
                }
              }
            }

            Rectangle {
              id: guideTarget
              visible: root.animationState === "guide"
              x: stage.width - width - 48
              y: Math.round((stage.height - height) / 2)
              width: 168
              height: 112
              radius: 14
              color: "#171d30"
              border.color: "#bb9af7"
              border.width: 3

              SequentialAnimation on opacity {
                running: guideTarget.visible && !root.reducedMotion
                loops: Animation.Infinite
                NumberAnimation { to: 0.65; duration: 500 }
                NumberAnimation { to: 1; duration: 500 }
              }

              Column {
                anchors.centerIn: parent
                spacing: 8

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: "APPS MENU"
                  color: "#c0caf5"
                  font.family: "monospace"
                  font.pixelSize: 17
                  font.weight: Font.Bold
                }

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: "SUPER + ALT + SPACE"
                  color: "#7dcfff"
                  font.family: "monospace"
                  font.pixelSize: 11
                }
              }
            }

            Item {
              id: guideCharacter
              readonly property real spriteScale: root.scales[root.scaleIndex]
              readonly property real destinationX: guideTarget.x - width + 18
              readonly property real destinationY:
                guideTarget.y + Math.round((guideTarget.height - height) / 2)
              visible: root.animationState === "guide"
              width: 256 * spriteScale
              height: 192 * spriteScale
              x: -width + ((destinationX + width) * root.guideProgress)
              y: destinationY -
                (root.reducedMotion
                  ? 0
                  : Math.sin(root.guideProgress * Math.PI) * 64) +
                root.guideArrivalOffset

              Rectangle {
                anchors.centerIn: parent
                visible: root.guidePhase === "transition"
                width: 150
                height: 150
                radius: 75
                color: "transparent"
                border.color: "#7dcfff"
                border.width: 4
                opacity: Math.sin(root.guideBlend * Math.PI) * 0.8
                scale: 0.7 + (root.guideBlend * 0.7)
              }

              Image {
                anchors.fill: parent
                visible: root.guidePhase !== "point"
                source: root.assetRoot + "/sprites/hexon-flight.png"
                fillMode: Image.PreserveAspectFit
                smooth: false
                mipmap: false
                opacity: root.guidePhase === "transition" ? 1 - root.guideBlend : 1
                scale: root.guidePhase === "transition"
                  ? 1 - (root.guideBlend * 0.03)
                  : 1
              }

              Image {
                anchors.fill: parent
                visible: root.guidePhase !== "approach"
                source: root.assetRoot + "/sprites/hexon-point.png"
                fillMode: Image.PreserveAspectFit
                smooth: false
                mipmap: false
                opacity: root.guidePhase === "transition" ? root.guideBlend : 1
                scale: root.guidePhase === "transition"
                  ? 1 + (root.guideBlend * (root.pointPoseScale - 1))
                  : root.pointPoseScale
              }
            }

            Rectangle {
              anchors {
                horizontalCenter: guideCharacter.horizontalCenter
                bottom: guideCharacter.top
                bottomMargin: -12
              }
              visible: root.animationState === "guide" && root.guidePhase === "point"
              width: guideSpeechText.implicitWidth + 28
              height: 42
              radius: 10
              color: "#e0e5ff"
              border.color: "#bb9af7"

              Text {
                id: guideSpeechText
                anchors.centerIn: parent
                text: "HERE'S YOUR APPS MENU!"
                color: "#1a1b26"
                font.family: "monospace"
                font.pixelSize: 13
                font.weight: Font.Bold
              }
            }

            Item {
              id: character
              readonly property real spriteScale: root.scales[root.scaleIndex]
              readonly property bool isFlying:
                root.animationState === "fly" || root.animationState === "fly-up"
              readonly property bool isFlyingUp: root.animationState === "fly-up"
              visible: root.animationState !== "guide"
              width: (isFlying ? 256 : 192) * spriteScale
              height: 192 * spriteScale
              x: isFlyingUp
                ? Math.round((stage.width - width) / 2)
                : isFlying
                ? (root.reducedMotion
                    ? Math.round((stage.width - width) / 2)
                    : -width + ((stage.width + width) * root.flightProgress))
                : (root.movedRight ? stage.width - width - 48 : 48)
              y: isFlyingUp
                ? (root.reducedMotion
                    ? Math.round((stage.height - height) / 2)
                    : stage.height + width -
                      ((stage.height + (width * 2)) * root.flightProgress))
                : Math.round((stage.height - height) / 2) +
                (isFlying && !root.reducedMotion
                  ? Math.round(Math.sin(root.flightProgress * Math.PI * 2) * 22)
                  : 0)
              rotation: isFlyingUp
                ? -90
                : isFlying && !root.reducedMotion
                ? Math.sin(root.flightProgress * Math.PI * 2) * 3
                : 0

              Behavior on x {
                enabled: !root.reducedMotion && !character.isFlying
                NumberAnimation {
                  duration: 850
                  easing.type: Easing.InOutCubic
                }
              }

              SpriteSequence {
                id: hexon
                anchors.fill: parent
                visible: !character.isFlying
                interpolate: false
                goalSprite: root.animationState === "talk" ? "talk" : "idle"
                onGoalSpriteChanged: jumpTo(goalSprite)

                sprites: [
                  Sprite {
                    name: "idle"
                    source: root.assetRoot + "/sprites/hexon-idle.png"
                    frameCount: 16
                    frameWidth: 192
                    frameHeight: 192
                    frameRate: root.reducedMotion ? 2 : 6
                    to: { "idle": 1, "talk": 1 }
                  },
                  Sprite {
                    name: "talk"
                    source: root.assetRoot + "/sprites/hexon-talk.png"
                    frameCount: 8
                    frameWidth: 192
                    frameHeight: 192
                    frameRate: root.reducedMotion ? 2 : 8
                    to: { "idle": 1, "talk": 1 }
                  }
                ]
              }

              Image {
                anchors.fill: parent
                visible: character.isFlying
                source: root.assetRoot + "/sprites/hexon-flight.png"
                fillMode: Image.PreserveAspectFit
                smooth: false
                mipmap: false
              }
            }

            Rectangle {
              anchors {
                left: character.left
                right: character.right
                bottom: character.bottom
              }
              height: 1
              color: "#7aa2f7"
              visible: root.animationState !== "guide"
              opacity: character.isFlying ? 0 : 0.45
            }

            Rectangle {
              anchors {
                horizontalCenter: character.horizontalCenter
                bottom: character.top
                bottomMargin: -16
              }
              visible: root.animationState === "talk"
              width: speechText.implicitWidth + 28
              height: 42
              radius: 10
              color: "#e0e5ff"
              border.color: "#7aa2f7"

              Text {
                id: speechText
                anchors.centerIn: parent
                text: "READY TO HELP!"
                color: "#1a1b26"
                font.family: "monospace"
                font.pixelSize: 14
                font.weight: Font.Bold
              }
            }

            Text {
              anchors {
                left: parent.left
                bottom: parent.bottom
                margins: 12
              }
              text: "State: " + root.animationState +
                "  |  Scale: " + root.scales[root.scaleIndex] + "x" +
                "  |  Motion: " + (root.reducedMotion ? "reduced" : "full") +
                (root.demoRunning ? "  |  Playing all" : "")
              color: "#7dcfff"
              font.family: "monospace"
              font.pixelSize: 13
            }
          }

          Flow {
            Layout.fillWidth: true
            Layout.preferredHeight: 88
            spacing: 8

            LabButton {
              label: "Idle"
              selected: root.animationState === "idle"
              onActivated: root.selectAnimationState("idle")
            }

            LabButton {
              label: "Talk"
              selected: root.animationState === "talk"
              onActivated: root.selectAnimationState("talk")
            }

            LabButton {
              label: "Fly"
              selected: root.animationState === "fly"
              onActivated: root.selectAnimationState("fly")
            }

            LabButton {
              label: "Fly up"
              selected: root.animationState === "fly-up"
              onActivated: root.selectAnimationState("fly-up")
            }

            LabButton {
              label: "Fly + point"
              selected: root.animationState === "guide"
              onActivated: root.selectAnimationState("guide")
            }

            LabButton {
              label: root.demoRunning ? "Playing all..." : "Play all"
              selected: root.demoRunning
              onActivated: root.startDemo()
            }

            LabButton {
              label: root.movedRight ? "Move left" : "Move right"
              onActivated: root.moveCharacter()
            }

            LabButton {
              label: "Scale " + root.scales[root.scaleIndex] + "x"
              onActivated: root.cycleScale()
            }

            LabButton {
              label: root.reducedMotion ? "Reduced motion" : "Full motion"
              selected: root.reducedMotion
              onActivated: root.toggleMotion()
            }

            LabButton {
              label: "Close"
              onActivated: Qt.quit()
            }
          }
        }
      }
    }
  }
}
