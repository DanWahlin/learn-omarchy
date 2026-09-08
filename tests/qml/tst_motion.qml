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
      start = source.indexOf("          Timer {\n            interval: 32")
      var arrival = source.slice(start, source.indexOf("          Behavior on presentationScale", start))
      verify(timing !== null && update !== null && behaviors.length > 0)
      harness.fixture = Qt.createQmlObject(
        "import QtQuick\nItem { id: root; width: 2000; height: 1200\n"
        + "property bool reducedMotion: false\nproperty bool introDeparting: false\n"
        + "property string characterState: 'tour-fly'\nproperty int characterTravelDuration: 900\n"
        + "property string welcomeStage: ''\nproperty int introGeneration: 0\nproperty int arrivals: 0\n"
        + "function welcomeArrived(generation) { arrivals++; welcomeStage = 'welcome' }\n"
        + "Item { id: overlay; property bool shouldShow: true }\n"
        + "Item { id: introPlayer; property bool handoffPinned: false }\n"
        + "property alias coach: hexonCoach\n"
        + timing[0]
        + "\nItem { id: characterMouse; property bool pressed: false }\n"
        + "Item { id: fallAnimation; property bool running: false }\n"
        + "Item { id: hexonCoach; width: 100; height: 100\n"
        + "property real contextX: 0\nproperty real contextY: 0\n"
        + "property bool userPlaced: false\nproperty real userX: 0\nproperty real userY: 0\n"
        + "property bool isFlying: true\nproperty bool uprightFlight: true\nproperty bool targetsIntro: false\nproperty real flightBank: 0\n"
        + "x: userPlaced ? userX : contextX; y: userPlaced ? userY : contextY\n"
        + update[0] + "\n" + behaviors + "\n" + arrival + "\n} }", harness)
    }

    function init() {
      failOnWarning(/.*/)
      fixture.reducedMotion = true
      fixture.coach.userPlaced = false
      fixture.coach.contextX = 0
      fixture.coach.contextY = 0
      fixture.introDeparting = false
      fixture.coach.targetsIntro = false
      fixture.welcomeStage = ""
      fixture.arrivals = 0
      wait(20)
      fixture.reducedMotion = false
    }

    function test_firstAscentUsesItsOwnTimingBeforeMotionStarts() {
      fixture.introDeparting = true
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

    function test_welcomeArrivalWaitsForActualTravelOnBothAxes() {
      for (var stage of ["center-flight", "menu-flight"]) {
        fixture.welcomeStage = stage
        fixture.coach.contextX += 900
        fixture.coach.contextY += 300
        var previous = fixture.arrivals
        wait(250)
        compare(fixture.arrivals, previous)
        tryCompare(fixture, "arrivals", previous + 1, 1800)
        compare(fixture.coach.x, fixture.coach.contextX)
        compare(fixture.coach.y, fixture.coach.contextY)
      }
    }

    function test_reducedWelcomeArrivesWithoutAFlightDelay() {
      fixture.reducedMotion = true
      fixture.welcomeStage = "center-flight"
      fixture.coach.contextX = 700
      fixture.coach.contextY = 300
      tryCompare(fixture, "arrivals", 1, 100)
    }

    function test_introPlayerCoordinatesAreNotInterpolatedTwice() {
      fixture.coach.targetsIntro = true
      fixture.coach.contextX = 400
      fixture.coach.contextY = 700
      compare(fixture.coach.x, 400)
      compare(fixture.coach.y, 700)
    }

    function test_introHandoffPinsLastPositionThenUsesSlowerTourFlight() {
      fixture.coach.targetsIntro = true
      fixture.coach.contextX = 300
      fixture.coach.contextY = 700
      fixture.coach.userX = fixture.coach.x
      fixture.coach.userY = fixture.coach.y
      fixture.coach.userPlaced = true
      fixture.introDeparting = true
      fixture.coach.targetsIntro = false
      fixture.coach.contextX = 900
      fixture.coach.contextY = 300
      wait(20)
      compare(fixture.coach.x, 300)
      compare(fixture.coach.y, 700)
      fixture.coach.userPlaced = false
      compare(fixture.characterTravelDuration, fixture.travelDurationForDistance(Math.sqrt(600 * 600 + 400 * 400), true))
      wait(250)
      verify(fixture.coach.x > 300 && fixture.coach.x < 900)
      verify(fixture.coach.y < 700 && fixture.coach.y > 300)
      tryCompare(fixture.coach, "x", 900, 1300)
      tryCompare(fixture.coach, "y", 300, 1300)
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
