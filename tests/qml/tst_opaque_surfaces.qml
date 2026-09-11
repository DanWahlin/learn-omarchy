import QtQuick
import QtTest

Item {
    id: harness
    width: 960
    height: 540
    property var fixture
    Rectangle { id: backdrop; anchors.fill: parent; color: "white" }

    TestCase {
        name: "OpaqueTextSurfaces"
        when: windowShown

        function initTestCase() {
            failOnWarning(/.*/)
            var request = new XMLHttpRequest()
            request.open("GET", Qt.resolvedUrl("../../app/shell.qml"), false)
            request.send()
            var source = request.responseText
            var appearance = source.slice(source.indexOf("  readonly property color panelColor:"),
                source.indexOf("  component PreferenceSwitch:"))
            var keycap = source.slice(source.indexOf("  component Keycap:"),
                source.indexOf("  function setCharacterState("))
            var start = source.indexOf("        Rectangle {\n          id: keyboardHint")
            var banner = source.slice(start, source.indexOf("        UiPanel {\n          id: teachingContent", start))
            var colorHelper = source.match(/^  function colorWithAlpha\([^\n]*\) \{[\s\S]*?^  \}/m)
            verify(appearance.length > 1000 && keycap.length > 100 && banner.length > 100 && colorHelper)
            fixture = Qt.createQmlObject(`import QtQuick
Item {
    id: root
    width: harness.width; height: harness.height
    property color background: "#1a1b26"
    property color foreground: "#c0caf5"
    property color accent: "#7aa2f7"
    property color instruction: "#e0af68"
    property color urgent: "#f7768e"
    property color muted: "#8992b7"
    property real textScale: 1
    property string phase: "menu"
    property bool referenceBrowsing: true
    property bool keyboardExclusive: false
    property bool keyboardFocused: false
    property bool exerciseRunning: false
    property QtObject controlPalette: QtObject { property color highlightedText: "black" }
    property alias button: sampleButton
    property alias panel: samplePanel
    property alias keycap: sampleKeycap
    property alias banner: keyboardHint
    function handleKeyPressed(event) {}
    function updateActiveKeys(event, pressed) {}
    function setKeyboardExclusive(value) { keyboardExclusive = value }
    function returnFromReference() { referenceBrowsing = false }
    ${colorHelper[0]}
    ${appearance}
    ${keycap}
    ${banner}
    UiPanel {
        id: samplePanel
        x: 30; y: 130; width: 300; height: 100
        Text { anchors.centerIn: parent; text: "A readable caption"; color: root.foreground }
    }
    UiButton {
        id: sampleButton
        x: 30; y: 280; width: 240; height: 44
        label: "SAMPLE BUTTON"
    }
    Keycap {
        id: sampleKeycap
        x: 30; y: 380; width: implicitWidth; height: implicitHeight
        label: "SUPER"
    }
}`, harness)
        }

        function init() {
            failOnWarning(/.*/)
            fixture.background = "#1a1b26"
            fixture.foreground = "#c0caf5"
            fixture.referenceBrowsing = true
            fixture.keyboardExclusive = false
            fixture.button.enabled = true
            fixture.button.kind = "secondary"
            fixture.forceActiveFocus()
            mouseMove(harness, 900, 510)
            wait(150)
        }

        function samples() {
            var image = grabImage(harness)
            var items = [fixture.button, fixture.panel, fixture.keycap, fixture.banner]
            var pixels = items.map(function(item) {
                var point = item.mapToItem(harness, 12, item.height / 2)
                return image.pixel(Math.round(point.x), Math.round(point.y))
            })
            var edge = fixture.keycap.mapToItem(harness, 12, fixture.keycap.height - 2)
            pixels.push(image.pixel(Math.round(edge.x), Math.round(edge.y)))
            return pixels
        }

        function verifyBackgroundBlocked() {
            backdrop.color = "#ff00ff"
            wait(30)
            var first = samples()
            backdrop.color = "#00ff00"
            wait(30)
            var second = samples()
            for (var i = 0; i < first.length; i++)
                compare(first[i], second[i], "surface " + i + " must block changing content behind it")
        }

        function test_buttonsStayOpaque_data() {
            var rows = []
            for (var light of [false, true])
                for (var kind of ["primary", "secondary", "ghost", "danger"])
                    for (var enabled of [true, false])
                        rows.push({ tag: [light, kind, enabled].join("-"),
                            light: light, kind: kind, enabled: enabled })
            return rows
        }

        function test_buttonsStayOpaque(data) {
            if (data.light) {
                fixture.background = "#f5f5f5"
                fixture.foreground = "#222222"
            }
            fixture.button.kind = data.kind
            fixture.button.enabled = data.enabled
            wait(150)
            compare(fixture.panelColor.a, 1)
            compare(fixture.subtleFill.a, 1)
            compare(fixture.button.color.a, 1)
            compare(fixture.button.opacity, 1)
            compare(fixture.button.activeFocus, false)
            verifyBackgroundBlocked()
            mouseMove(fixture.button, fixture.button.width / 2, fixture.button.height / 2)
            wait(150)
            compare(fixture.button.hovered, true)
            compare(fixture.button.color.a, 1)
            verifyBackgroundBlocked()
            if (data.enabled) {
                fixture.button.forceActiveFocus()
                compare(fixture.button.activeFocus, true)
                compare(fixture.button.color.a, 1)
                verifyBackgroundBlocked()
            }
        }

        function test_printReturnAndKeyboardBannersStaySolidWhenHovered() {
            for (var reference of [true, false]) {
                fixture.referenceBrowsing = reference
                mouseMove(fixture.banner, fixture.banner.width / 2, fixture.banner.height / 2)
                wait(30)
                compare(fixture.banner.color.a, 1)
                verifyBackgroundBlocked()
            }
        }
    }
}
