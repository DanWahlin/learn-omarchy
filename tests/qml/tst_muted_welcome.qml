import QtQuick
import QtTest

Item {
  id: harness
  property var fixture
  TestCase {
    name: "MutedWelcomeReadingClock"
    when: windowShown
    function initTestCase() {
      var xhr = new XMLHttpRequest()
      xhr.open("GET", Qt.resolvedUrl("../../app/shell.qml"), false)
      xhr.send()
      var source = xhr.responseText
      var start = source.indexOf("  Timer {\n    id: welcomeReadingClock")
      var end = source.indexOf("\n  function resetWelcomeReading()", start)
      verify(start >= 0 && end > start)
      fixture = Qt.createQmlObject("import QtQuick\nItem { id: root\n"
        + "property bool welcomeReadingActive: false\nproperty bool narrationEnabled: false\n"
        + "property bool synchronizedWelcomeText: true\nproperty bool reducedMotion: false\n"
        + "property real welcomeReadingElapsed: 0\n" + source.slice(start, end) + "\n}", harness)
    }
    function test_clockOnlyAdvancesForVisibleMutedAnimatedReading() {
      fixture.welcomeReadingActive = true
      tryVerify(function() { return fixture.welcomeReadingElapsed >= 100 })
      for (var field of ["narrationEnabled", "reducedMotion"]) {
        fixture[field] = true
        var stopped = fixture.welcomeReadingElapsed
        wait(120)
        compare(fixture.welcomeReadingElapsed, stopped)
        fixture[field] = false
        tryVerify(function() { return fixture.welcomeReadingElapsed > stopped })
      }
      fixture.synchronizedWelcomeText = false
      var fullText = fixture.welcomeReadingElapsed
      wait(120)
      compare(fixture.welcomeReadingElapsed, fullText)
      fixture.synchronizedWelcomeText = true
      fixture.welcomeReadingActive = false
      var hidden = fixture.welcomeReadingElapsed
      wait(120)
      compare(fixture.welcomeReadingElapsed, hidden)
    }
  }
}
