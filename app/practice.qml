import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

ShellRoot {
  id: root
  readonly property string mode: Quickshell.env("LEARN_OMARCHY_PRACTICE_MODE")
  readonly property string appRoot: Quickshell.env("LEARN_OMARCHY_ROOT") || Quickshell.shellDir + "/.."
  property var baseline: []
  property bool baselineReady: false
  property bool menuSeen: false
  property string terminalAddress: ""
  property bool lockObserved: false
  property bool clipboardSeen: false
  property bool closing: false

  OmarchyTheme {
    id: theme
    fallbackColors: ({
      background: Quickshell.env("LEARN_OMARCHY_PRACTICE_BACKGROUND"),
      foreground: Quickshell.env("LEARN_OMARCHY_PRACTICE_FOREGROUND"),
      accent: Quickshell.env("LEARN_OMARCHY_PRACTICE_ACCENT"),
      urgent: Quickshell.env("LEARN_OMARCHY_PRACTICE_ERROR")
    })
  }

  function closeNativeSurfaces() {
    if (clipboardSeen) Quickshell.execDetached(["omarchy-shell", "shell", "hide", "omarchy.clipboard"])
    if (menuSeen) Quickshell.execDetached(["omarchy", "menu", "close"])
  }

  Component.onDestruction: if (!closing) closeNativeSurfaces()

  function closePractice() {
    if (closing) return
    closing = true
    closeNativeSurfaces()
    captureProcess.running = false
    taskProcess.running = false
    baselineProcess.running = false
    lockStatus.running = false
    lockCheckTimer.stop()
    lockObservationTimeout.stop()
    finishClosing()
  }

  function finishClosing() {
    // Destroying Quickshell's Process kills it immediately, before its child cleanup can run.
    if (closing && !captureProcess.running && !taskProcess.running) Qt.quit()
  }

  function lockUnavailable(message) {
    lockCheckTimer.stop()
    lockObservationTimeout.stop()
    lockStatus.running = false
    content.busy = false
    content.error = message + " Return and skip this optional exercise."
  }

  function handleLockStatus(code, raw) {
    if (!content.busy || closing) return
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

  IpcHandler {
    target: "practice"
    function cancel(): void { root.closePractice() }
    function status(): string {
      var focused = content.Window.window ? content.Window.window.activeFocusItem : null
      return JSON.stringify({
        mode: root.mode, verified: content.verified, busy: content.busy,
        copiedFirst: content.copiedFirst, copiedSecond: content.copiedSecond,
        historyOpened: content.historyOpened, menuSeen: root.menuSeen,
        terminalAddress: root.terminalAddress, lockObserved: root.lockObserved,
        sample: root.mode === "clipboard" ? content.sample : "",
        screenshot: content.screenshot,
        captureCard: root.mode === "capture" ? content.captureCardGeometry() : null,
        stage: content.stage, artifact: content.artifact, recording: content.recording,
        focusedControl: focused ? focused.objectName : "", error: content.error
      })
    }
  }

  FloatingWindow {
    id: practiceWindow
    title: "Learn Omarchy - practice"
    implicitWidth: 760
    implicitHeight: 680
    minimumSize: Qt.size(460, 480)
    color: theme.colors.background
    visible: true
    onClosed: root.closePractice()
    PracticeContent {
      id: content
      anchors.fill: parent
      mode: root.mode
      textScale: Number(Quickshell.env("LEARN_OMARCHY_PRACTICE_SCALE") || "1")
      backgroundColor: theme.colors.background
      foreground: theme.colors.foreground
      accent: theme.colors.accent
      muted: theme.colors.muted
      errorColor: theme.colors.urgent
      onCancelled: root.closePractice()
      onFinished: {
        if (!verified || root.closing) return
        console.log("LEARN_PRACTICE_RESULT:" + JSON.stringify({ mode: root.mode, completed: true }))
        root.closePractice()
      }
      onCaptureRequested: {
        verified = false
        error = ""
        screenshot = ""
        captureCopied = false
        captureEdited = false
        busy = true
        captureProcess.running = true
      }
      onLockRequested: {
        error = ""
        busy = true
        root.lockObserved = false
        lockProcess.running = true
        lockCheckTimer.start()
        lockObservationTimeout.start()
      }
      onTaskRequested: function(action, options) {
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
  }
  IdleInhibitor {
    window: practiceWindow
    enabled: root.mode !== "screen-lock"
  }
  Process {
    id: taskProcess
    command: [root.appRoot + "/bin/learn-omarchy-practice", "--session", root.mode]
    running: ["screen-recording", "ocr", "qr", "dictation", "web-app", "transcode", "sharing"].indexOf(root.mode) !== -1
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(data) {
        try { content.handleTaskResult(JSON.parse(data)) }
        catch (error) { content.busy = false; content.error = "The practice helper returned an invalid result." }
      }
    }
    onExited: function(code) {
      if (root.closing) { root.finishClosing(); return }
      content.busy = false
      content.recording = false
      if (code !== 0) content.error = "Practice helper unavailable. Return and retry, or skip the optional exercise."
    }
    onRunningChanged: if (root.closing && !running) root.finishClosing()
  }
  Process {
    id: baselineProcess
    command: ["hyprctl", "clients", "-j"]
    running: root.mode === "app-search"
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var clients = JSON.parse(text)
          if (!Array.isArray(clients)) throw new Error("Expected a client list")
          root.baseline = clients.map(function(client) { return client.address })
          root.baselineReady = true
          content.status = "Ready. Open the Apps menu to begin."
        } catch (error) { content.error = "Couldn't read the desktop window list. Return to your coach and try again." }
      }
    }
    onExited: function(code) {
      if (code !== 0) content.error = "Couldn't inspect the desktop (exit " + code + ")."
    }
  }
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (root.mode === "clipboard") {
        if (event.name === "openlayer" && String(event.data).trim() === "omarchy-clipboard") {
          root.clipboardSeen = true
          content.observeHistory()
        }
        return
      }
      if (root.mode !== "app-search" || !root.baselineReady || content.verified) return
      if (event.name === "openlayer" && String(event.data).trim() === "omarchy-menu") root.menuSeen = true
      var parts = String(event.data || "").split(",")
      var address = parts[0].indexOf("0x") === 0 ? parts[0] : "0x" + parts[0]
      if (event.name === "openwindow" && root.menuSeen && root.terminalAddress === "" &&
          root.baseline.indexOf(address) === -1 &&
          /ghostty|alacritty|kitty|foot|wezterm|console|terminal/i.test(parts[2] || "")) {
        root.terminalAddress = address
        content.status = "New terminal detected. Close that terminal with Super+W."
      }
      if (event.name === "closewindow" && root.terminalAddress !== "" && address === root.terminalAddress) {
        content.verified = true
      }
    }
  }
  Process {
    id: captureProcess
    command: [root.appRoot + "/bin/learn-omarchy-practice", "--capture"]
    stdout: StdioCollector { id: captureOutput }
    onExited: function(code) {
      if (root.closing) { root.finishClosing(); return }
      content.busy = false
      if (code === 2) { content.status = "Selection cancelled. Nothing was completed; try again when ready."; return }
      var path = captureOutput.text.trim()
      if (code !== 0 || !/^\/.*\/learn-omarchy-capture\.[A-Za-z0-9]+\/practice\.png$/.test(path)) {
        content.error = "Capture failed. Try selecting a region again."
        return
      }
      content.screenshot = path
    }
    onRunningChanged: if (root.closing && !running) root.finishClosing()
  }
  Process {
    id: lockProcess
    command: ["omarchy", "system", "lock"]
    onExited: function(code) {
      if (code !== 0) {
        root.lockUnavailable("Locking failed (exit " + code + ").")
      }
    }
  }
  Timer {
    id: lockCheckTimer
    interval: 400
    repeat: true
    onTriggered: if (!lockStatus.running) lockStatus.running = true
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
    onExited: function(code) { root.handleLockStatus(code, lockOutput.text) }
  }
}
