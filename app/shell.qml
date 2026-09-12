import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "TeachingLayout.js" as TeachingLayout
import "WindowOutcomes.js" as WindowOutcomes
import "Retention.js" as Retention
import "ArcadeLogic.js" as ArcadeLogic

ShellRoot {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")
  readonly property string appRoot: Quickshell.env("LEARN_OMARCHY_ROOT") || (Quickshell.shellDir + "/..")
  readonly property string coursePath: Quickshell.env("LEARN_OMARCHY_COURSE") || (appRoot + "/courses/omarchy-basics.json")
  readonly property string courseDir: Quickshell.env("LEARN_OMARCHY_COURSE_DIR") || (appRoot + "/courses")
  readonly property string characterOverride: String(Quickshell.env("LEARN_OMARCHY_CHARACTER") || "").toLowerCase()
  readonly property string settingsPath: stateHome + "/learn-omarchy/settings.json"
  readonly property string arcadePath: stateHome + "/learn-omarchy/arcade.json"
  property string requestedCharacter: characterOverride
  readonly property var resolvedPack: characterStore.selectedPack
  readonly property string characterName: resolvedPack ? resolvedPack.id : ""
  property string savedCharacter: ""
  property bool settingsResolved: false
  property bool progressResolved: false
  // Retained for migration from the original automatic-tour first run.
  property bool tourSeen: false
  property bool welcomeSeen: false
  property bool welcomeSettingPresent: false
  property bool splashActive: true
  property real startupOpacity: 1
  property bool startupRevealPending: false
  readonly property color startupBackground: "#020c1a"
  property var mixedLessonIds: []
  property int mixedLessonPosition: 0
  readonly property bool mixedPracticeActive: mixedLessonIds.length > 0
  readonly property int mixedEligibleCount: Retention.eligibleLessons(course, stepResults, stepCredits).length
  property string retentionNotice: ""
  property bool referenceBrowsing: false
  property bool referenceRestoreCapture: false
  property string referenceRequestPhase: ""
  readonly property string cheatSheetPath: stateHome + "/learn-omarchy/shortcuts.html"

  function startMixedPractice() {
    var plan = Retention.mixedPracticePlan(course, stepResults, stepCredits, 3)
    if (plan.length < 2) {
      retentionNotice = "Complete at least two practice-ready modules to unlock mixed practice."
      return false
    }

    retentionNotice = ""
    mixedLessonIds = plan
    mixedLessonPosition = 0
    startLesson(Retention.lessonIndex(course, plan[0]), true, false, true)
    return true
  }

  function openArcade() {
    if (!course) return
    resetLessonRuntime()
    stopAudio()
    lessonIndex = -1
    stepIndex = 0
    activeKeys = ({})
    pressedPhysicalKeys = ({})
    phase = "arcade"
    setCharacterState("hidden", "")
    renewKeyboardCapture()
  }

  function saveArcadeStats(value) {
    arcadeStats = ArcadeLogic.mergeStats(value)
    arcadeFile.setText(JSON.stringify(arcadeStats, null, 2) + "\n")
  }

  function loadArcadeStats(text) {
    try {
      arcadeStats = ArcadeLogic.mergeStats(JSON.parse(text))
    } catch (error) {
      console.warn("learn-omarchy: arcade scores could not be parsed:", error)
      arcadeStats = ArcadeLogic.defaultStats()
    }
  }

  FileView {
    id: arcadeFile
    path: root.arcadePath
    atomicWrites: true
    blockWrites: true
    printErrors: false
    onLoaded: root.loadArcadeStats(text())
    onLoadFailed: root.arcadeStats = ArcadeLogic.defaultStats()
    onSaveFailed: function(error) {
      console.warn("learn-omarchy: arcade scores could not be saved:", root.arcadePath, error)
    }
  }

  function nextMixedLesson() {
    if (!mixedPracticeActive || phase !== "lesson-complete") return
    if (mixedLessonPosition + 1 >= mixedLessonIds.length) {
      returnToMenu()
      return
    }
    var next = mixedLessonPosition + 1
    var index = Retention.lessonIndex(course, mixedLessonIds[next])
    if (index < 0) {
      returnToMenu()
      retentionNotice = "The course changed. Start a new mixed-practice session."
      return
    }
    mixedLessonPosition = next
    startLesson(index, true, false, true)
  }

  function openCheatSheet() {
    if (cheatSheetProcess.running || !course || referenceBrowsing ||
        (phase !== "menu" && phase !== "lesson-complete")) return
    referenceRequestPhase = phase
    retentionNotice = "Preparing printable shortcuts..."
    cheatSheetProcess.command = ["node", "--experimental-strip-types",
      appRoot + "/tools/generate-cheat-sheet.mjs", coursePath, cheatSheetPath]
    cheatSheetProcess.running = true
  }

  function finishCheatSheetGeneration(code, errors) {
    if (code !== 0) {
      retentionNotice = "The printable reference couldn't be generated. Try again."
      console.warn("learn-omarchy: cheat sheet generation failed:", code, errors)
      return
    }
    if (phase !== referenceRequestPhase) {
      retentionNotice = "Printable shortcuts are saved at " + cheatSheetPath + ". Open them when you're ready."
      return
    }
    var captureWasExclusive = keyboardExclusive
    setKeyboardExclusive(false)
    var url = "file://" + cheatSheetPath.split("/").map(encodeURIComponent).join("/")
    if (Qt.openUrlExternally(url)) {
      referenceRestoreCapture = captureWasExclusive
      referenceBrowsing = true
      if (welcomeStage !== "") finishWelcome()
      stopAudio()
      retentionNotice = "Shortcuts sent to your browser; it may be on another workspace. Keys are released for printing. Use the return banner when you're finished."
    } else {
      setKeyboardExclusive(captureWasExclusive)
      retentionNotice = "Couldn't open the browser. The reference is saved at " + cheatSheetPath + "; open it in your browser to print."
      console.warn("learn-omarchy: couldn't open printable reference:", url)
    }
  }

  function returnFromReference() {
    if (!referenceBrowsing) return
    referenceBrowsing = false
    var restoreCapture = referenceRestoreCapture
    referenceRestoreCapture = false
    setKeyboardExclusive(restoreCapture)
    retentionNotice = ""
  }

  function finishSplash() {
    if (!splashActive) return
    startupRevealPending = !reducedMotion
    startupOpacity = reducedMotion ? 1 : 0
    splashActive = false
    maybeBeginWelcome()
    if (!introActive) revealStartupScene()
  }
  function revealStartupScene() {
    if (!startupRevealPending) return
    startupRevealPending = false
    if (reducedMotion) startupOpacity = 1
    else startupFadeIn.restart()
  }
  NumberAnimation {
    id: startupFadeIn
    target: root
    property: "startupOpacity"
    from: 0
    to: 1
    duration: 750
    easing.type: Easing.InOutSine
  }
  readonly property var characterIndex: characterStore.packs
  property int characterPick: 0
  // "first-run" asks for a coach and proceeds on pick; "settings" stays open.
  property string settingsMode: "settings"
  property bool resetConfirmPending: false
  property bool resetOptionsExpanded: false
  onResetConfirmPendingChanged: if (resetConfirmPending) resetOptionsExpanded = true
  property bool resetJustDone: false
  property string settingsSaveError: ""
  property string progressSaveError: ""
  property string stateSaveRetry: ""
  readonly property string characterAssetRoot: resolvedPack ? resolvedPack.assetUrl : ""
  readonly property var characterConfig: resolvedPack ? resolvedPack.manifest : ({})
  readonly property string characterDisplayName: String(characterConfig.displayName || "Coach")
  readonly property bool characterFlames: Boolean(characterConfig.effects && characterConfig.effects.thrusters)
  readonly property string characterNotice: characterStore.notice
  property string integrationNotice: Quickshell.env("LEARN_OMARCHY_INTEGRATION_ERROR")
    ? "Some highlights may be approximate on this desktop." : ""
  property string introNotice: ""
  Component.onDestruction: {
    interactionAudio.stop()
    cancelIntro()
    stopAudio()
    runCleanup()
  }

  CharacterPackStore {
    id: characterStore
    appRoot: root.appRoot
    requestedId: root.requestedCharacter
    onReadyChanged: if (ready) root.characterPacksReady()
    onPacksChanged: if (ready) root.characterPacksReady()
    onSelectedPackChanged: root.syncCharacterPick()
  }

  function characterPacksReady() {
    syncCharacterPick()
    if (!characterStore.selectedPack) {
      if (settingsResolved && phase !== "loading" && phase !== "settings")
        openSettings(characterChosen() ? "settings" : "first-run")
      return
    }
    if (settingsResolved && characterChosen()) maybeBeginWelcome()
  }

  function refreshCharacters() {
    if (phase === "waiting" || phase === "highlight") {
      if (!pauseLesson()) return false
    }
    cancelIntro()
    stopAudio()
    characterStore.refresh()
    return true
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
    return String(text || "").replace(/HEXON/g, function() { return characterDisplayName })
  }

  function captionText(text) {
    var value = String(text || "")
    var paragraphStart = 0
    if (value.indexOf("\n") === -1) {
      value = value.replace(/([.!?])\s+(?=[A-Z])/g, function(match, punctuation, offset) {
        if (offset - paragraphStart < 150 || value.length - offset < 60) return match
        paragraphStart = offset + match.length
        return punctuation + "\n\n"
      })
    }
    // Keep each paragraph's last two words together without changing narration.
    return value.replace(/(\S+)[ \t]+(\S+)(?=[ \t]*(?:\n|$))/g, "$1\u00a0$2")
  }

  function characterChosen() {
    return characterOverride !== "" || savedCharacter !== ""
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
      welcomeSettingPresent = typeof parsed.welcomeSeen === "boolean"
      welcomeSeen = welcomeSettingPresent ? parsed.welcomeSeen : tourSeen
      audioEnabled = parsed.audioEnabled !== false
      speechEnabled = parsed.speechEnabled !== false
      synchronizedWelcomeText = typeof parsed.typeText === "boolean" ? parsed.typeText : parsed.synchronizedWelcomeText !== false
      effectsEnabled = parsed.effectsEnabled !== false
      speechVolume = speechEnabled ? boundedNumber(parsed.speechVolume, 80, 0, 100) : 0
      effectsVolume = effectsEnabled ? boundedNumber(parsed.effectsVolume, 45, 0, 100) : 0
      speechRate = boundedNumber(parsed.speechRate, 1, 0.75, 1.5)
      motionReduced = parsed.motionReduced === true
      autoAdvance = parsed.autoAdvance !== false
      textScale = boundedNumber(parsed.textScale, 1, 1, 1.3)
    } catch (error) {
      console.warn("learn-omarchy: settings file couldn't be parsed:", error)
      savedCharacter = ""
      tourSeen = false
      welcomeSeen = false
      welcomeSettingPresent = false
    }
    if (characterOverride === "" && savedCharacter !== "") applyCharacter(savedCharacter)
    settingsResolved = true
    if (phase === "menu" && lessonIndex < 0) {
      if (!characterChosen()) openCharacterPicker()
      else maybeBeginWelcome()
    }
  }

  function persistSettings() {
    return writeState(settingsFile, "settings", JSON.stringify({
      schemaVersion: 1,
      character: savedCharacter,
      tourSeen: tourSeen,
      welcomeSeen: welcomeSeen,
      audioEnabled: audioEnabled,
      speechEnabled: speechEnabled,
      synchronizedWelcomeText: synchronizedWelcomeText,
      typeText: synchronizedWelcomeText,
      effectsEnabled: effectsEnabled,
      speechVolume: speechVolume,
      effectsVolume: effectsVolume,
      speechRate: speechRate,
      motionReduced: motionReduced,
      autoAdvance: autoAdvance,
      textScale: textScale
    }, null, 2) + "\n")
  }

  function writeState(file, kind, text) {
    var previousError = kind === "settings" ? settingsSaveError : progressSaveError
    if (previousError !== "") {
      // FileView caches failed writes too; reload before retrying identical data.
      // Do not replace the learner's current choices with the old disk contents.
      stateSaveRetry = kind
      try {
        file.reload()
        file.waitForJob()
      } finally {
        stateSaveRetry = ""
      }
    }
    file.setText(text)
    return (kind === "settings" ? settingsSaveError : progressSaveError) === ""
  }

  function reportStateSaveFailure(kind, error) {
    var message = kind === "settings"
      ? "Settings could not be saved. Check that your state folder is writable, then try again."
      : "Lesson progress could not be saved. Check that your state folder is writable, then try again."
    if (kind === "settings") settingsSaveError = message
    else progressSaveError = message
    resetJustDone = false
    console.warn("learn-omarchy:", message, kind === "settings" ? settingsPath : progressPath, error)
  }

  function maybeBeginWelcome() {
    if (splashActive || !course || !settingsResolved || !progressResolved || !characterStore.ready ||
        !characterStore.selectedPack || !characterChosen()) return false
    if (phase !== "menu" || lessonIndex >= 0 || course.lessons.length === 0) return false
    // Only migrate an absent flag. Explicit false is a reset, even if another
    // course still has saved progress. Empty progress files are not prior use.
    if (!welcomeSettingPresent) {
      welcomeSeen = tourSeen || Object.keys(progressByCourse).some(function(id) {
        return progressByCourse[id].length > 0
      }) || Object.keys(progressDetails).some(function(id) {
        var detail = progressDetails[id] || {}
        return ["steps", "credits", "bookmarks"].some(function(key) {
          return Object.keys(detail[key] || {}).length > 0
        })
      })
      welcomeSettingPresent = true
      persistSettings()
    }
    if (welcomeSeen) return false
    // An interrupted or skipped welcome counts as seen; never trap the user in it.
    welcomeSeen = true
    persistSettings()
    startIntro()
    return true
  }

  function enterHome() {
    phase = "menu"
    if (characterStore.ready && !characterStore.selectedPack) {
      openSettings(characterChosen() ? "settings" : "first-run")
      return
    }
    selectedLessonIndex = firstIncompleteLessonIndex()
    setCharacterState("menu-point", "CHOOSE A LESSON")
    maybeBeginWelcome()
  }

  function applyCharacter(id) {
    var next = String(id || "").toLowerCase()
    if (next === "") return false
    if (next === requestedCharacter) return true
    if (phase === "waiting" || phase === "highlight") {
      if (!pauseLesson()) return false
    }
    cancelIntro()
    stopAudio()
    introNotice = ""
    requestedCharacter = next
    characterStore.select(next)
    syncCharacterPick()
    return true
  }

  function chooseCharacter(id) {
    var next = String(id || "").toLowerCase()
    if (!characterStore.ready || !characterIndex.some(function(pack) { return pack.id === next })) return
    if (!applyCharacter(next)) return
    savedCharacter = next
    persistSettings()
    if (phase === "settings" && settingsMode === "first-run") enterHome()
  }

  function openCharacterPicker() {
    openSettings("first-run")
  }

  function openSettings(mode) {
    if (phase === "loading" || phase === "error" || lessonTransitionRunning) return
    if (welcomeStage !== "") cancelIntro()
    settingsReturnToLesson = false
    if (phase === "waiting" || phase === "highlight" || phase === "paused") {
      if (phase !== "paused" && !pauseLesson()) return
      settingsReturnToLesson = true
    }
    settingsMode = mode || "settings"
    resetConfirmPending = false
    resetOptionsExpanded = false
    syncCharacterPick()
    if (!settingsReturnToLesson) stopAudio()
    phase = "settings"
    setCharacterState("hidden", "")
  }

  function closeSettings() {
    if (phase !== "settings") return
    if (!characterStore.ready || !characterStore.selectedPack) {
      if (settingsMode === "first-run") Qt.quit()
      return
    }
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
      if (!course.lessons[i].optional && !lessonCompleted(course.lessons[i])) return i
    }
    for (var j = 0; j < course.lessons.length; j++) {
      if (!lessonCompleted(course.lessons[j])) return j
    }
    return 0
  }

  function requestResetProgress() {
    if (!resetConfirmPending) {
      resetConfirmPending = true
      return
    }
    resetConfirmPending = false
    resetJustDone = false
    resetDoneTimer.stop()
    completedLessons = ({})
    stepResults = ({})
    stepCredits = ({})
    lessonBookmarks = ({})
    settingsReturnToLesson = false
    if (lessonIndex >= 0) {
      resetLessonRuntime()
      lessonIndex = -1
    }
    var progressSaved = persistProgress()
    tourSeen = false
    welcomeSeen = false
    welcomeSettingPresent = true
    // Forget the coach as well, so the next open starts like a fresh install.
    savedCharacter = ""
    var settingsSaved = persistSettings()
    resetJustDone = progressSaved && settingsSaved
    if (resetJustDone) resetDoneTimer.restart()
  }

  function moveCharacterPick(delta) {
    if (characterIndex.length === 0) return
    characterPick = Math.max(0, Math.min(characterIndex.length - 1, characterPick + delta))
  }

  readonly property string progressPath: stateHome + "/learn-omarchy/progress.json"
  property var arcadeStats: ArcadeLogic.defaultStats()
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
    if (referenceBrowsing) returnFromReference()
    tourDetailsExpanded = false
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
  property var pressedPhysicalKeys: ({})
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
  readonly property bool inlineAppSearch: currentStepIsPractice && currentStep.practice === "app-search"
  property bool practiceSessionActive: false
  property int practiceSessionGeneration: -1
  property string practiceSessionMode: ""
  property Item practiceHost: null
  property Item arcadeHost: null
  property bool exitAfterPractice: false
  readonly property bool embeddedPracticeRunning: exerciseRunning && practiceSessionActive
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
  property var windowChangeBaseline: null
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
  onAudioEnabledChanged: if (!audioEnabled) introAmbienceProcess.running = false
  property bool speechEnabled: true
  readonly property bool narrationEnabled: audioEnabled && speechEnabled && speechVolume > 0
  property bool effectsEnabled: true
  onEffectsEnabledChanged: if (!effectsEnabled) introAmbienceProcess.running = false
  property int speechVolume: 80
  property int effectsVolume: 45
  onEffectsVolumeChanged: if (effectsVolume <= 0) introAmbienceProcess.running = false
  property real speechRate: 1
  readonly property real narrationPlaybackRate: speechRate *
    boundedNumber((characterConfig.narration || {}).playbackRate, 1, 0.5, 2)
  property real textScale: 1
  property bool autoAdvance: true
  property bool tourDetailsExpanded: false
  onTourDetailsExpandedChanged: updateTourDetails()
  property real highlightStartedAt: 0
  property bool completionNarrationDone: false
  property bool audioStopRequested: false
  property string audioProcessPath: ""
  property bool lessonCaptionVisible: false
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
  property bool windowLaunchAcknowledged: true
  property bool windowOwnershipVerified: false
  property bool windowOwnershipStopping: false
  property bool windowPresentationReady: false
  property var windowPresentationSize: null
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

  readonly property color accent: appTheme.colors.accent
  readonly property color foreground: appTheme.colors.foreground
  readonly property color background: appTheme.colors.background
  readonly property color muted: appTheme.colors.muted
  readonly property color urgent: appTheme.colors.urgent
  readonly property color instruction: appTheme.colors.instruction
  OmarchyTheme { id: appTheme }
  property ThemePalette controlPalette: ThemePalette {
    backgroundColor: root.background
    foregroundColor: root.foreground
    accentColor: root.accent
    mutedColor: root.muted
  }
  onReducedMotionChanged: {
    characterTravelDuration = reducedMotion ? 0 : 900
    if (reducedMotion) {
      introAmbienceProcess.running = false
      startupFadeIn.stop()
      startupRevealPending = false
      startupOpacity = 1
    }
  }

  onSelectedLessonIndexChanged: {
    // The picker is a single column now; no lateral hop between cards.
    var nextColumn = 0
    var crossesColumn = nextColumn !== characterMenuColumn
    characterMenuColumn = nextColumn
    if (phase !== "menu" || !course) return
    if (welcomeStage !== "") finishWelcome()
    characterMenuPointTimer.stop()
    if (reducedMotion || !crossesColumn) {
      setCharacterState("menu-point", "CHOOSE A LESSON")
    } else {
      setCharacterState("menu-fly", "MOVING OVER")
      characterMenuPointTimer.restart()
    }
  }

  readonly property var currentLesson: course && lessonIndex >= 0 ? course.lessons[lessonIndex] : null
  readonly property var currentStep: currentLesson ? currentLesson.steps[stepIndex] : null
  onCurrentStepChanged: tourDetailsExpanded = false
  readonly property bool currentStepIsTour: Boolean(currentStep && currentStep.kind === "tour")
  readonly property bool currentStepIsPractice: Boolean(currentStep && currentStep.kind === "practice")
  readonly property bool currentStepClosesWindow: Boolean(currentStep &&
    Array.isArray(currentStep.completion.events) &&
    currentStep.completion.events.indexOf("closewindow") !== -1)
  readonly property bool currentStepHasNoVisibleTarget: currentStepClosesWindow || currentStepIsPractice ||
    Boolean(currentStep && currentStep.completion.windowState && currentStep.completion.windowState.specialWorkspace &&
      currentStep.completion.windowState.specialVisible !== true)
  readonly property bool currentTourTalks: currentStepIsTour && currentStep.pose === "talk"
  readonly property string tourRestingState: currentTourTalks ? "tour-talk" : "tour-point"
  readonly property string tourRestingMessage: currentTourTalks ? "HELLO!" : "LOOK HERE"
  readonly property int completedCount: {
    if (!course) return 0
    var count = 0
    for (var i = 0; i < course.lessons.length; i++) {
      if (lessonCompleted(course.lessons[i])) count++
    }
    return count
  }
  readonly property int coreLessonCount: course ? course.lessons.filter(function(lesson) { return !lesson.optional }).length : 0
  readonly property int coreCompletedCount: course ? course.lessons.filter(function(lesson) {
    return !lesson.optional && lessonCompleted(lesson)
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

  function lessonCompleted(lesson) {
    return lesson && (lesson.kind === "welcome" ? welcomeSeen : completedLessons[lesson.id] === true)
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
    if (lesson.kind === "welcome") return welcomeSeen
    return lesson.steps.every(function(step) {
      return step.optional || stepCredits[step.id] === true ||
        ["introduced", "assisted", "practiced"].indexOf(stepResults[step.id]) !== -1
    })
  }

  property bool lessonWrapupPlayed: false
  property bool lessonWrapupReady: false
  onLessonWrapupReadyChanged: if (lessonWrapupReady) playLessonWrapup()
  property bool lessonWrapupStopping: false
  property int lessonWrapupGeneration: 0

  CaptionReveal {
    id: lessonReveal
    sourceKey: (root.currentLesson ? root.currentLesson.id : "") + "/" +
      (root.currentStep ? root.currentStep.id : "") + "/" + root.lessonCaptionStage
    sourceText: root.currentStep ? String(root.lessonCaptionStage === "completion"
      ? root.currentStep.completionMessage || "" : root.currentStep.instruction || "") : ""
    displayText: root.characterText(sourceText)
    formattedText: root.captionText(displayText)
    typeText: root.synchronizedWelcomeText
    reducedMotion: root.reducedMotion
    narrationEnabled: root.narrationEnabled
    audioAvailable: root.lessonCaptionStage === "completion" ? root.completionAudioPath() !== "" : root.currentAudioPath() !== ""
    active: root.lessonCaptionVisible && (root.phase === "waiting" || root.phase === "highlight") && !root.lessonTransitionRunning
    paused: root.phase === "paused" || root.phase === "settings" || root.audioPaused
    wordsPerMinute: Math.round(root.readingWordsPerMinute * root.narrationPlaybackRate)
  }
  readonly property string lessonCaptionStage: phase === "highlight" ||
    ((phase === "paused" || phase === "settings") && pausedPhase === "highlight") ? "completion" : "instruction"

  function lessonCaptionMatches(message) {
    return message === lessonReveal.displayText
  }

  function lessonRevealEnd(message) {
    // Practice recall prompts and expanded tour details have no matching recording.
    if (practiceMode && lessonCaptionStage === "instruction" && narrationEnabled && !lessonReveal.playing) return -1
    return lessonCaptionMatches(message) ? lessonReveal.revealEnd : -1
  }

  function receiveLessonPlayback(raw, generation, stepId, stage) {
    if (!audioProcess.running || audioStopRequested || !currentStep ||
        currentStep.id !== stepId || stage !== lessonCaptionStage) return
    lessonReveal.receive(raw, generation)
  }

  CaptionReveal {
    id: wrapupReveal
    sourceKey: root.currentLesson ? root.currentLesson.id : ""
    sourceText: root.currentLessonWrapup() ? root.currentLessonWrapup().text : ""
    displayText: root.characterText(sourceText)
    formattedText: root.captionText(displayText)
    typeText: root.synchronizedWelcomeText
    reducedMotion: root.reducedMotion
    narrationEnabled: root.narrationEnabled
    audioAvailable: root.currentLessonWrapup() !== null &&
      characterStore.audioPath(root.currentLessonWrapup().audio, sourceText, root.courseDir) !== ""
    active: root.lessonWrapupReady && root.phase === "lesson-complete"
    wordsPerMinute: Math.round(root.readingWordsPerMinute * root.narrationPlaybackRate)
  }

  function timedSpeechCommand(path) {
    return ["node", appRoot + "/tools/play-timed-speech.mjs", "--volume", String(speechVolume),
      "--speed", String(narrationPlaybackRate), "--audio", path]
  }

  function currentLessonWrapup() {
    if (!course || !currentLesson || !currentLesson.wrapUp) return null
    var result = lessonResultSummary(currentLesson)
    if (course.wrapUp && (result.skipped > 0 || result.remaining > 0)) return course.wrapUp.explored
    if (course.wrapUp && result.assisted > 0) return course.wrapUp.assisted
    return currentLesson.wrapUp
  }

  function playLessonWrapup() {
    if (!lessonWrapupReady || phase !== "lesson-complete" || characterState !== "celebrate" || lessonTransitionRunning ||
        lessonWrapupPlayed || lessonWrapupStopping || !narrationEnabled) return
    var message = currentLessonWrapup()
    if (!message) return
    var path = characterStore.audioPath(message.audio, message.text, courseDir)
    if (path === "") return
    lessonWrapupPlayed = true
    lessonWrapupSpeech.generation = lessonWrapupGeneration
    lessonWrapupSpeech.captionGeneration = wrapupReveal.beginPlayback()
    lessonWrapupSpeech.command = timedSpeechCommand(path)
    lessonWrapupSpeech.running = true
  }

  function stopLessonWrapup() {
    wrapupReveal.cancel()
    lessonWrapupGeneration++
    if (lessonWrapupSpeech.running) {
      lessonWrapupStopping = true
      lessonWrapupSpeech.running = false
    }
  }

  function lessonWrapupExited(exitCode, generation) {
    if (lessonWrapupStopping) {
      lessonWrapupStopping = false
      playLessonWrapup()
      return
    }
    if (generation !== lessonWrapupGeneration || phase !== "lesson-complete") return
    wrapupReveal.finish(lessonWrapupSpeech.captionGeneration, exitCode)
    if (exitCode !== 0) console.warn("learn-omarchy: lesson wrap-up audio unavailable; the message remains visible")
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
      audioProcess.write(JSON.stringify({ command: "pause" }) + "\n")
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
    if (narrationEnabled && audioPaused && audioProcess.running &&
        (audioProcessPath === currentAudioPath() || audioProcessPath === completionAudioPath())) {
      audioProcess.write(JSON.stringify({ command: "resume" }) + "\n")
      audioPaused = false
      resumedAudio = true
    } else if (audioPaused) {
      stopAudio()
    }
    if (phase === "highlight") {
      setCharacterState("target-point", "HERE IT IS")
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
  readonly property color panelColor: background
  readonly property color panelBorder: colorWithAlpha(foreground, 0.16)
  readonly property color subtleFill: Qt.tint(panelColor, colorWithAlpha(foreground, 0.06))
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
    property string icon: ""
    readonly property var iconPaths: ({
      settings: "M9 3H15L16 6L19 7L22 11L20 14L20 17L15 21L12 20L9 21L4 17L4 14L2 11L5 7L8 6Z M16 12A4 4 0 1 0 8 12A4 4 0 1 0 16 12",
      keyboard: "M3 5H21V19H3Z M6 9H7 M11 9H12 M16 9H17 M6 12H7 M11 12H12 M16 12H17 M7 16H17",
      "keyboard-off": "M3 5H21V19H3Z M6 9H7 M11 9H12 M16 9H17 M7 16H17 M2 2L22 22",
      volume: "M3 9H7L12 5V19L7 15H3Z M16 8Q20 12 16 16 M19 4Q26 12 19 20",
      muted: "M3 9H7L12 5V19L7 15H3Z M16 9L22 15 M22 9L16 15",
      play: "M7 4L20 12L7 20Z",
      pause: "M7 4V20 M17 4V20",
      help: "M22 12A10 10 0 1 0 2 12A10 10 0 1 0 22 12 M9 8C9 4 17 5 15 9L12 12V14 M12 17V18",
      skip: "M4 5L15 12L4 19Z M19 5V19",
      close: "M6 6L18 18 M18 6L6 18"
    })
    signal clicked()
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: label
    Accessible.description: description
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
    z: hovered || activeFocus ? 200 : 0
    readonly property real windowX: {
      var position = x
      for (var ancestor = parent; ancestor; ancestor = ancestor.parent) position += ancestor.x
      return position
    }

    implicitWidth: icon !== "" ? implicitHeight : buttonLabel.implicitWidth + (compact ? 24 : 32)
    implicitHeight: icon !== "" ? 44 * root.textScale : compact ? 32 : 40
    radius: 9
    color: !enabled ? root.subtleFill : primary
      ? (hovered ? Qt.lighter(root.accent, 1.18) : root.accent)
      : danger
        ? Qt.tint(root.panelColor, root.colorWithAlpha(root.urgent, hovered ? 0.34 : 0.14))
        : ghost
          ? Qt.tint(root.panelColor, root.colorWithAlpha(root.foreground, hovered ? 0.16 : 0.06))
          : Qt.tint(root.panelColor, root.colorWithAlpha(root.accent, hovered ? 0.36 : 0.16))
    border.width: activeFocus ? 3 : 1
    border.color: !enabled ? root.panelBorder : primary
      ? root.accent
      : danger
        ? root.colorWithAlpha(root.urgent, 0.7)
        : ghost
          ? root.colorWithAlpha(root.foreground, 0.2)
          : root.colorWithAlpha(root.accent, 0.55)

    Behavior on color { ColorAnimation { duration: 110 } }

    Text {
      id: buttonLabel
      visible: button.icon === ""
      anchors.centerIn: parent
      text: button.label
      textFormat: Text.PlainText
      color: !button.enabled ? root.muted : button.primary ? root.controlPalette.highlightedText : root.foreground
      font.family: "monospace"
      font.pixelSize: (button.compact ? 11 : 12) * root.textScale
      font.weight: Font.Bold
      font.letterSpacing: 1.1
    }

    Image {
      visible: button.icon !== ""
      anchors.centerIn: parent
      width: 22 * root.textScale
      height: width
      sourceSize.width: width
      sourceSize.height: height
      source: button.icon === "" ? "" : "data:image/svg+xml;utf8," + encodeURIComponent(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" stroke="'
        + (!button.enabled ? root.muted : button.primary ? root.controlPalette.highlightedText : root.foreground)
        + '" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" d="'
        + button.iconPaths[button.icon] + '"/></svg>')
    }

    MouseArea {
      id: buttonMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: button.clicked()
    }

    Rectangle {
      objectName: "buttonTooltip"
      visible: button.enabled && (button.hovered || button.activeFocus)
        && (button.icon !== "" || button.description !== button.label)
      z: 100
      anchors.top: parent.bottom
      anchors.topMargin: 6
      x: Math.max(8 - button.windowX, button.width - width)
      width: Math.min(320 * root.textScale, hintText.implicitWidth + 20)
      height: hintText.implicitHeight + 14
      radius: 6
      color: root.panelColor
      opacity: 1
      border.color: root.muted
      Text {
        id: hintText
        anchors.centerIn: parent
        width: parent.width - 20
        text: button.description === button.label ? button.label : button.label + "\n" + button.description
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        color: root.foreground
        font.pixelSize: 12 * root.textScale
      }
    }
  }

  component PreferenceSwitch: Controls.Switch {
    id: preference
    property string description: ""
    font.pixelSize: 16 * root.textScale
    Accessible.name: text
    Accessible.description: description
    ThemePalette { target: preference; colors: appTheme.colors }
    Keys.onPressed: function(event) { root.handleSystemVolumeKey(event) }
    Controls.ToolTip.visible: hovered && description !== ""
    Controls.ToolTip.text: description
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
      textFormat: Text.PlainText
      color: root.foreground
      font.pixelSize: 13 * root.textScale
      wrapMode: Text.WordWrap
    }
    Controls.Slider {
      id: preferenceControl
      Keys.onPressed: function(event) { root.handleSystemVolumeKey(event) }
      ThemePalette { target: preferenceControl; colors: appTheme.colors }
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
      color: keycap.active ? Qt.darker(root.accent, 1.5) : Qt.tint(root.panelColor, root.colorWithAlpha(root.foreground, 0.28))
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
      color: keycap.isPlus ? root.muted : (keycap.active ? root.controlPalette.highlightedText : root.foreground)
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
      setCharacterState("celebrate", "STEP COMPLETE")
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
      lessonWrapupPlayed = false
      wrapupReveal.reset()
      phase = "lesson-complete"
      if (lessonFullyExplored(currentLesson)) interactionAudio.notify("module-complete")
      if (reducedMotion) {
        setCharacterState("celebrate", lessonFullyExplored(currentLesson) ? "MODULE COMPLETE!" : "MODULE EXPLORED")
      } else {
        setCharacterState("module-fly", "LESSON FINISHED")
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
      : ["node", appRoot + "/tools/bar-geometry.mjs"]
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
        integrationNotice = ""
        return
      }
      geometryProviderAvailable = false
      integrationNotice = "Some highlights may be approximate on this desktop."
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
      if (widgets && widgets.version === 1) {
        if (!parseProviderGeometry(raw, requestScreens || geometryScreens()))
          throw new Error("bar layer measurement doesn't match this desktop")
        return
      }
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
    if (rect && ["top", "bottom", "left", "right"].indexOf(widgets[0].barEdge) !== -1 &&
        widgets.every(function(widget) { return widget.barEdge === widgets[0].barEdge }))
      rect.barEdge = widgets[0].barEdge
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
    if (phase !== "waiting" || !currentStep || actionRunning) return
    if (currentStep.completion.type === "hyprland-workspace-is") {
      if (currentWorkspaceId() === Number(currentStep.completion.id)) {
        restoreActionKeyboard()
        completeCurrentStep()
      }
      else if (++workspaceCheckAttempts < 5) workspaceCompletionTimer.restart()
      else if (!actionRunning && actionStepId === currentStep.id) {
        clearActiveKeys()
        showRecovery("The requested workspace isn't active yet. Try the shortcut again, or choose Help.", "")
      }
      return
    }
    if (currentStep.completion.type !== "hyprland-workspace-change" || workspaceStartId < 0) return
    var activeWorkspaceId = currentWorkspaceId()
    if (activeWorkspaceId >= 0 && activeWorkspaceId !== workspaceStartId) {
      restoreActionKeyboard()
      completeCurrentStep()
      return
    }
    workspaceCheckAttempts++
    if (workspaceCheckAttempts < 5) workspaceCompletionTimer.restart()
    else if (actionStepId === currentStep.id) {
      clearActiveKeys()
      showRecovery("The workspace hasn't changed yet. Try the shortcut again, or choose Help.", "")
    }
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
    if (lesson && lesson.kind === "welcome") return "WELCOME"
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
      if (key && ["SUPER", "CTRL", "ALT", "SHIFT"].indexOf(key) === -1 &&
          !lessonTransitionRunning && !actionRunning) interactionAudio.notify("wrong")
      setCharacterState("incorrect", "TRY THE HIGHLIGHTED KEYS")
      characterReactionTimer.interval = 680
    }
    characterReactionTimer.restart()
  }

  // The pack owns the scene; the host owns the welcome and menu handoff.
  property string welcomeStage: ""
  property var welcomeNarration: null
  property bool welcomeNarrationStarted: false
  property bool welcomeNarrationFinished: false
  property bool welcomeSpeechStopping: false
  property bool synchronizedWelcomeText: true
  property alias welcomeWordTimings: welcomeReveal.words
  property alias welcomeTimingText: welcomeReveal.timingText
  property alias welcomePlaybackMs: welcomeReveal.positionMs
  property alias welcomeTimingFailed: welcomeReveal.failed
  property bool welcomeReadingActive: false
  property bool welcomeCaptionVisible: false
  onWelcomeCaptionVisibleChanged: if (!welcomeCaptionVisible) welcomeReadTimer.stop()
  property alias welcomeReadingElapsed: welcomeReveal.readingElapsed
  property alias welcomeReadingStartOffset: welcomeReveal.readingStartOffset
  readonly property int welcomeRevealEnd: welcomeReveal.revealEnd

  CaptionReveal {
    id: welcomeReveal
    sourceKey: root.introGeneration + "/" + root.welcomeStage
    sourceText: root.welcomeInstruction()
    displayText: root.welcomeText
    formattedText: root.captionText(displayText)
    typeText: root.synchronizedWelcomeText
    reducedMotion: root.reducedMotion
    narrationEnabled: root.narrationEnabled && !root.welcomeReadingActive
    audioAvailable: root.welcomeAudioPath() !== ""
    active: root.welcomeReadingActive && root.welcomeCaptionVisible
    wordsPerMinute: Math.round(root.readingWordsPerMinute * root.narrationPlaybackRate)
  }

  function welcomeAudioPath() {
    if (!welcomeNarration) return ""
    var audio = welcomeStage === "recommendation" ? welcomeNarration.recommendationAudio :
      welcomeStage === "controls" ? welcomeNarration.controls?.audio : welcomeNarration.audio
    return characterStore.audioPath(audio, welcomeInstruction(), appRoot + "/courses")
  }

  function resetWelcomeReading() {
    welcomeReadingActive = false
    welcomeReadingElapsed = 0
    welcomeReadingStartOffset = 0
  }

  function receiveWelcomePlayback(raw, generation, stage) {
    if (generation !== introGeneration || stage !== welcomeStage || welcomeSpeechStopping ||
        !welcomeSpeech.running) return
    welcomeReveal.receive(raw, welcomeSpeech.captionGeneration)
  }

  function welcomeInstruction() {
    if (!welcomeNarration) return "Welcome to Omarchy! Let's look at what you can learn."
    if (welcomeStage === "recommendation") return welcomeNarration.recommendation
    if (welcomeStage === "controls" && welcomeNarration.controls) return welcomeNarration.controls.instruction
    var instructions = welcomeNarration.instructions
    return instructions && Object.prototype.hasOwnProperty.call(instructions, characterName)
      ? instructions[characterName] : welcomeNarration.instruction
  }

  readonly property string welcomeText: welcomeStage === "welcome" || welcomeStage === "controls"
    ? characterText(welcomeInstruction())
    : (welcomeNarration && welcomeNarration.recommendation
      ? welcomeNarration.recommendation : "Choose a lesson to get started.")
  property bool introActive: false
  onIntroActiveChanged: if (!introActive) revealStartupScene()
  property int introGeneration: 0
  property bool introPlaybackStarted: false
  property bool introDeparting: false
  signal introPlaybackRequested(int generation)
  signal introCancellationRequested(bool keepPosition)
  signal introHandoffRequested(int generation)
  signal introReleaseRequested()

  function startIntro() {
    if (!characterStore.ready || !characterStore.selectedPack) return
    cancelIntro()
    stopAudio()
    phase = "welcome"
    welcomeStage = "scene"
    introNotice = ""
    introActive = true
    setCharacterState("intro", "")
    introStartTimer.restart()
  }

  function beginIntroScene() {
    if (!introActive || phase !== "welcome" || welcomeStage !== "scene" || characterState !== "intro") return
    introStartTimer.stop()
    introPlaybackRequested(introGeneration)
  }

  function cancelIntro(keepPosition) {
    // Invalidate callbacks before cancelling players: cancellation emits synchronously.
    introGeneration++
    introStartTimer.stop()
    welcomeReadTimer.stop()
    resetWelcomeReading()
    stopWelcomeSpeech()
    welcomeNarrationStarted = false
    welcomeNarrationFinished = false
    if (!keepPosition) {
      var wasWelcome = welcomeStage !== ""
      welcomeStage = ""
      if (wasWelcome && (phase === "welcome" || phase === "menu")) {
        phase = "menu"
        setCharacterState("menu-point", "CHOOSE A LESSON")
      }
    }
    introActive = false
    introPlaybackStarted = false
    introDeparting = false
    introCancellationRequested(Boolean(keepPosition))
    if (sfxProcess.running) sfxProcess.running = false
    if (!keepPosition && introAmbienceProcess.running) introAmbienceProcess.running = false
  }

  function skipIntroScene() {
    if (phase !== "welcome" || !introActive) return
    finishIntro(introGeneration)
  }

  function finishIntro(generation, message) {
    if (generation !== introGeneration || !introActive || phase !== "welcome" || welcomeStage !== "scene") return
    if (message) {
      introNotice = String(message)
      console.warn("learn-omarchy: intro:", message)
    }
    introHandoffRequested(generation)
    cancelIntro(true)
    introDeparting = true
    welcomeStage = "center-flight"
    var nextGeneration = introGeneration
    // Keep the last body position pinned until normal travel bindings are enabled.
    setCharacterState("tour-fly", "")
    Qt.callLater(function() {
      if (introGeneration !== nextGeneration || phase !== "welcome" || welcomeStage !== "center-flight") return
      introReleaseRequested()
    })
  }

  function welcomeArrived(generation) {
    if (generation !== introGeneration) return
    if (phase === "welcome" && welcomeStage === "center-flight") {
      introDeparting = false
      welcomeStage = "welcome"
      setCharacterState("tour-talk", "")
    } else if (phase === "welcome" && welcomeStage === "controls-flight") {
      welcomeStage = "controls"
      setCharacterState("tour-point", "")
    } else if (phase === "menu" && welcomeStage === "menu-flight") {
      welcomeStage = "recommendation"
      setCharacterState("menu-point", "")
    }
  }

  function welcomeCaptionShown() {
    if (welcomeStage !== "welcome" && welcomeStage !== "controls" && welcomeStage !== "recommendation") return
    if (!narrationEnabled) welcomeReadingActive = true
    if (narrationEnabled && !welcomeReadingActive && welcomeNarration && !welcomeNarrationFinished) {
      var path = welcomeAudioPath()
      if (path !== "") {
        if (welcomeSpeechStopping) return
        if (!welcomeNarrationStarted) {
          welcomeSpeech.captionGeneration = welcomeReveal.beginPlayback()
          welcomeNarrationStarted = true
          welcomeSpeech.generation = introGeneration
          welcomeSpeech.stage = welcomeStage
          welcomeSpeech.command = timedSpeechCommand(path)
          welcomeSpeech.running = true
        }
        return
      }
    }
    if (welcomeReadTimer.running && welcomeReadTimer.generation === introGeneration &&
        welcomeReadTimer.stage === welcomeStage) return
    welcomeReadTimer.generation = introGeneration
    welcomeReadTimer.stage = welcomeStage
    welcomeReadTimer.interval = readingDuration(welcomeText)
    welcomeReadTimer.restart()
  }

  function stopWelcomeSpeech() {
    welcomeReveal.cancel()
    if (!welcomeSpeech.running) return
    welcomeSpeechStopping = true
    welcomeSpeech.running = false
  }

  function welcomeSpeechExited(exitCode, generation, stage) {
    if (welcomeSpeechStopping) {
      welcomeSpeechStopping = false
      if ((phase === "welcome" && (welcomeStage === "welcome" || welcomeStage === "controls")) ||
          (phase === "menu" && welcomeStage === "recommendation")) welcomeCaptionShown()
      return
    }
    if (generation !== introGeneration || welcomeStage !== (stage || "welcome")) return
    welcomeReveal.finish(welcomeSpeech.captionGeneration, exitCode)
    welcomeNarrationFinished = true
    if (exitCode !== 0) {
      console.warn("learn-omarchy: welcome narration failed; using reading time")
      welcomeCaptionShown()
    } else {
      welcomeReadTimer.generation = introGeneration
      welcomeReadTimer.stage = welcomeStage
      welcomeReadTimer.interval = narrationRestMs
      welcomeReadTimer.restart()
    }
  }

  function advanceWelcome(generation, stage) {
    if (generation !== introGeneration || stage !== welcomeStage) return
    if (stage === "scene") skipIntroScene()
    else if (stage === "welcome" || stage === "controls") {
      welcomeReadTimer.stop()
      resetWelcomeReading()
      stopWelcomeSpeech()
      welcomeNarrationStarted = false
      welcomeNarrationFinished = false
      if (stage === "welcome" && welcomeNarration && welcomeNarration.controls) {
        welcomeStage = "controls-flight"
        setCharacterState("tour-fly", "")
        return
      }
      welcomeStage = "menu-flight"
      selectedLessonIndex = course && course.lessons[0].kind === "welcome" && course.lessons.length > 1 ? 1 : 0
      phase = "menu"
      setCharacterState("menu-fly", "")
    } else if (stage === "recommendation") finishWelcome()
  }

  function finishWelcome() {
    if (welcomeStage === "") return
    cancelIntro()
    phase = "menu"
    setCharacterState("menu-point", "CHOOSE A LESSON")
  }

  function startCharacterStep() {
    if (currentStepIsTour) {
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
      setCharacterState("step-fly", "ON MY WAY")
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
    if (phase !== "waiting" || !currentStepIsTour || introActive) return
    if (introDeparting && characterState !== tourRestingState) return
    introDeparting = false
    if (narrationEnabled && currentAudioPath() !== "") {
      playCurrentAudio(true)
      return
    }
    scheduleTourAdvance(tourFallbackDuration())
  }

  function canAutoAdvanceTour() {
    return phase === "waiting" && currentStepIsTour && autoAdvance && !tourDetailsExpanded &&
      !introActive && !introDeparting &&
      !audioProcess.running && !audioStopRequested && pendingAudioPath === ""
  }

  function updateTourDetails() {
    tourAdvanceTimer.stop()
    if (!tourDetailsExpanded)
      scheduleTourAdvance(Math.max(narrationRestMs, readingDuration(currentStep ? currentStep.detail : "")))
  }

  function scheduleTourAdvance(delay) {
    if (!canAutoAdvanceTour() || (lessonTransitionRunning && pendingLessonTransition !== "")) return
    tourAdvanceTimer.interval = delay === undefined ? Math.max(narrationRestMs, tourAdvanceDelay()) : delay
    tourAdvanceTimer.restart()
  }

  function advanceTour() {
    if (canAutoAdvanceTour() && !lessonTransitionRunning) advance()
  }

  function openedToolKeyboardHint() {
    return phase === "highlight" && keyboardExclusive && currentStep &&
      currentStep.completion.type === "hyprland-layer-open" &&
      !/release keys|releasing (?:the )?keys/i.test(currentStep.completionMessage || "")
      ? "Use Release Keys to interact with the opened tool." : ""
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
    if (key === Qt.Key_Minus) return "MINUS"
    if (key === Qt.Key_Equal) return "EQUAL"
    if (key === Qt.Key_Comma) return "COMMA"
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

    var scan = Number(event.nativeScanCode) || 0
    var physical = Object.assign({}, pressedPhysicalKeys)
    var direct = scan > 0 && physical[scan] ? physical[scan] : keyName(event.key)
    var expectedKeys = phase === "arcade" && arcadeHost ? arcadeHost.expectedKeys : currentStepKeys
    if (expectedKeys.indexOf("MINUS") !== -1 && scan === 20) direct = "MINUS"
    if (expectedKeys.indexOf("EQUAL") !== -1 && scan === 21) direct = "EQUAL"
    // Wayland exposes XKB scan codes: the number row is 10-19. Shift
    // changes Qt's logical key (for example 2 becomes @), not the keycap.
    if (!direct && (event.modifiers & Qt.ShiftModifier) && scan >= 10 && scan <= 19)
      direct = String((scan - 9) % 10)
    if (scan > 0) {
      if (pressed) physical[scan] = direct || "__KEY_" + event.key
      else delete physical[scan]
    }
    pressedPhysicalKeys = physical
    if (pressed && direct) next[direct] = true
    else if (!pressed && direct) delete next[direct]
    else {
      var unsupported = "__KEY_" + event.key
      if (pressed) next[unsupported] = true
      else delete next[unsupported]
    }
    activeKeys = next
    if (pressed) {
      if (phase === "arcade") {
        if (!event.isAutoRepeat && arcadeHost) arcadeHost.handleKeyPress(direct, Object.keys(next))
        return
      }
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
    pressedPhysicalKeys = {}
    comboTriggered = false
  }

  function confirmDetectedShortcut() {
    var expected = expectedKeyMap()
    var confirmed = {}
    for (var key in expected) confirmed[key] = true
    activeKeys = confirmed
    comboTriggered = true
    setCharacterState("celebrate", "STEP COMPLETE")
    layerCompletionFeedbackTimer.restart()
  }

  function normalizedWindowAddress(value) {
    var address = String(value || "").trim()
    if (address === "") return ""
    return address.indexOf("0x") === 0 ? address : "0x" + address
  }

  function resetWindowTarget() {
    windowGeometryGeneration++
    windowLaunchToken = ""
    windowLaunchAcknowledged = true
    tutorialLaunchProcess.running = false
    stopWindowOwnership()
    windowOwnershipVerified = false
    if (usesWindowActivation()) {
      actionRunning = false
      actionStepId = ""
    }
    windowPresentationProcess.running = false
    windowPresentationReady = false
    windowPresentationSize = null
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
    requestBarGeometry()
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
    var expectedChange = currentStep.completion.windowState
    if ((expectedChange.resized || expectedChange.splitChanged) &&
        (actionRunning || actionStepId !== currentStep.id || !windowChangeBaseline)) return
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
    if (outcomeProcess.running || scratchpadVisibilityProcess.running) {
      outcomeRetryTimer.restart()
      return
    }
    outcomeProcess.requestGeneration = outcomeGeneration
    outcomeProcess.running = true
  }

  function matchesWindowState(client, expected) {
    if (!client || client.mapped === false ||
        (client.hidden === true && (!expected.specialWorkspace || expected.focused === true))) return false
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
    if (outcomeExpected && (outcomeExpected.resized || outcomeExpected.splitChanged) &&
        (actionRunning || !currentStep || actionStepId !== currentStep.id || !windowChangeBaseline)) return
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
    var changedAsExpected = true
    if (outcomeExpected.resized)
      changedAsExpected = WindowOutcomes.resized(windowChangeBaseline && windowChangeBaseline.first, client)
    if (outcomeExpected.splitChanged) {
      var splitPeer = clients.find(function(item) {
        return item && normalizedWindowAddress(item.address) === currentPeerWindow()
      })
      changedAsExpected = WindowOutcomes.splitChanged(windowChangeBaseline, client, splitPeer)
    }
    if (pairSwapped && changedAsExpected && matchesWindowState(client, outcomeExpected)) {
      if (outcomeExpected.specialVisible !== undefined) {
        if (!Number.isInteger(client.monitor)) {
          retryOutcome()
          return
        }
        scratchpadVisibilityProcess.requestGeneration = generation
        scratchpadVisibilityProcess.monitorId = client.monitor
        scratchpadVisibilityProcess.verifiedWindow = client
        scratchpadVisibilityProcess.running = true
        return
      }
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
    retryOutcome()
  }

  function retryOutcome() {
    if (++outcomeAttempts < windowGeometryMaxAttempts) {
      outcomeRetryTimer.restart()
    } else {
      outcomeAddress = ""
      clearActiveKeys()
      showRecovery("The expected window change hasn't happened. Try again, or return to the tutorial window's launch activity.", currentStep.windowFromStep)
    }
  }

  function parseScratchpadVisibility(raw, generation, monitorId, exitCode, windowData) {
    if (generation !== outcomeGeneration || phase !== "waiting" || outcomeAddress === "") return
    if (currentTutorialWindow() !== outcomeAddress) {
      outcomeAddress = ""
      clearActiveKeys()
      showRecovery("The scratchpad's tutorial window is no longer available. Reopen it to continue.", currentStep.windowFromStep)
      return
    }
    var monitors
    try {
      if (exitCode !== 0) throw new Error("monitor query failed")
      monitors = JSON.parse(raw)
      if (!Array.isArray(monitors)) throw new Error("invalid monitor response")
    } catch (error) {
      outcomeAddress = ""
      clearActiveKeys()
      showRecovery("Couldn't verify scratchpad visibility. Try again.", currentStep.windowFromStep)
      console.warn("learn-omarchy: scratchpad visibility unavailable:", error)
      return
    }
    var monitor = monitors.find(function(item) { return item && Number(item.id) === monitorId })
    if (!monitor || !monitor.specialWorkspace || typeof monitor.specialWorkspace.name !== "string") {
      retryOutcome()
      return
    }
    var visible = monitor.specialWorkspace.name === "special:" + outcomeExpected.specialWorkspace
    if (visible !== outcomeExpected.specialVisible) {
      retryOutcome()
      return
    }
    if (visible) {
      if (!clientGeometryReady(windowData) || normalizedWindowAddress(windowData.address) !== outcomeAddress) {
        retryOutcome()
        return
      }
      targetWindowAddress = outcomeAddress
      outcomeAddress = ""
      completeWindowDetection(windowData, monitor)
      return
    }
    outcomeAddress = ""
    targetWindowGeometry = null
    targetMonitorGeometry = null
    restoreActionKeyboard()
    confirmDetectedShortcut()
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
    if (!windowLaunchAcknowledged) {
      windowOwnershipVerified = true
      return
    }
    windowOwnershipVerified = false
    rememberTutorialWindow(pendingTutorialWindowAddress, currentStep.id)
    if (currentStep.windowSize) {
      if (!windowPresentationReady) {
        prepareTutorialWindow()
        return
      }
      if (!targetWindowGeometry || !windowPresentationSize ||
          !targetWindowGeometry.floating ||
          targetWindowGeometry.size[0] < windowPresentationSize.width - 4 ||
          targetWindowGeometry.size[1] < windowPresentationSize.height - 4) {
        retryWindowGeometry("The activity window still needs enough room to show its contents.")
        return
      }
    }
    completeWindowDetection(targetWindowGeometry, targetMonitorGeometry)
  }

  function prepareTutorialWindow() {
    if (windowPresentationProcess.running) return
    if (!targetMonitorGeometry || tutorialWindows.indexOf(pendingTutorialWindowAddress) === -1) {
      retryWindowGeometry("The owned window's display isn't available.")
      return
    }
    var monitor = targetMonitorGeometry
    var size = logicalMonitorSize(monitor)
    var width = Math.floor(Math.min(currentStep.windowSize.width, size.width - 80))
    var height = Math.floor(Math.min(currentStep.windowSize.height, size.height * 0.55))
    var x = Math.round(Number(monitor.x) + (size.width - width) / 2)
    var y = Math.round(Number(monitor.y) + 70)
    if (![width, height, x, y].every(Number.isFinite) || width < 960 || height < 360) {
      resetWindowTarget()
      actionRunning = false
      clearActiveKeys()
      showRecovery("This display doesn't have enough room to show the activity monitor clearly. Use a larger display, or Skip.")
      return
    }
    windowPresentationSize = { width: width, height: height }
    var selector = "window=" + JSON.stringify("address:" + pendingTutorialWindowAddress)
    windowPresentationProcess.requestGeneration = windowGeometryGeneration
    windowPresentationProcess.command = ["hyprctl", "eval",
      "hl.dispatch(hl.dsp.window.float({" + selector + ", action=\"on\"})); " +
      "hl.dispatch(hl.dsp.window.resize({" + selector + ", x=" + width + ", y=" + height + ", relative=false})); " +
      "hl.dispatch(hl.dsp.window.move({" + selector + ", x=" + x + ", y=" + y + ", relative=false}))"]
    windowPresentationProcess.running = true
  }

  function finishWindowPresentation(exitCode, generation) {
    if (generation !== windowGeometryGeneration || phase !== "waiting" || !windowGeometryPending) return
    if (exitCode !== 0) {
      resetWindowTarget()
      actionRunning = false
      clearActiveKeys()
      showRecovery("Couldn't give the activity monitor enough room. Try launching it again, or Skip.")
      return
    }
    windowPresentationReady = true
    queryWindowGeometry()
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
    interactionAudio.notify("correct")
    runStepAction("shortcut")
  }

  function fail(message) {
    resetLessonRuntime()
    errorMessage = String(message)
    phase = "error"
    setCharacterState("hidden", "")
    console.error("learn-omarchy:", errorMessage)
  }

  function coreLessonsFirst(lessons) {
    return lessons.filter(function(lesson) { return !lesson.optional })
      .concat(lessons.filter(function(lesson) { return lesson.optional }))
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
    parsed.lessons = coreLessonsFirst(parsed.lessons)
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
    if (phase === "menu" && lessonIndex < 0 && characterChosen()) maybeBeginWelcome()
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
    return writeState(progressFile, "progress", JSON.stringify({
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
  function resetLessonRuntime(preserveMixed) {
    if (!preserveMixed) {
      mixedLessonIds = []
      mixedLessonPosition = 0
    }
    interactionAudio.stop()
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

  function isOpeningTour(index) {
    if (!course) return false
    var openingIndex = course.lessons[0].kind === "welcome" ? 1 : 0
    var lesson = course.lessons[index]
    return Boolean(index === openingIndex && lesson && lesson.steps[0] && lesson.steps[0].kind === "tour")
  }

  function startLesson(index, practice, resume, preserveMixed) {
    if (!course || !characterStore.ready || !characterStore.selectedPack ||
        index < 0 || index >= course.lessons.length) return
    resetLessonRuntime(preserveMixed)
    selectedLessonIndex = index
    if (course.lessons[index].kind === "welcome") {
      lessonIndex = -1
      practiceMode = false
      welcomeSeen = true
      welcomeSettingPresent = true
      persistSettings()
      startIntro()
      return
    }
    lessonIndex = index
    stepIndex = 0
    practiceMode = practice === true
    var startsWithTour = isOpeningTour(index)
    if (resume !== false && !practiceMode && !startsWithTour) {
      var bookmark = lessonBookmarks[course.lessons[index].id]
      for (var i = 0; i < course.lessons[index].steps.length; i++) {
        if (course.lessons[index].steps[i].id === bookmark) stepIndex = i
      }
    }
    errorMessage = ""
    if (startsWithTour && !tourSeen) {
      tourSeen = true
      persistSettings()
    }
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
    lessonReveal.reset()
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
    windowChangeBaseline = null
    windowBaselineProcess.running = false
    layoutPreflightProcess.running = false
    windowLaunchToken = ""
    stopWindowOwnership()
    tutorialLaunchProcess.running = false
    windowOwnershipVerified = false
    directionPreviewTimer.stop()
    directionPreviewProcess.running = false
    if (exerciseRunning) {
      exerciseRunning = false
      if (exerciseRestoreCapture) setKeyboardExclusive(true)
      exerciseRestoreCapture = false
      practiceProcess.running = false
    }
    if (practiceSessionActive && practiceLoader.item) practiceLoader.item.cancel()
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
    cancelIntro()
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
    var peerStep = currentStep && (currentStep.swapWithStep || currentStep.pairWithStep)
    var address = peerStep ? tutorialWindowsByStep[peerStep] : ""
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

  function failWindowPreflight(message) {
    windowChangeBaseline = null
    actionRunning = false
    actionStepId = ""
    clearActiveKeys()
    restoreActionKeyboard()
    showRecovery(message, currentStep && currentStep.windowFromStep || "")
  }

  function parseWindowBaseline(raw, generation) {
    if (generation !== actionGeneration || !actionRunning || !currentStep) return
    var clients
    try {
      clients = JSON.parse(raw)
      if (!Array.isArray(clients)) throw new Error("Expected a window list")
    } catch (error) {
      failWindowPreflight("Couldn't measure the practice windows. Try again.")
      return
    }
    var client = clients.find(function(item) {
      return item && normalizedWindowAddress(item.address) === currentTutorialWindow()
    })
    var peer = clients.find(function(item) {
      return item && normalizedWindowAddress(item.address) === currentPeerWindow()
    })
    var baseline = WindowOutcomes.capture(client, peer)
    var beforeState = Object.assign({}, currentStep.completion.windowState)
    // The split command focuses its owned target; focus is a postcondition.
    if (beforeState.splitChanged) delete beforeState.focused
    if (!baseline.first || !matchesWindowState(client, beforeState)) {
      failWindowPreflight("The practice window isn't in the expected state. Return to its launch activity or skip.")
      return
    }
    windowChangeBaseline = baseline
    if (currentStep.completion.windowState.splitChanged) {
      if (!WindowOutcomes.orientation(baseline.first, baseline.peer)) {
        failWindowPreflight("Both owned practice windows must be tiled on the same workspace before changing the split.")
        return
      }
      layoutPreflightProcess.requestGeneration = generation
      layoutPreflightProcess.running = true
    } else if (restoreKeyboardAfterAction) focusActionTimer.restart()
    else helpProcess.running = true
  }

  function parseLayoutPreflight(raw, generation) {
    if (generation !== actionGeneration || !actionRunning || !windowChangeBaseline) return
    var workspaces
    try {
      workspaces = JSON.parse(raw)
      if (!Array.isArray(workspaces)) throw new Error("Expected workspace metadata")
    } catch (error) {
      failWindowPreflight("Couldn't check the practice workspace's layout. Try again or skip this activity.")
      return
    }
    var workspace = workspaces.find(function(item) { return item.id === windowChangeBaseline.first.workspace })
    if (!workspace || workspace.tiledLayout !== "dwindle") {
      failWindowPreflight("This split activity needs the dwindle layout. Your layout is unchanged; skip this activity on a custom layout.")
      return
    }
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
    if (!currentStepIsTour) interactionAudio.notify("step-complete")
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

  function currentAudioPath() {
    return currentStep ? characterStore.audioPath(currentStep.audio, currentStep.instruction, courseDir) : ""
  }

  function completionAudioPath() {
    return currentStep ? characterStore.audioPath(currentStep.completionAudio, currentStep.completionMessage, courseDir) : ""
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
    if ((!narrationEnabled || completionAudioPath() === "") && currentStep)
      minimumDwell = Math.max(minimumDwell, readingDuration(currentStep.completionMessage))
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
    if (!narrationEnabled || introActive || (introDeparting && characterState !== tourRestingState) ||
        path === "" || (phase !== "waiting" && phase !== "highlight")) return
    if (path !== (phase === "highlight" ? completionAudioPath() : currentAudioPath())) return
    if (currentStepIsTour && phase === "waiting") tourAdvanceTimer.stop()
    if (path === completionAudioPath() && path !== currentAudioPath()) {
      if (phase !== "highlight") return
      completionTimer.stop()
    }
    audioStopRequested = false
    pendingAudioPath = ""
    pendingAudioPreserveCharacterState = false
    audioProcessPath = path
    audioProcess.captionGeneration = lessonReveal.beginPlayback()
    audioProcess.stepId = currentStep.id
    audioProcess.captionStage = lessonCaptionStage
    audioProcess.command = timedSpeechCommand(path)
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
    stopLessonWrapup()
    lessonReveal.cancel()
    pendingAudioPath = ""
    pendingAudioPreserveCharacterState = false
    if (audioProcess.running) {
      audioStopRequested = true
      audioProcess.running = false
    }
    audioPaused = false
  }

  function toggleAudio() {
    var visibleWelcomeEnd = welcomeRevealEnd
    audioEnabled = !audioEnabled
    if (!audioEnabled && (welcomeStage === "welcome" || welcomeStage === "controls" || welcomeStage === "recommendation")) {
      welcomeReadingStartOffset = visibleWelcomeEnd < 0 ? captionText(welcomeText).length : visibleWelcomeEnd
      welcomeReadingElapsed = 0
      stopWelcomeSpeech()
      welcomeNarrationFinished = true
      welcomeCaptionShown()
    }
    persistSettings()
    if (audioEnabled) {
      if (!speechEnabled || introActive) return
      if ((phase === "welcome" && (welcomeStage === "welcome" || welcomeStage === "controls")) ||
          (phase === "menu" && welcomeStage === "recommendation")) {
        // Sound toggles don't replay a line already being read or spoken.
        // Stage advancement resets reading mode for the next narration.
        if (welcomeNarrationStarted || welcomeNarrationFinished || welcomeReadingActive) {
          welcomeReadingStartOffset = visibleWelcomeEnd < 0 ? captionText(welcomeText).length : visibleWelcomeEnd
          welcomeReadingElapsed = 0
          welcomeReadingActive = true
        }
        welcomeCaptionShown()
      } else if (phase === "lesson-complete") {
        lessonWrapupPlayed = false
        playLessonWrapup()
      } else if (phase === "highlight") {
        playCompletionNarration()
      } else if (currentStepIsTour) {
        tourAdvanceTimer.stop()
        beginTourNarration()
      } else {
        playCurrentAudio()
      }
      return
    }
    var wasPlayingTour = currentStepIsTour && audioProcess.running
    stopAudio()
    if (sfxProcess.running) sfxProcess.running = false
    if (phase === "highlight") finishCompletionNarration()
    if (!wasPlayingTour && !tourAdvanceTimer.running) scheduleTourAdvance(tourFallbackDuration())
  }

  function replayCurrentAudio() {
    if (phase !== "waiting" || !currentStep || currentAudioPath() === "" || introActive) return
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
    if (usesWindowActivation() && tutorialLaunchProcess.running) {
      showRecovery("The previous launch is still finishing. Try again in a moment.")
      return
    }
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
    if (actionCompletionType === "hyprland-workspace-is" || actionCompletionType === "hyprland-workspace-change")
      workspaceCheckAttempts = 0
    armHelpDetection()
    var tutorialWindow = currentTutorialWindow()
    var command = resolveWindowCommand(currentStep.help.command, tutorialWindow)
    if ((currentStep.help.command.join(" ").indexOf("{tutorialWindow}") !== -1 && tutorialWindow === "") ||
        ((currentStep.swapWithStep || currentStep.pairWithStep) && currentPeerWindow() === "")) {
      var missingStep = tutorialWindow === "" ? currentStep.windowFromStep : currentStep.swapWithStep || currentStep.pairWithStep
      // The required window is missing; never fall back to another window.
      console.warn("learn-omarchy: Help skipped because the window from", currentStep.windowFromStep, "isn't available; repeat its launch activity or skip this activity")
      actionRunning = false
      actionStepId = ""
      shortcutArmedUntil = 0
      clearActiveKeys()
      setCharacterState("coach", "LET'S REOPEN THE PRACTICE WINDOW")
      showRecovery("The required tutorial window isn't available. Return to its launch activity to create a safe target, or skip this activity.", missingStep)
      return
    }
    if (usesWindowActivation()) {
      // A launcher may remain attached to its application (notably Files).
      // Advancing must cancel detection, not terminate the learner's window.
      windowLaunchToken = Date.now().toString(36) + "-" + Math.random().toString(36).slice(2) + "-" + Math.random().toString(36).slice(2)
      var directLaunch = (command.length === 1 && command[0] === "omacalc") ||
        (command.length === 3 && command[0] === "omarchy" && command[1] === "launch" && command[2] === "nautilus")
      windowLaunchAcknowledged = directLaunch
      windowOwnershipVerified = false
      if (directLaunch) {
        Quickshell.execDetached(["env", "LEARN_OMARCHY_WINDOW_TOKEN=" + windowLaunchToken].concat(command))
        windowActivationHintTimer.restart()
      } else {
        windowActivationHintTimer.stop()
        tutorialLaunchProcess.requestGeneration = actionGeneration
        tutorialLaunchProcess.requestToken = windowLaunchToken
        tutorialLaunchProcess.command = ["node", appRoot + "/tools/tutorial-launch.mjs",
          "--token", windowLaunchToken, "--detach",
          "--profile-root", Quickshell.env("XDG_RUNTIME_DIR") || stateHome, "--"].concat(command)
        tutorialLaunchProcess.running = true
      }
      return
    }
    var changesWorkspace = actionCompletionType === "hyprland-workspace-is" ||
      actionCompletionType === "hyprland-workspace-change"
    if (keyboardExclusive && (changesWorkspace ||
        (currentStep.completion.windowState && currentStep.completion.windowState.focused === true))) {
      restoreKeyboardAfterAction = true
      setKeyboardExclusive(false)
    }
    helpProcess.command = command
    if (currentStep.completion.windowState &&
        (currentStep.completion.windowState.resized || currentStep.completion.windowState.splitChanged)) {
      windowChangeBaseline = null
      windowBaselineProcess.requestGeneration = actionGeneration
      windowBaselineProcess.running = true
    } else if (currentStep.swapWithStep) {
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

  function finishTutorialLaunch(exitCode, generation, token, output, errors) {
    if (generation !== actionGeneration || token !== windowLaunchToken || phase !== "waiting") return
    var packet
    var message = "The tutorial application couldn't be launched."
    try {
      packet = JSON.parse(String(exitCode === 0 ? output : errors))
      if (packet && typeof packet.error === "string") message = packet.error
    } catch (error) {
      message = "The tutorial launcher returned an invalid response (exit " + exitCode + ")."
      console.warn("learn-omarchy: invalid launch response:", error)
    }
    if (exitCode !== 0 || !packet || packet.ok !== true || packet.state !== "spawned" ||
        !Number.isSafeInteger(packet.pid) || packet.pid <= 0) {
      resetWindowTarget()
      clearActiveKeys()
      showRecovery(message)
      return
    }
    windowLaunchAcknowledged = true
    windowActivationHintTimer.restart()
    if (windowOwnershipVerified)
      finishWindowOwnership(0, windowGeometryGeneration, token)
  }

  function startPracticeExercise() {
    if (phase !== "waiting" || lessonTransitionRunning || actionRunning || !currentStepIsPractice) return
    if (practiceProcess.running || practiceSessionActive) {
      showRecovery("The previous exercise is still closing. Try again in a moment.")
      return
    }
    if (!inlineAppSearch && !practiceHost) {
      showRecovery("The exercise area isn't available on this display. Try again in a moment.")
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
    if (inlineAppSearch) {
      practiceProcess.requestGeneration = actionGeneration
      practiceProcess.command = [appRoot + "/bin/learn-omarchy-practice", currentStep.practice]
      practiceProcess.running = true
    } else {
      practiceSessionGeneration = actionGeneration
      practiceSessionMode = currentStep.practice
      practiceSessionActive = true
    }
  }

  function finishEmbeddedPractice(generation, mode, completed, message) {
    if (generation !== practiceSessionGeneration || !practiceSessionActive) return
    Qt.callLater(function() {
      if (generation !== root.practiceSessionGeneration || !root.practiceSessionActive) return
      root.practiceSessionActive = false
      if (root.exitAfterPractice) {
        Qt.quit()
        return
      }
      if (generation !== root.actionGeneration || !root.exerciseRunning) return
      root.finishPracticeExercise(message ? 1 : 0, generation,
        completed ? "LEARN_PRACTICE_RESULT:" + JSON.stringify({ mode: mode, completed: true }) : "")
      if (message) {
        console.warn("learn-omarchy exercise:", message)
        root.showRecovery(message)
      }
    })
  }

  function requestExit() {
    runCleanup()
    stopAudio()
    exitAfterPractice = practiceSessionActive
    cancelAction()
    if (!exitAfterPractice) Qt.quit()
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
        // Special-workspace events name the workspace, not its window. Verify
        // the owned client snapshot instead; address-bearing events still match exactly.
        var specialWorkspaceEvent = (event.name === "activespecial" || event.name === "activespecialv2") &&
          completion.windowState && completion.windowState.specialWorkspace !== undefined
        var subject = normalizedWindowAddress(payload.split(",")[0])
        if (expectedTutorialWindow === "" || (!specialWorkspaceEvent && subject !== expectedTutorialWindow)) {
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

  property var pendingSystemVolumeActions: []

  function queueSystemVolume(action) {
    if ([5, -5, 1, -1, "mute-toggle"].indexOf(action) === -1) {
      console.warn("learn-omarchy: unsupported system volume action")
      return
    }
    var queue = pendingSystemVolumeActions.slice()
    var last = queue.length - 1
    // Coalesce key-repeat adjustments while the previous command is running.
    if (typeof action === "number" && last >= 0 && typeof queue[last] === "number") {
      queue[last] = Math.max(-100, Math.min(100, queue[last] + action))
      if (queue[last] === 0) queue.pop()
    } else queue.push(action)
    pendingSystemVolumeActions = queue
    runSystemVolumeAction()
  }

  function runSystemVolumeAction() {
    if (systemVolumeProcess.running || pendingSystemVolumeActions.length === 0) return
    var queue = pendingSystemVolumeActions.slice()
    var action = queue.shift()
    pendingSystemVolumeActions = queue
    systemVolumeProcess.command = ["omarchy", "audio", "output", "volume",
      typeof action === "number" && action > 0 ? "+" + action : String(action)]
    systemVolumeProcess.running = true
  }

  function finishSystemVolumeAction(exitCode) {
    if (exitCode !== 0) {
      pendingSystemVolumeActions = []
      console.warn("learn-omarchy: system volume adjustment failed with exit code", exitCode)
      Quickshell.execDetached(["notify-send", "Volume adjustment failed",
        "Learn Omarchy couldn't change the system volume. Check your audio output in the desktop bar."])
      return
    }
    Qt.callLater(runSystemVolumeAction)
  }

  component SystemVolumeShortcut: Shortcut {
    property var action
    context: Qt.ApplicationShortcut
    enabled: root.keyboardExclusive && root.shortcutInhibitionActive
    onActivated: root.queueSystemVolume(action)
  }
  SystemVolumeShortcut { sequence: "Volume Up"; action: 5 }
  SystemVolumeShortcut { sequence: "Volume Down"; action: -5 }
  SystemVolumeShortcut { sequence: "Volume Mute"; action: "mute-toggle"; autoRepeat: false }
  SystemVolumeShortcut { sequence: "Alt+Volume Up"; action: 1 }
  SystemVolumeShortcut { sequence: "Alt+Volume Down"; action: -1 }

  Process {
    id: systemVolumeProcess
    onExited: function(exitCode) { root.finishSystemVolumeAction(exitCode) }
  }

  function handleSystemVolumeKey(event) {
    if (!keyboardExclusive || !shortcutInhibitionActive) return false
    var modifiers = event.modifiers & (Qt.ShiftModifier | Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)
    if (modifiers !== Qt.NoModifier && modifiers !== Qt.AltModifier) return false
    var key = event.key
    // Layer surfaces can receive key events without Qt activating application shortcuts.
    var up = key === Qt.Key_VolumeUp
    var down = key === Qt.Key_VolumeDown
    var mute = key === Qt.Key_VolumeMute
    if (!up && !down && !mute) return false
    if (mute && modifiers !== Qt.NoModifier) return false
    event.accepted = true
    if (mute && event.isAutoRepeat) return true
    queueSystemVolume(mute ? "mute-toggle" : (up ? 1 : -1) * (modifiers === Qt.AltModifier ? 1 : 5))
    return true
  }

  function handleKeyPressed(event) {
    var plain = event.modifiers === Qt.NoModifier
    if (referenceBrowsing) {
      if (isPlainEscape(event) || (plain && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)))
        returnFromReference()
      event.accepted = true
      return
    }
    if (phase === "arcade") {
      if (isPlainEscape(event)) {
        returnToMenu()
      } else if (plain && event.key === Qt.Key_H) {
        if (arcadeHost) arcadeHost.showHint()
      } else if (plain && arcadeHost &&
          (event.key === Qt.Key_1 || event.key === Qt.Key_2 || event.key === Qt.Key_3 ||
           event.key === Qt.Key_R || event.key === Qt.Key_Return ||
           event.key === Qt.Key_Enter || event.key === Qt.Key_Space)) {
        arcadeHost.handleControlKey(keyName(event.key))
      } else {
        updateActiveKeys(event, true)
      }
      event.accepted = true
      return
    }
    if (handleSystemVolumeKey(event)) return
    if (phase === "welcome" && plain) {
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
        advanceWelcome(introGeneration, welcomeStage)
      else if (isPlainEscape(event)) finishWelcome()
      else return
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
      else if (event.key === Qt.Key_A) openArcade()
      else if (isPlainEscape(event)) Qt.quit()
      else return
      event.accepted = true
      return
    }
    if (phase === "lesson-complete") {
      if (event.key === Qt.Key_R) startLesson(lessonIndex, false, false)
      else if (event.key === Qt.Key_P) startLesson(lessonIndex, true, false)
      else if (isPlainEscape(event)) returnToMenu()
      else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        if (mixedPracticeActive) nextMixedLesson()
        else returnToMenu()
      }
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
      event.accepted = !!(event.modifiers & (Qt.MetaModifier | Qt.ControlModifier | Qt.AltModifier)) &&
        expectedKeyMap()[keyName(event.key)] === true
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
    id: settingsFile
    path: root.settingsPath
    atomicWrites: true
    // These small state files must finish saving before reset or exit can succeed.
    blockWrites: true
    printErrors: false
    onLoaded: if (root.stateSaveRetry !== "settings") root.loadSettings(text())
    onLoadFailed: if (root.stateSaveRetry !== "settings") root.loadSettings("{}")
    onSaved: root.settingsSaveError = ""
    onSaveFailed: function(error) { root.reportStateSaveFailure("settings", error) }
  }

  FileView {
    id: progressFile
    path: root.progressPath
    watchChanges: true
    atomicWrites: true
    blockWrites: true
    printErrors: false
    onLoaded: if (root.stateSaveRetry !== "progress") root.loadProgress(text())
    onFileChanged: reload()
    onLoadFailed: if (root.stateSaveRetry !== "progress") root.loadProgress("{}")
    onSaved: root.progressSaveError = ""
    onSaveFailed: function(error) { root.reportStateSaveFailure("progress", error) }
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
        splashActive: root.splashActive,
        startupOpacity: root.startupOpacity,
        startupRevealPending: root.startupRevealPending,
        character: root.characterName,
        requestedCharacter: root.requestedCharacter,
        characterPacksReady: characterStore.ready,
        characterNotice: root.characterNotice,
        integrationNotice: root.integrationNotice,
        retentionNotice: root.retentionNotice,
        referenceBrowsing: root.referenceBrowsing,
        geometryProviderAvailable: root.geometryProviderAvailable,
        barGeometry: root.barGeometry,
        introActive: root.introActive,
        introGeneration: root.introGeneration,
        introNotice: root.introNotice,
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
        welcomeSeen: root.welcomeSeen,
        welcomeStage: root.welcomeStage,
        welcomeTimingWords: root.welcomeWordTimings.length,
        welcomePlaybackMs: root.welcomePlaybackMs,
        welcomeRevealEnd: root.welcomeRevealEnd,
        lessonCaptionStage: root.lessonCaptionStage,
        lessonTimingWords: lessonReveal.words.length,
        lessonPlaybackMs: lessonReveal.positionMs,
        lessonRevealEnd: lessonReveal.revealEnd,
        lessonReadingElapsed: lessonReveal.readingElapsed,
        lessonCaptionVisible: root.lessonCaptionVisible,
        wrapupTimingWords: wrapupReveal.words.length,
        wrapupPlaybackMs: wrapupReveal.positionMs,
        wrapupRevealEnd: wrapupReveal.revealEnd,
        welcomeReadingElapsed: root.welcomeReadingElapsed,
        completedLessons: root.completedLessons,
        stepResults: root.stepResults,
        practiceMode: root.practiceMode,
        mixedLessonIds: root.mixedLessonIds,
        mixedLessonPosition: root.mixedLessonPosition,
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
        practiceSessionActive: root.practiceSessionActive,
        embeddedExercise: practiceLoader.item ? JSON.parse(practiceLoader.item.status()) : null,
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

    function mixedPractice(): string {
      if (root.phase !== "menu" && root.phase !== "lesson-complete") return "busy"
      return root.startMixedPractice() ? "started" : "needs-completed-modules"
    }

    function nextMixed(): string {
      if (!root.mixedPracticeActive || root.phase !== "lesson-complete") return "not-ready"
      root.nextMixedLesson()
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

    function refreshCoaches(): string {
      return root.refreshCharacters() ? "refreshing" : "busy"
    }

    function target(): string {
      if (root.phase !== "waiting" || !root.currentStep) return "not-waiting"
      root.completeCurrentStep()
      return "ok"
    }

    function skip(): string {
      if (root.welcomeStage !== "") { root.finishWelcome(); return "ok" }
      if (root.phase !== "waiting" || !root.currentStep) return "not-waiting"
      root.skipCurrentStep()
      return "ok"
    }
  }

  // Application sound effects are independent of
  // narration so the two never interrupt each other; muted with the speaker.
  InteractionAudio {
    id: interactionAudio
    appRoot: root.appRoot
    enabled: root.audioEnabled && root.effectsEnabled
    volume: root.effectsVolume
    paused: root.phase === "paused"
    suspended: root.phase === "settings" || root.introActive || root.welcomeStage !== ""
  }

  Process {
    id: cheatSheetProcess
    stdout: StdioCollector { }
    stderr: StdioCollector { id: cheatSheetErrors }
    onExited: function(code) { root.finishCheatSheetGeneration(code, cheatSheetErrors.text) }
  }

  Process {
    id: sfxProcess
  }

  Process {
    id: introAmbienceProcess
  }

  function canPlayEffects() {
    return audioEnabled && effectsEnabled && effectsVolume > 0 && !reducedMotion &&
      phase !== "paused" && phase !== "settings"
  }

  function playSound(name) {
    if (!canPlayEffects()) return
    if (sfxProcess.running) sfxProcess.running = false
    sfxProcess.command = ["mpv", "--no-video", "--really-quiet", "--volume=" + effectsVolume, "--", appRoot + "/assets/sounds/" + name]
    sfxProcess.running = true
  }

  function playIntroSound(id, generation) {
    if (!introActive || generation !== introGeneration || phase !== "welcome") return
    if (id === "birds-welcome.opus") {
      if (!canPlayEffects()) return
      introAmbienceProcess.running = false
      introAmbienceProcess.command = ["mpv", "--no-video", "--really-quiet",
        "--volume=" + (effectsVolume * 0.60).toFixed(2), "--", appRoot + "/assets/sounds/" + id]
      introAmbienceProcess.running = true
      return
    }
    if (["rocket-land.opus", "rocket-liftoff.opus"].indexOf(id) < 0) return
    playSound(id)
  }

  FileView {
    path: root.appRoot + "/courses/welcome.json"
    onLoaded: {
      try {
        var data = JSON.parse(text())
        if (typeof data.instruction !== "string" || !data.instruction.trim() ||
            data.audio !== "audio/host-welcome.mp3") throw new Error("Invalid welcome narration metadata")
        if (data.recommendationAudio !== undefined && (data.recommendationAudio !== "audio/host-lessons.mp3" ||
            typeof data.recommendation !== "string" || !data.recommendation.trim()))
          throw new Error("Invalid welcome lesson-menu narration")
        if (data.controls !== undefined && (!data.controls || typeof data.controls.instruction !== "string" ||
            !data.controls.instruction.trim() || data.controls.audio !== "audio/host-controls.mp3"))
          throw new Error("Invalid welcome controls narration metadata")
        if (data.instructions !== undefined && (!data.instructions || typeof data.instructions !== "object" ||
            Array.isArray(data.instructions) || Object.keys(data.instructions).some(function(id) {
              return typeof data.instructions[id] !== "string" || !data.instructions[id].trim()
            }))) throw new Error("Invalid character welcome instructions")
        root.welcomeNarration = data
      } catch (error) {
        console.warn("learn-omarchy: welcome narration unavailable:", error)
      }
    }
    onLoadFailed: console.warn("learn-omarchy: welcome narration metadata couldn't be loaded")
  }

  Process {
    id: welcomeSpeech
    property int generation: -1
    property int captionGeneration: -1
    property string stage: ""
    stdout: SplitParser {
      onRead: function(data) { root.receiveWelcomePlayback(data, welcomeSpeech.generation, welcomeSpeech.stage) }
    }
    onExited: function(exitCode) {
      root.welcomeSpeechExited(exitCode, generation, stage)
    }
  }

  Process {
    id: lessonWrapupSpeech
    property int generation: -1
    property int captionGeneration: -1
    stdout: SplitParser {
      onRead: function(data) {
        if (!root.lessonWrapupStopping && lessonWrapupSpeech.running &&
            lessonWrapupSpeech.generation === root.lessonWrapupGeneration && root.phase === "lesson-complete")
          wrapupReveal.receive(data, lessonWrapupSpeech.captionGeneration)
      }
    }
    onExited: function(exitCode) { root.lessonWrapupExited(exitCode, generation) }
  }

  Process {
    id: audioProcess
    property int captionGeneration: -1
    property string stepId: ""
    property string captionStage: ""
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(data) { root.receiveLessonPlayback(data, audioProcess.captionGeneration, audioProcess.stepId, audioProcess.captionStage) }
    }
    onStarted: {
      root.recordAudioPlayback("started", root.audioProcessPath, null)
      if (root.audioPaused) audioProcess.write(JSON.stringify({ command: "pause" }) + "\n")
    }
    onExited: function(exitCode) {
      var stopped = root.audioStopRequested
      var finishedPath = root.audioProcessPath
      if (!stopped) lessonReveal.finish(audioProcess.captionGeneration, exitCode)
      root.recordAudioPlayback(stopped ? "interrupted" : "finished", finishedPath, exitCode)
      var queuedPath = root.pendingAudioPath
      var preserveQueuedCharacterState = root.pendingAudioPreserveCharacterState
      var queuedGeneration = root.actionGeneration
      root.audioStopRequested = false
      root.audioPaused = false
      root.audioProcessPath = ""
      root.pendingAudioPath = ""
      root.pendingAudioPreserveCharacterState = false
      if (stopped) {
        if (queuedPath !== "" && root.narrationEnabled &&
            (queuedPath === root.currentAudioPath() || queuedPath === root.completionAudioPath())) {
          Qt.callLater(function() {
            if (root.actionGeneration === queuedGeneration && !audioProcess.running && !root.audioStopRequested)
              root.startAudioPath(queuedPath, preserveQueuedCharacterState)
          })
        } else if (
          root.phase === "waiting" &&
          root.currentStepIsTour &&
          !root.narrationEnabled
        ) {
          root.scheduleTourAdvance(root.tourFallbackDuration())
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
        root.scheduleTourAdvance(root.tourFallbackDuration())
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
    id: windowBaselineProcess
    property int requestGeneration: -1
    command: ["hyprctl", "clients", "-j"]
    stdout: StdioCollector { id: windowBaselineOutput }
    onExited: function(code) {
      if (requestGeneration !== root.actionGeneration || !root.actionRunning) return
      if (code !== 0) root.failWindowPreflight("Couldn't inspect the practice windows. Try again.")
      else root.parseWindowBaseline(windowBaselineOutput.text, requestGeneration)
    }
  }

  Process {
    id: layoutPreflightProcess
    property int requestGeneration: -1
    command: ["hyprctl", "workspaces", "-j"]
    stdout: StdioCollector { id: layoutPreflightOutput }
    onExited: function(code) {
      if (requestGeneration !== root.actionGeneration || !root.actionRunning) return
      if (code !== 0) root.failWindowPreflight("Couldn't inspect the workspace layout. Try again.")
      else root.parseLayoutPreflight(layoutPreflightOutput.text, requestGeneration)
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
    id: welcomeReadTimer
    property int generation: -1
    property string stage: ""
    repeat: false
    onTriggered: root.advanceWelcome(generation, stage)
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

  Loader {
    id: practiceLoader
    parent: root.practiceHost
    width: parent ? parent.width : 0
    height: parent ? parent.height : 0
    visible: root.embeddedPracticeRunning && root.phase === "waiting"
    active: root.practiceSessionActive
    sourceComponent: Component {
      PracticeSession {
        readonly property int requestGeneration: root.practiceSessionGeneration
        mode: root.practiceSessionMode
        autoStart: false
        textScale: root.textScale
        backgroundColor: root.background
        foreground: root.foreground
        accent: root.accent
        muted: root.muted
        errorColor: root.urgent
        onCompleted: root.finishEmbeddedPractice(requestGeneration, mode, true, "")
        onCancelled: root.finishEmbeddedPractice(requestGeneration, mode, false, "")
        onFailed: function(message) { root.finishEmbeddedPractice(requestGeneration, mode, false, message) }
      }
    }
    onLoaded: {
      if (!root.exerciseRunning || root.practiceSessionGeneration !== root.actionGeneration) {
        item.cancel()
        return
      }
      item.start()
      Qt.callLater(function() {
        if (practiceLoader.item && root.embeddedPracticeRunning) practiceLoader.item.focusPractice()
      })
    }
    onStatusChanged: {
      if (status === Loader.Error && root.practiceSessionActive)
        root.finishEmbeddedPractice(root.practiceSessionGeneration, root.practiceSessionMode, false,
          "Couldn't load the exercise area. Try again, or Skip.")
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
        (root.actionCompletionType === "hyprland-workspace-change" ||
          root.actionCompletionType === "hyprland-workspace-is")
      ) {
        root.workspaceCheckAttempts = 0
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

  Process {
    id: scratchpadVisibilityProcess
    property int requestGeneration: -1
    property int monitorId: -1
    property var verifiedWindow: null
    command: ["hyprctl", "monitors", "-j"]
    stdout: StdioCollector { id: scratchpadVisibilityOutput }
    onExited: function(code) {
      root.parseScratchpadVisibility(scratchpadVisibilityOutput.text, requestGeneration, monitorId, code, verifiedWindow)
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
    id: tutorialLaunchProcess
    property int requestGeneration: -1
    property string requestToken: ""
    stdout: StdioCollector { id: tutorialLaunchOutput }
    stderr: StdioCollector { id: tutorialLaunchErrors }
    onExited: function(exitCode) {
      root.finishTutorialLaunch(exitCode, requestGeneration, requestToken,
        tutorialLaunchOutput.text, tutorialLaunchErrors.text)
    }
  }

  Process {
    id: windowPresentationProcess
    property int requestGeneration: -1
    onExited: function(exitCode) {
      root.finishWindowPresentation(exitCode, requestGeneration)
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
    id: tourAdvanceTimer
    repeat: false
    onTriggered: root.advanceTour()
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
      if (root.phase === "menu" && root.welcomeStage === "" && root.characterState === "menu-fly") {
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
          root.setCharacterState("target-point", "HERE IT IS")
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
        root.introDeparting = false
        if (!root.introActive) root.beginTourNarration()
      } else if (root.phase === "waiting" && root.characterState === "help-settle") {
        root.setCharacterState("help", "RIGHT HERE")
      } else if (root.phase === "menu" && root.welcomeStage === "" && root.characterState === "menu-settle") {
        root.setCharacterState("menu-point", "CHOOSE A LESSON")
      } else if (root.phase === "highlight" && root.characterState === "target-settle") {
        root.setCharacterState("target-point", "HERE IT IS")
      } else if (root.phase === "lesson-complete" && root.characterState === "module-settle") {
        root.setCharacterState("celebrate", root.lessonFullyExplored(root.currentLesson) ? "MODULE COMPLETE!" : "MODULE EXPLORED")
      }
    }
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
        screen: screenScope.modelData
        visible: root.splashActive && overlay.isFocusedScreen
        anchors { top: true; bottom: true; left: true; right: true }
        color: root.startupBackground
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "learn-omarchy-splash"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        SplashScreen {
          anchors.fill: parent
          backgroundColor: root.startupBackground
          source: "file://" + root.appRoot.split("/").map(encodeURIComponent).join("/") + "/assets/splash/learn-omarchy-poster.png"
          active: root.splashActive && overlay.isFocusedScreen
          ready: root.phase === "error" || (root.course !== null && root.settingsResolved &&
            root.progressResolved && characterStore.ready)
          reducedMotion: root.reducedMotion
          onFinished: root.finishSplash()
          onImageFailed: console.warn("learn-omarchy: splash artwork unavailable; using the title fallback")
        }
      }

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
        readonly property bool shouldShow: !root.splashActive && root.phase !== "loading" && isFocusedScreen
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
          Boolean(highlight) && !targetIsEstimated &&
          (highlight.target !== "panel" || usesWindowTarget || Boolean(measuredBarTarget && measuredBarTarget.panel))
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
        contentItem.opacity: root.startupOpacity
        anchors {
          top: true
          bottom: true
          left: true
          right: true
        }
        color: root.colorWithAlpha(root.startupBackground, 1 - root.startupOpacity)
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "learn-omarchy"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.keyboardExclusive && !root.keyboardCaptureResetting
          ? WlrKeyboardFocus.Exclusive : root.embeddedPracticeRunning ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
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
          enabled: overlay.shouldShow && (root.phase === "waiting" || root.phase === "highlight" ||
            root.phase === "arcade") &&
            !(root.embeddedPracticeRunning && root.practiceSessionMode === "screen-lock")
        }
        mask: Region {
          Region { item: topicPanel }
          Region { item: keyboardHint }
          Region { item: characterPanel }
          Region { item: packNoticePanel }
          Region { item: teachingContent }
          Region { item: controls }
          Region { item: completionPanel }
          Region { item: errorPanel }
          Region { item: pausePanel }
          Region { item: welcomeControls }
          Region { item: arcadePanel }
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
              if (overlay.shouldShow && !root.embeddedPracticeRunning)
                Qt.callLater(function() { if (!root.embeddedPracticeRunning) keyCatcher.forceActiveFocus() })
            }
          }

          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) { root.handleKeyPressed(event) }
          Keys.onReleased: function(event) {
            if (root.phase === "waiting" || root.phase === "arcade") {
              root.updateActiveKeys(event, false)
              event.accepted = false
            }
          }

          Component.onCompleted: Qt.callLater(function() { if (!root.embeddedPracticeRunning) keyCatcher.forceActiveFocus() })
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
          visible: !root.referenceBrowsing &&
            (root.phase === "menu" || root.phase === "settings" || root.phase === "lesson-complete" || root.phase === "error")
          color: root.colorWithAlpha(root.background, 0.72)
        }

        // Darken the desktop while the opening scene plays so the sprites read clearly.
        Rectangle {
          anchors.fill: parent
          visible: opacity > 0
          color: root.background
          opacity: root.introActive ? 0.6 : 0
          Behavior on opacity {
            NumberAnimation { duration: 600; easing.type: Easing.InOutSine }
          }
        }

        UiPanel {
          id: packNoticePanel
          visible: !root.referenceBrowsing && root.phase !== "settings" && root.phase !== "loading" &&
            (root.characterNotice !== "" || root.introNotice !== "" || root.integrationNotice !== "")
          anchors.horizontalCenter: parent.horizontalCenter
          y: 44
          width: Math.min(680, parent.width - 48)
          height: packNoticeContent.implicitHeight + 24
          z: 30
          stripe: root.instruction
          ColumnLayout {
            id: packNoticeContent
            anchors.fill: parent
            anchors.margins: 12
            Text {
              Layout.fillWidth: true
              text: [root.characterNotice || root.introNotice, root.integrationNotice].filter(function(value) { return value }).join("\n")
              textFormat: Text.PlainText
              color: root.foreground
              wrapMode: Text.WordWrap
              font.pixelSize: 13 * root.textScale
            }
            UiButton {
              compact: true
              label: "COACH SETTINGS"
              visible: root.characterNotice !== "" || root.introNotice !== ""
              onClicked: root.openSettings("settings")
            }
          }
        }

        UiPanel {
          id: characterPanel
          property bool showPackDetails: false
          onVisibleChanged: if (!visible) showPackDetails = false
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
                text: root.settingsMode === "first-run" ? "Pick a guide to welcome you to Omarchy. You can change coaches at any time." : "Choose your coach and make the lessons comfortable for you."
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
                ThemePalette { target: settingsScrollbar; colors: appTheme.colors }
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

                Text {
                  Layout.fillWidth: true
                  visible: text !== ""
                  text: [root.settingsSaveError, root.progressSaveError, root.characterNotice, root.introNotice, characterStore.narrationNotice, root.integrationNotice].filter(function(value) { return value }).join("\n")
                  textFormat: Text.PlainText
                  color: root.instruction
                  wrapMode: Text.WordWrap
                  font.pixelSize: 13 * root.textScale
                }
                UiButton {
                  visible: root.settingsMode !== "first-run" && characterStore.diagnostics.length > 0
                  compact: true
                  kind: "ghost"
                  label: (characterPanel.showPackDetails ? "HIDE" : "SHOW") + " COACH PACK DETAILS (" + characterStore.diagnostics.length + ")"
                  onClicked: characterPanel.showPackDetails = !characterPanel.showPackDetails
                }
                Text {
                  objectName: "packDetails"
                  Layout.fillWidth: true
                  visible: root.settingsMode !== "first-run" && characterPanel.showPackDetails && text !== ""
                  text: characterStore.diagnostics.map(function(item) { return item.message || String(item) }).join("\n")
                  textFormat: Text.PlainText
                  color: root.muted
                  wrapMode: Text.WordWrap
                  font.pixelSize: 12 * root.textScale
                }
                UiButton {
                  label: "REFRESH COACHES"
                  visible: root.settingsMode !== "first-run"
                  compact: true
                  onClicked: root.refreshCharacters()
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
                      readonly property var preview: modelData.manifest.preview
                      readonly property var previewSprite: modelData.manifest.sprites[preview.sprite]

                      Layout.fillWidth: true
                      Layout.minimumWidth: 0
                      implicitWidth: 300
                      implicitHeight: root.settingsMode === "first-run" ? 320 : Math.max(160, coachDetails.implicitHeight + 32)
                      color: characterCardMouse.containsMouse || selected ? Qt.tint(root.panelColor, root.colorWithAlpha(root.accent, 0.14)) : root.subtleFill
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
                            source: characterCard.modelData.assetUrl + "/" + characterCard.previewSprite.path
                            sourceClipRect: Qt.rect(characterCard.preview.frame * characterCard.previewSprite.frameWidth,
                              0, characterCard.previewSprite.frameWidth, characterCard.previewSprite.frameHeight)
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
                            text: characterCard.modelData.manifest.displayName
                            textFormat: Text.PlainText
                            color: characterCard.selected ? root.instruction : root.foreground
                            font.family: "monospace"
                            font.pixelSize: 18 * root.textScale
                            font.weight: Font.Bold
                          }
                          Text {
                            Layout.fillWidth: true
                            horizontalAlignment: root.settingsMode === "first-run" ? Text.AlignHCenter : Text.AlignLeft
                            text: characterCard.modelData.manifest.description || ""
                            textFormat: Text.PlainText
                            color: root.muted
                            wrapMode: Text.WordWrap
                            font.family: "sans-serif"
                            font.pixelSize: 12 * root.textScale
                          }
                          Text {
                            Layout.fillWidth: true
                            horizontalAlignment: root.settingsMode === "first-run" ? Text.AlignHCenter : Text.AlignLeft
                            text: characterCard.active && root.settingsMode !== "first-run" ? "CURRENT COACH" : (characterCard.modelData.id === characterStore.fallbackId ? "DEFAULT" : "")
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
                  text: "AUDIO"
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

                  PreferenceSlider {
                    objectName: "narrationVolumePreference"
                    Layout.fillWidth: true
                    label: "Narration volume"
                    displayValue: root.speechVolume === 0 ? "Off" : root.speechVolume + "%"
                    value: root.speechVolume
                    onAdjusted: function (value) {
                      root.speechVolume = value;
                      root.speechEnabled = value > 0;
                      if (!root.speechEnabled) {
                        root.stopAudio();
                        root.stopWelcomeSpeech();
                      }
                      root.persistSettings();
                    }
                  }
                  PreferenceSlider {
                    objectName: "effectsVolumePreference"
                    Layout.fillWidth: true
                    label: "Effects volume"
                    displayValue: root.effectsVolume === 0 ? "Off" : root.effectsVolume + "%"
                    value: root.effectsVolume
                    onAdjusted: function (value) {
                      root.effectsVolume = value;
                      root.effectsEnabled = value > 0;
                      if (!root.effectsEnabled && sfxProcess.running) sfxProcess.running = false;
                      root.persistSettings();
                    }
                  }
                  PreferenceSlider {
                    Layout.fillWidth: true
                    label: "Narration speed"
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
                }
                RowLayout {
                  objectName: "audioMutedNotice"
                  visible: root.settingsMode !== "first-run" && !root.audioEnabled
                  Layout.fillWidth: true
                  Text {
                    Layout.fillWidth: true
                    text: "Audio is muted."
                    color: root.foreground
                    font.pixelSize: 14 * root.textScale
                  }
                  UiButton {
                    label: "UNMUTE"
                    compact: true
                    onClicked: root.toggleAudio()
                  }
                }
                Text {
                  visible: root.settingsMode !== "first-run"
                  Layout.fillWidth: true
                  text: "Set a volume to zero to turn it off. Volume and speed changes apply to the next clip or Replay."
                  wrapMode: Text.WordWrap
                  color: root.muted
                  font.pixelSize: 13 * root.textScale
                }
                Text {
                  visible: root.settingsMode !== "first-run"
                  Layout.fillWidth: true
                  text: "READING & MOTION"
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
                  rowSpacing: 14
                  columnSpacing: 24
                  PreferenceSwitch {
                    objectName: "typeTextSwitch"
                    Layout.fillWidth: true
                    text: "Reveal captions as spoken"
                    description: "Show words with the coach; off shows complete captions immediately."
                    checked: root.synchronizedWelcomeText
                    onToggled: { root.synchronizedWelcomeText = checked; root.persistSettings() }
                  }
                  PreferenceSwitch {
                    objectName: "reduceMotionSwitch"
                    Layout.fillWidth: true
                    text: "Reduce motion"
                    description: "Reduce animation and show complete captions immediately."
                    checked: root.motionReduced
                    onToggled: { root.motionReduced = checked; root.persistSettings() }
                  }
                  PreferenceSwitch {
                    objectName: "autoAdvanceSwitch"
                    Layout.fillWidth: true
                    text: "Advance automatically"
                    description: "Move on after narration; off lets you choose when to continue."
                    checked: root.autoAdvance
                    onToggled: { root.autoAdvance = checked; root.persistSettings() }
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
                  text: "Captions follow the voice, or reveal at reading speed when muted. Reduced motion always shows full text."
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

                UiButton {
                  visible: root.settingsMode !== "first-run"
                  kind: "ghost"
                  compact: true
                  label: root.resetOptionsExpanded ? "HIDE RESET OPTIONS" : "SHOW RESET OPTIONS"
                  onClicked: {
                    root.resetOptionsExpanded = !root.resetOptionsExpanded
                    if (!root.resetOptionsExpanded) root.resetConfirmPending = false
                  }
                }

                GridLayout {
                  visible: root.settingsMode !== "first-run" && root.resetOptionsExpanded
                  Layout.fillWidth: true
                  columns: characterColumn.width < 640 ? 1 : 2
                  columnSpacing: 14
                  rowSpacing: 10

                  Text {
                    Layout.fillWidth: true
                    text: root.resetConfirmPending
                      ? "Reset all lesson progress, including the tour? Click CONFIRM RESET to clear progress and your saved coach, or CANCEL to keep them."
                      : root.resetJustDone ? "Progress reset, including the tour. Click Done to choose a coach and replay the welcome."
                      : root.completedCount + " of " + (root.course ? root.course.lessons.length : 0) + " modules complete. Reset clears your progress and saved coach."
                    color: root.resetJustDone || root.resetConfirmPending ? root.instruction : root.foreground
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
                  UiButton {
                    visible: root.resetConfirmPending
                    label: "CANCEL"
                    onClicked: root.resetConfirmPending = false
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
                kind: root.settingsMode === "first-run" ? "ghost" : "primary"
                label: root.settingsMode === "first-run" ? "EXIT" : "DONE"
                onClicked: root.closeSettings()
              }
            }
          }
        }

        ArcadePanel {
          id: arcadePanel
          anchors.fill: parent
          z: 30
          visible: !root.referenceBrowsing && root.phase === "arcade" && overlay.shouldShow
          active: visible
          course: root.course
          stats: root.arcadeStats
          backgroundColor: root.background
          foregroundColor: root.foreground
          accentColor: root.accent
          mutedColor: root.muted
          urgentColor: root.urgent
          textScale: root.textScale
          reducedMotion: root.reducedMotion
          onActiveHostChanged: function(isActive) {
            if (isActive) root.arcadeHost = arcadePanel
            else if (root.arcadeHost === arcadePanel) root.arcadeHost = null
          }
          onCloseRequested: root.returnToMenu()
          onStatsCommitted: function(value) { root.saveArcadeStats(value) }
          onEffectRequested: function(name) {
            if (name === "success") root.playSound("interaction-correct.wav")
            else if (name === "finish") root.playSound("interaction-module-complete.wav")
            else root.playSound("interaction-step-complete.wav")
          }
        }

        UiPanel {
          id: topicPanel
          visible: !root.referenceBrowsing && root.phase === "menu" && root.course
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
                    readonly property bool completed: root.lessonCompleted(modelData)

                    Layout.fillWidth: true
                    Layout.preferredHeight: lessonColumn.rowHeight
                    Layout.rightMargin: 6
                    color: cardMouse.containsMouse || selected
                      ? Qt.tint(root.panelColor, root.colorWithAlpha(root.accent, 0.14))
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
                      function onYChanged() { if (lessonCard.selected) Qt.callLater(lessonCard.syncCharacterTarget) }
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
                        color: lessonCard.completed ? root.accent : Qt.tint(root.panelColor, root.colorWithAlpha(root.accent, 0.16))
                        border.color: root.colorWithAlpha(root.accent, lessonCard.completed ? 1 : 0.5)
                        border.width: 1
                        radius: 10

                        Text {
                          anchors.centerIn: parent
                          text: lessonCard.completed ? "✓" : lessonCard.modelData.icon
                          color: lessonCard.completed ? root.controlPalette.highlightedText : root.controlPalette.link
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
                          textFormat: Text.PlainText
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
                        text: lessonCard.modelData.kind === "welcome" ? (root.welcomeSeen ? "REPLAY" : "WELCOME")
                          : root.lessonBookmarks[lessonCard.modelData.id] &&
                          !root.isOpeningTour(lessonCard.index)
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

            Item {
              id: welcomeMenuSlot
              Layout.fillWidth: true
              Layout.preferredHeight: visible ? welcomeCaption.height : 0
              visible: root.welcomeStage === "menu-flight" || root.welcomeStage === "recommendation"
            }

            GridLayout {
              z: 20
              Layout.alignment: Qt.AlignHCenter
              columns: topicPanel.width < 760 ? 1 : 3
              UiButton {
                label: "MIXED PRACTICE"
                enabled: root.mixedEligibleCount >= 2
                onClicked: root.startMixedPractice()
              }
              UiButton {
                label: cheatSheetProcess.running ? "PREPARING REFERENCE..." : "PRINTABLE SHORTCUTS"
                description: "Open the shortcut sheet in your browser, move the course aside, and release keys for printing"
                enabled: !cheatSheetProcess.running
                onClicked: root.openCheatSheet()
              }
              UiButton {
                label: "SHORTCUT ARCADE"
                description: "Play three safe shortcut games and chase your personal bests"
                onClicked: root.openArcade()
              }
            }
            Text {
              Layout.fillWidth: true
              text: root.retentionNotice || (root.mixedEligibleCount < 2
                ? "Complete two practice-ready modules to unlock a mixed review."
                : "Mixed practice reviews up to three completed modules in shuffled order.")
              textFormat: Text.PlainText
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              color: root.muted
              font.pixelSize: 12 * root.textScale
            }

            RowLayout {
              Layout.alignment: Qt.AlignHCenter
              spacing: 18

              Repeater {
                model: root.course && root.course.lessons[root.selectedLessonIndex] &&
                  root.course.lessons[root.selectedLessonIndex].kind === "welcome"
                  ? [["↑ ↓", "CHOOSE"], ["⏎", root.welcomeSeen ? "REPLAY WELCOME" : "START WELCOME"], ["ESC", "CLOSE"]]
                  : [["↑ ↓", "CHOOSE"], ["⏎", "START / RESUME"], ["P", "PRACTICE"], ["A", "ARCADE"], ["ESC", "CLOSE"]]

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
          visible: !root.keyboardExclusive && !root.exerciseRunning && root.phase !== "loading"
          anchors {
            top: parent.top
            horizontalCenter: parent.horizontalCenter
            topMargin: 42
          }
          width: keyboardHintText.implicitWidth + 32
          height: 40
          radius: 10
          color: keyboardHintMouse.containsMouse ? Qt.tint(root.panelColor, root.colorWithAlpha(root.instruction, 0.3)) : root.panelColor
          border.color: root.instruction
          border.width: 1

          Text {
            id: keyboardHintText
            anchors.centerIn: parent
            text: root.referenceBrowsing ? "Print in your browser · click to return to Learn Omarchy" : root.keyboardFocused
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
            onClicked: root.referenceBrowsing ? root.returnFromReference() : root.setKeyboardExclusive(true)
          }
        }

        UiPanel {
          id: teachingContent
          readonly property bool compactTour: root.phase === "waiting" && root.currentStepIsTour
          readonly property bool detailsExpanded: root.tourDetailsExpanded
          readonly property var avoidTarget: root.phase === "highlight" && root.currentStep &&
            root.currentStep.highlight && root.currentStep.highlight.target === "panel"
            ? (overlay.measuredBarTarget && overlay.measuredBarTarget.panel ? overlay.measuredBarTarget : overlay.measuredWindowTarget)
            : null
          readonly property var placement: TeachingLayout.position(overlay.width, overlay.height, width, height, avoidTarget)
          visible: root.phase === "waiting" || root.phase === "highlight"
          opacity: root.lessonContentOpacity
          x: placement.x
          y: placement.y
          width: TeachingLayout.panelWidth(overlay.width, overlay.height, compactTour ? 680 * root.textScale : 900, avoidTarget)
          height: consoleColumn.implicitHeight + (compactTour ? 24 : 38)
          radius: 16
          stripe: compactTour ? "transparent" : root.phase === "waiting" ? root.instruction : root.accent

          ColumnLayout {
            id: consoleColumn
            anchors {
              left: parent.left
              right: parent.right
              top: parent.top
              leftMargin: 20
              rightMargin: 20
              topMargin: teachingContent.compactTour ? 12 : 18
            }
            spacing: 12

            GridLayout {
              id: lessonNavigation
              Layout.fillWidth: true
              readonly property bool stacked: teachingContent.width <
                (teachingContent.compactTour
                  ? topicsButton.implicitWidth + backButton.implicitWidth + 8 + navRightGroup.implicitWidth + stepCounter.implicitWidth
                  : sideWidth * 2 + lessonTitleGroup.implicitWidth) + columnSpacing * 4 + 40
              columns: stacked ? 1 : 5
              columnSpacing: 10
              rowSpacing: 8

              // Full-panel navigation keeps the title centred as actions change.
              readonly property real sideWidth: Math.max(topicsButton.implicitWidth + backButton.implicitWidth + 8, navRightGroup.implicitWidth)

              Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: teachingContent.compactTour
                  ? topicsButton.implicitWidth + backButton.implicitWidth + 8 : lessonNavigation.sideWidth
                Layout.minimumWidth: Layout.preferredWidth
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
                  onClicked: root.previousStep()
                }
                }
              }

              Item { visible: !lessonNavigation.stacked; Layout.fillWidth: true }

              ColumnLayout {
                id: lessonTitleGroup
                Layout.alignment: Qt.AlignHCenter
                spacing: 5

                Text {
                  visible: !teachingContent.compactTour
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
                    model: !teachingContent.compactTour && root.currentLesson ? root.currentLesson.steps.length : 0

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
                    id: stepCounter
                    Layout.leftMargin: teachingContent.compactTour ? 0 : 10
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

              Item { visible: !lessonNavigation.stacked; Layout.fillWidth: true }

              Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: teachingContent.compactTour ? navRightGroup.implicitWidth : lessonNavigation.sideWidth
                Layout.minimumWidth: Layout.preferredWidth
                implicitHeight: navRightGroup.implicitHeight

                RowLayout {
                  id: navRightGroup
                  anchors.right: parent.right
                  spacing: 10

                  UiButton {
                    visible: root.phase === "waiting" && !root.introActive && root.currentAudioPath() !== ""
                      && (!teachingContent.compactTour || teachingContent.detailsExpanded)
                    compact: true
                    label: "▶ REPLAY"
                    onClicked: {
                      if (root.practiceMode) { root.practiceHintVisible = true; root.stepAssisted = true }
                      root.replayCurrentAudio()
                    }
                  }

                  UiButton {
                    visible: root.phase === "waiting" && !teachingContent.compactTour
                    kind: "ghost"
                    compact: true
                    label: "SKIP →"
                    onClicked: root.skipCurrentStep()
                  }

                  UiButton {
                    visible: root.phase === "waiting" &&
                      (teachingContent.compactTour || Boolean(root.currentStep && root.currentStep.detail))
                    compact: true
                    kind: "ghost"
                    label: teachingContent.detailsExpanded ? "LESS" : "DETAILS"
                    description: "Show or hide extra guidance"
                    onClicked: {
                      root.tourDetailsExpanded = !root.tourDetailsExpanded
                      if (root.tourDetailsExpanded && root.practiceMode && !root.currentStepIsTour) {
                        root.practiceHintVisible = true
                        root.stepAssisted = true
                      }
                    }
                  }

                  UiButton {
                    visible: teachingContent.compactTour
                    compact: true
                    kind: "primary"
                    label: "NEXT"
                    onClicked: { root.stopAudio(); root.advance() }
                  }
                }
              }
            }

            Rectangle {
              visible: !teachingContent.compactTour
              Layout.fillWidth: true
              Layout.preferredHeight: 1
              color: root.panelBorder
            }

            Text {
              id: teachingInstruction
              readonly property int revealEnd: root.lessonRevealEnd(message)
              readonly property color inkColor: root.phase === "waiting" ? root.instruction : root.foreground
              visible: !root.embeddedPracticeRunning && (!teachingContent.compactTour || teachingContent.detailsExpanded)
              Layout.fillWidth: true
              Layout.leftMargin: 8
              Layout.rightMargin: 8
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.Wrap
              textFormat: Text.PlainText
              color: revealEnd >= 0 ? "transparent" : inkColor
              font.family: "sans-serif"
              font.pixelSize: 21 * root.textScale
              font.weight: Font.Bold
              lineHeight: 1.15
              text: root.captionText(message)
              readonly property string message: {
                if (root.phase === "highlight" && root.currentStep && root.currentStep.completionMessage)
                  return root.characterText(root.currentStep.completionMessage)
                if (root.practiceMode && !root.practiceHintVisible && root.currentStep && root.currentStep.practicePrompt)
                  return root.characterText(root.currentStep.practicePrompt)
                if (root.currentStepIsTour && root.currentStep && root.currentStep.detail)
                  return root.characterText(root.currentStep.detail)
                return root.currentStep ? root.characterText(root.currentStep.instruction) : ""
              }
              WordRevealText {
                reducedMotion: root.reducedMotion
                anchors.fill: parent
                visible: teachingInstruction.revealEnd >= 0
                fullText: teachingInstruction.text
                revealEnd: teachingInstruction.revealEnd
                font: teachingInstruction.font
                color: teachingInstruction.inkColor
                horizontalAlignment: teachingInstruction.horizontalAlignment
                lineHeight: teachingInstruction.lineHeight
              }
              Binding {
                target: root
                property: "lessonCaptionVisible"
                when: overlay.shouldShow
                value: root.currentStepIsTour && root.phase === "waiting" ? tourCaption.ready :
                  teachingContent.visible && teachingInstruction.visible && teachingContent.opacity > 0 &&
                  root.lessonCaptionMatches(teachingInstruction.message)
              }
            }

            RowLayout {
              id: instructionKeys
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

            UiButton {
              id: stepActionButton
              visible: Boolean(root.phase === "waiting" && root.currentStep && !root.currentStepIsTour &&
                root.currentStep.keys.length === 0 && !root.embeddedPracticeRunning)
              Layout.alignment: Qt.AlignHCenter
              kind: "primary"
              label: root.exerciseRunning && root.inlineAppSearch ? "SEARCH IN PROGRESS" :
                (root.currentStep ? root.currentStep.actionLabel || "Continue" : "").toUpperCase()
              enabled: !root.exerciseRunning && !root.practiceSessionActive
              onClicked: root.runStepAction("action")
            }

            Text {
              id: teachingNote
              visible: Boolean(!root.currentStepIsTour && root.currentStep && root.currentStep.note &&
                (root.phase === "waiting" || (root.phase === "highlight" && root.currentStep.highlight &&
                  root.currentStep.highlight.target === "panel")))
              Layout.fillWidth: true
              Layout.leftMargin: 8
              Layout.rightMargin: 8
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.Wrap
              textFormat: Text.PlainText
              color: root.foreground
              font.family: "sans-serif"
              font.pixelSize: 17 * root.textScale
              lineHeight: 1.2
              text: root.currentStep ? root.captionText(root.characterText(root.currentStep.note || "")) : ""
            }

            Text {
              id: teachingDetails
              visible: Boolean(root.phase === "waiting" && !root.currentStepIsTour &&
                teachingContent.detailsExpanded && root.currentStep && root.currentStep.detail)
              Layout.fillWidth: true
              Layout.leftMargin: 8
              Layout.rightMargin: 8
              horizontalAlignment: Text.AlignLeft
              wrapMode: Text.Wrap
              textFormat: Text.PlainText
              color: root.foreground
              font.family: "sans-serif"
              font.pixelSize: 17 * root.textScale
              lineHeight: 1.2
              text: root.currentStep ? root.captionText(root.characterText(root.currentStep.detail || "")) : ""
            }

            Text {
              visible: root.practiceMode && root.phase === "waiting" && !root.currentStepIsTour && !root.practiceHintVisible
              Layout.fillWidth: true
              text: "Practice mode: press H for a hint."
              color: root.foreground
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              font.pixelSize: 16 * root.textScale
            }

            Text {
              id: openedToolKeyboardHint
              text: root.openedToolKeyboardHint()
              visible: text !== ""
              Layout.fillWidth: true
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              color: root.instruction
              font.pixelSize: 17 * root.textScale
              Accessible.role: Accessible.StaticText
              Accessible.name: text
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
              label: "REOPEN PRACTICE WINDOW"
              onClicked: root.recoverTutorialWindow()
            }
            UiButton {
              visible: root.phase === "highlight"
              Layout.alignment: Qt.AlignHCenter
              kind: "primary"
              label: "CONTINUE"
              onClicked: { root.stopAudio(); root.advance() }
            }

            Item {
              id: embeddedPracticeHost
              visible: root.embeddedPracticeRunning
              Layout.fillWidth: true
              Layout.preferredHeight: Math.min(360 * root.textScale, overlay.height * 0.4)
              Component.onCompleted: if (overlay.isFocusedScreen) root.practiceHost = embeddedPracticeHost
              Component.onDestruction: {
                if (root.practiceHost === embeddedPracticeHost) {
                  root.practiceHost = null
                  if (root.practiceSessionActive) root.cancelAction()
                }
              }
              Connections {
                target: overlay
                function onIsFocusedScreenChanged() {
                  if (overlay.isFocusedScreen) root.practiceHost = embeddedPracticeHost
                }
              }
            }

            Text {
              visible: root.exerciseRunning && root.inlineAppSearch
              Layout.fillWidth: true
              text: "Keys go to your desktop. Close the new terminal to finish, or choose Skip."
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
              color: root.foreground
              font.pixelSize: 14 * root.textScale
            }
          }
        }

        Rectangle {
          id: welcomeToolbarOutline
          visible: root.phase === "welcome" &&
            (root.welcomeStage === "controls-flight" || root.welcomeStage === "controls")
          x: controls.x - 8
          y: controls.y - 8
          width: controls.width + 16
          height: controls.height + 16
          z: 99
          color: "transparent"
          border.color: root.instruction
          border.width: 3
          radius: 12
        }

        GridLayout {
          id: controls
          z: 100
          visible: !root.referenceBrowsing && root.phase !== "loading" && root.phase !== "settings"
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
          columns: overlay.width < 480 * root.textScale ? 3 : 7
          columnSpacing: 8
          rowSpacing: 8

          UiButton {
            visible: root.phase !== "settings"
            compact: true
            icon: "settings"
            label: "SETTINGS"
            onClicked: root.openSettings("settings")
          }

          UiButton {
            compact: true
            icon: root.keyboardExclusive ? "keyboard" : "keyboard-off"
            label: root.keyboardExclusive ? "RELEASE KEYS" : "CAPTURE KEYS"
            enabled: !root.exerciseRunning
            description: "Choose whether shortcuts go to the course or your other windows"
            onClicked: root.setKeyboardExclusive(!root.keyboardExclusive)
          }

          UiButton {
            compact: true
            icon: root.audioEnabled ? "volume" : "muted"
            label: root.audioEnabled ? "MUTE" : "UNMUTE"
            description: "Mute or unmute narration and effects"
            onClicked: root.toggleAudio()
          }

          UiButton {
            visible: root.phase === "waiting" || root.phase === "highlight" || root.phase === "paused"
            compact: true
            icon: root.phase === "paused" ? "play" : "pause"
            label: root.phase === "paused" ? "RESUME" : "PAUSE"
            onClicked: root.phase === "paused" ? root.resumePausedLesson() : root.pauseLesson()
          }

          UiButton {
            visible: Boolean(root.phase === "waiting" && root.currentStep && root.currentStep.help)
            enabled: !root.actionRunning && root.outcomeAddress === ""
            compact: true
            icon: "help"
            label: "HELP"
            onClicked: root.requestHelpAction()
          }

          UiButton {
            visible: root.welcomeStage !== "" && root.phase !== "welcome"
            compact: true
            icon: "skip"
            label: "SKIP WELCOME"
            onClicked: root.finishWelcome()
          }

          UiButton {
            compact: true
            kind: "danger"
            icon: "close"
            label: "EXIT"
            onClicked: root.requestExit()
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
          readonly property bool narrationReady: visible && overlay.shouldShow && root.lessonContentOpacity === 1 &&
            root.characterState === "celebrate" && !coachTravelX.running && !coachTravelY.running &&
            !root.lessonTransitionRunning
          Binding {
            target: root
            property: "lessonWrapupReady"
            when: overlay.shouldShow
            value: completionPanel.narrationReady
          }
          visible: !root.referenceBrowsing && root.phase === "lesson-complete" && root.currentLesson
          onVisibleChanged: if (visible) completionScroll.contentY = 0
          opacity: root.lessonContentOpacity
          anchors.centerIn: parent
          width: Math.min(620, parent.width - 48)
          height: Math.min(parent.height - 72, completionColumn.implicitHeight + 64)
          radius: 18
          stripe: root.accent

          Flickable {
            id: completionScroll
            anchors.fill: parent
            anchors.margins: 32
            contentWidth: width
            contentHeight: completionColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }
            Connections {
              target: completionScroll.Window.window
              function onActiveFocusItemChanged() {
                if (root.phase !== "lesson-complete") return
                var item = completionScroll.Window.window.activeFocusItem
                var ancestor = item
                while (ancestor && ancestor !== completionColumn) ancestor = ancestor.parent
                if (!ancestor) return
                var point = item.mapToItem(completionColumn, 0, 0)
                if (point.y < completionScroll.contentY) completionScroll.contentY = Math.max(0, point.y - 8)
                else if (point.y + item.height > completionScroll.contentY + completionScroll.height)
                  completionScroll.contentY = Math.min(completionScroll.contentHeight - completionScroll.height,
                    point.y + item.height - completionScroll.height + 8)
              }
            }

          ColumnLayout {
            id: completionColumn
            width: completionScroll.width
            spacing: 14

            Rectangle {
              Layout.alignment: Qt.AlignHCenter
              implicitWidth: 72
              implicitHeight: 72
              radius: 36
              color: Qt.tint(root.panelColor, root.colorWithAlpha(root.accent, 0.16))
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
              id: wrapupCaptionText
              Layout.fillWidth: true
              visible: root.currentLessonWrapup() !== null
              text: root.currentLessonWrapup() ? root.captionText(root.characterText(root.currentLessonWrapup().text)) : ""
              textFormat: Text.PlainText
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.Wrap
              color: wrapupReveal.revealEnd >= 0 ? "transparent" : root.foreground
              font.pixelSize: 18 * root.textScale
              lineHeight: 1.2
              WordRevealText {
                reducedMotion: root.reducedMotion
                anchors.fill: parent
                visible: wrapupReveal.revealEnd >= 0
                fullText: wrapupCaptionText.text
                revealEnd: wrapupReveal.revealEnd
                font: wrapupCaptionText.font
                color: root.foreground
                horizontalAlignment: wrapupCaptionText.horizontalAlignment
                lineHeight: wrapupCaptionText.lineHeight
              }
            }
            Text {
              Layout.fillWidth: true
              horizontalAlignment: Text.AlignHCenter
              text: {
                var result = root.lessonResultSummary(root.currentLesson)
                return result.practiced + " practiced, " + result.assisted + " assisted, " +
                  result.introduced + " introduced, " + result.skipped + " skipped."
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
                label: root.mixedPracticeActive
                  ? (root.mixedLessonPosition + 1 < root.mixedLessonIds.length
                    ? "NEXT PRACTICE MODULE" : "FINISH MIXED PRACTICE")
                  : "CHOOSE ANOTHER TOPIC"
                onClicked: root.mixedPracticeActive ? root.nextMixedLesson() : root.returnToMenu()
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
              UiButton {
                label: cheatSheetProcess.running ? "PREPARING REFERENCE..." : "PRINTABLE SHORTCUTS"
                description: "Open the shortcut sheet in your browser, move the course aside, and release keys for printing"
                enabled: !cheatSheetProcess.running
                onClicked: root.openCheatSheet()
              }
              UiButton {
                visible: !root.mixedPracticeActive
                label: "MIXED PRACTICE"
                enabled: root.mixedEligibleCount >= 2
                onClicked: root.startMixedPractice()
              }
            }
            Text {
              Layout.fillWidth: true
              visible: root.retentionNotice !== "" || root.mixedPracticeActive
              text: root.retentionNotice || ("Mixed practice: module " +
                (root.mixedLessonPosition + 1) + " of " + root.mixedLessonIds.length)
              textFormat: Text.PlainText
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              color: root.muted
              font.pixelSize: 12 * root.textScale
            }
          }
          }
        }

        RowLayout {
          id: welcomeControls
          visible: root.phase === "welcome"
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 24
          UiButton {
            visible: root.welcomeStage === "welcome" || root.welcomeStage === "controls"
            kind: "primary"
            label: root.welcomeStage === "welcome" ? "CONTINUE" : "SHOW LESSONS"
            onClicked: root.advanceWelcome(root.introGeneration, root.welcomeStage)
          }
          UiButton {
            kind: "ghost"
            label: "SKIP WELCOME"
            onClicked: root.finishWelcome()
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
        visible: overlay.visible && mapped && !root.referenceBrowsing
        contentItem.opacity: root.startupOpacity
        anchors {
          top: true
          bottom: true
          left: true
          right: true
        }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "learn-omarchy-ohm-1"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {
          Region { item: hexonCoach }
          Region { item: welcomeCaption.visible && !welcomeCaption.recommendation &&
            welcomeCaptionScroll.contentHeight > welcomeCaptionScroll.height ? welcomeCaption : null }
          Region { item: tourCaption.visible &&
            tourCaptionScroll.contentHeight > tourCaptionScroll.height ? tourCaption : null }
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
          id: welcomeCaption
          z: 11
          readonly property bool recommendation: root.phase === "menu"
          readonly property bool ready: overlay.shouldShow && hexonCoach.visible &&
            ((root.phase === "welcome" && root.welcomeStage === "welcome" && root.characterState === "tour-talk") ||
             (root.phase === "welcome" && root.welcomeStage === "controls" && root.characterState === "tour-point") ||
             (recommendation && root.welcomeStage === "recommendation" && root.characterState === "menu-point"))
            && !coachTravelX.running && !coachTravelY.running
            && !characterMouse.pressed && !fallAnimation.running
          parent: recommendation ? welcomeMenuSlot : hexonWindow.contentItem
          visible: opacity > 0
          opacity: ready ? 1 : 0
          onReadyChanged: {
            if (ready && overlay.shouldShow) root.welcomeCaptionShown()
            else if (overlay.shouldShow) {
              welcomeReadTimer.stop()
              root.welcomeReadingActive = false
            }
          }
          Binding {
            target: root
            property: "welcomeCaptionVisible"
            when: overlay.shouldShow
            value: welcomeCaption.ready
          }
          Behavior on opacity {
            onTargetValueChanged: welcomeFade.duration = targetValue > 0 && !root.reducedMotion ? 240 : 0
            NumberAnimation { id: welcomeFade; duration: 0; easing.type: Easing.InOutSine }
          }
          width: recommendation ? welcomeMenuSlot.width : Math.min(920, overlay.width - 48)
          height: Math.min(welcomeCaptionText.implicitHeight + 40, Math.max(100, overlay.height - 120))
          x: recommendation ? 0 : Math.max(12, Math.min(overlay.width - width - 12,
            hexonCoach.x + hexonCoach.width / 2 - width / 2))
          y: recommendation ? 0 : Math.max(12, Math.min(overlay.height - height - 90,
            hexonCoach.y + hexonCoach.height + 16))
          radius: 12
          color: root.panelColor
          border.color: root.colorWithAlpha(root.instruction, 0.8)
          Flickable {
            id: welcomeCaptionScroll
            anchors.fill: parent
            anchors.margins: 20
            contentWidth: width
            contentHeight: welcomeCaptionText.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            Controls.ScrollBar.vertical: Controls.ScrollBar {
              id: welcomeScrollBar
              ThemePalette { target: welcomeScrollBar; colors: appTheme.colors }
            }
            Text {
              id: welcomeCaptionText
              width: welcomeCaptionScroll.width
              text: root.captionText(root.welcomeText)
              onTextChanged: welcomeCaptionScroll.contentY = 0
              textFormat: Text.PlainText
              horizontalAlignment: Text.AlignLeft
              wrapMode: Text.Wrap
              color: root.instruction
              font.pixelSize: (welcomeCaption.recommendation ? 17 : 21) * root.textScale
              lineHeight: 1.2
              opacity: root.welcomeRevealEnd >= 0 ? 0 : 1
            }
            WordRevealText {
              reducedMotion: root.reducedMotion
              width: welcomeCaptionText.width
              visible: root.welcomeRevealEnd >= 0
              fullText: welcomeCaptionText.text
              revealEnd: root.welcomeRevealEnd
              font: welcomeCaptionText.font
              color: welcomeCaptionText.color
            }
          }
        }

        Rectangle {
          id: tourCaption
          z: 11
          readonly property bool ready: hexonCoach.visible && root.phase === "waiting"
            && root.currentStepIsTour && !root.introActive
            && root.characterState === root.tourRestingState
            && !coachTravelX.running && !coachTravelY.running
            && !characterMouse.pressed && !fallAnimation.running
          visible: opacity > 0
          opacity: ready ? root.lessonContentOpacity : 0
          Behavior on opacity {
            onTargetValueChanged: captionFade.duration = targetValue > 0 && !root.reducedMotion ? 240 : 0
            NumberAnimation {
              id: captionFade
              duration: 0
              easing.type: Easing.InOutSine
            }
          }
          width: Math.min(880, overlay.width - 48)
          height: Math.min(tourCaptionText.implicitHeight + 40, Math.max(100, overlay.height - 48))
          // Centre under HEXON, but never leave the screen.
          x: Math.round(Math.max(12, Math.min(overlay.width - width - 12,
            hexonCoach.x + (hexonCoach.width / 2) - (width / 2))))
          y: Math.round(Math.max(12, Math.min(overlay.height - height - 12, hexonCoach.y + hexonCoach.arcOffset + hexonCoach.height + 16)))
          radius: 12
          color: root.panelColor
          border.color: root.colorWithAlpha(root.instruction, 0.8)
          border.width: 1

          Flickable {
            id: tourCaptionScroll
            anchors.fill: parent
            anchors.margins: 20
            contentWidth: width
            contentHeight: tourCaptionText.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            Controls.ScrollBar.vertical: Controls.ScrollBar {
              id: tourScrollBar
              ThemePalette { target: tourScrollBar; colors: appTheme.colors }
            }
            Text {
              id: tourCaptionText
              width: tourCaptionScroll.width
              text: root.currentStep ? root.captionText(root.characterText(root.currentStep.instruction)) : ""
              onTextChanged: tourCaptionScroll.contentY = 0
              textFormat: Text.PlainText
              horizontalAlignment: Text.AlignLeft
              wrapMode: Text.Wrap
              color: root.instruction
              font.family: "sans-serif"
              font.pixelSize: 21 * root.textScale
              lineHeight: 1.2
              opacity: root.lessonRevealEnd(root.currentStep ? root.characterText(root.currentStep.instruction) : "") >= 0 ? 0 : 1
            }
            WordRevealText {
              reducedMotion: root.reducedMotion
              width: tourCaptionText.width
              fullText: tourCaptionText.text
              revealEnd: root.lessonRevealEnd(root.currentStep ? root.characterText(root.currentStep.instruction) : "")
              visible: revealEnd >= 0
              font: tourCaptionText.font
              color: tourCaptionText.color
            }
          }
        }

        IntroPlayer {
          id: introPlayer
          z: 8
          anchors.fill: parent
          sequence: root.resolvedPack ? root.resolvedPack.intro : null
          assetRoot: root.characterAssetRoot
          displayName: root.characterDisplayName
          reducedMotion: root.reducedMotion
          visible: root.introActive && overlay.shouldShow
          onPhaseChanged: {
            if (overlay.shouldShow && (phase === "playing" || phase === "fallback"))
              root.revealStartupScene()
          }
          property int playbackGeneration: -1
          property bool handoffPinned: false
          palette: ({
            accent: root.accent,
            instruction: root.instruction,
            foreground: root.foreground,
            background: root.background,
            muted: root.muted,
            urgent: root.urgent
          })
          Component.onDestruction: {
            if (root.introActive && playbackGeneration === root.introGeneration)
              root.finishIntro(playbackGeneration, "Display removed; continuing the welcome.")
          }

          onFinished: if (overlay.shouldShow) root.finishIntro(playbackGeneration)
          onFailed: function(message) {
            if (overlay.shouldShow) root.finishIntro(playbackGeneration, message)
          }
          onCancelled: {
            if (root.introActive && playbackGeneration === root.introGeneration && overlay.shouldShow)
              root.finishIntro(playbackGeneration, "The introduction was interrupted; continuing the welcome.")
          }
          onDiagnostic: function(message) {
            if (overlay.shouldShow) {
              root.introNotice = message
              console.warn("learn-omarchy: intro:", message)
            }
          }

          onSoundRequested: function(path) {
            if (overlay.shouldShow) root.playIntroSound(path, playbackGeneration)
          }
          Connections {
            target: root
            function onIntroPlaybackRequested(generation) {
              if (!overlay.shouldShow || root.introPlaybackStarted || introPlayer.playbackGeneration === generation) return
              introPlayer.playbackGeneration = generation
              root.introPlaybackStarted = true
              introPlayer.play()
            }
            function onIntroCancellationRequested(keepPosition) {
              if (!keepPosition && introPlayer.handoffPinned) {
                introPlayer.handoffPinned = false
                hexonCoach.userPlaced = false
              }
              introPlayer.cancel()
            }
            function onIntroHandoffRequested(generation) {
              if (!overlay.shouldShow) return
              hexonCoach.userX = hexonCoach.x
              hexonCoach.userY = hexonCoach.y
              hexonCoach.userPlaced = true
              introPlayer.handoffPinned = true
            }
            function onIntroReleaseRequested() {
              if (!introPlayer.handoffPinned) return
              introPlayer.handoffPinned = false
              hexonCoach.userPlaced = false
            }
          }
          Connections {
            target: overlay
            function onShouldShowChanged() {
              if (overlay.shouldShow && root.introActive && !root.introPlaybackStarted && !introStartTimer.running)
                root.beginIntroScene()
              if (!overlay.shouldShow && root.introActive &&
                  introPlayer.playbackGeneration === root.introGeneration)
                root.finishIntro(introPlayer.playbackGeneration, "Display changed; continuing the welcome on the active display.")
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
          readonly property bool uprightFlight: Boolean(root.characterConfig.motion &&
            root.characterConfig.motion.tourFlight === "upright") && targetsTour
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
          readonly property var barPosition: (targetsTour || targetsCompletion) && overlay.highlight &&
            (overlay.highlight.target === "workspace" || overlay.highlight.barWidgets) &&
            overlay.highlight.target !== "panel"
            ? TeachingLayout.besideBar(overlay.width, overlay.height, width, height,
                {x: overlay.targetBoundsX, y: overlay.targetBoundsY,
                  width: overlay.fittedHighlightWidth, height: overlay.fittedHighlightHeight,
                  edge: overlay.measuredBarTarget ? overlay.measuredBarTarget.barEdge : undefined}) : null
          readonly property bool isPointingUp: barPosition ? barPosition.edge === "top" && isPointing :
            root.characterState === "tour-point" || (root.characterState === "target-point" && completionPointsUp)
          readonly property bool targetsIntro: root.characterState === "intro"
          readonly property bool targetsWelcomeControls: root.phase === "welcome" &&
            (root.welcomeStage === "controls-flight" || root.welcomeStage === "controls")
          readonly property bool targetsWelcome: root.phase === "welcome" && !targetsIntro
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
            targetsWelcomeControls ? 1 :
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
            (targetsIntro && introPlayer.characterFlying)
          readonly property bool isSettledHover:
            visible && !isFlying && !targetsIntro && root.characterState !== "hidden"
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
          readonly property real contextX: barPosition ? barPosition.x : targetsIntro
            ? introPlayer.characterX - 8
            : targetsWelcomeControls ? Math.max(18, Math.min(overlay.width - width - 18,
                controls.x + controls.width / 2 - upTipLocalX))
            : targetsWelcome ? (overlay.width - width) / 2
            : targetsMenu
            ? Math.max(18, Math.min(overlay.width - width - 18, menuTargetX - width + 45))
            : targetsTour
              ? tourX
            : targetsCompletion
              ? Math.max(18 - (width * (1 - targetScale) / 2), Math.min(overlay.width - width - 18, targetX))
              : targetsModuleComplete
                ? moduleTargetX
              : waitingX
          readonly property real contextY: barPosition ? barPosition.y : targetsIntro
            ? introPlayer.characterY - (height - 192)
            : targetsWelcomeControls ? Math.max(0, controls.y + controls.height + 16 - upTipLocalY)
            : targetsWelcome ? Math.max(40, (overlay.height - height) / 2 - 40)
            : targetsMenu
            ? Math.max(50, menuTargetY - (height * 0.55))
            : targetsTour
              ? tourY
            : targetsCompletion
              ? Math.max(completionPointsUp ? -(height - 192) : 50, Math.min(bottomY, targetY))
              : targetsModuleComplete
                ? moduleTargetY
              : waitingY

          visible: (root.phase === "menu" || root.phase === "welcome" ||
            root.phase === "waiting" ||
            root.phase === "highlight" ||
            root.phase === "lesson-complete") &&
            root.characterState !== "hidden" && Boolean(root.resolvedPack) &&
            (!targetsIntro || introPlayer.characterVisible)
          width: 240
          height: 260
          x: userPlaced ? userX : contextX
          y: userPlaced ? userY : contextY
          scale: targetsIntro ? introPlayer.characterScale : effectScale * presentationScale
          rotation: targetsIntro ? introPlayer.characterRotation : effectRotation
          opacity: targetsIntro ? introPlayer.characterOpacity : effectOpacity
          transformOrigin: Item.Bottom
          transform: Translate { y: hexonCoach.targetsIntro ? 0 : hexonCoach.arcOffset }

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

          Timer {
            interval: 32
            repeat: true
            running: overlay.shouldShow &&
              (root.welcomeStage === "center-flight" || root.welcomeStage === "controls-flight" || root.welcomeStage === "menu-flight")
            onTriggered: {
              if (!introPlayer.handoffPinned && !coachTravelX.running && !coachTravelY.running &&
                  !characterMouse.pressed && !fallAnimation.running &&
                  Math.abs(hexonCoach.x - hexonCoach.contextX) < 1 &&
                  Math.abs(hexonCoach.y - hexonCoach.contextY) < 1)
                root.welcomeArrived(root.introGeneration)
            }
          }

          Behavior on presentationScale {
            enabled: hexonCoach.visible && !root.reducedMotion && !hexonCoach.targetsIntro
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
            var leavingIntro = root.introDeparting && root.characterState === "tour-fly"
            root.characterTravelDuration = root.travelDurationForDistance(distance, leavingIntro)
            flightBank = !root.reducedMotion && isFlying && uprightFlight ? 8 * (contextX - x) / Math.max(1, distance) : 0
          }

          Behavior on x {
            enabled: hexonCoach.visible && !root.reducedMotion && !hexonCoach.targetsIntro && !characterMouse.pressed
            onTargetValueChanged: hexonCoach.updateTravelDuration()
            NumberAnimation {
              id: coachTravelX
              duration: root.characterTravelDuration
              easing.type: Easing.InOutSine
            }
          }

          Behavior on y {
            enabled: hexonCoach.visible && !root.reducedMotion && !hexonCoach.targetsIntro && !characterMouse.pressed && !fallAnimation.running
            onTargetValueChanged: hexonCoach.updateTravelDuration()
            NumberAnimation {
              id: coachTravelY
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
                root.characterState === "module-fly"
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
                root.characterState === "module-settle"
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
                root.characterState === "intro"
              ) {
                fallAnimation.stop()
                if (!introPlayer.handoffPinned) hexonCoach.userPlaced = false
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
            running: hexonCoach.visible && hexonCoach.isFlying && !hexonCoach.targetsIntro && !root.reducedMotion
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
            rotation: hexonCoach.targetsIntro ? 0 : hexonCoach.flightBank
            Behavior on rotation {
              enabled: !root.reducedMotion && !hexonCoach.targetsIntro
              NumberAnimation { duration: 240; easing.type: Easing.InOutSine }
            }
            transform: Scale {
              origin.x: 112
              origin.y: 192
              xScale: hexonCoach.targetsIntro ? 1 : 2 - hexonCoach.stretch
              yScale: hexonCoach.targetsIntro ? 1 : hexonCoach.stretch
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
              pack: root.resolvedPack
              pose: hexonCoach.targetsIntro ? introPlayer.characterPose :
                hexonCoach.isPointing ? (hexonCoach.isPointingUp ? "point-up" : "point") : "idle"
              talking: welcomeCaption.ready || (audioProcess.running && !root.audioPaused && !root.audioStopRequested) ||
                (lessonWrapupSpeech.running && !root.lessonWrapupStopping)
              flying: hexonCoach.targetsIntro ? introPlayer.characterFlying :
                hexonCoach.isFlying && !hexonCoach.uprightFlight
              // Keep target landmarks stable throughout an approach, rather
              // than letting movement-driven facing change the destination.
              landmarkFacing: hexonCoach.pointDirection
              facing: hexonCoach.targetsIntro ? introPlayer.characterFacing : hexonCoach.isFlying
                ? (hexonCoach.uprightFlight ? 1 : hexonCoach.flightDirection)
                : hexonCoach.isPointing ? hexonCoach.pointDirection : 1
              reducedMotion: root.reducedMotion
              animated: hexonWindow.visible && root.phase !== "paused"
              onErrorMessageChanged: {
                if (errorMessage && root.resolvedPack && overlay.shouldShow)
                  console.warn("learn-omarchy: " + errorMessage)
              }
            }

            Text {
              anchors.centerIn: parent
              width: parent.width
              z: 3
              visible: Boolean(root.resolvedPack) && coachArt.errorMessage !== ""
              text: coachArt.errorMessage + "\nOpen Settings to choose another coach."
              textFormat: Text.PlainText
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
            enabled: root.phase !== "menu" && !hexonCoach.targetsIntro
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
                hexonCoach.interactionMessage = "LET'S LEARN!"
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
