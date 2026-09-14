pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

ColumnLayout {
  id: root
  required property var arcade
  property string detailView: ""
  component GameCard: Rectangle {
    property var playButton
  }
  readonly property var controls: {
    var items = []
    for (var i = 0; i < modes.count; i++) {
      var card = modes.itemAt(i) as GameCard
      if (card) {
        items.push(card.playButton)
      }
    }
    items.push(optionsToggle, progressToggle)
    if (detailView === "options") items.push(topicButton, paceButton)
    if (recommendation.visible) items.push(recommendation)
    return items
  }
  function toggleDetails(view) {
    detailView = detailView === view ? "" : view
    var toggle = view === "options" ? optionsToggle : progressToggle
    root.arcade.focusNavigationControl(toggle)
    Qt.callLater(function() { root.arcade.ensureControlVisible(toggle) })
  }
  spacing: root.arcade.compactLayout ? 16 : 24

  ArcadePixelText {
    Layout.fillWidth: true
    text: "Select your game"
    color: root.arcade.foregroundColor
    font.pixelSize: 16 * root.arcade.fontScale
  }
  Text {
    Layout.fillWidth: true
    text: "New here? Start with Window Rescue. No timer, and hints whenever you need them."
    color: root.arcade.mutedColor
    font.pixelSize: 13 * root.arcade.fontScale
    wrapMode: Text.WordWrap
  }
  GridLayout {
    id: modeGrid
    objectName: "arcadeModeGrid"
    Layout.fillWidth: true
    columns: root.width >= 960 * root.arcade.textScale ? 3 : 1
    uniformCellWidths: true
    uniformCellHeights: columns === 3
    columnSpacing: 32 * root.arcade.textScale
    rowSpacing: 24 * root.arcade.textScale
    Repeater {
      id: modes
      model: [
        { id: "rescue", title: "Window Rescue", tag: "START HERE · NO TIMER", detail: "Fly a rescue route by completing a different desktop mission each run." },
        { id: "sprint", title: "Shortcut Sprint", tag: "60 SECONDS", detail: "How many shortcuts can you remember in a minute?" },
        { id: "keyfall", title: "Keyfall", tag: "FALLING CARDS", detail: "Try the shortcut before its card reaches the bottom." }
      ]
      GameCard {
        id: card
        required property var modelData
        required property int index
        readonly property color cardAccent: root.arcade.colorForMode(modelData.id)
        readonly property color cardInk: root.arcade.inkForColor(cardAccent)
        readonly property real contentPadding: root.arcade.compactLayout ? 18 : 24
        readonly property bool selectionHighlighted: root.arcade.selectedControl === play || cardHover.hovered
        objectName: "arcadeModeCard-" + modelData.id
        playButton: play
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.alignment: Qt.AlignTop
        Layout.minimumWidth: 0
        implicitHeight: Math.max(cardContent.implicitHeight + contentPadding * 2,
          root.arcade.compactLayout ? 0 : 350 * root.arcade.textScale)
        radius: 2
        color: Qt.tint(root.arcade.surfaceColor, Qt.rgba(cardAccent.r, cardAccent.g, cardAccent.b,
          selectionHighlighted ? 0.14 : 0.025))
        border.color: selectionHighlighted ? cardInk
          : Qt.tint(root.arcade.surfaceColor, Qt.rgba(cardAccent.r, cardAccent.g, cardAccent.b, 0.4))
        border.width: selectionHighlighted ? 3 : 1
        ArcadeBezel {
          anchors.fill: parent
          anchors.margins: -5
          accent: card.cardAccent
          opacity: card.selectionHighlighted ? 1 : 0.4
          marquee: true
        }
        HoverHandler {
          id: cardHover
          onHoveredChanged: {
            if (hovered) root.arcade.focusNavigationControl(play)
          }
        }
        ColumnLayout {
          id: cardContent
          anchors.fill: parent
          anchors.margins: card.contentPadding
          spacing: root.arcade.compactLayout ? 12 : 16
          Text {
            text: card.modelData.tag
            color: card.cardInk
            font.pixelSize: 10 * root.arcade.fontScale
            font.weight: Font.Bold
            font.letterSpacing: 0.8
          }
          ArcadeModePreview {
            Layout.fillWidth: true
            Layout.preferredHeight: root.arcade.compactLayout ? 112 : 152
            arcade: root.arcade
            mode: card.modelData.id
          }
          ArcadePixelText {
            Layout.fillWidth: true
            text: card.modelData.title
            color: root.arcade.foregroundColor
            font.pixelSize: 15 * root.arcade.fontScale
          }
          Text {
            objectName: "arcadeGameDescription-" + card.modelData.id
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: implicitHeight
            text: card.modelData.detail
            color: root.arcade.mutedColor
            font.pixelSize: 13 * root.arcade.fontScale
            wrapMode: Text.WordWrap
          }
          ArcadeButton {
            id: play
            objectName: "arcadePlay-" + card.modelData.id
            Layout.fillWidth: true
            arcade: root.arcade
            highlightColor: card.cardAccent
            text: "Play"
            primary: card.modelData.id === "rescue"
            navigationSelected: root.arcade.selectedControl === play
            onClicked: root.arcade.startGame(card.modelData.id)
          }
        }
      }
    }
  }
  RowLayout {
    Layout.fillWidth: true
    spacing: 10
    ArcadeButton {
      id: optionsToggle
      objectName: "arcadeOptionsToggle"
      arcade: root.arcade
      text: root.detailView === "options" ? "Hide options" : "Options"
      Accessible.description: "Optional topic and speed settings"
      navigationSelected: root.arcade.selectedControl === optionsToggle
      onClicked: root.toggleDetails("options")
    }
    ArcadeButton {
      id: progressToggle
      objectName: "arcadeProgressToggle"
      arcade: root.arcade
      text: root.detailView === "progress" ? "Hide progress" : "Your progress"
      navigationSelected: root.arcade.selectedControl === progressToggle
      onClicked: root.toggleDetails("progress")
    }
    Item { Layout.fillWidth: true }
  }
  GridLayout {
    objectName: "arcadeOptions"
    Layout.fillWidth: true
    visible: root.detailView === "options"
    columns: root.arcade.compactLayout ? 1 : 2
    columnSpacing: 10
    rowSpacing: 8
    ArcadeButton {
      id: topicButton
      objectName: "arcadeTopicOption"
      Layout.fillWidth: true
      arcade: root.arcade
      text: "Topic: " + root.arcade.categoryLabel(root.arcade.selectedCategory)
      navigationSelected: root.arcade.selectedControl === topicButton
      Accessible.description: "Cycle the topic for Sprint and Keyfall. Rescue always follows its six-action mission."
      onClicked: root.arcade.cycleCategory()
    }
    ArcadeButton {
      id: paceButton
      objectName: "arcadePaceOption"
      Layout.fillWidth: true
      arcade: root.arcade
      text: "Keyfall speed: " + root.arcade.selectedPace
      navigationSelected: root.arcade.selectedControl === paceButton
      onClicked: root.arcade.cyclePace()
    }
  }
  Rectangle {
    objectName: "arcadeProgress"
    visible: root.detailView === "progress"
    Layout.fillWidth: true
    implicitHeight: mastery.implicitHeight + 30
    color: root.arcade.surfaceColor
    radius: 12
    border.color: root.arcade.lineColor
    ColumnLayout {
      id: mastery
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: 15
      spacing: 10
      Text {
        text: "Your progress"
        color: root.arcade.foregroundColor
        font.pixelSize: 16 * root.arcade.fontScale
        font.weight: Font.DemiBold
      }
      Text {
        Layout.fillWidth: true
        visible: root.arcade.mastery.practiced === 0
        text: "Play a round and your progress will appear here. Hints count as practice, too."
        color: root.arcade.mutedColor
        font.pixelSize: 13 * root.arcade.fontScale
        wrapMode: Text.WordWrap
      }
      ArcadeButton {
        id: recommendation
        Layout.fillWidth: true
        arcade: root.arcade
        visible: root.detailView === "progress" && root.arcade.mastery.practiced > 0 && root.arcade.recommendation.ids.length > 0
        text: "Practice a few shortcuts again"
        navigationSelected: root.arcade.selectedControl === recommendation
        onClicked: root.arcade.practiceThose(root.arcade.recommendation.ids, "keyfall")
      }
      Text {
        Layout.fillWidth: true
        visible: root.arcade.mastery.practiced > 0
        text: root.arcade.mastery.practiced + " / " + root.arcade.mastery.total + " practiced  ·  "
          + root.arcade.mastery.learning + " learning  ·  " + root.arcade.mastery.independent
          + " independent  ·  " + root.arcade.mastery.mastered + " retained"
        color: root.arcade.foregroundColor
        font.pixelSize: 13 * root.arcade.fontScale
        wrapMode: Text.WordWrap
      }
      Flow {
        Layout.fillWidth: true
        visible: root.arcade.mastery.practiced > 0
        spacing: 8
        Repeater {
          model: root.arcade.mastery.byCategory
          Rectangle {
            id: cell
            required property var modelData
            width: Math.min(mastery.width, categoryText.implicitWidth + 24)
            height: categoryText.implicitHeight + 18
            radius: 7
            color: root.arcade.raisedColor
            border.color: modelData.mastered > 0 ? root.arcade.inkAccent : root.arcade.lineColor
            Text {
              id: categoryText
              anchors.centerIn: parent
              text: root.arcade.categoryLabel(cell.modelData.category) + "  "
                + cell.modelData.practiced + "/" + cell.modelData.total + " practiced · " + cell.modelData.mastered + " retained"
              color: root.arcade.foregroundColor
              font.pixelSize: 11 * root.arcade.fontScale
            }
          }
        }
      }
      Text {
        Layout.fillWidth: true
        visible: root.arcade.mastery.practiced > 0
        text: "Remembering a shortcut on different days builds lasting recall. Earned milestones stay yours."
        color: root.arcade.mutedColor
        font.pixelSize: 12 * root.arcade.fontScale
        wrapMode: Text.WordWrap
      }
      Flow {
        Layout.fillWidth: true
        visible: root.arcade.mastery.practiced > 0
        spacing: 8
        Repeater {
          model: root.arcade.learningMilestones
          Rectangle {
            id: milestone
            required property var modelData
            readonly property bool earned: modelData.earned
            objectName: "arcadeMilestone-" + modelData.id
            width: Math.min(mastery.width, milestoneLabel.implicitWidth + 24)
            height: milestoneLabel.implicitHeight + 18
            radius: 7
            color: earned ? root.arcade.raisedColor : root.arcade.surfaceColor
            border.color: earned ? root.arcade.inkAccent : root.arcade.lineColor
            Accessible.role: Accessible.StaticText
            Accessible.name: modelData.label + (earned ? ", earned" : ", not yet earned")
            Text {
              id: milestoneLabel
              anchors.centerIn: parent
              text: (milestone.earned ? "✓  " : "○  ") + milestone.modelData.label + (milestone.earned ? "" : " · not yet")
              color: milestone.earned ? root.arcade.inkAccent : root.arcade.mutedColor
              font.pixelSize: 11 * root.arcade.fontScale
              Accessible.ignored: true
            }
          }
        }
      }
    }
  }
  Text {
    Layout.fillWidth: true
    visible: root.arcade.feedback.length > 0
    text: root.arcade.feedback
    color: root.arcade.mutedColor
    font.pixelSize: 13 * root.arcade.fontScale
    wrapMode: Text.WordWrap
  }
}
