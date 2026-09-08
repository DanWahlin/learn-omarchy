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
  property bool exerciseRunning: false
  property color foreground: "#c0caf5"
  property color background: "#1a1b26"
  property color accent: "#7aa2f7"
  property color instruction: "#e0af68"
  property color urgent: "#f7768e"
  property color muted: "#a0a9c9"
  property color panelColor: background
  property color panelBorder: "#414868"
  property color keyFace: background
  property Palette controlPalette: Palette { highlightedText: "black" }
  property string lastAction: ""
  property bool audioStopped: false

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
  function handleKeyPressed(event) {}
  function updateActiveKeys(event, pressed) {}
  function openedToolKeyboardHint() { return fixture ? fixture.openedToolKeyboardHint() : "" }

  QtObject { id: audioProcess; property bool running: false }
  Timer { id: tourAdvanceTimer; onTriggered: fixture.advanceTour() }

  Item { id: overlay; anchors.fill: parent }

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
      var components = source.slice(source.indexOf("  component UiPanel:"), source.indexOf("  component PreferenceSlider:"))
        + source.slice(source.indexOf("  component Keycap:"), source.indexOf("  function setCharacterState("))
      var start = source.indexOf("        UiPanel {\n          id: teachingContent")
      var end = source.indexOf("        GridLayout {\n          id: controls", start)
      verify(start >= 0 && end > start)
      var runtimeFunctions = ["readingDuration", "tourAdvanceDelay", "canAutoAdvanceTour",
        "updateTourDetails", "scheduleTourAdvance", "advanceTour", "openedToolKeyboardHint"]
        .map(function(name) {
          return source.match(new RegExp("  function " + name + "\\([^\\n]*\\) \\{[\\s\\S]*?\\n  \\}"))[0]
        }).join("\n")
      root.fixture = Qt.createQmlObject(
        "import QtQuick\nimport QtQuick.Layouts\nItem { anchors.fill: parent\n"
        + "property alias panel: teachingContent\nproperty alias navigation: lessonNavigation\n"
        + "property alias instructionText: teachingInstruction\n"
        + "property alias keyboardHint: openedToolKeyboardHint\n"
        + runtimeFunctions + components + source.slice(start, end) + "\n}", overlay)
    }

    function init() {
      failOnWarning(/.*/)
      root.phase = "waiting"
      root.currentStepIsTour = true
      root.width = 1200
      root.textScale = 1
      root.lastAction = ""
      root.audioStopped = false
      root.recoveryMessage = ""
      root.recoveryStepId = ""
      root.keyboardExclusive = true
      root.autoAdvance = true
      audioProcess.running = false
      root.tourDetailsExpanded = false
      tourAdvanceTimer.stop()
      wait(30)
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

    function test_layerKeyboardHintFollowsCaptureAndDoesNotRepeatInstruction() {
      verify(!fixture.keyboardHint.visible)
      root.phase = "highlight"
      tryCompare(fixture.keyboardHint, "visible", true)
      compare(fixture.keyboardHint.text, "Use Release Keys to interact with the opened tool.")
      verify(root.keyboardExclusive)
      root.keyboardExclusive = false
      tryCompare(fixture.keyboardHint, "visible", false)
      root.keyboardExclusive = true
      root.currentStep = Object.assign({}, root.currentStep, {
        completionMessage: "Choose Release Keys before typing or browsing here."
      })
      tryCompare(fixture.keyboardHint, "visible", false)
      root.currentStep = Object.assign({}, root.currentStep, {completionMessage: "The menu is open."})
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
