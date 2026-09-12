import QtQuick
import QtTest
import "../../app" as App

Item {
  width: 800
  height: 600
  App.CaptionReveal {
    id: caption
    sourceText: "One two three four."
    audioAvailable: true
  }
  TestCase {
    name: "NarratedCaptionState"
    when: windowShown
    function init() {
      failOnWarning(/.*/)
      caption.narrationEnabled = true
      caption.active = true
      caption.paused = false
      caption.typeText = true
      caption.reducedMotion = false
      caption.audioAvailable = true
      caption.sourceText = "One two three four."
      caption.displayText = Qt.binding(function() { return caption.sourceText })
      caption.formattedText = Qt.binding(function() { return caption.displayText })
      caption.deadlineMs = 3000
      caption.reset()
    }
    function timing(token, text) {
      caption.receive(JSON.stringify({ type: "timing", text: text || caption.sourceText,
        words: [{ startMs: 100, endOffset: 3 }, { startMs: 400, endOffset: 7 },
          { startMs: 700, endOffset: 13 }, { startMs: 1000, endOffset: 19 }] }), token)
    }
    function position(token, ms) {
      caption.receive(JSON.stringify({ type: "position", positionMs: ms }), token)
    }
    function test_everyCaptionStageTracksMedia_data() {
      return ["welcome", "instruction", "completion", "wrapup"].map(function(stage) { return { tag: stage } })
    }
    function test_everyCaptionStageTracksMedia(data) {
      caption.sourceKey = data.tag
      compare(caption.revealEnd, 0, "pending playback cannot flash complete text")
      var token = caption.beginPlayback()
      timing(token)
      wait(100)
      compare(caption.revealEnd, 0, "wall clock does not advance voiced captions")
      position(token, 100)
      compare(caption.revealEnd, 3)
      caption.paused = true
      position(token, 700)
      wait(120)
      compare(caption.revealEnd, 3)
      caption.paused = false
      position(token, 700)
      compare(caption.revealEnd, 13)
      position(token, 400)
      compare(caption.revealEnd, 7, "actual backwards seek is respected")
      caption.finish(token, 0)
      compare(caption.revealEnd, -1)
    }
    function test_mutedReadingSurvivesVisibilityPauseAndFormatting() {
      caption.narrationEnabled = false
      compare(caption.revealEnd, 3)
      tryVerify(function() { return caption.revealEnd >= 7 })
      var elapsed = caption.readingElapsed
      caption.active = false
      wait(180)
      compare(caption.readingElapsed, elapsed)
      caption.formattedText = "One two\n\nthree four."
      compare(caption.readingElapsed, elapsed)
      caption.active = true
      caption.paused = true
      wait(180)
      compare(caption.readingElapsed, elapsed)
      caption.paused = false
      tryVerify(function() { return caption.readingElapsed > elapsed })
      caption.sourceKey = "new-step"
      compare(caption.readingElapsed, 0)
      compare(caption.revealEnd, 3)
    }
    function test_muteContinuesVisiblePrefixAndUnmuteReplayRestarts() {
      var token = caption.beginPlayback()
      timing(token)
      position(token, 700)
      compare(caption.revealEnd, 13)
      caption.narrationEnabled = false
      caption.cancel()
      verify(caption.revealEnd >= 13)
      caption.narrationEnabled = true
      var replay = caption.beginPlayback()
      compare(caption.revealEnd, 0)
      timing(token)
      position(token, 1000)
      compare(caption.revealEnd, 0, "old clip cannot affect a replay")
      timing(replay)
      position(replay, 100)
      compare(caption.revealEnd, 3)
    }
    function test_sourceChangeRejectsStaleTimingAndCompletion() {
      var token = caption.beginPlayback()
      caption.sourceText = "A different completion message."
      timing(token)
      position(token, 700)
      caption.finish(token, 0)
      compare(caption.revealEnd, 0)
      verify(!caption.finished)
      var next = caption.beginPlayback()
      ignoreWarning(/learn-omarchy: caption timing unavailable.*/)
      timing(next, "One two three four.")
      verify(caption.revealEnd >= 0)
    }
    function test_mismatchAndFallbackLatch() {
      var token = caption.beginPlayback()
      caption.displayText = "Try new words here."
      ignoreWarning(/learn-omarchy: caption timing unavailable.*/)
      timing(token)
      verify(caption.failed)
      var fallbackEnd = caption.revealEnd
      verify(fallbackEnd >= 0 && fallbackEnd < caption.formattedText.length)
      caption.displayText = caption.sourceText
      timing(token)
      position(token, 100)
      verify(caption.revealEnd >= fallbackEnd)
    }
    function test_deadlineNeedsBothTimingAndPosition() {
      caption.deadlineMs = 80
      var token = caption.beginPlayback()
      position(token, 100)
      ignoreWarning(/learn-omarchy: caption timing unavailable.*/)
      tryCompare(caption, "failed", true)
      verify(caption.revealEnd >= 0 && caption.revealEnd < caption.formattedText.length)
      verify(caption.playing, "deadline never ends speech or advances a lesson")
    }
    function test_pausingPendingPlaybackAlsoPausesTheDeadline() {
      caption.deadlineMs = 80
      var token = caption.beginPlayback()
      caption.paused = true
      wait(160)
      verify(!caption.failed)
      compare(caption.revealEnd, 0)
      caption.paused = false
      timing(token)
      position(token, 100)
      wait(160)
      verify(!caption.failed)
      compare(caption.revealEnd, 3)
    }
    function test_settingsAndUnsupportedVoice() {
      var token = caption.beginPlayback()
      timing(token)
      position(token, 400)
      for (var field of ["reducedMotion", "typeText"]) {
        caption[field] = field === "reducedMotion"
        compare(caption.revealEnd, -1)
        caption[field] = field !== "reducedMotion"
        compare(caption.revealEnd, 7)
      }
      caption.audioAvailable = false
      compare(caption.revealEnd, -1)
      caption.narrationEnabled = false
      verify(caption.revealEnd >= 0, "muted silent packs still use reading speed")
    }
    function test_playbackErrorShowsCompleteTextAndLatePacketsCannotHideIt() {
      var token = caption.beginPlayback()
      ignoreWarning(/learn-omarchy: caption timing unavailable.*/)
      caption.finish(token, 2)
      compare(caption.revealEnd, -1)
      timing(token)
      position(token, 100)
      compare(caption.revealEnd, -1)
    }
  }
}
