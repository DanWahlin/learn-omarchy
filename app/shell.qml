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
  // Per-character geometry from assets/characters/<name>/character.json.
  // Defaults describe HEXON so an incomplete manifest still works.
  property var characterConfig: ({})
  readonly property string characterPrefix: String(characterConfig.prefix || characterName)
  readonly property string characterDisplayName: String(characterConfig.displayName || characterName.toUpperCase())
  readonly property bool characterFlames: characterConfig.flames !== false
  readonly property real pointPoseScale: Number(characterConfig.pointPoseScale) > 0 ? Number(characterConfig.pointPoseScale) : 1.13
  readonly property real pointUpPoseScale: Number(characterConfig.pointUpPoseScale) > 0 ? Number(characterConfig.pointUpPoseScale) : pointPoseScale
  readonly property var pointTip: characterConfig.pointTip || ({ "x": 165, "y": 75 })
  readonly property var upTip: characterConfig.upTip || ({ "x": 147, "y": 42 })
  readonly property var idleFlames: characterConfig.idleFlames || [[96, 181], [130, 181]]
  readonly property var pointFlames: characterConfig.pointFlames || [[80, 153], [122, 150]]
  // Characters with wings supply a flight strip (256px frames) shown while travelling.
  readonly property int flightFrames: Math.max(0, Math.floor(Number(characterConfig.flightFrames) || 0))
  // Closed-eye variants of the pointing poses (<prefix>-point-blink.png etc.).
  readonly property bool pointBlink: characterConfig.pointBlink === true
  // Halfway pointing frames (<prefix>-point-mid.png etc.) shown while the limb raises or lowers.
  readonly property bool poseMid: characterConfig.poseMid === true
  readonly property real flightFrameRate: Number(characterConfig.flightFrameRate) > 0 ? Number(characterConfig.flightFrameRate) : 5
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
      tourSeen: tourSeen
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
    if (phase !== "menu" && phase !== "settings") return
    settingsMode = mode || "settings"
    resetConfirmPending = false
    syncCharacterPick()
    stopAudio()
    phase = "settings"
    setCharacterState("hidden", "")
  }

  function closeSettings() {
    if (phase !== "settings") return
    resetConfirmPending = false
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
      if (!completedLessons[course.lessons[i].id]) return i
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
  // The overlay holds the keyboard exclusively so shortcuts light up the
  // keycaps. The keyboard button (or IPC "keys") releases it to other
  // windows; the hint pill or the button takes it back.
  property bool keyboardExclusive: true

  function setKeyboardExclusive(exclusive) {
    keyboardExclusive = Boolean(exclusive)
    if (keyboardExclusive) Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
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
  // True while the coach is sitting at his waiting spot beside the panel.
  property bool characterParked: false
  property int externalLayerTick: 0

  readonly property int windowGeometryMaxAttempts: 6
  readonly property int shortcutArmWindowMs: 8000
  readonly property int helpArmWindowMs: 10000

  readonly property int characterTravelDuration: reducedMotion ? 0 : 1050
  // Coaches with halfway frames switch poses with hard cuts, like sprite
  // animation; the landing squash and the halfway frame do the smoothing.
  readonly property int characterPoseFadeDuration: reducedMotion || poseMid ? 0 : 420

  property color accent: "#7aa2f7"
  property color foreground: "#a9b1d6"
  property color background: "#1a1b26"
  property color muted: "#565f89"
  property color urgent: "#f7768e"
  property color instruction: "#e0af68"

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

  function colorWithAlpha(colorValue, alpha) {
    return Qt.rgba(colorValue.r, colorValue.g, colorValue.b, alpha)
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
    signal clicked()
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
    border.width: 1
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
      font.pixelSize: button.compact ? 11 : 12
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
      font.pixelSize: keycap.small ? 11 : 17
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
      Qt.callLater(playCurrentAudio)
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
    var firstStep = course.lessons[index].steps[0]
    introRequested = Boolean(index === 0 && firstStep && firstStep.kind === "tour")
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

  function playCompletionNarration() {
    if (phase !== "highlight") return
    var path = completionAudioPath()
    if (!audioEnabled || path === "") return
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
    if (phase !== "highlight") return
    completionTimer.interval = 900
    completionTimer.restart()
  }

  function startAudioPath(path, preserveCharacterState) {
    if (!audioEnabled || path === "") return
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
    var wasPlayingCompletion = phase === "highlight" && audioProcess.running
    stopAudio()
    if (phase === "highlight" && !wasPlayingCompletion && !completionTimer.running) finishCompletionNarration()
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
    if (event.name === "openlayer" && String(event.data || "").trim().indexOf("learn-omarchy") !== 0) {
      // A newer overlay-level surface stacks above ours; re-map HEXON's window so he stays visible.
      externalLayerTick++
    }
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
      return
    }
    if (completion && completion.type === "hyprland-event" && Array.isArray(completion.events)) {
      if (completion.events.indexOf(String(event.name)) === -1) return
      var payload = String(event.data || "")
      if (completion.dataPattern && !(new RegExp(String(completion.dataPattern))).test(payload)) return
      if (!windowDetectionArmed()) {
        console.info("learn-omarchy: ignoring", event.name, "because no shortcut or Help action is pending")
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

  function handleKeyPressed(event) {
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
    if (phase === "highlight") {
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

    function status(): string {
      return JSON.stringify({
        phase: root.phase,
        character: root.characterName,
        lessonIndex: root.lessonIndex,
        selectedLessonIndex: root.selectedLessonIndex,
        stepIndex: root.stepIndex,
        lessonId: root.currentLesson ? root.currentLesson.id : "",
        stepId: root.currentStep ? root.currentStep.id : "",
        keyboardFocused: root.keyboardFocused,
        keyboardExclusive: root.keyboardExclusive,
        tourSeen: root.tourSeen,
        completedLessons: root.completedLessons,
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
    if (!audioEnabled || reducedMotion) return
    if (sfxProcess.running) sfxProcess.running = false
    sfxProcess.command = ["mpv", "--no-video", "--really-quiet", "--volume=70", "--", appRoot + "/assets/sounds/" + name]
    sfxProcess.running = true
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
        if (queuedPath !== "" && root.audioEnabled &&
            (queuedPath === root.currentAudioPath() || queuedPath === root.completionAudioPath())) {
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
    interval: 420
    repeat: false
    onTriggered: {
      if (root.phase === "highlight" && root.currentStep) {
        if (root.reducedMotion) {
          root.setCharacterState("target-point", "HERE IT IS!")
          root.playCompletionNarration()
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
        root.setCharacterState(root.tourRestingState, root.tourRestingMessage)
        // During the opening scene the narration waits for the ship to leave.
        if (!root.introActive) root.beginTourNarration()
      } else if (root.phase === "waiting" && root.characterState === "help-settle") {
        root.setCharacterState("help", "RIGHT HERE")
      } else if (root.phase === "menu" && root.characterState === "menu-settle") {
        root.setCharacterState("menu-point", "CHOOSE A LESSON")
      } else if (root.phase === "highlight" && root.characterState === "target-settle") {
        root.setCharacterState("target-point", "HERE IT IS!")
        root.playCompletionNarration()
      } else if (root.phase === "lesson-complete" && root.characterState === "module-settle") {
        root.setCharacterState("celebrate", "MODULE COMPLETE!")
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

    delegate: Scope {
      id: screenScope

      required property var modelData

      PanelWindow {
        id: overlay

        property real menuSelectionX: width / 2
        property real menuSelectionY: height / 2
        readonly property bool isFocusedScreen: {
          var monitor = Hyprland.monitorFor(screenScope.modelData)
          return monitor && monitor === Hyprland.focusedMonitor
        }
        readonly property bool shouldShow: root.phase !== "loading" && isFocusedScreen
        readonly property var highlight: root.currentStep ? root.currentStep.highlight : null
        readonly property var hyprlandMonitor: Hyprland.monitorFor(screenScope.modelData)
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

        readonly property real tourCenterX: highlight ? targetBoundsX + (fittedHighlightWidth / 2) : width / 2
        readonly property real tourCenterY: highlight ? targetBoundsY + (fittedHighlightHeight / 2) : height / 2
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
        WlrLayershell.keyboardFocus: root.keyboardExclusive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
        mask: Region {
          Region { item: topicPanel }
          Region { item: keyboardHint }
          Region { item: characterPanel }
          Region { item: teachingContent }
          Region { item: controls }
          Region { item: completionPanel }
          Region { item: errorPanel }
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
          width: Math.min(880, parent.width - 64)
          height: characterColumn.implicitHeight + 64
          radius: 18
          stripe: root.accent

          ColumnLayout {
            id: characterColumn
            anchors.centerIn: parent
            width: parent.width - 64
            spacing: 16

            Text {
              Layout.alignment: Qt.AlignHCenter
              text: root.settingsMode === "first-run" ? "Choose your coach" : "Settings"
              color: root.instruction
              font.family: "sans-serif"
              font.pixelSize: 30
              font.weight: Font.Bold
            }
            Text {
              Layout.fillWidth: true
              horizontalAlignment: Text.AlignHCenter
              text: root.settingsMode === "first-run"
                ? "Your coach flies around the screen, points things out, and talks you through every shortcut. You can change coaches later from the settings button in the top right."
                : "Pick who coaches you and manage your progress."
              color: root.foreground
              opacity: 0.8
              wrapMode: Text.WordWrap
              font.family: "sans-serif"
              font.pixelSize: 14
            }

            Text {
              visible: root.settingsMode !== "first-run"
              text: "COACH"
              color: root.muted
              font.family: "monospace"
              font.pixelSize: 11
              font.weight: Font.Bold
            }

            RowLayout {
              Layout.alignment: Qt.AlignHCenter
              spacing: 22

              Repeater {
                model: root.characterIndex

                Rectangle {
                  id: characterCard
                  required property int index
                  required property var modelData
                  readonly property bool selected: index === root.characterPick
                  readonly property bool active: modelData.id === root.characterName

                  implicitWidth: 300
                  implicitHeight: 340
                  color: characterCardMouse.containsMouse || selected
                    ? root.colorWithAlpha(root.accent, 0.14)
                    : root.subtleFill
                  border.color: selected ? root.colorWithAlpha(root.accent, 0.85) : root.colorWithAlpha(root.foreground, 0.12)
                  border.width: selected ? 2 : 1
                  radius: 14
                  scale: selected ? 1.03 : 1

                  Behavior on scale {
                    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                  }

                  ColumnLayout {
                    anchors {
                      fill: parent
                      margins: 18
                    }
                    spacing: 8

                    Item {
                      Layout.alignment: Qt.AlignHCenter
                      Layout.preferredWidth: 192
                      Layout.preferredHeight: 192

                      Image {
                        anchors.centerIn: parent
                        width: 192
                        height: 192
                        source: root.appRoot + "/assets/characters/" + characterCard.modelData.id +
                          "/sprites/" + characterCard.modelData.id + "-idle.png"
                        sourceClipRect: Qt.rect(0, 0, 192, 192)
                        fillMode: Image.Pad
                        smooth: false
                        mipmap: false
                        scale: characterCard.selected ? 1.12 : 1

                        Behavior on scale {
                          NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                        }
                      }
                    }

                    Text {
                      Layout.alignment: Qt.AlignHCenter
                      text: characterCard.modelData.displayName || characterCard.modelData.id.toUpperCase()
                      color: characterCard.selected ? root.instruction : root.foreground
                      font.family: "monospace"
                      font.pixelSize: 20
                      font.weight: Font.Bold
                    }
                    Text {
                      Layout.fillWidth: true
                      horizontalAlignment: Text.AlignHCenter
                      text: characterCard.modelData.tagline || ""
                      color: root.foreground
                      opacity: 0.75
                      wrapMode: Text.WordWrap
                      font.family: "sans-serif"
                      font.pixelSize: 12
                    }
                    Text {
                      Layout.alignment: Qt.AlignHCenter
                      text: characterCard.active && root.settingsMode !== "first-run"
                        ? "CURRENT COACH"
                        : (characterCard.modelData.id === "hexon" ? "DEFAULT" : "")
                      color: characterCard.active && root.settingsMode !== "first-run" ? root.accent : root.muted
                      font.family: "monospace"
                      font.pixelSize: 10
                      font.weight: Font.Bold
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
              text: "PROGRESS"
              color: root.muted
              font.family: "monospace"
              font.pixelSize: 11
              font.weight: Font.Bold
            }

            RowLayout {
              visible: root.settingsMode !== "first-run"
              Layout.fillWidth: true
              spacing: 14

              Text {
                Layout.fillWidth: true
                text: root.resetJustDone
                  ? "Progress reset. Closing Settings asks for a coach again, then starts the tour."
                  : root.completedCount + " of " + (root.course ? root.course.lessons.length : 0) +
                    " modules complete. Resetting clears every checkmark and the coach choice, like a fresh install."
                color: root.resetJustDone ? root.instruction : root.foreground
                opacity: 0.85
                wrapMode: Text.WordWrap
                font.family: "sans-serif"
                font.pixelSize: 13
              }

              UiButton {
                // Fixed width so the label change never moves the button under the cursor.
                kind: "danger"
                Layout.preferredWidth: Math.max(implicitWidth, resetConfirmMetrics.implicitWidth + 32)
                label: root.resetConfirmPending ? "CLICK AGAIN TO CONFIRM" : "RESET PROGRESS"
                border.width: root.resetConfirmPending ? 2 : 1
                onClicked: root.requestResetProgress()

                Text {
                  id: resetConfirmMetrics
                  visible: false
                  text: "CLICK AGAIN TO CONFIRM"
                  font.family: "monospace"
                  font.pixelSize: 12
                  font.weight: Font.Bold
                  font.letterSpacing: 1.1
                }
              }
            }

            RowLayout {
              Layout.alignment: Qt.AlignHCenter
              spacing: 14

              Text {
                text: root.settingsMode === "first-run"
                  ? "↑ ↓ CHOOSE   ·   ⏎ CONFIRM"
                  : "↑ ↓ CHOOSE A COACH   ·   R RESETS PROGRESS   ·   ESC CLOSES"
                color: root.muted
                font.family: "monospace"
                font.pixelSize: 10
                font.weight: Font.Bold
                font.letterSpacing: 1
              }

              UiButton {
                visible: root.settingsMode !== "first-run"
                kind: "primary"
                label: "DONE"
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
                  text: root.completedCount + " OF " + (root.course ? root.course.lessons.length : 0) + " COMPLETE"
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
                    width: root.course && root.course.lessons.length > 0
                      ? Math.round(parent.width * root.completedCount / root.course.lessons.length)
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
                          text: lessonCard.modelData.title
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
                        text: lessonCard.completed
                          ? "DONE"
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
                      // Select on real mouse movement only. A pointer merely
                      // resting over the panel when it appears must not steal
                      // the selection from the next unfinished module.
                      onPositionChanged: root.selectedLessonIndex = lessonCard.index
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
                model: [["↑ ↓", "CHOOSE"], ["⏎", "START"], ["ESC", "CLOSE"]]

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
              readonly property real sideWidth: Math.max(topicsButton.implicitWidth, navRightGroup.implicitWidth)

              Item {
                Layout.preferredWidth: lessonNavigation.sideWidth
                Layout.minimumWidth: lessonNavigation.sideWidth
                implicitHeight: topicsButton.implicitHeight

                UiButton {
                  id: topicsButton
                  anchors.left: parent.left
                  kind: "ghost"
                  compact: true
                  label: "← TOPICS"
                  onClicked: root.returnToMenu()
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
                      // Layouts size children by implicit size, so animate that.
                      implicitWidth: current ? 20 : 8
                      implicitHeight: 8
                      radius: 4
                      color: done ? root.accent : current ? root.instruction : root.colorWithAlpha(root.foreground, 0.22)
                      Behavior on implicitWidth { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                      Behavior on color { ColorAnimation { duration: 200 } }
                    }
                  }

                  Text {
                    Layout.leftMargin: 10
                    text: root.currentLesson ? "STEP " + (root.stepIndex + 1) + " OF " + root.currentLesson.steps.length : ""
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
                    onClicked: root.replayCurrentAudio()
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
              font.pixelSize: 21
              font.weight: Font.Bold
              lineHeight: 1.15
              text: {
                if (root.phase === "highlight" && root.currentStep && root.currentStep.completionMessage)
                  return root.characterText(root.currentStep.completionMessage)
                if (root.currentStepIsTour && root.currentStep && root.currentStep.detail)
                  return root.characterText(root.currentStep.detail)
                return root.currentStep ? root.characterText(root.currentStep.instruction) : ""
              }
            }

            Text {
              visible: Boolean(root.phase === "waiting" && !root.currentStepIsTour && root.currentStep && root.currentStep.detail)
              Layout.fillWidth: true
              Layout.leftMargin: 8
              Layout.rightMargin: 8
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              color: root.foreground
              opacity: 0.72
              font.family: "sans-serif"
              font.pixelSize: 14
              text: root.currentStep ? root.characterText(root.currentStep.detail || "") : ""
            }

            RowLayout {
              visible: Boolean(root.phase === "waiting" && root.currentStep && root.currentStep.keys.length > 0)
              Layout.alignment: Qt.AlignHCenter
              Layout.topMargin: 4
              Layout.bottomMargin: 2
              spacing: 14

              Repeater {
                model: root.currentStep ? root.currentStep.keys : []

                Keycap {
                  required property string modelData
                  label: modelData.toUpperCase()
                  active: label !== "+" && root.activeKeys[label] === true
                }
              }
            }

            UiButton {
              visible: Boolean(root.phase === "waiting" && root.currentStep && !root.currentStepIsTour && root.currentStep.keys.length === 0)
              Layout.alignment: Qt.AlignHCenter
              kind: "primary"
              label: (root.currentStep ? root.currentStep.actionLabel || "Continue" : "").toUpperCase()
              onClicked: root.runStepAction("action")
            }
          }
        }

        RowLayout {
          id: controls
          z: 100
          visible: root.phase !== "loading"
          // The coach parks under the bar's right end for right-anchored
          // tour stops, exactly where these buttons sit; tuck them away so
          // learners aren't tempted to click them mid-tour.
          readonly property bool tuckedAway: root.phase === "waiting" &&
            root.currentStepIsTour &&
            Boolean(overlay.highlight) &&
            String(overlay.highlight.anchor || "").indexOf("right") !== -1
          opacity: tuckedAway ? 0 : 1
          enabled: !tuckedAway
          Behavior on opacity {
            NumberAnimation { duration: root.reducedMotion ? 0 : 450; easing.type: Easing.InOutSine }
          }
          anchors {
            top: parent.top
            right: parent.right
            topMargin: 42
            rightMargin: 24
          }
          spacing: 8

          Rectangle {
            visible: root.phase !== "settings"
            implicitWidth: 42
            implicitHeight: 42
            color: settingsMouse.containsMouse ? root.colorWithAlpha(root.accent, 0.34) : root.panelColor
            border.color: root.colorWithAlpha(root.accent, 0.55)
            border.width: 1
            radius: 21

            Text {
              anchors.centerIn: parent
              text: "⚙"
              color: root.foreground
              font.family: "sans-serif"
              font.pixelSize: 20
            }

            MouseArea {
              id: settingsMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (root.phase === "menu") root.openSettings("settings")
                else if (root.phase !== "loading" && root.phase !== "error") {
                  root.returnToMenu()
                  root.openSettings("settings")
                }
              }
            }
          }

          Rectangle {
            implicitWidth: 42
            implicitHeight: 42
            color: keysMouse.containsMouse ? root.colorWithAlpha(root.accent, 0.34) : root.panelColor
            border.color: root.keyboardExclusive ? root.colorWithAlpha(root.accent, 0.55) : root.instruction
            border.width: root.keyboardExclusive ? 1 : 2
            radius: 21

            Text {
              anchors.centerIn: parent
              text: "⌨"
              color: root.keyboardExclusive ? root.foreground : root.instruction
              font.family: "sans-serif"
              font.pixelSize: 19
            }

            MouseArea {
              id: keysMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.setKeyboardExclusive(!root.keyboardExclusive)
            }
          }

          Rectangle {
            implicitWidth: 42
            implicitHeight: 42
            color: audioMouse.containsMouse ? root.colorWithAlpha(root.accent, 0.34) : root.panelColor
            border.color: root.audioEnabled ? root.colorWithAlpha(root.accent, 0.55) : root.muted
            border.width: 1
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

          UiButton {
            visible: Boolean(root.phase === "waiting" && root.currentStep && root.currentStep.help)
            Layout.preferredHeight: 42
            label: "?  HELP"
            onClicked: root.requestHelpAction()
          }

          Rectangle {
            implicitWidth: 42
            implicitHeight: 42
            color: closeMouse.containsMouse ? root.colorWithAlpha(root.urgent, 0.3) : root.panelColor
            border.color: closeMouse.containsMouse ? root.urgent : root.colorWithAlpha(root.foreground, 0.3)
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
              text: "MODULE COMPLETE"
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
              text: "Nice work. Choose another topic or replay this module whenever you want."
              color: root.foreground
              opacity: 0.8
              wrapMode: Text.WordWrap
              font.family: "sans-serif"
              font.pixelSize: 15
            }
            RowLayout {
              Layout.alignment: Qt.AlignHCenter
              Layout.topMargin: 8
              spacing: 12

              UiButton {
                kind: "primary"
                label: "CHOOSE ANOTHER TOPIC"
                onClicked: root.returnToMenu()
              }
              UiButton {
                kind: "ghost"
                label: "REPLAY MODULE"
                onClicked: root.startLesson(root.lessonIndex)
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
            !root.currentTourTalks &&
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
                if (!introScene.rocket) return
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
          // Random blinks while holding a pointing pose.
          property bool blinking: false
          // 0 = limb down, 1 = halfway, 2 = pointing. Steps through 1 on the way up and down.
          property int poseStage: isPointing ? 2 : 0
          onIsPointingChanged: {
            if (root.reducedMotion || !root.poseMid) {
              poseStage = isPointing ? 2 : 0
              return
            }
            poseStage = 1
            poseStageTimer.restart()
          }
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
            root.characterState === "target-fly" ||
            root.characterState === "target-settle" ||
            root.characterState === "target-point"
          readonly property bool targetsTour:
            root.characterState === "tour-fly" ||
            root.characterState === "tour-settle" ||
            root.characterState === "tour-point" ||
            root.characterState === "tour-talk"
          readonly property bool isPointingUp: root.characterState === "tour-point"
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
            root.characterState === "target-point" ||
            root.characterState === "tour-point" ||
            root.characterState === "menu-point"
          // Fingertip of the upward pose inside the 224x192 image (before the 1.13 pose scale).
          readonly property real upTipImageX: Number(root.upTip.x)
          readonly property real upTipImageY: Number(root.upTip.y)
          readonly property real upTipLocalX: 8 + 112 + ((upTipImageX - 112) * pointUpPoseScale)
          readonly property real upTipLocalY: (height - 192) + 96 + ((upTipImageY - 96) * pointUpPoseScale)
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
          readonly property real pointPoseScale: root.pointPoseScale
          readonly property real pointUpPoseScale: root.pointUpPoseScale
          // Reticle sits a little ahead of the fingertip when pointing sideways.
          readonly property real pointLead: 15
          readonly property real pointTipLocalX: 8 + 112 + ((Number(root.pointTip.x) - 112) * pointPoseScale)
          readonly property real pointTipLocalY: (height - 192) + 96 + ((Number(root.pointTip.y) - 96) * pointPoseScale)
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
            overlay.targetPointX - (width / 2) - ((pointTipLocalX + pointLead - (width / 2)) * targetScale)
          readonly property real targetY:
            overlay.targetPointY - height + ((height - pointTipLocalY) * targetScale)
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
              ? Math.max(50, Math.min(bottomY, targetY))
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
                var swoop = Math.min(70, Math.max(24, horizontal * 0.1))
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
                if (root.phase === "lesson-complete") confettiAnimation.restart()
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
            // Blink at irregular intervals while pointing; the idle strip blinks on its own.
            id: blinkTimer
            interval: 2600
            repeat: true
            running: hexonCoach.visible && hexonCoach.isPointing && !hexonCoach.isFlying &&
              root.pointBlink && !root.reducedMotion
            onTriggered: {
              hexonCoach.blinking = true
              blinkOffTimer.restart()
              interval = 2200 + Math.floor(Math.random() * 3000)
            }
            onRunningChanged: if (!running) hexonCoach.blinking = false
          }

          Timer {
            id: poseStageTimer
            interval: 140
            repeat: false
            onTriggered: hexonCoach.poseStage = hexonCoach.isPointing ? 2 : 0
          }

          Timer {
            id: blinkOffTimer
            interval: 130
            repeat: false
            onTriggered: hexonCoach.blinking = false
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
              model: (hexonCoach.isPointing ? root.pointFlames : root.idleFlames).map(function(point) {
                return { "x": Number(point[0]), "y": Number(point[1]) }
              })

              delegate: Item {
                required property var modelData

                property real flamePulse: 1

                visible: hexonCoach.visible && !root.reducedMotion && root.characterFlames && !characterImageArea.showsFlight
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

            // Winged characters travel with their flight strip instead of the idle pose.
            readonly property bool showsFlight: root.flightFrames > 0 && !root.reducedMotion &&
              hexonCoach.isFlying && root.characterState.indexOf("-fly") !== -1

            SpriteSequence {
              anchors.centerIn: parent
              z: 1
              visible: root.flightFrames > 0
              opacity: characterImageArea.showsFlight ? 1 : 0
              width: 256
              height: 192
              interpolate: false
              running: characterImageArea.showsFlight
              transform: Scale {
                origin.x: 128
                xScale: hexonCoach.flightDirection
              }
              sprites: [
                Sprite {
                  name: "fly"
                  source: root.spriteSource("flight")
                  frameCount: Math.max(1, root.flightFrames)
                  frameWidth: 256
                  frameHeight: 192
                  frameRate: root.flightFrameRate
                }
              ]

              Behavior on opacity {
                NumberAnimation {
                  duration: root.characterPoseFadeDuration
                  easing.type: Easing.InOutSine
                }
              }
            }

            SpriteSequence {
              anchors.centerIn: parent
              z: 1
              opacity: hexonCoach.poseStage > 0 || characterImageArea.showsFlight ? 0 : 1
              width: 192
              height: 192
              interpolate: false
              goalSprite: root.characterState === "talk" ||
                (root.characterState === "tour-talk" && audioProcess.running)
                ? "talk" : "idle"
              onGoalSpriteChanged: jumpTo(goalSprite)

              sprites: [
                Sprite {
                  name: "idle"
                  source: root.spriteSource("idle")
                  frameCount: 16
                  frameWidth: 192
                  frameHeight: 192
                  frameRate: root.reducedMotion ? 2 : 6
                  to: { "idle": 1, "talk": 1 }
                },
                Sprite {
                  name: "talk"
                  source: root.spriteSource("talk")
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
              z: 2
              visible: root.pointBlink
              opacity: hexonCoach.poseStage === 2 && hexonCoach.isPointingUp && hexonCoach.blinking ? 1 : 0
              source: root.spriteSource("point-up-blink")
              fillMode: Image.PreserveAspectFit
              smooth: false
              mipmap: false
              scale: hexonCoach.pointUpPoseScale
            }

            Image {
              anchors.fill: parent
              z: 2
              visible: root.pointBlink
              opacity: hexonCoach.poseStage === 2 && !hexonCoach.isPointingUp && hexonCoach.blinking ? 1 : 0
              source: root.spriteSource("point-blink")
              fillMode: Image.PreserveAspectFit
              smooth: false
              mipmap: false
              scale: hexonCoach.pointPoseScale
            }

            Image {
              anchors.fill: parent
              z: 1
              visible: root.poseMid
              opacity: hexonCoach.poseStage === 1 && hexonCoach.isPointingUp ? 1 : 0
              source: root.spriteSource("point-up-mid")
              fillMode: Image.PreserveAspectFit
              smooth: false
              mipmap: false
              scale: hexonCoach.pointUpPoseScale
            }

            Image {
              anchors.fill: parent
              z: 1
              visible: root.poseMid
              opacity: hexonCoach.poseStage === 1 && !hexonCoach.isPointingUp ? 1 : 0
              source: root.spriteSource("point-mid")
              fillMode: Image.PreserveAspectFit
              smooth: false
              mipmap: false
              scale: hexonCoach.pointPoseScale
            }

            Image {
              anchors.fill: parent
              z: 1
              opacity: hexonCoach.poseStage === 2 && hexonCoach.isPointingUp ? 1 : 0
              source: root.spriteSource("point-up")
              fillMode: Image.PreserveAspectFit
              smooth: false
              mipmap: false
              scale: hexonCoach.pointUpPoseScale

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
              opacity: hexonCoach.poseStage === 2 && !hexonCoach.isPointingUp ? 1 : 0
              source: root.spriteSource("point")
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

      }
    }
  }
}
