import QtQuick

Image {
    id: root
    property color foregroundColor: "#edf1f6"
    readonly property bool artworkReady: status === Image.Ready
    readonly property string artworkError: status === Image.Error
        ? "Cannot load splash illustration: " + source : ""
    signal loadFailed()

    onStatusChanged: if (status === Image.Error) loadFailed()
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    smooth: true
    mipmap: true
    Accessible.role: Accessible.Graphic
    Accessible.name: "Learn Omarchy. Your desktop. Your way. Ohm and Ollie beside a tiled desktop."

    Text {
        objectName: "splashFallback"
        visible: !root.artworkReady
        anchors.centerIn: parent
        text: "LEARN OMARCHY"
        textFormat: Text.PlainText
        color: root.foregroundColor
        font.family: "monospace"
        font.bold: true
        font.pixelSize: Math.min(48, root.width / 15)
    }
}
