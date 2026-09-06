import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import QtTest

Item {
  id: root
  width: 1920
  height: 1200

  property string appRoot: Qt.resolvedUrl("../..").toString().replace(/\/$/, "")
  property string phase: "settings"
  property string settingsMode: "settings"
  property real textScale: 1
  property var characterIndex: []
  property string characterName: "owl"
  property int characterPick: 1
  property bool speechEnabled: true
  property bool effectsEnabled: true
  property bool audioEnabled: true
  property bool motionReduced: false
  readonly property bool reducedMotion: motionReduced
  property bool autoAdvance: true
  property real speechVolume: 80
  property real effectsVolume: 45
  property real speechRate: 1
  property bool resetJustDone: false
  property bool resetConfirmPending: false
  property int completedCount: 1
  property var course: ({ lessons: new Array(11) })
  property color foreground: "#c0caf5"
  property color background: "#1a1b26"
  property color accent: "#7aa2f7"
  property color instruction: "#e0af68"
  property color urgent: "#f7768e"
  property color muted: "#a0a9c9"
  property color panelColor: background
  property color panelBorder: "#414868"
  property color subtleFill: "#24283b"
  property bool keyboardExclusive: true
  property bool currentStepIsTour: false
  property bool introActive: false
  property string characterState: "hidden"
  property var currentStep: null
  property bool actionRunning: false
  property bool exerciseRunning: false
  property string outcomeAddress: ""
  property int savedCount: 0
  property var fixture

  Item { id: sfxProcess; property bool running: false }
  Item {
    id: overlay
    anchors.fill: parent
    property var highlight: null
  }

  function colorWithAlpha(color, alpha) { return Qt.rgba(color.r, color.g, color.b, alpha) }
  function persistSettings() { savedCount++ }
  function stopAudio() {}
  function toggleAudio() { audioEnabled = !audioEnabled; persistSettings() }
  function closeSettings() { phase = "menu" }
  function chooseCharacter(id) { characterName = id; persistSettings() }
  function requestResetProgress() { resetConfirmPending = true }
  function handleKeyPressed(event) {}
  function updateActiveKeys(event, pressed) {}

  function readSource(path) {
    var xhr = new XMLHttpRequest()
    xhr.open("GET", Qt.resolvedUrl(path), false)
    xhr.send()
    return xhr.responseText
  }

  function descendants(item, predicate) {
    var result = []
    if (predicate(item)) result.push(item)
    for (var child of item.children || [])
      result = result.concat(descendants(child, predicate))
    return result
  }

  function button(label) {
    var matches = descendants(fixture, function(item) { return "label" in item && item.label === label && "clicked" in item })
    return matches.length ? matches[0] : null
  }

  TestCase {
    name: "ProductionSettingsLayout"
    when: windowShown

    function initTestCase() {
      root.characterIndex = JSON.parse(root.readSource("../../assets/characters/index.json")).characters
      var source = root.readSource("../../app/shell.qml")
      verify(source.length > 1000)
      var components = source.slice(source.indexOf("  component UiPanel:"), source.indexOf("  component Keycap:"))
      var start = source.indexOf("        UiPanel {\n          id: characterPanel")
      var panel = source.slice(start, source.indexOf("        UiPanel {\n          id: topicPanel", start))
      start = source.indexOf("        GridLayout {\n          id: controls")
      var controls = source.slice(start, source.indexOf("        UiPanel {\n          id: pausePanel", start))
      verify(panel.length > 1000)
      root.fixture = Qt.createQmlObject(
        "import QtQuick\nimport QtQuick.Layouts\nimport QtQuick.Controls as Controls\n"
        + "Item { width: root.width; height: root.height\n"
        + "property alias panel: characterPanel\nproperty alias header: settingsHeader\n"
        + "property alias footer: settingsFooter\nproperty alias scroll: settingsScroll\n"
        + "property alias controls: controls\n"
        + components + panel + controls + "\n}", overlay)
      wait(100)
    }

    function init() {
      failOnWarning(/.*/)
      root.phase = "settings"
      root.settingsMode = "settings"
      root.textScale = 1
      root.resetConfirmPending = false
      root.currentStepIsTour = false
      overlay.highlight = null
      root.width = 1920
      root.height = 1200
      fixture.scroll.contentY = 0
      wait(100)
    }

    function test_regionsStaySeparated_data() {
      return [
        { tag: "desktop", w: 1920, h: 1200, scale: 1, firstRun: false },
        { tag: "laptop", w: 1280, h: 720, scale: 1, firstRun: false },
        { tag: "large-text", w: 1280, h: 720, scale: 1.3, firstRun: false },
        { tag: "narrow", w: 640, h: 720, scale: 1.3, firstRun: false },
        { tag: "first-run", w: 1280, h: 720, scale: 1, firstRun: true },
        { tag: "first-run-narrow", w: 640, h: 720, scale: 1.3, firstRun: true }
      ]
    }

    function test_regionsStaySeparated(data) {
      root.width = data.w
      root.height = data.h
      root.textScale = data.scale
      root.settingsMode = data.firstRun ? "first-run" : "settings"
      wait(150)
      var panel = fixture.panel
      var header = fixture.header.mapToItem(panel, 0, 0)
      var scroll = fixture.scroll.mapToItem(panel, 0, 0)
      var footer = fixture.footer.mapToItem(panel, 0, 0)
      verify(panel.x >= 0 && panel.y >= 0)
      verify(panel.x + panel.width <= root.width + 1)
      verify(panel.y + panel.height <= root.height + 1)
      verify(scroll.y >= header.y + fixture.header.height + 19)
      verify(footer.y >= scroll.y + fixture.scroll.height + 19)
      verify(footer.y + fixture.footer.height <= panel.height - 23)
      verify(fixture.scroll.height > 100)
      compare(fixture.controls.visible, false)
      var done = root.button(data.firstRun ? "EXIT" : "DONE")
      verify(done !== null && done.visible)
      var donePoint = done.mapToItem(panel, 0, 0)
      verify(donePoint.y >= footer.y)
      verify(donePoint.x + done.width <= panel.width - 23)
      var sliders = root.descendants(fixture, function(item) { return "from" in item && "to" in item && "moved" in item })
      compare(sliders.length, 4)
      for (var slider of sliders) {
        if (!data.firstRun) {
          verify(slider.height >= 32)
          verify(slider.handle.height <= slider.height)
        }
      }
      if (data.firstRun) compare(root.button("SPEECH ON").visible, false)
    }

    function test_footerDoesNotScrollAndDoneWorks() {
      root.height = 720
      wait(100)
      var before = fixture.footer.mapToItem(fixture.panel, 0, 0)
      fixture.scroll.contentY = fixture.scroll.contentHeight - fixture.scroll.height
      wait(50)
      var after = fixture.footer.mapToItem(fixture.panel, 0, 0)
      compare(after.y, before.y)
      mouseClick(root.button("DONE"))
      compare(root.phase, "menu")
    }

    function test_focusedControlsAreRevealed() {
      root.width = 640
      root.height = 720
      root.textScale = 1.3
      wait(150)
      var reset = root.button("RESET PROGRESS")
      reset.forceActiveFocus(Qt.TabFocusReason)
      wait(100)
      var position = reset.mapToItem(fixture.scroll, 0, 0)
      verify(position.y >= -1)
      verify(position.y + reset.height <= fixture.scroll.height + 1)
      verify(fixture.scroll.contentY > 0)
    }

    function test_toolbarStaysCompactWhenChangingSides() {
      root.phase = "waiting"
      root.currentStepIsTour = true
      for (var i = 0; i < 3; i++) {
        overlay.highlight = { anchor: "top-right" }
        wait(50)
        compare(fixture.controls.x, 24)
        compare(fixture.controls.width, fixture.controls.implicitWidth)
        verify(fixture.controls.width < 900)
        overlay.highlight = { anchor: "top-left" }
        wait(50)
        compare(fixture.controls.x, root.width - fixture.controls.width - 24)
        compare(fixture.controls.width, fixture.controls.implicitWidth)
        verify(fixture.controls.width < 900)
      }
    }
  }
}
