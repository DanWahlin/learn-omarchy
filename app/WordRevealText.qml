import QtQuick
import "CaptionTiming.js" as CaptionTiming

Text {
  id: root
  property string fullText: ""
  property int revealEnd: -1
  text: CaptionTiming.styledText(fullText, revealEnd)
  textFormat: Text.StyledText
  wrapMode: Text.Wrap
  horizontalAlignment: Text.AlignLeft
  lineHeight: 1.2
  Accessible.role: Accessible.StaticText
  Accessible.name: fullText
}
