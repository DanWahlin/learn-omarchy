import QtQuick
import QtTest

Item {
  id: harness
  width: 1200
  height: 800
  property var fixture

  TestCase {
    name: "WelcomeCaptionArrival"
    when: windowShown

    function initTestCase() {
      var xhr = new XMLHttpRequest()
      xhr.open("GET", Qt.resolvedUrl("../../app/shell.qml"), false)
      xhr.send()
      var source = xhr.responseText
      var start = source.indexOf("        Rectangle {\n          id: welcomeCaption")
      var end = source.indexOf("        Rectangle {\n          id: tourCaption", start)
      verify(start >= 0 && end > start)
      fixture = Qt.createQmlObject(
        "import QtQuick\nimport QtQuick.Controls as Controls\nimport \"../../app\"\nItem { id: root; width: 1200; height: 800\n"
        + "QtObject { id: appTheme; property var colors: ({}) }\n"
        + "property string phase: 'welcome'\nproperty string welcomeStage: 'center-flight'\n"
        + "property bool reducedMotion: false\nproperty real textScale: 1\n"
        + "property string characterState: 'tour-fly'\nproperty color panelColor: 'black'\n"
        + "property color instruction: 'white'\nproperty string welcomeText: 'Hi! Welcome to Omarchy.'\n"
        + "property int readingStarts: 0\nproperty bool reading: false\n"
        + "function welcomeCaptionShown() { readingStarts++; reading = true }\n"
        + "function colorWithAlpha(color, alpha) { return color }\n"
        + source.match(/^  function captionText\([^\n]*\) \{[\s\S]*?^  \}/m)[0] + "\n"
        + "property alias captionTextItem: welcomeCaptionText\n"
        + "property alias caption: welcomeCaption\nproperty alias movingX: coachTravelX.running\n"
        + "property alias movingY: coachTravelY.running\nproperty alias dragging: characterMouse.pressed\n"
        + "property alias falling: fallAnimation.running\nproperty alias menuSlot: welcomeMenuSlot\n"
        + "Item { id: overlay; width: root.width; height: root.height; property bool shouldShow: true }\n"
        + "Item { id: hexonWindow; property Item contentItem: overlay }\n"
        + "Item { id: welcomeMenuSlot; x: 300; y: 120; width: 600; height: 160 }\n"
        + "Item { id: hexonCoach; x: 488; y: 260; width: 224; height: 192 }\n"
        + "QtObject { id: coachTravelX; property bool running: false }\n"
        + "QtObject { id: coachTravelY; property bool running: false }\n"
        + "QtObject { id: characterMouse; property bool pressed: false }\n"
        + "QtObject { id: fallAnimation; property bool running: false }\n"
        + "QtObject { id: welcomeReadTimer; function stop() { root.reading = false } }\n"
        + source.slice(start, end) + "\n}", harness)
    }

    function init() {
      failOnWarning(/.*/)
      fixture.reducedMotion = true
      fixture.phase = "welcome"
      fixture.welcomeStage = "center-flight"
      fixture.characterState = "tour-fly"
      fixture.movingX = false
      fixture.movingY = false
      fixture.dragging = false
      fixture.falling = false
      fixture.readingStarts = 0
      fixture.reading = false
      fixture.width = 1200
      fixture.height = 800
      fixture.textScale = 1
      wait(10)
      compare(fixture.caption.opacity, 0)
      fixture.reducedMotion = false
    }

    function test_bothMessagesWaitForBothAxesThenFadeIn() {
      for (var stage of ["welcome", "recommendation"]) {
        fixture.movingX = true
        fixture.movingY = true
        fixture.phase = stage === "welcome" ? "welcome" : "menu"
        fixture.welcomeStage = stage
        fixture.characterState = stage === "welcome" ? "tour-talk" : "menu-point"
        wait(20)
        compare(fixture.caption.opacity, 0)
        verify(!fixture.reading)
        fixture.movingX = false
        wait(20)
        compare(fixture.caption.opacity, 0)
        fixture.movingY = false
        wait(80)
        verify(fixture.caption.opacity > 0 && fixture.caption.opacity < 1)
        verify(fixture.reading)
        tryCompare(fixture.caption, "opacity", 1)
      }
      compare(fixture.caption.parent, fixture.menuSlot)
      compare(fixture.caption.width, fixture.menuSlot.width)
      verify(fixture.caption.height <= fixture.menuSlot.height)
    }

    function test_motionDragAndCancellationHideImmediatelyAndStopReading() {
      fixture.welcomeStage = "welcome"
      fixture.characterState = "tour-talk"
      tryCompare(fixture.caption, "opacity", 1)
      for (var property of ["movingX", "movingY", "dragging", "falling"]) {
        fixture[property] = true
        tryCompare(fixture.caption, "opacity", 0, 50)
        verify(!fixture.reading)
        fixture[property] = false
        tryCompare(fixture.caption, "opacity", 1)
      }
      fixture.phase = "settings"
      tryCompare(fixture.caption, "opacity", 0, 50)
      verify(!fixture.reading)
    }

    function test_reducedMotionStillWaitsForRestThenShowsImmediately() {
      fixture.reducedMotion = true
      fixture.welcomeStage = "welcome"
      wait(20)
      compare(fixture.caption.opacity, 0)
      fixture.characterState = "tour-talk"
      tryCompare(fixture.caption, "opacity", 1, 50)
      compare(fixture.readingStarts, 1)
      compare(fixture.caption.y, 260 + 192 + 16)
    }

    function test_longWelcomeIsWiderLeftAlignedAndSplitIntoParagraphs() {
      var xhr = new XMLHttpRequest()
      xhr.open("GET", Qt.resolvedUrl("../../courses/welcome.json"), false)
      xhr.send()
      fixture.welcomeText = JSON.parse(xhr.responseText).instruction.replace("HEXON", "Ohm-1")
      fixture.welcomeStage = "welcome"
      fixture.characterState = "tour-talk"
      tryCompare(fixture.caption, "opacity", 1)
      compare(fixture.caption.width, 920)
      compare(fixture.captionTextItem.horizontalAlignment, Text.AlignLeft)
      verify(fixture.captionTextItem.text.indexOf("\n\n") > 0)
      compare(fixture.captionTextItem.text.replace(/\s+/g, " "), fixture.welcomeText)
      fixture.width = 640
      fixture.height = 480
      fixture.textScale = 1.3
      wait(50)
      verify(fixture.caption.x >= 0 && fixture.caption.y >= 0)
      verify(fixture.caption.x + fixture.caption.width <= fixture.width)
      verify(fixture.caption.y + fixture.caption.height <= fixture.height)
      verify(fixture.captionTextItem.width <= fixture.caption.width - 40)
    }
  }
}
