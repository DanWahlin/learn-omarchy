pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

Rectangle {
  id: root
  required property var arcade
  property string eyebrow: ""
  property bool centered: false
  property bool emphasizeChanges: false
  property bool attentionActive: false
  property bool neon: false
  property int cardPadding: arcade.compactLayout ? 18 : 24
  property real promptPixelSize: (arcade.compactLayout ? 23 : 28) * arcade.fontScale
  property real promptOpacity: 1
  property real promptOffset: 0
  property real emphasisOpacity: 0
  property real attentionOpacity: 0.12
  property real attentionTint: 0.32
  property real neonOpacity: 0.16
  readonly property bool emphasisRunning: promptEmphasis.running
  readonly property bool attentionRunning: promptAttention.running
  readonly property color promptColor: attentionActive
    ? Qt.tint(arcade.foregroundColor, Qt.rgba(arcade.modeAccent.r,
        arcade.modeAccent.g, arcade.modeAccent.b,
        arcade.reducedMotion ? 0.62 : attentionTint))
    : arcade.foregroundColor
  implicitHeight: content.implicitHeight + cardPadding * 2
  radius: 2
  color: neon ? Qt.tint(arcade.surfaceColor,
    Qt.rgba(arcade.modeAccent.r, arcade.modeAccent.g, arcade.modeAccent.b, 0.08))
    : arcade.surfaceColor
  border.color: arcade.hinted ? arcade.modeInk : Qt.tint(arcade.surfaceColor,
    Qt.rgba(arcade.modeAccent.r, arcade.modeAccent.g, arcade.modeAccent.b, 0.45))
  border.width: 2
  Accessible.role: Accessible.Grouping
  Accessible.name: arcade.hinted ? "Learn dock" : "Current shortcut"

  Rectangle {
    objectName: "arcadePromptNeonOuter"
    anchors.fill: parent
    anchors.margins: -10
    radius: 2
    color: "transparent"
    border.color: root.arcade.modeAccent
    border.width: 3
    opacity: root.neon ? root.neonOpacity * 0.45 : 0
    z: -2
  }

  Rectangle {
    objectName: "arcadePromptNeonInner"
    anchors.fill: parent
    anchors.margins: -5
    radius: 2
    color: "transparent"
    border.color: root.arcade.modeAccent
    border.width: 2
    opacity: root.neon ? root.neonOpacity : 0
    z: -1
  }

  function emphasize() {
    promptEmphasis.stop()
    promptOpacity = 1
    promptOffset = 0
    emphasisOpacity = 0
    if (!emphasizeChanges || arcade.reducedMotion || !arcade.currentPrompt) return
    promptOpacity = 0.55
    promptOffset = 8
    emphasisOpacity = 0.7
    promptEmphasis.start()
  }

  onEmphasizeChangesChanged: if (emphasizeChanges) Qt.callLater(emphasize)

  Connections {
    target: root.arcade
    function onCurrentPromptChanged() { root.emphasize() }
  }

  Rectangle {
    objectName: "arcadePromptEmphasis"
    anchors.fill: parent
    radius: root.radius
    color: "transparent"
    border.color: root.arcade.modeAccent
    border.width: 3
    opacity: root.emphasisOpacity
    z: 2
  }

  Rectangle {
    objectName: "arcadePromptAttention"
    anchors.fill: parent
    anchors.margins: -6
    radius: root.radius + 6
    color: "transparent"
    border.color: root.arcade.modeAccent
    border.width: 2
    opacity: root.attentionActive
      ? root.arcade.reducedMotion ? 0.28 : root.attentionOpacity
      : 0
    z: 1
  }

  ColumnLayout {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: root.cardPadding
    spacing: 12
    Text {
      objectName: "arcadePromptEyebrow"
      Layout.fillWidth: true
      text: root.eyebrow
      color: root.arcade.modeInk
      font.pixelSize: 11 * root.arcade.fontScale
      font.weight: Font.Bold
      font.letterSpacing: 1
      wrapMode: Text.WordWrap
      horizontalAlignment: root.centered ? Text.AlignHCenter : Text.AlignLeft
    }
    Text {
      objectName: "arcadePrompt"
      Layout.fillWidth: true
      text: root.arcade.currentPrompt
      color: root.promptColor
      font.pixelSize: root.promptPixelSize
      font.weight: Font.DemiBold
      wrapMode: Text.WordWrap
      horizontalAlignment: root.centered ? Text.AlignHCenter : Text.AlignLeft
      opacity: root.promptOpacity
      transform: Translate { y: root.promptOffset }
      Accessible.role: Accessible.StaticText
      Accessible.name: text
    }
    Text {
      objectName: "arcadeHintDetail"
      Layout.fillWidth: true
      visible: root.arcade.hintVisible && text.length > 0
      text: root.arcade.currentDetail
      color: root.arcade.mutedColor
      font.pixelSize: 14 * root.arcade.fontScale
      wrapMode: Text.WordWrap
      horizontalAlignment: root.centered ? Text.AlignHCenter : Text.AlignLeft
    }
    Item {
      Layout.fillWidth: true
      implicitHeight: hintKeys.implicitHeight
      visible: root.arcade.hintVisible
      ArcadeKeyPills {
        id: hintKeys
        objectName: "arcadeHintKeys"
        width: Math.min(implicitWidth, parent.width)
        anchors.left: root.centered ? undefined : parent.left
        anchors.horizontalCenter: root.centered ? parent.horizontalCenter : undefined
        arcade: root.arcade
        keys: root.arcade.expectedKeys
        revealed: true
      }
    }
  }

  ParallelAnimation {
    id: promptEmphasis
    NumberAnimation {
      target: root
      property: "promptOpacity"
      to: 1
      duration: 220
      easing.type: Easing.OutCubic
    }
    NumberAnimation {
      target: root
      property: "promptOffset"
      to: 0
      duration: 260
      easing.type: Easing.OutCubic
    }
    NumberAnimation {
      target: root
      property: "emphasisOpacity"
      to: 0
      duration: 650
      easing.type: Easing.OutCubic
    }
  }

  SequentialAnimation {
    id: promptAttention
    running: root.attentionActive && !root.arcade.reducedMotion
    loops: Animation.Infinite
    ParallelAnimation {
      NumberAnimation {
        target: root
        property: "attentionOpacity"
        from: 0.12
        to: 0.38
        duration: 1400
        easing.type: Easing.InOutSine
      }

      NumberAnimation {
        target: root
        property: "attentionTint"
        from: 0.32
        to: 0.78
        duration: 1400
        easing.type: Easing.InOutSine
      }
    }
    ParallelAnimation {
      NumberAnimation {
        target: root
        property: "attentionOpacity"
        from: 0.38
        to: 0.12
        duration: 1400
        easing.type: Easing.InOutSine
      }
      NumberAnimation {
        target: root
        property: "attentionTint"
        from: 0.78
        to: 0.32
        duration: 1400
        easing.type: Easing.InOutSine
      }
    }
  }

  SequentialAnimation {
    running: root.neon && root.visible && root.arcade.running && root.arcade.active
      && !root.arcade.reducedMotion
    loops: Animation.Infinite
    NumberAnimation {
      target: root
      property: "neonOpacity"
      from: 0.13
      to: 0.24
      duration: 1500
      easing.type: Easing.InOutSine
    }
    NumberAnimation {
      target: root
      property: "neonOpacity"
      from: 0.24
      to: 0.13
      duration: 1500
      easing.type: Easing.InOutSine
    }
  }
}
