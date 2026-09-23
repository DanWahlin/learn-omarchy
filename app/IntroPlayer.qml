import QtQuick
import "IntroTimeline.js" as Timeline

Item {
    id: player
    property var sequence: null
    property string assetRoot: ""
    property string displayName: ""
    property bool reducedMotion: false
    property var introColors: ({})
    readonly property var defaultPalette: ({
        accent: "#718cba", instruction: "#f1c27d", foreground: "#d9e2ef",
        background: "#182028", muted: "#8b97a8", urgent: "#e87979"
    })
    readonly property bool running: phase !== "idle"
    readonly property real characterX: characterState.x === undefined ? width / 2 - 112 : characterState.x
    readonly property real characterY: characterState.y === undefined ? height * 0.75 - 192 : characterState.y
    readonly property real characterScale: characterState.scale === undefined ? 1 : characterState.scale
    readonly property real characterOpacity: characterState.opacity === undefined ? 1 : characterState.opacity
    readonly property bool characterVisible: !!characterState.visible
    readonly property string characterPose: characterState.pose || "idle"
    readonly property int characterFacing: characterState.facing || 1
    readonly property bool characterFlying: !!characterState.flying
    readonly property real characterRotation: characterState.rotation || 0
    readonly property var handoff: characterState
    property var characterState: ({ visible: false })
    property var layerDefinitions: []
    property var layerStates: ({})
    property var assetEntries: []
    property var loadedAssets: ({})
    property var nativeSizes: ({})
    property var timeline: null
    property string phase: "idle"
    property string failureMessage: ""
    property int generation: 0
    property real startedAt: 0
    property real elapsed: 0
    property int pendingAssets: 0
    property int nextSound: 0
    property bool initialized: false

    signal finished()
    signal cancelled()
    signal failed(string message)
    signal diagnostic(string message)
    signal soundRequested(string path)

    function stop(clearCharacter) {
        generation++
        clock.stop()
        phase = "idle"
        timeline = null
        layerDefinitions = []
        layerStates = ({})
        assetEntries = []
        loadedAssets = ({})
        nativeSizes = ({})
        pendingAssets = 0
        nextSound = 0
        if (clearCharacter) characterState = ({ visible: false })
    }
    function cancel() {
        var wasRunning = running
        stop(true)
        if (wasRunning) cancelled()
    }
    function reset() { cancel(); characterState = ({ visible: false }) }
    function fallback(message, failure) {
        stop(true)
        failureMessage = failure ? message : ""
        diagnostic(message)
        characterState = { x: width / 2 - 112, y: height * 0.75 - 192,
            visible: true, opacity: 1, scale: 1, pose: "idle", facing: 1, flying: false }
        phase = "fallback"
        elapsed = 0
        startedAt = Date.now()
        clock.restart()
    }
    function play() {
        cancel()
        failureMessage = ""
        if (sequence === null || sequence === undefined) {
            fallback("This pack has no intro sequence; using a static entrance.", false)
            return
        }
        var errors = Timeline.validateIntroSequence(sequence)
        if (errors.length) {
            fallback("Invalid intro sequence: " + errors.join("; "), true)
            return
        }
        if (reducedMotion) {
            fallback("Reduced motion: using a static entrance.", false)
            return
        }
        var paths = Timeline.introAssetPaths(sequence)
        if (paths.length && !/^file:\/\/\//.test(assetRoot)) {
            fallback("Intro assets require a local file URL pack directory.", true)
            return
        }
        timeline = Timeline.compile(sequence)
        layerDefinitions = timeline.layers
        phase = paths.length ? "loading" : "playing"
        elapsed = 0
        startedAt = Date.now()
        pendingAssets = paths.length
        var entries = []
        for (var i = 0; i < paths.length; i++) entries.push({ path: paths[i], token: generation })
        assetEntries = entries
        if (!pendingAssets) { updateFrame(); emitSoundCues() }
        if (running) clock.restart()
    }
    function assetUrl(path) { return assetRoot.replace(/\/+$/, "") + "/" + path }
    function assetReady(path, token, w, h) {
        if (token !== generation || phase !== "loading" || loadedAssets[path]) return
        loadedAssets[path] = true
        var sizes = nativeSizes
        for (var i = 0; i < layerDefinitions.length; i++) {
            var layer = layerDefinitions[i]
            if (layer.images && layer.images[0] === path) sizes[layer.id] = { width: w, height: h }
        }
        nativeSizes = sizes
        pendingAssets--
        if (!pendingAssets) {
            phase = "playing"
            elapsed = 0
            startedAt = Date.now()
            updateFrame()
            emitSoundCues()
        }
    }
    function assetFailed(path, token) {
        if (token !== generation || !running) return
        fallback("Unable to load intro asset: " + path, true)
    }
    function updateFrame() {
        if (!timeline) return
        var states = Timeline.sample(timeline, elapsed, width, height, nativeSizes)
        characterState = states.character
        layerStates = states
    }
    function emitSoundCues() {
        var token = generation
        while (token === generation && phase === "playing" && timeline &&
               nextSound < timeline.sounds.length && timeline.sounds[nextSound].at <= elapsed) {
            var cue = timeline.sounds[nextSound++].cue
            soundRequested(cue)
        }
    }
    function complete() {
        var message = failureMessage
        // Keep the nominal production-body placement for the host-owned flight.
        var finalCharacter = characterState
        stop(false)
        characterState = finalCharacter
        failureMessage = ""
        if (message) failed(message)
        else finished()
    }
    function tick() {
        if (!running) return
        elapsed = Date.now() - startedAt
        if (phase === "loading") {
            if (elapsed > 2000) fallback("Intro asset loading timed out.", true)
        } else if (phase === "fallback") {
            if (elapsed >= 250) complete()
        } else {
            var token = generation
            updateFrame()
            emitSoundCues()
            if (token !== generation || phase !== "playing" || !timeline) return
            if (elapsed >= timeline.duration) complete()
        }
    }
    function resized() {
        if (phase === "playing") updateFrame()
        else if (phase === "fallback") {
            var state = characterState
            state.x = width / 2 - 112
            state.y = height * 0.75 - 192
            characterState = Object.assign({}, state)
        }
    }
    function substituted(text) {
        return String(text || "").split("{displayName}").join(String(displayName).substring(0, 80))
    }
    function resolveColor(value) {
        if (typeof value === "string" && value.indexOf("theme:") === 0) {
            var key = value.substring(6)
            if (Timeline.THEME_COLORS.indexOf(key) >= 0) {
                var candidate = String((introColors || {})[key] || "")
                return /^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(candidate) ? candidate : defaultPalette[key]
            }
        }
        return Timeline.color(value) ? value : defaultPalette.foreground
    }
    function layerColors(definition) {
        return (definition.colors || ["theme:instruction", "theme:foreground", "theme:accent"]).map(resolveColor)
    }
    onSequenceChanged: if (initialized) cancel()
    onAssetRootChanged: if (initialized) cancel()
    onReducedMotionChanged: if (running && reducedMotion) fallback("Reduced motion: using a static entrance.", false)
    onWidthChanged: resized()
    onHeightChanged: resized()
    Component.onCompleted: initialized = true
    Component.onDestruction: { generation++; clock.stop() }

    Timer { id: clock; interval: 16; repeat: true; onTriggered: player.tick() }

    Repeater {
        model: player.assetEntries
        delegate: Image {
            required property var modelData
            visible: false
            source: player.assetUrl(modelData.path)
            asynchronous: true
            onStatusChanged: {
                if (status === Image.Ready) player.assetReady(modelData.path, modelData.token, implicitWidth, implicitHeight)
                else if (status === Image.Error) player.assetFailed(modelData.path, modelData.token)
            }
        }
    }
    Repeater {
        model: player.layerDefinitions
        delegate: Item {
            id: layerItem
            required property var modelData
            readonly property var definition: modelData
            readonly property var layerState: player.layerStates[definition.id] || ({})
            readonly property bool active: player.phase === "playing" && layerState.visible === true
            readonly property real age: player.elapsed
            x: layerState.x || 0
            y: layerState.y || 0
            width: layerState.width || 0
            height: layerState.height || 0
            z: definition.z || 0
            visible: active
            opacity: layerState.opacity === undefined ? 1 : layerState.opacity
            scale: layerState.scale === undefined ? 1 : layerState.scale
            rotation: layerState.rotation || 0
            transformOrigin: Item.Bottom
            Image {
                objectName: "introImage-" + layerItem.definition.id
                anchors.fill: parent
                visible: layerItem.definition.type === "image"
                source: visible && layerItem.definition.images
                    ? player.assetUrl(layerItem.definition.images[layerItem.layerState.frame || 0]) : ""
                fillMode: Image.Stretch
                smooth: false
                mipmap: false
            }
            Rectangle {
                objectName: "introCueBackground"
                visible: layerItem.definition.type === "text"
                x: -10
                y: -10
                width: prompt.implicitWidth + 20
                height: prompt.implicitHeight + 20
                readonly property color panelColor: player.resolveColor(layerItem.definition.background || "theme:background")
                color: Qt.rgba(panelColor.r, panelColor.g, panelColor.b, 1)
                border.color: player.resolveColor(layerItem.definition.border || "theme:accent")
                radius: 4
            }
            Text {
                id: prompt
                objectName: "introCueText"
                visible: layerItem.definition.type === "text"
                readonly property string fullText: player.substituted(layerItem.layerState.text)
                text: layerItem.definition.typewriter
                    ? fullText.substring(0, Math.floor(Math.max(0, layerItem.age - (layerItem.layerState.textAt || 0)) / 34)) +
                      (Math.floor(layerItem.age / 480) % 2 ? " " : "█")
                    : fullText
                textFormat: Text.PlainText
                color: player.layerColors(layerItem.definition)[0]
                font.family: "monospace"
                font.pixelSize: layerItem.definition.fontSize || 20
                font.bold: true
            }
            IntroEffect {
                anchors.fill: parent
                visible: layerItem.definition.type === "effect"
                effect: layerItem.definition.effect || ""
                count: layerItem.definition.count || 1
                colors: player.layerColors(layerItem.definition)
                backgroundColor: player.resolveColor(layerItem.definition.background || "theme:background")
                borderColor: player.resolveColor(layerItem.definition.border || "theme:muted")
                period: layerItem.definition.period || 1600
                amplitude: layerItem.definition.amplitude === undefined ? 18 : layerItem.definition.amplitude
                elapsed: layerItem.age
                progress: layerItem.layerState.progress || 0
            }
        }
    }
}
