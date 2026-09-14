pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

ColumnLayout {
  id: root
  required property var arcade
  readonly property var controls: [resultsButton]
  readonly property string title: arcade.mode === "rescue" ? "Destination reached"
    : arcade.mode === "sprint" ? "Time's up" : "Round complete"
  readonly property string detail: arcade.mode === "rescue"
    ? arcade.rescueMission ? arcade.rescueMission.success : "The desktop rescue is complete."
    : arcade.mode === "sprint"
    ? "You completed " + arcade.answeredCount + " shortcut" + (arcade.answeredCount === 1 ? "" : "s") + " in this sprint."
    : "You finished " + arcade.answeredCount + " prompt" + (arcade.answeredCount === 1 ? "" : "s") + "."
  spacing: 0

  ColumnLayout {
    Layout.fillWidth: true
    Layout.maximumWidth: 680 * root.arcade.textScale
    Layout.alignment: Qt.AlignHCenter
    spacing: 16 * root.arcade.textScale

    ArcadeModePreview {
      visible: root.arcade.mode !== "rescue"
      Layout.preferredWidth: 300 * root.arcade.textScale
      Layout.preferredHeight: 96 * root.arcade.textScale
      Layout.alignment: Qt.AlignHCenter
      arcade: root.arcade
      mode: root.arcade.mode
    }
    ArcadeRescueJourney {
      objectName: "arcadeRescueArrival"
      visible: root.arcade.mode === "rescue"
      Layout.fillWidth: true
      Layout.preferredHeight: 92 * root.arcade.textScale
      arcade: root.arcade
      completedActions: root.arcade.runTarget
      totalSteps: root.arcade.runTarget
      showBurst: false
    }
    ArcadePixelText {
      objectName: "arcadeRoundCompleteTitle"
      Layout.fillWidth: true
      text: root.title
      color: root.arcade.foregroundColor
      font.pixelSize: 25 * root.arcade.fontScale
      horizontalAlignment: Text.AlignHCenter
    }
    Text {
      objectName: "arcadeRoundCompleteDetail"
      Layout.fillWidth: true
      text: root.detail
      color: root.arcade.mutedColor
      font.pixelSize: 16 * root.arcade.fontScale
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
    }
    ArcadeButton {
      id: resultsButton
      objectName: "arcadeSeeResults"
      Layout.alignment: Qt.AlignHCenter
      arcade: root.arcade
      text: "See results · Enter"
      primary: true
      navigationSelected: root.arcade.selectedControl === resultsButton
      onClicked: root.arcade.showResults()
    }
  }
}
