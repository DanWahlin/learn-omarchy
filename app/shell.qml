import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
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
  readonly property string characterOverride: String(Quickshell.env("LEARN_OMARCHY_CHARACTER") || "").toLowerCase()
  readonly property string settingsPath: stateHome + "/learn-omarchy/settings.json"
  property string characterName: characterOverride !== "" ? characterOverride : "hexon"
  property string savedCharacter: ""
  property bool settingsResolved: false
  property bool progressResolved: false
  // Set once the tour has been opened automatically, so a skipped tour is not
  // forced again; completion itself lives in the progress file like any lesson.
  property bool tourSeen: false
  property var characterIndex: []
  property int characterPick: 0
  // "first-run" asks for a coach and proceeds on pick; "settings" stays open.
  property string settingsMode: "settings"
  property bool resetConfirmPending: false
  property bool resetJustDone: false
  readonly property string characterAssetRoot: appRoot + "/assets/characters/" + characterName
  // Per-character presentation from assets/characters/<name>/character.json.
  property var characterConfig: ({})
  readonly property string characterDisplayName: String(characterConfig.displayName || characterName.toUpperCase())
  readonly property bool characterFlames: characterConfig.flames !== false
  // Opening scene played when the tour starts: "rocket" lands and the coach
  // steps out of the hatch, or "tree" grows and the coach takes off from a
  // branch. Sprites are <prefix>-intro.png (plus -intro-open.png for the open
  // hatch); anchorX/anchorY give the doorway floor or the perch as fractions
  // of the sprite.
  readonly property var introConfig: characterConfig.intro && typeof characterConfig.intro === "object" ? characterConfig.intro : ({})
  readonly property string introKind: String(introConfig.kind || (characterFlames ? "rocket" : "tree"))
  readonly property real introAnchorX: Number(introConfig.anchorX) > 0 ? Number(introConfig.anchorX) : (introKind === "rocket" ? 0.5 : 0.84)
  readonly property real introAnchorY: Number(introConfig.anchorY) > 0 ? Number(introConfig.anchorY) : (introKind === "rocket" ? 0.7 : 0.63)

  // One expression per path so a coach switch never mixes the new folder
  // with the previous manifest's sprite prefix mid-update.
  function spriteSource(kind) {
    var prefix = characterConfig.prefix ? String(characterConfig.prefix) : characterName
    return appRoot + "/assets/characters/" + characterName + "/sprites/" + prefix + "-" + kind + ".png"
  }

  function colorLuminance(value) {
    var channels = [value.r, value.g, value.b]
    var weights = [0.2126, 0.7152, 0.0722]
    var total = 0
    for (var i = 0; i < channels.length; i++) {
      var v = channels[i]
      total += weights[i] * (v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4))
    }
    return total
  }

  function readableSecondaryColor(value, base) {
    var backgroundLight = colorLuminance(base)
    var destination = backgroundLight > 0.179 ? 0 : 1
    for (var i = 0; i <= 20; i++) {
      var amount = i / 20
      var candidate = Qt.rgba(value.r * (1 - amount) + destination * amount,
        value.g * (1 - amount) + destination * amount,
        value.b * (1 - amount) + destination * amount, 1)
      var light = colorLuminance(candidate)
      if ((Math.max(light, backgroundLight) + 0.05) / (Math.min(light, backgroundLight) + 0.05) >= 4.5) return candidate
    }
    return Qt.rgba(destination, destination, destination, 1)
  }

  function characterText(text) {
    return String(text || "").replace(/HEXON/g, characterDisplayName)
  }

  function characterChosen() {
    return characterOverride !== "" || savedCharacter !== ""
  }

  function loadCharacterIndex(raw) {
    try {
      var parsed = JSON.parse(String(raw || "{}"))
      var list = parsed && Array.isArray(parsed.characters) ? parsed.characters : []
      characterIndex = list.filter(function(entry) { return entry && typeof entry.id === "string" })
    } catch (error) {
      console.warn("learn-omarchy: character index couldn't be parsed:", error)
      characterIndex = []
    }
    syncCharacterPick()
  }

  function syncCharacterPick() {
    for (var i = 0; i < characterIndex.length; i++) {
      if (characterIndex[i].id === characterName) {
        characterPick = i
        return
      }
    }
    characterPick = 0
  }

  function loadSettings(raw) {
    try {
      var parsed = JSON.parse(String(raw || "{}"))
      savedCharacter = parsed && typeof parsed.character === "string" ? parsed.character.toLowerCase() : ""
      tourSeen = Boolean(parsed && parsed.tourSeen === true)
      audioEnabled = parsed.audioEnabled !== false
      speechEnabled = parsed.speechEnabled !== false
      effectsEnabled = parsed.effectsEnabled !== false
      speechVolume = boundedNumber(parsed.speechVolume, 80, 0, 100)
      effectsVolume = boundedNumber(parsed.effectsVolume, 45, 0, 100)
      speechRate = boundedNumber(parsed.speechRate, 1, 0.75, 1.5)
      motionReduced = parsed.motionReduced === true
      autoAdvance = parsed.autoAdvance !== false
      textScale = boundedNumber(parsed.textScale, 1, 1, 1.3)
    } catch (error) {
      console.warn("learn-omarchy: settings file couldn't be parsed:", error)
      savedCharacter = ""
      tourSeen = false
    }
    if (characterOverride === "" && savedCharacter !== "") applyCharacter(savedCharacter)
    settingsResolved = true
    if (phase === "menu" && lessonIndex < 0) {
      if (!characterChosen()) openCharacterPicker()
      else maybeAutoStartTour()
    }
  }

  function persistSettings() {
    settingsFile.setText(JSON.stringify({
      schemaVersion: 1,
      character: savedCharacter,
      tourSeen: tourSeen,
      audioEnabled: audioEnabled,
      speechEnabled: speechEnabled,
      effectsEnabled: effectsEnabled,
      speechVolume: speechVolume,
      effectsVolume: effectsVolume,
      speechRate: speechRate,
      motionReduced: motionReduced,
      autoAdvance: autoAdvance,
      textScale: textScale
    }, null, 2) + "\n")
  }

  // First run: open the tour straight away instead of the topic menu. Only
  // when progress is known, the tour was never completed, and it was never
  // auto-opened before.
  function maybeAutoStartTour() {
    if (!course || !settingsResolved || !progressResolved || tourSeen) return false
    if (phase !== "menu" || lessonIndex >= 0 || course.lessons.length === 0) return false
    if (completedLessons[course.lessons[0].id]) return false
    tourSeen = true
    persistSettings()
    startLesson(0)
    return true
  }

  function enterHome() {
    phase = "menu"
    selectedLessonIndex = firstIncompleteLessonIndex()
    setCharacterState("menu-point", "CHOOSE A LESSON")
    maybeAutoStartTour()
  }

  function applyCharacter(id) {
    var next = String(id || "").toLowerCase()
    if (next === "" || next === characterName) return
    characterConfig = {}
    characterName = next
    characterFile.reload()
    syncCharacterPick()
  }

  function chooseCharacter(id) {
    applyCharacter(id)
    savedCharacter = characterName
    persistSettings()
    if (phase === "settings" && settingsMode === "first-run") enterHome()
  }

  function openCharacterPicker() {
    openSettings("first-run")
  }

  function openSettings(mode) {
    if (phase === "loading" || phase === "error" || lessonTransitionRunning) return
    settingsReturnToLesson = false
    if (phase === "waiting" || phase === "highlight" || phase === "paused") {
      if (phase !== "paused" && !pauseLesson()) return
      settingsReturnToLesson = true
    }
    settingsMode = mode || "settings"
    resetConfirmPending = false
    syncCharacterPick()
    if (!settingsReturnToLesson) stopAudio()
    phase = "settings"
    setCharacterState("hidden", "")
  }

  function closeSettings() {
    if (phase !== "settings") return
    resetConfirmPending = false
    var resumeLesson = settingsReturnToLesson && currentLesson && currentStep
    settingsReturnToLesson = false
    if (resumeLesson) {
      phase = "paused"
      resumePausedLesson()
      return
    }
    if (!characterChosen()) {
      // Nothing picked yet: on first run Escape leaves the app; after a reset
      // the dialog turns back into the coach picker.
      if (settingsMode === "first-run") Qt.quit()
      else openSettings("first-run")
      return
    }
    enterHome()
  }

  function firstIncompleteLessonIndex() {
    if (!course) return 0
    for (var i = 0; i < course.lessons.length; i++) {
      if (!course.lessons[i].optional && !completedLessons[course.lessons[i].id]) return i
    }
    for (var j = 0; j < course.lessons.length; j++) {
      if (!completedLessons[course.lessons[j].id]) return j
    }
    return 0
  }

  function requestResetProgress() {
    if (!resetConfirmPending) {
      resetConfirmPending = true
      resetConfirmTimer.restart()
      return
    }
    resetConfirmTimer.stop()
    resetConfirmPending = false
    completedLessons = ({})
    stepResults = ({})
    stepCredits = ({})
    lessonBookmarks = ({})
    settingsReturnToLesson = false
    if (lessonIndex >= 0) {
      resetLessonRuntime()
      lessonIndex = -1
    }
    persistProgress()
    tourSeen = false
    // Forget the coach as well, so the next open starts like a fresh install.
    savedCharacter = ""
    persistSettings()
    resetJustDone = true
    resetDoneTimer.restart()
  }

  function moveCharacterPick(delta) {
    if (characterIndex.length === 0) return
    characterPick = Math.max(0, Math.min(characterIndex.length - 1, characterPick + delta))
  }

  function loadCharacterConfig(raw) {
    try {
      var parsed = JSON.parse(String(raw || "{}"))
      characterConfig = parsed && typeof parsed === "object" ? parsed : {}
    } catch (error) {
      console.warn("learn-omarchy: character manifest couldn't be parsed:", error)
      characterConfig = {}
    }
  }
  readonly property string progressPath: stateHome + "/learn-omarchy/progress.json"
  readonly property string themePath: stateHome + "/omarchy/current/theme"
  readonly property string themeNamePath: stateHome + "/omarchy/current/theme.name"
  property bool motionReduced: false
  readonly property bool reducedMotion: motionReduced ||
    Quickshell.env("LEARN_OMARCHY_REDUCED_MOTION") === "1"

  property var course: null
  property int lessonIndex: -1
  property int selectedLessonIndex: 0
  property real menuWheelRemainder: 0
  property real menuPointerX: NaN
  property real menuPointerY: NaN
  property int characterMenuColumn: 0
  property int stepIndex: 0
  property string phase: "loading"
  onPhaseChanged: {
    if (phase === "menu") {
      menuWheelRemainder = 0
      menuPointerX = NaN
      menuPointerY = NaN
    }
  }
  property string errorMessage: ""
  property var completedLessons: ({})
  property var progressByCourse: ({})
  property var progressDetails: ({})
  property var stepResults: ({})
  property var stepCredits: ({})
  property var lessonBookmarks: ({})
  property bool practiceMode: false
  property bool practiceHintVisible: false
  property bool stepAssisted: false
  property string pausedPhase: "waiting"
  property real pausedAt: 0
  property bool pausedCompletionPending: false
  property bool audioPaused: false
  property bool settingsReturnToLesson: false
  property string recoveryMessage: ""
  property string recoveryStepId: ""
  property string recoveryReturnStepId: ""
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
  property bool keyboardCaptureResetting: false
  property bool shortcutInhibitionActive: false
  property bool restoreKeyboardAfterAction: false
  property bool exerciseRunning: false
  property bool exerciseRestoreCapture: false
  property var swapBefore: null
  property string directionalKey: ""
  readonly property bool currentStepNeedsDirection: !!(currentStep && (currentStep.directionFromStep || currentStep.swapWithStep))
  readonly property var currentStepKeys: (currentStep ? currentStep.keys : []).map(function(key) {
    return currentStepNeedsDirection && directionalKey && ["LEFT", "RIGHT", "UP", "DOWN"].indexOf(key) !== -1
      ? directionalKey : key
  })
  property var barGeometry: []
  property bool barGeometryAvailable: true
  property string barGeometryTopology: ""
  property bool geometryProviderAvailable: true
  property real geometryProviderRetryAt: 0
  // The overlay holds the keyboard exclusively so shortcuts light up the
  // keycaps. The keyboard button (or IPC "keys") releases it to other
  // windows; the hint pill or the button takes it back.
  property bool keyboardExclusive: true
  signal requestKeyboardFocus()

  function setKeyboardExclusive(exclusive) {
    keyboardExclusive = Boolean(exclusive)
    if (keyboardExclusive) renewKeyboardCapture()
    else {
      keyboardCaptureTimer.stop()
      keyboardCaptureResetting = false
    }
  }

  function renewKeyboardCapture() {
    if (!keyboardExclusive || restoreKeyboardAfterAction || exerciseRunning) return
    // Commit None on its own frame before Exclusive. Item focus can remain
    // true after Hyprland moves keyboard focus to another desktop surface.
    keyboardCaptureResetting = true
    keyboardCaptureTimer.restart()
  }
  property string actionStepId: ""
  property string actionCompletionType: ""
  property int actionCompletionDelay: 250
  property bool audioEnabled: true
  property bool speechEnabled: true
  readonly property bool narrationEnabled: audioEnabled && speechEnabled && speechVolume > 0
  property bool effectsEnabled: true
  property int speechVolume: 80
  property int effectsVolume: 45
  property real speechRate: 1
  property real textScale: 1
  property bool autoAdvance: true
  property real highlightStartedAt: 0
  property bool completionNarrationDone: false
  property bool audioStopRequested: false
  property string audioProcessPath: ""
  property var audioPlaybackEvents: []
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
  property int outcomeGeneration: 0
  property int outcomeAttempts: 0
  property string outcomeAddress: ""
  property var outcomeExpected: null
  property int targetScreenId: -1
  property string targetLayerNamespace: ""
  property string targetLayerMonitor: ""
  // Windows the course itself launched in the current module (Hyprland
  // addresses, oldest first). Close steps only act on and accept these.
  property var tutorialWindows: []
  property var tutorialWindowsByStep: ({})
  property var tutorialWindowSnapshots: ({})
  property string windowLaunchToken: ""
  property bool windowOwnershipStopping: false
  property string pendingTutorialWindowAddress: ""
  property real shortcutArmedUntil: 0
  property real characterX: 0
  property real characterY: 0
  // True while the coach is sitting at his waiting spot beside the panel.
  property bool characterParked: false
  property int externalLayerTick: 0

  readonly property int windowGeometryMaxAttempts: 6
  readonly property int shortcutArmWindowMs: 8000
  readonly property int helpArmWindowMs: 10000
  readonly property int readingWordsPerMinute: 200

  readonly property int narrationRestMs: 900
  property int characterTravelDuration: reducedMotion ? 0 : 900

  property color accent: "#7aa2f7"
  property color foreground: "#a9b1d6"
  property color background: "#1a1b26"
  property color muted: "#8992b7"
  property color urgent: "#f7768e"
  property color instruction: "#e0af68"
  onReducedMotionChanged: characterTravelDuration = reducedMotion ? 0 : 900

  onSelectedLessonIndexChanged: {
    // The picker is a single column now; no lateral hop between cards.
    var nextColumn = 0
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
  readonly property bool currentStepIsPractice: Boolean(currentStep && currentStep.kind === "practice")
  readonly property bool currentStepClosesWindow: Boolean(currentStep &&
    Array.isArray(currentStep.completion.events) &&
    currentStep.completion.events.indexOf("closewindow") !== -1)
  readonly property bool currentStepHasNoVisibleTarget: currentStepClosesWindow || currentStepIsPractice ||
    Boolean(currentStep && currentStep.completion.windowState && currentStep.completion.windowState.specialWorkspace)
  readonly property bool currentTourTalks: currentStepIsTour && currentStep.pose === "talk"
  readonly property string tourRestingState: currentTourTalks ? "tour-talk" : "tour-point"
  readonly property string tourRestingMessage: currentTourTalks ? "HELLO!" : "LOOK HERE"
  readonly property int completedCount: {
    if (!course) return 0
    var count = 0
    for (var i = 0; i < course.lessons.length; i++) {
      if (completedLessons[course.lessons[i].id]) count++
    }
    return count
  }
  readonly property int coreLessonCount: course ? course.lessons.filter(function(lesson) { return !lesson.optional }).length : 0
  readonly property int coreCompletedCount: course ? course.lessons.filter(function(lesson) {
    return !lesson.optional && completedLessons[lesson.id]
  }).length : 0

  function colorWithAlpha(colorValue, alpha) {
    return Qt.rgba(colorValue.r, colorValue.g, colorValue.b, alpha)
  }

  function boundedNumber(value, fallback, minimum, maximum) {
    return typeof value === "number" && isFinite(value)
      ? Math.max(minimum, Math.min(maximum, value)) : fallback
  }

  function showRecovery(message, stepId) {
    restoreActionKeyboard()
    recoveryMessage = message
    recoveryStepId = stepId || ""
    console.warn("learn-omarchy:", message)
  }

  function recoverTutorialWindow() {
    if (!currentLesson || !recoveryStepId || lessonTransitionRunning) return
    for (var i = 0; i < currentLesson.steps.length; i++) {
      if (currentLesson.steps[i].id === recoveryStepId) {
        recoveryReturnStepId = currentStep.id
        beginLessonTransition("step", i)
        return
      }
    }
  }

  function recordStepResult(result) {
    if (!currentStep) return
    var next = Object.assign({}, stepResults)
    next[currentStep.id] = result
    stepResults = next
    if (["introduced", "assisted", "practiced"].indexOf(result) !== -1) {
      var credits = Object.assign({}, stepCredits)
      credits[currentStep.id] = true
      stepCredits = credits
    }
    persistProgress()
  }

  function lessonResultSummary(lesson) {
    var counts = { introduced: 0, assisted: 0, practiced: 0, skipped: 0, remaining: 0 }
    if (!lesson) return counts
    for (var i = 0; i < lesson.steps.length; i++) {
      var result = stepResults[lesson.steps[i].id]
      if (Object.prototype.hasOwnProperty.call(counts, result)) counts[result]++
      else counts.remaining++
    }
    return counts
  }

  function lessonFullyExplored(lesson) {
    if (!lesson) return false
    return lesson.steps.every(function(step) {
      return step.optional || stepCredits[step.id] === true ||
        ["introduced", "assisted", "practiced"].indexOf(stepResults[step.id]) !== -1
    })
  }

  function previousStep() {
    if (!currentLesson || stepIndex <= 0 || lessonTransitionRunning) return
    recoveryReturnStepId = ""
    cancelAction()
    stopAudio()
    beginLessonTransition("step", stepIndex - 1)
  }

  function pauseLesson() {
    if ((phase !== "waiting" && phase !== "highlight") || lessonTransitionRunning) return false
    if (actionRunning || windowGeometryPending || outcomeAddress !== "") {
      showRecovery("Wait for the current action to finish before pausing.")
      return false
    }
    pausedPhase = phase
    pausedAt = Date.now()
    pausedCompletionPending = layerCompletionFeedbackTimer.running || actionCompletionTimer.running
    completionTimer.stop()
    actionCompletionTimer.stop()
    tourAdvanceTimer.stop()
    layerCompletionFeedbackTimer.stop()
    characterHelpActionTimer.stop()
    characterHelpPointTimer.stop()
    clearActiveKeys()
    if (audioProcess.running && !audioStopRequested) {
      // Linux SIGSTOP/SIGCONT preserve mpv's playback position across a pause.
      if (Number(audioProcess.processId) > 0) audioProcess.signal(19)
      audioPaused = true
    }
    if (sfxProcess.running) sfxProcess.running = false
    cancelIntro()
    phase = "paused"
    return true
  }

  function resumePausedLesson() {
    if (phase !== "paused" || !currentStep) return
    if (pausedPhase === "highlight") highlightStartedAt += Date.now() - pausedAt
    phase = pausedPhase
    clearActiveKeys()
    if (phase === "waiting" && pausedCompletionPending) {
      pausedCompletionPending = false
      completeCurrentStep()
      return
    }
    var resumedAudio = false
    if (audioPaused && audioProcess.running &&
        (audioProcessPath === currentAudioPath() || audioProcessPath === completionAudioPath())) {
      if (Number(audioProcess.processId) > 0) audioProcess.signal(18)
      audioPaused = false
      resumedAudio = true
    } else if (audioPaused) {
      stopAudio()
    }
    if (phase === "highlight") {
      setCharacterState("target-point", "HERE IT IS!")
      if (!resumedAudio) {
        if (!completionNarrationDone && narrationEnabled && completionAudioPath() !== "") playCompletionNarration()
        else finishCompletionNarration()
      }
    } else {
      setCharacterState(currentStepIsTour ? tourRestingState : "coach", "YOUR TURN")
      if (!resumedAudio) {
        if (currentStepIsTour) beginTourNarration()
        else if (!practiceMode) playCurrentAudio(true)
      }
      if (currentStep.windowFromStep && currentTutorialWindow() === "") {
        showRecovery("The tutorial window was closed while the lesson was paused. Return to its launch activity to continue.", currentStep.windowFromStep)
      } else if (currentStep.completion.windowState && actionStepId === currentStep.id) requestOutcomeVerification()
    }
  }

  // Shared look for every panel, button, and keycap so the app reads as one
  // console rather than a collection of pills.
  readonly property color panelColor: colorWithAlpha(background, 0.96)
  readonly property color panelBorder: colorWithAlpha(foreground, 0.16)
  readonly property color subtleFill: colorWithAlpha(foreground, 0.06)
  readonly property color keyFace: Qt.lighter(background, 1.45)

  component UiPanel: Item {
    id: panel
    default property alias content: panelBody.data
    property real radius: 16
    property color stripe: "transparent"
    property color edge: root.panelBorder

    Rectangle {
      anchors.fill: parent
      anchors.margins: -12
      radius: panel.radius + 12
      color: Qt.rgba(0, 0, 0, 0.12)
    }
    Rectangle {
      anchors.fill: parent
      anchors.margins: -5
      radius: panel.radius + 5
      color: Qt.rgba(0, 0, 0, 0.26)
    }
    Rectangle {
      id: panelBody
      anchors.fill: parent
      radius: panel.radius
      color: root.panelColor
      border.color: panel.edge
      border.width: 1

      Rectangle {
        visible: panel.stripe.a > 0
        anchors.top: parent.top
        anchors.topMargin: 1
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - (panel.radius * 2)
        height: 3
        radius: 2
        color: panel.stripe
      }
    }
  }

  component UiButton: Rectangle {
    id: button
    property string label: ""
    // "primary" | "secondary" | "ghost" | "danger"
    property string kind: "secondary"
    property bool compact: false
    property string description: label
    signal clicked()
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: description
    Accessible.onPressAction: clicked()
    Keys.onPressed: function(event) {
      var plain = !(event.modifiers & (Qt.MetaModifier | Qt.ControlModifier | Qt.AltModifier | Qt.ShiftModifier))
      if (plain && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)) {
        clicked()
        event.accepted = true
      } else if (!plain || (event.key !== Qt.Key_Tab && event.key !== Qt.Key_Backtab)) root.handleKeyPressed(event)
    }
    Keys.onReleased: function(event) {
      if (root.phase === "waiting") root.updateActiveKeys(event, false)
    }
    readonly property bool hovered: buttonMouse.containsMouse
    readonly property bool primary: kind === "primary"
    readonly property bool danger: kind === "danger"
    readonly property bool ghost: kind === "ghost"

    implicitWidth: buttonLabel.implicitWidth + (compact ? 24 : 32)
    implicitHeight: compact ? 32 : 40
    radius: 9
    color: primary
      ? (hovered ? Qt.lighter(root.accent, 1.18) : root.accent)
      : danger
        ? root.colorWithAlpha(root.urgent, hovered ? 0.34 : 0.14)
        : ghost
          ? root.colorWithAlpha(root.foreground, hovered ? 0.16 : 0.06)
          : root.colorWithAlpha(root.accent, hovered ? 0.36 : 0.16)
    border.width: activeFocus ? 3 : 1
    border.color: primary
      ? root.accent
      : danger
        ? root.colorWithAlpha(root.urgent, 0.7)
        : ghost
          ? root.colorWithAlpha(root.foreground, 0.2)
          : root.colorWithAlpha(root.accent, 0.55)

    Behavior on color { ColorAnimation { duration: 110 } }

    Text {
      id: buttonLabel
      anchors.centerIn: parent
      text: button.label
      color: button.primary ? root.background : root.foreground
      font.family: "monospace"
      font.pixelSize: (button.compact ? 11 : 12) * root.textScale
      font.weight: Font.Bold
      font.letterSpacing: 1.1
    }

    MouseArea {
      id: buttonMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: button.clicked()
    }

    Rectangle {
      visible: button.hovered && button.description !== button.label
      z: 100
      anchors.top: parent.bottom
      anchors.topMargin: 6
      anchors.right: parent.right
      width: hintText.implicitWidth + 20
      height: hintText.implicitHeight + 14
      radius: 6
      color: root.background
      border.color: root.muted
      Text {
        id: hintText
        anchors.centerIn: parent
        text: button.description
        color: root.foreground
        font.pixelSize: 12
      }
    }
  }

  component PreferenceSlider: ColumnLayout {
    id: preference
    property string label: ""
    property string displayValue: ""
    property real value: 0
    property real minimum: 0
    property real maximum: 100
    property real step: 1
    signal adjusted(real value)
    spacing: 8

    Text {
      Layout.fillWidth: true
      text: preference.label + ": " + preference.displayValue
      color: root.foreground
      font.pixelSize: 13 * root.textScale
      wrapMode: Text.WordWrap
    }
    Controls.Slider {
      id: preferenceControl
      Layout.fillWidth: true
      Layout.preferredHeight: 32
      from: preference.minimum
      to: preference.maximum
      stepSize: preference.step
      value: preference.value
      Accessible.name: preference.label
      onMoved: preference.adjusted(value)
      background: Rectangle {
        implicitWidth: 160
        implicitHeight: 6
        x: preferenceControl.leftPadding
        y: preferenceControl.topPadding + preferenceControl.availableHeight / 2 - height / 2
        width: preferenceControl.availableWidth
        height: 6
        radius: 3
        color: root.subtleFill
        Rectangle {
          width: preferenceControl.visualPosition * parent.width
          height: parent.height
          color: root.accent
          radius: 3
        }
      }
      handle: Rectangle {
        implicitWidth: 20
        implicitHeight: 20
        x: preferenceControl.leftPadding + preferenceControl.visualPosition * (preferenceControl.availableWidth - width)
        y: preferenceControl.topPadding + preferenceControl.availableHeight / 2 - height / 2
        width: 20
        height: 20
        radius: 10
        color: root.foreground
        border.color: root.accent
        border.width: preferenceControl.activeFocus ? 4 : 1
      }
    }
  }

  component Keycap: Item {
    id: keycap
    property string label: ""
    property bool active: false
    property bool small: false
    readonly property bool isPlus: label === "+"

    implicitWidth: isPlus ? (small ? 14 : 26) : keyText.implicitWidth + (small ? 14 : 36)
    implicitHeight: small ? 22 : 54
    scale: active ? 1.06 : 1
    Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

    Rectangle {
      // Keycap edge under the face for a little depth.
      visible: !keycap.isPlus
      anchors.fill: parent
      radius: keycap.small ? 5 : 9
      color: keycap.active ? Qt.darker(root.accent, 1.5) : root.colorWithAlpha(root.foreground, 0.28)
    }
    Rectangle {
      visible: !keycap.isPlus
      anchors.fill: parent
      anchors.bottomMargin: keycap.small ? 2 : 4
      radius: keycap.small ? 5 : 9
      color: keycap.active ? root.accent : root.keyFace
      border.color: keycap.active ? root.colorWithAlpha(root.foreground, 0.75) : root.colorWithAlpha(root.foreground, 0.22)
      border.width: 1
      Behavior on color { ColorAnimation { duration: 90 } }
    }
    Text {
      id: keyText
      anchors.centerIn: parent
      anchors.verticalCenterOffset: keycap.isPlus ? 0 : -(keycap.small ? 1 : 2)
      text: keycap.label
      textFormat: Text.PlainText
      color: keycap.isPlus ? root.muted : (keycap.active ? root.background : root.foreground)
      font.family: "monospace"
      font.pixelSize: (keycap.small ? 11 : 17) * root.textScale
      font.weight: Font.Bold
    }
  }

  function setCharacterState(state, message) {
    characterState = state
    characterMessage = message || ""
    characterCue++
  }

  function beginLessonTransition(kind, nextStepIndex) {
    if (lessonTransitionRunning) return
    completionTimer.stop()
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
      if (targetMonitorGeometry) targetScreenId = Number(targetMonitorGeometry.id)
      highlightStartedAt = Date.now()
      completionNarrationDone = false
      setCharacterState("celebrate", "NICE WORK!")
      characterTargetFlyTimer.restart()
      playCompletionNarration()
      if (!narrationEnabled || completionAudioPath() === "") finishCompletionNarration()
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
        setCharacterState("celebrate", lessonFullyExplored(currentLesson) ? "MODULE COMPLETE!" : "MODULE EXPLORED")
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

  function highlightWidth(highlight) {
    if (!highlight) return 0
    if (highlight.target === "workspace") return 28
    if (highlight.dynamic === "workspaces") return 12 + (barWorkspaceCount() * 28)
    return highlight.width
  }

  function estimatedTargetGeometry(highlight, screenWidth, screenHeight, slot) {
    if (!highlight || screenWidth <= 0 || screenHeight <= 0) return null
    var reference = course && course.referenceViewport || { width: 1920, height: 1200 }
    var scaleX = screenWidth / reference.width
    var scaleY = screenHeight / reference.height
    var width = Math.min(screenWidth, highlightWidth(highlight) * scaleX)
    var height = Math.min(screenHeight, highlight.height * scaleY)
    if (highlight.shape === "circle") {
      width = Math.min(screenWidth, screenHeight, highlight.width * Math.min(scaleX, scaleY))
      height = width
    }
    var anchor = String(highlight.anchor || "center")
    var offsetX = (highlight.x + (highlight.target === "workspace" ? slot * 28 : 0)) * scaleX
    var offsetY = highlight.y * scaleY
    var x = anchor.indexOf("left") !== -1 ? offsetX
      : anchor.indexOf("right") !== -1 ? screenWidth - width + offsetX
      : (screenWidth - width) / 2 + offsetX
    var y = anchor.indexOf("top") !== -1 ? offsetY
      : anchor.indexOf("bottom") !== -1 ? screenHeight - height + offsetY
      : (screenHeight - height) / 2 + offsetY
    return { x: Math.max(0, Math.min(screenWidth - width, x)),
      y: Math.max(0, Math.min(screenHeight - height, y)), width: width, height: height, estimated: true }
  }

  function requestBarGeometry() {
    if (barGeometryProcess.running || !currentStep) return
    var highlight = currentStep.highlight
    if (!(highlight.target === "workspace" || highlight.target === "panel" || highlight.barWidgets)) return
    var provider = geometryProviderAvailable || Date.now() >= geometryProviderRetryAt
    if (!provider && Quickshell.screens.length !== 1) return
    barGeometryProcess.requestScreens = geometryScreens()
    barGeometryProcess.providerRequest = provider
    barGeometryProcess.command = provider
      ? ["omarchy-shell", "learnGeometry", "snapshot"]
      : ["omarchy-shell", "shell", "debugBarGeometry"]
    barGeometryProcess.running = true
  }

  function geometryScreens() {
    return Quickshell.screens.map(function(screen) {
      return { name: screen.name, width: screen.width, height: screen.height, x: screen.x, y: screen.y }
    }).sort(function(a, b) { return String(a.name).localeCompare(String(b.name)) })
  }

  function finishBarGeometry(exitCode, raw, screens, provider) {
    if (JSON.stringify(screens) !== JSON.stringify(geometryScreens())) return
    if (provider) {
      if (exitCode === 0 && parseProviderGeometry(raw, screens)) {
        geometryProviderAvailable = true
        return
      }
      geometryProviderAvailable = false
      geometryProviderRetryAt = Date.now() + 30000
      barGeometry = []
      Qt.callLater(requestBarGeometry)
    } else if (exitCode === 0) {
      parseBarGeometry(raw, screens)
    } else {
      barGeometry = []
      barGeometryAvailable = false
      console.warn("learn-omarchy: bar measurement request failed; showing estimates")
    }
  }

  function validMeasuredWidget(widget) {
    return widget && typeof widget.id === "string" &&
      ["x", "y", "width", "height"].every(function(key) {
        return typeof widget[key] === "number" && isFinite(widget[key])
      }) && widget.width >= 0 && widget.height >= 0
  }

  function parseProviderGeometry(raw, screens) {
    try {
      var snapshot = JSON.parse(raw)
      if (!snapshot || snapshot.version !== 1 || !Array.isArray(snapshot.screens)) throw new Error("unsupported geometry snapshot")
      var widgets = []
      var seen = {}
      for (var output of snapshot.screens) {
        var screen = screens.find(function(entry) { return entry.name === output.name })
        if (!screen || seen[output.name] || output.width !== screen.width || output.height !== screen.height ||
            !Array.isArray(output.widgets)) throw new Error("geometry output doesn't match the current screen layout")
        seen[output.name] = true
        for (var widget of output.widgets) {
          if (!validMeasuredWidget(widget)) throw new Error("invalid measured widget")
          if (widget.workspaceId !== undefined && (!Number.isInteger(widget.workspaceId) || widget.workspaceId < 1)) {
            throw new Error("invalid measured workspace")
          }
          widgets.push(Object.assign({}, widget, { screenName: output.name }))
        }
      }
      barGeometry = widgets
      barGeometryTopology = JSON.stringify(screens)
      barGeometryAvailable = true
      return true
    } catch (error) {
      barGeometry = []
      console.warn("learn-omarchy: monitor-aware geometry unavailable:", error)
      return false
    }
  }

  function parseBarGeometry(raw, requestScreens) {
    try {
      var widgets = JSON.parse(raw)
      if (!Array.isArray(widgets)) throw new Error("bar geometry wasn't a list")
      var screens = requestScreens || geometryScreens()
      if (screens.length !== 1 || JSON.stringify(screens) !== JSON.stringify(geometryScreens())) {
        barGeometry = []
        return
      }
      for (var widget of widgets) {
        if (!validMeasuredWidget(widget)) throw new Error("invalid bar widget geometry")
      }
      // Legacy records omit the bar window's screen-edge offset (notably on
      // bottom/right bars), so don't promote these coordinates to exact targets.
      barGeometry = widgets.map(function(widget) {
        return Object.assign({}, widget, { screenName: screens[0].name, estimated: true })
      })
      barGeometryTopology = JSON.stringify(screens)
      barGeometryAvailable = true
    } catch (error) {
      barGeometry = []
      barGeometryAvailable = false
      console.warn("learn-omarchy: measured bar geometry unavailable; using course estimates:", error)
    }
  }

  function barTargetGeometry(highlight, slot, requestedScreen, viewportWidth, viewportHeight) {
    if (!highlight || barGeometryTopology !== JSON.stringify(geometryScreens())) return null
    var screen = requestedScreen || (Quickshell.screens.length === 1 ? Quickshell.screens[0] : null)
    if (!screen) return null
    var screenWidgets = barGeometry.filter(function(widget) {
      return widget.screenName === screen.name && widget.visible && widget.itemVisible && widget.width > 0 && widget.height > 0
    })
    var exactWorkspace = highlight.target === "workspace" ? screenWidgets.find(function(widget) {
      return widget.workspaceId === (highlight.workspaceId || currentWorkspaceId())
    }) : null
    var panelId = highlight.target === "panel" && currentStep && currentStep.completion.namespace
      ? "panel:" + currentStep.completion.namespace : ""
    var exactPanel = panelId !== "" ? screenWidgets.find(function(widget) { return widget.id === panelId }) : null
    var ids = highlight.target === "workspace" ? ["omarchy.workspaces"] : highlight.barWidgets
    var widgets = exactPanel ? [exactPanel] : exactWorkspace ? [exactWorkspace] : screenWidgets.filter(function(widget) {
      return ids && ids.indexOf(widget.id) !== -1
    })
    if (!widgets.length) return null
    var left = Math.min.apply(null, widgets.map(function(widget) { return widget.x }))
    var top = Math.min.apply(null, widgets.map(function(widget) { return widget.y }))
    var right = Math.max.apply(null, widgets.map(function(widget) { return widget.x + widget.width }))
    var bottom = Math.max.apply(null, widgets.map(function(widget) { return widget.y + widget.height }))
    var interpolateWorkspace = highlight.target === "workspace" && !exactWorkspace
    var estimated = interpolateWorkspace || widgets.some(function(widget) { return widget.estimated === true })
    if (interpolateWorkspace) {
      var cell = (right - left) / barWorkspaceCount()
      var size = Math.min(cell, bottom - top)
      left += slot * cell + (cell - size) / 2
      top += (bottom - top - size) / 2
      right = left + size
      bottom = top + size
    }
    var rect = projectWindowGeometry({ at: [left, top], size: [right - left, bottom - top] },
      { x: 0, y: 0, width: screen.width, height: screen.height, scale: 1, transform: 0 },
      viewportWidth || screen.width, viewportHeight || screen.height)
    if (rect && estimated) rect.estimated = true
    if (rect && exactPanel) rect.panel = true
    return rect
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
    if (phase !== "waiting" || !currentStep) return
    if (currentStep.completion.type === "hyprland-workspace-is") {
      if (currentWorkspaceId() === Number(currentStep.completion.id)) completeCurrentStep()
      else if (++workspaceCheckAttempts < 5) workspaceCompletionTimer.restart()
      return
    }
    if (currentStep.completion.type !== "hyprland-workspace-change" || workspaceStartId < 0) return
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
    if (!currentStep || !Array.isArray(currentStepKeys)) return expected
    for (var i = 0; i < currentStepKeys.length; i++) {
      var key = String(currentStepKeys[i]).toUpperCase()
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
      // Keycaps acknowledge individual keys; celebrate only the verified outcome.
      return
    } else {
      setCharacterState("incorrect", "TRY THE HIGHLIGHTED KEYS")
      characterReactionTimer.interval = 680
    }
    characterReactionTimer.restart()
  }

  // The tour's opening scene. startLesson asks for it; the first tour step
  // plays it before the coach flies to the welcome stop. Stages: "arrive"
  // (rocket descends / tree grows), "reveal" (coach appears), "exit" (coach
  // steps out of the rocket), "launch" (coach takes off, scene fades).
  property bool introRequested: false
  property bool introActive: false
  property string introStage: ""
  // Descent and liftoff share this duration so the ship leaves as it arrived.
  readonly property int introRocketTravelMs: 1600
  // Fades the instruction panel away while the scene owns the bottom of the screen.
  property real introPanelOpacity: introActive ? 0 : 1

  function startIntro() {
    setCharacterState("intro", "")
    // The layer surface can still be settling its size right after launch;
    // give it a moment so the landing spot is measured against the final height.
    introStartTimer.restart()
  }

  function beginIntroScene() {
    if (phase !== "waiting" || !currentStepIsTour || characterState !== "intro") return
    introActive = true
    introStage = "arrive"
    introTimer.interval = introKind === "rocket" ? 2000 : 1100
    introTimer.restart()
  }

  function cancelIntro() {
    introStartTimer.stop()
    introTimer.stop()
    introLandTimer.stop()
    introRequested = false
    introActive = false
    introStage = ""
  }

  function skipIntroScene() {
    if (phase !== "waiting" || (!introActive && characterState !== "intro")) return
    cancelIntro()
    startCharacterStep()
  }

  function advanceIntro() {
    if (!introActive || phase !== "waiting" || !currentStepIsTour) {
      cancelIntro()
      return
    }
    if (introStage === "arrive") {
      introStage = "reveal"
      setCharacterState("intro-stand", "HELLO!")
      introTimer.interval = introKind === "rocket" ? 800 : 1500
    } else if (introStage === "reveal" && introKind === "rocket") {
      // Fly out of the hatch and land beside the pad.
      introStage = "exit"
      setCharacterState("intro-exit", "")
      introLandTimer.restart()
      introTimer.interval = 1600
    } else if (introStage === "reveal" || introStage === "exit") {
      // Rocket: the ship lifts off at the pace it came in while the coach
      // watches from beside the pad, so he never crosses its path.
      // Tree: the coach takes off straight away.
      introStage = "launch"
      if (introKind === "rocket") {
        introTimer.interval = introRocketTravelMs + 150
      } else {
        setCharacterState("tour-fly", "FOLLOW ME")
        characterTourArrivalTimer.restart()
        introTimer.interval = 950
      }
    } else if (introStage === "launch") {
      // Ship gone: now the coach heads for the welcome stop as the scene fades.
      introStage = "clear"
      if (introKind === "rocket") {
        setCharacterState("tour-fly", "FOLLOW ME")
        characterTourArrivalTimer.restart()
      }
      introTimer.interval = 650
    } else {
      introActive = false
      introStage = ""
      // The coach has been waiting at the welcome stop; now he can talk.
      if (characterState === tourRestingState) beginTourNarration()
      return
    }
    introTimer.restart()
  }

  function startCharacterStep() {
    if (currentStepIsTour) {
      if (introRequested && !reducedMotion) {
        introRequested = false
        startIntro()
        return
      }
      if (reducedMotion) {
        setCharacterState(tourRestingState, tourRestingMessage)
        Qt.callLater(beginTourNarration)
      } else {
        setCharacterState("tour-fly", "FOLLOW ME")
        characterTourArrivalTimer.restart()
      }
      return
    }
    if (reducedMotion) {
      setCharacterState("coach", "YOUR TURN")
      if (!practiceMode) Qt.callLater(playCurrentAudio)
    } else if (characterParked) {
      // Already beside the panel (Skip, or one hotkey step after another):
      // a flight would just be the flying pose hovering in place, which
      // reads as a false dash sideways. A short landing bounce is enough.
      setCharacterState("step-settle", "READY")
      characterTravelSettleTimer.restart()
    } else {
      setCharacterState("step-fly", "ON MY WAY!")
      characterStepArrivalTimer.restart()
    }
    if (!practiceMode && !reducedMotion) playCurrentAudio(true)
  }

  function tourFallbackDuration() {
    var completion = currentStep ? currentStep.completion : null
    var text = currentStep ? currentStep.instruction + " " + (currentStep.detail || "") : ""
    return Math.max(readingDuration(text), Number(completion && completion.durationMs || 0))
  }

  function readingDuration(text) {
    var words = String(text || "").trim().split(/\s+/).filter(function(word) { return word !== "" }).length
    return Math.max(2200, 800 + Math.ceil(words * 60000 / readingWordsPerMinute))
  }

  function tourAdvanceDelay() {
    var completion = currentStep ? currentStep.completion : null
    return Math.max(100, Number(completion && completion.delayMs || 900))
  }

  function beginTourNarration() {
    if (phase !== "waiting" || !currentStepIsTour) return
    if (narrationEnabled && currentAudioPath() !== "") {
      playCurrentAudio(true)
      return
    }
    if (autoAdvance) {
      tourAdvanceTimer.interval = tourFallbackDuration()
      tourAdvanceTimer.restart()
    }
  }

  function scheduleTourAdvance() {
    if (phase !== "waiting" || !currentStepIsTour || !autoAdvance) return
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
    if (key === Qt.Key_Left) return "LEFT"
    if (key === Qt.Key_Right) return "RIGHT"
    if (key === Qt.Key_Up) return "UP"
    if (key === Qt.Key_Down) return "DOWN"
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
      checkExpectedCombo()
    }
  }

  function usesWindowActivation() {
    return Boolean(
      currentStep &&
      currentStep.completion &&
      currentStep.completion.type === "hyprland-window-activated"
    )
  }

  // Steps verified by a generic Hyprland event only count the event once the
  // taught keys (or Help) have been seen, so unrelated desktop activity
  // doesn't complete them.
  function usesArmedDetection() {
    return Boolean(
      currentStep &&
      currentStep.completion &&
      (currentStep.completion.type === "hyprland-window-activated" ||
        currentStep.completion.type === "hyprland-event")
    )
  }

  function armShortcutDetection(keys) {
    if (phase !== "waiting" || !usesArmedDetection()) return
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
    if (!usesArmedDetection()) return
    shortcutArmedUntil = Math.max(shortcutArmedUntil, Date.now() + helpArmWindowMs)
  }

  function windowDetectionArmed() {
    if (!usesArmedDetection()) return false
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
    stopWindowOwnership()
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
    pendingTutorialWindowAddress = ""
    shortcutArmedUntil = 0
    targetLayerNamespace = ""
    targetLayerMonitor = ""
  }

  function requestPanelGeometry(namespace) {
    targetLayerNamespace = namespace
    if (layerGeometryProcess.running) return
    layerGeometryProcess.requestGeneration = windowGeometryGeneration
    layerGeometryProcess.running = true
  }

  function logicalMonitorSize(monitor) {
    var scale = Number(monitor.scale) > 0 ? Number(monitor.scale) : 1
    var transform = Number(monitor.transform) || 0
    var logicalWidth = Number(monitor.width) / scale
    var logicalHeight = Number(monitor.height) / scale
    if (transform % 2 === 1) return { width: logicalHeight, height: logicalWidth }
    return { width: logicalWidth, height: logicalHeight }
  }

  function projectWindowGeometry(windowData, monitor, screenWidth, screenHeight) {
    if (!windowData || !monitor || screenWidth <= 0 || screenHeight <= 0) return null
    var logical = logicalMonitorSize(monitor)
    if (!(logical.width > 0 && logical.height > 0)) return null
    var scaleX = screenWidth / logical.width
    var scaleY = screenHeight / logical.height
    var x = (windowData.at[0] - monitor.x) * scaleX
    var y = (windowData.at[1] - monitor.y) * scaleY
    var right = Math.min(screenWidth, x + windowData.size[0] * scaleX)
    var bottom = Math.min(screenHeight, y + windowData.size[1] * scaleY)
    x = Math.max(0, x)
    y = Math.max(0, y)
    if (!(right > x && bottom > y)) return null
    return { x: x, y: y, width: right - x, height: bottom - y }
  }

  function panelSurfaceIsFullscreen(layer, monitor) {
    var size = logicalMonitorSize(monitor)
    return Number(layer.size[0]) >= size.width - 2 &&
      Number(layer.size[1]) >= size.height - 2
  }

  function parseLayerGeometry(raw, generation) {
    if (generation !== windowGeometryGeneration || targetLayerNamespace === "") return
    var data
    try {
      data = JSON.parse(raw)
    } catch (error) {
      console.warn("learn-omarchy: panel geometry unavailable; using course estimate:", error)
      return
    }
    var candidates = []
    for (var monitorName in data) {
      if (!data[monitorName] || typeof data[monitorName] !== "object") continue
      var layers = data[monitorName].levels || data[monitorName].layers || {}
      for (var level in layers) {
        var entries = layers[level]
        if (!Array.isArray(entries)) continue
        for (var i = 0; i < entries.length; i++) {
          var layer = entries[i]
          if (!layer || layer.namespace !== targetLayerNamespace ||
              !(Number(layer.w) > 0 && Number(layer.h) > 0) ||
              !isFinite(Number(layer.x)) || !isFinite(Number(layer.y))) continue
          candidates.push({ monitorName: monitorName, layer: layer })
        }
      }
    }
    var preferred = targetLayerMonitor || (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "")
    var candidate = candidates.find(function(entry) { return entry.monitorName === preferred })
    if (!candidate && candidates.length === 1) candidate = candidates[0]
    if (candidate) {
      var selectedLayer = candidate.layer
      targetLayerMonitor = candidate.monitorName
      targetWindowGeometry = { at: [Number(selectedLayer.x), Number(selectedLayer.y)],
        size: [Number(selectedLayer.w), Number(selectedLayer.h)], monitor: -1 }
      if (!monitorGeometryProcess.running) {
        monitorGeometryProcess.requestGeneration = generation
        monitorGeometryProcess.running = true
      }
      windowGeometryRefreshTimer.restart()
      if (phase === "waiting" && currentStep && actionStepId === currentStep.id &&
          !layerCompletionFeedbackTimer.running) confirmDetectedShortcut()
      return
    }
    if (candidates.length > 1) console.warn("learn-omarchy: panel monitor is ambiguous; showing estimates")
    targetWindowGeometry = null
    targetMonitorGeometry = null
  }

  function requestOutcomeVerification() {
    if (phase !== "waiting" || !currentStep || !currentStep.completion.windowState) return
    var address = currentTutorialWindow()
    if (address === "") {
      showRecovery("The tutorial window is missing. Return to its launch activity before trying again.", currentStep.windowFromStep)
      return
    }
    outcomeAddress = address
    outcomeExpected = currentStep.completion.windowState
    outcomeAttempts = 0
    outcomeGeneration++
    queryOutcome()
  }

  function queryOutcome() {
    if (outcomeAddress === "" || phase !== "waiting") return
    if (outcomeProcess.running) {
      outcomeRetryTimer.restart()
      return
    }
    outcomeProcess.requestGeneration = outcomeGeneration
    outcomeProcess.running = true
  }

  function matchesWindowState(client, expected) {
    if (!client || client.mapped === false ||
        (client.hidden === true && !expected.specialWorkspace)) return false
    if (expected.specialWorkspace !== undefined &&
        (!client.workspace || client.workspace.name !== "special:" + expected.specialWorkspace)) return false
    if (expected.workspace !== undefined &&
        (!client.workspace || Number(client.workspace.id) !== Number(expected.workspace))) return false
    if (expected.floating !== undefined && (typeof client.floating !== "boolean" || client.floating !== expected.floating)) return false
    if (expected.fullscreen !== undefined && (typeof client.fullscreen !== "number" || (client.fullscreen > 0) !== expected.fullscreen)) return false
    if (expected.focused !== undefined && (typeof client.focusHistoryID !== "number" || (client.focusHistoryID === 0) !== expected.focused)) return false
    if (expected.focused === true && expected.workspace !== undefined &&
        currentWorkspaceId() !== Number(expected.workspace)) return false
    return true
  }

  function parseOutcome(raw, generation) {
    if (generation !== outcomeGeneration || outcomeAddress === "" || phase !== "waiting") return
    var clients
    try {
      clients = JSON.parse(raw)
      if (!Array.isArray(clients)) throw new Error("clients response wasn't a list")
    } catch (error) {
      showRecovery("Couldn't read the window state. Try the activity again. " + error)
      outcomeAddress = ""
      return
    }
    var client = null
    for (var i = 0; i < clients.length; i++) {
      if (clients[i] && normalizedWindowAddress(clients[i].address) === outcomeAddress) client = clients[i]
    }
    var pairSwapped = true
    if (outcomeExpected.swapped) {
      var peer = clients.find(function(item) { return item && swapBefore && normalizedWindowAddress(item.address) === swapBefore.peer })
      pairSwapped = Boolean(swapBefore && client && peer && Array.isArray(client.at) && Array.isArray(peer.at) &&
        client.at[0] === swapBefore.peerAt[0] && client.at[1] === swapBefore.peerAt[1] &&
        peer.at[0] === swapBefore.firstAt[0] && peer.at[1] === swapBefore.firstAt[1])
    }
    if (pairSwapped && matchesWindowState(client, outcomeExpected)) {
      outcomeAddress = ""
      if (outcomeExpected.specialWorkspace) {
        targetWindowGeometry = null
        targetMonitorGeometry = null
        restoreActionKeyboard()
        confirmDetectedShortcut()
        return
      }
      targetWindowAddress = normalizedWindowAddress(client.address)
      windowGeometryPending = true
      windowGeometryGeneration++
      targetWindowGeometry = client
      if (!monitorGeometryProcess.running) {
        monitorGeometryProcess.requestGeneration = windowGeometryGeneration
        monitorGeometryProcess.running = true
      }
      else windowGeometryRetryTimer.restart()
      return
    }
    if (++outcomeAttempts < windowGeometryMaxAttempts) {
      outcomeRetryTimer.restart()
    } else {
      outcomeAddress = ""
      clearActiveKeys()
      showRecovery("The expected window change hasn't happened. Try again, or return to the tutorial window's launch activity.", currentStep.windowFromStep)
    }
  }

  function captureStepStartWindow() {
    if (!usesWindowActivation()) return
    if (stepStartWindowProcess.running) return
    stepStartWindowProcess.requestGeneration = windowGeometryGeneration
    stepStartWindowProcess.running = true
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
    showRecovery("Couldn't locate the expected application window. Try the launch again. " + reason)
    resetWindowTarget()
    clearActiveKeys()
  }

  function rememberTutorialWindow(address, stepId) {
    var normalized = normalizedWindowAddress(address)
    if (normalized === "" || tutorialWindows.indexOf(normalized) !== -1) return
    tutorialWindows = tutorialWindows.concat([normalized])
    var next = Object.assign({}, tutorialWindowsByStep)
    next[stepId] = normalized
    tutorialWindowsByStep = next
  }

  function forgetTutorialWindow(address) {
    var normalized = normalizedWindowAddress(address)
    if (tutorialWindows.indexOf(normalized) === -1) return
    tutorialWindows = tutorialWindows.filter(function(entry) { return entry !== normalized })
    var next = {}
    for (var stepId in tutorialWindowsByStep) {
      if (tutorialWindowsByStep[stepId] !== normalized) next[stepId] = tutorialWindowsByStep[stepId]
    }
    tutorialWindowsByStep = next
    var snapshots = Object.assign({}, tutorialWindowSnapshots)
    delete snapshots[normalized]
    tutorialWindowSnapshots = snapshots
  }

  function currentTutorialWindow() {
    if (!currentStep || !currentStep.windowFromStep) return ""
    var address = tutorialWindowsByStep[currentStep.windowFromStep] || ""
    return tutorialWindows.indexOf(address) !== -1 ? address : ""
  }

  function finishWindowDetection(windowData, monitorData) {
    if (windowData && clientGeometryReady(windowData) && windowLaunchToken !== "" &&
        normalizedWindowAddress(windowData.address) === pendingTutorialWindowAddress) {
      if (windowOwnershipProcess.running || windowOwnershipStopping) {
        windowGeometryRetryTimer.restart()
        return
      }
      targetWindowGeometry = windowData
      targetMonitorGeometry = monitorData
      windowOwnershipProcess.requestGeneration = windowGeometryGeneration
      windowOwnershipProcess.requestToken = windowLaunchToken
      windowOwnershipProcess.command = ["node", appRoot + "/tools/verify-window-owner.mjs",
        String(windowData.pid), windowLaunchToken]
      windowOwnershipProcess.running = true
      return
    }
    completeWindowDetection(windowData, monitorData)
  }

  function finishWindowOwnership(exitCode, generation, token) {
    windowOwnershipStopping = false
    if (generation !== windowGeometryGeneration || token !== windowLaunchToken ||
        phase !== "waiting" || !currentStep || pendingTutorialWindowAddress === "") return
    if (exitCode !== 0) {
      actionRunning = false
      actionStepId = ""
      resetWindowTarget()
      clearActiveKeys()
      showRecovery("That window couldn't be linked to this tutorial launch, so it won't be controlled. Launch a fresh application window, or skip this activity.")
      return
    }
    rememberTutorialWindow(pendingTutorialWindowAddress, currentStep.id)
    completeWindowDetection(targetWindowGeometry, targetMonitorGeometry)
  }

  function stopWindowOwnership() {
    if (!windowOwnershipProcess.running) return
    windowOwnershipStopping = true
    windowOwnershipProcess.running = false
  }

  function completeWindowDetection(windowData, monitorData) {
    if (usesWindowActivation()) actionRunning = false
    restoreActionKeyboard()
    windowGeometryPending = false
    pendingTutorialWindowAddress = ""
    windowGeometryRetryTimer.stop()
    targetWindowGeometry = windowData
    targetMonitorGeometry = monitorData
    storeWindowSnapshot(windowData, monitorData)
    if (monitorData) targetScreenId = Number(monitorData.id)
    windowActivationHintTimer.stop()
    if (windowData && monitorData) windowGeometryRefreshTimer.restart()
    confirmDetectedShortcut()
  }

  function storeWindowSnapshot(windowData, monitorData) {
    if (windowData && monitorData && tutorialWindows.indexOf(targetWindowAddress) !== -1) {
      var snapshots = Object.assign({}, tutorialWindowSnapshots)
      snapshots[targetWindowAddress] = { window: windowData, monitor: monitorData }
      tutorialWindowSnapshots = snapshots
    }
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
    if (!(Number(windowData.size[0]) > 0 && Number(windowData.size[1]) > 0)) return false
    if (!isFinite(Number(windowData.at[0])) || !isFinite(Number(windowData.at[1]))) return false
    return true
  }

  function parseClientGeometry(raw, generation) {
    var wasRefresh = windowGeometryRefreshTimer.refreshing
    windowGeometryRefreshTimer.refreshing = false
    if (generation !== windowGeometryGeneration) return
    if (wasRefresh) {
      try {
        var refreshed = findClientByAddress(raw)
        if (clientGeometryReady(refreshed)) {
          targetWindowGeometry = refreshed
          storeWindowSnapshot(refreshed, targetMonitorGeometry)
          if (!monitorGeometryProcess.running) {
            monitorGeometryProcess.requestGeneration = generation
            monitorGeometryProcess.running = true
          }
        } else {
          targetWindowGeometry = null
          targetMonitorGeometry = null
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
    var pattern = currentStep && currentStep.completion.appIdPattern
    if (pattern && !(new RegExp(pattern, "i")).test(String(windowData.initialClass || windowData.class || ""))) {
      showRecovery("That isn't the application expected by this activity. Try the launch again.")
      resetWindowTarget()
      clearActiveKeys()
      return
    }
    targetWindowGeometry = windowData
    monitorGeometryProcess.requestGeneration = generation
    monitorGeometryProcess.running = true
  }

  function parseMonitorGeometry(raw, generation) {
    if (generation !== windowGeometryGeneration) return
    var windowData = targetWindowGeometry
    if (!windowData) return
    try {
      var monitors = JSON.parse(String(raw || "[]"))
      if (!Array.isArray(monitors)) throw new Error("monitors response wasn't a list")
      var windowMonitor = Number(windowData.monitor)
      var selected = null
      for (var i = 0; i < monitors.length; i++) {
        if (targetLayerMonitor !== "" ? monitors[i].name === targetLayerMonitor : Number(monitors[i].id) === windowMonitor) {
          selected = monitors[i]
          break
        }
      }
      if (!selected) throw new Error("monitor " + windowMonitor + " not found")
      // Omarchy menus can be small cards inside transparent full-screen
      // surfaces. The compositor exposes the surface, not the card bounds.
      if (targetLayerMonitor !== "" && panelSurfaceIsFullscreen(windowData, selected)) {
        targetWindowGeometry = null
        targetMonitorGeometry = null
        targetScreenId = Number(selected.id)
        return
      }
      if (windowGeometryPending) finishWindowDetection(windowData, selected)
      else {
        targetMonitorGeometry = selected
        targetScreenId = Number(selected.id)
        storeWindowSnapshot(windowData, selected)
      }
    } catch (error) {
      console.warn("learn-omarchy: couldn't read monitor geometry:", error, "- using the configured target estimate")
      if (windowGeometryPending) finishWindowDetection(windowData, null)
    }
  }

  function checkExpectedCombo() {
    if (phase !== "waiting" || comboTriggered || !currentStep || !currentStep.help) return
    var keys = currentStepKeys
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
    root.muted = readableSecondaryColor(root.muted, root.background)
    root.urgent = next.urgent
    root.instruction = next.instruction
  }

  function fail(message) {
    resetLessonRuntime()
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
    if (parsed.referenceViewport !== undefined &&
        (!parsed.referenceViewport || ["width", "height"].some(function(key) {
          var value = parsed.referenceViewport[key]
          return typeof value !== "number" || !isFinite(value) || value <= 0
        }))) {
      fail("Course referenceViewport must contain finite positive width and height.")
      return
    }
    // A reload is a lifecycle boundary: nothing from the old course may keep
    // running, or a pending transition would dereference a step that is gone.
    resetLessonRuntime()
    course = parsed
    lessonIndex = -1
    selectedLessonIndex = 0
    stepIndex = 0
    errorMessage = ""
    applyCourseProgress()
    if (settingsResolved && !characterChosen()) {
      settingsMode = "first-run"
      phase = "settings"
      setCharacterState("hidden", "")
    } else {
      enterHome()
    }
  }

  function applyCourseProgress() {
    var next = {}
    var ids = course && Array.isArray(progressByCourse[course.id]) ? progressByCourse[course.id] : []
    var details = course && progressDetails[course.id] ? progressDetails[course.id] : {}
    stepResults = details.steps || {}
    var bookmarks = Object.assign({}, details.bookmarks || {})
    var lessons = course ? course.lessons : []
    var hasCredits = details.credits && typeof details.credits === "object" && !Array.isArray(details.credits)
    var hasStepResults = details.steps && typeof details.steps === "object" && !Array.isArray(details.steps)
    var legacyCompletedSteps = []
    if (!hasStepResults) {
      for (var legacyId of ids) legacyCompletedSteps = legacyCompletedSteps.concat(legacyLessonStepIds(legacyId))
    }
    var credits = Object.assign({}, hasCredits ? details.credits : {})
    for (var i = 0; i < lessons.length; i++) {
      var previouslyComplete = ids.indexOf(lessons[i].id) !== -1
      for (var j = 0; j < lessons[i].steps.length; j++) {
        var step = lessons[i].steps[j]
        var successful = ["introduced", "assisted", "practiced"].indexOf(stepResults[step.id]) !== -1
        // Older completed badges prove recorded required work, even if a
        // later replay was skipped. Missing activities still need completion.
        var legacyCredit = !hasCredits && !step.optional &&
          ((previouslyComplete && Object.prototype.hasOwnProperty.call(stepResults, step.id)) ||
            legacyCompletedSteps.indexOf(step.id) !== -1)
        if (successful || legacyCredit) credits[step.id] = true
      }
    }
    stepCredits = credits
    for (var i = 0; i < lessons.length; i++) {
      var lesson = lessons[i]
      next[lesson.id] = lessonFullyExplored(lesson)
      if (!next[lesson.id] && ids.indexOf(lesson.id) !== -1) {
        var unfinished = lesson.steps.find(function(step) {
          return !step.optional && stepCredits[step.id] !== true
        })
        if (unfinished) bookmarks[lesson.id] = unfinished.id
      } else if (!next[lesson.id] && bookmarks[lesson.id]) {
        var bookmarkIndex = lesson.steps.findIndex(function(step) { return step.id === bookmarks[lesson.id] })
        var inserted = lesson.steps.slice(0, Math.max(0, bookmarkIndex)).find(function(step) {
          return !step.optional && stepCredits[step.id] !== true &&
            !Object.prototype.hasOwnProperty.call(stepResults, step.id)
        })
        if (inserted) bookmarks[lesson.id] = inserted.id
      }
    }
    completedLessons = next
    lessonBookmarks = bookmarks
  }

  function legacyLessonStepIds(lessonId) {
    // The lesson-only progress format predates activity credits. This frozen
    // catalog grants its earned work without crediting later course additions.
    if (!course || course.id !== "omarchy-essentials") return []
    var lessons = {
      "omarchy-tour": ["tour-welcome", "tour-workspaces", "tour-clock", "tour-status", "tour-omarchy-menu"],
      "menus-and-apps": ["open-root-menu", "open-apps", "open-keybindings"],
      "everyday-apps": ["launch-terminal", "close-terminal", "launch-browser", "launch-files", "close-files"],
      "windows": ["windows-open-first", "windows-open-second", "windows-focus-next", "windows-float",
        "windows-fullscreen", "windows-close-one", "windows-close-two"],
      "workspaces": ["workspaces-home", "workspaces-open-terminal", "workspaces-jump", "workspaces-back",
        "workspaces-send", "next-workspace", "previous-workspace", "workspaces-scratchpad", "workspaces-scratchpad-hide"],
      "bar-panels": ["audio-panel", "network-panel", "power-panel", "calendar-panel"],
      "personalization": ["background-menu", "theme-menu", "toggle-menu"],
      "clipboard-and-helpers": ["helpers-universal-copy", "clipboard-history", "helpers-emoji", "helpers-reminder"],
      "capture-and-share": ["capture-menu", "share-menu"],
      "setup-and-install": ["hardware-menu", "display-panel", "system-menu"],
      "first-real-session": ["finale-intro", "finale-home", "finale-terminal", "finale-browser",
        "finale-send-browser", "finale-back-to-one", "finale-close-terminal", "finale-to-two",
        "finale-close-browser", "finale-graduate"]
    }
    return lessons[lessonId] || []
  }

  function loadProgress(raw) {
    var nextByCourse = {}
    progressDetails = {}
    try {
      var parsed = JSON.parse(String(raw || "{}"))
      if (parsed && parsed.schemaVersion === 2 && parsed.courses && typeof parsed.courses === "object") {
        for (var courseId in parsed.courses) {
          if (Array.isArray(parsed.courses[courseId])) {
            nextByCourse[courseId] = parsed.courses[courseId].map(function(id) { return String(id) })
          }
          progressDetails = parsed.details && typeof parsed.details === "object" ? parsed.details : {}
        }
      } else if (parsed && typeof parsed.courseId === "string" && Array.isArray(parsed.completedLessons)) {
        nextByCourse[parsed.courseId] = parsed.completedLessons.map(function(id) { return String(id) })
      }
    } catch (error) {
      console.warn("learn-omarchy: progress file couldn't be parsed:", error)
    }
    progressByCourse = nextByCourse
    applyCourseProgress()
    progressResolved = true
    if (phase === "menu" && lessonIndex < 0 && characterChosen()) maybeAutoStartTour()
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
    var nextDetails = Object.assign({}, progressDetails)
    if (course) nextDetails[course.id] = { steps: stepResults, credits: stepCredits, bookmarks: lessonBookmarks }
    progressDetails = nextDetails
    progressFile.setText(JSON.stringify({
      schemaVersion: 2,
      courses: nextByCourse,
      details: nextDetails
    }, null, 2) + "\n")
  }

  function markCurrentLessonComplete() {
    if (!currentLesson) return
    var next = {}
    for (var id in completedLessons) next[id] = completedLessons[id]
    next[currentLesson.id] = completedLessons[currentLesson.id] === true || lessonFullyExplored(currentLesson)
    completedLessons = next
    var bookmarks = Object.assign({}, lessonBookmarks)
    delete bookmarks[currentLesson.id]
    lessonBookmarks = bookmarks
    persistProgress()
  }

  // Common teardown for leaving whatever lesson state is active: outgoing
  // transitions, timers, actions, geometry requests, keys, and narration.
  // Callers then decide where to go (a lesson, the menu, a reload, or an error).
  function resetLessonRuntime() {
    runCleanup()
    cancelAction()
    stopAudio()
    resetWindowTarget()
    actionCompletionTimer.stop()
    completionTimer.stop()
    lessonTransitionAnimation.stop()
    lessonTransitionRunning = false
    lessonContentOpacity = 1
    pendingLessonTransition = ""
    pendingTransitionStepIndex = -1
    clearActiveKeys()
    tutorialWindows = []
    tutorialWindowsByStep = {}
    tutorialWindowSnapshots = {}
    recoveryMessage = ""
    recoveryStepId = ""
    recoveryReturnStepId = ""
    targetScreenId = -1
    pausedCompletionPending = false
    settingsReturnToLesson = false
  }

  function startLesson(index, practice, resume) {
    if (!course || index < 0 || index >= course.lessons.length) return
    resetLessonRuntime()
    selectedLessonIndex = index
    lessonIndex = index
    stepIndex = 0
    practiceMode = practice === true
    var firstStep = course.lessons[index].steps[0]
    var startsWithIntro = index === 0 && firstStep && firstStep.kind === "tour"
    if (resume !== false && !practiceMode && !startsWithIntro) {
      var bookmark = lessonBookmarks[course.lessons[index].id]
      for (var i = 0; i < course.lessons[index].steps.length; i++) {
        if (course.lessons[index].steps[i].id === bookmark) stepIndex = i
      }
    }
    errorMessage = ""
    introRequested = Boolean(startsWithIntro && !practiceMode)
    startCurrentStep()
  }

  // "hyprland-workspace-is" steps are prerequisites; when the learner is
  // already on that workspace the step has nothing to teach and is skipped
  // without a transition.
  function stepAlreadySatisfied() {
    var completion = currentStep ? currentStep.completion : null
    return Boolean(completion && completion.type === "hyprland-workspace-is" && currentWorkspaceId() === Number(completion.id))
  }

  function startCurrentStep() {
    cancelAction()
    stopAudio()
    clearActiveKeys()
    resetWindowTarget()
    recoveryMessage = ""
    recoveryStepId = ""
    stepAssisted = false
    practiceHintVisible = false
    targetScreenId = -1
    var bookmarks = Object.assign({}, lessonBookmarks)
    if (currentLesson && currentStep) bookmarks[currentLesson.id] = currentStep.id
    lessonBookmarks = bookmarks
    persistProgress()
    if (stepAlreadySatisfied()) {
      recordStepResult("introduced")
      if (currentLesson && stepIndex + 1 < currentLesson.steps.length) {
        stepIndex++
        startCurrentStep()
      } else {
        phase = "waiting"
        beginLessonTransition("lesson-complete")
      }
      return
    }
    phase = "waiting"
    directionalKey = ""
    if (currentStepNeedsDirection) directionPreviewTimer.restart()
    captureWorkspaceStart()
    captureStepStartWindow()
    var snapshot = tutorialWindowSnapshots[currentTutorialWindow()]
    if (snapshot && currentStep && currentStep.highlight.target === "window") {
      targetWindowAddress = currentTutorialWindow()
      targetWindowGeometry = snapshot.window
      targetMonitorGeometry = snapshot.monitor
    }
    if (currentStep && currentStep.windowFromStep && currentTutorialWindow() === "") {
      showRecovery("The tutorial window isn't available. Return to its launch activity to create a safe target, or skip this activity.", currentStep.windowFromStep)
    }
    startCharacterStep()
    renewKeyboardCapture()
    requestBarGeometry()
  }

  function cancelAction() {
    windowLaunchToken = ""
    stopWindowOwnership()
    directionPreviewTimer.stop()
    directionPreviewProcess.running = false
    if (exerciseRunning) {
      exerciseRunning = false
      if (exerciseRestoreCapture) setKeyboardExclusive(true)
      exerciseRestoreCapture = false
      practiceProcess.running = false
    }
    restoreActionKeyboard()
    swapBefore = null
    swapPreflightProcess.running = false
    focusActionTimer.stop()
    actionGeneration++
    outcomeGeneration++
    outcomeRetryTimer.stop()
    outcomeAddress = ""
    outcomeExpected = null
    completionTimer.stop()
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
    introStartTimer.stop()
    introTimer.stop()
    introLandTimer.stop()
    introActive = false
    introStage = ""
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
      var command = currentStep.cleanup
      if (command.join(" ").indexOf("{tutorialWindow}") !== -1 && currentTutorialWindow() === "") {
        console.warn("learn-omarchy: cleanup skipped because its tutorial window is no longer available")
        return
      }
      Quickshell.execDetached(resolveWindowCommand(command, currentTutorialWindow()))
    }
  }

  function resolveWindowCommand(command, address) {
    return command.map(function(part) {
      return String(part).split("{tutorialWindow}").join("address:" + address)
        .split("{peerWindow}").join("address:" + currentPeerWindow())
    })
  }

  function currentPeerWindow() {
    var address = currentStep && currentStep.swapWithStep ? tutorialWindowsByStep[currentStep.swapWithStep] : ""
    return address && tutorialWindows.indexOf(address) !== -1 ? address : ""
  }

  function directionBetween(first, second) {
    if (!first || !second || first === second || first.hidden || second.hidden ||
        !first.workspace || !second.workspace || first.workspace.id !== second.workspace.id ||
        !Array.isArray(first.at) || !Array.isArray(second.at) ||
        !Array.isArray(first.size) || !Array.isArray(second.size)) return ""
    var dx = second.at[0] + second.size[0] / 2 - first.at[0] - first.size[0] / 2
    var dy = second.at[1] + second.size[1] / 2 - first.at[1] - first.size[1] / 2
    if (!isFinite(dx) || !isFinite(dy) || (dx === 0 && dy === 0)) return ""
    return Math.abs(dx) >= Math.abs(dy) ? (dx > 0 ? "RIGHT" : "LEFT") : (dy > 0 ? "DOWN" : "UP")
  }

  function parseDirectionPreview(raw, generation) {
    if (generation !== actionGeneration || phase !== "waiting" || !currentStepNeedsDirection) return
    var clients
    try {
      clients = JSON.parse(raw)
      if (!Array.isArray(clients)) throw new Error("Expected a window list")
    } catch (error) {
      showRecovery("Couldn't read the practice window positions. Try again.")
      return
    }
    var sourceStep = currentStep.directionFromStep || currentStep.windowFromStep
    var destinationStep = currentStep.swapWithStep || currentStep.windowFromStep
    var source = tutorialWindowsByStep[sourceStep]
    var destination = tutorialWindowsByStep[destinationStep]
    var first = clients.find(function(client) { return client && tutorialWindows.indexOf(source) !== -1 && normalizedWindowAddress(client.address) === source })
    var second = clients.find(function(client) { return client && tutorialWindows.indexOf(destination) !== -1 && normalizedWindowAddress(client.address) === destination })
    directionalKey = directionBetween(first, second)
    if (!directionalKey) {
      var missingStep = !first ? sourceStep : !second ? destinationStep : sourceStep
      showRecovery("Both practice terminals must be visible on the same workspace. Return to their launch activities.", missingStep)
    }
  }

  function parseSwapBaseline(raw, generation) {
    if (generation !== actionGeneration || !actionRunning || !currentStep || !currentStep.swapWithStep) return
    var clients
    try {
      clients = JSON.parse(raw)
      if (!Array.isArray(clients)) throw new Error("Expected a window list")
    } catch (error) {
      actionRunning = false
      clearActiveKeys()
      restoreActionKeyboard()
      showRecovery("Couldn't read the practice windows before swapping. Try again.")
      return
    }
    var first = clients.find(function(item) { return item && normalizedWindowAddress(item.address) === currentTutorialWindow() })
    var peer = clients.find(function(item) { return item && normalizedWindowAddress(item.address) === currentPeerWindow() })
    if (!first || !peer || first === peer || first.floating || peer.floating || first.fullscreen || peer.fullscreen ||
        first.mapped === false || peer.mapped === false ||
        first.hidden || peer.hidden || !first.workspace || !peer.workspace || first.workspace.id !== peer.workspace.id ||
        !Array.isArray(first.at) || first.at.length !== 2 || !first.at.every(Number.isFinite) ||
        !Array.isArray(peer.at) || peer.at.length !== 2 || !peer.at.every(Number.isFinite) ||
        (first.at[0] === peer.at[0] && first.at[1] === peer.at[1])) {
      actionRunning = false
      clearActiveKeys()
      restoreActionKeyboard()
      var missingStep = !first ? currentStep.windowFromStep : !peer ? currentStep.swapWithStep : currentStep.windowFromStep
      showRecovery("Both practice terminals must be tiled on the same workspace. Repeat their launch activities before swapping.", missingStep)
      return
    }
    swapBefore = { peer: currentPeerWindow(), firstAt: first.at.slice(), peerAt: peer.at.slice() }
    if (restoreKeyboardAfterAction) focusActionTimer.restart()
    else helpProcess.running = true
  }

  function returnToMenu() {
    resetLessonRuntime()
    lessonIndex = -1
    stepIndex = 0
    phase = "menu"
    selectedLessonIndex = firstIncompleteLessonIndex()
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
    recordStepResult(currentStepIsTour ? "introduced" : "skipped")
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
    recordStepResult(currentStepIsTour ? "introduced" : stepAssisted ? "assisted" : "practiced")
    beginLessonTransition("highlight")
  }

  function advance() {
    if (!currentLesson || !currentStep || lessonTransitionRunning) return
    completionTimer.stop()
    if (currentStepIsTour && phase === "waiting") recordStepResult("introduced")
    if (recoveryReturnStepId !== "" && currentStep.completion.type === "hyprland-window-activated") {
      var returnId = recoveryReturnStepId
      recoveryReturnStepId = ""
      for (var i = 0; i < currentLesson.steps.length; i++) {
        if (currentLesson.steps[i].id === returnId) {
          beginLessonTransition("step", i)
          return
        }
      }
    }
    if (stepIndex + 1 < currentLesson.steps.length) {
      beginLessonTransition("step", stepIndex + 1)
      return
    }
    beginLessonTransition("lesson-complete")
  }

  // Narration is recorded per coach (it says the coach's name and uses the
  // coach's voice): "audio/x.mp3" in the course resolves to
  // "audio/<character>/x.mp3" under the course directory.
  function characterAudioPath(relative) {
    if (!relative) return ""
    var slash = String(relative).lastIndexOf("/")
    var dir = slash === -1 ? "" : String(relative).substring(0, slash + 1)
    var file = slash === -1 ? String(relative) : String(relative).substring(slash + 1)
    return courseDir + "/" + dir + characterName + "/" + file
  }

  function currentAudioPath() {
    return currentStep && currentStep.audio ? characterAudioPath(currentStep.audio) : ""
  }

  function completionAudioPath() {
    return currentStep && currentStep.completionAudio ? characterAudioPath(currentStep.completionAudio) : ""
  }

  function recordAudioPlayback(event, path, exitCode) {
    var history = audioPlaybackEvents.slice(-511)
    history.push({ event: event, path: path, exitCode: exitCode, at: Date.now() })
    audioPlaybackEvents = history
  }

  function playCompletionNarration() {
    if (phase !== "highlight") return
    var path = completionAudioPath()
    if (!narrationEnabled || path === "") return
    completionNarrationDone = false
    if (audioProcess.running || audioStopRequested) {
      if (audioProcessPath === path && !audioStopRequested) return
      pendingAudioPath = path
      pendingAudioPreserveCharacterState = true
      audioStopRequested = true
      if (audioProcess.running) audioProcess.running = false
      return
    }
    completionTimer.stop()
    startAudioPath(path, true)
  }

  function finishCompletionNarration() {
    completionNarrationDone = true
    var minimumDwell = Math.max(2200, Number(currentStep && currentStep.highlight.durationMs || 0))
    if (!narrationEnabled && currentStep) minimumDwell = Math.max(minimumDwell, readingDuration(currentStep.completionMessage))
    scheduleCompletionAdvance(Math.max(narrationRestMs, minimumDwell - (Date.now() - highlightStartedAt)))
  }

  function scheduleCompletionAdvance(delay) {
    if (!autoAdvance || phase !== "highlight" || !currentStep ||
        (lessonTransitionRunning && pendingLessonTransition !== "")) return
    completionTimer.stepId = currentStep.id
    completionTimer.generation = actionGeneration
    completionTimer.interval = delay
    completionTimer.restart()
  }

  function advanceAfterCompletion(stepId, generation) {
    if (phase !== "highlight" || !currentStep || currentStep.id !== stepId ||
        actionGeneration !== generation || lessonTransitionRunning) return
    advance()
  }

  function startAudioPath(path, preserveCharacterState) {
    if (!narrationEnabled || path === "" || (phase !== "waiting" && phase !== "highlight")) return
    if (path !== currentAudioPath() && path !== completionAudioPath()) return
    if (path === completionAudioPath() && path !== currentAudioPath()) {
      if (phase !== "highlight") return
      completionTimer.stop()
    }
    audioStopRequested = false
    pendingAudioPath = ""
    pendingAudioPreserveCharacterState = false
    audioProcessPath = path
    audioProcess.command = [
      "mpv",
      "--no-video",
      "--really-quiet",
      "--volume=" + speechVolume,
      "--speed=" + speechRate,
      "--",
      path
    ]
    if (!preserveCharacterState) setCharacterState("talk", "LISTENING...")
    audioProcess.running = true
  }

  function playCurrentAudio(preserveCharacterState) {
    if (!narrationEnabled) return
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
      if (audioPaused && Number(audioProcess.processId) > 0) audioProcess.signal(18)
      audioStopRequested = true
      audioProcess.running = false
    }
    audioPaused = false
  }

  function toggleAudio() {
    audioEnabled = !audioEnabled
    persistSettings()
    if (audioEnabled) {
      if (!speechEnabled) return
      if (phase === "highlight") {
        playCompletionNarration()
      } else if (currentStepIsTour) {
        tourAdvanceTimer.stop()
        playCurrentAudio(true)
      } else {
        playCurrentAudio()
      }
      return
    }
    var wasPlayingTour = currentStepIsTour && audioProcess.running
    stopAudio()
    if (sfxProcess.running) sfxProcess.running = false
    if (phase === "highlight") finishCompletionNarration()
    if (autoAdvance && currentStepIsTour && !wasPlayingTour && phase === "waiting" && !tourAdvanceTimer.running) {
      tourAdvanceTimer.interval = tourFallbackDuration()
      tourAdvanceTimer.restart()
    }
  }

  function replayCurrentAudio() {
    if (!currentStep || !currentStep.audio) return
    audioEnabled = true
    speechEnabled = true
    persistSettings()
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
    if (phase === "waiting" && currentStepNeedsDirection && !directionalKey) {
      directionPreviewTimer.restart()
      showRecovery("Checking the practice window positions. Try the highlighted arrow once both terminals are ready.")
      return
    }
    if (currentStepIsPractice) {
      startPracticeExercise()
      return
    }
    if (phase !== "waiting" || lessonTransitionRunning || actionRunning || !currentStep || !currentStep.help || !Array.isArray(currentStep.help.command)) return
    if (source === "help" || source === "help-ready") stepAssisted = true
    recoveryMessage = ""
    recoveryStepId = ""
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
    var tutorialWindow = currentTutorialWindow()
    var command = resolveWindowCommand(currentStep.help.command, tutorialWindow)
    if ((currentStep.help.command.join(" ").indexOf("{tutorialWindow}") !== -1 && tutorialWindow === "") ||
        (currentStep.swapWithStep && currentPeerWindow() === "")) {
      var missingStep = tutorialWindow === "" ? currentStep.windowFromStep : currentStep.swapWithStep
      // The required window is missing; never fall back to another window.
      console.warn("learn-omarchy: Help skipped because the window from", currentStep.windowFromStep, "isn't available; repeat its launch activity or skip this activity")
      actionRunning = false
      actionStepId = ""
      shortcutArmedUntil = 0
      clearActiveKeys()
      setCharacterState("coach", "NO COURSE WINDOW - SKIP OR REPEAT MODULE")
      showRecovery("The required tutorial window isn't available. Return to its launch activity to create a safe target, or skip this activity.", missingStep)
      return
    }
    if (usesWindowActivation()) {
      // A launcher may remain attached to its application (notably Files).
      // Advancing must cancel detection, not terminate the learner's window.
      windowLaunchToken = Date.now().toString(36) + "-" + Math.random().toString(36).slice(2) + "-" + Math.random().toString(36).slice(2)
      Quickshell.execDetached(["env", "LEARN_OMARCHY_WINDOW_TOKEN=" + windowLaunchToken].concat(command))
      windowActivationHintTimer.restart()
      return
    }
    if (currentStep.completion.windowState && currentStep.completion.windowState.focused === true && keyboardExclusive) {
      restoreKeyboardAfterAction = true
      setKeyboardExclusive(false)
    }
    helpProcess.command = command
    if (currentStep.swapWithStep) {
      swapPreflightProcess.requestGeneration = actionGeneration
      swapPreflightProcess.running = true
    } else if (restoreKeyboardAfterAction) focusActionTimer.restart()
    else helpProcess.running = true
  }

  function restoreActionKeyboard() {
    if (!restoreKeyboardAfterAction) return
    restoreKeyboardAfterAction = false
    setKeyboardExclusive(true)
  }

  function startPracticeExercise() {
    if (phase !== "waiting" || lessonTransitionRunning || actionRunning || !currentStepIsPractice) return
    if (practiceProcess.running) {
      showRecovery("The previous exercise is still closing. Try again in a moment.")
      return
    }
    stopAudio()
    clearActiveKeys()
    recoveryMessage = ""
    recoveryStepId = ""
    actionGeneration++
    actionRunning = true
    actionStepId = currentStep.id
    exerciseRunning = true
    exerciseRestoreCapture = keyboardExclusive
    setKeyboardExclusive(false)
    practiceProcess.requestGeneration = actionGeneration
    practiceProcess.command = [appRoot + "/bin/learn-omarchy-practice", currentStep.practice]
    practiceProcess.running = true
  }

  function finishPracticeExercise(exitCode, generation, raw) {
    if (generation !== actionGeneration || !exerciseRunning || !currentStepIsPractice) return
    exerciseRunning = false
    actionRunning = false
    actionStepId = ""
    if (exerciseRestoreCapture) setKeyboardExclusive(true)
    exerciseRestoreCapture = false
    var results = String(raw || "").split("\n").filter(function(line) {
      return line.indexOf("LEARN_PRACTICE_RESULT:") !== -1
    })
    if (exitCode !== 0 || results.length !== 1) {
      showRecovery(exitCode === 0
        ? "Exercise closed without completing the task. Start it again when you're ready, or Skip."
        : "The exercise couldn't finish (exit " + exitCode + "). Try again or Skip.")
      return
    }
    var result
    try {
      var line = results[0]
      var start = line.indexOf("LEARN_PRACTICE_RESULT:") + "LEARN_PRACTICE_RESULT:".length
      result = JSON.parse(line.slice(start, line.lastIndexOf("}") + 1))
    } catch (error) {
      showRecovery("The exercise returned an invalid result. Please try again.")
      return
    }
    if (!result || result.mode !== currentStep.practice || result.completed !== true) {
      showRecovery("The exercise didn't verify this activity. Please try again.")
      return
    }
    completeCurrentStep()
  }

  function requestHelpAction() {
    if (currentStepIsPractice) {
      startPracticeExercise()
      return
    }
    if (phase !== "waiting" || actionRunning || !currentStep || !currentStep.help) return
    runStepAction("help")
  }

  function handleHyprlandEvent(event) {
    if (event.name === "openlayer" && String(event.data || "").trim().indexOf("learn-omarchy") !== 0) {
      // A newer overlay-level surface stacks above ours; re-map HEXON's window so he stays visible.
      externalLayerTick++
    }
    var expectedTutorialWindow = currentTutorialWindow()
    var eventWindow = event.name === "closewindow" ? normalizedWindowAddress(String(event.data || "").split(",")[0]) : ""
    if (eventWindow !== "" && eventWindow === pendingTutorialWindowAddress) {
      actionRunning = false
      actionStepId = ""
      resetWindowTarget()
      clearActiveKeys()
      showRecovery("The application closed before its launch could be verified. Try launching it again.")
    }
    if (eventWindow !== "") forgetTutorialWindow(eventWindow)
    if (!currentStep || phase !== "waiting") return
    var completion = currentStep.completion
    if (
      completion &&
      completion.type === "hyprland-window-activated" &&
      (event.name === "openwindow" || event.name === "activewindowv2")
    ) {
      var address = normalizedWindowAddress(String(event.data || "").split(",")[0])
      if (address === "") return
      // A new-window event is only a candidate. The process must also carry
      // the token inherited from this specific launch before we can own it.
      if (event.name === "openwindow" && actionStepId === currentStep.id &&
          windowDetectionArmed() &&
          (targetWindowAddress === "" || targetWindowAddress === address)) {
        pendingTutorialWindowAddress = address
      }
      if (windowGeometryPending || targetWindowGeometry) return
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
        if (shortcutInhibitionActive) return
        // Hyprland can consume the whole chord before the overlay sees any
        // key, so a newly opened window still counts as the taught outcome.
        console.info("learn-omarchy: accepting openwindow for", address, "without observed shortcut keys")
      }
      requestWindowGeometry(address)
      return
    }
    if (
      completion &&
      (completion.type === "hyprland-workspace-change" || completion.type === "hyprland-workspace-is") &&
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
      requestPanelGeometry(completion.namespace)
      confirmDetectedShortcut()
      return
    }
    if (completion && completion.type === "hyprland-event" && Array.isArray(completion.events)) {
      if (completion.events.indexOf(String(event.name)) === -1) return
      var payload = String(event.data || "")
      if (completion.dataPattern && !(new RegExp(String(completion.dataPattern))).test(payload)) return
      if (completion.target === "tutorial-window") {
        var subject = normalizedWindowAddress(payload.split(",")[0])
        if (expectedTutorialWindow === "" || subject !== expectedTutorialWindow) {
          console.info("learn-omarchy: ignoring", event.name, "for", subject, "because it isn't the window required by this activity")
          return
        }
      }
      if (!windowDetectionArmed()) {
        console.info("learn-omarchy: ignoring", event.name, "because no shortcut or Help action is pending")
        return
      }
      if (completion.windowState) {
        requestOutcomeVerification()
        return
      }
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

  function scrollMenuSelection(angleDelta, pixelDelta) {
    if (phase !== "menu" || !course) return
    var delta = pixelDelta !== 0 ? pixelDelta / 40 : angleDelta / 120
    if (menuWheelRemainder * delta < 0) menuWheelRemainder = 0
    menuWheelRemainder += delta
    var steps = Math.floor(Math.abs(menuWheelRemainder) + 0.000001)
    if (steps === 0) return
    var direction = menuWheelRemainder > 0 ? 1 : -1
    menuWheelRemainder -= direction * steps
    moveMenuSelection(-direction * steps)
  }

  function selectMenuAtPointer(index, x, y) {
    // Card-local coordinates change during scrolling even when the pointer
    // doesn't move. Compare positions in the stationary overlay instead.
    var moved = isFinite(menuPointerX) && isFinite(menuPointerY) &&
      (Math.abs(x - menuPointerX) > 1 || Math.abs(y - menuPointerY) > 1)
    menuPointerX = x
    menuPointerY = y
    if (moved && phase === "menu") selectedLessonIndex = index
  }

  function travelDurationForDistance(distance, leavingIntro) {
    if (reducedMotion) return 0
    // The first ascent needs time to read as a takeoff, even on smaller screens.
    var minimum = leavingIntro ? 1200 : 420
    var maximum = leavingIntro ? 1900 : 1500
    var millisecondsPerPixel = leavingIntro ? 1.35 : 1.15
    return Math.round(Math.max(minimum, Math.min(maximum, distance * millisecondsPerPixel)))
  }

  function handleKeyPressed(event) {
    var plain = event.modifiers === Qt.NoModifier
    if (phase === "waiting" && plain && (introActive || characterState === "intro") &&
        (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)) {
      skipIntroScene()
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Tab && plain) return
    if (phase === "paused") {
      if (isPlainEscape(event) || event.key === Qt.Key_Space || event.key === Qt.Key_P) resumePausedLesson()
      event.accepted = true
      return
    }
    if (lessonTransitionRunning) {
      event.accepted = true
      return
    }
    if (phase === "settings") {
      if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) moveCharacterPick(-1)
      else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down || event.key === Qt.Key_Tab) moveCharacterPick(1)
      else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
        if (characterIndex.length > 0) chooseCharacter(characterIndex[characterPick].id)
        if (settingsMode !== "first-run") closeSettings()
      } else if (event.key === Qt.Key_R && settingsMode !== "first-run") requestResetProgress()
      else if (isPlainEscape(event)) closeSettings()
      else return
      event.accepted = true
      return
    }
    if (phase === "menu") {
      if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) moveMenuSelection(-1)
      else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) moveMenuSelection(1)
      else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) startLesson(selectedLessonIndex)
      else if (event.key === Qt.Key_P) startLesson(selectedLessonIndex, true, false)
      else if (isPlainEscape(event)) Qt.quit()
      else return
      event.accepted = true
      return
    }
    if (phase === "lesson-complete") {
      if (event.key === Qt.Key_R) startLesson(lessonIndex, false, false)
      else if (event.key === Qt.Key_P) startLesson(lessonIndex, true, false)
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
    if (phase === "highlight") {
      if (event.key === Qt.Key_P && plain) {
        pauseLesson()
        event.accepted = true
        return
      }
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
        stopAudio()
        advance()
      } else if (isPlainEscape(event)) {
        returnToMenu()
      }
      event.accepted = true
      return
    }
    if (phase === "waiting") {
      if (plain && event.key === Qt.Key_P && expectedKeyMap()["P"] !== true) {
        pauseLesson()
        event.accepted = true
        return
      }
      if (plain && event.key === Qt.Key_H && practiceMode && expectedKeyMap()["H"] !== true) {
        practiceHintVisible = true
        stepAssisted = true
        event.accepted = true
        return
      }
      if (isPlainEscape(event)) {
        returnToMenu()
        event.accepted = true
        return
      }
      if (
        currentStep &&
        currentStep.keys.length === 0 &&
        plain &&
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
    id: characterFile
    path: root.characterAssetRoot + "/character.json"
    printErrors: false
    onLoaded: root.loadCharacterConfig(text())
    onLoadFailed: console.warn("learn-omarchy: no character manifest at", path, "- using HEXON defaults")
  }

  FileView {
    id: characterIndexFile
    path: root.appRoot + "/assets/characters/index.json"
    printErrors: false
    onLoaded: root.loadCharacterIndex(text())
    onLoadFailed: console.warn("learn-omarchy: no character index at", path)
  }

  FileView {
    id: settingsFile
    path: root.settingsPath
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadSettings(text())
    onLoadFailed: root.loadSettings("{}")
  }

  FileView {
    id: progressFile
    path: root.progressPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadProgress(text())
    onFileChanged: reload()
    onLoadFailed: root.loadProgress("{}")
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

    function audioLog(): string {
      return JSON.stringify(root.audioPlaybackEvents)
    }

    function status(): string {
      return JSON.stringify({
        phase: root.phase,
        character: root.characterName,
        settingsPath: root.settingsPath,
        lessonIndex: root.lessonIndex,
        selectedLessonIndex: root.selectedLessonIndex,
        stepIndex: root.stepIndex,
        lessonId: root.currentLesson ? root.currentLesson.id : "",
        stepId: root.currentStep ? root.currentStep.id : "",
        keyboardFocused: root.keyboardFocused,
        shortcutInhibitionActive: root.shortcutInhibitionActive,
        keyboardExclusive: root.keyboardExclusive,
        keys: root.currentStepKeys,
        tourSeen: root.tourSeen,
        completedLessons: root.completedLessons,
        stepResults: root.stepResults,
        practiceMode: root.practiceMode,
        recoveryMessage: root.recoveryMessage,
        outcomeAddress: root.outcomeAddress,
        swapBefore: root.swapBefore,
        autoAdvance: root.autoAdvance,
        audioPaused: root.audioPaused,
        characterState: root.characterState,
        characterMessage: root.characterMessage,
        lessonContentOpacity: root.lessonContentOpacity,
        lessonTransitionRunning: root.lessonTransitionRunning,
        workspaceStartId: root.workspaceStartId,
        activeKeys: root.activeKeys,
        comboTriggered: root.comboTriggered,
        actionRunning: root.actionRunning,
        actionStopping: root.actionStopping,
        actionStepId: root.actionStepId,
        pendingStepAction: root.pendingStepAction,
        exerciseRunning: root.exerciseRunning,
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

    function pause(): string {
      root.pauseLesson()
      return root.phase
    }

    function resume(): string {
      root.resumePausedLesson()
      return root.phase
    }

    function back(): string {
      if (root.phase !== "waiting" && root.phase !== "highlight") return "not-in-lesson"
      root.previousStep()
      return "ok"
    }

    function practice(index: string): string {
      var parsed = Number(index)
      if (!root.course || !isFinite(parsed) || parsed < 0 || parsed >= root.course.lessons.length) return "invalid-index"
      root.startLesson(Math.floor(parsed), true, false)
      return "ok"
    }

    function react(key: string): string {
      if (root.phase !== "waiting" || !root.currentStep) return "not-waiting"
      root.reactToKey(String(key).toUpperCase())
      return "ok"
    }

    function keys(mode: string): string {
      root.setKeyboardExclusive(String(mode) !== "release")
      return root.keyboardExclusive ? "exclusive" : "released"
    }

    function settings(action: string): string {
      var what = String(action)
      if (what === "open") { root.openSettings("settings"); return root.phase }
      if (what === "close") { root.closeSettings(); return root.phase }
      if (what === "reset") { root.requestResetProgress(); root.requestResetProgress(); return "reset" }
      return "unknown-action"
    }

    function coach(id: string): string {
      if (root.phase !== "menu" && root.phase !== "settings") return "not-in-menu"
      root.chooseCharacter(String(id))
      return root.characterName
    }

    function target(): string {
      if (root.phase !== "waiting" || !root.currentStep) return "not-waiting"
      root.completeCurrentStep()
      return "ok"
    }

    function skip(): string {
      if (root.phase !== "waiting" || !root.currentStep) return "not-waiting"
      root.skipCurrentStep()
      return "ok"
    }
  }

  // Short sound effects (booster rumble for the rocket scene). Independent of
  // narration so the two never interrupt each other; muted with the speaker.
  Process {
    id: sfxProcess
  }

  function playSound(name) {
    if (!audioEnabled || !effectsEnabled || reducedMotion || phase === "paused" || phase === "settings") return
    if (sfxProcess.running) sfxProcess.running = false
    sfxProcess.command = ["mpv", "--no-video", "--really-quiet", "--volume=" + effectsVolume, "--", appRoot + "/assets/sounds/" + name]
    sfxProcess.running = true
  }

  Process {
    id: audioProcess
    onStarted: {
      root.recordAudioPlayback("started", root.audioProcessPath, null)
      if (root.audioPaused) audioProcess.signal(19)
    }
    onExited: function(exitCode) {
      var stopped = root.audioStopRequested
      var finishedPath = root.audioProcessPath
      root.recordAudioPlayback(stopped ? "interrupted" : "finished", finishedPath, exitCode)
      var queuedPath = root.pendingAudioPath
      var preserveQueuedCharacterState = root.pendingAudioPreserveCharacterState
      root.audioStopRequested = false
      root.audioPaused = false
      root.audioProcessPath = ""
      root.pendingAudioPath = ""
      root.pendingAudioPreserveCharacterState = false
      if (stopped) {
        if (queuedPath !== "" && root.narrationEnabled &&
            (queuedPath === root.currentAudioPath() || queuedPath === root.completionAudioPath())) {
          Qt.callLater(function() {
            root.startAudioPath(queuedPath, preserveQueuedCharacterState)
          })
        } else if (
          root.phase === "waiting" &&
          root.currentStepIsTour &&
          !root.narrationEnabled &&
          finishedPath === root.currentAudioPath()
        ) {
          if (root.autoAdvance) {
            tourAdvanceTimer.interval = root.tourFallbackDuration()
            tourAdvanceTimer.restart()
          }
        } else if (root.phase === "highlight" && finishedPath === root.completionAudioPath()) {
          root.finishCompletionNarration()
        } else if (root.phase === "waiting" && root.characterState === "talk") {
          root.settleCharacter()
        }
        return
      }
      if (root.phase === "highlight" && finishedPath === root.completionAudioPath()) {
        if (exitCode !== 0) console.warn("learn-omarchy: completion narration failed with exit code", exitCode)
        root.finishCompletionNarration()
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
        root.currentStepIsTour &&
        finishedPath === root.currentAudioPath()
      ) {
        // The instruction stays on screen; the tour just uses its timed fallback.
        console.warn("learn-omarchy: tour narration failed with exit code", exitCode, "; using the fallback duration")
        if (root.autoAdvance) {
          tourAdvanceTimer.interval = root.tourFallbackDuration()
          tourAdvanceTimer.restart()
        }
      } else if (
        exitCode !== 0 &&
        root.phase === "waiting" &&
        root.narrationEnabled &&
        finishedPath === root.currentAudioPath()
      ) {
        root.showRecovery("Narration couldn't be played. You can still follow the written instruction, or use Replay to try again.")
        root.settleCharacter()
      } else if (root.phase === "waiting" && root.characterState === "talk") {
        root.settleCharacter()
      }
    }
  }

  Process {
    id: swapPreflightProcess
    property int requestGeneration: -1
    command: ["hyprctl", "clients", "-j"]
    stdout: StdioCollector { id: swapOutput }
    onExited: function(code) {
      if (requestGeneration !== root.actionGeneration || !root.actionRunning) return
      if (code !== 0) {
        root.actionRunning = false
        root.clearActiveKeys()
        root.restoreActionKeyboard()
        root.showRecovery("Couldn't inspect the practice windows (exit " + code + "). Try again.")
        return
      }
      root.parseSwapBaseline(swapOutput.text, requestGeneration)
    }
  }

  Timer {
    id: directionPreviewTimer
    interval: 100
    onTriggered: {
      if (!root.currentStepNeedsDirection || root.phase !== "waiting") return
      if (directionPreviewProcess.running) { restart(); return }
      directionPreviewProcess.requestGeneration = root.actionGeneration
      directionPreviewProcess.running = true
    }
  }

  Process {
    id: directionPreviewProcess
    property int requestGeneration: -1
    command: ["hyprctl", "clients", "-j"]
    stdout: StdioCollector { id: directionOutput }
    onExited: function(code) {
      if (requestGeneration !== root.actionGeneration || root.phase !== "waiting") return
      if (code !== 0) {
        root.showRecovery("Couldn't inspect the practice window positions (exit " + code + "). Try again.")
        return
      }
      root.parseDirectionPreview(directionOutput.text, requestGeneration)
    }
  }

  Process {
    id: practiceProcess
    property int requestGeneration: -1
    environment: ({
      LEARN_OMARCHY_PRACTICE_SCALE: String(root.textScale),
      LEARN_OMARCHY_PRACTICE_BACKGROUND: String(root.background),
      LEARN_OMARCHY_PRACTICE_FOREGROUND: String(root.foreground),
      LEARN_OMARCHY_PRACTICE_ACCENT: String(root.accent),
      LEARN_OMARCHY_PRACTICE_ERROR: String(root.urgent)
    })
    stdout: StdioCollector { id: practiceOutput }
    stderr: StdioCollector {
      onStreamFinished: if (text.trim()) console.warn("learn-omarchy exercise:", text.trim())
    }
    onExited: function(exitCode) {
      root.finishPracticeExercise(exitCode, requestGeneration, practiceOutput.text)
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
        root.clearActiveKeys()
        root.actionStepId = ""
        root.shortcutArmedUntil = 0
        root.pendingTutorialWindowAddress = ""
        root.showRecovery("The guided action failed (exit " + exitCode + "). Try again or skip this activity.", root.currentStep.windowFromStep)
        return
      }
      if (
        exitCode === 0 &&
        root.phase === "waiting" &&
        root.currentStep &&
        root.currentStep.id === root.actionStepId &&
        root.currentStep.completion.windowState
      ) {
        root.requestOutcomeVerification()
      } else if (
        exitCode === 0 &&
        root.phase === "waiting" &&
        root.currentStep &&
        root.currentStep.id === root.actionStepId &&
        root.actionCompletionType === "hyprland-layer-open"
      ) {
        root.requestPanelGeometry(root.currentStep.completion.namespace)
      } else if (
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

  Timer {
    id: keyboardCaptureTimer
    interval: 80
    repeat: false
    onTriggered: {
      root.keyboardCaptureResetting = false
      if (root.keyboardExclusive) root.requestKeyboardFocus()
    }
  }

  Timer {
    id: focusActionTimer
    interval: 160
    onTriggered: {
      if (root.phase === "waiting" && root.currentStep &&
          root.currentStep.id === root.actionStepId &&
          root.actionProcessGeneration === root.actionGeneration) helpProcess.running = true
    }
  }

  Process {
    id: layerGeometryProcess
    property int requestGeneration: -1
    command: ["hyprctl", "layers", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseLayerGeometry(text, layerGeometryProcess.requestGeneration)
    }
  }

  Process {
    id: barGeometryProcess
    property var requestScreens: []
    property bool providerRequest: false
    stdout: StdioCollector { id: barGeometryOutput }
    onExited: function(exitCode) {
      root.finishBarGeometry(exitCode, barGeometryOutput.text, requestScreens, providerRequest)
    }
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.phase === "waiting" || root.phase === "highlight"
    onTriggered: root.requestBarGeometry()
  }

  Process {
    id: outcomeProcess
    property int requestGeneration: -1
    command: ["hyprctl", "clients", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseOutcome(text, outcomeProcess.requestGeneration)
    }
  }

  Timer {
    id: outcomeRetryTimer
    interval: 150
    repeat: false
    onTriggered: root.queryOutcome()
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
    id: windowOwnershipProcess
    property int requestGeneration: -1
    property string requestToken: ""
    onExited: function(exitCode) {
      root.finishWindowOwnership(exitCode, requestGeneration, requestToken)
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
    repeat: true
    onTriggered: {
      if (root.targetLayerNamespace !== "" && root.phase === "highlight") {
        root.requestPanelGeometry(root.targetLayerNamespace)
        return
      }
      if (!root.targetWindowGeometry || root.phase !== "highlight") return
      if (clientGeometryProcess.running || monitorGeometryProcess.running) return
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
      root.actionRunning = false
      root.actionStepId = ""
      root.shortcutArmedUntil = 0
      root.clearActiveKeys()
      root.showRecovery("No application window appeared. Try Help again, or skip this activity.")
    }
  }

  SequentialAnimation {
    id: lessonTransitionAnimation

    NumberAnimation {
      target: root
      property: "lessonContentOpacity"
      to: 0
      duration: 240
      easing.type: Easing.InOutCubic
    }
    ScriptAction { script: root.applyLessonTransition() }
    PauseAnimation { duration: 100 }
    NumberAnimation {
      target: root
      property: "lessonContentOpacity"
      to: 1
      duration: 360
      easing.type: Easing.InOutCubic
    }
    ScriptAction { script: root.lessonTransitionRunning = false }
  }

  Timer {
    id: characterStepArrivalTimer
    interval: root.characterTravelDuration + 20
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
    interval: root.characterTravelDuration + 20
    repeat: false
    onTriggered: {
      if (root.phase === "waiting" && root.characterState === "tour-fly") {
        root.setCharacterState("tour-settle", "ALMOST THERE")
        characterTravelSettleTimer.restart()
      }
    }
  }

  Timer {
    id: introStartTimer
    interval: 500
    repeat: false
    onTriggered: root.beginIntroScene()
  }

  Timer {
    id: introTimer
    repeat: false
    onTriggered: root.advanceIntro()
  }

  Timer {
    id: introLandTimer
    interval: root.characterTravelDuration + 120
    repeat: false
    onTriggered: if (root.characterState === "intro-exit") root.setCharacterState("intro-land", "")
  }

  Behavior on introPanelOpacity {
    NumberAnimation { duration: root.reducedMotion ? 0 : 450; easing.type: Easing.InOutSine }
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
    interval: 100
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
    interval: 220
    repeat: false
    onTriggered: {
      if (root.phase === "waiting" && root.characterState === "step-settle") {
        root.settleCharacter()
      } else if (root.phase === "waiting" && root.characterState === "tour-settle") {
        root.setCharacterState(root.tourRestingState, root.tourRestingMessage)
        // During the opening scene the narration waits for the ship to leave.
        if (!root.introActive) root.beginTourNarration()
      } else if (root.phase === "waiting" && root.characterState === "help-settle") {
        root.setCharacterState("help", "RIGHT HERE")
      } else if (root.phase === "menu" && root.characterState === "menu-settle") {
        root.setCharacterState("menu-point", "CHOOSE A LESSON")
      } else if (root.phase === "highlight" && root.characterState === "target-settle") {
        root.setCharacterState("target-point", "HERE IT IS!")
      } else if (root.phase === "lesson-complete" && root.characterState === "module-settle") {
        root.setCharacterState("celebrate", root.lessonFullyExplored(root.currentLesson) ? "MODULE COMPLETE!" : "MODULE EXPLORED")
      }
    }
  }

  Timer {
    // A pending reset confirmation expires on its own rather than on mouse
    // movement, since the button resizes under the cursor when its label changes.
    id: resetConfirmTimer
    interval: 6000
    repeat: false
    onTriggered: root.resetConfirmPending = false
  }

  Timer {
    id: resetDoneTimer
    interval: 4000
    repeat: false
    onTriggered: root.resetJustDone = false
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
    property string stepId: ""
    property int generation: -1
    repeat: false
    onTriggered: root.advanceAfterCompletion(stepId, generation)
  }

  Timer {
    id: layerCompletionFeedbackTimer
    interval: 120
    repeat: false
    onTriggered: root.completeCurrentStep()
  }

  Variants {
    model: Quickshell.screens

    delegate: Scope {
      id: screenScope

      required property var modelData

      PanelWindow {
        id: overlay

        property real menuSelectionX: width / 2
        property real menuSelectionY: height / 2
        readonly property bool isFocusedScreen: {
          var monitor = Hyprland.monitorFor(screenScope.modelData)
          if (root.phase === "highlight" && root.targetScreenId >= 0)
            return monitor && Number(monitor.id) === root.targetScreenId
          return monitor && monitor === Hyprland.focusedMonitor
        }
        readonly property bool shouldShow: root.phase !== "loading" && !root.exerciseRunning && isFocusedScreen
        readonly property var highlight: root.currentStep ? root.currentStep.highlight : null
        readonly property var hyprlandMonitor: Hyprland.monitorFor(screenScope.modelData)
        readonly property bool windowOnThisMonitor:
          Boolean(root.targetWindowGeometry && root.targetMonitorGeometry) &&
          (!hyprlandMonitor || Number(hyprlandMonitor.id) === Number(root.targetMonitorGeometry.id))
        readonly property var measuredWindowTarget:
          Boolean(root.currentStep) && !root.currentStepHasNoVisibleTarget &&
          (root.currentStep.completion.type === "hyprland-window-activated" ||
            root.currentStep.highlight.target === "window" ||
            root.currentStep.highlight.target === "panel") &&
          windowOnThisMonitor
            ? root.projectWindowGeometry(root.targetWindowGeometry, root.targetMonitorGeometry, width, height) : null
        readonly property bool usesWindowTarget: measuredWindowTarget !== null && !(measuredBarTarget && measuredBarTarget.panel)
        readonly property real minimumLeftPointX: 213
        readonly property real windowTargetX: usesWindowTarget ? measuredWindowTarget.x : 0
        readonly property real windowTargetY: usesWindowTarget ? measuredWindowTarget.y : 0
        readonly property real windowTargetWidth: usesWindowTarget ? measuredWindowTarget.width : 0
        readonly property real windowTargetHeight: usesWindowTarget ? measuredWindowTarget.height : 0
        readonly property var measuredBarTarget: root.barTargetGeometry(highlight,
          workspaceSlot(highlight && highlight.workspaceId || root.currentWorkspaceId()),
          screenScope.modelData, width, height)
        readonly property var estimatedTarget: root.estimatedTargetGeometry(highlight, width, height,
          workspaceSlot(highlight && highlight.workspaceId || root.currentWorkspaceId()))
        readonly property bool targetIsEstimated: Boolean(highlight) &&
          (highlight.target === "window" ? !usesWindowTarget
            : !usesWindowTarget && (!measuredBarTarget || measuredBarTarget.estimated === true))
        readonly property bool hasReliableCompletionTarget: !root.currentStepHasNoVisibleTarget &&
          Boolean(highlight) && !targetIsEstimated
        readonly property real fittedHighlightWidth: usesWindowTarget ? windowTargetWidth
          : measuredBarTarget ? measuredBarTarget.width : estimatedTarget ? estimatedTarget.width : 0
        readonly property real fittedHighlightHeight: usesWindowTarget ? windowTargetHeight
          : measuredBarTarget ? measuredBarTarget.height : estimatedTarget ? estimatedTarget.height : 0
        readonly property real targetBoundsX: usesWindowTarget
          ? windowTargetX
          : measuredBarTarget ? measuredBarTarget.x
          : estimatedTarget ? estimatedTarget.x : width / 2
        readonly property real targetBoundsY: usesWindowTarget
          ? windowTargetY
          : measuredBarTarget ? measuredBarTarget.y
          : estimatedTarget ? estimatedTarget.y : height / 2
        readonly property real targetPointX: {
          var value
          if (usesWindowTarget) {
            value = leftEdgePointX(windowTargetX, windowTargetWidth)
          } else if (measuredBarTarget) {
            value = measuredBarTarget.panel ? leftEdgePointX(targetBoundsX, fittedHighlightWidth)
              : targetBoundsX + fittedHighlightWidth / 2
          } else if (highlight) {
            value = highlight.shape === "circle" || highlight.target === "workspace"
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

        readonly property real tourCenterX: highlight ? targetBoundsX + (fittedHighlightWidth / 2) : width / 2
        readonly property real tourCenterY: highlight ? targetBoundsY + (fittedHighlightHeight / 2) : height / 2
        readonly property real tourPointX: highlight ? targetBoundsX + (fittedHighlightWidth / 2) : width / 2
        // Fingertip target sits ~44px under the box so the antennas (about 38px
        // above the fingertip) stay clear of the bar area being discussed.
        readonly property real tourPointY: highlight ? targetBoundsY + fittedHighlightHeight + 44 : 80

        function workspaceSlot(id) {
          var ids = [1, 2, 3, 4, 5]
          var workspaces = Hyprland.workspaces ? Hyprland.workspaces.values : []
          for (var i = 0; i < workspaces.length; i++) {
            var value = Number(workspaces[i].id)
            if (value > 0 && value <= 10 && ids.indexOf(value) === -1) ids.push(value)
          }
          ids.sort(function(a, b) { return a - b })
          return Math.max(0, ids.indexOf(Number(id)))
        }

        function leftEdgePointX(left, itemWidth) {
          if (left >= minimumLeftPointX) return left
          return Math.min(left + itemWidth, minimumLeftPointX)
        }

        screen: screenScope.modelData
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
        WlrLayershell.keyboardFocus: root.keyboardExclusive && !root.keyboardCaptureResetting
          ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        // Layer focus alone doesn't prevent the compositor from handling
        // Super shortcuts before the course can safely target its own windows.
        ShortcutInhibitor {
          window: overlay
          enabled: root.keyboardExclusive && !root.keyboardCaptureResetting && overlay.shouldShow
          onActiveChanged: if (overlay.shouldShow) root.shortcutInhibitionActive = active
          onCancelled: root.setKeyboardExclusive(false)
        }
        IdleInhibitor {
          window: overlay
          enabled: overlay.shouldShow && (root.phase === "waiting" || root.phase === "highlight")
        }
        mask: Region {
          Region { item: topicPanel }
          Region { item: keyboardHint }
          Region { item: characterPanel }
          Region { item: teachingContent }
          Region { item: controls }
          Region { item: completionPanel }
          Region { item: errorPanel }
          Region { item: pausePanel }
        }

        // Omarchy's Apps menu shows a "Launching…" OSD two seconds after a
        // launch unless a new toplevel window appeared. This overlay is a
        // layer surface, not a window, so the OSD would sit there until its
        // timeout; dismiss it every half second for the first few seconds.
        property bool launchOsdDismissed: false
        property int launchOsdAttempts: 0
        onVisibleChanged: {
          if (!visible || launchOsdDismissed) return
          launchOsdDismissed = true
          launchOsdTimer.restart()
        }

        Timer {
          id: launchOsdTimer
          interval: 500
          repeat: true
          onTriggered: {
            Quickshell.execDetached(["omarchy-shell", "osd", "close"])
            overlay.launchOsdAttempts++
            if (overlay.launchOsdAttempts >= 9) stop()
          }
        }

        Item {
          id: keyCatcher
          anchors.fill: parent
          focus: true
          readonly property bool windowFocused: Window.active
          onWindowFocusedChanged: {
            if (!windowFocused && overlay.shouldShow && root.keyboardExclusive &&
                !root.keyboardCaptureResetting) root.renewKeyboardCapture()
          }
          Binding {
            target: root
            property: "keyboardFocused"
            when: overlay.shouldShow
            value: keyCatcher.activeFocus && keyCatcher.windowFocused
          }

          Connections {
            target: root
            function onRequestKeyboardFocus() {
              if (overlay.shouldShow) Qt.callLater(function() { keyCatcher.forceActiveFocus() })
            }
          }

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
          visible: root.phase === "menu" || root.phase === "settings" || root.phase === "lesson-complete" || root.phase === "error"
          color: root.colorWithAlpha(root.background, 0.72)
        }

        // Darken the desktop while the opening scene plays so the sprites read clearly.
        Rectangle {
          anchors.fill: parent
          visible: opacity > 0
          color: root.background
          opacity: root.introActive && root.introStage !== "clear" ? 0.6 : 0
          Behavior on opacity {
            NumberAnimation { duration: 600; easing.type: Easing.InOutSine }
          }
        }

        UiPanel {
          id: characterPanel
          visible: root.phase === "settings"
          anchors.centerIn: parent
          width: Math.min(880, parent.width - 48)
          height: Math.min(parent.height - 64, settingsHeader.implicitHeight + characterColumn.implicitHeight + settingsFooter.implicitHeight + 104)
          radius: 18
          stripe: root.accent

          ColumnLayout {
            id: settingsLayout
            anchors.fill: parent
            anchors.margins: 24
            spacing: 20

            ColumnLayout {
              id: settingsHeader
              Layout.fillWidth: true
              spacing: 6

              Text {
                Layout.fillWidth: true
                text: root.settingsMode === "first-run" ? "Choose your coach" : "Settings"
                color: root.foreground
                font.family: "sans-serif"
                font.pixelSize: 26 * root.textScale
                font.weight: Font.Bold
              }
              Text {
                Layout.fillWidth: true
                text: root.settingsMode === "first-run" ? "Pick a guide for your desktop tour. You can change coaches at any time." : "Choose your coach and make the lessons comfortable for you."
                color: root.muted
                wrapMode: Text.WordWrap
                font.family: "sans-serif"
                font.pixelSize: 14 * root.textScale
              }
            }

            Flickable {
              id: settingsScroll
              Layout.fillWidth: true
              Layout.fillHeight: true
              Layout.minimumHeight: 0
              Layout.preferredHeight: characterColumn.implicitHeight
              clip: true
              contentHeight: characterColumn.implicitHeight
              contentWidth: width
              boundsBehavior: Flickable.StopAtBounds
              flickableDirection: Flickable.VerticalFlick
              Controls.ScrollBar.vertical: Controls.ScrollBar {
                id: settingsScrollbar
                policy: Controls.ScrollBar.AsNeeded
              }
              Connections {
                target: settingsScroll.Window.window
                function onActiveFocusItemChanged() {
                  if (root.phase === "settings")
                    characterColumn.revealControl(settingsScroll.Window.window.activeFocusItem);
                }
              }

              ColumnLayout {
                id: characterColumn
                width: settingsScroll.width - (settingsScrollbar.visible ? 16 : 0)
                spacing: 18

                function revealControl(item) {
                  var ancestor = item;
                  while (ancestor && ancestor !== characterColumn)
                    ancestor = ancestor.parent;
                  if (!ancestor)
                    return;
                  var point = item.mapToItem(characterColumn, 0, 0);
                  if (point.y < settingsScroll.contentY)
                    settingsScroll.contentY = Math.max(0, point.y - 8);
                  else if (point.y + item.height > settingsScroll.contentY + settingsScroll.height)
                    settingsScroll.contentY = Math.min(settingsScroll.contentHeight - settingsScroll.height, point.y + item.height - settingsScroll.height + 8);
                }

                Text {
                  visible: root.settingsMode !== "first-run"
                  text: "COACH"
                  color: root.instruction
                  font.family: "monospace"
                  font.pixelSize: 12 * root.textScale
                  font.weight: Font.Bold
                }

                GridLayout {
                  Layout.fillWidth: true
                  columns: characterColumn.width < 640 ? 1 : 2
                  uniformCellWidths: true
                  columnSpacing: 16
                  rowSpacing: 16

                  Repeater {
                    model: root.characterIndex

                    Rectangle {
                      id: characterCard
                      required property int index
                      required property var modelData
                      readonly property bool selected: index === root.characterPick
                      readonly property bool active: modelData.id === root.characterName

                      Layout.fillWidth: true
                      Layout.minimumWidth: 0
                      implicitWidth: 300
                      implicitHeight: root.settingsMode === "first-run" ? 320 : Math.max(160, coachDetails.implicitHeight + 32)
                      color: characterCardMouse.containsMouse || selected ? root.colorWithAlpha(root.accent, 0.14) : root.subtleFill
                      border.color: selected ? root.colorWithAlpha(root.accent, 0.85) : root.colorWithAlpha(root.foreground, 0.12)
                      border.width: selected ? 2 : 1
                      radius: 14
                      GridLayout {
                        anchors {
                          fill: parent
                          margins: 16
                        }
                        columns: root.settingsMode === "first-run" ? 1 : 2
                        columnSpacing: 12
                        rowSpacing: 12

                        Item {
                          Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                          Layout.preferredWidth: root.settingsMode === "first-run" ? 160 : 120
                          Layout.preferredHeight: root.settingsMode === "first-run" ? 160 : 120

                          Image {
                            anchors.centerIn: parent
                            width: parent.width
                            height: parent.height
                            source: root.appRoot + "/assets/characters/" + characterCard.modelData.id + "/sprites/" + characterCard.modelData.id + "-idle.png"
                            sourceClipRect: Qt.rect(0, 0, 192, 192)
                            fillMode: Image.PreserveAspectFit
                            smooth: false
                            mipmap: false
                          }
                        }

                        ColumnLayout {
                          id: coachDetails
                          Layout.fillWidth: true
                          Layout.minimumWidth: 0
                          spacing: 8
                          Text {
                            Layout.fillWidth: true
                            horizontalAlignment: root.settingsMode === "first-run" ? Text.AlignHCenter : Text.AlignLeft
                            text: characterCard.modelData.displayName || characterCard.modelData.id.toUpperCase()
                            color: characterCard.selected ? root.instruction : root.foreground
                            font.family: "monospace"
                            font.pixelSize: 18 * root.textScale
                            font.weight: Font.Bold
                          }
                          Text {
                            Layout.fillWidth: true
                            horizontalAlignment: root.settingsMode === "first-run" ? Text.AlignHCenter : Text.AlignLeft
                            text: characterCard.modelData.tagline || ""
                            color: root.muted
                            wrapMode: Text.WordWrap
                            font.family: "sans-serif"
                            font.pixelSize: 12 * root.textScale
                          }
                          Text {
                            Layout.fillWidth: true
                            horizontalAlignment: root.settingsMode === "first-run" ? Text.AlignHCenter : Text.AlignLeft
                            text: characterCard.active && root.settingsMode !== "first-run" ? "CURRENT COACH" : (characterCard.modelData.id === "hexon" ? "DEFAULT" : "")
                            color: characterCard.active && root.settingsMode !== "first-run" ? root.accent : root.muted
                            font.family: "monospace"
                            font.pixelSize: 10 * root.textScale
                            font.weight: Font.Bold
                          }
                        }
                      }

                      MouseArea {
                        id: characterCardMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.characterPick = characterCard.index
                        onClicked: root.chooseCharacter(characterCard.modelData.id)
                      }
                    }
                  }
                }

                Rectangle {
                  visible: root.settingsMode !== "first-run"
                  Layout.fillWidth: true
                  Layout.preferredHeight: 1
                  color: root.colorWithAlpha(root.foreground, 0.18)
                }

                Text {
                  visible: root.settingsMode !== "first-run"
                  Layout.fillWidth: true
                  text: "LESSON PREFERENCES"
                  color: root.instruction
                  font.family: "monospace"
                  font.pixelSize: 12 * root.textScale
                  font.weight: Font.Bold
                }

                GridLayout {
                  visible: root.settingsMode !== "first-run"
                  Layout.fillWidth: true
                  columns: characterColumn.width < 560 ? 1 : 2
                  uniformCellWidths: true
                  rowSpacing: 18
                  columnSpacing: 24

                  UiButton {
                    Layout.fillWidth: true
                    label: root.speechEnabled ? "SPEECH ON" : "SPEECH OFF"
                    onClicked: {
                      root.speechEnabled = !root.speechEnabled;
                      if (!root.speechEnabled)
                        root.stopAudio();
                      root.persistSettings();
                    }
                  }
                  UiButton {
                    Layout.fillWidth: true
                    label: root.effectsEnabled ? "EFFECTS ON" : "EFFECTS OFF"
                    onClicked: {
                      root.effectsEnabled = !root.effectsEnabled;
                      if (!root.effectsEnabled && sfxProcess.running)
                        sfxProcess.running = false;
                      root.persistSettings();
                    }
                  }
                  UiButton {
                    Layout.fillWidth: true
                    label: root.reducedMotion ? "MOTION: REDUCED" : "MOTION: FULL"
                    onClicked: {
                      root.motionReduced = !root.motionReduced;
                      root.persistSettings();
                    }
                  }
                  UiButton {
                    Layout.fillWidth: true
                    label: root.autoAdvance ? "ADVANCE: AUTOMATIC" : "ADVANCE: MANUAL"
                    onClicked: {
                      root.autoAdvance = !root.autoAdvance;
                      root.persistSettings();
                    }
                  }
                  PreferenceSlider {
                    Layout.fillWidth: true
                    label: "Speech volume"
                    displayValue: root.speechVolume + "%"
                    value: root.speechVolume
                    onAdjusted: function (value) {
                      root.speechVolume = value;
                      root.persistSettings();
                    }
                  }
                  PreferenceSlider {
                    Layout.fillWidth: true
                    label: "Effect volume"
                    displayValue: root.effectsVolume + "%"
                    value: root.effectsVolume
                    onAdjusted: function (value) {
                      root.effectsVolume = value;
                      root.persistSettings();
                    }
                  }
                  PreferenceSlider {
                    Layout.fillWidth: true
                    label: "Speech speed"
                    minimum: 0.75
                    maximum: 1.5
                    step: 0.05
                    displayValue: root.speechRate.toFixed(2) + "x"
                    value: root.speechRate
                    onAdjusted: function (value) {
                      root.speechRate = value;
                      root.persistSettings();
                    }
                  }
                  PreferenceSlider {
                    Layout.fillWidth: true
                    label: "Text size"
                    minimum: 1
                    maximum: 1.3
                    step: 0.1
                    displayValue: Math.round(root.textScale * 100) + "%"
                    value: root.textScale
                    onAdjusted: function (value) {
                      root.textScale = value;
                      root.persistSettings();
                    }
                  }
                }
                Text {
                  visible: root.settingsMode !== "first-run"
                  Layout.fillWidth: true
                  text: "Volume and speed changes apply to the next clip or Replay."
                  wrapMode: Text.WordWrap
                  color: root.muted
                  font.pixelSize: 12 * root.textScale
                }

                Rectangle {
                  visible: root.settingsMode !== "first-run"
                  Layout.fillWidth: true
                  Layout.preferredHeight: 1
                  color: root.colorWithAlpha(root.foreground, 0.18)
                }

                Text {
                  visible: root.settingsMode !== "first-run"
                  text: "PROGRESS"
                  color: root.instruction
                  font.family: "monospace"
                  font.pixelSize: 12 * root.textScale
                  font.weight: Font.Bold
                }

                GridLayout {
                  visible: root.settingsMode !== "first-run"
                  Layout.fillWidth: true
                  columns: characterColumn.width < 640 ? 1 : 2
                  columnSpacing: 14
                  rowSpacing: 10

                  Text {
                    Layout.fillWidth: true
                    text: root.resetJustDone ? "Progress reset. Closing Settings asks for a coach again, then starts the tour." : root.completedCount + " of " + (root.course ? root.course.lessons.length : 0) + " modules complete. Reset clears your progress and saved coach."
                    color: root.resetJustDone ? root.instruction : root.foreground
                    opacity: 0.85
                    wrapMode: Text.WordWrap
                    font.family: "sans-serif"
                    font.pixelSize: 13 * root.textScale
                  }

                  UiButton {
                    // Fixed width so the label change never moves the button under the cursor.
                    kind: "danger"
                    Layout.preferredWidth: Math.max(implicitWidth, resetConfirmMetrics.implicitWidth + 32)
                    label: root.resetConfirmPending ? "CONFIRM RESET" : "RESET PROGRESS"
                    border.width: root.resetConfirmPending ? 2 : 1
                    onClicked: root.requestResetProgress()

                    Text {
                      id: resetConfirmMetrics
                      visible: false
                      text: "RESET PROGRESS"
                      font.family: "monospace"
                      font.pixelSize: 12 * root.textScale
                      font.weight: Font.Bold
                      font.letterSpacing: 1.1
                    }
                  }
                }
              }
            }

            RowLayout {
              id: settingsFooter
              Layout.fillWidth: true
              spacing: 12

              Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: root.settingsMode === "first-run" ? "Select a coach to begin." : "Changes are saved automatically."
                color: root.muted
                font.family: "sans-serif"
                font.pixelSize: 12 * root.textScale
                wrapMode: Text.WordWrap
              }

              UiButton {
                kind: "ghost"
                label: root.audioEnabled ? "MUTE ALL" : "UNMUTE"
                onClicked: root.toggleAudio()
              }

              UiButton {
                kind: root.settingsMode === "first-run" ? "ghost" : "primary"
                label: root.settingsMode === "first-run" ? "EXIT" : "DONE"
                onClicked: root.closeSettings()
              }
            }
          }
        }

        UiPanel {
          id: topicPanel
          visible: root.phase === "menu" && root.course
          anchors.centerIn: parent
          width: Math.min(860, parent.width - 64)
          height: Math.min(900, parent.height - 80)
          radius: 18
          stripe: root.accent

          ColumnLayout {
            anchors {
              fill: parent
              margins: 30
            }
            spacing: 16

            RowLayout {
              Layout.fillWidth: true
              spacing: 24

              ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                  text: "COURSE"
                  color: root.accent
                  font.family: "monospace"
                  font.pixelSize: 11
                  font.weight: Font.Bold
                  font.letterSpacing: 2
                }
                Text {
                  text: root.course ? root.course.title : ""
                  color: root.instruction
                  font.family: "sans-serif"
                  font.pixelSize: 30
                  font.weight: Font.Bold
                }
                Text {
                  Layout.maximumWidth: topicPanel.width - 320
                  text: root.course ? root.course.description : ""
                  color: root.foreground
                  opacity: 0.8
                  font.family: "sans-serif"
                  font.pixelSize: 15
                  wrapMode: Text.WordWrap
                }
              }

              ColumnLayout {
                Layout.alignment: Qt.AlignBottom
                Layout.preferredWidth: 220
                spacing: 8

                Text {
                  Layout.alignment: Qt.AlignRight
                  text: root.coreCompletedCount + " OF " + root.coreLessonCount + " CORE COMPLETE"
                  color: root.muted
                  font.family: "monospace"
                  font.pixelSize: 11
                  font.weight: Font.Bold
                  font.letterSpacing: 1
                }
                Rectangle {
                  Layout.fillWidth: true
                  Layout.preferredHeight: 8
                  radius: 4
                  color: root.colorWithAlpha(root.foreground, 0.12)

                  Rectangle {
                    height: parent.height
                    radius: 4
                    color: root.accent
                    width: root.coreLessonCount > 0
                      ? Math.round(parent.width * root.coreCompletedCount / root.coreLessonCount)
                      : 0
                    Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                  }
                }
              }
            }

            // One module per row, scrolling when the screen is short. The
            // selected row is kept in view for keyboard navigation.
            Flickable {
              id: lessonList
              Layout.fillWidth: true
              Layout.fillHeight: true
              clip: true
              contentWidth: width
              contentHeight: lessonColumn.implicitHeight
              boundsBehavior: Flickable.StopAtBounds
              flickableDirection: Flickable.VerticalFlick

              function revealSelected() {
                var rowHeight = lessonColumn.rowHeight + lessonColumn.spacing
                var top = root.selectedLessonIndex * rowHeight
                var bottom = top + lessonColumn.rowHeight
                if (top < contentY) contentY = Math.max(0, top)
                else if (bottom > contentY + height) contentY = Math.min(contentHeight - height, bottom - height)
              }

              Connections {
                target: root
                function onSelectedLessonIndexChanged() { if (root.phase === "menu") lessonList.revealSelected() }
              }

              WheelHandler {
                target: null
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: function(event) {
                  root.scrollMenuSelection(event.angleDelta.y, event.pixelDelta.y)
                  event.accepted = true
                }
              }

              Behavior on contentY {
                enabled: !lessonList.moving && !root.reducedMotion
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
              }

              ColumnLayout {
                id: lessonColumn
                width: lessonList.width
                spacing: 8
                readonly property int rowHeight: 76

                Repeater {
                  model: root.course ? root.course.lessons : []

                  Rectangle {
                    id: lessonCard
                    required property int index
                    required property var modelData
                    readonly property bool selected: index === root.selectedLessonIndex
                    readonly property bool completed: root.completedLessons[modelData.id] === true

                    Layout.fillWidth: true
                    Layout.preferredHeight: lessonColumn.rowHeight
                    Layout.rightMargin: 6
                    color: cardMouse.containsMouse || selected
                      ? root.colorWithAlpha(root.accent, 0.14)
                      : root.subtleFill
                    border.color: selected ? root.colorWithAlpha(root.accent, 0.8) : root.colorWithAlpha(root.foreground, 0.1)
                    border.width: 1
                    radius: 12
                    Behavior on color { ColorAnimation { duration: 120 } }

                    function syncCharacterTarget() {
                      if (selected) overlay.updateMenuSelectionTarget(lessonCard, index)
                    }

                    onSelectedChanged: if (selected) Qt.callLater(syncCharacterTarget)
                    onXChanged: if (selected) Qt.callLater(syncCharacterTarget)
                    onYChanged: if (selected) Qt.callLater(syncCharacterTarget)
                    onWidthChanged: if (selected) Qt.callLater(syncCharacterTarget)
                    onHeightChanged: if (selected) Qt.callLater(syncCharacterTarget)
                    Component.onCompleted: if (selected) Qt.callLater(syncCharacterTarget)

                    Connections {
                      target: lessonList
                      function onContentYChanged() { if (lessonCard.selected) Qt.callLater(lessonCard.syncCharacterTarget) }
                    }

                    Rectangle {
                      visible: lessonCard.selected
                      anchors {
                        left: parent.left
                        top: parent.top
                        bottom: parent.bottom
                        margins: 1
                        topMargin: 12
                        bottomMargin: 12
                      }
                      width: 4
                      radius: 2
                      color: root.instruction
                    }

                    RowLayout {
                      anchors {
                        fill: parent
                        leftMargin: 20
                        rightMargin: 18
                      }
                      spacing: 16

                      Rectangle {
                        implicitWidth: 42
                        implicitHeight: 42
                        color: lessonCard.completed ? root.accent : root.colorWithAlpha(root.accent, 0.16)
                        border.color: root.colorWithAlpha(root.accent, lessonCard.completed ? 1 : 0.5)
                        border.width: 1
                        radius: 10

                        Text {
                          anchors.centerIn: parent
                          text: lessonCard.completed ? "✓" : lessonCard.modelData.icon
                          color: lessonCard.completed ? root.background : root.accent
                          font.family: "monospace"
                          font.pixelSize: 15
                          font.weight: Font.Bold
                        }
                      }

                      ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3

                        Text {
                          Layout.fillWidth: true
                          text: lessonCard.modelData.title + (lessonCard.modelData.optional ? "  (optional)" : "")
                          color: lessonCard.selected ? root.instruction : root.foreground
                          font.family: "sans-serif"
                          font.pixelSize: 16
                          font.weight: Font.Bold
                          elide: Text.ElideRight
                        }
                        Text {
                          Layout.fillWidth: true
                          text: root.characterText(lessonCard.modelData.description)
                          color: root.foreground
                          opacity: 0.72
                          font.family: "sans-serif"
                          font.pixelSize: 13
                          elide: Text.ElideRight
                          maximumLineCount: 1
                        }
                      }

                      RowLayout {
                        spacing: 5
                        Repeater {
                          model: root.lessonShortcutLabel(lessonCard.modelData).split(" ")
                          Keycap {
                            required property string modelData
                            label: modelData
                            small: true
                          }
                        }
                      }

                      Text {
                        Layout.preferredWidth: 96
                        horizontalAlignment: Text.AlignRight
                        text: root.lessonBookmarks[lessonCard.modelData.id] &&
                          !(lessonCard.index === 0 && lessonCard.modelData.steps[0].kind === "tour")
                          ? "RESUME"
                          : lessonCard.completed
                            ? (root.lessonResultSummary(lessonCard.modelData).assisted > 0 ? "ASSISTED" : "DONE")
                            : root.lessonResultSummary(lessonCard.modelData).remaining === 0 ? "EXPLORED"
                            : lessonCard.modelData.estimatedMinutes + " MIN · " + lessonCard.modelData.steps.length + " STEPS"
                        color: lessonCard.completed ? root.accent : root.muted
                        font.family: "monospace"
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        font.letterSpacing: 0.8
                      }
                    }

                    MouseArea {
                      id: cardMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onPositionChanged: function(mouse) {
                        if (pressed || lessonList.dragging || lessonList.flicking) return
                        var point = mapToItem(overlay.contentItem, mouse.x, mouse.y)
                        root.selectMenuAtPointer(lessonCard.index, point.x, point.y)
                      }
                      onClicked: root.startLesson(lessonCard.index)
                    }
                  }
                }
              }

              // Slim scrollbar, only when the list overflows.
              Rectangle {
                visible: lessonList.contentHeight > lessonList.height
                anchors.right: parent.right
                width: 4
                radius: 2
                color: root.colorWithAlpha(root.foreground, 0.3)
                y: lessonList.height * (lessonList.contentY / Math.max(1, lessonList.contentHeight))
                height: Math.max(24, lessonList.height * (lessonList.height / Math.max(1, lessonList.contentHeight)))
              }
            }

            RowLayout {
              Layout.alignment: Qt.AlignHCenter
              spacing: 18

              Repeater {
                model: [["↑ ↓", "CHOOSE"], ["⏎", "START / RESUME"], ["P", "PRACTICE"], ["ESC", "CLOSE"]]

                RowLayout {
                  required property var modelData
                  spacing: 6
                  Keycap { label: modelData[0]; small: true }
                  Text {
                    text: modelData[1]
                    color: root.muted
                    font.family: "monospace"
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    font.letterSpacing: 1
                  }
                }
              }
            }
          }
        }

        Rectangle {
          id: keyboardHint
          // Stays up for as long as keys are released. It used to hide while
          // the overlay held focus, but with on-demand focus the pointer
          // entering the overlay grants focus, so the pill vanished on hover.
          visible: !root.keyboardExclusive && root.phase !== "loading"
          anchors {
            top: parent.top
            horizontalCenter: parent.horizontalCenter
            topMargin: 42
          }
          width: keyboardHintText.implicitWidth + 32
          height: 40
          radius: 10
          color: keyboardHintMouse.containsMouse ? root.colorWithAlpha(root.instruction, 0.3) : root.panelColor
          border.color: root.instruction
          border.width: 1

          Text {
            id: keyboardHintText
            anchors.centerIn: parent
            text: root.keyboardFocused
              ? "⌨  Keys follow the mouse right now  ·  click to keep them here"
              : "⌨  Keys are going to your other windows  ·  click to bring them back"
            color: root.foreground
            font.family: "sans-serif"
            font.pixelSize: 13
            font.weight: Font.DemiBold
          }

          MouseArea {
            id: keyboardHintMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.setKeyboardExclusive(true)
          }
        }

        UiPanel {
          id: teachingContent
          visible: root.phase === "waiting" || root.phase === "highlight"
          opacity: root.lessonContentOpacity * root.introPanelOpacity
          anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: 30
          }
          width: Math.min(900, overlay.width - 48)
          height: consoleColumn.implicitHeight + 38
          radius: 16
          stripe: root.phase === "waiting" ? root.instruction : root.accent

          ColumnLayout {
            id: consoleColumn
            anchors {
              left: parent.left
              right: parent.right
              top: parent.top
              leftMargin: 20
              rightMargin: 20
              topMargin: 18
            }
            spacing: 12

            RowLayout {
              id: lessonNavigation
              Layout.fillWidth: true
              spacing: 10

              // Both side slots share one width so the title stays centred
              // even when Replay and Skip are hidden.
              readonly property real sideWidth: Math.max(topicsButton.implicitWidth + backButton.implicitWidth + 8, navRightGroup.implicitWidth)

              Item {
                Layout.preferredWidth: lessonNavigation.sideWidth
                Layout.minimumWidth: lessonNavigation.sideWidth
                implicitHeight: topicsButton.implicitHeight

                RowLayout {
                  anchors.left: parent.left
                  spacing: 8
                UiButton {
                  id: topicsButton
                  kind: "ghost"
                  compact: true
                  label: "← TOPICS"
                  onClicked: root.returnToMenu()
                }
                UiButton {
                  id: backButton
                  compact: true
                  label: "BACK"
                  enabled: root.stepIndex > 0 && !root.lessonTransitionRunning
                  opacity: enabled ? 1 : 0.4
                  onClicked: root.previousStep()
                }
                }
              }

              Item { Layout.fillWidth: true }

              ColumnLayout {
                spacing: 5

                Text {
                  Layout.alignment: Qt.AlignHCenter
                  text: root.currentLesson ? root.currentLesson.title : ""
                  color: root.foreground
                  font.family: "sans-serif"
                  font.pixelSize: 13
                  font.weight: Font.DemiBold
                }

                RowLayout {
                  Layout.alignment: Qt.AlignHCenter
                  spacing: 6

                  Repeater {
                    model: root.currentLesson ? root.currentLesson.steps.length : 0

                    Rectangle {
                      required property int index
                      readonly property bool done: index < root.stepIndex || root.phase === "highlight" && index === root.stepIndex
                      readonly property bool current: index === root.stepIndex
                      readonly property string result: root.currentLesson
                        ? root.stepResults[root.currentLesson.steps[index].id] || "" : ""
                      Accessible.role: Accessible.StaticText
                      Accessible.name: "Activity " + (index + 1) + ": " + (result || (current ? "current" : "not started"))
                      // Layouts size children by implicit size, so animate that.
                      implicitWidth: current ? 20 : 8
                      implicitHeight: 8
                      radius: 4
                      color: result === "skipped" ? root.muted : result === "assisted" ? root.instruction :
                        done ? root.accent : current ? root.instruction : root.colorWithAlpha(root.foreground, 0.22)
                      Behavior on implicitWidth { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                      Behavior on color { ColorAnimation { duration: 200 } }
                    }
                  }

                  Text {
                    Layout.leftMargin: 10
                    text: root.currentLesson ? "STEP " + (root.stepIndex + 1) + " OF " + root.currentLesson.steps.length +
                      (root.currentStep && root.currentStep.optional ? " · OPTIONAL" : "") : ""
                    color: root.muted
                    font.family: "monospace"
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    font.letterSpacing: 1
                  }
                }
              }

              Item { Layout.fillWidth: true }

              Item {
                Layout.preferredWidth: lessonNavigation.sideWidth
                Layout.minimumWidth: lessonNavigation.sideWidth
                implicitHeight: navRightGroup.implicitHeight

                RowLayout {
                  id: navRightGroup
                  anchors.right: parent.right
                  spacing: 10

                  UiButton {
                    visible: Boolean(root.phase === "waiting" && root.currentStep && root.currentStep.audio)
                    compact: true
                    label: "▶ REPLAY"
                    onClicked: {
                      if (root.practiceMode) { root.practiceHintVisible = true; root.stepAssisted = true }
                      root.replayCurrentAudio()
                    }
                  }

                  UiButton {
                    visible: root.phase === "waiting"
                    kind: "ghost"
                    compact: true
                    label: "SKIP →"
                    onClicked: root.skipCurrentStep()
                  }
                }
              }
            }

            Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: 1
              color: root.panelBorder
            }

            Text {
              Layout.fillWidth: true
              Layout.leftMargin: 8
              Layout.rightMargin: 8
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              color: root.phase === "waiting" ? root.instruction : root.foreground
              font.family: "sans-serif"
              font.pixelSize: 21 * root.textScale
              font.weight: Font.Bold
              lineHeight: 1.15
              text: {
                if (root.phase === "highlight" && root.currentStep && root.currentStep.completionMessage)
                  return root.characterText(root.currentStep.completionMessage)
                if (root.practiceMode && !root.practiceHintVisible && root.currentStep && root.currentStep.help)
                  return root.currentStep.help.label.replace(/ for me$/i, "") + "."
                if (root.currentStepIsTour && root.currentStep && root.currentStep.detail)
                  return root.characterText(root.currentStep.detail)
                return root.currentStep ? root.characterText(root.currentStep.instruction) : ""
              }
            }

            Text {
              visible: Boolean(root.phase === "waiting" && !root.currentStepIsTour && root.currentStep && root.currentStep.detail && (!root.practiceMode || root.practiceHintVisible))
              Layout.fillWidth: true
              Layout.leftMargin: 8
              Layout.rightMargin: 8
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              color: root.foreground
              opacity: 0.72
              font.family: "sans-serif"
              font.pixelSize: 14 * root.textScale
              text: root.currentStep ? root.characterText(root.currentStep.detail || "") : ""
            }

            RowLayout {
              visible: Boolean(root.phase === "waiting" && root.currentStep && root.currentStep.keys.length > 0 && (!root.practiceMode || root.practiceHintVisible))
              Layout.alignment: Qt.AlignHCenter
              Layout.topMargin: 4
              Layout.bottomMargin: 2
              spacing: 14

              Repeater {
                model: root.currentStepKeys

                Keycap {
                  required property string modelData
                  label: modelData.toUpperCase()
                  active: label !== "+" && root.activeKeys[label] === true
                }
              }
            }

            Text {
              visible: root.practiceMode && root.phase === "waiting" && !root.currentStepIsTour
              Layout.fillWidth: true
              text: "PRACTICE: recall the shortcut. H reveals a hint. Help is still available. Actions remain course-guided."
              color: root.foreground
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              font.pixelSize: 12 * root.textScale
            }

            Text {
              visible: root.recoveryMessage !== ""
              Layout.fillWidth: true
              text: root.recoveryMessage
              textFormat: Text.PlainText
              color: root.instruction
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              font.pixelSize: 14 * root.textScale
              Accessible.role: Accessible.StaticText
              Accessible.name: text
            }
            UiButton {
              visible: root.recoveryStepId !== "" && root.phase === "waiting"
              Layout.alignment: Qt.AlignHCenter
              label: "RETURN TO WINDOW LAUNCH"
              onClicked: root.recoverTutorialWindow()
            }
            UiButton {
              visible: root.phase === "highlight" || (root.phase === "waiting" && root.currentStepIsTour)
              Layout.alignment: Qt.AlignHCenter
              kind: "primary"
              label: root.phase === "highlight" ? "CONTINUE" : "NEXT"
              onClicked: { root.stopAudio(); root.advance() }
            }

            UiButton {
              visible: Boolean(root.phase === "waiting" && root.currentStep && !root.currentStepIsTour && root.currentStep.keys.length === 0)
              Layout.alignment: Qt.AlignHCenter
              kind: "primary"
              label: (root.currentStep ? root.currentStep.actionLabel || "Continue" : "").toUpperCase()
              enabled: !root.exerciseRunning
              onClicked: root.runStepAction("action")
            }
            Text {
              visible: root.exerciseRunning
              Layout.fillWidth: true
              text: "Keys now go to the exercise window. Complete its task or close it to return to your coach."
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
              color: root.foreground
              font.pixelSize: 14 * root.textScale
            }
          }
        }

        GridLayout {
          id: controls
          z: 100
          visible: root.phase !== "loading" && root.phase !== "settings"
          readonly property bool leftDock: root.phase === "waiting" &&
            root.currentStepIsTour &&
            Boolean(overlay.highlight) &&
            String(overlay.highlight.anchor || "").indexOf("right") !== -1
          anchors {
            top: parent.top
            topMargin: 42
          }
          width: implicitWidth
          x: leftDock ? 24 : parent.width - width - 24
          columns: overlay.width < 900 ? 3 : 6
          columnSpacing: 8
          rowSpacing: 8

          UiButton {
            visible: root.phase !== "settings"
            compact: true
            label: "SETTINGS"
            onClicked: root.openSettings("settings")
          }

          UiButton {
            compact: true
            label: root.keyboardExclusive ? "RELEASE KEYS" : "CAPTURE KEYS"
            enabled: !root.exerciseRunning
            description: "Choose whether shortcuts go to the course or your other windows"
            onClicked: root.setKeyboardExclusive(!root.keyboardExclusive)
          }

          UiButton {
            compact: true
            label: root.audioEnabled ? "MUTE" : "UNMUTE"
            description: "Mute or unmute narration and effects"
            onClicked: root.toggleAudio()
          }

          UiButton {
            visible: root.phase === "waiting" || root.phase === "highlight" || root.phase === "paused"
            compact: true
            label: root.phase === "paused" ? "RESUME" : "PAUSE"
            onClicked: root.phase === "paused" ? root.resumePausedLesson() : root.pauseLesson()
          }

          UiButton {
            visible: Boolean(root.phase === "waiting" && root.currentStep && root.currentStep.help)
            enabled: !root.actionRunning && root.outcomeAddress === ""
            opacity: enabled ? 1 : 0.5
            compact: true
            label: "?  HELP"
            onClicked: root.requestHelpAction()
          }

          UiButton {
            visible: root.phase === "waiting" && (root.introActive || root.characterState === "intro")
            compact: true
            label: "SKIP INTRO"
            onClicked: root.skipIntroScene()
          }

          UiButton {
            compact: true
            kind: "danger"
            label: "EXIT"
            onClicked: {
              root.runCleanup()
              root.stopAudio()
              Qt.quit()
            }
          }
        }

        UiPanel {
          id: pausePanel
          visible: root.phase === "paused"
          anchors.centerIn: parent
          width: Math.min(520, parent.width - 48)
          height: 190
          stripe: root.instruction
          ColumnLayout {
            anchors.centerIn: parent
            width: parent.width - 40
            spacing: 18
            Text {
              Layout.fillWidth: true
              text: "Paused. Your place is saved."
              horizontalAlignment: Text.AlignHCenter
              color: root.foreground
              font.pixelSize: 22
            }
            UiButton {
              Layout.alignment: Qt.AlignHCenter
              kind: "primary"
              label: "RESUME"
              onClicked: root.resumePausedLesson()
            }
          }
        }

        UiPanel {
          id: completionPanel
          visible: root.phase === "lesson-complete" && root.currentLesson
          opacity: root.lessonContentOpacity
          anchors.centerIn: parent
          width: Math.min(620, parent.width - 48)
          height: completionColumn.implicitHeight + 64
          radius: 18
          stripe: root.accent

          ColumnLayout {
            id: completionColumn
            anchors.centerIn: parent
            width: parent.width - 64
            spacing: 14

            Rectangle {
              Layout.alignment: Qt.AlignHCenter
              implicitWidth: 72
              implicitHeight: 72
              radius: 36
              color: root.colorWithAlpha(root.accent, 0.16)
              border.color: root.accent
              border.width: 2

              Text {
                anchors.centerIn: parent
                text: "✓"
                color: root.accent
                font.family: "sans-serif"
                font.pixelSize: 36
                font.weight: Font.Bold
              }
            }
            Text {
              Layout.alignment: Qt.AlignHCenter
              text: root.lessonResultSummary(root.currentLesson).skipped > 0 ||
                root.lessonResultSummary(root.currentLesson).remaining > 0 ? "MODULE EXPLORED" : "MODULE COMPLETE"
              color: root.accent
              font.family: "monospace"
              font.pixelSize: 11
              font.weight: Font.Bold
              font.letterSpacing: 2
            }
            Text {
              Layout.fillWidth: true
              horizontalAlignment: Text.AlignHCenter
              text: root.currentLesson ? root.currentLesson.title : ""
              color: root.instruction
              font.family: "sans-serif"
              font.pixelSize: 28
              font.weight: Font.Bold
            }
            Text {
              Layout.fillWidth: true
              horizontalAlignment: Text.AlignHCenter
              text: {
                var result = root.lessonResultSummary(root.currentLesson)
                return result.practiced + " practiced, " + result.assisted + " assisted, " +
                  result.introduced + " introduced, " + result.skipped + " skipped. Practice again to recall the shortcuts without hints."
              }
              color: root.foreground
              opacity: 0.8
              wrapMode: Text.WordWrap
              font.family: "sans-serif"
              font.pixelSize: 15
            }
            GridLayout {
              Layout.alignment: Qt.AlignHCenter
              Layout.topMargin: 8
              columns: completionPanel.width < 620 || root.textScale > 1 ? 1 : 3
              columnSpacing: 12
              rowSpacing: 12

              UiButton {
                kind: "primary"
                label: "CHOOSE ANOTHER TOPIC"
                onClicked: root.returnToMenu()
              }
              UiButton {
                kind: "ghost"
                label: "REPLAY MODULE"
                onClicked: root.startLesson(root.lessonIndex, false, false)
              }
              UiButton {
                kind: "ghost"
                label: "PRACTICE"
                onClicked: root.startLesson(root.lessonIndex, true, false)
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

      PanelWindow {
        id: hexonWindow

        // HEXON, the target reticle, and the tour outline live in their own
        // overlay-level window with no keyboard focus. Newer layer surfaces
        // (menus, panels, the image selector) stack above older ones, so the
        // window is re-mapped whenever an external layer opens; that puts him
        // back on top without taking keyboard focus away from the menu.
        property bool mapped: true

        screen: screenScope.modelData
        // Track the main overlay's real window visibility, then re-map just
        // after it appears so this window is always the newer (upper) surface.
        visible: overlay.visible && mapped
        anchors {
          top: true
          bottom: true
          left: true
          right: true
        }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "learn-omarchy-hexon"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {
          Region { item: hexonCoach }
        }

        function raise() {
          if (!overlay.visible) return
          mapped = false
          raiseTimer.restart()
        }

        Timer {
          id: raiseTimer
          interval: 16
          repeat: false
          onTriggered: hexonWindow.mapped = true
        }

        Connections {
          target: root
          function onExternalLayerTickChanged() { hexonWindow.raise() }
        }

        Connections {
          target: overlay
          function onVisibleChanged() { if (overlay.visible) hexonWindow.raise() }
        }

        Component.onCompleted: if (overlay.visible) raise()

        Rectangle {
          id: workspacePointer
          z: 8
          visible: root.phase === "highlight" && root.characterState === "target-point" &&
            hexonCoach.targetsCompletion && hexonCoach.completionPointsUp
          readonly property real tipX: hexonCoach.x + hexonCoach.width / 2 +
            (hexonCoach.upTipLocalX - hexonCoach.width / 2) * hexonCoach.scale
          readonly property real tipY: hexonCoach.y + hexonCoach.height +
            (hexonCoach.upTipLocalY - hexonCoach.height) * hexonCoach.scale + hexonCoach.arcOffset
          readonly property real dx: overlay.targetPointX - tipX
          readonly property real dy: overlay.targetPointY - tipY
          x: tipX
          y: tipY
          width: Math.max(0, Math.sqrt(dx * dx + dy * dy) - targetMarker.width / 2)
          height: 2
          transformOrigin: Item.Left
          rotation: Math.atan2(dy, dx) * 180 / Math.PI
          color: root.colorWithAlpha(root.accent, 0.8)
          opacity: root.lessonContentOpacity
        }

        Rectangle {
          id: targetMarker
          z: 9
          visible: root.phase === "highlight" &&
            overlay.hasReliableCompletionTarget
          opacity: root.lessonContentOpacity
          width: overlay.highlight && overlay.highlight.target === "workspace" ? 28 : 38
          height: width
          x: Math.round(overlay.targetPointX - (width / 2))
          y: Math.round(overlay.targetPointY - (height / 2))
          color: "transparent"
          border.color: root.accent
          border.width: 4
          radius: width / 2

          SequentialAnimation on scale {
            running: targetMarker.visible && !root.reducedMotion
            loops: Animation.Infinite
            NumberAnimation { from: 0.72; to: 1.18; duration: 520; easing.type: Easing.OutCubic }
            NumberAnimation { from: 1.18; to: 0.72; duration: 520; easing.type: Easing.InCubic }
          }
        }

        Rectangle {
          id: resultOutline
          z: 8
          visible: root.phase === "highlight" && Boolean(overlay.highlight) &&
            !root.currentStepHasNoVisibleTarget &&
            (overlay.usesWindowTarget || overlay.measuredBarTarget || overlay.highlight.target === "workspace")
          x: overlay.targetBoundsX
          y: overlay.targetBoundsY
          width: overlay.usesWindowTarget ? overlay.windowTargetWidth : overlay.fittedHighlightWidth
          height: overlay.usesWindowTarget ? overlay.windowTargetHeight : overlay.fittedHighlightHeight
          color: root.colorWithAlpha(root.accent, 0.06)
          border.color: overlay.targetIsEstimated ? root.muted : root.accent
          border.width: 3
          radius: 8
          Rectangle {
            x: parent.height > 100 ? 8
              : Math.max(-overlay.targetBoundsX, Math.min(overlay.width - overlay.targetBoundsX - width, parent.width + 8))
            y: parent.height > 100 ? 8
              : overlay.targetBoundsY + parent.height + height + 6 <= overlay.height ? parent.height + 6 : -height - 6
            width: resultLabel.implicitWidth + 16
            height: resultLabel.implicitHeight + 10
            radius: 5
            color: root.panelColor
            Text {
              id: resultLabel
              anchors.centerIn: parent
              text: {
                if (!root.currentStep || !overlay.highlight) return ""
                if (overlay.highlight.target === "workspace") return "Workspace " + (overlay.highlight.workspaceId || root.currentWorkspaceId()) +
                  (overlay.targetIsEstimated ? " (estimated)" : "")
                if (overlay.highlight.target === "panel") return overlay.usesWindowTarget ||
                  (overlay.measuredBarTarget && overlay.measuredBarTarget.panel) ? "Panel opened" : "Panel button"
                var events = root.currentStep.completion.events || []
                return events.indexOf("closewindow") !== -1 ? "Window closed" : "Tutorial window"
              }
              color: root.foreground
              font.pixelSize: 12 * root.textScale
            }
          }
        }

        Rectangle {
          id: tourOutline
          z: 9
          visible: root.phase === "waiting" &&
            root.currentStepIsTour &&
            !root.currentTourTalks &&
            (root.characterState === "tour-point" || root.characterState === "tour-settle") &&
            overlay.highlight
          opacity: root.lessonContentOpacity
          x: Math.round(overlay.targetBoundsX)
          y: Math.round(overlay.targetBoundsY)
          width: Math.round(overlay.fittedHighlightWidth)
          height: Math.round(overlay.fittedHighlightHeight)
          color: root.colorWithAlpha(root.accent, 0.12)
          border.color: overlay.targetIsEstimated ? root.muted : root.accent
          border.width: overlay.highlight ? Math.max(2, Math.min(4, Number(overlay.highlight.borderWidth) || 3)) : 3
          radius: overlay.highlight ? Number(overlay.highlight.radius) || 8 : 8

          SequentialAnimation on border.color {
            running: tourOutline.visible && !root.reducedMotion && !overlay.targetIsEstimated
            loops: Animation.Infinite
            ColorAnimation { to: root.instruction; duration: 600 }
            ColorAnimation { to: root.accent; duration: 600 }
          }

          Rectangle {
            visible: overlay.targetIsEstimated
            width: estimateLabel.implicitWidth + 16
            height: estimateLabel.implicitHeight + 8
            x: Math.max(-parent.x, Math.min(overlay.width - parent.x - width, 0))
            y: Math.max(-parent.y, Math.min(overlay.height - parent.y - height,
              parent.y + parent.height + height + 6 <= overlay.height ? parent.height + 6 : -height - 6))
            radius: 4
            color: root.panelColor
            Text {
              id: estimateLabel
              anchors.centerIn: parent
              text: "Estimated area"
              color: root.foreground
              font.pixelSize: 12 * root.textScale
            }
          }
        }

        Rectangle {
          id: tourCaption
          z: 11
          visible: hexonCoach.visible && root.phase === "waiting" && root.currentStepIsTour && !root.introActive
          opacity: root.lessonContentOpacity
          width: Math.min(680, overlay.width - 24, Math.max(260, tourCaptionText.implicitWidth + 44))
          height: tourCaptionText.implicitHeight + 32
          // Centre under HEXON, but never leave the screen.
          x: Math.round(Math.max(12, Math.min(overlay.width - width - 12,
            hexonCoach.x + (hexonCoach.width / 2) - (width / 2))))
          y: Math.round(Math.min(overlay.height - height - 12, hexonCoach.y + hexonCoach.arcOffset + hexonCoach.height + 8))
          radius: 12
          color: root.panelColor
          border.color: root.colorWithAlpha(root.instruction, 0.8)
          border.width: 1

          Text {
            id: tourCaptionText
            width: Math.min(tourCaption.width - 44, implicitWidth)
            anchors.centerIn: parent
            text: root.currentStep ? root.characterText(root.currentStep.instruction) : ""
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            color: root.instruction
            font.family: "sans-serif"
            font.pixelSize: 21
            font.weight: Font.Bold
          }
        }

        // Opening scene for the tour: HEXON's rocket drops down the middle of
        // the screen, lands at the bottom and he steps out of the hatch; or
        // OLLIE's tree grows and she takes off from its branch. The coach in
        // the scene is the real hexonCoach, parked at coachX/coachY.
        Item {
          id: introScene
          z: 8
          anchors.fill: parent
          visible: opacity > 0
          opacity: root.introActive && root.introStage !== "clear" ? 1 : 0
          Behavior on opacity {
            NumberAnimation { duration: root.introStage === "clear" ? 600 : 450; easing.type: Easing.InOutSine }
          }

          readonly property bool rocket: root.introKind === "rocket"
          readonly property string stage: root.introStage
          readonly property real groundY: overlay.height - 10
          readonly property real coachX: rocket
            ? (stage === "arrive" || stage === "reveal"
              ? rocketArt.x + (root.introAnchorX * rocketArt.width) - (hexonCoach.width / 2)
              : rocketArt.x + (rocketArt.width * 0.5) + 150)
            : treeArt.x + (root.introAnchorX * treeArt.width) - (hexonCoach.width / 2)
          readonly property real coachY: rocket
            ? (stage === "arrive" || stage === "reveal"
              ? rocketArt.landedY + (root.introAnchorY * rocketArt.height) - hexonCoach.height + 4
              : groundY - hexonCoach.height - 12)
            : treeArt.y + (root.introAnchorY * treeArt.height) - hexonCoach.height + 8

          property var stars: []
          Component.onCompleted: {
            var list = []
            for (var i = 0; i < 48; i++) {
              list.push({
                "fx": Math.random(),
                "fy": Math.random() * 0.8,
                "size": 2 + Math.floor(Math.random() * 3),
                "period": 900 + Math.floor(Math.random() * 1800),
                "warm": Math.random() < 0.3
              })
            }
            stars = list
          }

          Repeater {
            model: introScene.stars

            Rectangle {
              required property var modelData
              x: Math.round(modelData.fx * overlay.width)
              y: Math.round(40 + (modelData.fy * overlay.height))
              width: modelData.size
              height: modelData.size
              color: modelData.warm ? root.instruction : root.foreground
              opacity: 0.25

              SequentialAnimation on opacity {
                running: introScene.visible && !root.reducedMotion
                loops: Animation.Infinite
                NumberAnimation { to: 0.9; duration: modelData.period; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0.2; duration: modelData.period; easing.type: Easing.InOutSine }
              }
            }
          }

          // Typed status line, like a terminal prompt.
          Item {
            id: introPrompt
            x: 28
            y: 58
            readonly property string fullText: {
              var name = root.characterDisplayName
              if (introScene.stage === "arrive") return introScene.rocket ? "> INCOMING TRANSMISSION..." : "> SOMETHING STIRS IN THE TREE..."
              if (introScene.stage === "reveal" || introScene.stage === "exit") return "> " + name + (introScene.rocket ? " HAS LANDED." : " IS AWAKE.")
              return "> TOUR STARTING"
            }
            property int shown: 0
            property bool cursorOn: true
            onFullTextChanged: { shown = 0; typeTimer.restart() }

            Timer {
              id: typeTimer
              interval: root.reducedMotion ? 0 : 34
              repeat: true
              running: introScene.visible
              onTriggered: {
                if (introPrompt.shown < introPrompt.fullText.length) introPrompt.shown++
              }
            }

            Timer {
              interval: 480
              repeat: true
              running: introScene.visible
              onTriggered: introPrompt.cursorOn = !introPrompt.cursorOn
            }

            Rectangle {
              anchors.fill: promptText
              anchors.margins: -10
              color: root.colorWithAlpha(root.background, 0.82)
              radius: 4
              border.color: root.colorWithAlpha(root.accent, 0.5)
              border.width: 1
            }

            Text {
              id: promptText
              text: introPrompt.fullText.substring(0, introPrompt.shown) + (introPrompt.cursorOn ? "█" : " ")
              color: root.instruction
              font.family: "monospace"
              font.pixelSize: 20
              font.weight: Font.Bold
            }
          }

          // Landing pad with blinking edge lights, at the very bottom of the screen.
          Item {
            id: landingPad
            visible: introScene.rocket
            width: Math.round(rocketArt.width * 1.7)
            height: 14
            x: Math.round((overlay.width - width) / 2)
            y: Math.round(introScene.groundY - height + 4)
            property bool phase: false

            Timer {
              interval: 420
              repeat: true
              running: introScene.rocket && introScene.visible && !root.reducedMotion
              onTriggered: landingPad.phase = !landingPad.phase
            }

            Rectangle {
              anchors.fill: parent
              color: root.colorWithAlpha(root.background, 0.95)
              border.color: root.muted
              border.width: 2
            }

            Repeater {
              model: 10

              Rectangle {
                required property int index
                width: 8
                height: 8
                y: 3
                x: Math.round(8 + (index * ((landingPad.width - 24) / 9)))
                color: (index % 2 === 0) === landingPad.phase ? root.instruction : root.accent
                opacity: (index % 2 === 0) === landingPad.phase ? 1 : 0.35
              }
            }
          }

          Item {
            id: rocketArt
            visible: introScene.rocket
            readonly property bool doorOpen: introScene.stage === "reveal" || introScene.stage === "exit"
            readonly property bool thrusting: descent.running || liftoff.running
            property bool landed: false
            property real flamePulse: 1

            height: Math.round(Math.max(360, Math.min(700, overlay.height * 0.5)))
            width: rocketImage.implicitHeight > 0
              ? Math.round(height * rocketImage.implicitWidth / rocketImage.implicitHeight)
              : Math.round(height * 0.44)
            x: Math.round((overlay.width - width) / 2)
            readonly property real landedY: introScene.groundY - height
            y: -height - 80

            Connections {
              target: root
              function onIntroStageChanged() {
                if (!introScene.rocket || !overlay.shouldShow) return
                if (root.introStage === "arrive") {
                  descent.stop()
                  liftoff.stop()
                  rocketArt.landed = false
                  rocketArt.y = -rocketArt.height - 80
                  descent.from = rocketArt.y
                  descent.to = rocketArt.landedY
                  if (root.reducedMotion) {
                    rocketArt.y = rocketArt.landedY
                    rocketArt.landed = true
                  } else {
                    descent.restart()
                    root.playSound("rocket-land.opus")
                  }
                } else if (root.introStage === "launch" && !root.reducedMotion) {
                  liftoff.from = rocketArt.y
                  liftoff.to = -rocketArt.height - 120
                  liftoff.restart()
                  root.playSound("rocket-liftoff.opus")
                }
              }
              function onIntroActiveChanged() {
                if (!root.introActive) {
                  descent.stop()
                  liftoff.stop()
                  if (sfxProcess.running) sfxProcess.running = false
                }
              }
            }

            NumberAnimation {
              id: descent
              target: rocketArt
              property: "y"
              duration: root.introRocketTravelMs
              easing.type: Easing.OutQuad
              onFinished: rocketArt.landed = true
            }

            NumberAnimation {
              id: liftoff
              target: rocketArt
              property: "y"
              duration: root.introRocketTravelMs
              easing.type: Easing.InQuad
            }

            Timer {
              interval: 70
              repeat: true
              running: rocketArt.thrusting
              onTriggered: rocketArt.flamePulse = 0.8 + (Math.random() * 0.4)
            }

            // Engine exhaust: chunky pixel flames under the nozzle, drawn
            // behind the hull so the landing legs stay in front.
            Repeater {
              model: [-0.09, 0, 0.09]

              Item {
                required property var modelData
                required property int index
                visible: rocketArt.thrusting && !root.reducedMotion
                x: Math.round((rocketArt.width / 2) + (modelData * rocketArt.width) - 6)
                y: Math.round(rocketArt.height * 0.9)
                width: 12
                height: 26
                z: -1
                scale: (index === 1 ? 5.2 : 3.6) * rocketArt.flamePulse
                transformOrigin: Item.Top

                Rectangle { x: 4; width: 4; height: 6; color: root.foreground }
                Rectangle { x: 2; y: 5; width: 8; height: 7; color: root.instruction }
                Rectangle { x: 3; y: 12; width: 6; height: 8; color: root.urgent }
                Rectangle { x: 5; y: 20; width: 2; height: 6; color: root.urgent }
              }
            }

            Image {
              id: rocketImage
              anchors.fill: parent
              source: introScene.rocket && root.characterConfig.prefix ? root.spriteSource("intro") : ""
              fillMode: Image.Stretch
              opacity: rocketArt.doorOpen ? 0 : 1
              Behavior on opacity { NumberAnimation { duration: 160 } }
            }

            Image {
              anchors.fill: parent
              source: introScene.rocket && root.characterConfig.prefix ? root.spriteSource("intro-open") : ""
              fillMode: Image.Stretch
              opacity: rocketArt.doorOpen ? 1 : 0
              Behavior on opacity { NumberAnimation { duration: 160 } }
            }

            // Dust kicked up on touchdown.
            Repeater {
              model: 10

              Rectangle {
                id: dust
                required property int index
                readonly property real direction: index < 5 ? -1 : 1
                readonly property real reach: 60 + ((index % 5) * 42)
                width: 9 - (index % 3) * 2
                height: width
                color: index % 2 === 0 ? root.muted : root.foreground
                opacity: 0
                x: rocketArt.width / 2
                y: rocketArt.height - 8

                ParallelAnimation {
                  running: rocketArt.landed && !root.reducedMotion
                  NumberAnimation { target: dust; property: "x"; from: rocketArt.width / 2; to: (rocketArt.width / 2) + (dust.direction * dust.reach); duration: 680; easing.type: Easing.OutCubic }
                  NumberAnimation { target: dust; property: "y"; from: rocketArt.height - 8; to: rocketArt.height - 8 - (14 + ((dust.index % 5) * 10)); duration: 680; easing.type: Easing.OutCubic }
                  SequentialAnimation {
                    NumberAnimation { target: dust; property: "opacity"; to: 0.9; duration: 80 }
                    NumberAnimation { target: dust; property: "opacity"; to: 0; duration: 600; easing.type: Easing.InQuad }
                  }
                }
              }
            }
          }

          Item {
            id: treeArt
            visible: !introScene.rocket
            height: Math.round(Math.max(320, Math.min(640, overlay.height * 0.46)))
            width: treeImage.implicitHeight > 0
              ? Math.round(height * treeImage.implicitWidth / treeImage.implicitHeight)
              : Math.round(height * 1.09)
            // Slightly left of centre so the perch on the right-hand branch
            // ends up near the middle of the screen.
            x: Math.round((overlay.width / 2) - (width * 0.72))
            y: Math.round(introScene.groundY - height)
            transformOrigin: Item.Bottom
            scale: 1

            SequentialAnimation {
              running: root.introActive && !introScene.rocket && !root.reducedMotion
              PropertyAction { target: treeArt; property: "scale"; value: 0.1 }
              NumberAnimation { target: treeArt; property: "scale"; to: 1; duration: 1000; easing.type: Easing.OutBack }
            }

            // Gentle sway.
            SequentialAnimation on rotation {
              running: treeArt.visible && introScene.visible && !root.reducedMotion
              loops: Animation.Infinite
              NumberAnimation { to: 0.8; duration: 1900; easing.type: Easing.InOutSine }
              NumberAnimation { to: -0.8; duration: 1900; easing.type: Easing.InOutSine }
            }

            Image {
              id: treeImage
              anchors.fill: parent
              source: !introScene.rocket && root.characterConfig.prefix ? root.spriteSource("intro") : ""
              fillMode: Image.Stretch
            }

            // Fireflies drifting around the canopy.
            Repeater {
              model: 7

              Rectangle {
                id: firefly
                required property int index
                width: 4
                height: 4
                color: root.instruction
                x: Math.round(treeArt.width * (0.1 + ((index * 0.13) % 0.8)))
                y: Math.round(treeArt.height * (0.08 + ((index * 0.17) % 0.5)))
                opacity: 0

                SequentialAnimation on opacity {
                  running: treeArt.visible && introScene.visible && !root.reducedMotion
                  loops: Animation.Infinite
                  PauseAnimation { duration: 300 + (firefly.index * 260) }
                  NumberAnimation { to: 1; duration: 500 }
                  NumberAnimation { to: 0; duration: 700 }
                  PauseAnimation { duration: 400 }
                }

                SequentialAnimation on y {
                  running: treeArt.visible && introScene.visible && !root.reducedMotion
                  loops: Animation.Infinite
                  NumberAnimation { to: Math.round(treeArt.height * (0.08 + ((firefly.index * 0.17) % 0.5))) - 18; duration: 1400 + (firefly.index * 150); easing.type: Easing.InOutSine }
                  NumberAnimation { to: Math.round(treeArt.height * (0.08 + ((firefly.index * 0.17) % 0.5))) + 10; duration: 1400 + (firefly.index * 150); easing.type: Easing.InOutSine }
                }
              }
            }
          }
        }

        // Fading pixel trail behind the coach while flying.
        Repeater {
          model: hexonCoach.trail

          Rectangle {
            required property int index
            required property var modelData
            readonly property real age: (hexonCoach.trail.length - index) / Math.max(1, hexonCoach.trail.length)

            z: 9
            width: 6 + Math.round((1 - age) * 6)
            height: width
            x: modelData.x - (width / 2)
            y: modelData.y - (height / 2)
            radius: 1
            color: index % 2 === 0 ? root.accent : root.instruction
            opacity: Math.max(0, 0.75 - (age * 0.75))
          }
        }

        Item {
          id: hexonCoach
          z: 10

          property real effectScale: 1
          property real effectRotation: 0
          property real effectOpacity: 1
          // +1 when the current trip heads right, -1 when it heads left; the
          // flight pose is mirrored so winged characters never fly backwards.
          property int flightDirection: 1
          readonly property bool uprightFlight: root.characterFlames && (targetsTour || targetsIntro)
          property real flightBank: 0
          // Volume-preserving squash and stretch for takeoff and landing.
          property real stretch: 1
          // Vertical swoop applied on top of the straight-line travel so long
          // horizontal trips arc instead of sliding.
          property real arcOffset: 0
          property real arcHeight: 0
          // Recent centre positions while flying, drawn as a fading pixel trail.
          property var trail: []
          property bool userPlaced: false
          property real userX: 0
          property real userY: 0
          property string interactionMessage: ""
          readonly property bool targetsCompletion:
            overlay.hasReliableCompletionTarget &&
            (root.characterState === "target-fly" ||
            root.characterState === "target-settle" ||
            root.characterState === "target-point")
          readonly property bool targetsTour:
            root.characterState === "tour-fly" ||
            root.characterState === "tour-settle" ||
            root.characterState === "tour-point" ||
            root.characterState === "tour-talk"
          readonly property bool completionPointsUp: targetsCompletion && overlay.targetPointY < 90
          readonly property bool isPointingUp: root.characterState === "tour-point" ||
            (root.characterState === "target-point" && completionPointsUp)
          readonly property bool targetsIntro:
            root.characterState === "intro" ||
            root.characterState === "intro-stand" ||
            root.characterState === "intro-exit" ||
            root.characterState === "intro-land"
          readonly property bool targetsMenu:
            root.characterState === "menu-fly" ||
            root.characterState === "menu-settle" ||
            root.characterState === "menu-point"
          readonly property bool targetsModuleComplete: root.phase === "lesson-complete"
          readonly property bool isPointing:
            root.characterState === "help" ||
            (root.characterState === "target-point" && targetsCompletion) ||
            root.characterState === "tour-point" ||
            root.characterState === "menu-point"
          readonly property int pointDirection:
            (targetsCompletion ? overlay.targetPointX : targetsTour ? overlay.tourPointX : overlay.width) < width ? -1 : 1
          // Renderer landmarks already include pose registration and facing.
          readonly property real upTipLocalX: 8 + coachArt.upTipX
          readonly property real upTipLocalY: (height - 192) + coachArt.upTipY
          readonly property real tourTipX:
            Math.max(18 + upTipLocalX, Math.min(overlay.width - 18 - (width - upTipLocalX), overlay.tourPointX))
          readonly property real tourX: root.currentTourTalks
            ? Math.max(18, Math.min(overlay.width - width - 18, overlay.tourCenterX - (width / 2)))
            : tourTipX - upTipLocalX
          readonly property real tourY: root.currentTourTalks
            ? Math.max(40, Math.min(bottomY, overlay.tourCenterY - (height / 2)))
            : Math.max(-(height - 192) - 4, overlay.tourPointY - upTipLocalY)
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
            root.characterState === "module-settle" ||
            root.characterState === "intro-exit"
          readonly property bool isSettledHover:
            visible && !isFlying && root.characterState !== "hidden"
          // Reticle sits a little ahead of the fingertip when pointing sideways.
          readonly property real pointLead: 15 * pointDirection
          readonly property real pointTipLocalX: 8 + coachArt.pointTipX
          readonly property real pointTipLocalY: (height - 192) + coachArt.pointTipY
          readonly property real waitingX:
            teachingContent.x >= width + 46 ? teachingContent.x - width - 22 : 24
          readonly property real waitingY:
            teachingContent.x >= width + 46
              ? Math.max(70, overlay.height - height - 28)
              : teachingContent.y - height - 16
          readonly property real waitingScale: teachingContent.x >= width + 46
            ? 1 : Math.max(0.4, Math.min(1, (teachingContent.y - 100) / height))
          readonly property real menuTargetX: overlay.menuSelectionX
          readonly property real menuTargetY: overlay.menuSelectionY
          readonly property real moduleTargetX:
            Math.max(18, completionPanel.x - width - 22)
          readonly property real moduleTargetY:
            Math.max(50, Math.min(bottomY,
              completionPanel.y + (completionPanel.height / 2) - (height * 0.55)))
          readonly property real targetScale: targetsCompletion
            ? Math.max(0.85, Math.min(1, overlay.width / 900))
            : 1
          readonly property real responsiveScale: targetsCompletion ? targetScale
            : targetsMenu || targetsTour || targetsIntro || targetsModuleComplete ? 1 : waitingScale
          property real presentationScale: responsiveScale
          readonly property real targetX:
            overlay.targetPointX - (width / 2) - (((completionPointsUp ? upTipLocalX : pointTipLocalX + pointLead) - (width / 2)) * targetScale)
          readonly property real targetY:
            overlay.targetPointY + (completionPointsUp ? 70 : 0) - height +
              ((height - (completionPointsUp ? upTipLocalY : pointTipLocalY)) * targetScale)
          readonly property real bottomY: overlay.height - height - 28
          readonly property real contextX: targetsIntro
            ? introScene.coachX
            : targetsMenu
            ? Math.max(18, Math.min(overlay.width - width - 18, menuTargetX - width + 45))
            : targetsTour
              ? tourX
            : targetsCompletion
              ? Math.max(18 - (width * (1 - targetScale) / 2), Math.min(overlay.width - width - 18, targetX))
              : targetsModuleComplete
                ? moduleTargetX
              : waitingX
          readonly property real contextY: targetsIntro
            ? introScene.coachY
            : targetsMenu
            ? Math.max(50, menuTargetY - (height * 0.55))
            : targetsTour
              ? tourY
            : targetsCompletion
              ? Math.max(completionPointsUp ? -(height - 192) : 50, Math.min(bottomY, targetY))
              : targetsModuleComplete
                ? moduleTargetY
              : waitingY

          visible: (root.phase === "menu" ||
            root.phase === "waiting" ||
            root.phase === "highlight" ||
            root.phase === "lesson-complete") &&
            root.characterState !== "hidden" &&
            root.characterState !== "intro"
          width: 240
          height: 260
          x: userPlaced ? userX : contextX
          y: userPlaced ? userY : contextY
          scale: effectScale * presentationScale
          rotation: effectRotation
          opacity: effectOpacity
          transformOrigin: Item.Bottom
          transform: Translate { y: hexonCoach.arcOffset }

          onIsSettledHoverChanged: {
            if (!isSettledHover) characterImageArea.hoverOffset = 0
          }

          Binding {
            target: root
            property: "characterParked"
            when: overlay.shouldShow
            value: hexonCoach.visible &&
              !hexonCoach.userPlaced &&
              Math.abs(hexonCoach.x - hexonCoach.waitingX) < 12 &&
              Math.abs(hexonCoach.y - hexonCoach.waitingY) < 12
          }

          onXChanged: {
            if (overlay.shouldShow) root.characterX = x
            // Face the way we are actually moving; destinations can update a
            // frame after the flight cue, so the motion itself is the truth.
            if (isFlying && Math.abs(x - lastTrackedX) > 0.3) flightDirection = x > lastTrackedX ? 1 : -1
            lastTrackedX = x
          }
          property real lastTrackedX: 0
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
          function updateTravelDuration() {
            var distance = Math.sqrt(Math.pow(contextX - x, 2) + Math.pow(contextY - y, 2))
            var leavingIntro = root.introActive && root.characterState === "tour-fly"
            root.characterTravelDuration = root.travelDurationForDistance(distance, leavingIntro)
            flightBank = !root.reducedMotion && isFlying && uprightFlight ? 8 * (contextX - x) / Math.max(1, distance) : 0
          }

          Behavior on x {
            enabled: hexonCoach.visible && !root.reducedMotion && !characterMouse.pressed
            onTargetValueChanged: hexonCoach.updateTravelDuration()
            NumberAnimation {
              duration: root.characterTravelDuration
              easing.type: Easing.InOutSine
            }
          }

          Behavior on y {
            enabled: hexonCoach.visible && !root.reducedMotion && !characterMouse.pressed && !fallAnimation.running
            onTargetValueChanged: hexonCoach.updateTravelDuration()
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
              if (!overlay.shouldShow) return
              hexonCoach.updateTravelDuration()
              if (root.reducedMotion) {
                hexonCoach.stretch = 1
              } else if (
                root.characterState === "step-fly" ||
                root.characterState === "help-fly" ||
                root.characterState === "target-fly" ||
                root.characterState === "tour-fly" ||
                root.characterState === "menu-fly" ||
                root.characterState === "module-fly" ||
                root.characterState === "intro-exit"
              ) {
                landingAnimation.stop()
                takeoffAnimation.restart()
                // Swoop height follows the horizontal distance; dip when near the top edge.
                var horizontal = Math.abs(hexonCoach.contextX - hexonCoach.x)
                var swoop = hexonCoach.uprightFlight ? 0 : Math.min(45, horizontal * 0.065)
                hexonCoach.arcHeight = hexonCoach.y < 160 ? swoop : -swoop
                arcAnimation.restart()
              } else if (
                root.characterState === "step-settle" ||
                root.characterState === "help-settle" ||
                root.characterState === "target-settle" ||
                root.characterState === "tour-settle" ||
                root.characterState === "menu-settle" ||
                root.characterState === "module-settle" ||
                root.characterState === "intro-land"
              ) {
                takeoffAnimation.stop()
                landingAnimation.restart()
              }
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
                root.characterState === "tour-talk" ||
                root.characterState === "menu-fly" ||
                root.characterState === "menu-settle" ||
                root.characterState === "menu-point" ||
                root.characterState === "module-fly" ||
                root.characterState === "module-settle" ||
                root.characterState === "intro" ||
                root.characterState === "intro-stand" ||
                root.characterState === "intro-exit" ||
                root.characterState === "intro-land"
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
                if (root.phase === "lesson-complete" && root.lessonFullyExplored(root.currentLesson)) confettiAnimation.restart()
              }
              else if (root.characterState === "intro-stand") {
                hexonCoach.effectScale = 1
                hexonCoach.effectRotation = 0
                introAppearAnimation.restart()
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
            id: arcAnimation
            NumberAnimation {
              target: hexonCoach
              property: "arcOffset"
              to: hexonCoach.arcHeight
              duration: Math.round(root.characterTravelDuration * 0.5)
              easing.type: Easing.OutQuad
            }
            NumberAnimation {
              target: hexonCoach
              property: "arcOffset"
              to: 0
              duration: Math.round(root.characterTravelDuration * 0.5)
              easing.type: Easing.InQuad
            }
          }

          NumberAnimation {
            id: introAppearAnimation
            target: hexonCoach
            property: "effectOpacity"
            from: 0
            to: 1
            duration: 420
            easing.type: Easing.OutCubic
          }

          SequentialAnimation {
            id: takeoffAnimation
            NumberAnimation { target: hexonCoach; property: "stretch"; to: 0.9; duration: 90; easing.type: Easing.OutQuad }
            NumberAnimation { target: hexonCoach; property: "stretch"; to: 1.08; duration: 170; easing.type: Easing.OutQuad }
            NumberAnimation { target: hexonCoach; property: "stretch"; to: 1; duration: 260; easing.type: Easing.InOutSine }
          }

          SequentialAnimation {
            id: landingAnimation
            NumberAnimation { target: hexonCoach; property: "stretch"; to: 1.06; duration: 90; easing.type: Easing.OutQuad }
            NumberAnimation { target: hexonCoach; property: "stretch"; to: 0.94; duration: 130; easing.type: Easing.InOutSine }
            NumberAnimation { target: hexonCoach; property: "stretch"; to: 1; duration: 200; easing.type: Easing.OutBack }
          }

          Timer {
            id: trailTimer
            interval: 55
            repeat: true
            running: hexonCoach.visible && hexonCoach.isFlying && !root.reducedMotion
            onTriggered: {
              var next = hexonCoach.trail.slice(-7)
              next.push({ "x": hexonCoach.x + (hexonCoach.width / 2), "y": hexonCoach.y + hexonCoach.arcOffset + hexonCoach.height - 96 })
              hexonCoach.trail = next
            }
            onRunningChanged: if (!running) trailFadeTimer.restart()
          }

          Timer {
            id: trailFadeTimer
            interval: 70
            repeat: true
            running: false
            onTriggered: {
              if (hexonCoach.trail.length === 0) { stop(); return }
              hexonCoach.trail = hexonCoach.trail.slice(1)
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
            easing.type: Easing.InQuad
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

            // Module-completion burst. One 0 -> 1 value drives every piece; each
            // piece staggers its own start, flies out on an arc, flutters, spins,
            // and fades, so the whole thing is a single animation.
            property real progress: 1
            readonly property bool active: progress < 1
            readonly property real originX: hexonCoach.width / 2
            readonly property real originY: hexonCoach.height - 130

            anchors.fill: parent
            visible: active

            NumberAnimation {
              id: confettiAnimation
              target: confettiBurst
              property: "progress"
              from: 0
              to: 1
              duration: 2600
              easing.type: Easing.Linear
            }

            Repeater {
              model: 56

              Rectangle {
                required property int index
                readonly property real seed: ((index * 7919) % 97) / 97
                readonly property real seed2: ((index * 104729) % 89) / 89
                readonly property real seed3: ((index * 15485863) % 83) / 83
                // Two waves: the second half of the pieces launch about a third of the way in.
                readonly property real delay: (index % 2 === 0 ? 0 : 0.32) + (seed3 * 0.12)
                readonly property real t: Math.max(0, Math.min(1, (confettiBurst.progress - delay) / (1 - delay)))
                // Fan across the upper half, launching a little faster straight up.
                readonly property real angle: (Math.PI * 0.08) + (seed * Math.PI * 0.84)
                readonly property real speed: 240 + (seed2 * 220)
                readonly property real vx: Math.cos(angle) * speed
                readonly property real vy: Math.sin(angle) * speed * (0.85 + (0.3 * Math.abs(Math.sin(angle))))
                readonly property real flutter: Math.sin((t * 9) + (seed * 6.28)) * 14 * t
                readonly property real px: confettiBurst.originX + (vx * t) + flutter
                readonly property real py: confettiBurst.originY - (vy * t) + (260 * t * t)
                readonly property bool streamer: index % 3 === 0

                width: streamer ? 4 : 5 + Math.round(seed2 * 5)
                height: streamer ? 12 + Math.round(seed * 8) : width
                x: px - (width / 2)
                y: py - (height / 2)
                rotation: (seed3 * 360) + (t * 720 * (index % 2 === 0 ? 1 : -1))
                opacity: t <= 0 ? 0 : t < 0.6 ? 1 : Math.max(0, 1 - ((t - 0.6) / 0.4))
                color: index % 5 === 0
                  ? root.accent
                  : index % 5 === 1
                    ? root.instruction
                    : index % 5 === 2
                      ? root.urgent
                      : index % 5 === 3
                        ? root.foreground
                        : root.colorWithAlpha(root.accent, 0.55)
              }
            }

            // A few four-point sparkles that pop around HEXON during the burst.
            Repeater {
              model: 6

              Item {
                required property int index
                readonly property real seed: ((index * 7919) % 97) / 97
                readonly property real start: 0.1 + (index * 0.13)
                readonly property real life: Math.max(0, Math.min(1, (confettiBurst.progress - start) / 0.28))
                readonly property real pop: life < 0.5 ? life * 2 : (1 - life) * 2

                x: confettiBurst.originX - 120 + (seed * 240) - 9
                y: confettiBurst.originY - 40 - (((index * 37) % 120)) - 9
                width: 18
                height: 18
                scale: 0.4 + pop
                opacity: pop
                visible: life > 0 && life < 1

                Rectangle { x: 7; y: 0; width: 4; height: 18; color: root.instruction }
                Rectangle { x: 0; y: 7; width: 18; height: 4; color: root.instruction }
                Rectangle { x: 6; y: 6; width: 6; height: 6; color: root.foreground }
              }
            }
          }

          Rectangle {
            // Only genuine feedback gets a bubble: key reactions, celebrations,
            // and click or drag responses. Status words during narration and
            // travel never matched what was being said, so they stay hidden.
            readonly property bool reacting:
              root.characterState === "correct" ||
              root.characterState === "incorrect" ||
              root.characterState === "celebrate"
            visible: !hexonCoach.isPointingUp && (reacting || hexonCoach.interactionMessage !== "")
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
            rotation: hexonCoach.flightBank
            Behavior on rotation {
              enabled: !root.reducedMotion
              NumberAnimation { duration: 240; easing.type: Easing.InOutSine }
            }
            transform: Scale {
              origin.x: 112
              origin.y: 192
              xScale: 2 - hexonCoach.stretch
              yScale: hexonCoach.stretch
            }

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
              model: coachArt.flameSockets

              delegate: Item {
                required property var modelData

                property real flamePulse: 1

                visible: hexonCoach.visible && !root.reducedMotion && root.characterFlames && !coachArt.isFlyingSprite
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

            CharacterSprite {
              id: coachArt
              z: 1
              assetRoot: root.characterAssetRoot
              config: root.characterConfig
              pose: hexonCoach.isPointing ? (hexonCoach.isPointingUp ? "point-up" : "point") : "idle"
              talking: audioProcess.running && !root.audioPaused && !root.audioStopRequested
              flying: hexonCoach.isFlying && !hexonCoach.uprightFlight
              // Keep target landmarks stable throughout an approach, rather
              // than letting movement-driven facing change the destination.
              landmarkFacing: hexonCoach.pointDirection
              facing: hexonCoach.isFlying
                ? (hexonCoach.uprightFlight ? 1 : hexonCoach.flightDirection)
                : hexonCoach.isPointing ? hexonCoach.pointDirection : 1
              reducedMotion: root.reducedMotion
              animated: hexonWindow.visible && root.phase !== "paused"
              onErrorMessageChanged: {
                if (errorMessage && config.prefix && overlay.shouldShow)
                  console.warn("learn-omarchy: " + errorMessage)
              }
            }

            Text {
              anchors.centerIn: parent
              width: parent.width
              z: 3
              visible: !!root.characterConfig.prefix && coachArt.errorMessage !== ""
              text: coachArt.errorMessage + "\nOpen Settings to choose another coach."
              color: root.urgent
              wrapMode: Text.Wrap
              font.pixelSize: 12 * root.textScale
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
              var scenePosition = hexonCoach.mapToItem(hexonWindow.contentItem, mouse.x, mouse.y)
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
              var scenePosition = hexonCoach.mapToItem(hexonWindow.contentItem, mouse.x, mouse.y)
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
                hexonCoach.interactionMessage = root.characterConfig.clickMessage ||
                  (root.characterFlames ? "BEEP BOOP!" : "HOOT!")
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

      }
    }
  }
}
