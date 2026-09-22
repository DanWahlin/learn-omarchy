import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "ThemeColors.js" as ThemeColors

Item {
  id: root
  implicitWidth: 760
  implicitHeight: 320
  property string mode: "clipboard"
  property real textScale: 1
  property color backgroundColor: ThemeColors.defaults.background
  property color foreground: ThemeColors.defaults.foreground
  property color accent: ThemeColors.defaults.accent
  property color muted: Qt.tint(backgroundColor, Qt.rgba(foreground.r, foreground.g, foreground.b, 0.78))
  property color errorColor: ThemeColors.defaults.urgent
  property bool showFooter: true
  property bool autoStart: true
  readonly property string appRoot: Quickshell.env("LEARN_OMARCHY_ROOT") || Quickshell.shellDir + "/.."
  readonly property bool closing: lifecycle === "closing"
  readonly property bool running: lifecycle === "running"
  readonly property bool verified: content.verified
  readonly property bool busy: content.busy
  readonly property string artifact: content.artifact || content.screenshot
  readonly property string error: content.error
  property string lifecycle: "idle"
  property string outcome: "cancelled"
  property string failureMessage: ""
  property bool lockObserved: false
  property bool clipboardSeen: false
  property bool taskPending: false
  property bool capturePending: false
  property bool recordingPending: false
  property bool lockPending: false
  property bool lockStatusPending: false
  property bool closingQueued: false
  signal completed()
  signal cancelled()
  signal failed(string message)
  onModeChanged: if (running) cancel()

  function start() {
    // A session is single-use: a fresh Loader also isolates delayed callbacks.
    if (lifecycle !== "idle") return
    lifecycle = "running"
    if (["clipboard", "capture", "screen-lock", "compose", "screen-recording", "ocr", "qr", "dictation", "dictation-corrections", "notifications", "web-app", "transcode", "sharing"].indexOf(mode) === -1) {
      failureMessage = "Unsupported practice activity. Return to your coach and choose another activity."
      closePractice("failed")
      return
    }
    if (["qr", "dictation", "dictation-corrections", "web-app", "transcode", "sharing"].indexOf(mode) !== -1) {
      taskPending = true
      taskProcess.running = true
    }
    if (mode === "capture") {
      capturePending = true
      captureProcess.running = true
    }
    if (mode === "screen-recording") {
      recordingPending = true
      recordingProcess.running = true
    }
  }

  function cancel() {
    closePractice("cancelled")
  }

  function finish() {
    if (running && content.verified && !content.busy) closePractice("completed")
  }

  function focusPractice() {
    if (running) content.focusPractice()
  }

  function closePractice(result) {
    if (closing || lifecycle === "closed") return
    outcome = result || "cancelled"
    lifecycle = "closing"
    content.stopPlayback()
    captureProcess.running = false
    recordingProcess.running = false
    taskProcess.running = false
    lockProcess.running = false
    lockStatus.running = false
    // A request cancelled before Quickshell's post-reload start has no exit event.
    if (!captureProcess.running) capturePending = false
    if (!recordingProcess.running) recordingPending = false
    if (!taskProcess.running) taskPending = false
    if (!lockProcess.running) lockPending = false
    if (!lockStatus.running) lockStatusPending = false
    lockCheckTimer.stop()
    lockObservationTimeout.stop()
    finishClosing()
  }

  function finishClosing() {
    // Process destruction kills children before helper SIGTERM cleanup finishes.
    // Wait for process exit (or failed startup), then let handlers unwind before unloading.
    if (!closing || closingQueued || taskPending || capturePending || recordingPending || lockPending || lockStatusPending) return
    closingQueued = true
    Qt.callLater(function() {
      if (!root.closing) return
      root.lifecycle = "closed"
      if (root.outcome === "completed") root.completed()
      else if (root.outcome === "failed") root.failed(root.failureMessage)
      else root.cancelled()
    })
  }

  function status() {
    var focused = content.Window.window ? content.Window.window.activeFocusItem : null
    return JSON.stringify({
      mode: mode, running: running, closing: closing,
      verified: content.verified, busy: content.busy,
      copiedFirst: content.copiedFirst, copiedSecond: content.copiedSecond,
      historyOpened: content.historyOpened, lockObserved: lockObserved,
      sample: mode === "clipboard" ? content.sample : "",
      screenshot: content.screenshot,
      captureCard: mode === "capture" ? content.captureCardGeometry() : null,
      stage: content.stage, artifact: content.artifact, recording: content.recording,
      focusedControl: focused ? focused.objectName : "", error: content.error
    })
  }

  function lockUnavailable(message) {
    if (!running) return
    lockCheckTimer.stop()
    lockObservationTimeout.stop()
    lockStatus.running = false
    content.busy = false
    content.error = message + " Return and skip this optional exercise."
  }

  function handleLockStatus(code, raw) {
    if (!content.busy || !running) return
    if (code !== 0) {
      lockUnavailable("Couldn't read Omarchy's lock status.")
      return
    }
    var state
    try {
      state = JSON.parse(raw)
      if (!state || typeof state.locked !== "boolean" || typeof state.sessionLocked !== "boolean" || typeof state.secure !== "boolean") {
        throw new Error("Unsupported lock status")
      }
    } catch (error) {
      lockUnavailable("Omarchy returned an unsupported lock status.")
      return
    }
    if (state.sessionLocked && state.secure) {
      lockObserved = true
      lockObservationTimeout.stop()
    } else if (!state.locked && !state.sessionLocked && !state.secure && lockObserved) {
      content.busy = false
      content.verified = true
      lockCheckTimer.stop()
    }
  }

  Component.onCompleted: if (autoStart) start()
  PracticeContent {
    id: content
    objectName: "practiceContent"
    anchors.fill: parent
    enabled: root.running
    mode: root.mode
    textScale: root.textScale
    backgroundColor: root.backgroundColor
    foreground: root.foreground
    accent: root.accent
    muted: root.muted
    errorColor: root.errorColor
    showFooter: root.showFooter
    onCancelled: root.cancel()
    onFinished: root.finish()
    onLockRequested: {
      if (!root.running || root.lockPending || root.lockStatusPending) return
      error = ""
      busy = true
      root.lockObserved = false
      root.lockPending = true
      lockProcess.running = true
      lockCheckTimer.start()
      lockObservationTimeout.start()
    }
    onTaskRequested: function(action, options) {
      if (!root.running) return
      var request = { action: action }
      if (options.height !== undefined) request.height = options.height
      if (!taskProcess.running) {
        busy = false
        error = "The practice helper is unavailable. Return to your coach and retry."
        return
      }
      taskProcess.write(JSON.stringify(request) + "\n")
    }
  }
  Process {
    id: taskProcess
    command: [root.appRoot + "/bin/learn-omarchy-practice", "--session", root.mode]
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(data) {
        if (!root.running) return
        try { content.handleTaskResult(JSON.parse(data)) }
        catch (error) { content.busy = false; content.error = "The practice helper returned an invalid result." }
      }
    }
    onExited: function(code) {
      root.taskPending = false
      if (root.closing) { root.finishClosing(); return }
      if (!root.running) return
      content.busy = false
      content.recording = false
      content.error = "Practice helper unavailable. Return and retry, or skip the optional exercise."
    }
    onRunningChanged: {
      if (running || !root.taskPending) return
      root.taskPending = false
      if (root.closing) { root.finishClosing(); return }
      content.busy = false
      content.error = "Practice helper unavailable. Return and retry, or skip the optional exercise."
    }
  }
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (root.running && root.mode === "clipboard" &&
          event.name === "openlayer" && String(event.data).trim() === "omarchy-clipboard") {
        root.clipboardSeen = true
        content.observeHistory()
      }
    }
  }
  Process {
    id: captureProcess
    command: [root.appRoot + "/bin/learn-omarchy-practice", "--watch-screenshots"]
    stdout: SplitParser {
      onRead: function(data) {
        if (!root.running) return
        var path = String(data || "").trim()
        if (!/^\/.*\/screenshot-\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\.png$/.test(path)) {
          content.error = "The screenshot watcher returned an invalid file. Return and retry."
          return
        }
        content.screenshot = path
      }
    }
    onExited: function(code) {
      root.capturePending = false
      if (root.closing) { root.finishClosing(); return }
      if (!root.running) return
      content.error = code === 0
        ? "The screenshot watcher stopped. Return and retry the exercise."
        : "The screenshot watcher is unavailable. Return and retry the exercise."
    }
    onRunningChanged: {
      if (running || !root.capturePending) return
      root.capturePending = false
      if (root.closing) { root.finishClosing(); return }
      content.busy = false
      content.error = "Screenshot watching is unavailable. Return to your coach and retry."
    }
  }
  Process {
    id: recordingProcess
    command: [root.appRoot + "/bin/learn-omarchy-practice", "--watch-recordings"]
    stdout: SplitParser {
      onRead: function(data) {
        if (!root.running) return
        try {
          var event = JSON.parse(String(data || "").trim())
          if (event.event === "started") content.observeRecordingStarted()
          else if (event.event === "saved" && /^\/.*\/screenrecording-\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\.mp4$/.test(event.path))
            content.observeRecordingSaved(event.path)
          else if (event.event === "already-active")
            content.error = "A screen recording was already active when this exercise started. Stop it, then start a new recording for this exercise."
          else content.error = "The screen recording watcher returned an invalid event. Return and retry."
        } catch (error) {
          content.error = "The screen recording watcher returned invalid data. Return and retry."
        }
      }
    }
    onExited: function(code) {
      root.recordingPending = false
      if (root.closing) { root.finishClosing(); return }
      if (!root.running) return
      content.error = code === 0
        ? "Screen recording watching stopped. Return and retry the exercise."
        : "Screen recording watching is unavailable. Return and retry the exercise."
    }
    onRunningChanged: {
      if (running || !root.recordingPending) return
      root.recordingPending = false
      if (root.closing) { root.finishClosing(); return }
      content.error = "Screen recording watching is unavailable. Return to your coach and retry."
    }
  }
  Process {
    id: lockProcess
    command: ["omarchy", "system", "lock"]
    onExited: function(code) {
      root.lockPending = false
      if (root.closing) { root.finishClosing(); return }
      if (code !== 0) root.lockUnavailable("Locking failed (exit " + code + ").")
    }
    onRunningChanged: {
      if (running || !root.lockPending) return
      root.lockPending = false
      if (root.closing) { root.finishClosing(); return }
      root.lockUnavailable("The lock command is unavailable.")
    }
  }
  Timer {
    id: lockCheckTimer
    interval: 400
    repeat: true
    onTriggered: {
      if (root.running && !root.lockStatusPending) {
        root.lockStatusPending = true
        lockStatus.running = true
      }
    }
  }
  Timer {
    id: lockObservationTimeout
    interval: 10000
    onTriggered: root.lockUnavailable("The desktop didn't report that it locked.")
  }
  Process {
    id: lockStatus
    command: ["omarchy-shell", "lock", "status"]
    stdout: StdioCollector { id: lockOutput }
    onExited: function(code) {
      root.lockStatusPending = false
      if (root.closing) { root.finishClosing(); return }
      root.handleLockStatus(code, lockOutput.text)
    }
    onRunningChanged: {
      if (running || !root.lockStatusPending) return
      root.lockStatusPending = false
      if (root.closing) { root.finishClosing(); return }
      root.lockUnavailable("Couldn't read Omarchy's lock status.")
    }
  }
}
