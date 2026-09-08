import QtQuick

Rectangle {
    id: root
    property url source
    property bool active: false
    property bool ready: false
    property bool reducedMotion: false
    property color backgroundColor: "#1a1b26"
    property color foregroundColor: "#c0caf5"
    property int displayDuration: 1600
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
        finished()
    }
    function dismiss() {
        elapsed = true
        tryFinish()
    }
    onActiveChanged: {
        minimumDisplay.stop()
        if (!active) return
        dismissed = false
        elapsed = reducedMotion
        if (!elapsed) minimumDisplay.restart()
        forceActiveFocus()
        tryFinish()
    }
    onReadyChanged: tryFinish()
    onReducedMotionChanged: if (reducedMotion) dismiss()
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
    Image {
        id: artwork
        anchors.centerIn: parent
        width: Math.max(0, Math.min(1100, parent.width - 48, (parent.height - 100) * 1.5))
        height: width / 1.5
        source: root.source
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        mipmap: true
        onStatusChanged: if (status === Image.Error) root.imageFailed()
    }
    Text {
        visible: artwork.status !== Image.Ready
        anchors.centerIn: parent
        text: "LEARN OMARCHY"
        textFormat: Text.PlainText
        color: root.foregroundColor
        font.pixelSize: Math.min(36, root.width / 16)
        font.bold: true
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
