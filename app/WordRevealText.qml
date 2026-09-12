import QtQuick
import "CaptionTiming.js" as CaptionTiming

Text {
  id: root
  property string fullText: ""
  property int revealEnd: -1
  property bool reducedMotion: false
  property int fadeDuration: 160
  text: CaptionTiming.styledText(fullText, reducedMotion ? -1 : revealEnd)
  textFormat: Text.StyledText
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
