import QtQuick
import QtTest

Item {
  id: harness
  width: 2000
  height: 1200
  property var fixture

  TestCase {
    name: "CharacterFlightTiming"
    when: windowShown

    function initTestCase() {
      var xhr = new XMLHttpRequest()
      xhr.open("GET", Qt.resolvedUrl("../../app/shell.qml"), false)
      xhr.send()
      var source = xhr.responseText
      var timing = source.match(/^  function travelDurationForDistance\([^\n]*\) \{[\s\S]*?^  \}/m)
      var update = source.match(/^          function updateTravelDuration\([^\n]*\) \{[\s\S]*?^          \}/m)
      var start = source.indexOf("          Behavior on x {")
      var behaviors = source.slice(start, source.indexOf("          Connections {", start))
      verify(timing !== null && update !== null && behaviors.length > 0)
      harness.fixture = Qt.createQmlObject(
        "import QtQuick\nItem { id: root; width: 2000; height: 1200\n"
        + "property bool reducedMotion: false\nproperty bool introActive: false\n"
        + "property string characterState: 'tour-fly'\nproperty int characterTravelDuration: 900\n"
        + "property alias coach: hexonCoach\n"
        + timing[0]
        + "\nItem { id: characterMouse; property bool pressed: false }\n"
        + "Item { id: fallAnimation; property bool running: false }\n"
        + "Item { id: hexonCoach; width: 100; height: 100\n"
        + "property real contextX: 0\nproperty real contextY: 0\n"
        + "property bool isFlying: true\nproperty bool uprightFlight: true\nproperty real flightBank: 0\n"
        + "x: contextX; y: contextY\n"
        + update[0] + "\n" + behaviors + "\n} }", harness)
    }

    function init() {
      failOnWarning(/.*/)
      fixture.reducedMotion = true
      fixture.coach.contextX = 0
      fixture.coach.contextY = 0
      fixture.introActive = false
      wait(20)
      fixture.reducedMotion = false
    }

    function test_firstAscentUsesItsOwnTimingBeforeMotionStarts() {
      fixture.introActive = true
      fixture.coach.contextY = 1000
      compare(fixture.characterTravelDuration, 1350)
      compare(fixture.coach.flightBank, 0)
      wait(750)
      verify(fixture.coach.y > 0 && fixture.coach.y < 950)
      tryCompare(fixture.coach, "y", 1000, 1000)
    }

    function test_nextTripDoesNotReuseThePreviousDuration() {
      fixture.coach.contextX = 1000
      compare(fixture.characterTravelDuration, 1150)
      tryCompare(fixture.coach, "x", 1000, 1600)
      fixture.coach.contextX = 1500
      compare(fixture.characterTravelDuration, 575)
      tryCompare(fixture.coach, "x", 1500, 900)
    }

    function test_reducedMotionStillMovesImmediately() {
      fixture.reducedMotion = true
      fixture.coach.contextY = 1000
      compare(fixture.coach.y, 1000)
      compare(fixture.characterTravelDuration, 0)
      compare(fixture.coach.flightBank, 0)
    }

    function test_bankFollowsTravelAndLevelsOnArrival() {
      fixture.coach.contextX = 500
      compare(fixture.coach.flightBank, 8)
      tryCompare(fixture.coach, "x", 500, 1000)
      fixture.coach.updateTravelDuration()
      compare(fixture.coach.flightBank, 0)
      fixture.coach.contextX = 0
      compare(fixture.coach.flightBank, -8)
      tryCompare(fixture.coach, "x", 0, 1000)
    }
  }
}
