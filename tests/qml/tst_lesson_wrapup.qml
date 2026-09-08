import QtQuick
import QtTest

Item {
  id: harness
  width: 900
  height: 700
  property var fixture
  TestCase {
    name: "LessonWrapupArrival"
    when: windowShown
    function initTestCase() {
      var xhr = new XMLHttpRequest()
      xhr.open("GET", Qt.resolvedUrl("../../app/shell.qml"), false)
      xhr.send()
      var source = xhr.responseText
      var start = source.indexOf("          readonly property bool narrationReady:")
      var end = source.indexOf("          opacity:", start)
      verify(start >= 0 && end > start)
      fixture = Qt.createQmlObject("import QtQuick\nItem { id: root; width: 900; height: 700\n"
        + "property string phase: 'lesson-complete'\nproperty var currentLesson: ({})\n"
        + "property real lessonContentOpacity: 1\nproperty string characterState: 'module-fly'\n"
        + "property bool lessonTransitionRunning: false\nproperty bool lessonWrapupReady: false\n"
        + "property int starts: 0\nfunction playLessonWrapup() { starts++ }\n"
        + source.match(/^  onLessonWrapupReadyChanged:.*$/m)[0] + "\n"
        + "property alias movingX: coachTravelX.running\nproperty alias movingY: coachTravelY.running\n"
        + "property alias activeScreen: overlay.shouldShow\n"
        + "QtObject { id: overlay; property bool shouldShow: true }\n"
        + "QtObject { id: coachTravelX; property bool running: false }\n"
        + "QtObject { id: coachTravelY; property bool running: false }\n"
        + "Item { id: completionPanel\n" + source.slice(start, end) + "\n} }", harness)
    }
    function init() {
      failOnWarning(/.*/)
      fixture.characterState = "module-fly"
      fixture.phase = "lesson-complete"
      fixture.lessonContentOpacity = 1
      fixture.lessonTransitionRunning = false
      fixture.movingX = false
      fixture.movingY = false
      fixture.activeScreen = true
      fixture.starts = 0
      wait(10)
    }
    function test_waitsForBothAxesAndPanelFade() {
      fixture.movingX = true
      fixture.movingY = true
      fixture.characterState = "celebrate"
      fixture.movingX = false
      wait(10)
      compare(fixture.starts, 0)
      fixture.lessonContentOpacity = 0.5
      fixture.movingY = false
      wait(10)
      compare(fixture.starts, 0)
      fixture.lessonContentOpacity = 1
      tryCompare(fixture, "starts", 1)
      fixture.phase = "menu"
      verify(!fixture.lessonWrapupReady)
    }
    function test_inactiveDisplayCannotStartNarration() {
      fixture.activeScreen = false
      fixture.characterState = "celebrate"
      wait(10)
      compare(fixture.starts, 0)
      fixture.activeScreen = true
      tryCompare(fixture, "starts", 1)
    }
    function test_outgoingTransitionCannotRestartSpeech() {
      fixture.lessonTransitionRunning = true
      fixture.characterState = "celebrate"
      wait(10)
      compare(fixture.starts, 0)
      fixture.lessonTransitionRunning = false
      tryCompare(fixture, "starts", 1)
    }
  }
}
