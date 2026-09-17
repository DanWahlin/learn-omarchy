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
  function isInPracticeViewport(item, scroll) {
    var point = item.mapToItem(scroll, 0, 0)
    return point.y >= -1 && point.y + item.height <= scroll.height + 1
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
      practice.showFooter = true
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
    function test_resetRestartsClipboardAtTheFirstNote() {
      practice.copiedFirst = true
      practice.copiedSecond = true
      practice.historyOpened = true
      findChild(practice, "pasteDestination").text = practice.sample
      practice.resetExercise()
      verify(!practice.copiedFirst)
      verify(!practice.copiedSecond)
      verify(!practice.historyOpened)
      compare(findChild(practice, "pasteDestination").text, "")
      verify(findChild(practice, "firstNote").visible)
      verify(!findChild(practice, "secondNote").visible)
    }
    function test_disabledFinishIsVisiblyInactive() {
      var finish = findChild(practice, "finishExercise")
      verify(!finish.enabled)
      compare(finish.background.color, practice.backgroundColor)
      verify(finish.contentItem.color !== practice.backgroundColor, "Disabled text stays readable")
      practice.verified = true
      verify(finish.enabled)
      compare(finish.background.color, practice.accent)
      practice.busy = true
      verify(!finish.enabled)
      compare(finish.background.color, practice.backgroundColor)
    }
    function test_compactWorkbenchKeepsFooterAndFocusedFieldsVisible() {
      root.width = 640
      root.height = 320
      practice.mode = "compose"
      practice.textScale = 1.3
      practice.focusPractice()
      var smile = findChild(practice, "composeSmile")
      tryCompare(smile, "activeFocus", true)
      keyClick(Qt.Key_Tab)
      var heart = findChild(practice, "composeHeart")
      tryCompare(heart, "activeFocus", true)
      wait(30)
      var scroll = findChild(practice, "practiceScroll")
      var point = heart.mapToItem(scroll, 0, 0)
      verify(point.y >= 0 && point.y + heart.height <= scroll.height,
        "Focused field y=" + point.y + ", height=" + heart.height + ", viewport=" + scroll.height)
      var finish = findChild(practice, "finishExercise")
      var footer = finish.mapToItem(practice, 0, 0)
      verify(footer.y + finish.height <= practice.height)
      practice.showFooter = false
      verify(!finish.visible)
      practice.mode = "capture"
      practice.focusPractice()
      tryCompare(findChild(practice, "selectRegion"), "activeFocus", true)
    }
    function test_clipboardProgressRevealsEachNextStep_data() {
      return [
        { tag: "desktop", width: 760, height: 480, scale: 1.25 },
        { tag: "narrow-large", width: 460, height: 320, scale: 1.3 }
      ]
    }
    function test_clipboardProgressRevealsEachNextStep(data) {
      root.width = data.width
      root.height = data.height
      practice.textScale = data.scale
      var scroll = findChild(practice, "practiceScroll")
      var first = findChild(practice, "firstNote")
      var second = findChild(practice, "secondNote")
      var history = findChild(practice, "clipboardHistoryInstructions")
      verify(first.visible)
      verify(!second.visible)
      verify(!history.visible)

      practice.observeCopy(true, practice.sample)
      tryCompare(second, "visible", true)
      tryCompare(second, "activeFocus", true)
      wait(30)
      var secondPoint = second.mapToItem(scroll, 0, 0)
      verify(secondPoint.y >= 0 && secondPoint.y + second.height <= scroll.height,
        "Second note must be fully visible after copying the first")

      practice.observeCopy(false, practice.secondSample)
      tryCompare(history, "visible", true)
      wait(30)
      var historyPoint = history.mapToItem(scroll, 0, 0)
      verify(historyPoint.y >= 0 && historyPoint.y + history.height <= scroll.height,
        "History instructions must be fully visible after copying the second")
    }
    function test_progressiveResultsRevealNextAction_data() {
      var scenarios = [
        { tag: "recording-selected", mode: "screen-recording", next: "startRecording" },
        { tag: "recording-started", mode: "screen-recording", next: "stopRecording" },
        { tag: "recording-stopped", mode: "screen-recording", next: "playOutput" },
        { tag: "ocr-extracted", mode: "ocr", next: "copyExtracted" },
        { tag: "qr-prepared", mode: "qr", next: "extractSample" },
        { tag: "dictation-available", mode: "dictation", next: "consentDictation" },
        { tag: "web-app-created", mode: "web-app", next: "openWebApp" },
        { tag: "web-app-opened", mode: "web-app", next: "removeWebApp" },
        { tag: "transcode-prepared", mode: "transcode", next: "playOriginal" },
        { tag: "transcode-finished", mode: "transcode", next: "playOutput" },
        { tag: "sharing-prepared", mode: "sharing", next: "shareRecipient" }
      ]
      var rows = []
      for (var scenario of scenarios) {
        rows.push({
          tag: scenario.tag + "-desktop",
          transition: scenario.tag,
          mode: scenario.mode,
          next: scenario.next,
          width: 760,
          scale: 1
        })
        rows.push({
          tag: scenario.tag + "-narrow-large",
          transition: scenario.tag,
          mode: scenario.mode,
          next: scenario.next,
          width: 460,
          scale: 1.3
        })
      }
      return rows
    }
    function test_progressiveResultsRevealNextAction(data) {
      root.width = data.width
      root.height = 320
      practice.textScale = data.scale
      practice.mode = data.mode
      practice.resetExercise()

      if (data.transition === "recording-started") {
        practice.region = "0,0 100x100"
        practice.stage = 1
      } else if (data.transition === "recording-stopped") {
        practice.region = "0,0 100x100"
        practice.stage = 2
        practice.recording = true
      } else if (data.transition === "web-app-opened") {
        practice.stage = 1
      } else if (data.transition === "transcode-finished") {
        practice.original = "/tmp/original.mp4"
        practice.originalBytes = 200
        practice.originalPlayed = true
        practice.stage = 1
        findChild(practice, "outputResolution").currentIndex = 1
      }

      if (data.transition === "recording-selected")
        practice.handleTaskResult({ action: "select", region: "0,0 100x100" })
      else if (data.transition === "recording-started")
        practice.handleTaskResult({ action: "start", recording: true })
      else if (data.transition === "recording-stopped")
        practice.handleTaskResult({ action: "stop", path: "/tmp/output.mp4" })
      else if (data.transition === "ocr-extracted")
        practice.handleTaskResult({ action: "extract", text: "OMARCHY SAFE SAMPLE", path: "/tmp/ocr.txt" })
      else if (data.transition === "qr-prepared")
        practice.handleTaskResult({
          action: "prepare",
          image: Qt.resolvedUrl("../../assets/characters/owl/sprites/owl-idle.png").toString().replace("file://", "")
        })
      else if (data.transition === "dictation-available")
        practice.handleTaskResult({ action: "check", available: true })
      else if (data.transition === "web-app-created")
        practice.handleTaskResult({ action: "create", path: "/tmp/demo.desktop" })
      else if (data.transition === "web-app-opened")
        practice.handleTaskResult({ action: "open", opened: true })
      else if (data.transition === "transcode-prepared")
        practice.handleTaskResult({ action: "prepare", path: "/tmp/original.mp4", bytes: 200 })
      else if (data.transition === "transcode-finished")
        practice.handleTaskResult({ action: "convert", path: "/tmp/output.mp4", bytes: 100, originalBytes: 200 })
      else if (data.transition === "sharing-prepared")
        practice.handleTaskResult({ action: "prepare", path: "/tmp/share-note.txt" })

      var next = findChild(practice, data.next)
      tryCompare(next, "activeFocus", true)
      wait(30)
      verify(isInPracticeViewport(next, findChild(practice, "practiceScroll")),
        data.next + " must be fully visible after " + data.transition)
    }
    function test_tabFromScrollReturnsToTheNextEnabledExerciseControl() {
      practice.mode = "screen-recording"
      practice.stage = 2
      practice.recording = true
      var scroll = findChild(practice, "practiceScroll")
      scroll.forceActiveFocus()
      keyClick(Qt.Key_Tab)
      tryCompare(findChild(practice, "stopRecording"), "activeFocus", true)
    }
    function test_reviewedSampleCanTabOutToTheFooter() {
      practice.mode = "ocr"
      practice.extracted = "OMARCHY SAFE SAMPLE"
      var input = findChild(practice, "exerciseInput")
      input.text = practice.extracted
      practice.nativeSamplePasted = true
      var review = findChild(practice, "reviewRecognized")
      verify(review.enabled)
      review.clicked()
      verify(practice.verified)
      verify(!review.enabled)
      input.forceActiveFocus()
      keyClick(Qt.Key_Tab)
      tryCompare(findChild(practice, "returnWithoutCompleting"), "activeFocus", true)
      keyClick(Qt.Key_Tab)
      tryCompare(findChild(practice, "finishExercise"), "activeFocus", true)
    }
    function test_sharingFocusFindsTheEnabledRecipientSelector() {
      practice.mode = "sharing"
      practice.stage = 1
      practice.focusPractice()
      tryCompare(findChild(practice, "shareRecipient"), "activeFocus", true)
      findChild(practice, "returnWithoutCompleting").forceActiveFocus()
      keyClick(Qt.Key_Tab)
      tryCompare(findChild(practice, "shareRecipient"), "activeFocus", true)
    }
    function test_mediaPreviewCanTakeFocusAndBeRevealed() {
      root.width = 640
      root.height = 320
      practice.mode = "transcode"
      practice.original = "/test-original.mp4"
      var video = findChild(practice, "practiceVideo")
      video.forceActiveFocus()
      practice.scheduleReveal(video)
      wait(50)
      var scroll = findChild(practice, "practiceScroll")
      var position = video.mapToItem(scroll, 0, 0)
      verify(position.y >= -1 && position.y + video.height <= scroll.height + 1)
      keyClick(Qt.Key_Tab)
      tryCompare(findChild(practice, "outputResolution"), "activeFocus", true)
    }
    function test_qrRemainsFullyVisibleWhenDecodeButtonHasFocus() {
      root.width = 640
      root.height = 320
      practice.mode = "qr"
      practice.qrImage = Qt.resolvedUrl("../../assets/characters/ohm-1/sprites/ohm-1-point.png")
        .toString().replace(/^file:\/\//, "")
      for (var scale of [1, 1.3]) {
        practice.textScale = scale
        var extract = findChild(practice, "extractSample")
        extract.forceActiveFocus()
        practice.scheduleReveal(extract)
        wait(50)
        var scroll = findChild(practice, "practiceScroll")
        var qr = findChild(practice, "sampleQr")
        var position = qr.mapToItem(scroll, 0, 0)
        verify(position.y >= -1, "QR top must not be clipped: " + position.y)
        verify(position.y + qr.height <= scroll.height + 1, "QR bottom must fit")
        var buttonPosition = extract.mapToItem(scroll, 0, 0)
        verify(buttonPosition.y + extract.height <= scroll.height + 1, "Decode button must fit")
      }
    }
    function test_nativeSampleStaysFixedWhileControlsScroll() {
      root.width = 640
      root.height = 320
      practice.textScale = 1.3
      for (var mode of ["screen-recording", "ocr"]) {
        practice.mode = mode
        wait(30)
        var sample = findChild(practice, "nativePracticeSample")
        var before = sample.mapToItem(practice, 0, 0)
        var scroll = findChild(practice, "practiceScroll")
        scroll.contentItem.contentY = Math.max(0, scroll.contentItem.contentHeight - scroll.height)
        if (mode === "screen-recording") {
          practice.region = "100,100 300x80"
          practice.stage = 1
          findChild(practice, "startRecording").forceActiveFocus()
        }
        wait(30)
        var after = sample.mapToItem(practice, 0, 0)
        compare(after.x, before.x)
        compare(after.y, before.y, "Reviewing or starting must not move the selected sample")
        verify(sample.visible && sample.height > 0 && scroll.height > 0)
      }
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
      verify(findChild(practice, "exerciseInstructions").text.indexOf("press Shift+Enter") !== -1)
      verify(findChild(practice, "clipboardHistoryInstructions").text.indexOf("Shift+Enter") !== -1)
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
      root.width = 460
      root.height = 320
      practice.textScale = 1.3
      practice.mode = "capture"
      verify(!practice.verified)
      practice.screenshot = Qt.resolvedUrl("../../assets/characters/owl/sprites/owl-idle.png").toString().replace("file://", "")
      var copy = findChild(practice, "copyCapture")
      tryCompare(copy, "enabled", true)
      tryCompare(copy, "activeFocus", true)
      wait(30)
      verify(isInPracticeViewport(copy, findChild(practice, "practiceScroll")),
        "Capture review controls must be revealed after selecting a region")
      verify(!practice.verified)
      copy.clicked()
      verify(!practice.verified)
      findChild(practice, "captureAnnotation").text = "My practice capture"
      tryCompare(practice, "verified", true)
    }
    function test_allModesStartIncomplete_data() {
      var rows = []
      for (var mode of ["compose", "screen-recording", "ocr", "qr", "dictation", "dictation-corrections", "notifications", "web-app", "transcode", "sharing"]) {
        rows.push({ tag: mode, mode: mode, width: 760, scale: 1 })
        rows.push({ tag: mode + "-narrow-large", mode: mode, width: 460, scale: 1.3 })
      }
      return rows
    }
    function test_allModesStartIncomplete(data) {
      root.width = data.width
      root.height = 320
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
      tryCompare(findChild(practice, "copyExtracted"), "activeFocus", true)
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
    function test_dictationCorrectionUsesMetadataAndA_specificSimulation() {
      practice.mode = "dictation-corrections"
      findChild(practice, "inspectDictationCorrections").clicked()
      compare(taskSpy.signalArguments[0][0], "inspect")
      practice.handleTaskResult({ action: "inspect", source: "sample", replacementsDocumented: false })
      var choice = findChild(practice, "dictationCorrectionChoice")
      choice.currentIndex = 2
      findChild(practice, "applyDictationCorrection").clicked()
      verify(!practice.verified)
      choice.currentIndex = 1
      findChild(practice, "applyDictationCorrection").clicked()
      verify(practice.verified)
      practice.resetExercise()
      verify(!practice.verified)
      verify(!practice.correctionApplied)
      compare(choice.currentIndex, 0)
    }
    function test_notificationPracticeRestoresSimulatedQuietMode() {
      practice.mode = "notifications"
      findChild(practice, "showSampleNotification").clicked()
      findChild(practice, "openSampleNotificationHistory").clicked()
      findChild(practice, "dismissSampleNotification").clicked()
      var quiet = findChild(practice, "toggleSampleQuiet")
      quiet.clicked()
      verify(practice.simulatedQuiet)
      verify(!practice.verified)
      quiet.clicked()
      verify(!practice.simulatedQuiet)
      verify(practice.verified)
      compare(taskSpy.count, 0, "Notification practice never calls a host helper")
      practice.resetExercise()
      verify(!practice.verified)
      verify(!practice.simulatedQuiet)
      verify(!practice.simulatedQuietSeen)
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
