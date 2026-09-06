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
        "import QtQuick\nItem { id: root; width: 1200; height: 800\n"
        + "property string phase: 'waiting'\nproperty bool currentStepIsTour: true\n"
        + "property bool introActive: false\nproperty bool reducedMotion: false\n"
        + "property string characterState: 'tour-fly'\nproperty string tourRestingState: 'tour-talk'\n"
        + "property real lessonContentOpacity: 1\nproperty color panelColor: 'black'\n"
        + "property color instruction: 'white'\nproperty var currentStep: ({instruction: 'Welcome'})\n"
        + "function characterText(text) { return text }\nfunction colorWithAlpha(color, alpha) { return color }\n"
        + "property alias caption: tourCaption\nproperty alias movingX: coachTravelX.running\n"
        + "property alias movingY: coachTravelY.running\n"
        + "Item { id: overlay; width: 1200; height: 800 }\n"
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
      fixture.characterState = "tour-fly"
      fixture.introActive = false
      fixture.movingX = false
      fixture.movingY = false
      fixture.lessonContentOpacity = 1
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
      fixture.introActive = true
      tryCompare(fixture.caption, "opacity", 0, 50)
      fixture.tourRestingState = "tour-talk"
    }
  }
}
