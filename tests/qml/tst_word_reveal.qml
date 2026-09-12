import QtQuick
import QtTest
import "../../app" as App

Item {
  width: 960
  height: 700
  Text {
    id: reference
    width: 600
    text: "Hi! I'm Ohm-1, but you can call me Ohm for short.\n\nSpend less time managing your desktop and operating system. Your desktop - your\u00a0way."
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    font.pixelSize: 21
    lineHeight: 1.2
  }
  App.WordRevealText {
    id: reveal
    width: reference.width
    fullText: reference.text
    font: reference.font
    color: "black"
    y: 300
  }
  TestCase {
    name: "WordRevealLayout"
    when: windowShown
    function test_revealStaysWithinTheFullCaptionLayout() {
      failOnWarning(/.*/)
      reference.text = "Hi! I'm Ohm-1, but you can call me Ohm for short.\n\nSpend less time managing your desktop and operating system. Your desktop - your\u00a0way."
      for (var size of [320, 600, 880]) {
        reference.width = size
        for (var end of [-1, 0, 3, 18, 61, 95, reference.text.length]) {
          reveal.revealEnd = end
          wait(10)
          verify(reveal.implicitHeight <= reference.implicitHeight + 1)
          if (end < 0 || end >= reference.text.length) {
            verify(Math.abs(reveal.implicitHeight - reference.implicitHeight) < 1)
            verify(Math.abs(reveal.contentWidth - reference.contentWidth) < 1)
          }
          compare(reveal.Accessible.name, reference.text)
        }
      }
    }
    function test_visibleTextFollowsTheWordClockWithoutRestartingTheFade() {
      reference.text = "Hello world"
      reference.width = 600
      reveal.revealEnd = 0
      tryCompare(reveal, "opacity", 1)
      var hidden = grabImage(reveal)
      reveal.revealEnd = 3
      wait(20)
      compare(reveal.opacity, 1, "word-clock updates must not restart the fade")
      var firstWord = grabImage(reveal)
      verify(!hidden.equals(firstWord), "the first timed word must become visible")
      reveal.revealEnd = -1
      wait(20)
      verify(!firstWord.equals(grabImage(reveal)), "timing completion reveals the remaining caption")
    }
    function test_reducedMotionAndPlainText() {
      reveal.reducedMotion = true
      reference.text = "Read <this> & that.\n\nKeep every line."
      compare(reveal.opacity, 1)
      verify(reveal.text.indexOf("&lt;this&gt;") >= 0)
      compare(reveal.textFormat, Text.StyledText)
      compare(reveal.Accessible.name, reference.text)
      reveal.reducedMotion = false
    }
  }
}
