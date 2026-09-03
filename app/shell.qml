import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")
  readonly property string appRoot: Quickshell.env("LEARN_OMARCHY_ROOT") || (Quickshell.shellDir + "/..")
  readonly property string coursePath: Quickshell.env("LEARN_OMARCHY_COURSE") || (appRoot + "/courses/omarchy-basics.json")
  readonly property string courseDir: Quickshell.env("LEARN_OMARCHY_COURSE_DIR") || (appRoot + "/courses")
  readonly property string progressPath: stateHome + "/learn-omarchy/progress.json"
  readonly property string themePath: stateHome + "/omarchy/current/theme"
  readonly property string themeNamePath: stateHome + "/omarchy/current/theme.name"

  property var course: null
  property int lessonIndex: -1
  property int selectedLessonIndex: 0
  property int stepIndex: 0
  property string phase: "loading"
  property string errorMessage: ""
  property int remapGeneration: 0
  property var completedLessons: ({})
  property var progressByCourse: ({})
  property var activeKeys: ({})
  property bool comboTriggered: false
  property bool actionRunning: false
  property bool actionStopping: false
  property bool pendingStepAction: false
  property string pendingActionStepId: ""
  property int pendingActionGeneration: -1
  property int actionGeneration: 0
  property int actionProcessGeneration: -1
  property bool keyboardFocused: false
  property string actionStepId: ""
  property string actionCompletionType: ""
  property int actionCompletionDelay: 250
  property bool audioEnabled: true
  property bool audioStopRequested: false
  property string audioProcessPath: ""
  property string pendingAudioPath: ""

  property color accent: "#7aa2f7"
  property color foreground: "#a9b1d6"
  property color background: "#1a1b26"
  property color muted: "#565f89"
  property color urgent: "#f7768e"
  property color instruction: "#e0af68"

  readonly property var currentLesson: course && lessonIndex >= 0 ? course.lessons[lessonIndex] : null
  readonly property var currentStep: currentLesson ? currentLesson.steps[stepIndex] : null
  readonly property int completedCount: {
    if (!course) return 0
    var count = 0
    for (var i = 0; i < course.lessons.length; i++) {
      if (completedLessons[course.lessons[i].id]) count++
    }
    return count
  }

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
    if (key === Qt.Key_Tab) return "TAB"
    if (key === Qt.Key_Escape) return "ESCAPE"
    if (key >= Qt.Key_A && key <= Qt.Key_Z) return String.fromCharCode(key)
    if (key >= Qt.Key_0 && key <= Qt.Key_9) return String.fromCharCode(key)
    return ""
  }

  function updateActiveKeys(event, pressed) {
    var next = {}
    for (var activeKey in activeKeys) {
      if (activeKeys[activeKey]) next[activeKey] = true
    }

    function setModifier(name, active) {
      if (active) next[name] = true
      else delete next[name]
    }

    setModifier("SUPER", Boolean(event.modifiers & Qt.MetaModifier))
    setModifier("ALT", Boolean(event.modifiers & Qt.AltModifier))
    setModifier("CTRL", Boolean(event.modifiers & Qt.ControlModifier))
    setModifier("SHIFT", Boolean(event.modifiers & Qt.ShiftModifier))

    var direct = keyName(event.key)
    if (pressed && direct) next[direct] = true
    else if (!pressed && direct) delete next[direct]
    else {
      var unsupported = "__KEY_" + event.key
      if (pressed) next[unsupported] = true
      else delete next[unsupported]
    }
    activeKeys = next
    if (pressed) Qt.callLater(checkExpectedCombo)
  }

  function clearActiveKeys() {
    activeKeys = {}
    comboTriggered = false
  }

  function checkExpectedCombo() {
    if (phase !== "waiting" || comboTriggered || !currentStep || !currentStep.help) return
    var keys = currentStep.keys || []
    if (keys.length === 0) return
    var expected = {}
    for (var i = 0; i < keys.length; i++) {
      var key = String(keys[i]).toUpperCase()
      if (key !== "+") expected[key] = true
    }
    var expectedCount = Object.keys(expected).length
    var activeCount = 0
    for (var activeKey in activeKeys) {
      if (!activeKeys[activeKey]) continue
      activeCount++
      if (expected[activeKey] !== true) return
    }
    if (activeCount !== expectedCount) return
    comboTriggered = true
    runStepAction()
  }

  function parseTheme(raw) {
    var next = {
      accent: root.accent,
      foreground: root.foreground,
      background: root.background,
      muted: root.muted,
      urgent: root.urgent,
      instruction: root.instruction
    }
    var foundInstruction = false
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var match = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (!match) continue
      if (match[1] === "accent") next.accent = match[2]
      else if (match[1] === "foreground") next.foreground = match[2]
      else if (match[1] === "background") next.background = match[2]
      else if (match[1] === "muted" || match[1] === "dark_foreground") next.muted = match[2]
      else if (match[1] === "red") next.urgent = match[2]
      else if (match[1] === "yellow") {
        next.instruction = match[2]
        foundInstruction = true
      }
    }
    if (!foundInstruction) next.instruction = next.accent
    root.accent = next.accent
    root.foreground = next.foreground
    root.background = next.background
    root.muted = next.muted
    root.urgent = next.urgent
    root.instruction = next.instruction
  }

  function fail(message) {
    stopAudio()
    actionCompletionTimer.stop()
    completionTimer.stop()
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
    if (!parsed || parsed.schemaVersion !== 2 || !Array.isArray(parsed.lessons) || parsed.lessons.length === 0) {
      fail("Course metadata is invalid. Run learn-omarchy-validate for details.")
      return
    }
    course = parsed
    lessonIndex = -1
    selectedLessonIndex = 0
    stepIndex = 0
    clearActiveKeys()
    errorMessage = ""
    phase = "menu"
    applyCourseProgress()
  }

  function applyCourseProgress() {
    var next = {}
    var ids = course && Array.isArray(progressByCourse[course.id]) ? progressByCourse[course.id] : []
    for (var i = 0; i < ids.length; i++) next[String(ids[i])] = true
    completedLessons = next
  }

  function loadProgress(raw) {
    var nextByCourse = {}
    try {
      var parsed = JSON.parse(String(raw || "{}"))
      if (parsed && parsed.schemaVersion === 2 && parsed.courses && typeof parsed.courses === "object") {
        for (var courseId in parsed.courses) {
          if (Array.isArray(parsed.courses[courseId])) {
            nextByCourse[courseId] = parsed.courses[courseId].map(function(id) { return String(id) })
          }
        }
      } else if (parsed && typeof parsed.courseId === "string" && Array.isArray(parsed.completedLessons)) {
        nextByCourse[parsed.courseId] = parsed.completedLessons.map(function(id) { return String(id) })
      }
    } catch (error) {
      console.warn("learn-omarchy: progress file couldn't be parsed:", error)
    }
    progressByCourse = nextByCourse
    applyCourseProgress()
  }

  function persistProgress() {
    var ids = []
    for (var id in completedLessons) {
      if (completedLessons[id]) ids.push(id)
    }
    var nextByCourse = {}
    for (var courseId in progressByCourse) {
      nextByCourse[courseId] = progressByCourse[courseId]
    }
    if (course) nextByCourse[course.id] = ids
    progressByCourse = nextByCourse
    progressFile.setText(JSON.stringify({
      schemaVersion: 2,
      courses: nextByCourse
    }, null, 2) + "\n")
  }

  function markCurrentLessonComplete() {
    if (!currentLesson) return
    var next = {}
    for (var id in completedLessons) next[id] = completedLessons[id]
    next[currentLesson.id] = true
    completedLessons = next
    persistProgress()
  }

  function startLesson(index) {
    if (!course || index < 0 || index >= course.lessons.length) return
    runCleanup()
    stopAudio()
    actionCompletionTimer.stop()
    completionTimer.stop()
    selectedLessonIndex = index
    lessonIndex = index
    stepIndex = 0
    errorMessage = ""
    startCurrentStep()
  }

  function startCurrentStep() {
    cancelAction()
    stopAudio()
    clearActiveKeys()
    phase = "waiting"
    Qt.callLater(playCurrentAudio)
  }

  function cancelAction() {
    actionGeneration++
    actionCompletionTimer.stop()
    actionRunning = false
    pendingStepAction = false
    pendingActionStepId = ""
    pendingActionGeneration = -1
    actionStepId = ""
    if (helpProcess.running) {
      actionStopping = true
      helpProcess.running = false
    }
  }

  function runCleanup() {
    if (currentStep && Array.isArray(currentStep.cleanup) && currentStep.cleanup.length > 0) {
      Quickshell.execDetached(currentStep.cleanup)
    }
  }

  function returnToMenu() {
    runCleanup()
    cancelAction()
    stopAudio()
    completionTimer.stop()
    clearActiveKeys()
    lessonIndex = -1
    stepIndex = 0
    phase = "menu"
  }

  function skipCurrentStep() {
    if (!currentLesson || !currentStep) return
    runCleanup()
    cancelAction()
    stopAudio()
    completionTimer.stop()
    if (stepIndex + 1 < currentLesson.steps.length) {
      stepIndex++
      startCurrentStep()
    } else {
      markCurrentLessonComplete()
      phase = "lesson-complete"
    }
  }

  function completeCurrentStep() {
    if (!currentStep || phase !== "waiting") return
    stopAudio()
    clearActiveKeys()
    phase = "highlight"
    remapGeneration++
    completionTimer.interval = Math.max(350, Number(currentStep.highlight.durationMs || 1800))
    completionTimer.restart()
  }

  function advance() {
    if (!currentLesson || !currentStep) return
    runCleanup()
    if (stepIndex + 1 < currentLesson.steps.length) {
      stepIndex++
      startCurrentStep()
      return
    }
    markCurrentLessonComplete()
    phase = "lesson-complete"
  }

  function currentAudioPath() {
    return currentStep && currentStep.audio ? courseDir + "/" + currentStep.audio : ""
  }

  function startAudioPath(path) {
    if (!audioEnabled || path === "" || path !== currentAudioPath()) return
    audioStopRequested = false
    pendingAudioPath = ""
    audioProcessPath = path
    audioProcess.command = [
      "mpv",
      "--no-video",
      "--really-quiet",
      "--",
      path
    ]
    audioProcess.running = true
  }

  function playCurrentAudio() {
    if (!audioEnabled) return
    var path = currentAudioPath()
    if (path === "") return
    if (audioProcess.running || audioStopRequested) {
      if (audioProcessPath === path && !audioStopRequested) return
      pendingAudioPath = path
      audioStopRequested = true
      if (audioProcess.running) audioProcess.running = false
      return
    }
    startAudioPath(path)
  }

  function stopAudio() {
    pendingAudioPath = ""
    if (audioProcess.running) {
      audioStopRequested = true
      audioProcess.running = false
    }
  }

  function toggleAudio() {
    audioEnabled = !audioEnabled
    if (audioEnabled) playCurrentAudio()
    else stopAudio()
  }

  function replayCurrentAudio() {
    if (!currentStep || !currentStep.audio) return
    audioEnabled = true
    pendingAudioPath = currentAudioPath()
    if (audioProcess.running || audioStopRequested) {
      audioStopRequested = true
      if (audioProcess.running) audioProcess.running = false
    } else {
      startAudioPath(pendingAudioPath)
    }
  }

  function runStepAction() {
    if (actionRunning || !currentStep || !currentStep.help || !Array.isArray(currentStep.help.command)) return
    if (actionStopping || helpProcess.running) {
      pendingStepAction = true
      pendingActionStepId = currentStep.id
      pendingActionGeneration = actionGeneration
      return
    }
    pendingStepAction = false
    pendingActionStepId = ""
    pendingActionGeneration = -1
    actionGeneration++
    actionProcessGeneration = actionGeneration
    actionRunning = true
    actionStepId = currentStep.id
    actionCompletionType = currentStep.completion.type
    actionCompletionDelay = Number(currentStep.completion.delayMs || 250)
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

  function moveMenuSelection(delta) {
    if (!course) return
    selectedLessonIndex = Math.max(0, Math.min(course.lessons.length - 1, selectedLessonIndex + delta))
  }

  function handleKeyPressed(event) {
    if (phase === "menu") {
      if (event.key === Qt.Key_Left) moveMenuSelection(-1)
      else if (event.key === Qt.Key_Right) moveMenuSelection(1)
      else if (event.key === Qt.Key_Up) moveMenuSelection(-2)
      else if (event.key === Qt.Key_Down) moveMenuSelection(2)
      else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) startLesson(selectedLessonIndex)
      else if (event.key === Qt.Key_Escape) Qt.quit()
      else return
      event.accepted = true
      return
    }
    if (phase === "lesson-complete") {
      if (event.key === Qt.Key_R) startLesson(lessonIndex)
      else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Escape) returnToMenu()
      else return
      event.accepted = true
      return
    }
    if (phase === "error") {
      if (event.key === Qt.Key_Escape) returnToMenu()
      event.accepted = true
      return
    }
    if (phase === "waiting") {
      if (event.key === Qt.Key_Escape) {
        returnToMenu()
        event.accepted = true
        return
      }
      if (
        currentStep &&
        currentStep.keys.length === 0 &&
        (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
      ) {
        runStepAction()
        event.accepted = true
        return
      }
      updateActiveKeys(event, true)
      event.accepted = false
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
    id: progressFile
    path: root.progressPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadProgress(text())
    onFileChanged: reload()
    onLoadFailed: root.completedLessons = ({})
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
    function onRawEvent(event) { root.handleHyprlandEvent(event) }
  }

  IpcHandler {
    target: "learn"

    function status(): string {
      return JSON.stringify({
        phase: root.phase,
        lessonIndex: root.lessonIndex,
        stepIndex: root.stepIndex,
        lessonId: root.currentLesson ? root.currentLesson.id : "",
        stepId: root.currentStep ? root.currentStep.id : "",
        keyboardFocused: root.keyboardFocused
      })
    }

    function start(index: string): string {
      var parsed = Number(index)
      if (!isFinite(parsed)) return "invalid-index"
      root.startLesson(Math.floor(parsed))
      return "ok"
    }

    function activate(): string {
      if (root.phase !== "waiting" || !root.currentStep) return "not-waiting"
      root.runStepAction()
      return "ok"
    }
  }

  Process {
    id: audioProcess
    onExited: function(exitCode) {
      var stopped = root.audioStopRequested
      var finishedPath = root.audioProcessPath
      var queuedPath = root.pendingAudioPath
      root.audioStopRequested = false
      root.audioProcessPath = ""
      root.pendingAudioPath = ""
      if (stopped) {
        if (queuedPath !== "" && root.audioEnabled && queuedPath === root.currentAudioPath()) {
          Qt.callLater(function() { root.startAudioPath(queuedPath) })
        }
        return
      }
      if (
        exitCode !== 0 &&
        root.phase === "waiting" &&
        root.audioEnabled &&
        finishedPath === root.currentAudioPath()
      ) {
        root.fail("Narration couldn't be played. Check the audio file and mpv installation.")
      }
    }
  }

  Process {
    id: helpProcess
    onExited: function(exitCode) {
      root.actionStopping = false
      if (root.actionProcessGeneration !== root.actionGeneration) {
        if (root.pendingStepAction && root.phase === "waiting" && root.currentStep) {
          var pendingStepId = root.pendingActionStepId
          var pendingGeneration = root.pendingActionGeneration
          root.pendingStepAction = false
          root.pendingActionStepId = ""
          root.pendingActionGeneration = -1
          Qt.callLater(function() {
            if (
              root.phase === "waiting" &&
              root.currentStep &&
              root.currentStep.id === pendingStepId &&
              root.actionGeneration === pendingGeneration
            ) {
              root.runStepAction()
            }
          })
        }
        return
      }
      root.actionRunning = false
      if (
        exitCode !== 0 &&
        root.phase === "waiting" &&
        root.currentStep &&
        root.currentStep.id === root.actionStepId
      ) {
        root.fail("The guided action failed with exit code " + exitCode + ".")
        return
      }
      if (
        root.phase === "waiting" &&
        root.currentStep &&
        root.currentStep.id === root.actionStepId &&
        root.actionCompletionType === "action-success"
      ) {
        actionCompletionTimer.interval = Math.max(100, root.actionCompletionDelay)
        actionCompletionTimer.restart()
      }
    }
  }

  Timer {
    id: actionCompletionTimer
    repeat: false
    onTriggered: root.completeCurrentStep()
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
      readonly property bool capturesKeyboard:
        root.phase === "menu" || root.phase === "waiting" || root.phase === "lesson-complete" || root.phase === "error"
      readonly property real fittedHighlightWidth: {
        if (!highlight) return 0
        if (highlight.shape === "circle") {
          return Math.max(0, Math.min(highlight.width, width - 20, height - 20))
        }
        return Math.max(0, Math.min(highlight.width, width - 20))
      }
      readonly property real fittedHighlightHeight: {
        if (!highlight) return 0
        if (highlight.shape === "circle") return fittedHighlightWidth
        return Math.max(0, Math.min(highlight.height, height - 20))
      }

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
      WlrLayershell.keyboardFocus: capturesKeyboard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
      mask: Region {
        Region { item: topicPanel }
        Region { item: lessonNavigation }
        Region { item: controls }
        Region { item: replayButton }
        Region { item: actionButton }
        Region { item: completionPanel }
        Region { item: errorPanel }
      }

      function anchoredX(anchor, itemWidth, offset) {
        var value
        if (anchor.indexOf("left") !== -1 || anchor === "left") value = offset
        else if (anchor.indexOf("right") !== -1 || anchor === "right") value = width - itemWidth + offset
        else value = Math.round((width - itemWidth) / 2) + offset
        return Math.max(10, Math.min(width - itemWidth - 10, value))
      }

      function anchoredY(anchor, itemHeight, offset) {
        var value
        if (anchor.indexOf("top") !== -1 || anchor === "top") value = offset
        else if (anchor.indexOf("bottom") !== -1 || anchor === "bottom") value = height - itemHeight + offset
        else value = Math.round((height - itemHeight) / 2) + offset
        return Math.max(10, Math.min(height - itemHeight - 10, value))
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
        onTriggered: {
          overlay.mapped = true
          if (overlay.capturesKeyboard) Qt.callLater(function() { keyCatcher.forceActiveFocus() })
        }
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        onActiveFocusChanged: root.keyboardFocused = activeFocus

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) { root.handleKeyPressed(event) }
        Keys.onReleased: function(event) {
          if (root.phase === "waiting") {
            root.updateActiveKeys(event, false)
            event.accepted = false
          }
        }

        Connections {
          target: root
          function onPhaseChanged() {
            if (overlay.capturesKeyboard) Qt.callLater(function() { keyCatcher.forceActiveFocus() })
          }
        }

        Component.onCompleted: {
          if (overlay.capturesKeyboard) Qt.callLater(function() { keyCatcher.forceActiveFocus() })
        }
      }

      Rectangle {
        anchors.fill: parent
        visible: root.phase === "menu" || root.phase === "lesson-complete" || root.phase === "error"
        color: root.colorWithAlpha(root.background, 0.72)
      }

      Rectangle {
        id: highlightFrame
        visible: root.phase === "highlight" && overlay.highlight
        width: overlay.fittedHighlightWidth
        height: overlay.fittedHighlightHeight
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

      Rectangle {
        id: topicPanel
        visible: root.phase === "menu" && root.course
        anchors.centerIn: parent
        width: Math.min(980, parent.width - 64)
        height: Math.min(850, parent.height - 64)
        color: root.background
        border.color: root.accent
        border.width: 2
        radius: 18

        ColumnLayout {
          anchors {
            fill: parent
            margins: 28
          }
          spacing: 12

          RowLayout {
            Layout.fillWidth: true

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 4

              Text {
                text: root.course ? root.course.title : ""
                color: root.instruction
                font.family: "sans-serif"
                font.pixelSize: 30
                font.weight: Font.Bold
              }
              Text {
                Layout.maximumWidth: topicPanel.width - 150
                text: root.course ? root.course.description : ""
                color: root.foreground
                opacity: 0.82
                font.family: "sans-serif"
                font.pixelSize: 15
                wrapMode: Text.WordWrap
              }
            }

            Rectangle {
              implicitWidth: progressText.implicitWidth + 24
              implicitHeight: 36
              color: root.colorWithAlpha(root.accent, 0.18)
              border.color: root.accent
              border.width: 1
              radius: 18

              Text {
                id: progressText
                anchors.centerIn: parent
                text: root.completedCount + " / " + (root.course ? root.course.lessons.length : 0) + " complete"
                color: root.foreground
                font.family: "sans-serif"
                font.pixelSize: 13
                font.weight: Font.DemiBold
              }
            }
          }

          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: root.colorWithAlpha(root.foreground, 0.18)
          }

          GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 2
            columnSpacing: 14
            rowSpacing: 14

            Repeater {
              model: root.course ? root.course.lessons : []

              Rectangle {
                id: lessonCard
                required property int index
                required property var modelData
                readonly property bool selected: index === root.selectedLessonIndex
                readonly property bool completed: root.completedLessons[modelData.id] === true

                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 105
                color: cardMouse.containsMouse || selected
                  ? root.colorWithAlpha(root.accent, 0.18)
                  : root.colorWithAlpha(root.foreground, 0.045)
                border.color: selected ? root.accent : root.colorWithAlpha(root.foreground, 0.22)
                border.width: selected ? 2 : 1
                radius: 12

                RowLayout {
                  anchors {
                    fill: parent
                    margins: 16
                  }
                  spacing: 14

                  Rectangle {
                    implicitWidth: 48
                    implicitHeight: 48
                    color: lessonCard.completed ? root.accent : root.colorWithAlpha(root.accent, 0.16)
                    border.color: root.accent
                    border.width: 1
                    radius: 24

                    Text {
                      anchors.centerIn: parent
                      text: lessonCard.completed ? "✓" : lessonCard.modelData.icon
                      color: lessonCard.completed ? root.background : root.foreground
                      font.family: "monospace"
                      font.pixelSize: 16
                      font.weight: Font.Bold
                    }
                  }

                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                      Layout.fillWidth: true
                      text: lessonCard.modelData.title
                      color: lessonCard.selected ? root.instruction : root.foreground
                      font.family: "sans-serif"
                      font.pixelSize: 17
                      font.weight: Font.Bold
                      elide: Text.ElideRight
                    }
                    Text {
                      Layout.fillWidth: true
                      text: lessonCard.modelData.description
                      color: root.foreground
                      opacity: 0.72
                      font.family: "sans-serif"
                      font.pixelSize: 12
                      wrapMode: Text.WordWrap
                      maximumLineCount: 2
                      elide: Text.ElideRight
                    }
                    Text {
                      text: lessonCard.modelData.estimatedMinutes + " min  ·  " + lessonCard.modelData.steps.length + " activities"
                      color: root.muted
                      font.family: "sans-serif"
                      font.pixelSize: 11
                    }
                  }
                }

                MouseArea {
                  id: cardMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: root.selectedLessonIndex = lessonCard.index
                  onClicked: root.startLesson(lessonCard.index)
                }
              }
            }

          }

          Text {
            Layout.alignment: Qt.AlignHCenter
            text: "Arrow keys choose  ·  Enter starts  ·  Escape closes"
            color: root.muted
            font.family: "sans-serif"
            font.pixelSize: 12
          }
        }
      }

      RowLayout {
        id: lessonNavigation
        visible: root.phase === "waiting" || root.phase === "highlight"
        anchors {
          top: parent.top
          left: parent.left
          topMargin: 42
          leftMargin: 24
        }
        spacing: 10

        Rectangle {
          implicitWidth: topicsLabel.implicitWidth + 24
          implicitHeight: 42
          color: topicsMouse.containsMouse
            ? root.colorWithAlpha(root.accent, 0.32)
            : root.background
          border.color: root.accent
          border.width: 1
          radius: 21

          Text {
            id: topicsLabel
            anchors.centerIn: parent
            text: "← Topics"
            color: root.foreground
            font.family: "sans-serif"
            font.pixelSize: 14
            font.weight: Font.DemiBold
          }

          MouseArea {
            id: topicsMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.returnToMenu()
          }
        }

        Rectangle {
          implicitWidth: lessonStatus.implicitWidth + 24
          implicitHeight: 42
          color: root.background
          border.color: root.colorWithAlpha(root.foreground, 0.3)
          border.width: 1
          radius: 21

          Text {
            id: lessonStatus
            anchors.centerIn: parent
            text: root.currentLesson
              ? root.currentLesson.title + "  ·  " + (root.stepIndex + 1) + " / " + root.currentLesson.steps.length
              : ""
            color: root.foreground
            font.family: "sans-serif"
            font.pixelSize: 13
          }
        }

        Rectangle {
          visible: root.phase === "waiting"
          implicitWidth: skipLabel.implicitWidth + 24
          implicitHeight: 42
          color: skipMouse.containsMouse
            ? root.colorWithAlpha(root.foreground, 0.14)
            : root.background
          border.color: root.muted
          border.width: 1
          radius: 21

          Text {
            id: skipLabel
            anchors.centerIn: parent
            text: "Skip"
            color: root.foreground
            opacity: 0.8
            font.family: "sans-serif"
            font.pixelSize: 13
          }

          MouseArea {
            id: skipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.skipCurrentStep()
          }
        }
      }

      ColumnLayout {
        id: teachingContent
        visible: root.phase === "waiting" || root.phase === "highlight"
        anchors {
          horizontalCenter: parent.horizontalCenter
          bottom: parent.bottom
          bottomMargin: 42
        }
        spacing: 12

        Rectangle {
          Layout.alignment: Qt.AlignHCenter
          Layout.preferredWidth: Math.min(820, overlay.width - 48)
          Layout.preferredHeight: messageColumn.implicitHeight + 28
          color: root.background
          border.color: root.accent
          border.width: 2
          radius: 12

          ColumnLayout {
            id: messageColumn
            anchors {
              left: parent.left
              right: replayButton.visible ? replayButton.left : parent.right
              verticalCenter: parent.verticalCenter
              leftMargin: 22
              rightMargin: replayButton.visible ? 14 : 22
            }
            spacing: 5

            Text {
              Layout.fillWidth: true
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              color: root.phase === "waiting" ? root.instruction : root.foreground
              font.family: "sans-serif"
              font.pixelSize: 19
              font.weight: Font.Bold
              text: {
                if (root.phase === "highlight" && root.currentStep && root.currentStep.completionMessage)
                  return root.currentStep.completionMessage
                return root.currentStep ? root.currentStep.instruction : ""
              }
            }

            Text {
              visible: Boolean(root.phase === "waiting" && root.currentStep && root.currentStep.detail)
              Layout.fillWidth: true
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              color: root.foreground
              opacity: 0.72
              font.family: "sans-serif"
              font.pixelSize: 13
              text: root.currentStep ? root.currentStep.detail || "" : ""
            }
          }

          Rectangle {
            id: replayButton
            visible: Boolean(root.phase === "waiting" && root.currentStep && root.currentStep.audio)
            anchors {
              right: parent.right
              verticalCenter: parent.verticalCenter
              rightMargin: 12
            }
            width: 38
            height: 38
            color: replayMouse.containsMouse
              ? root.colorWithAlpha(root.accent, 0.4)
              : root.colorWithAlpha(root.accent, 0.18)
            border.color: root.accent
            border.width: 1
            radius: 19

            Text {
              anchors.centerIn: parent
              text: "▶"
              color: root.foreground
              font.family: "sans-serif"
              font.pixelSize: 16
            }

            MouseArea {
              id: replayMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.replayCurrentAudio()
            }
          }
        }

        RowLayout {
          visible: Boolean(root.phase === "waiting" && root.currentStep && root.currentStep.keys.length > 0)
          Layout.alignment: Qt.AlignHCenter
          spacing: 16

          Repeater {
            model: root.currentStep ? root.currentStep.keys : []

            Rectangle {
              required property string modelData
              readonly property string normalizedKey: modelData.toUpperCase()
              readonly property bool keyActive: normalizedKey !== "+" && root.activeKeys[normalizedKey] === true
              implicitWidth: keyLabel.implicitWidth + (normalizedKey === "+" ? 24 : 36)
              implicitHeight: 54
              scale: keyActive ? 1.08 : 1
              color: keyActive ? root.accent : root.background
              border.color: keyActive ? root.foreground : (normalizedKey === "+" ? root.muted : root.accent)
              border.width: keyActive ? 3 : (normalizedKey === "+" ? 1 : 2)
              radius: 8

              Behavior on scale {
                NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
              }
              Behavior on color { ColorAnimation { duration: 90 } }

              Text {
                id: keyLabel
                anchors.centerIn: parent
                text: normalizedKey
                textFormat: Text.PlainText
                color: keyActive ? root.background : root.foreground
                font.family: "monospace"
                font.pixelSize: normalizedKey === "+" ? 19 : 18
                font.weight: Font.Bold
              }
            }
          }
        }

        Rectangle {
          id: actionButton
          visible: Boolean(root.phase === "waiting" && root.currentStep && root.currentStep.keys.length === 0)
          Layout.alignment: Qt.AlignHCenter
          implicitWidth: actionLabelText.implicitWidth + 42
          implicitHeight: 52
          color: actionMouse.containsMouse ? root.accent : root.colorWithAlpha(root.accent, 0.24)
          border.color: root.accent
          border.width: 2
          radius: 10

          Text {
            id: actionLabelText
            anchors.centerIn: parent
            text: root.currentStep ? root.currentStep.actionLabel || "Continue" : ""
            color: actionMouse.containsMouse ? root.background : root.foreground
            font.family: "sans-serif"
            font.pixelSize: 16
            font.weight: Font.Bold
          }

          MouseArea {
            id: actionMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.runStepAction()
          }
        }
      }

      RowLayout {
        id: controls
        visible: root.phase === "waiting" || root.phase === "highlight"
        anchors {
          top: parent.top
          right: parent.right
          topMargin: 42
          rightMargin: 24
        }
        spacing: 8

        Rectangle {
          visible: Boolean(root.currentStep && root.currentStep.audio)
          implicitWidth: 42
          implicitHeight: 42
          color: audioMouse.containsMouse ? root.colorWithAlpha(root.accent, 0.34) : root.background
          border.color: root.audioEnabled ? root.accent : root.muted
          border.width: root.audioEnabled ? 2 : 1
          radius: 21

          Text {
            anchors.centerIn: parent
            text: root.audioEnabled ? "🔊" : "🔇"
            color: root.foreground
            font.family: "sans-serif"
            font.pixelSize: 18
          }

          MouseArea {
            id: audioMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleAudio()
          }
        }

        Rectangle {
          visible: Boolean(root.phase === "waiting" && root.currentStep && root.currentStep.help)
          implicitWidth: helpRow.implicitWidth + 24
          implicitHeight: 42
          color: helpMouse.containsMouse ? root.colorWithAlpha(root.accent, 0.34) : root.background
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
            onClicked: root.runStepAction()
          }
        }

        Rectangle {
          implicitWidth: 42
          implicitHeight: 42
          color: closeMouse.containsMouse ? root.colorWithAlpha(root.urgent, 0.3) : root.background
          border.color: closeMouse.containsMouse ? root.urgent : root.muted
          border.width: 1
          radius: 21

          Text {
            anchors.centerIn: parent
            text: "X"
            color: root.foreground
            font.family: "sans-serif"
            font.pixelSize: 17
            font.weight: Font.Bold
          }

          MouseArea {
            id: closeMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.runCleanup()
              root.stopAudio()
              Qt.quit()
            }
          }
        }
      }

      Rectangle {
        id: completionPanel
        visible: root.phase === "lesson-complete" && root.currentLesson
        anchors.centerIn: parent
        width: Math.min(620, parent.width - 48)
        height: completionColumn.implicitHeight + 56
        color: root.background
        border.color: root.accent
        border.width: 2
        radius: 18

        ColumnLayout {
          id: completionColumn
          anchors.centerIn: parent
          width: parent.width - 56
          spacing: 14

          Text {
            Layout.alignment: Qt.AlignHCenter
            text: "✓"
            color: root.accent
            font.family: "sans-serif"
            font.pixelSize: 42
            font.weight: Font.Bold
          }
          Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.currentLesson ? root.currentLesson.title + " complete" : "Module complete"
            color: root.instruction
            font.family: "sans-serif"
            font.pixelSize: 26
            font.weight: Font.Bold
          }
          Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: "Nice work. Choose another topic or replay this module whenever you want."
            color: root.foreground
            opacity: 0.8
            wrapMode: Text.WordWrap
            font.family: "sans-serif"
            font.pixelSize: 14
          }
          RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 12

            Rectangle {
              implicitWidth: topicsCompleteLabel.implicitWidth + 30
              implicitHeight: 46
              color: completeTopicsMouse.containsMouse ? root.accent : root.colorWithAlpha(root.accent, 0.22)
              border.color: root.accent
              border.width: 2
              radius: 10

              Text {
                id: topicsCompleteLabel
                anchors.centerIn: parent
                text: "Choose another topic"
                color: completeTopicsMouse.containsMouse ? root.background : root.foreground
                font.family: "sans-serif"
                font.pixelSize: 14
                font.weight: Font.Bold
              }
              MouseArea {
                id: completeTopicsMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.returnToMenu()
              }
            }

            Rectangle {
              implicitWidth: replayLessonLabel.implicitWidth + 30
              implicitHeight: 46
              color: replayLessonMouse.containsMouse
                ? root.colorWithAlpha(root.foreground, 0.14)
                : root.background
              border.color: root.muted
              border.width: 1
              radius: 10

              Text {
                id: replayLessonLabel
                anchors.centerIn: parent
                text: "Replay module"
                color: root.foreground
                font.family: "sans-serif"
                font.pixelSize: 14
              }
              MouseArea {
                id: replayLessonMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.startLesson(root.lessonIndex)
              }
            }
          }
        }
      }

      Rectangle {
        id: errorPanel
        visible: root.phase === "error"
        anchors.centerIn: parent
        width: Math.min(660, parent.width - 48)
        height: errorColumn.implicitHeight + 56
        color: root.background
        border.color: root.urgent
        border.width: 2
        radius: 16

        ColumnLayout {
          id: errorColumn
          anchors.centerIn: parent
          width: parent.width - 56
          spacing: 14

          Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: "Something needs attention"
            color: root.urgent
            font.family: "sans-serif"
            font.pixelSize: 22
            font.weight: Font.Bold
          }
          Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.errorMessage
            textFormat: Text.PlainText
            color: root.foreground
            font.family: "sans-serif"
            font.pixelSize: 14
            wrapMode: Text.WordWrap
          }
          Text {
            Layout.alignment: Qt.AlignHCenter
            text: "Press Escape to return to topics"
            color: root.muted
            font.family: "sans-serif"
            font.pixelSize: 12
          }
        }
      }
    }
  }
}
