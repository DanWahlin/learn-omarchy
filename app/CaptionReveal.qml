import QtQuick
import "CaptionTiming.js" as CaptionTiming

Item {
  id: root
  property string sourceKey: ""
  property string sourceText: ""
  property string displayText: sourceText
  property string formattedText: displayText
  property bool typeText: true
  property bool reducedMotion: false
  property bool narrationEnabled: true
  property bool audioAvailable: false
  property bool active: false
  property bool paused: false
  property int wordsPerMinute: 200
  property int deadlineMs: 3000

  property var words: []
  property string timingText: ""
  property real positionMs: -1
  property bool failed: false
  property bool finished: false
  property bool playing: false
  property int generation: 0
  property real readingElapsed: 0
  property int readingStartOffset: 0
  property int lastVoicedEnd: 0
  property alias deadline: timingDeadline
  readonly property int revealEnd: !typeText || reducedMotion ? -1
    : !narrationEnabled ? CaptionTiming.readingOffset(formattedText, readingElapsed, wordsPerMinute, readingStartOffset)
    : finished || failed || !audioAvailable ? -1
    : positionMs < 0 || !words.length ? 0
    : CaptionTiming.revealOffset(timingText, displayText, formattedText, words, positionMs)

  onRevealEndChanged: if (narrationEnabled) lastVoicedEnd = revealEnd
  onSourceKeyChanged: reset()
  onSourceTextChanged: reset()
  onPausedChanged: {
    if (paused) timingDeadline.stop()
    else if (playing && !failed && !(words.length && positionMs >= 0)) timingDeadline.restart()
  }
  onNarrationEnabledChanged: {
    if (!narrationEnabled && (playing || finished || failed)) {
      readingStartOffset = lastVoicedEnd < 0 ? formattedText.length : lastVoicedEnd
      readingElapsed = 0
    }
  }

  function resetPlayback() {
    timingDeadline.stop()
    generation++
    words = []
    timingText = ""
    positionMs = -1
    failed = false
    finished = false
    playing = false
    lastVoicedEnd = 0
  }

  function reset() {
    resetPlayback()
    readingElapsed = 0
    readingStartOffset = 0
  }

  function beginPlayback() {
    reset()
    playing = true
    if (!paused) timingDeadline.restart()
    return generation
  }

  function fallback(reason) {
    timingDeadline.stop()
    failed = true
    console.warn("learn-omarchy: caption timing unavailable; showing full text:", reason)
  }

  function cancel() {
    generation++
    timingDeadline.stop()
    playing = false
    finished = true
    words = []
    timingText = ""
    positionMs = -1
  }

  function finish(token, exitCode) {
    if (token !== generation || !playing) return
    playing = false
    finished = true
    timingDeadline.stop()
    if (exitCode !== 0) fallback("narration exited with code " + exitCode)
  }

  function receive(raw, token) {
    if (token !== generation || !playing || failed || !narrationEnabled) return
    try {
      var message = JSON.parse(raw)
      if (message.type === "fallback") {
        fallback(message.reason || "unsupported recording")
      } else if (message.type === "timing") {
        if (message.text !== sourceText ||
            CaptionTiming.revealOffset(message.text, displayText, formattedText, message.words, 0) < 0)
          throw new Error("word timing doesn't match this caption")
        timingText = message.text
        words = message.words
      } else if (message.type === "position") {
        if (typeof message.positionMs !== "number" || !isFinite(message.positionMs) || message.positionMs < 0)
          throw new Error("invalid playback position")
        if (!paused) positionMs = message.positionMs
      }
      if (words.length && positionMs >= 0) timingDeadline.stop()
    } catch (error) {
      fallback(String(error))
    }
  }

  Timer {
    id: timingDeadline
    interval: root.deadlineMs
    onTriggered: root.fallback("word timing or playback clock didn't arrive")
  }
  Timer {
    interval: 50
    repeat: true
    running: root.active && !root.paused && !root.narrationEnabled && root.typeText && !root.reducedMotion
      && root.revealEnd < root.formattedText.length
    onTriggered: root.readingElapsed += interval
  }
}
