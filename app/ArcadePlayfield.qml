pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
  id: root
  required property var arcade
  readonly property var controls: []
  readonly property real desktopHeight: Math.max(164, Math.min(620,
    arcade.playViewportHeight - hud.implicitHeight - prompt.implicitHeight
      - 20 - 2 * spacing - 48 * arcade.textScale))
  spacing: arcade.compactLayout ? 12 : 18

  RowLayout {
    id: hud
    objectName: "arcadeHud"
    Layout.fillWidth: true
    spacing: root.arcade.compactLayout ? 12 : 24
    ColumnLayout {
      objectName: "arcadeSupportPanel"
      Layout.fillWidth: true
      spacing: 2
      ArcadePixelText {
        objectName: "arcadeHudScore"
        text: "SCORE"
        color: root.arcade.mutedColor
        font.pixelSize: 10 * root.arcade.fontScale
      }
      ArcadePixelText {
        text: String(root.arcade.score)
        color: root.arcade.modeInk
        font.pixelSize: 30 * root.arcade.fontScale
      }
    }
    ColumnLayout {
      Layout.fillWidth: true
      spacing: 2
      Text {
        Layout.fillWidth: true
        text: "FIRST-TRY STREAK"
        color: root.arcade.mutedColor
        font.pixelSize: 10 * root.arcade.fontScale
        font.letterSpacing: 0.6
        wrapMode: Text.WordWrap
        horizontalAlignment: root.arcade.mode === "rescue" ? Text.AlignRight : Text.AlignHCenter
      }
      ArcadePixelText {
        Layout.fillWidth: true
        text: String(root.arcade.streak)
        color: root.arcade.foregroundColor
        font.pixelSize: 25 * root.arcade.fontScale
        horizontalAlignment: root.arcade.mode === "rescue" ? Text.AlignRight : Text.AlignHCenter
      }
    }
    ColumnLayout {
      visible: root.arcade.mode !== "rescue"
      Layout.fillWidth: true
      spacing: 2
      Text {
        Layout.fillWidth: true
        text: root.arcade.mode === "sprint" ? "60-SECOND CHALLENGE"
          : root.arcade.mode === "rescue" ? "MISSION PROGRESS"
          : root.arcade.queue.length > root.arcade.deck.length ? "INCLUDING PRACTICE RETRIES" : "PROMPTS COMPLETED"
        color: root.arcade.mutedColor
        font.pixelSize: 10 * root.arcade.fontScale
        horizontalAlignment: Text.AlignRight
        wrapMode: Text.WordWrap
      }
      ArcadePixelText {
        Layout.fillWidth: true
        text: root.arcade.mode === "sprint" ? root.arcade.formatTime(root.arcade.remainingMs)
          : root.arcade.answeredCount + " / " + root.arcade.runTarget
        color: root.arcade.foregroundColor
        font.pixelSize: 30 * root.arcade.fontScale
        horizontalAlignment: Text.AlignRight
      }
    }
  }
  ProgressBar {
    id: roundProgress
    visible: root.arcade.mode !== "rescue"
    Layout.fillWidth: true
    implicitHeight: 8
    from: 0
    to: 1
    value: root.arcade.mode === "sprint" ? root.arcade.remainingMs / 60000
      : root.arcade.keyfallProgress
    Accessible.name: root.arcade.mode === "keyfall" ? "Recall time used" : "Time remaining"
    Accessible.description: root.arcade.mode === "sprint"
      ? root.arcade.formatTime(root.arcade.remainingMs) + " remaining" : ""
    background: Rectangle { radius: 4; color: root.arcade.lineColor }
    contentItem: Item {
      Rectangle {
        width: roundProgress.visualPosition * parent.width
        height: parent.height + 8
        anchors.verticalCenter: parent.verticalCenter
        radius: height / 2
        color: root.arcade.modeAccent
        opacity: 0.18
      }
      Rectangle {
        width: roundProgress.visualPosition * parent.width
        height: parent.height
        radius: 4
        color: root.arcade.modeInk
      }
    }
  }
  Rectangle {
    id: arena
    objectName: "arcadeArena"
    Layout.fillWidth: true
    implicitHeight: root.arcade.mode === "rescue" ? prompt.implicitHeight + root.desktopHeight + 20
      : Math.max(prompt.implicitHeight + (root.arcade.mode === "sprint" ? 280 : 190),
        root.arcade.playViewportHeight - 160 * root.arcade.textScale)
    radius: 2
    color: root.arcade.mode === "rescue" ? "transparent"
      : Qt.tint(root.arcade.surfaceColor, Qt.rgba(root.arcade.modeAccent.r, root.arcade.modeAccent.g, root.arcade.modeAccent.b, 0.035))
    border.color: root.arcade.mode === "rescue" ? "transparent"
      : Qt.tint(root.arcade.surfaceColor, Qt.rgba(root.arcade.modeAccent.r, root.arcade.modeAccent.g, root.arcade.modeAccent.b, 0.28))
    border.width: root.arcade.mode === "rescue" ? 0 : 2

    Rectangle {
      objectName: "arcadeNeonScreenFrame"
      anchors.fill: parent
      anchors.margins: 7
      visible: root.arcade.mode !== "rescue"
      radius: 2
      color: "transparent"
      border.color: root.arcade.modeAccent
      border.width: 1
      opacity: 0.18
      z: 2
    }

    ArcadeSprintTrack {
      anchors.fill: parent
      visible: root.arcade.mode === "sprint"
      arcade: root.arcade
    }
    ArcadeKeyfallField {
      anchors.fill: parent
      visible: root.arcade.mode === "keyfall"
      arcade: root.arcade
    }
    ArcadePromptCard {
      id: prompt
      objectName: "arcadePromptCard"
      readonly property real arrivalY: 52
      readonly property real dockY: Math.max(arrivalY, arena.height - height - 92)
      property bool keyfallMissAnimating: false
      property real keyfallMissY: arrivalY
      property real keyfallMissOpacity: 1
      property real keyfallMissScale: 1
      property real keyfallMissOffset: 0
      readonly property bool landing: root.arcade.mode === "keyfall"
        && (root.arcade.hinted || root.arcade.responsePending)
      readonly property bool splitLanding: landing && arena.width >= 1100
        && !root.arcade.reducedMotion
      readonly property real laneX: root.arcade.hinted ? arena.width * 0.75 : arena.width * 0.25
      arcade: root.arcade
      centered: true
      neon: root.arcade.mode !== "rescue"
      emphasizeChanges: root.arcade.mode !== "keyfall"
      attentionActive: root.arcade.mode === "rescue" && !root.arcade.challengeEngaged
        && !root.arcade.responsePending
      cardPadding: root.arcade.mode === "sprint"
        ? root.arcade.compactLayout ? 22 : 30
        : root.arcade.compactLayout ? 18 : 24
      promptPixelSize: root.arcade.mode === "sprint"
        ? (root.arcade.compactLayout ? 29 : 34) * root.arcade.fontScale
        : (root.arcade.compactLayout ? 23 : 28) * root.arcade.fontScale
      width: Math.min(splitLanding ? parent.width * 0.46
        : parent.width - (root.arcade.mode === "rescue" ? 0 : 40),
        root.arcade.mode === "rescue" ? 940
        : root.arcade.mode === "sprint" ? 980 * root.arcade.textScale : 800)
      height: implicitHeight
      x: (splitLanding && !keyfallMissAnimating ? laneX - width / 2
        : (parent.width - width) / 2) + keyfallMissOffset
      y: keyfallMissAnimating ? keyfallMissY
        : root.arcade.mode === "rescue" ? 0
        : root.arcade.mode === "sprint" ? Math.max(62, (arena.height - height - 146) / 2)
        : root.arcade.reducedMotion ? arrivalY
        : landing ? dockY : arrivalY + root.arcade.keyfallProgress * (dockY - arrivalY)
      opacity: keyfallMissOpacity
      scale: keyfallMissScale
      eyebrow: root.arcade.hinted
        ? root.arcade.mode === "sprint" ? "LEARN ZONE · TIMER RUNNING"
          : root.arcade.mode === "keyfall" ? "PRACTICE · TRY THE REVEALED KEYS" : "LEARN ZONE · NO DEADLINE"
        : root.arcade.mode === "rescue" ? "NEXT ACTION · MISSION "
          + Math.min(root.arcade.challengeIndex + 1, root.arcade.runTarget)
          + " / " + root.arcade.runTarget + " · "
          + (root.arcade.rescueMission ? root.arcade.rescueMission.title.toUpperCase() : "WINDOW RESCUE")
        : root.arcade.isRetry ? "RECALL RETRY · WITHOUT THE HINT"
        : root.arcade.mode === "keyfall" ? (root.arcade.challengeElapsedMs < root.arcade.arrivalDwellMs ? "READ FIRST · " : "RECALL · ")
          + (root.arcade.currentChallenge ? root.arcade.categoryLabel(root.arcade.currentChallenge.category).toUpperCase() : "")
        : "RECALL · " + (root.arcade.currentChallenge ? root.arcade.categoryLabel(root.arcade.currentChallenge.category).toUpperCase() : "")
      Behavior on y {
        enabled: root.arcade.mode === "keyfall" && !root.arcade.reducedMotion
          && !prompt.keyfallMissAnimating
        NumberAnimation { duration: 100 }
      }
      Behavior on x {
        enabled: root.arcade.mode === "keyfall" && !root.arcade.reducedMotion
          && !prompt.keyfallMissAnimating
        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
      }
      z: 3

      function resetKeyfallMiss() {
        keyfallMissAnimation.stop()
        keyfallMissAnimating = false
        keyfallMissOpacity = 1
        keyfallMissScale = 1
        keyfallMissOffset = 0
      }

      function playKeyfallMiss() {
        if (root.arcade.mode !== "keyfall") return
        resetKeyfallMiss()
        if (root.arcade.reducedMotion) return
        keyfallMissY = y
        keyfallMissAnimating = true
        keyfallMissAnimation.start()
      }

      Connections {
        target: root.arcade
        function onKeyfallMissed() { prompt.playKeyfallMiss() }
        function onChallengeIndexChanged() { prompt.resetKeyfallMiss() }
        function onSessionIdChanged() { prompt.resetKeyfallMiss() }
        function onScreenChanged() { if (!root.arcade.running) prompt.resetKeyfallMiss() }
        function onReducedMotionChanged() { prompt.resetKeyfallMiss() }
        function onResponsePendingChanged() { if (root.arcade.responsePending) prompt.resetKeyfallMiss() }
      }

      SequentialAnimation {
        id: keyfallMissAnimation
        ParallelAnimation {
          NumberAnimation {
            target: prompt
            property: "keyfallMissOpacity"
            to: 0
            duration: 150
            easing.type: Easing.InCubic
          }
          SequentialAnimation {
            NumberAnimation { target: prompt; property: "keyfallMissOffset"; to: -10; duration: 45 }
            NumberAnimation { target: prompt; property: "keyfallMissOffset"; to: 10; duration: 55 }
            NumberAnimation { target: prompt; property: "keyfallMissOffset"; to: -6; duration: 45 }
            NumberAnimation { target: prompt; property: "keyfallMissOffset"; to: 0; duration: 35 }
          }
          NumberAnimation {
            target: prompt
            property: "keyfallMissScale"
            to: 0.9
            duration: 150
            easing.type: Easing.InCubic
          }
        }
        PropertyAction { target: prompt; property: "keyfallMissY"; value: prompt.dockY }
        ParallelAnimation {
          NumberAnimation {
            target: prompt
            property: "keyfallMissOpacity"
            to: 1
            duration: 210
            easing.type: Easing.OutCubic
          }
          NumberAnimation {
            target: prompt
            property: "keyfallMissScale"
            to: 1
            duration: 210
            easing.type: Easing.OutBack
          }
        }
        ScriptAction { script: prompt.keyfallMissAnimating = false }
      }
    }
    ArcadeScoreBurst {
      id: scoreBurst
      x: Math.max(12, Math.min(arena.width - width - 12, prompt.x + prompt.width / 2 - width / 2))
      y: root.arcade.mode === "rescue"
        ? Math.min(arena.height - height, prompt.y + prompt.height + 32)
        : root.arcade.mode === "keyfall" ? Math.max(48, prompt.y - height - 22)
        : prompt.y + prompt.height + 28
      arcade: root.arcade
    }
    ArcadeRescueScene {
      objectName: "arcadeRescueScene"
      visible: root.arcade.mode === "rescue"
      arcade: root.arcade
      completedActions: root.arcade.rescueCompleted
      y: prompt.height + 20
      width: parent.width
      height: root.desktopHeight
    }
  }
  Text {
    id: feedbackText
    objectName: "arcadeRunFeedback"
    Layout.fillWidth: true
    Layout.maximumWidth: (root.arcade.mode === "rescue" ? 940 : 800) * root.arcade.textScale
    Layout.alignment: Qt.AlignHCenter
    visible: text.length > 0
    text: root.arcade.feedback
    color: root.arcade.responsePending ? root.arcade.foregroundColor : root.arcade.mutedColor
    font.pixelSize: 13 * root.arcade.fontScale
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.WordWrap
    Accessible.role: Accessible.StaticText
    Accessible.name: text
  }
}
