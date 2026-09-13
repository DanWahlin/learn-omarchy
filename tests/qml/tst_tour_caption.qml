import QtQuick
import QtTest

Item {
  id: harness
  width: 1200
  height: 800
  property var fixture

  TestCase {
    name: "TourCaptionArrival"
    when: windowShown

    function initTestCase() {
      var xhr = new XMLHttpRequest()
      xhr.open("GET", Qt.resolvedUrl("../../app/shell.qml"), false)
      xhr.send()
      var source = xhr.responseText
      var start = source.indexOf("        Rectangle {\n          id: tourCaption")
      var end = source.indexOf("        IntroPlayer {", start)
      verify(start >= 0 && end > start)
      fixture = Qt.createQmlObject(
        "import QtQuick\nimport QtQuick.Controls as Controls\nimport \"../../app\"\nItem { id: root; width: 1200; height: 800\n"
        + "QtObject { id: appTheme; property var colors: ({}) }\n"
        + "property string phase: 'waiting'\nproperty bool currentStepIsTour: true\n"
        + "property bool introActive: false\nproperty bool reducedMotion: false\nproperty real textScale: 1\n"
        + "property string characterState: 'tour-fly'\nproperty string tourRestingState: 'tour-talk'\n"
        + "property real lessonContentOpacity: 1\nproperty color panelColor: 'black'\n"
        + "property color instruction: 'white'\nproperty var currentStep: ({instruction: 'Welcome'})\n"
        + "function characterText(text) { return text }\nfunction colorWithAlpha(color, alpha) { return color }\n"
        + "property int revealEnd: -1\nfunction lessonRevealEnd(message) { return revealEnd }\n"
        + source.match(/^  function captionText\([^\n]*\) \{[\s\S]*?^  \}/m)[0] + "\n"
        + "property alias captionTextItem: tourCaptionText\n"
        + "property var lineWidths: []\n"
        + "FontMetrics { id: captionMetrics; font: tourCaptionText.font }\n"
        + "function textWidth(text) { return captionMetrics.advanceWidth(text) }\n"
        + "Connections { target: tourCaptionText; function onLineLaidOut(line) {\n"
        + "if (line.number === 0) root.lineWidths = []; root.lineWidths.push(line.implicitWidth)\n} }\n"
        + "property alias caption: tourCaption\nproperty alias movingX: coachTravelX.running\n"
        + "property alias movingY: coachTravelY.running\n"
        + "property alias dragging: characterMouse.pressed\nproperty alias falling: fallAnimation.running\n"
        + "Item { id: overlay; width: root.width; height: root.height }\n"
        + "Item { id: hexonCoach; width: 224; height: 192; property real arcOffset: 0 }\n"
        + "QtObject { id: coachTravelX; property bool running: false }\n"
        + "QtObject { id: coachTravelY; property bool running: false }\n"
        + "QtObject { id: characterMouse; property bool pressed: false }\n"
        + "QtObject { id: fallAnimation; property bool running: false }\n"
        + source.slice(start, end) + "\n}", harness)
    }

    function init() {
      failOnWarning(/.*/)
      fixture.reducedMotion = true
      fixture.phase = "waiting"
      fixture.currentStep = {instruction: "Welcome to the desktop. Follow the highlighted bar."}
      fixture.characterState = "tour-fly"
      fixture.introActive = false
      fixture.movingX = false
      fixture.movingY = false
      fixture.dragging = false
      fixture.falling = false
      fixture.revealEnd = -1
      fixture.lessonContentOpacity = 1
      fixture.width = 1200
      fixture.height = 800
      fixture.textScale = 1
      wait(10)
      compare(fixture.caption.opacity, 0)
      fixture.reducedMotion = false
    }

    function test_hiddenDuringIntroFlightAndSettling() {
      for (var state of ["intro", "tour-fly", "tour-settle"]) {
        fixture.characterState = state
        wait(20)
        compare(fixture.caption.opacity, 0)
        verify(!fixture.caption.visible)
      }
    }

    function test_waitsForBothAxesThenFadesIn() {
      fixture.movingX = true
      fixture.movingY = true
      fixture.characterState = "tour-talk"
      wait(30)
      compare(fixture.caption.opacity, 0)
      fixture.movingX = false
      wait(30)
      compare(fixture.caption.opacity, 0)
      fixture.movingY = false
      wait(80)
      verify(fixture.caption.opacity > 0 && fixture.caption.opacity < 1)
      tryCompare(fixture.caption, "opacity", 1)
      fixture.characterState = "tour-fly"
      tryCompare(fixture.caption, "opacity", 0, 50)
    }

    function test_reducedMotionShowsRestingCaptionImmediately() {
      fixture.reducedMotion = true
      fixture.tourRestingState = "tour-point"
      fixture.characterState = "tour-point"
      tryCompare(fixture.caption, "opacity", 1, 50)
      compare(fixture.caption.y, 192 + 16)
      fixture.introActive = true
      tryCompare(fixture.caption, "opacity", 0, 50)
      fixture.tourRestingState = "tour-talk"
    }

    function test_repositioningDoesNotInterruptAnArrivedCaption() {
      fixture.revealEnd = 7
      fixture.characterState = "tour-talk"
      tryCompare(fixture.caption, "opacity", 1)
      var height = fixture.caption.height
      for (var end of [14, 21, 28]) {
        fixture.movingX = true
        fixture.movingY = true
        fixture.revealEnd = end
        wait(30)
        compare(fixture.caption.opacity, 1, "A geometry refresh must not hide narration already being read")
        verify(fixture.caption.ready)
        compare(fixture.caption.height, height)
        compare(fixture.revealEnd, end)
        fixture.movingX = false
        fixture.movingY = false
        wait(30)
        compare(fixture.caption.opacity, 1)
      }
      fixture.movingX = true
      fixture.currentStep = {instruction: "A different tour step."}
      tryCompare(fixture.caption, "opacity", 0, 50)
      fixture.movingX = false
      tryCompare(fixture.caption, "opacity", 1)
      fixture.dragging = true
      tryCompare(fixture.caption, "opacity", 0, 50)
      fixture.falling = true
      fixture.dragging = false
      compare(fixture.caption.opacity, 0)
      fixture.falling = false
      tryCompare(fixture.caption, "opacity", 1)
      fixture.phase = "menu"
      tryCompare(fixture.caption, "opacity", 0, 50)
    }

    function test_captionUsesReadableWidthAlignmentAndTextScale() {
      fixture.currentStep = {instruction:"Follow the highlighted desktop bar. These controls help you navigate your workspace."}
      fixture.characterState = "tour-talk"
      tryCompare(fixture.caption, "opacity", 1)
      compare(fixture.caption.width, 880)
      compare(fixture.captionTextItem.horizontalAlignment, Text.AlignLeft)
      fixture.width = 640
      fixture.height = 480
      fixture.textScale = 1.3
      wait(30)
      compare(fixture.captionTextItem.font.pixelSize, 27)
      verify(fixture.caption.x >= 0 && fixture.caption.y >= 0)
      verify(fixture.caption.x + fixture.caption.width <= fixture.width)
      verify(fixture.caption.y + fixture.caption.height <= fixture.height)
    }

    function test_lastTwoWordsStayTogetherAcrossWidthsAndTextSizes() {
      var instruction = "You can also click this icon in the desktop bar to open the same menu, with apps, settings, and other resources. Use whichever way is more convenient."
      fixture.currentStep = {instruction: instruction}
      fixture.characterState = "tour-talk"
      for (var size of [[1200, 1], [640, 1], [640, 1.3], [360, 1.3]]) {
        fixture.width = size[0]
        fixture.textScale = size[1]
        wait(30)
        var textItem = fixture.captionTextItem
        compare(textItem.text.replace(/\s+/g, " "), instruction)
        verify(fixture.lineWidths.length > 0)
        verify(fixture.lineWidths[fixture.lineWidths.length - 1] >= fixture.textWidth("more\u00a0convenient.") - 1,
          "The final rendered line must contain at least the final two words.")
        verify(textItem.contentWidth <= textItem.width)
      }
      compare(fixture.captionText("First paragraph ends here.\n\nSecond paragraph stays together."),
        "First paragraph ends\u00a0here.\n\nSecond paragraph stays\u00a0together.")
    }
  }
}
