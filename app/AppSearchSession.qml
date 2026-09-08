import QtQuick
import Quickshell.Io
import Quickshell.Hyprland

Item {
  id: root
  visible: false
  property bool active: false
  property bool ready: false
  property bool menuSeen: false
  property var initialWindows: []
  property string terminalAddress: ""
  property bool baselinePending: false
  signal completed()
  signal failed(string message)

  function address(value) {
    var text = String(value || "").toLowerCase()
    if (!/^(?:0x)?[0-9a-f]+$/i.test(text)) return ""
    return (text.indexOf("0x") === 0 ? text : "0x" + text).toLowerCase()
  }

  function start() {
    if (active || baselinePending || baselineProcess.running) return
    active = true
    ready = false
    menuSeen = false
    terminalAddress = ""
    initialWindows = []
    baselinePending = true
    baselineProcess.running = true
  }

  function acceptBaseline(code, raw) {
    if (!active) return
    try {
      if (code !== 0) throw new Error("Couldn't inspect the desktop window list.")
      var clients = JSON.parse(raw)
      if (!Array.isArray(clients) || clients.some(function(client) { return !client || address(client.address) === "" }))
        throw new Error("The desktop returned an invalid window list.")
      initialWindows = clients.map(function(client) { return address(client.address) })
      ready = true
    } catch (error) {
      active = false
      failed(String(error))
    }
  }

  function observe(event) {
    if (!active || !ready) return
    if (event.name === "openlayer" && String(event.data).trim() === "omarchy-menu") menuSeen = true
    var parts = String(event.data || "").split(",")
    var window = address(parts[0])
    if (!window) return
    if (event.name === "openwindow" && menuSeen && terminalAddress === "" &&
        initialWindows.indexOf(window) === -1 && /ghostty|alacritty|kitty|foot|wezterm|console|terminal/i.test(parts[2] || ""))
      terminalAddress = window
    if (event.name === "closewindow" && terminalAddress !== "" && window === terminalAddress) {
      active = false
      completed()
    }
  }

  Process {
    id: baselineProcess
    command: ["hyprctl", "clients", "-j"]
    stdout: StdioCollector { id: baselineOutput }
    onExited: function(code) {
      root.baselinePending = false
      root.acceptBaseline(code, baselineOutput.text)
    }
    onRunningChanged: {
      if (!running && root.baselinePending) {
        root.baselinePending = false
        root.acceptBaseline(1, "")
      }
    }
  }
  Connections {
    target: Hyprland
    function onRawEvent(event) { root.observe(event) }
  }
}
