import QtQuick
import Quickshell.Io

QtObject {
    id: root
    property string appRoot: ""
    property bool enabled: true
    property real volume: 45
    property bool paused: false
    property bool suspended: false
    // Tests can exercise scheduling without opening an audio device.
    property bool playbackEnabled: true
    property int coalesceMs: 65
    property int startupTimeoutMs: 1500
    readonly property bool available: enabled && volume > 0 && !paused && !suspended
    readonly property bool busy: occupied || pending !== ""
    readonly property var cues: ({
        "correct": { file: "interaction-correct.wav", priority: 1, debounce: 180, duration: 160 },
        "wrong": { file: "interaction-wrong.wav", priority: 1, debounce: 650, duration: 220 },
        "step-complete": { file: "interaction-step-complete.wav", priority: 2, debounce: 350, duration: 340 },
        "module-complete": { file: "interaction-module-complete.wav", priority: 3, debounce: 900, duration: 580 }
    })
    property string pending: ""
    property string current: ""
    property bool occupied: false
    property bool cancelled: false
    property bool playerStarted: false
    property string lastError: ""
    property var lastAccepted: ({})
    signal cueStarted(string kind)
    signal playbackFailed(string kind, string message)

    function play(kind) { return notify(kind) }

    function notify(kind) {
        var cue = cues[kind]
        if (!available || !cue) return false
        var now = Date.now()
        if (lastAccepted[kind] !== undefined && now - lastAccepted[kind] < cue.debounce) return false
        if (pending && cues[pending].priority > cue.priority) return false
        if (occupied && current && cues[current].priority >= cue.priority) return false
        lastAccepted[kind] = now
        pending = kind
        coalesce.restart()
        return true
    }

    function flush() {
        if (!available || !pending) return
        if (occupied) {
            // Await actual process exit before launching its replacement.
            if (playbackEnabled) { cancelled = true; player.running = false }
            else { simulatedPlayback.stop(); released() }
            return
        }
        current = pending
        pending = ""
        occupied = true
        cancelled = false
        playerStarted = false
        lastError = ""
        if (playbackEnabled) {
            player.command = ["mpv", "--no-config", "--no-video", "--really-quiet",
                "--volume=" + Math.max(0, Math.min(100, volume)), "--",
                appRoot + "/assets/sounds/" + cues[current].file]
            startupDeadline.restart()
            player.running = true
        } else {
            simulatedPlayback.interval = cues[current].duration
            simulatedPlayback.restart()
        }
        cueStarted(current)
    }

    function released() {
        startupDeadline.stop()
        occupied = false
        current = ""
        cancelled = false
        playerStarted = false
        if (pending && !coalesce.running) flush()
    }

    function reportFailure(kind, message) {
        lastError = message
        playbackFailed(kind, message)
        console.warn("learn-omarchy: interaction audio:", message)
    }

    function exited(exitCode, exitStatus) {
        if (occupied && !cancelled && (exitCode !== 0 || exitStatus !== 0))
            reportFailure(current, "Player exited unsuccessfully (" + exitCode + ")")
        released()
    }

    function startupExpired() {
        if (!occupied || playerStarted) return
        reportFailure(current, "Audio player did not start; check that mpv is installed")
        stop()
        // A failed-to-start process has no exited signal.
        if (!player.running) released()
    }

    function stop() {
        pending = ""
        coalesce.stop()
        simulatedPlayback.stop()
        startupDeadline.stop()
        if (occupied && playbackEnabled) { cancelled = true; player.running = false }
        else released()
    }

    onAvailableChanged: if (!available) stop()
    onVolumeChanged: if (occupied) stop()
    Component.onDestruction: stop()

    property Timer coalesce: Timer {
        interval: root.coalesceMs
        onTriggered: root.flush()
    }
    property Timer simulatedPlayback: Timer {
        onTriggered: root.released()
    }
    property Timer startupDeadline: Timer {
        interval: root.startupTimeoutMs
        onTriggered: root.startupExpired()
    }
    property Process player: Process {
        onStarted: { root.playerStarted = true; root.startupDeadline.stop() }
        onExited: function(exitCode, exitStatus) { root.exited(exitCode, exitStatus) }
    }
}
