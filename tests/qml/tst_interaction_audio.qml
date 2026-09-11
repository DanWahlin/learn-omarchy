import QtQuick
import QtTest

Item {
    id: harness
    property var audio
    SignalSpy { id: started; target: audio; signalName: "cueStarted" }
    TestCase {
        name: "InteractionAudio"
        when: windowShown
        function initTestCase() {
            var request = new XMLHttpRequest()
            request.open("GET", Qt.resolvedUrl("../../app/InteractionAudio.qml"), false)
            request.send()
            // Quickshell's process plugin is executable-linked. Substitute only
            // that boundary for QtTest; the Node smoke test loads the real type.
            var source = request.responseText.replace("import Quickshell.Io", "")
                .replace("property Process player: Process {",
                    "property QtObject player: QtObject { property bool running: false; property var command: []; signal started(); signal exited(int exitCode, int exitStatus);")
            audio = Qt.createQmlObject(source, harness)
            audio.playbackEnabled = false
            audio.coalesceMs = 20
        }
        function init() {
            failOnWarning(/.*/)
            audio.stop()
            audio.lastAccepted = ({})
            audio.enabled = true
            audio.paused = false
            audio.suspended = false
            audio.volume = 45
            started.clear()
        }
        function cleanup() { audio.stop() }
        function test_coalescesTheFinalActionAndCompletion() {
            verify(audio.notify("correct"))
            verify(audio.notify("step-complete"))
            verify(audio.notify("module-complete"))
            verify(!audio.notify("wrong"))
            tryCompare(started, "count", 1)
            compare(started.signalArguments[0][0], "module-complete")
            compare(audio.current, "module-complete")
            verify(!audio.notify("correct"))
            tryCompare(audio, "busy", false)
            compare(started.count, 1)
        }
        function test_repeatedWrongChordIsDebounced() {
            verify(audio.notify("wrong"))
            verify(!audio.notify("wrong"))
            tryCompare(started, "count", 1)
            tryCompare(audio, "busy", false)
            verify(!audio.notify("wrong"))
            wait(450)
            verify(audio.notify("wrong"))
            tryCompare(started, "count", 2)
        }
        function test_completionReplacesALowerPriorityCue() {
            audio.notify("correct")
            tryCompare(started, "count", 1)
            verify(audio.notify("module-complete"))
            tryCompare(started, "count", 2)
            compare(audio.current, "module-complete")
            verify(!audio.notify("step-complete"))
        }
        function test_masterMuteEffectsVolumeAndSuspensionCancelPendingAndActive() {
            for (var field of ["enabled", "volume", "suspended", "paused"]) {
                audio.lastAccepted = ({})
                audio.notify("step-complete")
                audio[field] = field === "suspended" || field === "paused" ? true : field === "volume" ? 0 : false
                verify(!audio.busy)
                verify(!audio.notify("correct"))
                wait(40)
                compare(started.count, 0)
                audio[field] = field === "volume" ? 45 : field === "enabled"
                verify(audio.notify("correct"))
                tryCompare(started, "count", 1)
                audio[field] = field === "suspended" || field === "paused" ? true : field === "volume" ? 0 : false
                verify(!audio.busy)
                audio[field] = field === "volume" ? 45 : field === "enabled"
                started.clear()
            }
            verify(!audio.notify("../../not-a-cue"))
        }
        function test_playApiAndFailuresAreExplicitWithoutFailingTheLesson() {
            verify(audio.play("wrong"))
            tryCompare(started, "count", 1)
            ignoreWarning(/learn-omarchy: interaction audio:.*/)
            audio.exited(7, 0)
            verify(audio.lastError.indexOf("7") >= 0)
            verify(!audio.busy)
            verify(audio.play("step-complete"))
            tryCompare(started, "count", 2)
            compare(audio.lastError, "")
            ignoreWarning(/learn-omarchy: interaction audio:.*/)
            audio.startupExpired()
            verify(audio.lastError.indexOf("mpv") >= 0)
            verify(!audio.busy)
        }
    }
}
