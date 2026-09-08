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
  implicitHeight: 620
  property string mode: "clipboard"
  property real textScale: 1
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
  property bool verified: false
  property bool busy: false
  property string status: ""
  property string error: ""
  property string screenshot: ""
  readonly property var exercises: ({
    "compose": ["Type with Compose", "Tap and release Caps Lock, then m, then s for 😄. In the second field, tap Caps Lock, m, h for ❤️. Do not hold the keys together. Custom Compose mappings may differ; return and skip rather than changing settings."],
    "screen-recording": ["Record, stop, replay", "Select the animated practice card and check the region before starting. Record for at least one second, stop, then play the saved clip. This recording has no sound or webcam footage and won't stop another recorder."],
    "ocr": ["Turn pixels into text", "Select only the sample card and extract its words. OCR (optical character recognition) may make mistakes. Copy the extracted sample, paste it below, and compare it with the card. Requires slurp, grim and tesseract."],
    "qr": ["Read a QR code safely", "Create the harmless sample QR code, select it, and decode it. Copy the decoded text and paste it below to inspect the contents. No links are opened. Requires qrencode, slurp, grim and zbarimg."],
    "dictation": ["Try local dictation", "Check availability, then enable the practice field. Use Super+Ctrl+X to start and stop dictation, or hold F9 while speaking. Try “Omarchy practice,” then stop and review the words. You control the microphone; this exercise doesn't start it. Return and skip if dictation isn't available."],
    "web-app": ["Explore a demo web-app entry", "This isolated demo creates an entry only in the exercise folder, not your Apps menu. Explicitly create it, open its local preview, then remove it. Everyday Omarchy: Install Web App asks for a name and URL; Remove Web App removes a launcher, not your account."],
    "transcode": ["Create a smaller media copy", "Generate a harmless silent sample clip, play the original, choose a lower resolution, and convert a separate MP4 copy. Play the output and compare its size and quality. Requires ffmpeg and ffprobe. No original files are changed."],
    "sharing": ["Review before sharing", "Prepare the sample file, read its contents, and choose the intended demo recipient. This rehearsal doesn't discover real devices or send anything. For a real transfer, check that both devices have LocalSend and can reach each other on the network."]
  })
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
  property bool captureCopied: false
  property bool captureEdited: false
  onScreenshotChanged: {
    if (mode !== "capture") return
    verified = false
    captureCopied = false
    captureEdited = false
    if (captureAnnotation) captureAnnotation.text = ""
  }
  signal taskRequested(string action, var options)
  signal captureRequested()
  signal lockRequested()
  signal finished()
  signal cancelled()

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
    captureCopied = false
    captureEdited = false
    smile.text = ""
    heart.text = ""
    exerciseInput.text = ""
    recipient.currentIndex = 0
    resolution.currentIndex = 0
  }
  onModeChanged: resetExercise()

  function requestTask(action, options) {
    if (busy) return
    busy = true
    error = ""
    status = ""
    taskRequested(action, options || {})
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
      if (result.action === "select") { region = result.region; stage = 1 }
      if (result.action === "start" && result.recording) { recording = true; stage = 2 }
      if (result.action === "stop" && result.path) { recording = false; artifact = result.path; stage = 3; outputPlayed = false }
    } else if (mode === "ocr" || mode === "qr") {
      if (result.image) { qrImage = result.image; artifact = result.image }
      if (result.text === "OMARCHY SAFE SAMPLE") {
        extracted = result.text
        artifact = result.path || ""
        nativeSamplePasted = false
        verified = false
        exerciseInput.text = ""
        stage = 1
      }
    } else if (mode === "dictation" && result.available) {
      stage = 1
      status = "Voxtype is installed. Availability does not guarantee a configured microphone or running service."
    } else if (mode === "web-app") {
      if (result.action === "create" && result.path) { artifact = result.path; stage = 1 }
      if (result.action === "open" && result.opened && stage === 1) stage = 2
      if (result.action === "remove" && result.removed && stage === 2) { stage = 3; verified = true }
    } else if (mode === "transcode") {
      if (result.action === "prepare" && result.path) { original = result.path; originalBytes = result.bytes; stage = 1 }
      if (result.action === "convert" && result.path && result.bytes < result.originalBytes) {
        artifact = result.path
        outputBytes = result.bytes
        stage = 2
        outputPlayed = false
        verified = false
      }
    } else if (mode === "sharing" && result.path) { artifact = result.path; stage = 1 }
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
      verified = false
    }
    if (!first && copiedFirst && selected === secondSample) {
      copiedSecond = true
      historyOpened = false
      verified = false
    }
  }
  function observeHistory() {
    if (copiedSecond) historyOpened = true
  }
  function observePaste(text) {
    if (copiedFirst && copiedSecond && historyOpened && text === sample) verified = true
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

  function captureCardGeometry() {
    var position = captureCard.mapToItem(root, 0, 0)
    return { x: position.x, y: position.y, width: captureCard.width, height: captureCard.height }
  }

  Shortcut {
    sequence: "Escape"
    onActivated: root.cancelled()
  }

  component PracticeButton: Controls.Button {
    id: control
    PracticePalette { target: control }
    property bool primary: false
    onActiveFocusChanged: if (activeFocus) Qt.callLater(function() { root.revealControl(control) })
    font.pixelSize: 15 * root.textScale
    leftPadding: 16
    rightPadding: 16
    topPadding: 10
    bottomPadding: 10
    implicitHeight: Math.max(44, contentItem.implicitHeight + 20)
    contentItem: Text {
      text: control.text
      font: control.font
      color: control.primary ? controlPalette.highlightedText
        : control.enabled ? controlPalette.buttonText : controlPalette.disabled.buttonText
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      wrapMode: Text.WordWrap
    }
    background: Rectangle {
      radius: 8
      color: control.primary ? root.accent : control.enabled ? controlPalette.button : root.backgroundColor
      border.width: control.activeFocus || control.hovered ? 2 : 1
      border.color: control.activeFocus ? root.foreground : control.enabled ? root.accent : controlPalette.secondaryText
    }
  }

  component NoteArea: Controls.TextArea {
    id: control
    PracticePalette { target: control }
    onActiveFocusChanged: if (activeFocus) Qt.callLater(function() { root.revealControl(control) })
    font.pixelSize: 16 * root.textScale
    padding: 12
    color: enabled ? controlPalette.text : controlPalette.disabled.text
    placeholderTextColor: controlPalette.placeholderText
    selectionColor: root.accent
    selectedTextColor: controlPalette.highlightedText
    background: Rectangle {
      radius: 8
      color: controlPalette.base
      border.width: control.activeFocus ? 2 : 1
      border.color: control.activeFocus ? root.accent : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.4)
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
    width: Math.max(0, Math.min(parent.width - 48, 900 * root.textScale))
    height: Math.max(0, Math.min(parent.height - 48, 760 * root.textScale))
    spacing: 14
    Text {
      Layout.fillWidth: true
      text: root.extendedMode ? root.exercises[root.mode][0] : root.mode === "clipboard" ? "Copy, retrieve, paste"
        : root.mode === "capture" ? "Capture a practice card"
        : root.mode === "screen-lock" ? "Lock safely, then return"
        : "Find and launch your terminal"
      color: root.foreground
      font.pixelSize: 25 * root.textScale
      font.bold: true
      wrapMode: Text.WordWrap
    }
    Controls.ScrollView {
      id: scrollArea
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
    Text {
      objectName: "exerciseInstructions"
      Layout.fillWidth: true
      text: root.extendedMode ? root.exercises[root.mode][1] : root.mode === "clipboard"
        ? "This exercise replaces your clipboard with harmless sample text. Copy both notes in order with Super+C. Open history with Super+Ctrl+V, highlight the first note, and use Shift+Enter to copy without pasting. Then click the destination field and paste once with Super+V."
        : root.mode === "capture"
        ? "Select only the practice card below. Inspect the saved image, copy its file path, and add a label to the preview. The label appears here only; it doesn't change the saved image. Nothing is uploaded. Escape cancels the selection."
        : root.mode === "screen-lock"
        ? "Super+Ctrl+L locks your computer; it doesn't suspend it. Save your work and make sure you know your password. Lock now is optional and requires your explicit click. After unlocking, return here."
        : "Press Super+Alt+Space, search for your terminal (for example Terminal or Ghostty), and press Return. Then close that newly opened terminal with Super+W. Existing windows don't count and aren't closed by this exercise."
      color: root.muted
      wrapMode: Text.WordWrap
      font.pixelSize: 16 * root.textScale
    }
        NoteArea {
          id: smile
          objectName: "composeSmile"
          visible: root.mode === "compose"
          Layout.fillWidth: true
          placeholderText: "Caps Lock → m → s (smile)"
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
          placeholderText: "Caps Lock → m → h (heart)"
          Accessible.name: "Compose a heart"
          KeyNavigation.priority: KeyNavigation.BeforeItem
          KeyNavigation.tab: cancelButton
          KeyNavigation.backtab: smile
          onTextChanged: root.checkCompose()
        }
        Rectangle {
          visible: ["screen-recording", "ocr"].indexOf(root.mode) !== -1
          Layout.fillWidth: true
          implicitHeight: 130
          color: "white"
          Text {
            anchors.centerIn: parent
            text: "OMARCHY SAFE SAMPLE"
            color: "black"
            font.pixelSize: 22
          }
          Rectangle {
            visible: root.mode === "screen-recording"
            y: 100
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
        PracticeButton {
          objectName: "prepareSample"
          visible: ["qr", "transcode", "sharing"].indexOf(root.mode) !== -1
          enabled: !root.busy && root.stage === 0 && root.qrImage === ""
          text: "Prepare harmless sample"
          onClicked: root.requestTask("prepare")
        }
        Image {
          visible: root.mode === "qr" && root.qrImage !== ""
          Layout.fillWidth: true
          Layout.preferredHeight: 260
          source: root.qrImage ? "file://" + root.qrImage : ""
          fillMode: Image.PreserveAspectFit
          Accessible.name: "Harmless sample QR code"
        }
        PracticeButton {
          objectName: "extractSample"
          visible: root.mode === "ocr" || root.mode === "qr"
          enabled: !root.busy && (root.mode === "ocr" || root.qrImage !== "")
          text: root.mode === "ocr" ? "Select sample and extract text" : "Select sample and decode QR"
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
          objectName: "copyExtracted"
          visible: root.extracted !== ""
          text: "Copy recognized sample"
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
          objectName: "consentDictation"
          visible: root.mode === "dictation" && root.stage >= 1
          enabled: !root.consent && !root.verified
          text: "I'm ready to use my microphone with the shortcut"
          onClicked: { root.consent = true; exerciseInput.forceActiveFocus() }
        }
        NoteArea {
          id: exerciseInput
          objectName: "exerciseInput"
          visible: ["ocr", "qr", "dictation"].indexOf(root.mode) !== -1
          enabled: root.mode === "dictation" ? root.consent : root.extracted !== ""
          Layout.fillWidth: true
          wrapMode: TextEdit.Wrap
          placeholderText: root.mode === "dictation" ? "Dictate: Omarchy practice" : "Paste the recognized sample here"
          Accessible.name: placeholderText
          KeyNavigation.priority: KeyNavigation.BeforeItem
          KeyNavigation.tab: reviewRecognized
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
          visible: ["ocr", "qr", "dictation"].indexOf(root.mode) !== -1
          enabled: !root.verified && (root.mode === "dictation"
            ? root.consent && /^omarchy practice[.!]?$/i.test(exerciseInput.text.trim())
            : root.nativeSamplePasted)
          text: root.mode === "dictation" ? "I stopped dictation and proofread the words" : "The pasted words match the sample"
          onClicked: { root.verified = true; root.status = "Reviewed locally. Nothing sent." }
        }
        PracticeButton {
          objectName: "selectRecording"
          visible: root.mode === "screen-recording"
          enabled: !root.busy && !root.recording && root.stage < 2
          text: "Select recording region"
          onClicked: root.requestTask("select")
        }
        Text {
          visible: root.mode === "screen-recording" && root.region !== ""
          Layout.fillWidth: true
          text: "Review selected region: " + root.region + ". Only start if it contains the practice card."
          wrapMode: Text.WordWrap
          color: root.foreground
          font.pixelSize: 16 * root.textScale
        }
        PracticeButton {
          objectName: "startRecording"
          visible: root.mode === "screen-recording"
          enabled: !root.busy && root.stage === 1 && root.region !== ""
          text: "Start silent recording of reviewed region"
          onClicked: root.requestTask("start")
        }
        PracticeButton {
          objectName: "stopRecording"
          visible: root.mode === "screen-recording"
          enabled: !root.busy && root.recording
          text: "Stop my recording"
          onClicked: root.requestTask("stop")
        }
        PracticeButton {
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
          onActiveFocusChanged: if (activeFocus) Qt.callLater(function() { root.revealControl(resolution) })
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
          visible: ["screen-recording", "transcode"].indexOf(root.mode) !== -1 && (root.original !== "" || root.artifact !== "")
          Layout.fillWidth: true
          Layout.preferredHeight: 170
          Accessible.name: "Saved practice clip playback"
        }
        PracticeButton {
          objectName: "playOutput"
          visible: ["screen-recording", "transcode"].indexOf(root.mode) !== -1
          enabled: root.artifact !== "" && !root.busy
          text: "Play saved output"
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
          onActiveFocusChanged: if (activeFocus) Qt.callLater(function() { root.revealControl(recipient) })
          onCurrentIndexChanged: if (root.mode === "sharing") root.verified = false
        }
        PracticeButton {
          objectName: "reviewShare"
          visible: root.mode === "sharing"
          enabled: root.stage === 1 && recipient.currentIndex === 1
          text: "I've checked the file and demo recipient. Don't send anything."
          onClicked: { root.verified = true; root.status = "Preparation reviewed. No transfer attempted or delivery confirmed." }
        }
        Text {
          visible: root.artifact !== "" || root.original !== ""
          Layout.fillWidth: true
          text: root.original + (root.original ? "\n" : "") + root.artifact
          wrapMode: Text.WrapAnywhere
          color: root.muted
          font.pixelSize: 14 * root.textScale
        }
        Text { visible: root.mode === "clipboard"; Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "1. Select this note, then Super+C"; color: root.accent; font.pixelSize: 16 * root.textScale }
        NoteArea {
          id: first
          objectName: "firstNote"
          visible: root.mode === "clipboard"
          Layout.fillWidth: true
          text: root.sample
          readOnly: true
          selectByMouse: true
          wrapMode: TextEdit.Wrap
          Accessible.name: "First practice note"
          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            if (event.matches(StandardKey.Copy)) {
              var selected = selectedText
              Qt.callLater(function() { root.observeCopy(true, selected) })
            }
            event.accepted = false
          }
        }
        PracticeButton {
          visible: root.mode === "clipboard"
          text: root.copiedFirst ? "First note copied" : "Select first note"
          onClicked: { first.forceActiveFocus(); first.selectAll() }
        }
        Text { visible: root.mode === "clipboard"; Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "2. Copy this newer note with Super+C"; color: root.accent; font.pixelSize: 16 * root.textScale }
        NoteArea {
          id: second
          objectName: "secondNote"
          visible: root.mode === "clipboard"
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
        PracticeButton {
          id: selectNewerButton
          visible: root.mode === "clipboard"
          enabled: root.copiedFirst
          text: root.copiedSecond ? "Newer note copied" : "Select newer note"
          onClicked: { second.forceActiveFocus(); second.selectAll() }
        }
        Text {
          objectName: "clipboardHistoryInstructions"
          visible: root.mode === "clipboard"
          Layout.fillWidth: true
          text: "3. Open history with Super+Ctrl+V. Use the arrows to highlight the FIRST note, then Shift+Enter to copy it without pasting."
          wrapMode: Text.WordWrap
          color: root.accent
          font.pixelSize: 16 * root.textScale
        }
        NoteArea {
          id: destination
          objectName: "pasteDestination"
          visible: root.mode === "clipboard"
          enabled: root.copiedSecond
          Layout.fillWidth: true
          placeholderText: "4. Click here, then Super+V to paste the first note"
          selectByMouse: true
          wrapMode: TextEdit.Wrap
          Accessible.name: "Paste the first note after copying it with Shift+Enter"
          KeyNavigation.priority: KeyNavigation.BeforeItem
          KeyNavigation.tab: cancelButton
          KeyNavigation.backtab: selectNewerButton
          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            if (event.matches(StandardKey.Paste)) Qt.callLater(function() { root.observePaste(destination.text) })
            event.accepted = false
          }
        }
        Rectangle {
          id: captureCard
          visible: root.mode === "capture"
          Layout.fillWidth: true
          implicitHeight: 150
          radius: 12
          color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
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
        PracticeButton {
          objectName: "selectRegion"
          visible: root.mode === "capture"
          enabled: !root.busy
          text: "Select a region"
          onClicked: root.captureRequested()
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
            if (status === Image.Ready && sourceSize.width > 0 && sourceSize.height > 0) root.status = "Image loaded. Try the copy-path and preview annotation controls."
            if (status === Image.Error) {
              root.verified = false
              root.error = "The capture couldn't be opened. Select a region again."
            }
          }
          Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: annotationLabel.implicitHeight + 12
            visible: captureAnnotation.text.trim() !== ""
            color: root.backgroundColor
            Text {
              id: annotationLabel
              anchors.centerIn: parent
              width: parent.width - 12
              text: captureAnnotation.text
              color: root.foreground
              font.pixelSize: 14 * root.textScale
              wrapMode: Text.WordWrap
            }
          }
        }
        NoteArea {
          id: capturePath
          visible: false
          text: root.screenshot
        }
        PracticeButton {
          objectName: "copyCapture"
          visible: root.mode === "capture"
          enabled: preview.status === Image.Ready
          text: "Copy saved image path"
          onClicked: {
            capturePath.selectAll()
            capturePath.copy()
            root.captureCopied = true
            root.verified = root.captureEdited
          }
        }
        NoteArea {
          id: captureAnnotation
          objectName: "captureAnnotation"
          visible: root.mode === "capture" && preview.status === Image.Ready
          Layout.fillWidth: true
          placeholderText: "Add a preview annotation (original image stays unchanged)"
          Accessible.name: "Local preview annotation"
          KeyNavigation.priority: KeyNavigation.BeforeItem
          KeyNavigation.tab: cancelButton
          onTextChanged: {
            root.captureEdited = text.trim().length > 0
            if (root.mode === "capture") root.verified = root.captureCopied && root.captureEdited
          }
        }
        Text {
          visible: root.screenshot !== ""
          Layout.fillWidth: true
          text: root.screenshot
          font.pixelSize: 14 * root.textScale
          wrapMode: Text.WrapAnywhere
          color: root.muted
        }
        PracticeButton {
          visible: root.mode === "screen-lock"
          enabled: !root.busy && !root.verified
          text: "Lock this computer now"
          onClicked: root.lockRequested()
        }
        Text {
          Layout.fillWidth: true
          text: root.verified ? (root.mode === "sharing" ? "Sharing review complete. Nothing sent; delivery isn't confirmed."
            : root.mode === "dictation" ? "Text review complete. Microphone use wasn't checked."
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
    GridLayout {
      Layout.fillWidth: true
      columns: width < 600 * root.textScale ? 1 : 2
      columnSpacing: 12
      rowSpacing: 10
      PracticeButton {
        id: cancelButton
        objectName: "returnWithoutCompleting"
        Layout.fillWidth: true
        text: "Return without completing"
        KeyNavigation.priority: KeyNavigation.BeforeItem
        KeyNavigation.tab: finishButton
        onClicked: root.cancelled()
      }
      PracticeButton {
        id: finishButton
        objectName: "finishExercise"
        Layout.fillWidth: true
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
