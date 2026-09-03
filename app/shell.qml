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
  readonly property string characterAssetRoot: appRoot + "/assets/characters/hexon"
  readonly property string progressPath: stateHome + "/learn-omarchy/progress.json"
  readonly property string themePath: stateHome + "/omarchy/current/theme"
  readonly property string themeNamePath: stateHome + "/omarchy/current/theme.name"
  readonly property bool reducedMotion:
    Quickshell.env("LEARN_OMARCHY_REDUCED_MOTION") === "1"

  property var course: null
  property int lessonIndex: -1
  property int selectedLessonIndex: 0
  property int characterMenuColumn: 0
  property int stepIndex: 0
  property string phase: "loading"
  property string errorMessage: ""
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
  property bool pendingAudioPreserveCharacterState: false
  property string characterState: "hidden"
  property string characterMessage: ""
  property int characterCue: 0
  property real lessonContentOpacity: 1
  property bool lessonTransitionRunning: false
  property string pendingLessonTransition: ""
  property int pendingTransitionStepIndex: -1
  property int workspaceStartId: -1
  property int workspaceCheckAttempts: 0
  property var targetWindowGeometry: null
  property var targetMonitorGeometry: null
  property bool windowGeometryPending: false
  property string targetWindowAddress: ""
  property int windowGeometryGeneration: 0
  property int windowGeometryAttempts: 0
  property string stepStartWindowAddress: ""
  property real shortcutArmedUntil: 0
  property real characterX: 0
  property real characterY: 0

  readonly property int windowGeometryMaxAttempts: 6
  readonly property int shortcutArmWindowMs: 8000
  readonly property int helpArmWindowMs: 10000

  readonly property int characterTravelDuration: reducedMotion ? 0 : 1050
  readonly property int characterPoseFadeDuration: reducedMotion ? 0 : 420

  property color accent: "#7aa2f7"
  property color foreground: "#a9b1d6"
  property color background: "#1a1b26"
  property color muted: "#565f89"
  property color urgent: "#f7768e"
  property color instruction: "#e0af68"

  onSelectedLessonIndexChanged: {
    var nextColumn = selectedLessonIndex % 2
    var crossesColumn = nextColumn !== characterMenuColumn
    characterMenuColumn = nextColumn
    if (phase !== "menu" || !course) return
    characterMenuPointTimer.stop()
    if (reducedMotion || !crossesColumn) {
      setCharacterState("menu-point", "CHOOSE A LESSON")
    } else {
      setCharacterState("menu-fly", "MOVING OVER!")
      characterMenuPointTimer.restart()
    }
  }

  readonly property var currentLesson: course && lessonIndex >= 0 ? course.lessons[lessonIndex] : null
  readonly property var currentStep: currentLesson ? currentLesson.steps[stepIndex] : null
  readonly property bool currentStepIsTour: Boolean(currentStep && currentStep.kind === "tour")
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

  function setCharacterState(state, message) {
    characterState = state
    characterMessage = message || ""
    characterCue++
  }

  function beginLessonTransition(kind, nextStepIndex) {
    if (lessonTransitionRunning) return
    pendingLessonTransition = kind
    pendingTransitionStepIndex = nextStepIndex === undefined ? -1 : nextStepIndex
    if (reducedMotion) {
      applyLessonTransition()
      lessonContentOpacity = 1
      return
    }
    lessonTransitionRunning = true
    lessonTransitionAnimation.restart()
  }

  function applyLessonTransition() {
    var kind = pendingLessonTransition
    var nextStepIndex = pendingTransitionStepIndex
    pendingLessonTransition = ""
    pendingTransitionStepIndex = -1

    if (kind === "highlight") {
      phase = "highlight"
      setCharacterState("celebrate", "NICE WORK!")
      characterTargetFlyTimer.restart()
      completionTimer.interval = Math.max(2600, Number(currentStep.highlight.durationMs || 1800))
      completionTimer.restart()
      return
    }

    if (kind === "step") {
      runCleanup()
      stepIndex = nextStepIndex
      startCurrentStep()
      return
    }

    if (kind === "lesson-complete") {
      runCleanup()
      markCurrentLessonComplete()
      phase = "lesson-complete"
      if (reducedMotion) {
        setCharacterState("celebrate", "MODULE COMPLETE!")
      } else {
        setCharacterState("module-fly", "GREAT WORK!")
        characterModuleArrivalTimer.restart()
      }
    }
  }

  function barWorkspaceCount() {
    var ids = { 1: true, 2: true, 3: true, 4: true, 5: true }
    var values = Hyprland.workspaces ? Hyprland.workspaces.values : []
    for (var i = 0; i < values.length; i++) {
      var id = Number(values[i].id)
      if (id > 0 && id <= 10) ids[id] = true
    }
    return Object.keys(ids).length
  }

  function currentWorkspaceId() {
    return Hyprland.focusedWorkspace ? Number(Hyprland.focusedWorkspace.id) : -1
  }

  function captureWorkspaceStart() {
    workspaceCheckAttempts = 0
    workspaceStartId = currentStep &&
      currentStep.completion &&
      currentStep.completion.type === "hyprland-workspace-change"
        ? currentWorkspaceId()
        : -1
  }

  function checkWorkspaceCompletion() {
    if (
      phase !== "waiting" ||
      !currentStep ||
      currentStep.completion.type !== "hyprland-workspace-change" ||
      workspaceStartId < 0
    ) return
    var activeWorkspaceId = currentWorkspaceId()
    if (activeWorkspaceId >= 0 && activeWorkspaceId !== workspaceStartId) {
      completeCurrentStep()
      return
    }
    workspaceCheckAttempts++
    if (workspaceCheckAttempts < 5) workspaceCompletionTimer.restart()
  }

  function expectedKeyMap() {
    var expected = {}
    if (!currentStep || !Array.isArray(currentStep.keys)) return expected
    for (var i = 0; i < currentStep.keys.length; i++) {
      var key = String(currentStep.keys[i]).toUpperCase()
      if (key !== "+") expected[key] = true
    }
    return expected
  }

  function lessonShortcutLabel(lesson) {
    if (!lesson || !lesson.steps) return "GUIDED ACTIONS"
    for (var i = 0; i < lesson.steps.length; i++) {
      var keys = lesson.steps[i].keys
      if (keys && keys.length > 0) {
        var labels = []
        for (var keyIndex = 0; keyIndex < keys.length; keyIndex++) labels.push(keys[keyIndex])
        return labels.join(" ")
      }
    }
    return "GUIDED ACTIONS"
  }

  function reactToKey(key) {
    if (phase !== "waiting" || !currentStep || currentStep.keys.length === 0) return
    characterHelpPointTimer.stop()
    characterHelpActionTimer.stop()
    var expected = expectedKeyMap()
    if (key && expected[key] === true) {
      setCharacterState("correct", key + " - NICE!")
      characterReactionTimer.interval = 320
    } else {
      setCharacterState("incorrect", "TRY THE HIGHLIGHTED KEYS")
      characterReactionTimer.interval = 680
    }
    characterReactionTimer.restart()
  }

  function startCharacterStep() {
    if (currentStepIsTour) {
      if (reducedMotion) {
        setCharacterState("tour-point", "LOOK HERE")
        Qt.callLater(beginTourNarration)
      } else {
        setCharacterState("tour-fly", "FOLLOW ME")
        characterTourArrivalTimer.restart()
      }
      return
    }
    if (reducedMotion) {
      setCharacterState("coach", "YOUR TURN")
      Qt.callLater(playCurrentAudio)
    } else {
      setCharacterState("step-fly", "ON MY WAY!")
      characterStepArrivalTimer.restart()
    }
  }

  function tourFallbackDuration() {
    var completion = currentStep ? currentStep.completion : null
    return Math.max(1500, Number(completion && completion.durationMs || 5000))
  }

  function tourAdvanceDelay() {
    var completion = currentStep ? currentStep.completion : null
    return Math.max(100, Number(completion && completion.delayMs || 900))
  }

  function beginTourNarration() {
    if (phase !== "waiting" || !currentStepIsTour) return
    if (audioEnabled && currentAudioPath() !== "") {
      playCurrentAudio(true)
      return
    }
    tourAdvanceTimer.interval = tourFallbackDuration()
    tourAdvanceTimer.restart()
  }

  function scheduleTourAdvance() {
    if (phase !== "waiting" || !currentStepIsTour) return
    tourAdvanceTimer.interval = tourAdvanceDelay()
    tourAdvanceTimer.restart()
  }

  function settleCharacter() {
    if (audioProcess.running && !audioStopRequested) {
      setCharacterState("talk", "LISTENING...")
    } else {
      setCharacterState("coach", "YOUR TURN")
    }
  }

  function keyName(key) {
    if (key === Qt.Key_Meta || key === Qt.Key_Super_L || key === Qt.Key_Super_R) return "SUPER"
    if (key === Qt.Key_Alt || key === Qt.Key_AltGr) return "ALT"
    if (key === Qt.Key_Control) return "CTRL"
    if (key === Qt.Key_Shift) return "SHIFT"
    if (key === Qt.Key_Space) return "SPACE"
    if (key === Qt.Key_Return || key === Qt.Key_Enter) return "RETURN"
    if (key === Qt.Key_Tab || key === Qt.Key_Backtab) return "TAB"
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
    if (pressed) {
      armShortcutDetection(next)
      if (!event.isAutoRepeat) reactToKey(direct)
      Qt.callLater(checkExpectedCombo)
    }
  }

  function usesWindowActivation() {
    return Boolean(
      currentStep &&
      currentStep.completion &&
      currentStep.completion.type === "hyprland-window-activated"
    )
  }

  function armShortcutDetection(keys) {
    if (phase !== "waiting" || !usesWindowActivation()) return
    var expected = expectedKeyMap()
    var matched = 0
    for (var key in keys) {
      if (!keys[key]) continue
      if (expected[key] !== true) return
      matched++
    }
    if (matched === 0) return
    shortcutArmedUntil = Date.now() + shortcutArmWindowMs
  }

  function armHelpDetection() {
    if (!usesWindowActivation()) return
    shortcutArmedUntil = Math.max(shortcutArmedUntil, Date.now() + helpArmWindowMs)
  }

  function windowDetectionArmed() {
    if (!usesWindowActivation()) return false
    if (actionRunning && currentStep && actionStepId === currentStep.id) return true
    return Date.now() <= shortcutArmedUntil
  }

  function clearActiveKeys() {
    activeKeys = {}
    comboTriggered = false
  }

  function confirmDetectedShortcut() {
    var expected = expectedKeyMap()
    var confirmed = {}
    for (var key in expected) confirmed[key] = true
    activeKeys = confirmed
    comboTriggered = true
    setCharacterState("celebrate", "NICE WORK!")
    layerCompletionFeedbackTimer.restart()
  }

  function normalizedWindowAddress(value) {
    var address = String(value || "").trim()
    if (address === "") return ""
    return address.indexOf("0x") === 0 ? address : "0x" + address
  }

  function resetWindowTarget() {
    windowGeometryGeneration++
    windowGeometryAttempts = 0
    windowGeometryPending = false
    windowGeometryRetryTimer.stop()
    windowGeometryRefreshTimer.stop()
    windowGeometryRefreshTimer.refreshing = false
    windowActivationHintTimer.stop()
    targetWindowGeometry = null
    targetMonitorGeometry = null
    targetWindowAddress = ""
    stepStartWindowAddress = ""
    shortcutArmedUntil = 0
  }

  function captureStepStartWindow() {
    if (!usesWindowActivation()) return
    stepStartWindowProcess.requestGeneration = windowGeometryGeneration
    if (!stepStartWindowProcess.running) stepStartWindowProcess.running = true
  }

  function parseStepStartWindow(raw, generation) {
    if (generation !== windowGeometryGeneration) return
    try {
      var parsed = JSON.parse(String(raw || "{}"))
      stepStartWindowAddress = normalizedWindowAddress(parsed && parsed.address)
    } catch (error) {
      console.warn("learn-omarchy: couldn't read the active window at step start:", error)
      stepStartWindowAddress = ""
    }
  }

  function requestWindowGeometry(address) {
    if (windowGeometryPending || targetWindowGeometry) return
    windowGeometryGeneration++
    windowGeometryAttempts = 0
    windowGeometryPending = true
    targetWindowAddress = address
    targetWindowGeometry = null
    targetMonitorGeometry = null
    windowGeometryRefreshTimer.stop()
    queryWindowGeometry()
  }

  function queryWindowGeometry() {
    if (!windowGeometryPending) return
    if (clientGeometryProcess.running || monitorGeometryProcess.running) {
      windowGeometryRetryTimer.restart()
      return
    }
    clientGeometryProcess.requestGeneration = windowGeometryGeneration
    clientGeometryProcess.running = true
  }

  function retryWindowGeometry(reason) {
    windowGeometryAttempts++
    if (windowGeometryAttempts < windowGeometryMaxAttempts) {
      windowGeometryRetryTimer.restart()
      return
    }
    console.warn("learn-omarchy: window geometry for", targetWindowAddress, "unavailable (" + reason + "); using the configured target estimate")
    finishWindowDetection(null, null)
  }

  function finishWindowDetection(windowData, monitorData) {
    windowGeometryPending = false
    windowGeometryRetryTimer.stop()
    targetWindowGeometry = windowData
    targetMonitorGeometry = monitorData
    windowActivationHintTimer.stop()
    if (windowData && monitorData) windowGeometryRefreshTimer.restart()
    confirmDetectedShortcut()
  }

  function findClientByAddress(raw) {
    var parsed = JSON.parse(String(raw || "[]"))
    if (!Array.isArray(parsed)) throw new Error("clients response wasn't a list")
    for (var i = 0; i < parsed.length; i++) {
      if (normalizedWindowAddress(parsed[i].address) === targetWindowAddress) return parsed[i]
    }
    return null
  }

  function clientGeometryReady(windowData) {
    if (!windowData) return false
    if (!Array.isArray(windowData.at) || !Array.isArray(windowData.size)) return false
    if (windowData.mapped === false || windowData.hidden === true) return false
    if (Number(windowData.size[0]) <= 0 || Number(windowData.size[1]) <= 0) return false
    return true
  }

  function parseClientGeometry(raw, generation) {
    var wasRefresh = windowGeometryRefreshTimer.refreshing
    windowGeometryRefreshTimer.refreshing = false
    if (generation !== windowGeometryGeneration) return
    if (wasRefresh) {
      try {
        var refreshed = findClientByAddress(raw)
        if (clientGeometryReady(refreshed) && targetMonitorGeometry &&
            Number(refreshed.monitor) === Number(targetMonitorGeometry.id)) {
          targetWindowGeometry = refreshed
        }
      } catch (error) {
        console.warn("learn-omarchy: couldn't refresh window geometry:", error)
      }
      return
    }
    if (!windowGeometryPending) return
    var windowData = null
    try {
      windowData = findClientByAddress(raw)
    } catch (error) {
      retryWindowGeometry(String(error))
      return
    }
    if (!clientGeometryReady(windowData)) {
      retryWindowGeometry(windowData ? "window not laid out yet" : "window not listed yet")
      return
    }
    targetWindowGeometry = windowData
    monitorGeometryProcess.requestGeneration = generation
    monitorGeometryProcess.running = true
  }

  function parseMonitorGeometry(raw, generation) {
    if (generation !== windowGeometryGeneration || !windowGeometryPending) return
    var windowData = targetWindowGeometry
    if (!windowData) return
    try {
      var monitors = JSON.parse(String(raw || "[]"))
      if (!Array.isArray(monitors)) throw new Error("monitors response wasn't a list")
      var windowMonitor = Number(windowData.monitor)
      var selected = null
      for (var i = 0; i < monitors.length; i++) {
        if (Number(monitors[i].id) === windowMonitor) {
          selected = monitors[i]
          break
        }
      }
      if (!selected) throw new Error("monitor " + windowMonitor + " not found")
      finishWindowDetection(windowData, selected)
    } catch (error) {
      console.warn("learn-omarchy: couldn't read monitor geometry:", error, "- using the configured target estimate")
      finishWindowDetection(null, null)
    }
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
    setCharacterState("celebrate", "NICE WORK!")
    runStepAction("shortcut")
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
    resetWindowTarget()
    errorMessage = String(message)
    phase = "error"
    setCharacterState("hidden", "")
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
    setCharacterState("menu-point", "CHOOSE A LESSON")
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
    lessonTransitionAnimation.stop()
    lessonTransitionRunning = false
    lessonContentOpacity = 1
    pendingLessonTransition = ""
    pendingTransitionStepIndex = -1
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
    resetWindowTarget()
    phase = "waiting"
    captureWorkspaceStart()
    captureStepStartWindow()
    startCharacterStep()
  }

  function cancelAction() {
    actionGeneration++
    actionCompletionTimer.stop()
    layerCompletionFeedbackTimer.stop()
    characterStepArrivalTimer.stop()
    characterHelpPointTimer.stop()
    characterHelpActionTimer.stop()
    characterMenuPointTimer.stop()
    characterTargetFlyTimer.stop()
    characterTargetPointTimer.stop()
    characterModuleArrivalTimer.stop()
    characterTravelSettleTimer.stop()
    characterTourArrivalTimer.stop()
    tourAdvanceTimer.stop()
    workspaceCompletionTimer.stop()
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
    resetWindowTarget()
    completionTimer.stop()
    lessonTransitionAnimation.stop()
    lessonTransitionRunning = false
    lessonContentOpacity = 1
    pendingLessonTransition = ""
    pendingTransitionStepIndex = -1
    clearActiveKeys()
    lessonIndex = -1
    stepIndex = 0
    phase = "menu"
    if (reducedMotion) {
      setCharacterState("menu-point", "CHOOSE A LESSON")
    } else {
      setCharacterState("menu-fly", "CHOOSE A LESSON")
      characterMenuPointTimer.restart()
    }
  }

  function skipCurrentStep() {
    if (!currentLesson || !currentStep || lessonTransitionRunning) return
    cancelAction()
    stopAudio()
    completionTimer.stop()
    if (stepIndex + 1 < currentLesson.steps.length) {
      beginLessonTransition("step", stepIndex + 1)
    } else {
      beginLessonTransition("lesson-complete")
    }
  }

  function completeCurrentStep() {
    if (!currentStep || phase !== "waiting" || lessonTransitionRunning) return
    characterStepArrivalTimer.stop()
    characterHelpPointTimer.stop()
    characterHelpActionTimer.stop()
    stopAudio()
    clearActiveKeys()
    beginLessonTransition("highlight")
  }

  function advance() {
    if (!currentLesson || !currentStep || lessonTransitionRunning) return
    if (stepIndex + 1 < currentLesson.steps.length) {
      beginLessonTransition("step", stepIndex + 1)
      return
    }
    beginLessonTransition("lesson-complete")
  }

  function currentAudioPath() {
    return currentStep && currentStep.audio ? courseDir + "/" + currentStep.audio : ""
  }

  function startAudioPath(path, preserveCharacterState) {
    if (!audioEnabled || path === "" || path !== currentAudioPath()) return
    audioStopRequested = false
    pendingAudioPath = ""
    pendingAudioPreserveCharacterState = false
    audioProcessPath = path
    audioProcess.command = [
      "mpv",
      "--no-video",
      "--really-quiet",
      "--",
      path
    ]
    if (!preserveCharacterState) setCharacterState("talk", "LISTENING...")
    audioProcess.running = true
  }

  function playCurrentAudio(preserveCharacterState) {
    if (!audioEnabled) return
    var path = currentAudioPath()
    if (path === "") return
    if (audioProcess.running || audioStopRequested) {
      if (audioProcessPath === path && !audioStopRequested) return
      pendingAudioPath = path
      pendingAudioPreserveCharacterState = Boolean(preserveCharacterState)
      audioStopRequested = true
      if (audioProcess.running) audioProcess.running = false
      return
    }
    startAudioPath(path, Boolean(preserveCharacterState))
  }

  function stopAudio() {
    pendingAudioPath = ""
    pendingAudioPreserveCharacterState = false
    if (audioProcess.running) {
      audioStopRequested = true
      audioProcess.running = false
    }
  }

  function toggleAudio() {
    audioEnabled = !audioEnabled
    if (audioEnabled) {
      if (currentStepIsTour) {
        tourAdvanceTimer.stop()
        playCurrentAudio(true)
      } else {
        playCurrentAudio()
      }
      return
    }
    var wasPlayingTour = currentStepIsTour && audioProcess.running
    stopAudio()
    if (currentStepIsTour && !wasPlayingTour && phase === "waiting" && !tourAdvanceTimer.running) {
      tourAdvanceTimer.interval = tourFallbackDuration()
      tourAdvanceTimer.restart()
    }
  }

  function replayCurrentAudio() {
    if (!currentStep || !currentStep.audio) return
    audioEnabled = true
    tourAdvanceTimer.stop()
    pendingAudioPath = currentAudioPath()
    pendingAudioPreserveCharacterState = currentStepIsTour
    if (audioProcess.running || audioStopRequested) {
      audioStopRequested = true
      if (audioProcess.running) audioProcess.running = false
    } else {
      startAudioPath(pendingAudioPath)
    }
  }

  function runStepAction(source) {
    if (actionRunning || !currentStep || !currentStep.help || !Array.isArray(currentStep.help.command)) return
    if (source === "shortcut") {
      characterHelpPointTimer.stop()
      characterHelpActionTimer.stop()
    }
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
    armHelpDetection()
    helpProcess.command = currentStep.help.command
    helpProcess.running = true
  }

  function requestHelpAction() {
    if (actionRunning || !currentStep || !currentStep.help || characterHelpActionTimer.running) return
    if (reducedMotion) {
      setCharacterState("help", "RIGHT HERE")
    } else {
      setCharacterState("help-fly", "LET ME SHOW YOU")
      characterHelpPointTimer.restart()
    }
    characterHelpActionTimer.restart()
  }

  function handleHyprlandEvent(event) {
    if (!currentStep || phase !== "waiting") return
    var completion = currentStep.completion
    if (
      completion &&
      completion.type === "hyprland-window-activated" &&
      (event.name === "openwindow" || event.name === "activewindowv2")
    ) {
      if (windowGeometryPending || targetWindowGeometry) return
      var address = normalizedWindowAddress(String(event.data || "").split(",")[0])
      if (address === "") return
      if (event.name === "activewindowv2") {
        // Focus-only changes also happen when cleanup closes a layer, so they
        // must follow observed shortcut keys or a Help action and land on a
        // different window than the one active when the step began.
        if (address === stepStartWindowAddress) return
        if (!windowDetectionArmed()) {
          console.info("learn-omarchy: ignoring activewindowv2 for", address, "because no shortcut or Help action is pending")
          return
        }
      } else if (!windowDetectionArmed()) {
        // Hyprland can consume the whole chord before the overlay sees any
        // key, so a newly opened window still counts as the taught outcome.
        console.info("learn-omarchy: accepting openwindow for", address, "without observed shortcut keys")
      }
      requestWindowGeometry(address)
      return
    }
    if (
      completion &&
      completion.type === "hyprland-workspace-change" &&
      (event.name === "workspace" ||
        event.name === "workspacev2" ||
        event.name === "focusedmon" ||
        event.name === "focusedmonv2")
    ) {
      workspaceCompletionTimer.restart()
      return
    }
    if (
      completion &&
      completion.type === "hyprland-layer-open" &&
      event.name === "openlayer" &&
      String(event.data).trim() === completion.namespace
    ) {
      confirmDetectedShortcut()
    }
  }

  function isPlainEscape(event) {
    var modifierMask = Qt.MetaModifier | Qt.ControlModifier | Qt.AltModifier | Qt.ShiftModifier
    return event.key === Qt.Key_Escape && (event.modifiers & modifierMask) === 0
  }

  function moveMenuSelection(delta) {
    if (!course) return
    selectedLessonIndex = Math.max(0, Math.min(course.lessons.length - 1, selectedLessonIndex + delta))
  }

  function handleKeyPressed(event) {
    if (lessonTransitionRunning) {
      event.accepted = true
      return
    }
    if (phase === "menu") {
      if (event.key === Qt.Key_Left) moveMenuSelection(-1)
      else if (event.key === Qt.Key_Right) moveMenuSelection(1)
      else if (event.key === Qt.Key_Up) moveMenuSelection(-2)
      else if (event.key === Qt.Key_Down) moveMenuSelection(2)
      else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) startLesson(selectedLessonIndex)
      else if (isPlainEscape(event)) Qt.quit()
      else return
      event.accepted = true
      return
    }
    if (phase === "lesson-complete") {
      if (event.key === Qt.Key_R) startLesson(lessonIndex)
      else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || isPlainEscape(event)) returnToMenu()
      else return
      event.accepted = true
      return
    }
    if (phase === "error") {
      if (isPlainEscape(event)) returnToMenu()
      event.accepted = true
      return
    }
    if (phase === "waiting") {
      if (isPlainEscape(event)) {
        returnToMenu()
        event.accepted = true
        return
      }
      if (
        currentStep &&
        currentStep.keys.length === 0 &&
        (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
      ) {
        if (currentStepIsTour) skipCurrentStep()
        else runStepAction("action")
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
        selectedLessonIndex: root.selectedLessonIndex,
        stepIndex: root.stepIndex,
        lessonId: root.currentLesson ? root.currentLesson.id : "",
        stepId: root.currentStep ? root.currentStep.id : "",
        keyboardFocused: root.keyboardFocused,
        characterState: root.characterState,
        characterMessage: root.characterMessage,
        lessonContentOpacity: root.lessonContentOpacity,
        lessonTransitionRunning: root.lessonTransitionRunning,
        workspaceStartId: root.workspaceStartId,
        activeKeys: root.activeKeys,
        targetWindowAddress: root.targetWindowAddress,
        targetWindowGeometry: root.targetWindowGeometry,
        targetMonitorGeometry: root.targetMonitorGeometry,
        windowGeometryPending: root.windowGeometryPending,
        stepStartWindowAddress: root.stepStartWindowAddress,
        windowDetectionArmed: root.windowDetectionArmed(),
        characterX: root.characterX,
        characterY: root.characterY,
        audioRunning: audioProcess.running,
        reducedMotion: root.reducedMotion
      })
    }

    function start(index: string): string {
      var parsed = Number(index)
      if (!isFinite(parsed)) return "invalid-index"
      root.startLesson(Math.floor(parsed))
      return "ok"
    }

    function select(index: string): string {
      var parsed = Number(index)
      if (root.phase !== "menu" || !isFinite(parsed) || !root.course) return "invalid-selection"
      var target = Math.floor(parsed)
      if (target < 0 || target >= root.course.lessons.length) return "invalid-selection"
      root.selectedLessonIndex = target
      return "ok"
    }

    function activate(): string {
      if (root.phase !== "waiting" || !root.currentStep) return "not-waiting"
      root.requestHelpAction()
      return "ok"
    }

    function react(key: string): string {
      if (root.phase !== "waiting" || !root.currentStep) return "not-waiting"
      root.reactToKey(String(key).toUpperCase())
      return "ok"
    }

    function target(): string {
      if (root.phase !== "waiting" || !root.currentStep) return "not-waiting"
      root.completeCurrentStep()
      return "ok"
    }
  }

  Process {
    id: audioProcess
    onExited: function(exitCode) {
      var stopped = root.audioStopRequested
      var finishedPath = root.audioProcessPath
      var queuedPath = root.pendingAudioPath
      var preserveQueuedCharacterState = root.pendingAudioPreserveCharacterState
      root.audioStopRequested = false
      root.audioProcessPath = ""
      root.pendingAudioPath = ""
      root.pendingAudioPreserveCharacterState = false
      if (stopped) {
        if (queuedPath !== "" && root.audioEnabled && queuedPath === root.currentAudioPath()) {
          Qt.callLater(function() {
            root.startAudioPath(queuedPath, preserveQueuedCharacterState)
          })
        } else if (
          root.phase === "waiting" &&
          root.currentStepIsTour &&
          !root.audioEnabled &&
          finishedPath === root.currentAudioPath()
        ) {
          tourAdvanceTimer.interval = root.tourFallbackDuration()
          tourAdvanceTimer.restart()
        } else if (root.phase === "waiting" && root.characterState === "talk") {
          root.settleCharacter()
        }
        return
      }
      if (
        exitCode === 0 &&
        root.phase === "waiting" &&
        root.currentStepIsTour &&
        finishedPath === root.currentAudioPath()
      ) {
        root.scheduleTourAdvance()
        return
      }
      if (
        exitCode !== 0 &&
        root.phase === "waiting" &&
        root.audioEnabled &&
        finishedPath === root.currentAudioPath()
      ) {
        root.fail("Narration couldn't be played. Check the audio file and mpv installation.")
      } else if (root.phase === "waiting" && root.characterState === "talk") {
        root.settleCharacter()
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
      } else if (
        exitCode === 0 &&
        root.phase === "waiting" &&
        root.currentStep &&
        root.currentStep.id === root.actionStepId &&
        root.actionCompletionType === "hyprland-workspace-change"
      ) {
        workspaceCompletionTimer.restart()
      } else if (
        exitCode === 0 &&
        root.phase === "waiting" &&
        root.currentStep &&
        root.currentStep.id === root.actionStepId &&
        root.actionCompletionType === "hyprland-window-activated"
      ) {
        root.armHelpDetection()
        if (!root.windowGeometryPending && !root.targetWindowGeometry) windowActivationHintTimer.restart()
      }
    }
  }

  Process {
    id: stepStartWindowProcess
    property int requestGeneration: -1
    command: ["hyprctl", "activewindow", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseStepStartWindow(text, stepStartWindowProcess.requestGeneration)
    }
  }

  Process {
    id: clientGeometryProcess
    property int requestGeneration: -1
    command: ["hyprctl", "clients", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseClientGeometry(text, clientGeometryProcess.requestGeneration)
    }
  }

  Process {
    id: monitorGeometryProcess
    property int requestGeneration: -1
    command: ["hyprctl", "monitors", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseMonitorGeometry(text, monitorGeometryProcess.requestGeneration)
    }
  }

  Timer {
    id: windowGeometryRetryTimer
    interval: 150
    repeat: false
    onTriggered: root.queryWindowGeometry()
  }

  Timer {
    id: windowGeometryRefreshTimer
    property bool refreshing: false
    interval: 320
    repeat: false
    onTriggered: {
      if (!root.targetWindowGeometry || clientGeometryProcess.running) return
      refreshing = true
      clientGeometryProcess.requestGeneration = root.windowGeometryGeneration
      clientGeometryProcess.running = true
    }
  }

  Timer {
    id: windowActivationHintTimer
    interval: 4000
    repeat: false
    onTriggered: {
      if (
        root.phase !== "waiting" ||
        !root.usesWindowActivation() ||
        root.windowGeometryPending ||
        root.targetWindowGeometry
      ) return
      console.info("learn-omarchy: no application window appeared after the Help action for", root.currentStep.id)
      root.setCharacterState(audioProcess.running ? "talk" : "coach", "NO NEW WINDOW YET - TRY AGAIN OR SKIP")
    }
  }

  SequentialAnimation {
    id: lessonTransitionAnimation

    NumberAnimation {
      target: root
      property: "lessonContentOpacity"
      to: 0
      duration: 220
      easing.type: Easing.InOutCubic
    }
    ScriptAction { script: root.applyLessonTransition() }
    PauseAnimation { duration: 50 }
    NumberAnimation {
      target: root
      property: "lessonContentOpacity"
      to: 1
      duration: 300
      easing.type: Easing.InOutCubic
    }
    ScriptAction { script: root.lessonTransitionRunning = false }
  }

  Timer {
    id: characterStepArrivalTimer
    interval: root.characterTravelDuration + 180
    repeat: false
    onTriggered: {
      if (root.characterState === "step-fly") {
        root.setCharacterState("step-settle", "LANDING")
        characterTravelSettleTimer.restart()
      }
    }
  }

  Timer {
    id: characterTourArrivalTimer
    interval: root.characterTravelDuration + 180
    repeat: false
    onTriggered: {
      if (root.phase === "waiting" && root.characterState === "tour-fly") {
        root.setCharacterState("tour-settle", "ALMOST THERE")
        characterTravelSettleTimer.restart()
      }
    }
  }

  Timer {
    id: tourAdvanceTimer
    repeat: false
    onTriggered: {
      if (root.phase === "waiting" && root.currentStepIsTour && !root.lessonTransitionRunning) root.advance()
    }
  }

  Timer {
    id: characterModuleArrivalTimer
    interval: root.characterTravelDuration + 180
    repeat: false
    onTriggered: {
      if (root.phase === "lesson-complete" && root.characterState === "module-fly") {
        root.setCharacterState("module-settle", "ALMOST THERE")
        characterTravelSettleTimer.restart()
      }
    }
  }

  Timer {
    id: characterReactionTimer
    repeat: false
    onTriggered: {
      if (root.characterState === "correct" || root.characterState === "incorrect") {
        root.settleCharacter()
      }
    }
  }

  Timer {
    id: characterHelpPointTimer
    interval: root.characterTravelDuration
    repeat: false
    onTriggered: {
      if (root.phase === "waiting" && root.characterState === "help-fly") {
        root.setCharacterState("help-settle", "RIGHT HERE")
        characterTravelSettleTimer.restart()
      }
    }
  }

  Timer {
    id: characterHelpActionTimer
    interval: root.characterTravelDuration + 650
    repeat: false
    onTriggered: {
      if (
        root.phase === "waiting" &&
        (root.characterState === "help" ||
          root.characterState === "help-fly" ||
          root.characterState === "help-settle")
      ) {
        root.runStepAction("help-ready")
      }
    }
  }

  Timer {
    id: characterMenuPointTimer
    interval: root.characterTravelDuration
    repeat: false
    onTriggered: {
      if (root.phase === "menu" && root.characterState === "menu-fly") {
        root.setCharacterState("menu-settle", "CHOOSE A LESSON")
        characterTravelSettleTimer.restart()
      }
    }
  }

  Timer {
    id: characterTargetFlyTimer
    interval: 420
    repeat: false
    onTriggered: {
      if (root.phase === "highlight" && root.currentStep) {
        if (root.reducedMotion) {
          root.setCharacterState("target-point", "HERE IT IS!")
        } else {
          root.setCharacterState("target-fly", "LET'S TAKE A LOOK")
          characterTargetPointTimer.restart()
        }
      }
    }

  }

  Timer {
    id: characterTargetPointTimer
    interval: root.characterTravelDuration
    repeat: false
    onTriggered: {
      if (root.phase === "highlight" && root.characterState === "target-fly") {
        root.setCharacterState("target-settle", "RIGHT HERE")
        characterTravelSettleTimer.restart()
      }
    }
  }

  Timer {
    id: characterTravelSettleTimer
    interval: 340
    repeat: false
    onTriggered: {
      if (root.phase === "waiting" && root.characterState === "step-settle") {
        if (root.audioEnabled && root.currentAudioPath() !== "") root.playCurrentAudio()
        else root.settleCharacter()
      } else if (root.phase === "waiting" && root.characterState === "tour-settle") {
        root.setCharacterState("tour-point", "LOOK HERE")
        root.beginTourNarration()
      } else if (root.phase === "waiting" && root.characterState === "help-settle") {
        root.setCharacterState("help", "RIGHT HERE")
      } else if (root.phase === "menu" && root.characterState === "menu-settle") {
        root.setCharacterState("menu-point", "CHOOSE A LESSON")
      } else if (root.phase === "highlight" && root.characterState === "target-settle") {
        root.setCharacterState("target-point", "HERE IT IS!")
      } else if (root.phase === "lesson-complete" && root.characterState === "module-settle") {
        root.setCharacterState("celebrate", "MODULE COMPLETE!")
      }
    }
  }

  Timer {
    id: actionCompletionTimer
    repeat: false
    onTriggered: root.completeCurrentStep()
  }

  Timer {
    id: workspaceCompletionTimer
    interval: 120
    repeat: false
    onTriggered: root.checkWorkspaceCompletion()
  }

  Timer {
    id: completionTimer
    repeat: false
    onTriggered: root.advance()
  }

  Timer {
    id: layerCompletionFeedbackTimer
    interval: 320
    repeat: false
    onTriggered: root.completeCurrentStep()
  }

  Variants {
    model: Quickshell.screens

    delegate: PanelWindow {
      id: overlay

      required property var modelData
      property real menuSelectionX: width / 2
      property real menuSelectionY: height / 2
      readonly property bool isFocusedScreen: {
        var monitor = Hyprland.monitorFor(modelData)
        return monitor && monitor === Hyprland.focusedMonitor
      }
      readonly property bool shouldShow: root.phase !== "loading" && isFocusedScreen
      readonly property var highlight: root.currentStep ? root.currentStep.highlight : null
      readonly property var hyprlandMonitor: Hyprland.monitorFor(modelData)
      readonly property bool windowOnThisMonitor:
        Boolean(root.targetWindowGeometry && root.targetMonitorGeometry) &&
        (!hyprlandMonitor || Number(hyprlandMonitor.id) === Number(root.targetMonitorGeometry.id))
      readonly property bool usesWindowTarget:
        Boolean(root.currentStep) &&
        root.currentStep.completion.type === "hyprland-window-activated" &&
        windowOnThisMonitor
      readonly property real monitorLogicalWidth: usesWindowTarget
        ? logicalMonitorSize(root.targetMonitorGeometry).width
        : width
      readonly property real monitorLogicalHeight: usesWindowTarget
        ? logicalMonitorSize(root.targetMonitorGeometry).height
        : height
      readonly property real windowScaleX: monitorLogicalWidth > 0 ? width / monitorLogicalWidth : 1
      readonly property real windowScaleY: monitorLogicalHeight > 0 ? height / monitorLogicalHeight : 1
      readonly property real minimumLeftPointX: 213
      readonly property real windowTargetX: usesWindowTarget
        ? (Number(root.targetWindowGeometry.at[0]) - Number(root.targetMonitorGeometry.x)) * windowScaleX
        : 0
      readonly property real windowTargetY: usesWindowTarget
        ? (Number(root.targetWindowGeometry.at[1]) - Number(root.targetMonitorGeometry.y)) * windowScaleY
        : 0
      readonly property real windowTargetWidth: usesWindowTarget
        ? Number(root.targetWindowGeometry.size[0]) * windowScaleX
        : 0
      readonly property real windowTargetHeight: usesWindowTarget
        ? Number(root.targetWindowGeometry.size[1]) * windowScaleY
        : 0
      readonly property real dynamicHighlightWidth: {
        if (!highlight || highlight.dynamic !== "workspaces") return highlight ? highlight.width : 0
        // One 27px pill plus a 1px gap per workspace, with the bar's edge padding.
        return 12 + (root.barWorkspaceCount() * 28)
      }
      readonly property real fittedHighlightWidth: {
        if (!highlight) return 0
        if (highlight.shape === "circle") {
          return Math.max(0, Math.min(highlight.width, width - 20, height - 20))
        }
        return Math.max(0, Math.min(dynamicHighlightWidth, width - 20))
      }
      readonly property real fittedHighlightHeight: {
        if (!highlight) return 0
        if (highlight.shape === "circle") return fittedHighlightWidth
        return Math.max(0, Math.min(highlight.height, height - 20))
      }
      readonly property real targetBoundsX: usesWindowTarget
        ? windowTargetX
        : highlight
        ? anchoredX(highlight.anchor, fittedHighlightWidth, highlight.x)
        : width / 2
      readonly property real targetBoundsY: usesWindowTarget
        ? windowTargetY
        : highlight
        ? anchoredY(highlight.anchor, fittedHighlightHeight, highlight.y)
        : height / 2
      readonly property real targetPointX: {
        var value
        if (usesWindowTarget) {
          value = leftEdgePointX(windowTargetX, windowTargetWidth)
        } else if (highlight) {
          value = highlight.shape === "circle"
            ? targetBoundsX + (fittedHighlightWidth / 2)
            : leftEdgePointX(targetBoundsX, fittedHighlightWidth)
        } else {
          value = width / 2
        }
        return Math.max(0, Math.min(width, value))
      }
      readonly property real targetPointY: {
        var value
        if (usesWindowTarget) value = windowTargetY + (windowTargetHeight / 2)
        else if (highlight) value = targetBoundsY + (fittedHighlightHeight / 2)
        else value = height / 2
        return Math.max(0, Math.min(height, value))
      }

      readonly property real tourPointX: highlight ? targetBoundsX + (fittedHighlightWidth / 2) : width / 2
      // Fingertip target sits ~44px under the box so the antennas (about 38px
      // above the fingertip) stay clear of the bar area being discussed.
      readonly property real tourPointY: highlight ? targetBoundsY + fittedHighlightHeight + 44 : 80

      function logicalMonitorSize(monitor) {
        var scale = Number(monitor.scale) > 0 ? Number(monitor.scale) : 1
        var transform = Number(monitor.transform) || 0
        var logicalWidth = Number(monitor.width) / scale
        var logicalHeight = Number(monitor.height) / scale
        if (transform % 2 === 1) return { width: logicalHeight, height: logicalWidth }
        return { width: logicalWidth, height: logicalHeight }
      }

      function leftEdgePointX(left, itemWidth) {
        if (left >= minimumLeftPointX) return left
        return Math.min(left + itemWidth, minimumLeftPointX)
      }

      screen: modelData
      visible: shouldShow
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
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
      mask: Region {
        Region { item: topicPanel }
        Region { item: lessonNavigation }
        Region { item: controls }
        Region { item: replayButton }
        Region { item: actionButton }
        Region { item: hexonCoach }
        Region { item: completionPanel }
        Region { item: errorPanel }
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

        Component.onCompleted: Qt.callLater(function() { keyCatcher.forceActiveFocus() })
      }

      function anchoredX(anchor, itemWidth, offset) {
        var normalizedAnchor = String(anchor || "center")
        var value
        if (normalizedAnchor.indexOf("left") !== -1 || normalizedAnchor === "left") value = offset
        else if (normalizedAnchor.indexOf("right") !== -1 || normalizedAnchor === "right") value = width - itemWidth + offset
        else value = Math.round((width - itemWidth) / 2) + offset
        return Math.max(0, Math.min(width - itemWidth, value))
      }

      function anchoredY(anchor, itemHeight, offset) {
        var normalizedAnchor = String(anchor || "center")
        var value
        if (normalizedAnchor.indexOf("top") !== -1 || normalizedAnchor === "top") value = offset
        else if (normalizedAnchor.indexOf("bottom") !== -1 || normalizedAnchor === "bottom") value = height - itemHeight + offset
        else value = Math.round((height - itemHeight) / 2) + offset
        return Math.max(0, Math.min(height - itemHeight, value))
      }

      function updateMenuSelectionTarget(item, index) {
        if (!item || index !== root.selectedLessonIndex) return
        var point = item.mapToItem(
          topicPanel,
          0,
          item.height / 2
        )
        var nextX = topicPanel.x + point.x
        var nextY = topicPanel.y + point.y
        menuSelectionX = nextX
        menuSelectionY = nextY
      }

      Rectangle {
        anchors.fill: parent
        visible: root.phase === "menu" || root.phase === "lesson-complete" || root.phase === "error"
        color: root.colorWithAlpha(root.background, 0.72)
      }

      Rectangle {
        id: targetMarker
        z: 9
        visible: root.phase === "highlight" &&
          root.characterState === "target-point" &&
          overlay.highlight
        opacity: root.lessonContentOpacity
        width: 38
        height: 38
        x: Math.round(overlay.targetPointX - (width / 2))
        y: Math.round(overlay.targetPointY - (height / 2))
        color: "transparent"
        border.color: root.accent
        border.width: 4
        radius: 19

        SequentialAnimation on scale {
          running: targetMarker.visible && !root.reducedMotion
          loops: Animation.Infinite
          NumberAnimation { from: 0.72; to: 1.18; duration: 520; easing.type: Easing.OutCubic }
          NumberAnimation { from: 1.18; to: 0.72; duration: 520; easing.type: Easing.InCubic }
        }
      }

      Rectangle {
        id: tourOutline
        z: 9
        visible: root.phase === "waiting" &&
          root.currentStepIsTour &&
          (root.characterState === "tour-point" || root.characterState === "tour-settle") &&
          overlay.highlight
        opacity: root.lessonContentOpacity
        x: Math.round(overlay.targetBoundsX)
        y: Math.round(overlay.targetBoundsY)
        width: Math.round(overlay.fittedHighlightWidth)
        height: Math.round(overlay.fittedHighlightHeight)
        color: root.colorWithAlpha(root.accent, 0.12)
        border.color: root.accent
        border.width: overlay.highlight ? Math.max(2, Math.min(4, Number(overlay.highlight.borderWidth) || 3)) : 3
        radius: overlay.highlight ? Number(overlay.highlight.radius) || 8 : 8

        SequentialAnimation on border.color {
          running: tourOutline.visible && !root.reducedMotion
          loops: Animation.Infinite
          ColorAnimation { to: root.instruction; duration: 600 }
          ColorAnimation { to: root.accent; duration: 600 }
        }
      }

      Rectangle {
        id: tourCaption
        z: 11
        visible: hexonCoach.visible && root.phase === "waiting" && root.currentStepIsTour
        opacity: root.lessonContentOpacity
        width: Math.min(400, overlay.width - 24, Math.max(200, tourCaptionText.implicitWidth + 32))
        height: tourCaptionText.implicitHeight + 24
        // Centre under HEXON, but never leave the screen.
        x: Math.round(Math.max(12, Math.min(overlay.width - width - 12,
          hexonCoach.x + (hexonCoach.width / 2) - (width / 2))))
        y: Math.round(Math.min(overlay.height - height - 12, hexonCoach.y + hexonCoach.height + 8))
        radius: 12
        color: root.background
        border.color: root.instruction
        border.width: 2

        Text {
          id: tourCaptionText
          width: Math.min(tourCaption.width - 32, implicitWidth)
          anchors.centerIn: parent
          text: root.currentStep ? root.currentStep.instruction : ""
          textFormat: Text.PlainText
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          color: root.instruction
          font.family: "sans-serif"
          font.pixelSize: 15
          font.weight: Font.Bold
        }
      }

      Item {
        id: hexonCoach
        z: 10

        property real effectScale: 1
        property real effectRotation: 0
        property real effectOpacity: 1
        property bool userPlaced: false
        property real userX: 0
        property real userY: 0
        property string interactionMessage: ""
        readonly property bool targetsCompletion:
          root.characterState === "target-fly" ||
          root.characterState === "target-settle" ||
          root.characterState === "target-point"
        readonly property bool targetsTour:
          root.characterState === "tour-fly" ||
          root.characterState === "tour-settle" ||
          root.characterState === "tour-point"
        readonly property bool isPointingUp: root.characterState === "tour-point"
        readonly property bool targetsMenu:
          root.characterState === "menu-fly" ||
          root.characterState === "menu-settle" ||
          root.characterState === "menu-point"
        readonly property bool targetsModuleComplete: root.phase === "lesson-complete"
        readonly property bool isPointing:
          root.characterState === "help" ||
          root.characterState === "target-point" ||
          root.characterState === "tour-point" ||
          root.characterState === "menu-point"
        // Fingertip of the upward pose inside the 224x192 image (before the 1.13 pose scale).
        readonly property real upTipImageX: 147
        readonly property real upTipImageY: 42
        readonly property real upTipLocalX: 8 + 112 + ((upTipImageX - 112) * pointPoseScale)
        readonly property real upTipLocalY: (height - 192) + 96 + ((upTipImageY - 96) * pointPoseScale)
        readonly property real tourTipX:
          Math.max(18 + upTipLocalX, Math.min(overlay.width - 18 - (width - upTipLocalX), overlay.tourPointX))
        readonly property real tourX: tourTipX - upTipLocalX
        readonly property real tourY: Math.max(-(height - 192) - 4, overlay.tourPointY - upTipLocalY)
        readonly property bool isFlying:
          root.characterState === "step-fly" ||
          root.characterState === "step-settle" ||
          root.characterState === "help-fly" ||
          root.characterState === "help-settle" ||
          root.characterState === "target-fly" ||
          root.characterState === "target-settle" ||
          root.characterState === "tour-fly" ||
          root.characterState === "tour-settle" ||
          root.characterState === "menu-fly" ||
          root.characterState === "menu-settle" ||
          root.characterState === "module-fly" ||
          root.characterState === "module-settle"
        readonly property bool isSettledHover:
          visible && !isFlying && root.characterState !== "hidden"
        readonly property real pointPoseScale: 1.13
        readonly property real waitingX:
          Math.max(28, teachingContent.x - width - 22)
        readonly property real waitingY:
          Math.max(70, overlay.height - height - 28)
        readonly property real menuTargetX: overlay.menuSelectionX
        readonly property real menuTargetY: overlay.menuSelectionY
        readonly property real moduleTargetX:
          Math.max(18, completionPanel.x - width - 22)
        readonly property real moduleTargetY:
          Math.max(50, Math.min(bottomY,
            completionPanel.y + (completionPanel.height / 2) - (height * 0.55)))
        readonly property real targetScale: targetsCompletion
          ? Math.max(0.5, Math.min(1, (overlay.targetPointX - 18) / 195))
          : 1
        readonly property real responsiveScale: targetsCompletion ? targetScale : 1
        property real presentationScale: responsiveScale
        readonly property real targetX:
          overlay.targetPointX - (width / 2) - (75 * targetScale)
        readonly property real targetY:
          overlay.targetPointY - height + (117 * targetScale)
        readonly property real bottomY: overlay.height - height - 28
        readonly property real contextX: targetsMenu
          ? Math.max(18, Math.min(overlay.width - width - 18, menuTargetX - width + 45))
          : targetsTour
            ? tourX
          : targetsCompletion
            ? Math.max(18 - (width * (1 - targetScale) / 2), Math.min(overlay.width - width - 18, targetX))
            : targetsModuleComplete
              ? moduleTargetX
            : waitingX
        readonly property real contextY: targetsMenu
          ? Math.max(50, menuTargetY - (height * 0.55))
          : targetsTour
            ? tourY
          : targetsCompletion
            ? Math.max(50, Math.min(bottomY, targetY))
            : targetsModuleComplete
              ? moduleTargetY
            : waitingY

        visible: (root.phase === "menu" ||
          root.phase === "waiting" ||
          root.phase === "highlight" ||
          root.phase === "lesson-complete") &&
          root.characterState !== "hidden"
        width: 240
        height: 260
        x: userPlaced ? userX : contextX
        y: userPlaced ? userY : contextY
        scale: effectScale * presentationScale
        rotation: effectRotation
        opacity: effectOpacity
        transformOrigin: Item.Bottom

        onIsSettledHoverChanged: {
          if (!isSettledHover) characterImageArea.hoverOffset = 0
        }

        onXChanged: if (overlay.shouldShow) root.characterX = x
        onYChanged: if (overlay.shouldShow) root.characterY = y

        Behavior on presentationScale {
          enabled: hexonCoach.visible && !root.reducedMotion
          NumberAnimation {
            duration: 320
            easing.type: Easing.InOutSine
          }
        }

        // The pin (userPlaced) must not gate these Behaviors: when the pin is
        // released the x/y bindings can re-evaluate before `enabled` does,
        // which made HEXON jump to the target instead of flying there. Only
        // direct manipulation (dragging, the gravity fall) bypasses them.
        Behavior on x {
          enabled: hexonCoach.visible && !root.reducedMotion && !characterMouse.pressed
          NumberAnimation {
            duration: root.characterTravelDuration
            easing.type: Easing.InOutSine
          }
        }

        Behavior on y {
          enabled: hexonCoach.visible && !root.reducedMotion && !characterMouse.pressed && !fallAnimation.running
          NumberAnimation {
            duration: root.characterState === "menu-point" ? 620 : root.characterTravelDuration
            easing.type: Easing.InOutSine
          }
        }

        Connections {
          target: root

          function onPendingLessonTransitionChanged() {
            if (root.pendingLessonTransition !== "highlight" || !hexonCoach.visible) return
            fallAnimation.stop()
            hexonCoach.userX = hexonCoach.x
            hexonCoach.userY = hexonCoach.y
            hexonCoach.userPlaced = true
          }

          function onCharacterCueChanged() {
            if (
              root.characterState === "step-fly" ||
              root.characterState === "step-settle" ||
              root.characterState === "help-fly" ||
              root.characterState === "help-settle" ||
              root.characterState === "help" ||
              root.characterState === "target-fly" ||
              root.characterState === "target-settle" ||
              root.characterState === "target-point" ||
              root.characterState === "tour-fly" ||
              root.characterState === "tour-settle" ||
              root.characterState === "tour-point" ||
              root.characterState === "menu-fly" ||
              root.characterState === "menu-settle" ||
              root.characterState === "menu-point" ||
              root.characterState === "module-fly" ||
              root.characterState === "module-settle"
            ) {
              fallAnimation.stop()
              hexonCoach.userPlaced = false
            }
            if (root.reducedMotion) {
              hexonCoach.effectScale = 1
              hexonCoach.effectRotation = 0
              hexonCoach.effectOpacity = 1
              return
            }
            if (root.characterState === "correct") correctAnimation.restart()
            else if (root.characterState === "incorrect") incorrectAnimation.restart()
            else if (root.characterState === "celebrate") {
              celebrateAnimation.restart()
              confettiAnimation.restart()
            }
            else {
              hexonCoach.effectScale = 1
              hexonCoach.effectRotation = 0
              hexonCoach.effectOpacity = 1
            }
          }

          function onSelectedLessonIndexChanged() {
            if (root.phase === "menu") {
              fallAnimation.stop()
              hexonCoach.userPlaced = false
            }
          }
        }

        SequentialAnimation {
          id: correctAnimation
          PropertyAction {
            target: hexonCoach
            property: "effectScale"
            value: 1
          }
          NumberAnimation {
            target: hexonCoach
            property: "effectScale"
            to: 1.06
            duration: 220
            easing.type: Easing.InOutSine
          }
          NumberAnimation {
            target: hexonCoach
            property: "effectScale"
            to: 1
            duration: 280
            easing.type: Easing.InOutSine
          }
        }

        SequentialAnimation {
          id: incorrectAnimation
          PropertyAction {
            target: hexonCoach
            property: "effectRotation"
            value: 0
          }
          NumberAnimation {
            target: hexonCoach
            property: "effectRotation"
            to: -3
            duration: 160
            easing.type: Easing.InOutSine
          }
          NumberAnimation {
            target: hexonCoach
            property: "effectRotation"
            to: 3
            duration: 240
            easing.type: Easing.InOutSine
          }
          NumberAnimation {
            target: hexonCoach
            property: "effectRotation"
            to: 0
            duration: 220
            easing.type: Easing.InOutSine
          }
        }

        SequentialAnimation {
          id: celebrateAnimation
          PropertyAction {
            target: hexonCoach
            property: "effectScale"
            value: 1
          }
          NumberAnimation {
            target: hexonCoach
            property: "effectScale"
            to: 1.1
            duration: 260
            easing.type: Easing.InOutSine
          }
          NumberAnimation {
            target: hexonCoach
            property: "effectScale"
            to: 1
            duration: 360
            easing.type: Easing.InOutSine
          }
        }

        SequentialAnimation {
          id: clickAnimation
          PropertyAction {
            target: hexonCoach
            property: "effectScale"
            value: 1
          }
          NumberAnimation {
            target: hexonCoach
            property: "effectScale"
            to: 1.07
            duration: 180
            easing.type: Easing.InOutSine
          }
          NumberAnimation {
            target: hexonCoach
            property: "effectScale"
            to: 0.98
            duration: 160
            easing.type: Easing.InOutSine
          }
          NumberAnimation {
            target: hexonCoach
            property: "effectScale"
            to: 1
            duration: 220
            easing.type: Easing.InOutSine
          }
        }

        NumberAnimation {
          id: fallAnimation
          target: hexonCoach
          property: "userY"
          to: hexonCoach.bottomY
          duration: root.reducedMotion ? 0 : 850
          easing.type: Easing.OutCubic
        }

        Timer {
          id: interactionMessageTimer
          interval: 900
          repeat: false
          onTriggered: hexonCoach.interactionMessage = ""
        }

        Rectangle {
          anchors {
            horizontalCenter: parent.horizontalCenter
            verticalCenter: characterImageArea.verticalCenter
          }
          visible: root.characterState === "correct"
          width: 164
          height: 164
          radius: 82
          color: "transparent"
          border.color: root.accent
          border.width: 4
          opacity: 0.42

          SequentialAnimation on scale {
            running: root.characterState === "correct" && !root.reducedMotion
            loops: Animation.Infinite
            NumberAnimation { from: 0.86; to: 1.18; duration: 620; easing.type: Easing.OutCubic }
            NumberAnimation { from: 1.18; to: 0.86; duration: 620; easing.type: Easing.InCubic }
          }
        }

        Item {
          id: confettiBurst

          // 0 -> 1 over one burst. Every piece derives its own arc from this
          // single value, so the whole effect is one animation.
          property real progress: 1
          readonly property bool active: progress < 1
          readonly property real originX: hexonCoach.width / 2
          readonly property real originY: hexonCoach.height - 120

          anchors.fill: parent
          visible: active

          NumberAnimation {
            id: confettiAnimation
            target: confettiBurst
            property: "progress"
            from: 0
            to: 1
            duration: 1100
            easing.type: Easing.Linear
          }

          Repeater {
            model: 20

            Rectangle {
              required property int index
              readonly property real seed: ((index * 7919) % 97) / 97
              readonly property real seed2: ((index * 104729) % 89) / 89
              // Fan the pieces across the upper half so they fly up and out.
              readonly property real angle: (Math.PI * 0.12) + (index / 20) * (Math.PI * 0.76)
              readonly property real speed: 200 + (seed * 140)
              readonly property real vx: Math.cos(angle) * speed
              readonly property real vy: Math.sin(angle) * speed
              readonly property real t: confettiBurst.progress
              readonly property real px: confettiBurst.originX + (vx * t)
              readonly property real py: confettiBurst.originY - (vy * t) + (300 * t * t)

              width: 5 + Math.round(seed2 * 5)
              height: width
              x: px - (width / 2)
              y: py - (height / 2)
              rotation: t * 540 * (index % 2 === 0 ? 1 : -1)
              opacity: t < 0.55 ? 1 : Math.max(0, 1 - ((t - 0.55) / 0.45))
              color: index % 4 === 0
                ? root.accent
                : index % 4 === 1
                  ? root.instruction
                  : index % 4 === 2
                    ? root.urgent
                    : root.foreground
            }
          }
        }

        Rectangle {
          visible: !hexonCoach.isPointingUp
          anchors {
            top: parent.top
          }
          x: hexonCoach.isPointing
            ? 195 - width
            : (parent.width - width) / 2
          width: Math.min(230, Math.max(112, characterMessageText.implicitWidth + 24))
          height: Math.max(38, characterMessageText.implicitHeight + 16)
          radius: 10
          color: root.foreground
          border.color: root.characterState === "incorrect" ? root.urgent : root.accent
          border.width: 2

          Text {
            id: characterMessageText
            anchors {
              fill: parent
              margins: 8
            }
            text: hexonCoach.interactionMessage !== ""
              ? hexonCoach.interactionMessage
              : root.characterMessage
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
            color: root.background
            font.family: "monospace"
            font.pixelSize: 12
            font.weight: Font.Bold
          }
        }

        Item {
          id: characterImageArea

          property real hoverOffset: 0

          anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: hoverOffset
          }
          width: 224
          height: 192

          SequentialAnimation on hoverOffset {
            running: hexonCoach.isSettledHover && !root.reducedMotion
            loops: Animation.Infinite
            NumberAnimation {
              from: 0
              to: 4
              duration: 900
              easing.type: Easing.InOutSine
            }
            NumberAnimation {
              from: 4
              to: 0
              duration: 900
              easing.type: Easing.InOutSine
            }
          }

          Repeater {
            model: hexonCoach.isPointing
              ? [{ "x": 80, "y": 153 }, { "x": 122, "y": 150 }]
              : [{ "x": 96, "y": 181 }, { "x": 130, "y": 181 }]

            delegate: Item {
              required property var modelData

              property real flamePulse: 1

              visible: hexonCoach.visible && !root.reducedMotion
              x: modelData.x - 6
              y: modelData.y
              width: 12
              height: 26
              z: 0
              scale: (hexonCoach.isFlying ? 1.35 : 1) * flamePulse
              transformOrigin: Item.Top

              Rectangle {
                x: 4
                width: 4
                height: 6
                color: root.foreground
              }

              Rectangle {
                x: 2
                y: 5
                width: 8
                height: 7
                color: root.instruction
              }

              Rectangle {
                x: 3
                y: 12
                width: 6
                height: 8
                color: root.urgent
              }

              Rectangle {
                x: 5
                y: 20
                width: 2
                height: 6
                color: root.accent
              }

              SequentialAnimation on flamePulse {
                running: parent.visible
                loops: Animation.Infinite
                NumberAnimation {
                  from: 0.72
                  to: 1.08
                  duration: 150
                  easing.type: Easing.InOutSine
                }
                NumberAnimation {
                  from: 1.08
                  to: 0.82
                  duration: 190
                  easing.type: Easing.InOutSine
                }
              }

              SequentialAnimation on opacity {
                running: parent.visible
                loops: Animation.Infinite
                NumberAnimation { from: 0.72; to: 1; duration: 170 }
                NumberAnimation { from: 1; to: 0.76; duration: 170 }
              }
            }
          }

          SpriteSequence {
            anchors.centerIn: parent
            z: 1
            opacity: hexonCoach.isPointing ? 0 : 1
            width: 192
            height: 192
            interpolate: false
            goalSprite: root.characterState === "talk" ? "talk" : "idle"
            onGoalSpriteChanged: jumpTo(goalSprite)

            sprites: [
              Sprite {
                name: "idle"
                source: root.characterAssetRoot + "/sprites/hexon-idle.png"
                frameCount: 16
                frameWidth: 192
                frameHeight: 192
                frameRate: root.reducedMotion ? 2 : 6
                to: { "idle": 1, "talk": 1 }
              },
              Sprite {
                name: "talk"
                source: root.characterAssetRoot + "/sprites/hexon-talk.png"
                frameCount: 8
                frameWidth: 192
                frameHeight: 192
                frameRate: root.reducedMotion ? 2 : 8
                to: { "idle": 1, "talk": 1 }
              }
            ]

            Behavior on opacity {
              NumberAnimation {
                duration: root.characterPoseFadeDuration
                easing.type: Easing.InOutSine
              }
            }
          }

          Image {
            anchors.fill: parent
            z: 1
            opacity: hexonCoach.isPointingUp ? 1 : 0
            source: root.characterAssetRoot + "/sprites/hexon-point-up.png"
            fillMode: Image.PreserveAspectFit
            smooth: false
            mipmap: false
            scale: hexonCoach.pointPoseScale

            Behavior on opacity {
              NumberAnimation {
                duration: root.characterPoseFadeDuration
                easing.type: Easing.InOutSine
              }
            }
          }

          Image {
            anchors.fill: parent
            z: 1
            opacity: hexonCoach.isPointing && !hexonCoach.isPointingUp ? 1 : 0
            source: root.characterAssetRoot + "/sprites/hexon-point.png"
            fillMode: Image.PreserveAspectFit
            smooth: false
            mipmap: false
            scale: hexonCoach.pointPoseScale

            Behavior on opacity {
              NumberAnimation {
                duration: root.characterPoseFadeDuration
                easing.type: Easing.InOutSine
              }
            }
          }

        }

        MouseArea {
          id: characterMouse

          property real pressSceneX: 0
          property real pressSceneY: 0
          property real startX: 0
          property real startY: 0
          property bool moved: false

          anchors.fill: parent
          z: 20
          enabled: root.phase !== "menu"
          hoverEnabled: true
          cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
          preventStealing: true

          onPressed: function(mouse) {
            var scenePosition = hexonCoach.mapToItem(overlay.contentItem, mouse.x, mouse.y)
            fallAnimation.stop()
            pressSceneX = scenePosition.x
            pressSceneY = scenePosition.y
            startX = hexonCoach.x
            startY = hexonCoach.y
            moved = false
            hexonCoach.userX = startX
            hexonCoach.userY = startY
            hexonCoach.userPlaced = true
          }

          onPositionChanged: function(mouse) {
            if (!pressed) return
            var scenePosition = hexonCoach.mapToItem(overlay.contentItem, mouse.x, mouse.y)
            var deltaX = scenePosition.x - pressSceneX
            var deltaY = scenePosition.y - pressSceneY
            if (Math.abs(deltaX) > 4 || Math.abs(deltaY) > 4) moved = true
            hexonCoach.userX = Math.max(
              18,
              Math.min(overlay.width - hexonCoach.width - 18, startX + deltaX)
            )
            hexonCoach.userY = Math.max(
              28,
              Math.min(hexonCoach.bottomY, startY + deltaY)
            )
          }

          onReleased: {
            if (moved) {
              hexonCoach.interactionMessage = "WHEE!"
              interactionMessageTimer.restart()
              if (root.reducedMotion) hexonCoach.userY = hexonCoach.bottomY
              else fallAnimation.restart()
            } else {
              hexonCoach.userPlaced = false
              hexonCoach.interactionMessage = "BEEP BOOP!"
              interactionMessageTimer.restart()
              if (!root.reducedMotion) clickAnimation.restart()
            }
          }

          onCanceled: {
            if (hexonCoach.userPlaced) {
              if (root.reducedMotion) hexonCoach.userY = hexonCoach.bottomY
              else fallAnimation.restart()
            }
          }
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

                function syncCharacterTarget() {
                  if (selected) overlay.updateMenuSelectionTarget(lessonCard, index)
                }

                onSelectedChanged: if (selected) Qt.callLater(syncCharacterTarget)
                onXChanged: if (selected) Qt.callLater(syncCharacterTarget)
                onYChanged: if (selected) Qt.callLater(syncCharacterTarget)
                onWidthChanged: if (selected) Qt.callLater(syncCharacterTarget)
                onHeightChanged: if (selected) Qt.callLater(syncCharacterTarget)
                Component.onCompleted: if (selected) Qt.callLater(syncCharacterTarget)

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
                    Text {
                      text: root.lessonShortcutLabel(lessonCard.modelData)
                      color: root.accent
                      font.family: "monospace"
                      font.pixelSize: 11
                      font.weight: Font.DemiBold
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
        opacity: root.lessonContentOpacity
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
        opacity: root.lessonContentOpacity
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
                if (root.currentStepIsTour && root.currentStep && root.currentStep.detail)
                  return root.currentStep.detail
                return root.currentStep ? root.currentStep.instruction : ""
              }
            }

            Text {
              visible: Boolean(root.phase === "waiting" && !root.currentStepIsTour && root.currentStep && root.currentStep.detail)
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
          visible: Boolean(root.phase === "waiting" && root.currentStep && !root.currentStepIsTour && root.currentStep.keys.length === 0)
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
            onClicked: root.runStepAction("action")
          }
        }
      }

      RowLayout {
        id: controls
        z: 100
        visible: root.phase !== "loading"
        anchors {
          top: parent.top
          right: parent.right
          topMargin: 42
          rightMargin: 24
        }
        spacing: 8

        Rectangle {
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
            onClicked: root.requestHelpAction()
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
        opacity: root.lessonContentOpacity
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
