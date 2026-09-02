import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string appRoot: Quickshell.env("LEARN_OMARCHY_ROOT") || (Quickshell.shellDir + "/..")
  readonly property string coursePath: Quickshell.env("LEARN_OMARCHY_COURSE") || (appRoot + "/courses/omarchy-basics.json")
  readonly property string courseDir: Quickshell.env("LEARN_OMARCHY_COURSE_DIR") || (appRoot + "/courses")
  readonly property string themePath: home + "/.local/state/omarchy/current/theme"
  readonly property string themeNamePath: home + "/.local/state/omarchy/current/theme.name"

  property var course: null
  property int lessonIndex: 0
  property int stepIndex: 0
  property string phase: "loading"
  property string errorMessage: ""
  property int remapGeneration: 0
  property var activeKeys: ({})

  property color accent: "#7aa2f7"
  property color foreground: "#a9b1d6"
  property color background: "#1a1b26"
  property color muted: "#565f89"
  property color urgent: "#f7768e"

  readonly property var currentLesson: course && course.lessons ? course.lessons[lessonIndex] : null
  readonly property var currentStep: currentLesson && currentLesson.steps ? currentLesson.steps[stepIndex] : null
  readonly property bool courseFinished: phase === "complete"

  function colorWithAlpha(colorValue, alpha) {
    return Qt.rgba(colorValue.r, colorValue.g, colorValue.b, alpha)
  }

  function keyName(key) {
    if (key === Qt.Key_Meta || key === Qt.Key_Super_L || key === Qt.Key_Super_R) return "SUPER"
    if (key === Qt.Key_Alt || key === Qt.Key_AltGr) return "ALT"
    if (key === Qt.Key_Control) return "CTRL"
    if (key === Qt.Key_Shift) return "SHIFT"
    if (key === Qt.Key_Space) return "SPACE"
    if (key === Qt.Key_Return || key === Qt.Key_Enter) return "RETURN"
    if (key === Qt.Key_Escape) return "ESCAPE"
    if (key >= Qt.Key_A && key <= Qt.Key_Z) return String.fromCharCode(key)
    if (key >= Qt.Key_0 && key <= Qt.Key_9) return String.fromCharCode(key)
    return ""
  }

  function updateActiveKeys(event, pressed) {
    var next = {}
    if (event.modifiers & Qt.MetaModifier) next.SUPER = true
    if (event.modifiers & Qt.AltModifier) next.ALT = true
    if (event.modifiers & Qt.ControlModifier) next.CTRL = true
    if (event.modifiers & Qt.ShiftModifier) next.SHIFT = true

    var direct = keyName(event.key)
    if (pressed && direct) next[direct] = true
    else if (!pressed && direct) delete next[direct]
    activeKeys = next
  }

  function clearActiveKeys() {
    activeKeys = {}
  }

  function parseTheme(raw) {
    var next = {
      accent: root.accent,
      foreground: root.foreground,
      background: root.background,
      muted: root.muted,
      urgent: root.urgent
    }
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var match = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (!match) continue
      if (match[1] === "accent") next.accent = match[2]
      else if (match[1] === "foreground") next.foreground = match[2]
      else if (match[1] === "background") next.background = match[2]
      else if (match[1] === "muted" || match[1] === "dark_foreground") next.muted = match[2]
      else if (match[1] === "red") next.urgent = match[2]
    }
    root.accent = next.accent
    root.foreground = next.foreground
    root.background = next.background
    root.muted = next.muted
    root.urgent = next.urgent
  }

  function fail(message) {
    stopAudio()
    errorMessage = String(message)
    phase = "error"
    console.error("learn-omarchy:", errorMessage)
  }

  function loadCourse(raw) {
    var parsed
    try {
      parsed = JSON.parse(String(raw || ""))
    } catch (error) {
      fail("Course JSON couldn't be parsed: " + error)
      return
    }

    if (!parsed || parsed.schemaVersion !== 1 || !Array.isArray(parsed.lessons) || parsed.lessons.length === 0) {
      fail("Course metadata is invalid. Run learn-omarchy-validate for details.")
      return
    }

    course = parsed
    lessonIndex = 0
    stepIndex = 0
    clearActiveKeys()
    phase = "waiting"
    errorMessage = ""
    Qt.callLater(playCurrentAudio)
  }

  function startCurrentStep() {
    stopAudio()
    clearActiveKeys()
    phase = "waiting"
    Qt.callLater(playCurrentAudio)
  }

  function completeCurrentStep() {
    if (!currentStep || phase !== "waiting") return
    stopAudio()
    clearActiveKeys()
    phase = "highlight"
    remapGeneration++
    completionTimer.interval = Math.max(250, Number(currentStep.highlight.durationMs || 2000))
    completionTimer.restart()
  }

  function advance() {
    if (!currentLesson || !currentStep) return
    if (stepIndex + 1 < currentLesson.steps.length) {
      stepIndex++
      startCurrentStep()
      return
    }
    if (lessonIndex + 1 < course.lessons.length) {
      lessonIndex++
      stepIndex = 0
      startCurrentStep()
      return
    }
    phase = "complete"
    remapGeneration++
  }

  function playCurrentAudio() {
    if (!currentStep || !currentStep.audio) return
    audioProcess.running = false
    audioProcess.command = [
      "mpv",
      "--no-video",
      "--really-quiet",
      "--",
      courseDir + "/" + currentStep.audio
    ]
    audioProcess.running = true
  }

  function stopAudio() {
    if (audioProcess.running) audioProcess.running = false
  }

  function runHelp() {
    if (!currentStep || !currentStep.help || !Array.isArray(currentStep.help.command)) {
      fail("This step doesn't define a Help action.")
      return
    }
    helpProcess.command = currentStep.help.command
    helpProcess.running = true
  }

  function handleHyprlandEvent(event) {
    if (!currentStep || phase !== "waiting") return
    var completion = currentStep.completion
    if (
      completion &&
      completion.type === "hyprland-layer-open" &&
      event.name === "openlayer" &&
      String(event.data).trim() === completion.namespace
    ) {
      completeCurrentStep()
    }
  }

  FileView {
    id: courseFile
    path: root.coursePath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadCourse(text())
    onFileChanged: reload()
    onLoadFailed: function(error) {
      root.fail("Course couldn't be loaded from " + root.coursePath + ": " + error)
    }
  }

  FileView {
    id: colorsFile
    path: root.themePath + "/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.parseTheme(text())
    onFileChanged: reload()
  }

  FileView {
    id: themeNameFile
    path: root.themeNamePath
    watchChanges: true
    printErrors: false
    onFileChanged: {
      reload()
      colorsFile.reload()
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      root.handleHyprlandEvent(event)
    }
  }

  Process {
    id: audioProcess
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.phase === "waiting") {
        root.fail("Narration couldn't be played. Check the audio path and mpv installation.")
      }
    }
  }

  Process {
    id: helpProcess
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.fail("The Help action failed with exit code " + exitCode + ".")
      }
    }
  }

  Timer {
    id: completionTimer
    repeat: false
    onTriggered: root.advance()
  }

  Variants {
    model: Quickshell.screens

    delegate: PanelWindow {
      id: overlay

      required property var modelData
      property bool mapped: true
      readonly property bool isFocusedScreen: {
        var monitor = Hyprland.monitorFor(modelData)
        return monitor && monitor === Hyprland.focusedMonitor
      }
      readonly property bool shouldShow: root.phase !== "loading" && isFocusedScreen
      readonly property var highlight: root.currentStep ? root.currentStep.highlight : null

      screen: modelData
      visible: mapped && shouldShow
      anchors {
        top: true
        bottom: true
        left: true
        right: true
      }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "learn-omarchy"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: root.phase === "waiting"
        ? WlrKeyboardFocus.OnDemand
        : WlrKeyboardFocus.None
      mask: Region { item: controls }

      function anchoredX(anchor, itemWidth, offset) {
        if (anchor.indexOf("left") !== -1 || anchor === "left") return offset
        if (anchor.indexOf("right") !== -1 || anchor === "right") return width - itemWidth + offset
        return Math.round((width - itemWidth) / 2) + offset
      }

      function anchoredY(anchor, itemHeight, offset) {
        if (anchor.indexOf("top") !== -1 || anchor === "top") return offset
        if (anchor.indexOf("bottom") !== -1 || anchor === "bottom") return height - itemHeight + offset
        return Math.round((height - itemHeight) / 2) + offset
      }

      Connections {
        target: root
        function onRemapGenerationChanged() {
          if (!overlay.shouldShow) return
          overlay.mapped = false
          remapTimer.restart()
        }
      }

      Timer {
        id: remapTimer
        interval: 50
        repeat: false
        onTriggered: overlay.mapped = true
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: root.phase === "waiting"

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          root.updateActiveKeys(event, true)
          event.accepted = false
        }
        Keys.onReleased: function(event) {
          root.updateActiveKeys(event, false)
          event.accepted = false
        }

        Connections {
          target: root
          function onPhaseChanged() {
            if (root.phase === "waiting") Qt.callLater(function() { keyCatcher.forceActiveFocus() })
          }
        }

        Component.onCompleted: {
          if (root.phase === "waiting") Qt.callLater(function() { keyCatcher.forceActiveFocus() })
        }
      }

      Rectangle {
        id: highlightFrame
        visible: root.phase === "highlight" && overlay.highlight
        width: overlay.highlight ? overlay.highlight.width : 0
        height: overlay.highlight ? overlay.highlight.height : 0
        x: overlay.highlight ? overlay.anchoredX(overlay.highlight.anchor, width, overlay.highlight.x) : 0
        y: overlay.highlight ? overlay.anchoredY(overlay.highlight.anchor, height, overlay.highlight.y) : 0
        color: "transparent"
        border.color: root.accent
        border.width: overlay.highlight ? overlay.highlight.borderWidth : 0
        radius: overlay.highlight
          ? (overlay.highlight.shape === "circle" ? width / 2 : Number(overlay.highlight.radius || 0))
          : 0

        SequentialAnimation on opacity {
          running: highlightFrame.visible
          loops: Animation.Infinite
          NumberAnimation { from: 1; to: 0.58; duration: 650; easing.type: Easing.InOutSine }
          NumberAnimation { from: 0.58; to: 1; duration: 650; easing.type: Easing.InOutSine }
        }
      }

      ColumnLayout {
        id: teachingContent
        visible: root.phase === "waiting" || root.phase === "highlight" || root.courseFinished
        anchors {
          horizontalCenter: parent.horizontalCenter
          bottom: parent.bottom
          bottomMargin: 54
        }
        spacing: 12

        Rectangle {
          Layout.alignment: Qt.AlignHCenter
          Layout.preferredWidth: Math.min(implicitWidth, overlay.width - 48)
          Layout.preferredHeight: messageText.implicitHeight + 28
          implicitWidth: Math.max(360, messageText.implicitWidth + 40)
          color: root.colorWithAlpha(root.background, 0.96)
          border.color: root.colorWithAlpha(root.accent, 0.9)
          border.width: 2
          radius: 12

          Text {
            id: messageText
            anchors.centerIn: parent
            width: Math.min(implicitWidth, overlay.width - 88)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            color: root.foreground
            font.family: "sans-serif"
            font.pixelSize: 18
            font.weight: Font.DemiBold
            text: {
              if (root.courseFinished) return "Course complete!"
              if (root.phase === "highlight" && root.currentStep.completionMessage)
                return root.currentStep.completionMessage
              return root.currentStep ? root.currentStep.instruction : ""
            }
          }
        }

        RowLayout {
          visible: !root.courseFinished && root.currentStep && root.currentStep.keys
          Layout.alignment: Qt.AlignHCenter
          spacing: 16

          Repeater {
            model: root.currentStep && root.currentStep.keys ? root.currentStep.keys : []

            Rectangle {
              required property string modelData
              readonly property bool keyActive: modelData !== "+" && root.activeKeys[modelData] === true
              implicitWidth: keyLabel.implicitWidth + (modelData === "+" ? 24 : 36)
              implicitHeight: 54
              scale: keyActive ? 1.08 : 1
              color: keyActive
                ? root.accent
                : modelData === "+"
                ? root.colorWithAlpha(root.background, 0.86)
                : root.colorWithAlpha(root.accent, 0.22)
              border.color: keyActive ? root.foreground : (modelData === "+" ? root.muted : root.accent)
              border.width: keyActive ? 3 : (modelData === "+" ? 1 : 2)
              radius: 8

              Behavior on scale {
                NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
              }
              Behavior on color {
                ColorAnimation { duration: 90 }
              }

              Text {
                id: keyLabel
                anchors.centerIn: parent
                text: modelData
                textFormat: Text.PlainText
                color: keyActive ? root.background : root.foreground
                font.family: "monospace"
                font.pixelSize: modelData === "+" ? 19 : 18
                font.weight: Font.Bold
              }
            }
          }
        }
      }

      RowLayout {
        id: controls
        anchors {
          top: parent.top
          right: parent.right
          topMargin: 42
          rightMargin: 24
        }
        spacing: 8

        Rectangle {
          id: helpButton
          visible: root.phase === "waiting" && root.currentStep && root.currentStep.help
          implicitWidth: helpRow.implicitWidth + 24
          implicitHeight: 42
          color: helpMouse.containsMouse
            ? root.colorWithAlpha(root.accent, 0.34)
            : root.colorWithAlpha(root.background, 0.96)
          border.color: root.accent
          border.width: 2
          radius: 21

          RowLayout {
            id: helpRow
            anchors.centerIn: parent
            spacing: 8

            Text {
              text: "?"
              color: root.accent
              font.family: "sans-serif"
              font.pixelSize: 20
              font.weight: Font.Bold
            }
            Text {
              text: "Help"
              color: root.foreground
              font.family: "sans-serif"
              font.pixelSize: 14
              font.weight: Font.DemiBold
            }
          }

          MouseArea {
            id: helpMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.runHelp()
          }
        }

        Rectangle {
          implicitWidth: 42
          implicitHeight: 42
          color: closeMouse.containsMouse
            ? root.colorWithAlpha(root.urgent, 0.3)
            : root.colorWithAlpha(root.background, 0.96)
          border.color: closeMouse.containsMouse ? root.urgent : root.muted
          border.width: 1
          radius: 21

          Text {
            anchors.centerIn: parent
            text: "X"
            color: root.foreground
            font.family: "sans-serif"
            font.pixelSize: 22
          }

          MouseArea {
            id: closeMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.stopAudio()
              Qt.quit()
            }
          }
        }
      }

      Rectangle {
        visible: root.phase === "error"
        anchors.centerIn: parent
        width: Math.min(620, parent.width - 48)
        height: errorText.implicitHeight + 48
        color: root.colorWithAlpha(root.background, 0.98)
        border.color: root.urgent
        border.width: 2
        radius: 12

        Text {
          id: errorText
          anchors {
            fill: parent
            margins: 24
          }
          text: root.errorMessage
          textFormat: Text.PlainText
          color: root.foreground
          font.family: "sans-serif"
          font.pixelSize: 16
          wrapMode: Text.WordWrap
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }
      }
    }
  }
}
