import QtQuick
import QtTest

Item {
  id: root
  width: 1200
  height: 800
  property var fixture
  property string phase: "waiting"
  onPhaseChanged: tourDetailsExpanded = false
  property bool currentStepIsTour: true
  property bool tourDetailsExpanded: false
  onTourDetailsExpandedChanged: if (fixture) fixture.updateTourDetails()
  property bool autoAdvance: true
  property bool introDeparting: false
  property bool audioStopRequested: false
  property string pendingAudioPath: ""
  property int narrationRestMs: 900
  property int readingWordsPerMinute: 200
  property bool keyboardExclusive: true
  property real textScale: 1
  property bool reducedMotion: true
  property real lessonContentOpacity: 1
  property bool lessonTransitionRunning: false
  property string pendingLessonTransition: ""
  property int stepIndex: 1
  property var currentLesson: ({title: "Your desktop", steps: [{id: "first"}, {id: "second"}]})
  property var currentStep: ({instruction: "Look at the desktop bar.", detail: "Additional explanation.", keys: [],
    completionMessage: "The menu is open.", completion: {type: "hyprland-layer-open"}})
  onCurrentStepChanged: tourDetailsExpanded = false
  property var stepResults: ({})
  property var activeKeys: ({})
  readonly property var currentStepKeys: currentStep.keys
  property bool introActive: false
  property bool practiceMode: false
  property bool practiceHintVisible: false
  property bool stepAssisted: false
  property string recoveryMessage: ""
  property string recoveryStepId: ""
  property string integrationNotice: ""
  property bool currentStepHasNoVisibleTarget: false
  property bool exerciseRunning: false
  property bool practiceSessionActive: false
  readonly property bool embeddedPracticeRunning: exerciseRunning && practiceSessionActive
  property Item practiceHost: null
  readonly property bool inlineAppSearch: currentStep.practice === "app-search"
  property color foreground: "#c0caf5"
  property color background: "#1a1b26"
  property color accent: "#7aa2f7"
  property color instruction: "#e0af68"
  property color urgent: "#f7768e"
  property color muted: "#a0a9c9"
  property color panelColor: background
  property color subtleFill: background
  property color panelBorder: "#414868"
  property color keyFace: background
  property Palette controlPalette: Palette { highlightedText: "black" }
  property string lastAction: ""
  property bool audioStopped: false
  property bool lessonCaptionVisible: false
  property int revealEnd: -1
  function lessonRevealEnd(message) { return currentStepIsTour && phase === "waiting" ? -1 : revealEnd }
  function lessonCaptionMatches(message) {
    return message === (phase === "highlight" ? currentStep.completionMessage : currentStep.instruction)
  }

  function colorWithAlpha(color, alpha) { return Qt.rgba(color.r, color.g, color.b, alpha) }
  function characterText(text) { return text }
  function captionText(text) { return text }
  function currentAudioPath() { return "narration.mp3" }
  function stopAudio() { audioStopped = true }
  function advance() { lastAction = "advance" }
  function previousStep() { lastAction = "back" }
  function returnToMenu() { lastAction = "topics" }
  function replayCurrentAudio() { lastAction = "replay" }
  function skipCurrentStep() { lastAction = "skip" }
  function recoverTutorialWindow() { lastAction = "recover" }
  function runStepAction(action) { lastAction = action }
  function cancelAction() { exerciseRunning = false; practiceSessionActive = false }
  function handleKeyPressed(event) {}
  function updateActiveKeys(event, pressed) {}
  function geometryGuidance(estimated) { return fixture ? fixture.geometryGuidance(estimated) : "" }

  QtObject { id: audioProcess; property bool running: false }
  QtObject { id: barGeometryProcess; property bool running: false }
  Timer { id: tourAdvanceTimer; onTriggered: fixture.advanceTour() }

  Item {
    id: overlay
    anchors.fill: parent
    property bool shouldShow: true
    property bool isFocusedScreen: true
    property var measuredBarTarget: null
    property var measuredWindowTarget: null
    property bool targetIsEstimated: false
  }
  QtObject { id: tourCaption; property bool ready: true }

  function buttons(item) {
    var result = "label" in item && "clicked" in item && item.visible ? [item] : []
    for (var child of item.children || []) result = result.concat(buttons(child))
    return result
  }

  TestCase {
    name: "TeachingContentFocus"
    when: windowShown

    function initTestCase() {
      var xhr = new XMLHttpRequest()
      xhr.open("GET", Qt.resolvedUrl("../../app/shell.qml"), false)
      xhr.send()
      var source = xhr.responseText
      var components = source.slice(source.indexOf("  component UiPanel:"), source.indexOf("  component PreferenceSwitch:"))
        + source.slice(source.indexOf("  component Keycap:"), source.indexOf("  function setCharacterState("))
      var start = source.indexOf("        UiPanel {\n          id: teachingContent")
      var end = source.indexOf("        Rectangle {\n          id: welcomeToolbarOutline", start)
      verify(start >= 0 && end > start)
      var runtimeFunctions = ["readingDuration", "tourAdvanceDelay", "canAutoAdvanceTour",
        "updateTourDetails", "scheduleTourAdvance", "advanceTour", "geometryGuidance"]
        .map(function(name) {
          return source.match(new RegExp("  function " + name + "\\([^\\n]*\\) \\{[\\s\\S]*?\\n  \\}"))[0]
        }).join("\n")
      root.fixture = Qt.createQmlObject(
        "import QtQuick\nimport QtQuick.Layouts\nimport \"../../app\"\n"
        + "import \"../../app/TeachingLayout.js\" as TeachingLayout\nItem { anchors.fill: parent\n"
        + "property alias panel: teachingContent\nproperty alias navigation: lessonNavigation\n"
        + "property alias instructionText: teachingInstruction\n"
        + "property alias note: teachingNote\nproperty alias details: teachingDetails\n"
        + "property alias keycaps: instructionKeys\nproperty alias actionButton: stepActionButton\n"
        + runtimeFunctions + components + source.slice(start, end) + "\n}", overlay)
    }

    function init() {
      failOnWarning(/.*/)
      root.phase = "waiting"
      root.revealEnd = -1
      root.currentStepIsTour = true
      root.currentStep = {instruction: "Look at the desktop bar.", detail: "Additional explanation.", keys: [],
        completionMessage: "The menu is open.", completion: {type: "hyprland-layer-open"}}
      root.practiceMode = false
      root.exerciseRunning = false
      root.practiceSessionActive = false
      overlay.measuredBarTarget = null
      overlay.measuredWindowTarget = null
      root.practiceHintVisible = false
      root.stepAssisted = false
      root.width = 1200
      root.textScale = 1
      root.lastAction = ""
      root.audioStopped = false
      root.recoveryMessage = ""
      root.recoveryStepId = ""
      root.integrationNotice = ""
      root.currentStepHasNoVisibleTarget = false
      overlay.targetIsEstimated = false
      barGeometryProcess.running = false
      root.keyboardExclusive = true
      root.autoAdvance = true
      audioProcess.running = false
      root.tourDetailsExpanded = false
      tourAdvanceTimer.stop()
      wait(30)
    }

    function test_geometryGuidanceIsLocalToAnEstimatedLessonTarget() {
      var notice = findChild(fixture, "teachingGeometryNotice")
      verify(!notice.visible)
      root.integrationNotice = "Bar measurements are available."
      root.currentStep = { instruction: "Switch to workspace 2.", keys: ["SUPER", "2"],
        highlight: { target: "workspace", workspaceId: 2 }, completion: { type: "hyprland-workspace" } }
      overlay.targetIsEstimated = true
      wait(30)
      verify(notice.visible)
      verify(notice.text.indexOf("workspace number") >= 0)
      verify(notice.y + notice.height <= fixture.panel.height)
      overlay.targetIsEstimated = false
      tryCompare(notice, "visible", false)
      overlay.targetIsEstimated = true
      root.phase = "arcade"
      tryCompare(notice, "visible", false)
    }

    function test_tallPanelKeepsItsWarningAndCoachingCardOutsideTheNativeMenu() {
      root.currentStepIsTour = false
      root.currentStep = { instruction: "Open the guide.", keys: ["SUPER", "+", "K"],
        note: "Read only: selecting an entry executes its shortcut.",
        completionMessage: "Read the guide without executing a shortcut.",
        completion: { type: "hyprland-layer-open" }, highlight: { target: "panel" } }
      overlay.measuredBarTarget = { x: 500, y: 50, width: 200, height: 700, panel: true }
      root.phase = "highlight"
      wait(30)
      verify(fixture.note.visible)
      verify(fixture.panel.x + fixture.panel.width <= 484 ||
        fixture.panel.x >= 716, "The card must leave a gap beside the menu")
      verify(fixture.panel.y >= 12 && fixture.panel.y + fixture.panel.height <= root.height - 12)
    }

    function test_geometryPollingDoesNotResizeOrMoveTheTeachingPanel() {
      root.currentStepIsTour = false
      root.currentStep = { instruction: "Switch to workspace 2.", keys: ["SUPER", "2"],
        highlight: { target: "workspace", workspaceId: 2 }, completion: { type: "hyprland-workspace" } }
      root.integrationNotice = "Bar measurements are available."
      overlay.targetIsEstimated = true
      var notice = findChild(fixture, "teachingGeometryNotice")
      for (var scale of [1, 1.3]) {
        root.textScale = scale
        wait(30)
        var height = fixture.panel.height
        var y = fixture.panel.y
        for (var poll = 0; poll < 3; poll++) {
          barGeometryProcess.running = true
          wait(30)
          verify(notice.visible, "Background measurements must not hide existing guidance")
          compare(fixture.panel.height, height)
          compare(fixture.panel.y, y)
          barGeometryProcess.running = false
          wait(30)
          compare(fixture.panel.height, height)
          compare(fixture.panel.y, y)
        }
      }
    }

    function test_embeddedPracticeKeepsNormalNavigationAndItsSafetyNote() {
      root.stepIndex = 0
      root.currentStepIsTour = false
      root.currentStep = { instruction: "Start the exercise.", keys: [], practice: "clipboard",
        actionLabel: "Start exercise", note: "Use only the harmless sample." }
      root.practiceSessionActive = true
      root.exerciseRunning = true
      wait(30)
      verify(fixture.panel.visible)
      verify(fixture.navigation.visible)
      verify(fixture.note.visible)
      verify(root.practiceHost.visible && root.practiceHost.height > 0)
      verify(!fixture.actionButton.visible)
      verify(!fixture.instructionText.visible)
      verify(root.buttons(fixture).some(function(button) { return button.label === "SKIP →" }))
      var back = root.buttons(fixture).find(function(button) { return button.label === "BACK" })
      verify(!back.enabled)
      compare(back.opacity, 1)
      compare(back.color.a, 1)
      root.stepIndex = 1
    }

    function test_tourHasOneQuietNavigationRowWithoutDuplicateProse() {
      verify(fixture.panel.compactTour)
      verify(!fixture.instructionText.visible)
      compare(fixture.panel.stripe.a, 0)
      verify(fixture.panel.height <= 64)
      var visibleButtons = root.buttons(fixture)
      compare(visibleButtons.map(function(button) { return button.label }).join("|"), "← TOPICS|BACK|DETAILS|NEXT")
      for (var button of visibleButtons) {
        compare(Math.round(button.mapToItem(overlay, 0, 0).y),
          Math.round(visibleButtons[0].mapToItem(overlay, 0, 0).y))
      }
      for (var entry of [["← TOPICS", "topics"], ["BACK", "back"], ["NEXT", "advance"]]) {
        visibleButtons.find(function(button) { return button.label === entry[0] }).clicked()
        compare(root.lastAction, entry[1])
      }
      verify(root.audioStopped)
    }

    function test_detailsRetainExtraGuidanceAndReplayWithoutCompetingByDefault() {
      root.buttons(fixture).find(function(button) { return button.label === "DETAILS" }).clicked()
      wait(30)
      verify(fixture.instructionText.visible)
      compare(fixture.instructionText.text, root.currentStep.detail)
      root.buttons(fixture).find(function(button) { return button.label === "▶ REPLAY" }).clicked()
      compare(root.lastAction, "replay")
      root.buttons(fixture).find(function(button) { return button.label === "LESS" }).clicked()
      wait(30)
      verify(!fixture.instructionText.visible)
      root.tourDetailsExpanded = true
      root.currentStep = Object.assign({}, root.currentStep, {instruction: "A new tour stop."})
      wait(30)
      verify(!fixture.panel.detailsExpanded)
    }

    function test_detailsSuspendActualTimerAndResumeAfterReadingOrNarration() {
      fixture.scheduleTourAdvance(100)
      verify(tourAdvanceTimer.running)
      root.buttons(fixture).find(function(button) { return button.label === "DETAILS" }).clicked()
      verify(root.tourDetailsExpanded)
      verify(!tourAdvanceTimer.running)
      // Even an already queued timeout cannot move to another activity.
      tourAdvanceTimer.interval = 20
      tourAdvanceTimer.restart()
      wait(60)
      compare(root.lastAction, "")
      fixture.scheduleTourAdvance(20)
      verify(!tourAdvanceTimer.running)
      audioProcess.running = true
      root.buttons(fixture).find(function(button) { return button.label === "LESS" }).clicked()
      verify(audioProcess.running)
      verify(!tourAdvanceTimer.running)
      audioProcess.running = false
      fixture.scheduleTourAdvance()
      compare(tourAdvanceTimer.interval, root.narrationRestMs)
      verify(tourAdvanceTimer.running)
      root.tourDetailsExpanded = true
      root.tourDetailsExpanded = false
      verify(tourAdvanceTimer.interval >= 2200)
      tourAdvanceTimer.interval = 20
      tourAdvanceTimer.restart()
      tryCompare(root, "lastAction", "advance")
    }

    function test_detailsResetOnPauseAndManualNextStillWorks() {
      root.tourDetailsExpanded = true
      root.buttons(fixture).find(function(button) { return button.label === "NEXT" }).clicked()
      compare(root.lastAction, "advance")
      verify(root.audioStopped)
      root.phase = "paused"
      verify(!root.tourDetailsExpanded)
      verify(!tourAdvanceTimer.running)
      root.phase = "waiting"
      root.tourDetailsExpanded = true
      root.autoAdvance = false
      root.tourDetailsExpanded = false
      verify(!tourAdvanceTimer.running)
    }

    function test_actionAndCompletionInstructionsRemainAvailable() {
      root.currentStepIsTour = false
      wait(30)
      verify(!fixture.panel.compactTour)
      verify(fixture.instructionText.visible)
      compare(fixture.instructionText.text, root.currentStep.instruction)
      verify(root.buttons(fixture).some(function(button) { return button.label === "SKIP →" }))
      root.currentStepIsTour = true
      root.phase = "highlight"
      wait(30)
      verify(fixture.instructionText.visible)
      compare(fixture.instructionText.text, root.currentStep.completionMessage)
      verify(root.buttons(fixture).some(function(button) { return button.label === "CONTINUE" }))
    }

    function test_wordRevealKeepsActionLayoutAndSafetyGuidanceVisible() {
      root.currentStepIsTour = false
      root.currentStep = {instruction: "Hold Super and tap two.", keys: ["SUPER", "+", "2"],
        note: "Your windows stay open.", completionMessage: "You are on workspace two.",
        completion: {type: "manual"}}
      wait(30)
      var height = fixture.instructionText.height
      root.revealEnd = 4
      wait(20)
      compare(fixture.instructionText.color.a, 0)
      compare(fixture.instructionText.height, height)
      verify(fixture.keycaps.visible)
      verify(fixture.note.visible)
      verify(fixture.note.color.a > 0)
      compare(fixture.note.opacity, 1)
      var reveal = fixture.instructionText.children[0]
      verify(reveal.visible)
      compare(reveal.fullText, root.currentStep.instruction)
      compare(reveal.revealEnd, 4)
      root.phase = "highlight"
      root.revealEnd = 3
      wait(20)
      compare(reveal.fullText, root.currentStep.completionMessage)
      compare(reveal.revealEnd, 3)
      root.revealEnd = -1
      wait(20)
      verify(!reveal.visible)
      verify(fixture.instructionText.color.a > 0)
    }

    function test_actionShowsInstructionThenKeysThenOneReadableNote() {
      root.currentStepIsTour = false
      root.currentStep = {instruction: "Hold Super and tap 2.", keys: ["SUPER", "+", "2"],
        note: "Your windows stay open when you switch workspaces.",
        detail: "Workspace two may already contain windows. Switching doesn't close or move them."}
      wait(30)
      verify(fixture.instructionText.visible)
      verify(fixture.keycaps.visible)
      verify(fixture.note.visible)
      verify(!fixture.details.visible)
      compare(fixture.note.font.pixelSize, 17)
      compare(fixture.note.opacity, 1)
      verify(fixture.keycaps.y >= fixture.instructionText.y + fixture.instructionText.height)
      verify(fixture.note.y >= fixture.keycaps.y + fixture.keycaps.height)
      root.buttons(fixture).find(function(button) { return button.label === "DETAILS" }).clicked()
      wait(30)
      verify(fixture.details.visible)
      compare(fixture.details.text, root.currentStep.detail)
      compare(fixture.details.font.pixelSize, 17)
      compare(fixture.instructionText.text, root.currentStep.instruction)
      root.currentStep = {instruction: "Close this window.", keys: ["SUPER", "+", "W"]}
      wait(30)
      verify(!fixture.details.visible)
      verify(!fixture.note.visible)
      verify(!root.buttons(fixture).some(function(button) { return button.label === "DETAILS" }))
    }

    function test_practiceAlwaysShowsTheGoalButRevealsShortcutsOnlyWithAHint() {
      var xhr = new XMLHttpRequest()
      xhr.open("GET", Qt.resolvedUrl("../../courses/omarchy-basics.json"), false)
      xhr.send()
      var course = JSON.parse(xhr.responseText)
      root.currentStepIsTour = false
      root.practiceMode = true
      var count = 0
      for (var lesson of course.lessons) {
        for (var step of lesson.steps) {
          if (!step.help) continue
          root.currentStep = step
          root.practiceHintVisible = false
          wait(1)
          verify(fixture.instructionText.visible, step.id)
          compare(fixture.instructionText.text, step.practicePrompt, step.id)
          verify(!fixture.keycaps.visible, step.id)
          if (step.note) verify(fixture.note.visible, step.id)
          root.practiceHintVisible = true
          wait(1)
          compare(fixture.instructionText.text, step.instruction, step.id)
          compare(fixture.keycaps.visible, step.keys.length > 0, step.id)
          count++
        }
      }
      verify(count > 50)
      root.currentStep = { instruction: "Switch to workspace one with Super and 1.", keys: ["SUPER", "+", "1"],
        help: { label: "Take me there" } }
      root.practiceHintVisible = false
      wait(1)
      compare(fixture.instructionText.text, root.currentStep.instruction, "legacy courses show real guidance, never a generic button label")
    }

    function test_practiceGoalSwitchesToInstructionOnDetailsAndResultOnCompletion() {
      root.currentStepIsTour = false
      root.practiceMode = true
      root.currentStep = { instruction: "Press Super and 1.", practicePrompt: "Switch to workspace one.",
        keys: ["SUPER", "+", "1"], help: {label: "Take me there"},
        detail: "Your other windows stay open.", note: "Leave your other windows open.",
        completionMessage: "You're on workspace one.", completion: { type: "hyprland-workspace-is", id: 1 },
        highlight: { target: "workspace" } }
      wait(20)
      compare(fixture.instructionText.text, "Switch to workspace one.")
      root.buttons(fixture).find(function(button) { return button.label === "DETAILS" }).clicked()
      wait(20)
      compare(fixture.instructionText.text, "Press Super and 1.")
      verify(fixture.keycaps.visible)
      verify(root.stepAssisted)
      compare(root.lastAction, "", "requesting a hint doesn't perform the task")
      root.phase = "highlight"
      wait(20)
      compare(fixture.instructionText.text, "You're on workspace one.")
    }

    function test_practiceKeepsSafetyNoteAfterActionAndDetailsCountAsAHint() {
      root.currentStepIsTour = false
      root.practiceMode = true
      root.currentStep = {instruction: "Copy the practice notes.", keys: [], actionLabel: "Start exercise",
        note: "This replaces your clipboard with harmless sample text.", detail: "Copy the older note first."}
      wait(30)
      verify(fixture.actionButton.visible)
      verify(fixture.note.visible)
      verify(fixture.note.y >= fixture.actionButton.y + fixture.actionButton.height)
      verify(!fixture.details.visible)
      root.buttons(fixture).find(function(button) { return button.label === "DETAILS" }).clicked()
      verify(root.practiceHintVisible)
      verify(root.stepAssisted)
      fixture.actionButton.clicked()
      compare(root.lastAction, "action")
    }

    function test_actionNotesAndNavigationFitNarrowScreens() {
      root.currentStepIsTour = false
      root.currentStep = {instruction: "Hold Super and tap 2.", keys: ["SUPER", "+", "2"],
        note: "Your windows stay open when you switch workspaces.", detail: "Additional explanation."}
      for (var size of [[900, 1], [640, 1.3], [460, 1.3]]) {
        root.width = size[0]
        root.textScale = size[1]
        wait(30)
        verify(fixture.note.contentWidth <= fixture.note.width)
        for (var button of root.buttons(fixture)) {
          var position = button.mapToItem(overlay, 0, 0)
          verify(position.x >= 0)
          verify(position.x + button.width <= root.width)
        }

      }
    }

    function test_inlineSearchKeepsItsGuidanceAndSkipWithoutAnExerciseDialog() {
      root.currentStepIsTour = false
      root.currentStep = {instruction: "Open Apps, search for Terminal, then close the new terminal.",
        keys: [], practice: "app-search", actionLabel: "Start search", note: "Your existing windows stay open."}
      root.exerciseRunning = true
      root.keyboardExclusive = false
      wait(30)
      verify(fixture.panel.visible)
      verify(fixture.instructionText.visible)
      compare(fixture.instructionText.message, root.currentStep.instruction)
      verify(fixture.note.visible)
      compare(fixture.actionButton.label, "SEARCH IN PROGRESS")
      verify(!fixture.actionButton.enabled)
      verify(root.buttons(fixture).some(function(button) { return button.label === "SKIP →" }))
      root.exerciseRunning = false
    }

    function test_narrowAndLargeTextLayoutsKeepNavigationOnScreen() {
      for (var size of [[640, 1], [640, 1.3], [360, 1.3]]) {
        root.width = size[0]
        root.textScale = size[1]
        wait(30)
        for (var button of root.buttons(fixture)) {
          var position = button.mapToItem(overlay, 0, 0)
          verify(position.x >= 0)
          verify(position.x + button.width <= root.width)
          verify(position.y >= 0 && position.y + button.height <= root.height)
        }
      }
      verify(fixture.navigation.stacked)
    }

    function test_everyCourseStepFitsReadableLessonSurfaces() {
      var xhr = new XMLHttpRequest()
      xhr.open("GET", Qt.resolvedUrl("../../courses/omarchy-basics.json"), false)
      xhr.send()
      var course = JSON.parse(xhr.responseText)
      var checked = 0
      for (var display of [[1280, 720, 1], [1024, 720, 1.3], [640, 720, 1.3]]) {
        root.width = display[0]
        root.height = display[1]
        root.textScale = display[2]
        for (var lesson of course.lessons) {
          if (!lesson.steps.length) continue
          root.currentLesson = lesson
          for (var index = 0; index < lesson.steps.length; index++) {
            var step = lesson.steps[index]
            root.stepIndex = index
            root.currentStepIsTour = step.kind === "tour"
            root.currentStep = step
            root.phase = "waiting"
            wait(20)
            verify(fixture.panel.x >= 0 && fixture.panel.y >= 0, step.id)
            verify(fixture.panel.x + fixture.panel.width <= root.width + 1, step.id)
            verify(fixture.panel.y + fixture.panel.height <= root.height + 1, step.id)
            for (var button of root.buttons(fixture)) {
              var position = button.mapToItem(overlay, 0, 0)
              verify(position.x >= -1 && position.x + button.width <= root.width + 1,
                step.id + ": " + button.label + " at " + display.join("x") + " x=" + position.x + " width=" + button.width)
              verify(position.y >= -1 && position.y + button.height <= root.height + 1,
                step.id + ": " + button.label + " at " + display.join("x") + " y=" + position.y + " height=" + button.height)
            }
            if (root.currentStepIsTour) {
              verify(!fixture.instructionText.visible, step.id)
              if (step.detail) {
                root.tourDetailsExpanded = true
                wait(20)
                compare(fixture.instructionText.text, step.detail, step.id)
                verify(fixture.panel.y + fixture.panel.height <= root.height + 1, step.id + ": details")
                root.tourDetailsExpanded = false
              }
            } else {
              verify(fixture.instructionText.visible, step.id)
              compare(fixture.instructionText.text, step.instruction, step.id)
              verify(fixture.instructionText.contentWidth <= fixture.instructionText.width + 1, step.id)
              if (step.note) verify(fixture.note.visible, step.id)
            }
            root.phase = "highlight"
            wait(20)
            if (!root.currentStepIsTour && step.completionMessage) {
              compare(fixture.instructionText.text, step.completionMessage, step.id + ": completion")
              verify(fixture.instructionText.contentWidth <= fixture.instructionText.width + 1, step.id + ": completion")
            }
            verify(fixture.panel.y + fixture.panel.height <= root.height + 1, step.id + ": highlight")
            checked++
          }
        }
      }
      compare(checked, 93 * 3)
    }

    function test_recoveryIsNeverHiddenByCompactTour() {
      root.recoveryMessage = "The practice window was closed."
      root.recoveryStepId = "first"
      wait(30)
      var recovery = root.buttons(fixture).find(function(button) { return button.label === "REOPEN PRACTICE WINDOW" })
      verify(recovery !== undefined)
      recovery.clicked()
      compare(root.lastAction, "recover")
    }
  }
}
