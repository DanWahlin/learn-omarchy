import QtQuick
import QtTest
import "../../app" as App
import "../../app/IntroTimeline.js" as Timeline

Item {
    id: scene
    property bool cancelOnSound: false
    width: 1000
    height: 800
    App.IntroPlayer { id: player; anchors.fill: parent }
    App.CharacterSprite {
        id: coach
        z: 10
        x: player.characterX
        y: player.characterY
        scale: player.characterScale
        opacity: player.characterOpacity
        visible: player.characterVisible && config.formatVersion === 1
        pose: player.characterPose
        facing: player.characterFacing
        flying: player.characterFlying
        assetRoot: player.assetRoot
        transformOrigin: Item.Bottom
        previewFrame: 0
    }
    SignalSpy { id: done; target: player; signalName: "finished" }
    SignalSpy { id: cancelled; target: player; signalName: "cancelled" }
    SignalSpy { id: failed; target: player; signalName: "failed" }
    SignalSpy { id: diagnostics; target: player; signalName: "diagnostic" }
    SignalSpy { id: sounds; target: player; signalName: "soundRequested" }
    Connections {
        target: player
        function onSoundRequested(path) { if (scene.cancelOnSound) player.cancel() }
    }
    TestCase {
        name: "DataOnlyIntro"
        when: windowShown
        function init() {
            player.reset()
            player.reducedMotion = false
            player.sequence = null
            player.assetRoot = ""
            player.palette = ({})
            coach.config = ({})
            scene.cancelOnSound = false
            scene.width = 1000
            scene.height = 800
            done.clear(); cancelled.clear(); failed.clear(); diagnostics.clear(); sounds.clear()
        }
        function simple(duration) {
            return { version: 1, layers: [], character: { visible: true, x: 0, offsetX: 0 },
                steps: [{ type: "tween", target: "character", to: { x: 0.8 }, duration: duration }] }
        }
        function loadSequence(pack) {
            var request = new XMLHttpRequest()
            request.open("GET", Qt.resolvedUrl("../../" + pack + "/intro/sequence.json"), false)
            request.send()
            return JSON.parse(request.responseText)
        }
        function test_singleCompletionAndHandoff() {
            player.sequence = simple(80)
            player.play()
            tryCompare(done, "count", 1)
            compare(player.running, false)
            compare(player.characterVisible, true)
            compare(player.characterX, 800)
            wait(120)
            compare(done.count, 1)
            player.reset()
            compare(player.characterVisible, false)
        }
        function test_cancelRestartRejectsStaleAssets() {
            player.sequence = simple(180)
            player.play()
            var oldToken = player.generation
            wait(30)
            player.cancel()
            compare(cancelled.count, 1)
            compare(player.characterVisible, false)
            player.sequence = simple(50)
            player.play()
            player.assetFailed("stale.png", oldToken)
            tryCompare(done, "count", 1)
            wait(220)
            compare(done.count, 1)
            compare(failed.count, 0)
        }
        function test_switchCancelsOldSequence() {
            player.sequence = simple(140)
            player.play()
            player.assetRoot = Qt.resolvedUrl("../../assets/characters/hexon").toString()
            compare(cancelled.count, 1)
            wait(180)
            compare(done.count, 0)
            player.play()
            player.sequence = simple(30)
            compare(cancelled.count, 2)
            player.play()
            tryCompare(done, "count", 1)
        }
        function test_parallelJoin() {
            player.sequence = { version: 1, layers: [], steps: [
                { type: "parallel", branches: [
                    [{ type: "wait", duration: 35 }, { type: "set", target: "character", to: { facing: -1 } }],
                    [{ type: "wait", duration: 150 }, { type: "set", target: "character", to: { visible: true } }]
                ] },
                { type: "set", target: "character", to: { pose: "point" } }
            ] }
            player.play()
            wait(70)
            compare(done.count, 0)
            compare(player.characterFacing, -1)
            tryCompare(done, "count", 1)
            compare(player.characterPose, "point")
            compare(player.characterVisible, true)
        }
        function soundSequence() {
            return { version: 1, layers: [], steps: [
                { type: "sound", cue: "rocket-land.opus" },
                { type: "wait", duration: 70 },
                { type: "sound", cue: "rocket-liftoff.opus" },
                { type: "wait", duration: 100 }
            ] }
        }
        function test_soundCuesOnceAndCancellation() {
            player.sequence = soundSequence()
            player.play()
            compare(sounds.count, 1)
            compare(sounds.signalArguments[0][0], "rocket-land.opus")
            tryCompare(done, "count", 1)
            compare(sounds.count, 2)
            compare(sounds.signalArguments[1][0], "rocket-liftoff.opus")
            player.play()
            compare(sounds.count, 3)
            player.cancel()
            wait(220)
            compare(sounds.count, 3)
            player.reducedMotion = true
            player.play()
            tryCompare(done, "count", 2, 400)
            compare(sounds.count, 3)
        }
        function test_soundCallbackCanCancelSynchronously() {
            player.sequence = soundSequence()
            scene.cancelOnSound = true
            player.play()
            compare(player.running, false)
            compare(cancelled.count, 1)
            wait(220)
            compare(done.count, 0)
            compare(sounds.count, 1)
        }
        function test_themePaletteIsLiveAndAllowlisted() {
            player.sequence = simple(1000)
            player.play()
            var token = player.generation
            player.palette = { foreground: "#123456", instruction: Qt.rgba(1, 0, 0, 1),
                background: "not-a-color", secret: "#abcdef" }
            compare(player.resolveColor("theme:foreground"), "#123456")
            compare(player.resolveColor("theme:instruction"), "#ff0000")
            compare(player.resolveColor("theme:background"), player.defaultPalette.background)
            compare(player.resolveColor("#aabbcc"), "#aabbcc")
            compare(player.resolveColor("theme:secret"), player.defaultPalette.foreground)
            compare(player.generation, token)
            verify(player.running)
        }
        function test_cueTextAndDisplayNameStayLiteral() {
            player.displayName = '<b>NAME</b><img src="missing.png">$&'
            player.sequence = { version: 1,
                layers: [{ id: "label", type: "text", state: { text: "> {displayName}" } }],
                steps: [{ type: "wait", duration: 1000 }] }
            player.play()
            var cue = findChild(player, "introCueText")
            verify(cue !== null)
            compare(cue.textFormat, Text.PlainText)
            compare(cue.text, '> <b>NAME</b><img src="missing.png">$&')
            compare(player.substituted("{displayName}/{displayName}"),
                player.displayName + "/" + player.displayName)
        }
        function test_optionalAndReducedMotion() {
            player.play()
            compare(player.characterVisible, true)
            tryCompare(done, "count", 1, 400)
            compare(diagnostics.count, 1)
            player.sequence = simple(20000)
            player.reducedMotion = true
            player.play()
            compare(player.characterFlying, false)
            tryCompare(done, "count", 2, 400)
        }
        function test_midRunReducedMotionAndResize() {
            player.sequence = simple(2000)
            player.play()
            wait(50)
            var before = player.characterX
            scene.width = 2000
            compare(player.characterX, before * 2)
            player.reducedMotion = true
            compare(player.phase, "fallback")
            scene.height = 1000
            compare(player.characterY, 558)
            tryCompare(done, "count", 1, 400)
            compare(cancelled.count, 0)
        }
        function test_invalidAndRuntimeAssetFailure() {
            player.sequence = { version: 1, layers: [], steps: [{ type: "script", source: "bad()" }] }
            player.play()
            compare(player.characterVisible, true)
            tryCompare(failed, "count", 1, 400)
            compare(done.count, 0)
            player.assetRoot = Qt.resolvedUrl("../../assets/characters/hexon").toString()
            player.sequence = { version: 1,
                layers: [{ id: "missing", type: "image", images: ["sprites/does-not-exist.png"] }],
                steps: [{ type: "wait", duration: 5000 }] }
            player.play()
            tryCompare(failed, "count", 2, 1500)
            compare(player.characterVisible, true)
            compare(player.running, false)
            compare(done.count, 0)
        }
        function test_resizeReevaluatesTypedAnchors() {
            var timeline = Timeline.compile({
                version: 1,
                layers: [{ id: "anchor", type: "image", images: ["sprites/a.png"],
                    height: { viewport: 0.5, min: 100, max: 700 }, anchorX: 0.5, state: { x: 0.5 } }],
                character: { x: { layer: "anchor", anchor: 1 }, offsetX: 0 }, steps: []
            })
            var sizes = { anchor: { width: 100, height: 200 } }
            compare(Timeline.sample(timeline, 0, 1000, 800, sizes).character.x, 600)
            compare(Timeline.sample(timeline, 0, 2000, 1000, sizes).character.x, 1125)
        }
        function test_officialScenes_data() {
            return [{ tag: "HEXON", pack: "assets/characters/hexon" },
                    { tag: "OLLIE", pack: "assets/characters/owl" },
                    { tag: "SPARK", pack: "examples/characters/spark" }]
        }
        function test_officialScenes(data) {
            player.assetRoot = Qt.resolvedUrl("../../" + data.pack).toString()
            player.sequence = loadSequence(data.pack)
            var request = new XMLHttpRequest()
            request.open("GET", Qt.resolvedUrl("../../" + data.pack + "/character.json"), false)
            request.send()
            coach.config = JSON.parse(request.responseText)
            player.displayName = "<b>LOCAL</b>"
            player.play()
            tryCompare(player, "phase", "playing")
            compare(failed.count, 0)
            var duration = player.timeline.duration
            player.elapsed = Math.min(2400, duration - 1)
            player.startedAt = Date.now() - player.elapsed
            player.updateFrame()
            verify(player.characterVisible)
            tryCompare(coach, "errorMessage", "")
            waitForRendering(scene)
            var snapshot = grabImage(scene)
            compare(snapshot.width, scene.width)
            compare(snapshot.height, scene.height)
            player.startedAt = Date.now() - duration - 1
            player.tick()
            compare(done.count, 1)
            compare(player.running, false)
            compare(player.characterVisible, true)
        }
    }
}
