import QtQuick
import QtTest
import "../../app" as App

Item {
  id: root
  width: 800
  height: 740
  App.PracticeContent { id: practice; anchors.fill: parent; mode: "clipboard" }
  TextEdit { id: clipboardProbe; visible: false }
  SignalSpy { id: captureSpy; target: practice; signalName: "captureRequested" }
  SignalSpy { id: lockSpy; target: practice; signalName: "lockRequested" }
  SignalSpy { id: cancelSpy; target: practice; signalName: "cancelled" }
  SignalSpy { id: taskSpy; target: practice; signalName: "taskRequested" }
  SignalSpy { id: finishSpy; target: practice; signalName: "finished" }
  function button(item, label) {
    if ("clicked" in item && item.text === label) return item
    for (var child of item.children || []) {
      var found = button(child, label)
      if (found) return found
    }
    return null
  }
  TestCase {
    name: "ClipboardPractice"
    when: windowShown
    function init() {
      root.width = 800
      root.height = 740
      practice.mode = "clipboard"
      practice.resetExercise()
      practice.textScale = 1
      practice.screenshot = ""
      practice.busy = false
      practice.error = ""
      practice.copiedFirst = false
      practice.copiedSecond = false
      practice.historyOpened = false
      practice.verified = false
      findChild(practice, "pasteDestination").text = ""
      captureSpy.clear()
      lockSpy.clear()
      cancelSpy.clear()
      taskSpy.clear()
      finishSpy.clear()
    }
    function test_typingAloneCannotComplete() {
      practice.observePaste(practice.sample)
      verify(!practice.verified)
      practice.observeCopy(false, practice.secondSample)
      verify(!practice.copiedSecond)
    }
    function test_copyOrderAndOlderPasteAreRequired() {
      practice.observeCopy(true, "partial selection")
      verify(!practice.copiedFirst)
      practice.observeCopy(true, practice.sample)
      practice.observeCopy(false, practice.secondSample)
      practice.observePaste(practice.sample)
      verify(!practice.verified)
      practice.observeHistory()
      practice.observePaste(practice.secondSample)
      verify(!practice.verified)
      practice.observePaste(practice.sample)
      verify(practice.verified)
    }
    function test_nativeCopyAndPaste() {
      var first = findChild(practice, "firstNote")
      var second = findChild(practice, "secondNote")
      var destination = findChild(practice, "pasteDestination")
      first.forceActiveFocus()
      first.selectAll()
      keyClick(Qt.Key_C, Qt.ControlModifier)
      tryCompare(practice, "copiedFirst", true)
      clipboardProbe.text = ""
      clipboardProbe.paste()
      compare(clipboardProbe.text, practice.sample)
      second.forceActiveFocus()
      second.selectAll()
      keyClick(Qt.Key_C, Qt.ControlModifier)
      tryCompare(practice, "copiedSecond", true)
      clipboardProbe.text = ""
      clipboardProbe.paste()
      compare(clipboardProbe.text, practice.secondSample)

      // Simulate the picker restoring an older entry, not a fabricated paste event.
      practice.observeHistory()
      clipboardProbe.text = practice.sample
      clipboardProbe.selectAll()
      clipboardProbe.copy()
      destination.forceActiveFocus()
      destination.text = practice.sample
      verify(!practice.verified)
      destination.clear()
      keyClick(Qt.Key_V, Qt.ControlModifier)
      tryCompare(destination, "text", practice.sample)
      tryCompare(practice, "verified", true)
      keyClick(Qt.Key_Tab)
      tryCompare(findChild(practice, "returnWithoutCompleting"), "activeFocus", true)
      keyClick(Qt.Key_Tab)
      tryCompare(findChild(practice, "finishExercise"), "activeFocus", true)
      compare(destination.text, practice.sample)
    }
    function test_recopyRequiresHistoryAgain() {
      practice.observeCopy(true, practice.sample)
      practice.observeCopy(false, practice.secondSample)
      practice.observeHistory()
      practice.observeCopy(true, practice.sample)
      practice.observePaste(practice.sample)
      verify(!practice.verified)
      verify(!practice.historyOpened)
      verify(!practice.copiedSecond)
    }
    function test_explicitActions_data() {
      return [
        { tag: "capture-desktop", mode: "capture", width: 760 },
        { tag: "capture-narrow", mode: "capture", width: 460 },
        { tag: "lock-desktop", mode: "screen-lock", width: 760 },
        { tag: "lock-narrow", mode: "screen-lock", width: 460 },
        { tag: "capture-large-text", mode: "capture", width: 460, scale: 1.3 },
        { tag: "lock-large-text", mode: "screen-lock", width: 460, scale: 1.3 }
      ]
    }
    function test_explicitActions(data) {
      root.width = data.width
      root.height = 600
      practice.mode = data.mode
      practice.textScale = data.scale || 1
      wait(50)
      compare(captureSpy.count, 0)
      compare(lockSpy.count, 0)
      verify(!root.button(practice, "Finish exercise").enabled)
      for (var label of ["Return without completing", "Finish exercise"]) {
        var control = root.button(practice, label)
        var point = control.mapToItem(practice, 0, 0)
        verify(point.x >= 0 && point.x + control.width <= practice.width)
        verify(point.y >= 0 && point.y + control.height <= practice.height)
      }
      var action = root.button(practice, data.mode === "capture" ? "Select a region" : "Lock this computer now")
      action.forceActiveFocus()
      wait(30)
      mouseClick(action)
      compare(data.mode === "capture" ? captureSpy.count : lockSpy.count, 1)
      verify(!practice.verified)
      keyClick(Qt.Key_Escape)
      compare(cancelSpy.count, 1)
    }
    function test_captureRequiresImageCopyAndAnnotation() {
      practice.mode = "capture"
      verify(!practice.verified)
      practice.screenshot = Qt.resolvedUrl("../../assets/characters/owl/sprites/owl-idle.png").toString().replace("file://", "")
      var copy = findChild(practice, "copyCapture")
      tryCompare(copy, "enabled", true)
      verify(!practice.verified)
      copy.clicked()
      verify(!practice.verified)
      findChild(practice, "captureAnnotation").text = "My practice capture"
      tryCompare(practice, "verified", true)
    }
    function test_allModesStartIncomplete_data() {
      var rows = []
      for (var mode of ["compose", "screen-recording", "ocr", "qr", "dictation", "web-app", "transcode", "sharing"]) {
        rows.push({ tag: mode, mode: mode, width: 760, scale: 1 })
        rows.push({ tag: mode + "-narrow-large", mode: mode, width: 460, scale: 1.3 })
      }
      return rows
    }
    function test_allModesStartIncomplete(data) {
      root.width = data.width
      root.height = 480
      practice.textScale = data.scale
      practice.mode = data.mode
      wait(30)
      verify(!practice.verified)
      verify(!findChild(practice, "finishExercise").enabled)
      compare(taskSpy.count, 0, "No automatic capture, microphone use, creation or transfer")
      for (var name of ["returnWithoutCompleting", "finishExercise"]) {
        var control = findChild(practice, name)
        var point = control.mapToItem(practice, 0, 0)
        verify(point.x >= 0 && point.x + control.width <= practice.width)
        verify(point.y >= 0 && point.y + control.height <= practice.height)
      }
    }
    function test_composeChecksBothActualResults() {
      practice.mode = "compose"
      var smile = findChild(practice, "composeSmile")
      var heart = findChild(practice, "composeHeart")
      smile.text = "ms"
      heart.text = "mh"
      verify(!practice.verified)
      smile.text = "😄"
      verify(!practice.verified)
      heart.text = "❤️"
      verify(practice.verified)
      smile.clear()
      verify(!practice.verified)
    }
    function test_recordingNeedsSelectionStartStopAndPlayback() {
      practice.mode = "screen-recording"
      verify(!findChild(practice, "startRecording").enabled)
      verify(!findChild(practice, "stopRecording").enabled)
      practice.handleTaskResult({ action: "select", cancelled: true })
      verify(!practice.verified)
      practice.handleTaskResult({ action: "select", region: "0,0 100x100" })
      findChild(practice, "startRecording").clicked()
      compare(taskSpy.signalArguments[0][0], "start")
      verify(practice.busy)
      practice.handleTaskResult({ action: "start", recording: true })
      verify(findChild(practice, "stopRecording").enabled)
      verify(!practice.verified)
      findChild(practice, "stopRecording").clicked()
      practice.handleTaskResult({ action: "stop", path: "/nonexistent/recording.mp4" })
      verify(!practice.recording)
      verify(!practice.verified, "A saved path without successful playback is insufficient")
      findChild(practice, "playOutput").clicked()
      wait(100)
      verify(!practice.verified, "Playback failure never completes")
    }
    function test_recognitionRequiresRealPasteAndReview_data() {
      return [{ tag: "ocr", mode: "ocr" }, { tag: "qr", mode: "qr" }]
    }
    function test_recognitionRequiresRealPasteAndReview(data) {
      practice.mode = data.mode
      var input = findChild(practice, "exerciseInput")
      var review = findChild(practice, "reviewRecognized")
      practice.handleTaskResult({ action: "extract", text: "wrong sample" })
      verify(!input.enabled)
      practice.handleTaskResult({ action: "extract", text: "OMARCHY SAFE SAMPLE" })
      input.text = "OMARCHY SAFE SAMPLE"
      verify(!review.enabled, "Typing does not count as a paste")
      findChild(practice, "copyExtracted").clicked()
      input.clear()
      input.forceActiveFocus()
      keyClick(Qt.Key_V, Qt.ControlModifier)
      tryCompare(review, "enabled", true)
      verify(!practice.verified, "Proofreading is explicit")
      review.clicked()
      verify(practice.verified)
      input.text = "changed"
      verify(!practice.verified)
    }
    function test_dictationChecksAvailabilityConsentAndProofreading() {
      practice.mode = "dictation"
      var input = findChild(practice, "exerciseInput")
      var review = findChild(practice, "reviewRecognized")
      verify(!input.enabled)
      findChild(practice, "checkDictation").clicked()
      practice.handleTaskResult({ action: "check", error: "Voxtype is unavailable" })
      verify(!input.enabled)
      verify(!practice.verified)
      practice.handleTaskResult({ action: "check", available: true })
      verify(!input.enabled)
      findChild(practice, "consentDictation").clicked()
      verify(input.enabled)
      input.text = "wrong words"
      verify(!review.enabled)
      input.text = "Omarchy practice."
      verify(review.enabled)
      verify(!practice.verified)
      review.clicked()
      verify(practice.verified)
    }
    function test_webAppRequiresPreviewThenRemoval() {
      practice.mode = "web-app"
      verify(!findChild(practice, "openWebApp").enabled)
      verify(!findChild(practice, "removeWebApp").enabled)
      findChild(practice, "createWebApp").clicked()
      practice.handleTaskResult({ action: "create", path: "/demo/demo.desktop" })
      verify(!practice.verified)
      verify(!findChild(practice, "removeWebApp").enabled)
      findChild(practice, "openWebApp").clicked()
      practice.handleTaskResult({ action: "open", opened: true })
      verify(!practice.verified)
      findChild(practice, "removeWebApp").clicked()
      practice.handleTaskResult({ action: "remove", error: "Removal failed" })
      verify(!practice.verified)
      practice.handleTaskResult({ action: "remove", removed: true })
      verify(practice.verified)
    }
    function test_transcodeNeedsPlaybackSizeComparisonAndReview() {
      practice.mode = "transcode"
      practice.handleTaskResult({ action: "prepare", path: "/demo/original.mp4", bytes: 1000 })
      verify(!findChild(practice, "convertSample").enabled)
      practice.originalPlayed = true
      findChild(practice, "outputResolution").currentIndex = 1
      verify(findChild(practice, "convertSample").enabled)
      findChild(practice, "convertSample").clicked()
      compare(taskSpy.signalArguments[0][1].height, 240)
      practice.handleTaskResult({ action: "convert", path: "/demo/smaller.mp4", bytes: 200, originalBytes: 1000 })
      verify(!practice.verified)
      verify(!findChild(practice, "reviewTranscode").enabled)
      practice.outputPlayed = true
      findChild(practice, "reviewTranscode").clicked()
      verify(practice.verified)
    }
    function test_sharingReviewsOnlyIntendedRecipientNeverDelivery() {
      practice.mode = "sharing"
      var review = findChild(practice, "reviewShare")
      verify(!review.enabled)
      findChild(practice, "prepareSample").clicked()
      practice.handleTaskResult({ action: "prepare", path: "/demo/share-note.txt" })
      verify(!review.enabled)
      findChild(practice, "shareRecipient").currentIndex = 2
      verify(!review.enabled)
      findChild(practice, "shareRecipient").currentIndex = 1
      review.clicked()
      verify(practice.verified)
      compare(taskSpy.count, 1, "Review never requests a send")
      verify(practice.status.indexOf("No transfer attempted") !== -1)
      findChild(practice, "shareRecipient").currentIndex = 2
      verify(!practice.verified)
    }
  }
}
