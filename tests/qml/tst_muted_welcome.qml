import QtQuick
import QtTest
import "../../app" as App

Item {
  App.CaptionReveal {
    id: fixture
    sourceText: "Welcome to the desktop. These words reveal at reading speed."
    narrationEnabled: false
  }
  TestCase {
    name: "MutedCaptionReadingClock"
    when: windowShown
    function test_clockOnlyAdvancesForVisibleMutedAnimatedReading() {
      failOnWarning(/.*/)
      fixture.active = true
      tryVerify(function() { return fixture.readingElapsed >= 100 })
      for (var field of ["narrationEnabled", "reducedMotion", "paused"]) {
        fixture[field] = true
        var stopped = fixture.readingElapsed
        wait(120)
        compare(fixture.readingElapsed, stopped)
        fixture[field] = false
        tryVerify(function() { return fixture.readingElapsed > stopped })
      }
      fixture.typeText = false
      var fullText = fixture.readingElapsed
      wait(120)
      compare(fixture.readingElapsed, fullText)
      fixture.typeText = true
      fixture.active = false
      var hidden = fixture.readingElapsed
      wait(120)
      compare(fixture.readingElapsed, hidden)
    }
  }
}
