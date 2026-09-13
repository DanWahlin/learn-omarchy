import QtQuick
import QtTest

Item {
  id: root
  width: 1200
  height: 800
  property var fixture
  property string phase: "lesson-complete"
  property bool referenceBrowsing: false
  property var currentLesson: ({ title: "Omarchy tour" })
  property int lessonIndex: 1
  property real lessonContentOpacity: 1
  property bool lessonTransitionRunning: false
  property bool lessonWrapupReady: false
  property string characterState: "celebrate"
  property real textScale: 1
  property bool reducedMotion: true
  property bool mixedPracticeActive: false
  property int mixedLessonPosition: 0
  property var mixedLessonIds: ["tour", "windows"]
  property int mixedEligibleCount: 0
  property string retentionNotice: ""
  property string lastAction: ""
  property var result: ({ practiced: 3, assisted: 0, introduced: 5, skipped: 0, remaining: 0 })
  property var wrapup: ({ text: "Nice work, that's the tour. You've explored the desktop bar, switched workspaces, and opened the Omarchy menu." })
  property color background: "#080d20"
  property color foreground: "#dcc3aa"
  property color accent: "#8984d8"
  property color instruction: "#ebc343"
  property color urgent: "#ed7387"
  property color muted: "#aaa8c5"
  property color panelColor: background
  property color panelBorder: "#34354a"
  property color subtleFill: background
  property Palette controlPalette: Palette { highlightedText: "#080d20" }

  function colorWithAlpha(color, alpha) { return Qt.rgba(color.r, color.g, color.b, alpha) }
  function lessonResultSummary(lesson) { return result }
  function currentLessonWrapup() { return wrapup }
  function characterText(text) { return text }
  function captionText(text) { return text }
  function returnToMenu() { lastAction = "topics" }
  function nextMixedLesson() { lastAction = "next-review" }
  function startMixedPractice() { lastAction = "review" }
  function startLesson(index, practice, resume) { lastAction = index + ":" + practice + ":" + resume }
  function handleKeyPressed(event) {}
  function updateActiveKeys(event, pressed) {}

  QtObject { id: coachTravelX; property bool running: false }
  QtObject { id: coachTravelY; property bool running: false }
  QtObject { id: wrapupReveal; property int revealEnd: -1 }
  Item { id: overlay; anchors.fill: parent; property bool shouldShow: true }

  function buttons(item) {
    var found = "label" in item && "clicked" in item && item.visible ? [item] : []
    for (var child of item.children || []) found = found.concat(buttons(child))
    return found
  }
  function button(label) {
    return buttons(fixture).find(function(item) { return item.label === label })
  }

  TestCase {
    name: "SimpleModuleCompletion"
    when: windowShown

    function initTestCase() {
      var xhr = new XMLHttpRequest()
      xhr.open("GET", Qt.resolvedUrl("../../app/shell.qml"), false)
      xhr.send()
      var source = xhr.responseText
      var components = source.slice(source.indexOf("  component UiPanel:"), source.indexOf("  component PreferenceSwitch:"))
      var start = source.indexOf("        UiPanel {\n          id: completionPanel")
      var end = source.indexOf("        RowLayout {\n          id: welcomeControls", start)
      verify(start >= 0 && end > start)
      fixture = Qt.createQmlObject("import QtQuick\nimport QtQuick.Layouts\nimport QtQuick.Controls as Controls\n"
        + "import \"../../app\"\nItem { anchors.fill: parent\n"
        + "property alias panel: completionPanel\nproperty alias column: completionColumn\n"
        + "property alias caption: wrapupCaptionText\nproperty alias scroll: completionScroll\n"
        + components + source.slice(start, end) + "\n}", overlay)
    }

    function init() {
      failOnWarning(/.*/)
      root.phase = "menu"
      root.width = 1200
      root.height = 800
      root.textScale = 1
      root.currentLesson = { title: "Omarchy tour" }
      root.result = { practiced: 3, assisted: 0, introduced: 5, skipped: 0, remaining: 0 }
      root.wrapup = { text: "Nice work, that's the tour. You've explored the desktop bar, switched workspaces, and opened the Omarchy menu." }
      root.mixedPracticeActive = false
      root.mixedEligibleCount = 0
      root.mixedLessonPosition = 0
      root.retentionNotice = ""
      root.lastAction = ""
      wrapupReveal.revealEnd = -1
      root.phase = "lesson-complete"
      wait(30)
    }

    function test_defaultViewHasOneHeadingRecapAndMainAction() {
      compare(root.buttons(fixture).map(function(item) { return item.label }).join("|"),
        "CHOOSE ANOTHER TOPIC")
      compare(findChild(fixture, "completionHeading").text, "Omarchy tour complete")
      compare(findChild(fixture, "completionCheckmark").width, 48)
      compare(fixture.column.spacing, 22)
      compare(fixture.caption.text, root.wrapup.text)
      var heading = findChild(fixture, "completionHeading")
      verify(fixture.caption.y - heading.y - heading.height >= 22)
      verify(!findChild(fixture, "completionDetails"))
      verify(!findChild(fixture, "completionMoreOptions"))
      verify(!root.button("PRINTABLE SHORTCUTS"))
      root.button("CHOOSE ANOTHER TOPIC").clicked()
      compare(root.lastAction, "topics")
    }

    function test_primaryActionIsKeyboardAccessible() {
      root.button("CHOOSE ANOTHER TOPIC").forceActiveFocus(Qt.TabFocusReason)
      keyClick(Qt.Key_Space)
      compare(root.lastAction, "topics")
      root.lastAction = ""
      keyClick(Qt.Key_Return)
      compare(root.lastAction, "topics")
    }

    function test_activeReviewKeepsOnlyItsContinuationAction() {
      root.mixedEligibleCount = 2
      root.mixedPracticeActive = true
      wait(30)
      compare(root.buttons(fixture).length, 1)
      root.button("NEXT REVIEW MODULE").clicked()
      compare(root.lastAction, "next-review")
      root.mixedLessonPosition = 1
      wait(30)
      verify(root.button("FINISH REVIEW"))
    }

    function test_incompleteModulesKeepHonestHeadingsAndStableCaptions() {
      root.result = { practiced: 1, assisted: 0, introduced: 2, skipped: 3, remaining: 2 }
      wait(30)
      compare(findChild(fixture, "completionHeading").text, "Omarchy tour explored")
      compare(root.buttons(fixture).length, 1)
      var height = fixture.panel.height
      wrapupReveal.revealEnd = 10
      wait(30)
      compare(fixture.panel.height, height, "word reveal does not resize the recap")
    }

    function test_smallWindowsAndLargeTextKeepActionsInsideThePanel() {
      for (var size of [[640, 480, 1.3], [400, 600, 1.3], [1200, 800, 1]]) {
        root.width = size[0]
        root.height = size[1]
        root.textScale = size[2]
        root.mixedEligibleCount = 2
        wait(30)
        verify(fixture.panel.height <= root.height - 72)
        for (var button of root.buttons(fixture)) {
          button.forceActiveFocus(Qt.TabFocusReason)
          wait(30)
          var point = button.mapToItem(fixture.scroll, 0, 0)
          verify(point.x >= -1 && point.x + button.width <= fixture.scroll.width + 1, button.label)
          verify(point.y >= -1 && point.y + button.height <= fixture.scroll.height + 1, button.label)
        }
      }
    }
  }
}
