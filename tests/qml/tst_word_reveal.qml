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
    function test_revealKeepsFullTextWrappingAndHeight() {
      failOnWarning(/.*/)
      reference.text = "Hi! I'm Ohm-1, but you can call me Ohm for short.\n\nSpend less time managing your desktop and operating system. Your desktop - your\u00a0way."
      for (var size of [320, 600, 880]) {
        reference.width = size
        for (var end of [-1, 0, 3, 18, 61, 95, reference.text.length]) {
          reveal.revealEnd = end
          wait(10)
          compare(reveal.lineCount, reference.lineCount)
          compare(reveal.implicitHeight, reference.implicitHeight)
          verify(Math.abs(reveal.contentWidth - reference.contentWidth) < 1)
          compare(reveal.Accessible.name, reference.text)
        }
      }
    }
    function test_invisibleSuffixActuallyDisappears() {
      reference.text = "Hello world"
      reference.width = 600
      reveal.revealEnd = 0
      wait(20)
      var hidden = grabImage(reveal)
      reveal.revealEnd = -1
      wait(20)
      var full = grabImage(reveal)
      var changed = 0
      for (var y = 0; y < Math.min(reveal.height, 30); y++)
        for (var x = 0; x < 120; x++)
          if (hidden.pixel(x, y) !== full.pixel(x, y)) changed++
      verify(changed > 20, "transparent styling must hide the unrevealed words")
    }
  }
}
