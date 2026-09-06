pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../app" as App

ShellRoot {
  id: root
  readonly property string charactersRoot: Quickshell.env("CHARACTER_LAB_ROOT")
    || (Quickshell.shellDir + "/assets/characters")
  property string characterName: Quickshell.env("CHARACTER_LAB_CHARACTER") || "hexon"
  property var characters: []
  property var characterConfig: ({})
  property string loadError: ""
  property string animationState: "idle"
  property string selectedPose: "idle"
  property bool speaking: false
  property bool inFlight: false
  property int direction: 1
  property bool reducedMotion: false
  property bool playing: true
  property bool landmarks: false
  property int frame: -1
  property real spriteScale: 1
  property string background: "checkerboard"
  property bool movedRight: false
  property bool demoRunning: false
  property int demoIndex: 0
  property real progress: 0
  readonly property var states: ["idle", "talk", "point", "point-up", "fly", "fly-up", "guide"]

  function selectCharacter(name) {
    if (!characters.some(function(c) { return c.id === name })) return "invalid-character"
    if (name === characterName) return "ok"
    characterConfig = ({})
    loadError = ""
    characterName = name
    frame = -1
    return "ok"
  }

  function setState(name) {
    if (states.indexOf(name) < 0) return "invalid-state"
    animationState = name
    selectedPose = name === "point" || name === "point-up" ? name : name === "guide" ? "point" : "idle"
    speaking = name === "talk" || name === "guide"
    inFlight = name === "fly" || name === "fly-up"
    frame = -1
    progress = 0
    if ((inFlight || name === "guide") && !reducedMotion) travel.restart()
    return "ok"
  }

  function selectState(name) {
    demoRunning = false
    return setState(name)
  }

  function scrub(value) {
    frame = Math.max(0, Math.min(coach.frameCount - 1, value))
    playing = false
  }

  function togglePlay() {
    if (!playing) frame = -1
    playing = !playing
  }

  FileView {
    path: root.charactersRoot + "/index.json"
    onLoaded: {
      try { root.characters = JSON.parse(text()).characters }
      catch (error) { root.loadError = "Invalid character index: " + error }
    }
    onLoadFailed: root.loadError = "Cannot load character index"
  }
  FileView {
    path: root.charactersRoot + "/" + root.characterName + "/character.json"
    onLoaded: {
      try {
        root.characterConfig = JSON.parse(text())
        root.loadError = ""
      } catch (error) { root.loadError = "Invalid character manifest: " + error }
    }
    onLoadFailed: root.loadError = "Cannot load character manifest"
  }

  NumberAnimation {
    id: travel
    target: root
    property: "progress"
    from: 0
    to: 1
    duration: root.animationState === "guide" ? 6000 : 4000
    loops: Animation.Infinite
    running: window.visible && (root.inFlight || root.animationState === "guide")
      && !root.reducedMotion
    paused: running && (!root.playing || root.frame >= 0)
  }
  Timer {
    interval: 6500
    repeat: true
    running: window.visible && root.demoRunning && root.playing
    onTriggered: {
      root.demoIndex = (root.demoIndex + 1) % root.states.length
      root.setState(root.states[root.demoIndex])
    }
  }

  IpcHandler {
    target: "hexon-lab"
    function status(): string {
      return JSON.stringify({
        character: root.characterName, animationState: root.animationState,
        pose: coach.pose, talking: coach.talking, flying: coach.isFlyingSprite,
        facing: root.direction, scale: root.spriteScale, background: root.background,
        reducedMotion: root.reducedMotion, animated: root.playing,
        previewFrame: root.frame, currentFrame: coach.currentFrame, frameCount: coach.frameCount,
        landmarks: root.landmarks, movedRight: root.movedRight,
        demoRunning: root.demoRunning, error: root.loadError || coach.errorMessage,
        pointTip: [coach.pointTipX, coach.pointTipY], upTip: [coach.upTipX, coach.upTipY],
        flameSockets: coach.flameSockets
      })
    }
    function character(name: string): string { return root.selectCharacter(name) }
    function state(name: string): string { return root.selectState(name) }
    function pose(name: string): string {
      if (["idle", "point", "point-up"].indexOf(name) < 0) return "invalid-pose"
      root.demoRunning = false
      root.animationState = name
      root.selectedPose = name
      root.inFlight = false
      root.frame = -1
      return "ok"
    }
    function speech(enabled: bool): string { root.speaking = enabled; return "ok" }
    function flight(enabled: bool): string { root.inFlight = enabled; return "ok" }
    function facing(value: int): string {
      if (value !== 1 && value !== -1) return "invalid-facing"
      root.direction = value
      return "ok"
    }
    function background(name: string): string {
      if (["light", "dark", "checkerboard"].indexOf(name) < 0) return "invalid-background"
      root.background = name
      return "ok"
    }
    function size(value: real): string {
      if (!isFinite(value) || value < 0.5 || value > 3) return "invalid-scale"
      root.spriteScale = value
      return "ok"
    }
    function frame(value: int): string {
      if (value < -1 || value >= coach.frameCount) return "invalid-frame"
      if (value < 0) { root.frame = -1; root.playing = true }
      else root.scrub(value)
      return "ok"
    }
    function pause(): string { root.playing = false; return "ok" }
    function play(): string { root.frame = -1; root.playing = true; return "ok" }
    function landmarks(enabled: bool): string { root.landmarks = enabled; return "ok" }
    function demo(): string { root.demoRunning = true; root.demoIndex = 0; root.setState("idle"); return "ok" }
    function move(): string { root.movedRight = !root.movedRight; return "ok" }
    function scale(): string { root.spriteScale = root.spriteScale >= 2 ? 0.5 : root.spriteScale + 0.5; return "ok" }
    function motion(): string { root.reducedMotion = !root.reducedMotion; return "ok" }
  }

  component LabButton: Rectangle {
    id: button
    required property string label
    property bool selected: false
    signal activated
    implicitWidth: labelText.implicitWidth + 20
    implicitHeight: 32
    radius: 5
    color: selected ? "#334665" : mouse.containsMouse ? "#26314f" : "#171d30"
    border.color: selected ? "#7aa2f7" : "#555e7b"
    Text {
      id: labelText
      anchors.centerIn: parent
      text: button.label
      color: "#e0e5ff"
      font.pixelSize: 13
    }
    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: button.activated()
    }
  }

  FloatingWindow {
    id: window
    title: "Character Lab"
    visible: true
    implicitWidth: 1080
    implicitHeight: 760
    color: "#111521"

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: 20
      spacing: 10
      Text {
        text: "CHARACTER LAB · " + (root.characterConfig.displayName || root.characterName)
        color: "#c0caf5"
        font.pixelSize: 22
        font.bold: true
      }
      Text {
        text: "Production renderer · cyan: body / baseline · red: side tip · green: up tip · amber: flame sockets"
        color: "#a9b1d6"
        font.pixelSize: 13
      }
      Flow {
        Layout.fillWidth: true
        Layout.preferredHeight: childrenRect.height
        spacing: 6
        Repeater {
          model: root.characters
          LabButton {
            required property var modelData
            label: modelData.displayName
            selected: root.characterName === modelData.id
            onActivated: root.selectCharacter(modelData.id)
          }
        }
        Repeater {
          model: root.states
          LabButton {
            required property string modelData
            label: modelData
            selected: root.animationState === modelData
            onActivated: root.selectState(modelData)
          }
        }
      }
      Rectangle {
        id: stage
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        color: root.background === "light" ? "#f4f4f4" : "#0b0e17"
        Grid {
          visible: root.background === "checkerboard"
          columns: Math.ceil(stage.width / 24)
          Repeater {
            model: Math.ceil(stage.width / 24) * Math.ceil(stage.height / 24)
            Rectangle {
              required property int index
              width: 24
              height: 24
              color: (index % Math.ceil(stage.width / 24) + Math.floor(index / Math.ceil(stage.width / 24))) % 2
                ? "#999999" : "#cccccc"
            }
          }
        }
        Rectangle {
          id: guideTarget
          visible: root.animationState === "guide"
          x: root.direction > 0 ? stage.width - 130 : 30
          y: stage.height / 2 - 12
          width: 100
          height: 70
          radius: 8
          color: "#171d30"
          border.color: "#bb9af7"
          Text { anchors.centerIn: parent; text: "APPS MENU"; color: "#c0caf5"; font.pixelSize: 12 }
        }
        App.CharacterSprite {
          id: coach
          readonly property bool guiding: root.animationState === "guide"
          readonly property real approach: root.reducedMotion ? 1 : Math.min(1, root.progress * 3)
          readonly property real approachStart: root.direction > 0 ? -224 * scale : stage.width
          assetRoot: root.charactersRoot + "/" + root.characterName
          config: root.characterConfig
          pose: root.selectedPose
          talking: root.speaking
          flying: root.inFlight || (guiding && approach < 1)
          facing: root.direction
          reducedMotion: root.reducedMotion
          animated: root.playing
          previewFrame: root.frame
          showLandmarks: root.landmarks
          scale: root.spriteScale
          transformOrigin: Item.TopLeft
          x: guiding
            ? approachStart + (guideTarget.x + (root.direction < 0 ? guideTarget.width : 0)
                - pointTipX * scale - approachStart) * approach
            : root.inFlight && root.animationState !== "fly-up" && !root.reducedMotion
              ? -224 * scale + (stage.width + 224 * scale) * (root.direction > 0 ? root.progress : 1 - root.progress)
              : root.movedRight ? stage.width - 224 * scale - 35 : (stage.width - 224 * scale) / 2
          y: guiding ? guideTarget.y + 35 - pointTipY * scale - (root.reducedMotion ? 0 : Math.sin(approach * Math.PI) * 60)
            : root.animationState === "fly-up" && !root.reducedMotion
              ? stage.height - (stage.height + 192 * scale) * root.progress
              : (stage.height - 192 * scale) / 2
        }
      }
      Flow {
        Layout.fillWidth: true
        Layout.preferredHeight: childrenRect.height
        spacing: 6
        LabButton { label: "Speech"; selected: root.speaking; onActivated: root.speaking = !root.speaking }
        LabButton { label: "Flight"; selected: root.inFlight; onActivated: root.inFlight = !root.inFlight }
        LabButton { label: root.direction > 0 ? "Facing →" : "Facing ←"; onActivated: root.direction *= -1 }
        LabButton { label: "Reduced motion"; selected: root.reducedMotion; onActivated: root.reducedMotion = !root.reducedMotion }
        LabButton { label: "Landmarks"; selected: root.landmarks; onActivated: root.landmarks = !root.landmarks }
        LabButton { label: "Move"; onActivated: root.movedRight = !root.movedRight }
        LabButton { label: "Demo"; selected: root.demoRunning; onActivated: { root.demoRunning = !root.demoRunning; root.demoIndex = 0; root.setState("idle") } }
        Repeater {
          model: ["light", "dark", "checkerboard"]
          LabButton {
            required property string modelData
            label: modelData
            selected: root.background === modelData
            onActivated: root.background = modelData
          }
        }
      }
      Flow {
        Layout.fillWidth: true
        Layout.preferredHeight: childrenRect.height
        spacing: 6
        Repeater {
          model: [0.5, 1, 1.5, 2, 3]
          LabButton {
            required property real modelData
            label: modelData + "×"
            selected: root.spriteScale === modelData
            onActivated: root.spriteScale = modelData
          }
        }
        LabButton { label: root.playing ? "Pause" : "Play"; onActivated: root.togglePlay() }
        LabButton { label: "‹ Frame"; onActivated: root.scrub((coach.currentFrame + coach.frameCount - 1) % coach.frameCount) }
        LabButton { label: "Frame ›"; onActivated: root.scrub((coach.currentFrame + 1) % coach.frameCount) }
        Text {
          text: "  Frame " + coach.currentFrame + "/" + (coach.frameCount - 1) + (root.frame < 0 ? " · automatic" : " · scrubbed")
          color: "#c0caf5"
          height: 32
          verticalAlignment: Text.AlignVCenter
        }
      }
      Text {
        Layout.fillWidth: true
        text: root.loadError || coach.errorMessage || "Space: pause/play · ←/→: frame · Esc: close · IPC target: hexon-lab"
        color: root.loadError || coach.errorMessage ? "#ff7777" : "#a9b1d6"
        wrapMode: Text.Wrap
      }
    }
    Item {
      anchors.fill: parent
      focus: true
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Space) root.togglePlay()
        else if (event.key === Qt.Key_Left) root.scrub((coach.currentFrame + coach.frameCount - 1) % coach.frameCount)
        else if (event.key === Qt.Key_Right) root.scrub((coach.currentFrame + 1) % coach.frameCount)
        else if (event.key === Qt.Key_Escape) Qt.quit()
        else return
        event.accepted = true
      }
    }
  }
}
