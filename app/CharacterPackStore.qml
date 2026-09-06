pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io

QtObject {
  id: root
  property string appRoot: ""
  property string bundledRoot: appRoot + "/assets/characters"
  property string userRoot: ""
  property string requestedId: "hexon"
  property bool autoLoad: true

  readonly property bool ready: _ready
  readonly property bool loading: _loading
  readonly property var packs: _snapshot.packs
  readonly property string fallbackId: _snapshot.fallbackId || ""
  readonly property var selectedPack: resolveSelection(packs, requestedId, _snapshot.fallbackId)
  readonly property var diagnostics: (_snapshot.diagnostics || []).concat(_failure ? [_failure] : [])
  readonly property string notice: !ready ? "Loading character packs…"
    : !selectedPack ? (_failure || "No valid character packs are available.")
    : requestedId && selectedPack.id !== requestedId
      ? "Character pack '" + requestedId + "' is unavailable; using " + selectedPack.manifest.displayName + "."
      : _failure
  readonly property string narrationNotice: !selectedPack ? ""
    : selectedPack.manifest.narration?.mode === "silent" ? "This character uses text-only narration."
    : selectedPack.manifest.narration?.mode === "borrowed"
      ? "Borrowed narration: lines naming a coach intentionally use text only."
      : ""

  property var _snapshot: ({ version: 1, packs: [], diagnostics: [], fallbackId: null })
  property string _failure: ""
  property bool _ready: false
  property bool _loading: false
  property bool _stopping: false
  property bool _awaitingExit: false
  property bool _completed: false
  property int _generation: 0
  property bool _pending: false

  function resolveSelection(catalog, requested, fallback) {
    return catalog.find(function(pack) { return pack.id === requested })
      || catalog.find(function(pack) { return pack.id === fallback }) || null
  }

  function select(id) {
    requestedId = String(id || "")
    return selectedPack !== null && selectedPack.id === requestedId
  }

  function refresh() {
    _generation++
    if (_loading || _stopping || _awaitingExit) {
      _pending = true
      return
    }
    startDiscovery()
  }

  function startDiscovery() {
    if (_loading || _stopping || _awaitingExit) return
    _pending = false
    _loading = true
    worker.generation = _generation
    var command = ["node", "--experimental-strip-types", appRoot + "/tools/character-packs.ts",
      "discover", "--bundled-root", bundledRoot]
    if (userRoot) command.push("--user-root", userRoot)
    worker.command = command
    timeout.generation = worker.generation
    timeout.restart()
    worker.running = true
  }

  // Only the CLI validates manifests. This checks its transport envelope so a
  // truncated worker response cannot replace the last usable catalog.
  function acceptResult(output, failure, generation) {
    if (generation !== _generation) return
    if (!failure) {
      try {
        var result = JSON.parse(output)
        if (result.version !== 1 || !Array.isArray(result.packs)
            || !Array.isArray(result.diagnostics)
            || !(result.fallbackId === null || typeof result.fallbackId === "string"))
          throw new Error("Invalid discovery response")
        _snapshot = result
      } catch (error) {
        failure = "Cannot read character discovery result: " + error
      }
    }
    _failure = failure || ""
    _ready = true
    if (_failure) console.warn("Character packs:", _failure)
  }

  function finishDiscovery(output, failure, generation) {
    if (generation !== worker.generation || (!_loading && !_stopping)) return
    timeout.stop()
    var stopped = _stopping
    _awaitingExit = false
    _stopping = false
    if (!stopped) acceptResult(output, failure, generation)
    _loading = false
    if (_pending) Qt.callLater(startPendingDiscovery)
  }

  function discoveryStarted(generation) {
    if (generation === worker.generation && _loading) _awaitingExit = true
  }

  function expireDiscovery(generation) {
    if (generation !== worker.generation || !_loading || _stopping) return
    var failure = "Character discovery timed out or could not start."
    // Failed launches have no exit signal. A started process, including one
    // whose running flag just cleared, must release its request fields on exit.
    if (!worker.running && !_awaitingExit) {
      finishDiscovery("", failure, generation)
      return
    }
    timeout.stop()
    _stopping = true
    acceptResult("", failure, generation)
    worker.running = false
  }

  function startPendingDiscovery() {
    if (_pending && !_loading && !_stopping && !_awaitingExit) startDiscovery()
  }

  function audioPath(relativePath, spokenText, courseDir) {
    if (!relativePath || !selectedPack) return ""
    var narration = selectedPack.manifest.narration
    if (!narration || narration.mode === "silent") return ""
    // Course text uses HEXON as a generic substitution token. Borrowed audio
    // cannot substitute names, so those lines deliberately remain text-only.
    if (narration.mode === "borrowed") {
      var text = String(spokenText || "").toUpperCase()
      if (text.indexOf("HEXON") >= 0 || text.indexOf("OLLIE") >= 0) return ""
    }
    var relative = String(relativePath)
    var slash = relative.lastIndexOf("/")
    var directory = slash < 0 ? "" : relative.substring(0, slash + 1)
    var filename = slash < 0 ? relative : relative.substring(slash + 1)
    return String(courseDir).replace(/\/$/, "") + "/" + directory + narration.audioSet + "/" + filename
  }

  onAppRootChanged: if (_completed && autoLoad) Qt.callLater(refresh)
  onBundledRootChanged: if (_completed && autoLoad) Qt.callLater(refresh)
  onUserRootChanged: if (_completed && autoLoad) Qt.callLater(refresh)
  Component.onCompleted: { _completed = true; if (autoLoad) refresh() }

  property Process _worker: Process {
    id: worker
    property int generation: 0
    stdout: StdioCollector { id: output }
    stderr: StdioCollector { id: errors }
    onStarted: root.discoveryStarted(generation)
    onExited: function(code) {
      root.finishDiscovery(output.text,
        code === 0 ? "" : "Character discovery failed (exit " + code + "): " + errors.text.trim(),
        generation)
    }
  }
  property Timer _timeout: Timer {
    id: timeout
    property int generation: 0
    interval: 15000
    onTriggered: root.expireDiscovery(generation)
  }
}
