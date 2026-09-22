pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import QtMultimedia
import "ThemeColors.js" as ThemeColors

Rectangle {
  id: root
  color: backgroundColor
  implicitWidth: 760
  implicitHeight: 320
  property string mode: "clipboard"
  property real textScale: 1
  property bool showFooter: true
  property color backgroundColor: ThemeColors.defaults.background
  property color foreground: ThemeColors.defaults.foreground
  property color accent: ThemeColors.defaults.accent
  property color errorColor: ThemeColors.defaults.urgent
  property color muted: Qt.tint(backgroundColor, Qt.rgba(foreground.r, foreground.g, foreground.b, 0.78))
  ThemePalette {
    id: controlPalette
    backgroundColor: root.backgroundColor
    foregroundColor: root.foreground
    accentColor: root.accent
    mutedColor: root.muted
  }
  component PracticePalette: ThemePalette {
    backgroundColor: root.backgroundColor
    foregroundColor: root.foreground
    accentColor: root.accent
    mutedColor: root.muted
  }
  property string sample: "Omarchy practice " + Date.now().toString().slice(-6)
  property string secondSample: "A newer note " + sample
  property bool copiedFirst: false
  property bool copiedSecond: false
  property bool historyOpened: false
  property bool clipboardPasteMismatch: false
  property string clipboardFeedback: ""
  property bool verified: false
  property bool busy: false
  property string status: ""
  property string error: ""
  property string screenshot: ""
  readonly property var exercises: ({
    "compose": ["Type with Compose", "Enter a smile in the first field and a heart in the second. Compose uses separate key presses, not keys held together. Custom mappings may differ; return and skip rather than changing settings."],
    "screen-recording": ["Record, stop, replay", "Select the animated practice card and check the region before starting. Record for at least one second, stop, then play the saved clip. This recording has no sound or webcam footage and won't stop another recorder."],
    "ocr": ["Turn pixels into text", "Select only the sample card and extract its words. OCR (optical character recognition) may make mistakes. Copy the extracted sample, paste it below, and compare it with the card. Requires slurp, grim and tesseract."],
    "qr": ["Read a QR code safely", "Create the harmless sample QR code, select it, and decode it. Copy the decoded text and paste it below to inspect the contents. No links are opened. Requires qrencode, slurp, grim and zbarimg."],
    "dictation": ["Try local dictation", "Check availability, then enable the practice field. Dictate “Omarchy practice,” stop dictation, and review the words. You control the microphone; this exercise doesn't start it. Return and skip if dictation isn't available."],
    "dictation-corrections": ["Practice a dictation correction", "Inspect whether Voxtype's real configuration documents replacements, without displaying or editing it. Then apply a correction to a harmless simulated transcript. If Voxtype or its config is unavailable, the bundled sample teaches the same workflow."],
    "notifications": ["Practice with sample notifications", "Use this lesson-owned notification sample to open history, dismiss the sample, and turn simulated quiet mode on and back off. No desktop notifications are opened, invoked, or dismissed, and your real silencing preference never changes."],
    "web-app": ["Explore a demo web-app entry", "This isolated demo creates an entry only in the exercise folder, not your Apps menu. Explicitly create it, open its local preview, then remove it. Everyday Omarchy: Install Web App asks for a name and URL; Remove Web App removes a launcher, not your account."],
    "transcode": ["Create a smaller media copy", "Generate a harmless silent sample clip, play the original, choose a lower resolution, and convert a separate MP4 copy. Play the output and compare its size and quality. Requires ffmpeg and ffprobe. No original files are changed."],
    "sharing": ["Review before sharing", "Prepare the sample file, read its contents, and choose the intended demo recipient. This rehearsal doesn't discover real devices or send anything. For a real transfer, check that both devices have LocalSend and can reach each other on the network."]
  })
  readonly property var keyGuides: ({
    "compose": [
      { label: "Smile - tap one key at a time", keys: ["CAPS LOCK", "→", "M", "→", "S"] },
      { label: "Heart - tap one key at a time", keys: ["CAPS LOCK", "→", "M", "→", "H"] }
    ],
    "ocr": [
      { label: "Paste the copied text", keys: ["SUPER", "+", "V"] }
    ],
    "qr": [
      { label: "Paste the copied result", keys: ["SUPER", "+", "V"] }
    ],
    "dictation": [
      { label: "Start or stop dictation", keys: ["SUPER", "+", "CTRL", "+", "X"] },
      { label: "Or hold to talk, then release", keys: ["F9"] }
    ],
    "screen-lock": [
      { label: "Lock your screen", keys: ["SUPER", "+", "CTRL", "+", "L"] }
    ],
    "capture": [
      { label: "Open Capture, then choose Screenshot", keys: ["SUPER", "+", "CTRL", "+", "C"] }
    ]
  })
  readonly property var clipboardKeyGuides: !copiedFirst
    ? [{ label: "Copy the selected original note", keys: ["SUPER", "+", "C"] }]
    : !copiedSecond
      ? [{ label: "Copy the selected newer note", keys: ["SUPER", "+", "C"] }]
      : [
        { label: "Open clipboard history", keys: ["SUPER", "+", "CTRL", "+", "V"] },
        { label: "Choose \"" + sample + "\" (not the entry beginning \"A newer note\")", keys: ["SHIFT", "+", "ENTER"] },
        { label: "Paste the original note into the destination", keys: ["SUPER", "+", "V"] }
      ]
  readonly property var currentKeyGuides: mode === "clipboard" ? clipboardKeyGuides : keyGuides[mode] || []
  readonly property bool extendedMode: exercises[mode] !== undefined
  property int stage: 0
  property string artifact: ""
  property string original: ""
  property string region: ""
  property string extracted: ""
  property string qrImage: ""
  property int originalBytes: 0
  property int outputBytes: 0
  property bool recording: false
  property bool consent: false
  property bool originalPlayed: false
  property bool outputPlayed: false
  property bool nativeSamplePasted: false
  property bool simulatedQuiet: false
  property bool simulatedQuietSeen: false
  property bool correctionApplied: false
  onScreenshotChanged: {
    if (mode !== "capture") return
    verified = false
  }
  signal taskRequested(string action, var options)
  signal lockRequested()
  signal finished()
  signal cancelled()

  function stopPlayback() {
    player.stop()
  }

  function focusPractice() {
    if (mode === "compose") smile.forceActiveFocus()
    else if (mode === "clipboard") {
      first.forceActiveFocus()
      first.selectAll()
    }
    else if (exerciseInput.visible && exerciseInput.enabled) exerciseInput.forceActiveFocus()
    else {
      for (var child of bodyColumn.children) {
        if (child.visible && child.enabled && ("clicked" in child || child.activeFocusOnTab === true)) {
          child.forceActiveFocus()
          return
        }
      }
      if (showFooter) cancelButton.forceActiveFocus()
    }
  }

  function resetExercise() {
    if (!player) return
    player.stop()
    verified = false
    busy = false
    status = ""
    error = ""
    stage = 0
    artifact = ""
    original = ""
    region = ""
    extracted = ""
    qrImage = ""
    originalBytes = 0
    outputBytes = 0
    recording = false
    consent = false
    originalPlayed = false
    outputPlayed = false
    nativeSamplePasted = false
    simulatedQuiet = false
    simulatedQuietSeen = false
    correctionApplied = false
    copiedFirst = false
    copiedSecond = false
    historyOpened = false
    clipboardPasteMismatch = false
    clipboardFeedback = ""
    smile.text = ""
    heart.text = ""
    exerciseInput.text = ""
    destination.text = ""
    recipient.currentIndex = 0
    resolution.currentIndex = 0
    correctionChoice.currentIndex = 0
    scrollArea.contentItem.contentY = 0
  }
  onModeChanged: resetExercise()

  function requestTask(action, options) {
    if (busy) return
    busy = true
    error = ""
    status = ""
    taskRequested(action, options || {})
  }

  function focusAndReveal(control) {
    Qt.callLater(function() {
      if (!control || !control.visible || !control.enabled) return
      control.forceActiveFocus()
      Qt.callLater(function() { root.revealControl(control) })
    })
  }

  function handleTaskResult(result) {
    busy = false
    if (result.error) {
      error = result.error
      if (result.action === "stop") { recording = false; stage = 0; region = "" }
      return
    }
    if (result.cancelled) {
      if (result.action === "select") region = ""
      status = "Selection cancelled. Nothing completed; try again."
      return
    }
    if (mode === "screen-recording") {
      if (result.action === "select") {
        region = result.region
        stage = 1
        focusAndReveal(startRecordingButton)
      }
      if (result.action === "start" && result.recording) {
        recording = true
        stage = 2
        focusAndReveal(stopRecordingButton)
      }
      if (result.action === "stop" && result.path) {
        recording = false
        artifact = result.path
        stage = 3
        outputPlayed = false
        focusAndReveal(playOutputButton)
      }
    } else if (mode === "ocr" || mode === "qr") {
      if (result.image) {
        qrImage = result.image
        artifact = result.image
        stage = 1
        focusAndReveal(extractSampleButton)
      }
      if (result.text === "OMARCHY SAFE SAMPLE") {
        extracted = result.text
        artifact = result.path || ""
        nativeSamplePasted = false
        verified = false
        exerciseInput.text = ""
        stage = mode === "qr" ? 2 : 1
        focusAndReveal(copyExtractedButton)
      }
    } else if (mode === "dictation" && result.available) {
      stage = 1
      status = "Voxtype is installed. Availability does not guarantee a configured microphone or running service."
      focusAndReveal(consentDictationButton)
    } else if (mode === "dictation-corrections" && result.action === "inspect") {
      stage = 1
      status = result.source === "config"
        ? (result.replacementsDocumented
          ? "Your Voxtype config documents replacements. It was inspected read-only and its contents were not displayed."
          : "Your Voxtype config exists, but no replacements example was detected. It was not changed; use the bundled sample below.")
        : "Voxtype's config is unavailable. Using the bundled sample; no real config was created or changed."
      focusAndReveal(correctionChoice)
    } else if (mode === "web-app") {
      if (result.action === "create" && result.path) {
        artifact = result.path
        stage = 1
        focusAndReveal(openWebAppButton)
      }
      if (result.action === "open" && result.opened && stage === 1) {
        stage = 2
        focusAndReveal(removeWebAppButton)
      }
      if (result.action === "remove" && result.removed && stage === 2) { stage = 3; verified = true }
    } else if (mode === "transcode") {
      if (result.action === "prepare" && result.path) {
        original = result.path
        originalBytes = result.bytes
        stage = 1
        focusAndReveal(playOriginalButton)
      }
      if (result.action === "convert" && result.path && result.bytes < result.originalBytes) {
        artifact = result.path
        outputBytes = result.bytes
        stage = 2
        outputPlayed = false
        verified = false
        focusAndReveal(playOutputButton)
      }
    } else if (mode === "sharing" && result.path) {
      artifact = result.path
      stage = 1
      focusAndReveal(recipient)
    }
  }

  function observeExercisePaste(text) {
    if ((mode === "ocr" || mode === "qr") && extracted === "OMARCHY SAFE SAMPLE" && text.trim() === extracted)
      nativeSamplePasted = true
  }

  function checkCompose() {
    if (mode === "compose") verified = smile.text.trim() === "😄" && heart.text.trim().replace(/\uFE0F/g, "") === "❤"
  }

  function playMedia(path) {
    error = ""
    player.stop()
    player.source = "file://" + path
    player.play()
    videoPreview.forceActiveFocus()
    scheduleReveal(videoPreview)
  }

  MediaPlayer {
    id: player
    videoOutput: videoPreview
    onPositionChanged: {
      if (playbackState !== MediaPlayer.PlayingState || position < 250) return
      if (source.toString() === "file://" + root.original) root.originalPlayed = true
      if (source.toString() === "file://" + root.artifact) {
        root.outputPlayed = true
        if (root.mode === "screen-recording" && root.stage === 3) root.verified = true
      }
    }
    onErrorOccurred: function(error, errorString) { root.error = "Playback failed: " + errorString }
  }

  function observeCopy(first, selected) {
    if (first && selected === sample) {
      copiedFirst = true
      copiedSecond = false
      historyOpened = false
      clipboardPasteMismatch = false
      clipboardFeedback = ""
      verified = false
      Qt.callLater(function() {
        second.forceActiveFocus()
        second.selectAll()
        root.revealControl(second)
      })
    }
    if (!first && copiedFirst && selected === secondSample) {
      copiedSecond = true
      historyOpened = false
      clipboardPasteMismatch = false
      clipboardFeedback = ""
      verified = false
      Qt.callLater(function() {
        Qt.callLater(function() { root.revealControlFromTop(practiceKeyGuideList) })
      })
    }
  }
  function observeHistory() {
    if (copiedSecond) historyOpened = true
  }
  function observePaste(text) {
    if (!copiedFirst || !copiedSecond || !historyOpened) return
    if (text === sample) {
      clipboardPasteMismatch = false
      clipboardFeedback = ""
      verified = true
      return
    }

    clipboardPasteMismatch = true
    clipboardFeedback = text === secondSample
      ? "The newer note was pasted. Reopen clipboard history and choose \"" + sample + "\" instead."
      : "That isn't the complete original note. Use the three highlighted steps, then paste again."
    verified = false
    Qt.callLater(function() {
      destination.forceActiveFocus()
      destination.selectAll()
      root.revealControl(clipboardFeedbackText)
    })
  }

  function revealControl(control) {
    var ancestor = control.parent
    while (ancestor && ancestor !== bodyColumn) ancestor = ancestor.parent
    if (!ancestor) return
    var flickable = scrollArea.contentItem
    var point = control.mapToItem(bodyColumn, 0, 0)
    var nextY = flickable.contentY
    if (point.y < nextY + 12) nextY = point.y - 12
    else if (point.y + control.height > nextY + flickable.height - 12) nextY = point.y + control.height - flickable.height + 12
    flickable.contentY = Math.max(0, Math.min(Math.max(0, flickable.contentHeight - flickable.height), nextY))
  }

  function revealControlFromTop(control) {
    var flickable = scrollArea.contentItem
    var point = control.mapToItem(bodyColumn, 0, 0)
    flickable.contentY = Math.max(0, Math.min(Math.max(0, flickable.contentHeight - flickable.height),
      point.y + 20 * root.textScale))
  }

  function scheduleReveal(control) {
    revealTimer.control = control
    revealTimer.restart()
  }

  Timer {
    id: revealTimer
    property var control: null
    interval: 16
    onTriggered: if (control && control.activeFocus) root.revealControl(control)
  }

  function captureCardGeometry() {
    var position = captureCard.mapToItem(root, 0, 0)
    return { x: position.x, y: position.y, width: captureCard.width, height: captureCard.height }
  }

  Shortcut {
    sequence: "Escape"
    enabled: root.enabled && root.visible && root.mode !== "capture"
    onActivated: root.cancelled()
  }

  component PracticeButton: Controls.Button {
    id: control
    PracticePalette { target: control }
    property bool primary: false
    onActiveFocusChanged: if (activeFocus) root.scheduleReveal(control)
    font.pixelSize: 15 * root.textScale
    leftPadding: 16
    rightPadding: 16
    topPadding: 10
    bottomPadding: 10
    implicitHeight: Math.max(44, contentItem.implicitHeight + 20)
    contentItem: Text {
      text: control.text
      font: control.font
      color: !control.enabled ? controlPalette.disabled.buttonText
        : control.primary ? controlPalette.highlightedText : controlPalette.buttonText
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      wrapMode: Text.WordWrap
    }
    background: Rectangle {
      radius: 8
      color: !control.enabled ? root.backgroundColor : control.primary ? root.accent : controlPalette.button
      border.width: control.activeFocus || control.hovered ? 2 : 1
      border.color: control.activeFocus ? root.foreground : control.enabled ? root.accent : controlPalette.secondaryText
    }
  }

  component NoteArea: Controls.TextArea {
    id: control
    PracticePalette { target: control }
    onActiveFocusChanged: if (activeFocus) root.scheduleReveal(control)
    font.pixelSize: 16 * root.textScale
    implicitHeight: Math.max(76 * root.textScale, contentHeight + topPadding + bottomPadding)
    Layout.minimumHeight: 76 * root.textScale
    leftPadding: 16 * root.textScale
    rightPadding: 16 * root.textScale
    topPadding: 14 * root.textScale
    bottomPadding: 14 * root.textScale
    color: enabled ? controlPalette.text : controlPalette.disabled.text
    placeholderTextColor: controlPalette.placeholderText
    selectionColor: root.accent
    selectedTextColor: controlPalette.highlightedText
    background: Rectangle {
      radius: 10
      color: Qt.tint(controlPalette.base, Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04))
      border.width: control.activeFocus ? 3 : 2
      border.color: control.activeFocus ? root.accent : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.68)
    }
  }

  component PracticeKeycap: Item {
    id: keycap
    required property string label
    readonly property bool separator: label === "+" || label === "→"

    implicitWidth: separator ? 20 * root.textScale : keyText.implicitWidth + 24 * root.textScale
    implicitHeight: separator ? 42 * root.textScale : 46 * root.textScale

    Rectangle {
      visible: !keycap.separator
      anchors.fill: parent
      radius: 8
      color: Qt.tint(root.backgroundColor, Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.28))
    }
    Rectangle {
      visible: !keycap.separator
      anchors.fill: parent
      anchors.bottomMargin: 4 * root.textScale
      radius: 8
      color: controlPalette.button
      border.width: 1
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.24)
    }
    Text {
      id: keyText
      anchors.centerIn: parent
      anchors.verticalCenterOffset: keycap.separator ? 0 : -2 * root.textScale
      text: keycap.label
      color: keycap.separator ? root.muted : root.foreground
      font.family: "monospace"
      font.pixelSize: (keycap.separator ? 18 : 14) * root.textScale
      font.bold: true
    }
  }

  component PracticeComboBox: Controls.ComboBox {
    id: control
    PracticePalette { target: control }
    PracticePalette { target: control.popup }
    delegate: Controls.ItemDelegate {
      id: option
      required property int index
      required property var modelData
      width: control.width
      text: modelData
      font: control.font
      highlighted: control.highlightedIndex === index
      PracticePalette { target: option }
      contentItem: Text {
        text: option.text
        font: option.font
        color: option.highlighted ? controlPalette.highlightedText : controlPalette.text
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
      }
      background: Rectangle {
        color: option.highlighted ? controlPalette.highlight : controlPalette.base
      }
    }
  }

  ColumnLayout {
    anchors.centerIn: parent
    width: Math.max(0, Math.min(parent.width - 32, 900 * root.textScale))
    height: Math.max(0, parent.height - 24)
    spacing: 10
    Text {
      Layout.fillWidth: true
      text: root.extendedMode ? root.exercises[root.mode][0] : root.mode === "clipboard" ? "Copy, retrieve, paste"
        : root.mode === "capture" ? "Capture a practice card"
        : root.mode === "screen-lock" ? "Lock safely, then return"
        : "Unsupported practice activity"
      color: root.foreground
      font.pixelSize: 22 * root.textScale
      font.bold: true
      wrapMode: Text.WordWrap
    }
    Rectangle {
      id: nativePracticeSample
      objectName: "nativePracticeSample"
      visible: ["screen-recording", "ocr"].indexOf(root.mode) !== -1
      Layout.fillWidth: true
      implicitHeight: Math.min(130, root.height / 4)
      color: "white"
      Text {
        anchors.centerIn: parent
        text: "OMARCHY SAFE SAMPLE"
        color: "black"
        font.pixelSize: 22
      }
      Rectangle {
        visible: root.mode === "screen-recording"
        y: parent.height - height - 6
        width: 20
        height: 20
        color: root.accent
        SequentialAnimation on x {
          running: root.mode === "screen-recording"
          loops: Animation.Infinite
          NumberAnimation { from: 0; to: 240; duration: 1200 }
          NumberAnimation { from: 240; to: 0; duration: 1200 }
        }
      }
    }
    Controls.ScrollView {
      id: scrollArea
      objectName: "practiceScroll"
      clip: true
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Tab && event.modifiers === Qt.NoModifier &&
            scrollArea.Window.window && scrollArea.Window.window.activeFocusItem === scrollArea) {
          root.focusPractice()
          event.accepted = true
        }
      }
      PracticePalette { target: scrollArea }
      Controls.ScrollBar.vertical: Controls.ScrollBar {
        id: verticalScrollBar
        PracticePalette { target: verticalScrollBar }
      }
      Controls.ScrollBar.horizontal: Controls.ScrollBar {
        id: horizontalScrollBar
        PracticePalette { target: horizontalScrollBar }
      }
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.minimumHeight: 0
      contentWidth: availableWidth
      ColumnLayout {
        id: bodyColumn
        width: scrollArea.availableWidth
        spacing: 12
        ColumnLayout {
          id: practiceKeyGuideList
          objectName: "practiceKeyGuideList"
          visible: root.currentKeyGuides.length > 0
          Layout.fillWidth: true
          spacing: 8 * root.textScale

          Text {
            Layout.fillWidth: true
            text: "KEYS YOU'LL USE"
            color: root.accent
            font.pixelSize: 13 * root.textScale
            font.bold: true
            font.letterSpacing: 1.2 * root.textScale
          }
          ColumnLayout {
            Layout.fillWidth: true
            spacing: 8 * root.textScale

            Repeater {
              model: root.currentKeyGuides.length
              delegate: Rectangle {
                id: keyGuide
                required property int index
                readonly property var modelData: root.currentKeyGuides[index]
                objectName: "practiceKeyGuide" + index
                readonly property string guideLabel: modelData.label
                readonly property var guideKeys: modelData.keys
                Layout.fillWidth: true
                implicitHeight: keyGuideContent.implicitHeight + 20 * root.textScale
                radius: 10
                color: Qt.tint(root.backgroundColor, Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.12))
                border.width: 1
                border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.42)
                Accessible.role: Accessible.StaticText
                Accessible.name: guideLabel + ": " + guideKeys.join(" ")

                ColumnLayout {
                  id: keyGuideContent
                  anchors.fill: parent
                  anchors.margins: 10 * root.textScale
                  spacing: 7 * root.textScale
                  Text {
                    Layout.fillWidth: true
                    text: keyGuide.guideLabel
                    color: root.foreground
                    font.pixelSize: 15 * root.textScale
                    font.bold: true
                    wrapMode: Text.WordWrap
                  }
                  Row {
                    spacing: 5 * root.textScale
                    Repeater {
                      model: keyGuide.guideKeys
                      PracticeKeycap {
                        required property string modelData
                        label: modelData
                      }
                    }
                  }
                }
              }
            }
          }
        }
        Text {
          objectName: "exerciseInstructions"
          visible: root.mode !== "clipboard"
          Layout.fillWidth: true
          text: root.mode === "capture"
            ? "Choose Screenshot, then drag around only the practice card below. Print opens the picker directly on keyboards that have it. Escape cancels region selection."
            : root.mode === "screen-recording"
            ? (root.stage === 0
              ? "Select the animated practice card below."
              : root.stage === 1
              ? "The region is selected. Start the silent recording when you're ready."
              : root.stage === 2
              ? "Record for at least one second, then stop the recording."
              : "Play the saved recording to finish.")
            : root.mode === "ocr"
            ? (root.extracted === ""
              ? "Select the sample card to extract its text."
              : "Copy the recognized text, paste it below, and confirm that it matches.")
            : root.mode === "qr"
            ? (root.qrImage === ""
              ? "Create a harmless sample QR code."
              : root.extracted === ""
              ? "Select the QR code to decode it."
              : "Copy the decoded text, paste it below, and confirm that it matches.")
            : root.exercises[root.mode] ? root.exercises[root.mode][1] : root.mode === "clipboard"
            ? ""
            : root.mode === "screen-lock"
            ? "Locking doesn't suspend your computer. Save your work and make sure you know your password. Lock now is optional and requires your explicit click. After unlocking, return here."
            : "Return to your coach and choose another activity."
          color: root.muted
          wrapMode: Text.WordWrap
          font.pixelSize: (root.mode === "capture" ? 14 : 16) * root.textScale
        }
        NoteArea {
          id: smile
          objectName: "composeSmile"
          visible: root.mode === "compose"
          Layout.fillWidth: true
          placeholderText: "Smile appears here"
          Accessible.name: "Compose a smile"
          KeyNavigation.priority: KeyNavigation.BeforeItem
          KeyNavigation.tab: heart
          onTextChanged: root.checkCompose()
        }
        NoteArea {
          id: heart
          objectName: "composeHeart"
          visible: root.mode === "compose"
          Layout.fillWidth: true
          placeholderText: "Heart appears here"
          Accessible.name: "Compose a heart"
          KeyNavigation.priority: KeyNavigation.BeforeItem
          KeyNavigation.tab: cancelButton
          KeyNavigation.backtab: smile
          onTextChanged: root.checkCompose()
        }
        PracticeButton {
          objectName: "prepareSample"
          visible: ["qr", "transcode", "sharing"].indexOf(root.mode) !== -1 && root.stage === 0
          enabled: visible && !root.busy && root.qrImage === ""
          text: "Prepare harmless sample"
          onClicked: root.requestTask("prepare")
        }
        Image {
          objectName: "sampleQr"
          visible: root.mode === "qr" && root.qrImage !== "" && root.extracted === ""
          Layout.fillWidth: true
          Layout.preferredHeight: Math.max(64, Math.min(200,
            scrollArea.availableHeight - extractSampleButton.implicitHeight - bodyColumn.spacing - 24))
          source: root.qrImage ? "file://" + root.qrImage : ""
          fillMode: Image.PreserveAspectFit
          smooth: false
          Accessible.name: "Harmless sample QR code"
        }
        PracticeButton {
          id: extractSampleButton
          objectName: "extractSample"
          visible: (root.mode === "ocr" && root.extracted === "")
            || (root.mode === "qr" && root.qrImage !== "" && root.extracted === "")
          enabled: visible && !root.busy
          primary: true
          text: root.mode === "ocr" ? "Extract text from the card" : "Decode the QR code"
          onClicked: root.requestTask("extract")
        }
        NoteArea {
          id: extractedText
          visible: root.extracted !== ""
          Layout.fillWidth: true
          text: root.extracted
          readOnly: true
          selectByMouse: true
          Accessible.name: "Recognized sample text"
        }
        PracticeButton {
          id: copyExtractedButton
          objectName: "copyExtracted"
          visible: root.extracted !== ""
          primary: true
          text: root.mode === "qr" ? "Copy decoded text" : "Copy recognized text"
          onClicked: { extractedText.selectAll(); extractedText.copy(); exerciseInput.forceActiveFocus() }
        }
        PracticeButton {
          objectName: "checkDictation"
          visible: root.mode === "dictation"
          enabled: !root.busy && root.stage === 0
          text: "Check dictation availability"
          onClicked: root.requestTask("check")
        }
        PracticeButton {
          objectName: "inspectDictationCorrections"
          visible: root.mode === "dictation-corrections"
          enabled: !root.busy && root.stage === 0
          text: "Inspect config availability (read only)"
          onClicked: root.requestTask("inspect")
        }
        Text {
          visible: root.mode === "dictation-corrections" && root.stage >= 1
          Layout.fillWidth: true
          text: "Simulated transcript: “Run cube control get pods.”\nChoose the specific recurring correction that would turn only “cube control” into “kubectl”."
          color: root.foreground
          wrapMode: Text.WordWrap
          font.pixelSize: 16 * root.textScale
        }
        PracticeComboBox {
          id: correctionChoice
          objectName: "dictationCorrectionChoice"
          visible: root.mode === "dictation-corrections" && root.stage >= 1
          Layout.fillWidth: true
          model: ["Choose a replacement", "cube control → kubectl", "control → ctl", "run → execute"]
          Accessible.name: "Dictation replacement"
          onCurrentIndexChanged: {
            if (root.mode === "dictation-corrections") {
              root.correctionApplied = false
              root.verified = false
            }
          }
        }
        PracticeButton {
          objectName: "applyDictationCorrection"
          visible: root.mode === "dictation-corrections" && root.stage >= 1
          enabled: correctionChoice.currentIndex > 0 && !root.correctionApplied
          text: "Apply to simulated transcript"
          onClicked: {
            root.correctionApplied = true
            if (correctionChoice.currentIndex === 1) {
              root.verified = true
              root.status = "Corrected sample: “Run kubectl get pods.” Your real Voxtype config remains unchanged."
            } else {
              root.verified = false
              root.status = "That replacement is too broad or changes the wrong word. Choose the specific recurring phrase."
            }
          }
        }
        PracticeButton {
          id: consentDictationButton
          objectName: "consentDictation"
          visible: root.mode === "dictation" && root.stage >= 1
          enabled: !root.consent && !root.verified
          text: "I'm ready to use my microphone with the shortcut"
          onClicked: { root.consent = true; exerciseInput.forceActiveFocus() }
        }
        NoteArea {
          id: exerciseInput
          objectName: "exerciseInput"
          visible: root.mode === "dictation"
            || (["ocr", "qr"].indexOf(root.mode) !== -1 && root.extracted !== "")
          enabled: root.mode === "dictation" ? root.consent : root.extracted !== ""
          Layout.fillWidth: true
          wrapMode: TextEdit.Wrap
          placeholderText: root.mode === "dictation" ? "Dictate: Omarchy practice" : "Paste the recognized sample here"
          Accessible.name: placeholderText
          KeyNavigation.priority: KeyNavigation.BeforeItem
          KeyNavigation.tab: reviewRecognized.enabled ? reviewRecognized : cancelButton
          onTextChanged: { root.nativeSamplePasted = false; root.verified = false }
          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            if (event.matches(StandardKey.Paste)) Qt.callLater(function() { root.observeExercisePaste(exerciseInput.text) })
            event.accepted = false
          }
        }
        PracticeButton {
          id: reviewRecognized
          objectName: "reviewRecognized"
          visible: root.mode === "dictation"
            || (["ocr", "qr"].indexOf(root.mode) !== -1 && root.extracted !== "")
          enabled: !root.verified && (root.mode === "dictation"
            ? root.consent && /^omarchy practice[.!]?$/i.test(exerciseInput.text.trim())
            : root.nativeSamplePasted)
          text: root.mode === "dictation" ? "I stopped dictation and proofread the words" : "The pasted words match the sample"
          onClicked: { root.verified = true; root.status = "Reviewed locally. Nothing sent." }
        }
        PracticeButton {
          objectName: "selectRecording"
          visible: root.mode === "screen-recording" && root.stage === 0
          enabled: visible && !root.busy
          primary: true
          text: "Select the practice card"
          onClicked: root.requestTask("select")
        }
        PracticeButton {
          id: startRecordingButton
          objectName: "startRecording"
          visible: root.mode === "screen-recording" && root.stage === 1
          enabled: visible && !root.busy && root.region !== ""
          primary: true
          text: "Start recording"
          onClicked: root.requestTask("start")
        }
        PracticeButton {
          id: stopRecordingButton
          objectName: "stopRecording"
          visible: root.mode === "screen-recording" && root.stage === 2
          enabled: visible && !root.busy && root.recording
          primary: true
          text: "Stop recording"
          onClicked: root.requestTask("stop")
        }
        PracticeButton {
          id: playOriginalButton
          objectName: "playOriginal"
          visible: root.mode === "transcode"
          enabled: root.original !== "" && !root.busy
          text: "Play original sample"
          onClicked: root.playMedia(root.original)
        }
        PracticeComboBox {
          id: resolution
          objectName: "outputResolution"
          visible: root.mode === "transcode"
          Layout.fillWidth: true
          model: ["Choose output resolution", "240p", "180p"]
          Accessible.name: "Output resolution"
          onActiveFocusChanged: if (activeFocus) root.scheduleReveal(resolution)
        }
        PracticeButton {
          objectName: "convertSample"
          visible: root.mode === "transcode"
          enabled: root.originalPlayed && resolution.currentIndex > 0 && !root.busy
          text: "Create a smaller MP4 copy"
          onClicked: root.requestTask("convert", { height: resolution.currentIndex === 1 ? 240 : 180 })
        }
        VideoOutput {
          id: videoPreview
          objectName: "practiceVideo"
          KeyNavigation.priority: KeyNavigation.BeforeItem
          KeyNavigation.tab: root.mode === "transcode" ? resolution : cancelButton
          visible: ["screen-recording", "transcode"].indexOf(root.mode) !== -1 && (root.original !== "" || root.artifact !== "")
          Layout.fillWidth: true
          Layout.preferredHeight: 170
          Accessible.name: "Saved practice clip playback"
        }
        PracticeButton {
          id: playOutputButton
          objectName: "playOutput"
          visible: (root.mode === "screen-recording" && root.stage === 3 && root.artifact !== "")
            || root.mode === "transcode"
          enabled: root.artifact !== "" && !root.busy
          primary: root.mode === "screen-recording"
          text: root.mode === "screen-recording" ? "Play recording" : "Play saved output"
          onClicked: root.playMedia(root.artifact)
        }
        Text {
          visible: root.mode === "transcode" && root.outputBytes > 0
          Layout.fillWidth: true
          text: "Original: " + root.originalBytes + " bytes. Smaller copy: " + root.outputBytes + " bytes. Compare picture quality before sharing."
          color: root.foreground
          wrapMode: Text.WordWrap
          font.pixelSize: 16 * root.textScale
        }
        PracticeButton {
          objectName: "reviewTranscode"
          visible: root.mode === "transcode"
          enabled: root.originalPlayed && root.outputPlayed && root.outputBytes > 0 && root.outputBytes < root.originalBytes
          text: "I compared the original and smaller copy"
          onClicked: root.verified = true
        }
        PracticeButton {
          objectName: "createWebApp"
          visible: root.mode === "web-app"
          enabled: root.stage === 0 && !root.busy
          text: "Create isolated demo entry (not installed)"
          onClicked: root.requestTask("create")
        }
        PracticeButton {
          id: openWebAppButton
          objectName: "openWebApp"
          visible: root.mode === "web-app"
          enabled: root.stage === 1 && !root.busy
          text: "Open local demo preview"
          onClicked: root.requestTask("open")
        }
        Text {
          visible: root.mode === "web-app" && root.stage === 2
          Layout.fillWidth: true
          text: "Omarchy practice demo\nURL: https://example.org\nThis local preview makes no network request. A real web app opens its URL in a browser window."
          color: root.foreground
          font.pixelSize: 16 * root.textScale
          wrapMode: Text.WordWrap
        }
        PracticeButton {
          id: removeWebAppButton
          objectName: "removeWebApp"
          visible: root.mode === "web-app"
          enabled: root.stage === 2 && !root.busy
          text: "Remove my demo entry"
          onClicked: root.requestTask("remove")
        }
        Text {
          visible: root.mode === "sharing" && root.stage === 1
          Layout.fillWidth: true
          text: "share-note.txt\nOMARCHY SAFE SAMPLE\nA harmless practice note. No private information."
          color: root.foreground
          font.pixelSize: 16 * root.textScale
          wrapMode: Text.WordWrap
        }
        PracticeComboBox {
          id: recipient
          objectName: "shareRecipient"
          visible: root.mode === "sharing"
          enabled: root.stage === 1
          Layout.fillWidth: true
          model: ["Choose intended demo recipient", "My test phone (demo)", "Unknown nearby device (demo)"]
          Accessible.name: "Intended recipient"
          onActiveFocusChanged: if (activeFocus) root.scheduleReveal(recipient)
          onCurrentIndexChanged: if (root.mode === "sharing") root.verified = false
        }
        PracticeButton {
          objectName: "reviewShare"
          visible: root.mode === "sharing"
          enabled: root.stage === 1 && recipient.currentIndex === 1
          text: "I've checked the file and demo recipient. Don't send anything."
          onClicked: { root.verified = true; root.status = "Preparation reviewed. No transfer attempted or delivery confirmed." }
        }
        PracticeButton {
          objectName: "showSampleNotification"
          visible: root.mode === "notifications"
          enabled: root.stage === 0
          text: "Show lesson-owned sample notification"
          onClicked: { root.stage = 1; root.status = "Sample ready. This is inside the lesson, not your desktop notification service." }
        }
        Rectangle {
          visible: root.mode === "notifications" && root.stage >= 1 && root.stage < 3
          Layout.fillWidth: true
          implicitHeight: 86
          radius: 8
          color: Qt.tint(root.backgroundColor, Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16))
          Text {
            anchors.fill: parent
            anchors.margins: 12
            text: "Learn Omarchy sample\nBackup finished — harmless practice message"
            color: root.foreground
            wrapMode: Text.WordWrap
            font.pixelSize: 16 * root.textScale
          }
        }
        PracticeButton {
          objectName: "openSampleNotificationHistory"
          visible: root.mode === "notifications"
          enabled: root.stage === 1
          text: "Open sample history"
          onClicked: { root.stage = 2; root.status = "Sample history opened. Your real history was not read." }
        }
        PracticeButton {
          objectName: "dismissSampleNotification"
          visible: root.mode === "notifications"
          enabled: root.stage === 2
          text: "Dismiss only the lesson sample"
          onClicked: { root.stage = 3; root.status = "Lesson sample dismissed. No real notification was touched." }
        }
        PracticeButton {
          objectName: "toggleSampleQuiet"
          visible: root.mode === "notifications" && root.stage >= 3
          enabled: !root.verified
          text: root.simulatedQuiet ? "Turn simulated quiet mode off" : "Turn simulated quiet mode on"
          onClicked: {
            root.simulatedQuiet = !root.simulatedQuiet
            if (root.simulatedQuiet) {
              root.simulatedQuietSeen = true
              root.status = "Simulated quiet mode is on. Your desktop preference is unchanged; now turn the simulation off."
            } else if (root.simulatedQuietSeen) {
              root.verified = true
              root.status = "Simulation restored to alerts on. Your real notification settings never changed."
            }
          }
        }
        Text {
          visible: root.artifact !== "" || root.original !== ""
          Layout.fillWidth: true
          text: root.original + (root.original ? "\n" : "") + root.artifact
          wrapMode: Text.WrapAnywhere
          color: root.muted
          font.pixelSize: 14 * root.textScale
        }
        NoteArea {
          id: first
          objectName: "firstNote"
          visible: root.mode === "clipboard" && !root.copiedFirst
          Layout.fillWidth: true
          text: root.sample
          readOnly: true
          selectByMouse: true
          wrapMode: TextEdit.Wrap
          Accessible.name: "Original practice note"
          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            if (event.matches(StandardKey.Copy)) {
              var selected = selectedText
              Qt.callLater(function() { root.observeCopy(true, selected) })
            }
            event.accepted = false
          }
        }
        Text {
          visible: root.mode === "clipboard" && root.copiedFirst
          Layout.fillWidth: true
          text: "✓ Original note copied"
          color: root.foreground
          font.pixelSize: 15 * root.textScale
        }
        NoteArea {
          id: second
          objectName: "secondNote"
          visible: root.mode === "clipboard" && root.copiedFirst && !root.copiedSecond
          enabled: root.copiedFirst
          Layout.fillWidth: true
          text: root.secondSample
          readOnly: true
          selectByMouse: true
          wrapMode: TextEdit.Wrap
          Accessible.name: "Newer practice note"
          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            if (event.matches(StandardKey.Copy)) {
              var selected = selectedText
              Qt.callLater(function() { root.observeCopy(false, selected) })
            }
            event.accepted = false
          }
        }
        Text {
          visible: root.mode === "clipboard" && root.copiedSecond
          Layout.fillWidth: true
          text: "✓ Newer note copied"
          color: root.foreground
          font.pixelSize: 15 * root.textScale
        }
        NoteArea {
          id: destination
          objectName: "pasteDestination"
          visible: root.mode === "clipboard" && root.copiedSecond
          enabled: root.copiedSecond
          Layout.fillWidth: true
          placeholderText: "Paste the original note here"
          selectByMouse: true
          wrapMode: TextEdit.Wrap
          Accessible.name: "Paste the original note after copying it with Shift+Enter"
          KeyNavigation.priority: KeyNavigation.BeforeItem
          KeyNavigation.tab: cancelButton
          KeyNavigation.backtab: scrollArea
          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            if (event.matches(StandardKey.Paste)) Qt.callLater(function() { root.observePaste(destination.text) })
            event.accepted = false
          }
        }
        Text {
          id: clipboardFeedbackText
          objectName: "clipboardFeedback"
          visible: root.mode === "clipboard" && root.clipboardFeedback !== ""
          Layout.fillWidth: true
          text: root.clipboardFeedback
          color: root.errorColor
          font.pixelSize: 15 * root.textScale
          font.weight: Font.DemiBold
          wrapMode: Text.WordWrap
          Accessible.role: Accessible.AlertMessage
          Accessible.name: text
        }
        Rectangle {
          id: captureCard
          visible: root.mode === "capture"
          Layout.fillWidth: true
          implicitHeight: 150
          radius: 12
          color: Qt.tint(root.backgroundColor, Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18))
          Text {
            anchors.centerIn: parent
            width: parent.width - 24
            text: "MY FIRST OMARCHY CAPTURE\nA harmless practice card"
            color: root.foreground
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 21 * root.textScale
          }
        }
        Image {
          id: preview
          Accessible.name: "Captured practice card"
          visible: root.mode === "capture" && root.screenshot !== ""
          Layout.fillWidth: true
          Layout.preferredHeight: visible ? 160 : 0
          source: root.screenshot ? "file://" + root.screenshot : ""
          fillMode: Image.PreserveAspectFit
          onStatusChanged: {
            if (status === Image.Ready && sourceSize.width > 0 && sourceSize.height > 0) {
              root.verified = true
              root.status = "Screenshot captured. Choose Finish exercise to return to your coach."
              root.focusAndReveal(finishButton)
            }
            if (status === Image.Error) {
              root.verified = false
              root.error = "The capture couldn't be opened. Select a region again."
            }
          }
        }
        PracticeButton {
          visible: root.mode === "screen-lock"
          enabled: !root.busy && !root.verified
          text: "Lock this computer now"
          onClicked: root.lockRequested()
        }
        Text {
          visible: !(root.mode === "capture" && root.verified)
          Layout.fillWidth: true
          text: root.verified ? (root.mode === "sharing" ? "Sharing review complete. Nothing sent; delivery isn't confirmed."
            : root.mode === "dictation" ? "Text review complete. Microphone use wasn't checked."
            : root.mode === "dictation-corrections" ? "Correction practiced. Your real config was not edited."
            : root.mode === "notifications" ? "Sample notification workflow complete. Real notification state is unchanged."
            : "Exercise complete. Choose Finish exercise to return to your coach.") : root.status
          color: root.verified ? root.accent : root.foreground
          wrapMode: Text.WordWrap
          font.pixelSize: 16 * root.textScale
        }
        Text {
          visible: root.error !== ""
          Layout.fillWidth: true
          text: root.error
          color: root.errorColor
          font.pixelSize: 16 * root.textScale
          wrapMode: Text.WordWrap
        }
      }
    }
    Text {
      id: captureCompletionStatus
      objectName: "captureCompletionStatus"
      visible: root.mode === "capture" && root.verified
      Layout.fillWidth: true
      Layout.minimumHeight: visible ? implicitHeight : 0
      text: "Screenshot captured. Select Finish exercise."
      color: root.accent
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      font.pixelSize: 15 * root.textScale
      font.weight: Font.DemiBold
      Accessible.role: Accessible.AlertMessage
      Accessible.name: text
    }
    GridLayout {
      id: footerActions
      objectName: "practiceFooterActions"
      visible: root.showFooter
      Layout.alignment: Qt.AlignHCenter
      columns: root.width < 620 * root.textScale ? 1 : 2
      columnSpacing: 12
      rowSpacing: 10
      PracticeButton {
        id: cancelButton
        objectName: "returnWithoutCompleting"
        Layout.preferredWidth: Math.min(280 * root.textScale, root.width - 32)
        text: "Return without completing"
        KeyNavigation.priority: KeyNavigation.BeforeItem
        KeyNavigation.tab: finishButton.enabled ? finishButton : scrollArea
        onClicked: root.cancelled()
      }
      PracticeButton {
        id: finishButton
        objectName: "finishExercise"
        Layout.preferredWidth: Math.min(280 * root.textScale, root.width - 32)
        primary: true
        text: "Finish exercise"
        enabled: root.verified && !root.busy
        KeyNavigation.priority: KeyNavigation.BeforeItem
        KeyNavigation.backtab: cancelButton
        onClicked: root.finished()
      }
    }
  }
}
