import QtQuick

// Fixed decorative pixel primitives. Pack data selects these explicitly.
Item {
    id: effectRoot
    property string effect: ""
    property int count: 1
    property var colors: ["#f1c27d"]
    property color backgroundColor: "#182028"
    property color borderColor: "#8b97a8"
    property real period: 1600
    property real amplitude: 18
    property real elapsed: 0
    property real progress: 0
    Rectangle {
        anchors.fill: parent
        visible: effectRoot.effect === "strip"
        color: Qt.rgba(effectRoot.backgroundColor.r, effectRoot.backgroundColor.g, effectRoot.backgroundColor.b, 0.95)
        border.width: 2
        border.color: effectRoot.borderColor
    }
    Repeater {
        model: effectRoot.effect === "" ? 0 : effectRoot.count
        delegate: Item {
            id: particle
            required property int index
            readonly property real wave: Math.sin(effectRoot.elapsed * Math.PI * 2 / effectRoot.period + index * 1.7)
            readonly property real seedX: Math.sin((index + 1) * 12.9898) * 43758.5453
            readonly property real seedY: Math.sin((index + 1) * 78.233) * 12345.6789
            readonly property real fractionX: seedX - Math.floor(seedX)
            readonly property real fractionY: seedY - Math.floor(seedY)
            readonly property bool plume: effectRoot.effect === "plume"
            readonly property bool burst: effectRoot.effect === "burst"
            readonly property bool strip: effectRoot.effect === "strip"
            readonly property real reach: 60 + (index % 5) * 42
            width: plume ? 12 : strip ? 8 : burst ? 9 - (index % 3) * 2 : 2 + index % 3
            height: plume ? 26 : width
            x: plume ? effectRoot.width * (index + 1) / (effectRoot.count + 1) - width / 2
               : strip ? 8 + index * (effectRoot.width - 24) / Math.max(1, effectRoot.count - 1)
               : burst ? effectRoot.width / 2 + (index < effectRoot.count / 2 ? -1 : 1) * reach * effectRoot.progress
               : fractionX * effectRoot.width
            y: plume ? 0 : strip ? (effectRoot.height - height) / 2
               : burst ? effectRoot.height - (14 + (index % 5) * 10) * effectRoot.progress
               : fractionY * effectRoot.height + wave * effectRoot.amplitude
            scale: plume ? (index === Math.floor(effectRoot.count / 2) ? 5.2 : 3.6) * (1 + wave * 0.15) : 1
            transformOrigin: Item.Top
            opacity: plume ? 1 : strip ? (Math.floor(effectRoot.elapsed / 420) % 2 === index % 2 ? 1 : 0.35)
                     : burst ? Math.min(1, effectRoot.progress * 10) * (1 - effectRoot.progress)
                     : 0.25 + 0.65 * (wave + 1) / 2
            Rectangle {
                anchors.fill: parent
                visible: !particle.plume
                color: effectRoot.colors[particle.index % effectRoot.colors.length]
            }
            Rectangle { visible: particle.plume; x: 4; width: 4; height: 6; color: effectRoot.colors[0] }
            Rectangle { visible: particle.plume; x: 2; y: 5; width: 8; height: 7; color: effectRoot.colors[Math.min(1, effectRoot.colors.length - 1)] }
            Rectangle { visible: particle.plume; x: 3; y: 12; width: 6; height: 8; color: effectRoot.colors[Math.min(2, effectRoot.colors.length - 1)] }
            Rectangle { visible: particle.plume; x: 5; y: 20; width: 2; height: 6; color: effectRoot.colors[Math.min(2, effectRoot.colors.length - 1)] }
        }
    }
}
