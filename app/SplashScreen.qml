import QtQuick

Rectangle {
    id: root
    property url source
    property bool active: false
    property bool ready: false
    property bool reducedMotion: false
    property color backgroundColor: "#020c1a"
    property color foregroundColor: "#c0caf5"
    property int displayDuration: 1600
    property int fadeDuration: 650
    readonly property bool transitioning: fadeOut.running
    property bool elapsed: false
    property bool dismissed: false
    signal finished()
    signal imageFailed()

    color: backgroundColor
    visible: active
    focus: active
    Accessible.role: Accessible.Pane
    Accessible.name: "Learn Omarchy welcome screen"

    function tryFinish() {
        if (!active || dismissed || !ready || !elapsed) return
        dismissed = true
        if (reducedMotion) finished()
        else fadeOut.restart()
    }
    function dismiss() {
        elapsed = true
        tryFinish()
    }
    onActiveChanged: {
        minimumDisplay.stop()
        fadeOut.stop()
        opacity = 1
        if (!active) return
        dismissed = false
        elapsed = reducedMotion
        if (!elapsed) minimumDisplay.restart()
        forceActiveFocus()
        tryFinish()
    }
    onReadyChanged: tryFinish()
    onReducedMotionChanged: {
        if (!reducedMotion) return
        if (transitioning) {
            fadeOut.stop()
            if (active) finished()
        } else dismiss()
    }
    Component.onCompleted: {
        if (active) {
            elapsed = reducedMotion
            if (!elapsed) minimumDisplay.restart()
            tryFinish()
        }
    }
    Timer {
        id: minimumDisplay
        interval: root.displayDuration
        onTriggered: root.dismiss()
    }
    NumberAnimation {
        id: fadeOut
        target: root
        property: "opacity"
        from: 1
        to: 0
        duration: root.fadeDuration
        easing.type: Easing.InOutSine
        onFinished: if (root.active) root.finished()
    }
    SplashArtwork {
        id: artwork
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        objectName: "splashArtwork"
        width: parent.width
        height: Math.max(0, parent.height - 64)
        source: root.source
        foregroundColor: root.foregroundColor
        onLoadFailed: root.imageFailed()
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
        text: root.ready ? "Click or press Enter to continue" : "Getting things ready…"
        textFormat: Text.PlainText
        color: root.foregroundColor
        font.pixelSize: 14
    }
    MouseArea {
        anchors.fill: parent
        onClicked: root.dismiss()
    }
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter ||
            event.key === Qt.Key_Space || event.key === Qt.Key_Escape) root.dismiss()
        event.accepted = true
    }
}
