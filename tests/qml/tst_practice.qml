import QtQuick
import QtTest
import "../../app" as App

Item {
  id: root
  width: 800
  height: 740
  App.PracticeContent { id: practice; anchors.fill: parent; mode: "clipboard" }
  TextEdit { id: clipboardProbe; visible: false }
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
      practice.clipboardFeedback = ""
      practice.verified = false
      findChild(practice, "pasteDestination").text = ""
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
      compare(practice.clipboardFeedback, "")
      compare(findChild(practice, "pasteDestination").text, "")
      verify(findChild(practice, "firstNote").visible)
      verify(!findChild(practice, "secondNote").visible)
    }
    function test_clipboardAutomaticallySelectsTheActiveNote() {
      practice.mode = "clipboard"
      practice.focusPractice()
      var first = findChild(practice, "firstNote")
      tryCompare(first, "activeFocus", true)
      compare(first.selectedText, practice.sample)
      compare(root.button(practice, "Select first note"), null)

      practice.observeCopy(true, practice.sample)
      var second = findChild(practice, "secondNote")
      tryCompare(second, "activeFocus", true)
      compare(second.selectedText, practice.secondSample)
      compare(root.button(practice, "Select newer note"), null)
    }
    function test_footerActionsAreEqualAndCompact() {
      var cancel = findChild(practice, "returnWithoutCompleting")
      var finish = findChild(practice, "finishExercise")

      root.width = 1200
      root.height = 740
      wait(20)
      compare(cancel.width, finish.width)
      verify(cancel.width < root.width / 3)
      compare(cancel.y, finish.y)

      root.width = 460
      root.height = 520
      practice.textScale = 1.3
      wait(20)
      compare(cancel.width, finish.width)
      verify(finish.y >= cancel.y + cancel.height)
      verify(cancel.x >= 0 && cancel.x + cancel.width <= practice.width)
      verify(finish.x >= 0 && finish.x + finish.width <= practice.width)
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
    function test_keyboardPracticeShowsConsistentKeyGuides_data() {
      return [
        {
          tag: "clipboard",
          mode: "clipboard",
          guides: ["SUPER + C"]
        },
        {
          tag: "compose",
          mode: "compose",
          guides: ["CAPS LOCK → M → S", "CAPS LOCK → M → H"]
        },
        { tag: "recording", mode: "screen-recording", guides: ["SUPER + CTRL + C"] },
        { tag: "ocr", mode: "ocr", guides: ["SUPER + CTRL + C", "SUPER + V"] },
        {
          tag: "dictation",
          mode: "dictation",
          guides: ["SUPER + CTRL + X", "F9"]
        },
        { tag: "screen-lock", mode: "screen-lock", guides: ["SUPER + CTRL + L"] },
        { tag: "capture", mode: "capture", guides: ["SUPER + CTRL + C"] }
      ]
    }
    function test_keyboardPracticeShowsConsistentKeyGuides(data) {
      practice.mode = data.mode
      wait(30)
      var list = findChild(practice, "practiceKeyGuideList")
      compare(list.visible, data.guides.length > 0)
      compare(practice.currentKeyGuides.length, data.guides.length)
      for (var index = 0; index < data.guides.length; index++) {
        var guide = findChild(practice, "practiceKeyGuide" + index)
        verify(guide && guide.visible)
        compare(guide.guideKeys.join(" "), data.guides[index])
      }
    }
    function test_clipboardKeyGuideFollowsTheCurrentStep() {
      function compareGuides(expected) {
        compare(practice.currentKeyGuides.length, expected.length)
        wait(20)
        for (var index = 0; index < expected.length; index++) {
          var guide = findChild(practice, "practiceKeyGuide" + index)
          verify(guide && guide.visible)
          compare(guide.guideLabel, expected[index][0])
          compare(guide.guideKeys.join(" "), expected[index][1])
        }
      }

      practice.mode = "clipboard"
      verify(!findChild(practice, "exerciseInstructions").visible)
      compareGuides([["Copy the selected original note", "SUPER + C"]])

      practice.observeCopy(true, practice.sample)
      compareGuides([["Copy the selected newer note", "SUPER + C"]])

      practice.observeCopy(false, practice.secondSample)
      compareGuides([
        ["Open clipboard history", "SUPER + CTRL + V"],
        ["Choose \"" + practice.sample + "\" (not the entry beginning \"A newer note\")", "SHIFT + ENTER"],
        ["Paste the original note into the destination", "SUPER + V"]
      ])

      practice.observeHistory()
      compareGuides([
        ["Open clipboard history", "SUPER + CTRL + V"],
        ["Choose \"" + practice.sample + "\" (not the entry beginning \"A newer note\")", "SHIFT + ENTER"],
        ["Paste the original note into the destination", "SUPER + V"]
      ])
      verify(findChild(practice, "pasteDestination").placeholderText.indexOf("Super") === -1)
    }
    function test_supportingCopyDoesNotRepeatHighlightedShortcuts() {
      for (var mode of ["compose", "dictation", "screen-lock"]) {
        practice.mode = mode
        wait(10)
        var text = findChild(practice, "exerciseInstructions").text
        verify(text.indexOf("Super+") === -1, mode)
        verify(text.indexOf("Caps Lock →") === -1, mode)
        verify(text.indexOf("F9") === -1, mode)
      }
      practice.mode = "compose"
      verify(findChild(practice, "composeSmile").placeholderText.indexOf("Caps Lock") === -1)
      verify(findChild(practice, "composeHeart").placeholderText.indexOf("Caps Lock") === -1)
    }
    function test_textAreasAreProminentLearningControls() {
      root.width = 460
      root.height = 320
      practice.mode = "compose"
      practice.textScale = 1.3
      var smile = findChild(practice, "composeSmile")
      var heart = findChild(practice, "composeHeart")
      for (var field of [smile, heart]) {
        verify(field.implicitHeight >= 76 * practice.textScale)
        compare(field.background.border.width, 2)
      }
      smile.forceActiveFocus()
      tryCompare(smile, "activeFocus", true)
      compare(smile.background.border.width, 3)
      verify(isInPracticeViewport(smile, findChild(practice, "practiceScroll")))
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
      verify(first.visible)
      verify(!second.visible)

      practice.observeCopy(true, practice.sample)
      tryCompare(second, "visible", true)
      tryCompare(second, "activeFocus", true)
      wait(30)
      var secondPoint = second.mapToItem(scroll, 0, 0)
      verify(secondPoint.y >= 0 && secondPoint.y + second.height <= scroll.height,
        "Second note must be fully visible after copying the first")

      practice.observeCopy(false, practice.secondSample)
      wait(30)
      var history = findChild(practice, "practiceKeyGuide0")
      compare(history.guideKeys.join(" "), "SUPER + CTRL + V")
      var historyPoint = history.mapToItem(scroll, 0, 0)
      verify(historyPoint.y >= 0 && historyPoint.y + history.height <= scroll.height,
        "The current history shortcut must be fully visible after copying the second: y=" +
        historyPoint.y + ", height=" + history.height + ", viewport=" + scroll.height)
    }
    function test_clipboardFinalStepFitsDedicatedPracticeSurface() {
      root.width = 1100
      root.height = 680
      practice.textScale = 1
      practice.observeCopy(true, practice.sample)
      practice.observeCopy(false, practice.secondSample)
      wait(30)

      var scroll = findChild(practice, "practiceScroll")
      var firstGuide = findChild(practice, "practiceKeyGuide0")
      var secondGuide = findChild(practice, "practiceKeyGuide1")
      var thirdGuide = findChild(practice, "practiceKeyGuide2")
      verify(firstGuide.y < secondGuide.y)
      verify(secondGuide.y < thirdGuide.y)
      verify(isInPracticeViewport(findChild(practice, "pasteDestination"), scroll))
    }
    function test_progressiveResultsRevealNextAction_data() {
      var scenarios = [
        { tag: "recording-saved", mode: "screen-recording", next: "playOutput" },
        { tag: "qr-prepared", mode: "qr", next: "exerciseInput" },
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

      if (data.transition === "web-app-opened") {
        practice.stage = 1
      } else if (data.transition === "transcode-finished") {
        practice.original = "/tmp/original.mp4"
        practice.originalBytes = 200
        practice.originalPlayed = true
        practice.stage = 1
        findChild(practice, "outputResolution").currentIndex = 1
      }

      if (data.transition === "recording-saved")
        practice.observeRecordingSaved("/tmp/output.mp4")
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
      var viewport = findChild(practice, "practiceScroll")
      var position = next.mapToItem(viewport, 0, 0)
      var revealed = next.height <= viewport.height
        ? isInPracticeViewport(next, viewport)
        : position.y >= -1 && position.y < viewport.height
      verify(revealed,
        data.next + " must be fully visible after " + data.transition
        + ": y=" + position.y + ", height=" + next.height + ", viewport=" + viewport.height)
    }
    function test_activeRecordingCannotBeAbandonedFromTheExercise() {
      practice.mode = "screen-recording"
      practice.observeRecordingStarted()
      verify(practice.recording)
      verify(!findChild(practice, "returnWithoutCompleting").enabled)
      compare(findChild(practice, "returnWithoutCompleting").text, "Stop recording before returning")
      keyClick(Qt.Key_Escape)
      compare(cancelSpy.count, 0)
    }
    function test_verifiedNativeTextCanTabOutToTheFooter() {
      practice.mode = "ocr"
      var input = findChild(practice, "exerciseInput")
      input.text = "OMARCHY SAFE SAMPLE"
      practice.observeExercisePaste(input.text)
      verify(practice.verified)
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
    function test_qrStaysVisibleWhilePasteFieldScrollsIntoView() {
      root.width = 640
      root.height = 320
      practice.mode = "qr"
      practice.qrImage = Qt.resolvedUrl("../../assets/characters/ohm-1/sprites/ohm-1-point.png")
        .toString().replace(/^file:\/\//, "")
      for (var scale of [1, 1.3]) {
        practice.textScale = scale
        var input = findChild(practice, "exerciseInput")
        var sample = findChild(practice, "nativePracticeSample")
        var before = sample.mapToItem(practice, 0, 0)
        input.forceActiveFocus()
        practice.scheduleReveal(input)
        wait(50)
        var scroll = findChild(practice, "practiceScroll")
        var after = sample.mapToItem(practice, 0, 0)
        verify(Math.abs(after.x - before.x) <= 8)
        verify(Math.abs(after.y - before.y) <= 8)
        verify(sample.visible && findChild(practice, "sampleQr").visible)
        var inputPosition = input.mapToItem(scroll, 0, 0)
        verify(inputPosition.y >= -1 && inputPosition.y < scroll.height,
          "The focused paste field must start inside the viewport")
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
        if (mode === "screen-recording") practice.observeRecordingStarted()
        wait(30)
        var after = sample.mapToItem(practice, 0, 0)
        compare(after.x, before.x)
        compare(after.y, before.y, "Native capture progress must not move the selected sample")
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
    function test_wrongClipboardPasteExplainsAndPreparesRecovery() {
      practice.observeCopy(true, practice.sample)
      practice.observeCopy(false, practice.secondSample)
      practice.observeHistory()

      var destination = findChild(practice, "pasteDestination")
      destination.text = practice.secondSample
      practice.observePaste(destination.text)

      verify(!practice.verified)
      verify(practice.clipboardFeedback.includes("newer note"))
      tryCompare(destination, "selectedText", practice.secondSample)
      compare(practice.currentKeyGuides.length, 3)
      compare(findChild(practice, "practiceKeyGuide0").guideLabel, "Open clipboard history")
      compare(findChild(practice, "practiceKeyGuide1").guideLabel,
              "Choose \"" + practice.sample + "\" (not the entry beginning \"A newer note\")")
      compare(findChild(practice, "practiceKeyGuide2").guideLabel,
              "Paste the original note into the destination")
      verify(findChild(practice, "clipboardFeedback").visible)

      destination.text = practice.sample
      practice.observePaste(destination.text)
      verify(practice.verified)
      compare(practice.clipboardFeedback, "")
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
        { tag: "lock-desktop", mode: "screen-lock", width: 760 },
        { tag: "lock-narrow", mode: "screen-lock", width: 460 },
        { tag: "lock-large-text", mode: "screen-lock", width: 460, scale: 1.3 }
      ]
    }
    function test_explicitActions(data) {
      root.width = data.width
      root.height = 600
      practice.mode = data.mode
      practice.textScale = data.scale || 1
      wait(50)
      compare(lockSpy.count, 0)
      verify(!root.button(practice, "Finish exercise").enabled)
      for (var label of ["Return without completing", "Finish exercise"]) {
        var control = root.button(practice, label)
        var point = control.mapToItem(practice, 0, 0)
        verify(point.x >= 0 && point.x + control.width <= practice.width)
        verify(point.y >= 0 && point.y + control.height <= practice.height)
      }
      var action = root.button(practice, "Lock this computer now")
      action.forceActiveFocus()
      wait(30)
      mouseClick(action)
      compare(lockSpy.count, 1)
      verify(!practice.verified)
      keyClick(Qt.Key_Escape)
      compare(cancelSpy.count, 1)
    }
    function test_captureStartsWithTheHardwareNeutralScreenshotShortcut() {
      practice.mode = "capture"
      compare(practice.currentKeyGuides.length, 1)
      compare(practice.currentKeyGuides[0].label, "Open Capture, then choose Screenshot")
      compare(practice.currentKeyGuides[0].keys.join(" "), "SUPER + CTRL + C")
      compare(root.button(practice, "Select screenshot region"), null)
      keyClick(Qt.Key_Escape)
      compare(cancelSpy.count, 0)
    }
    function test_captureCompletesWhenTheScreenshotLoads() {
      root.width = 460
      root.height = 320
      practice.textScale = 1.3
      practice.mode = "capture"
      verify(!practice.verified)
      practice.screenshot = Qt.resolvedUrl("../../assets/characters/owl/sprites/owl-idle.png").toString().replace("file://", "")
      tryCompare(practice, "verified", true)
      var finish = findChild(practice, "finishExercise")
      tryCompare(finish, "enabled", true)
      tryCompare(finish, "activeFocus", true)
      wait(30)
      var success = findChild(practice, "captureCompletionStatus")
      verify(success.visible)
      var successPoint = success.mapToItem(practice, 0, 0)
      var finishPoint = finish.mapToItem(practice, 0, 0)
      verify(successPoint.y >= 0 && successPoint.y + success.height <= finishPoint.y)
      verify(finish.y + finish.height <= practice.height)
      compare(findChild(practice, "confirmCapture"), null)
      compare(root.button(practice, "Copy saved image path"), null)
      compare(findChild(practice, "captureAnnotation"), null)
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
    function test_recordingUsesNativeStartStopAndRequiresPlayback() {
      practice.mode = "screen-recording"
      var play = findChild(practice, "playOutput")
      verify(!play.visible)
      compare(practice.currentKeyGuides[0].label,
        "Open Capture, choose Screenrecord, then With no audio")
      practice.observeRecordingStarted()
      compare(practice.stage, 1)
      verify(practice.recording)
      compare(practice.currentKeyGuides[0].label,
        "Open Capture, then choose Stop Screenrecording")
      verify(!play.visible)
      verify(!practice.verified)
      practice.observeRecordingSaved("/nonexistent/recording.mp4")
      verify(!practice.recording)
      verify(play.visible)
      compare(practice.currentKeyGuides.length, 0)
      verify(!practice.verified, "A saved path without successful playback is insufficient")
      play.clicked()
      wait(100)
      verify(!practice.verified, "Playback failure never completes")
      practice.verified = true
      practice.observeRecordingStarted()
      verify(!practice.verified, "Starting a retake invalidates the previous playback")
      verify(!findChild(practice, "finishExercise").enabled)
    }
    function test_ocrAndQrUseNativeCaptureThenRequirePastedSample() {
      practice.mode = "ocr"
      var input = findChild(practice, "exerciseInput")
      verify(input.visible)
      verify(input.enabled)
      verify(!findChild(practice, "reviewRecognized").visible)
      compare(practice.currentKeyGuides.length, 2)
      compare(practice.currentKeyGuides[0].label, "Open Capture, then choose Text")
      practice.observeExercisePaste("wrong text")
      verify(!practice.verified)
      practice.observeExercisePaste("OMARCHY SAFE SAMPLE")
      verify(practice.verified)

      practice.mode = "qr"
      verify(findChild(practice, "prepareSample").visible)
      verify(!findChild(practice, "exerciseInput").visible)
      compare(practice.currentKeyGuides.length, 0)
      practice.handleTaskResult({
        action: "prepare",
        image: Qt.resolvedUrl("../../assets/characters/owl/sprites/owl-idle.png").toString().replace("file://", "")
      })
      verify(!findChild(practice, "prepareSample").visible)
      verify(findChild(practice, "exerciseInput").visible)
      compare(practice.currentKeyGuides.length, 2)
      compare(practice.currentKeyGuides[0].label, "Open Capture, then choose QR Code")
    }
    function test_nativeTextRequiresRealPaste_data() {
      return [{ tag: "ocr", mode: "ocr" }, { tag: "qr", mode: "qr" }]
    }
    function test_nativeTextRequiresRealPaste(data) {
      practice.mode = data.mode
      if (data.mode === "qr") {
        practice.handleTaskResult({
          action: "prepare",
          image: Qt.resolvedUrl("../../assets/characters/owl/sprites/owl-idle.png").toString().replace("file://", "")
        })
      }
      var input = findChild(practice, "exerciseInput")
      input.text = "OMARCHY SAFE SAMPLE"
      verify(!practice.verified, "Typing does not count as a paste")
      clipboardProbe.text = "OMARCHY SAFE SAMPLE"
      clipboardProbe.selectAll()
      clipboardProbe.copy()
      input.clear()
      input.forceActiveFocus()
      keyClick(Qt.Key_V, Qt.ControlModifier)
      tryCompare(practice, "verified", true)
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
