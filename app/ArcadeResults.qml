pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

ColumnLayout {
  id: root
  required property var arcade
  readonly property var controls: practice.visible ? [practice, replay, hub] : [replay, fresh, hub]
  readonly property string recordContext: {
    if (!arcade.competitive)
      return "Practice saved. Challenge records stay unchanged."
    if (!arcade.previousBest.plays)
      return "First score for this deck."
    if (arcade.newBest)
      return "New personal best."
    if (arcade.newBestPace)
      return "Matched your best score with a faster pace."
    var difference = arcade.finalScore - arcade.previousBest.bestScore
    if (difference === 0) return "Matched your personal best."
    return Math.abs(difference) + " points " + (difference > 0 ? "above" : "below") + " your best."
  }
  readonly property string totalsText: arcade.mode === "rescue"
    ? arcade.finalClean + " of " + arcade.answeredCount + " actions on the first try"
    : arcade.finalClean + " of " + arcade.answeredCount + " on the first try"
      + "  ·  " + arcade.formatTime(arcade.finalElapsedMs) + " active"
  spacing: 0

  ColumnLayout {
    objectName: "arcadeResultsLayout"
    Layout.fillWidth: true
    Layout.maximumWidth: 760 * root.arcade.textScale
    Layout.alignment: Qt.AlignHCenter
    spacing: 12 * root.arcade.textScale

    ArcadeModePreview {
      Layout.preferredWidth: Math.min(320 * root.arcade.textScale,
        root.arcade.compactLayout ? root.arcade.width - 80 : 320 * root.arcade.textScale)
      Layout.preferredHeight: 96 * root.arcade.textScale
      Layout.alignment: Qt.AlignHCenter
      arcade: root.arcade
      mode: root.arcade.mode
    }

    ColumnLayout {
      objectName: "arcadeResultsCopy"
      Layout.fillWidth: true
      spacing: 5 * root.arcade.textScale
      ArcadePixelText {
        Layout.fillWidth: true
        text: root.arcade.resultTitle
        color: root.arcade.foregroundColor
        font.pixelSize: 22 * root.arcade.fontScale
        horizontalAlignment: Text.AlignHCenter
      }
      Item {
        objectName: "arcadeResultScoreboard"
        Layout.preferredWidth: Math.min(360 * root.arcade.textScale,
          root.arcade.width - 96 * root.arcade.textScale)
        Layout.preferredHeight: 68 * root.arcade.textScale
        Layout.alignment: Qt.AlignHCenter
        Rectangle {
          anchors.fill: parent
          anchors.margins: -7 * root.arcade.textScale
          radius: 2
          color: root.arcade.modeAccent
          opacity: 0.1
        }
        Rectangle {
          anchors.fill: parent
          radius: 2
          color: Qt.tint(root.arcade.surfaceColor,
            Qt.rgba(root.arcade.modeAccent.r, root.arcade.modeAccent.g,
              root.arcade.modeAccent.b, 0.13))
          border.color: root.arcade.modeInk
          border.width: 2
        }
        ArcadePixelText {
          objectName: "arcadeResultScore"
          anchors.centerIn: parent
          text: root.arcade.finalScore + " POINTS"
          color: root.arcade.modeInk
          font.pixelSize: Math.min(23 * root.arcade.fontScale,
            (parent.width - 32 * root.arcade.textScale) * 7 / (text.length * 6 - 1))
        }
      }
      Text {
        objectName: "arcadeResultTotalsLine"
        Layout.preferredWidth: Math.min(560 * root.arcade.textScale,
          root.arcade.width - 96 * root.arcade.textScale)
        Layout.alignment: Qt.AlignHCenter
        text: root.totalsText
        color: root.arcade.foregroundColor
        font.pixelSize: 14 * root.arcade.fontScale
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
      }
    }

    Text {
      objectName: "arcadeRecordContext"
      Layout.fillWidth: true
      visible: root.arcade.mode !== "rescue"
      text: root.recordContext
      color: root.arcade.mutedColor
      font.pixelSize: 13 * root.arcade.fontScale
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
    }
    Text {
      objectName: "arcadePracticeSummary"
      Layout.fillWidth: true
      visible: root.arcade.mode !== "rescue" && root.arcade.weakRunIds.length > 0
      text: root.arcade.weakRunIds.length + " shortcut"
        + (root.arcade.weakRunIds.length === 1 ? "" : "s") + " ready to practice again."
      color: root.arcade.modeInk
      font.pixelSize: 13 * root.arcade.fontScale
      font.weight: Font.DemiBold
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
    }

    GridLayout {
      Layout.fillWidth: root.arcade.compactLayout
      Layout.alignment: Qt.AlignHCenter
      columns: root.arcade.compactLayout ? 1 : 3
      columnSpacing: 8
      rowSpacing: 8

      ArcadeButton {
        id: practice
        objectName: "arcadePracticeWeakButton"
        visible: root.arcade.weakRunIds.length > 0
        Layout.fillWidth: root.arcade.compactLayout
        arcade: root.arcade
        text: root.arcade.mode === "rescue" ? "Practice this mission"
          : "Practice " + root.arcade.weakRunIds.length + " shortcut"
            + (root.arcade.weakRunIds.length === 1 ? "" : "s")
        primary: true
        navigationSelected: root.arcade.selectedControl === practice
        onClicked: root.arcade.practiceThose(root.arcade.weakRunIds, root.arcade.mode)
      }
      ArcadeButton {
        id: replay
        objectName: "arcadeReplayButton"
        Layout.fillWidth: root.arcade.compactLayout
        arcade: root.arcade
        text: "Play again"
        primary: !practice.visible
        navigationSelected: root.arcade.selectedControl === replay
        onClicked: root.arcade.raceDeck()
      }
      ArcadeButton {
        id: fresh
        objectName: "arcadeFreshButton"
        visible: !practice.visible
        Layout.fillWidth: root.arcade.compactLayout
        arcade: root.arcade
        text: root.arcade.mode === "rescue" ? "New mission" : "New deck"
        navigationSelected: root.arcade.selectedControl === fresh
        onClicked: root.arcade.startGame(root.arcade.mode)
      }
      ArcadeButton {
        id: hub
        objectName: "arcadeResultsHubButton"
        Layout.fillWidth: root.arcade.compactLayout
        arcade: root.arcade
        text: "Arcade hub"
        navigationSelected: root.arcade.selectedControl === hub
        onClicked: root.arcade.openHub()
      }
    }
  }
}
