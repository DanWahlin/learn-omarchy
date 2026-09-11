import QtQuick

Text {
  id: root
  property string fullText: ""
  property int revealEnd: -1
  property bool reducedMotion: false
  property int fadeDuration: 160
  // Keep the timing input for existing narration/reading clocks. Presentation
  // fades the whole caption once, rather than reserving rows of invisible words.
  text: fullText
  textFormat: Text.PlainText
  wrapMode: Text.Wrap
  horizontalAlignment: Text.AlignLeft
  lineHeight: 1.2
  Accessible.role: Accessible.StaticText
  Accessible.name: fullText
  onFullTextChanged: {
    entrance.stop()
    opacity = reducedMotion || !visible || !fullText ? 1 : 0
    if (opacity === 0) entrance.restart()
  }
  onReducedMotionChanged: if (reducedMotion) { entrance.stop(); opacity = 1 }
  NumberAnimation {
    id: entrance
    target: root
    property: "opacity"
    to: 1
    duration: root.fadeDuration
    easing.type: Easing.OutQuad
  }
}
