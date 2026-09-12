pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "ArcadeLogic.js" as ArcadeLogic

Item {
  id: root

  required property var course
  required property var stats
  required property color backgroundColor
  required property color foregroundColor
  required property color accentColor
  required property color mutedColor
  required property color urgentColor
  required property real textScale
  required property bool reducedMotion
  property bool active: false

  signal closeRequested()
  signal statsCommitted(var value)
  signal effectRequested(string name)
  signal activeHostChanged(bool isActive)

  property string screen: "hub"
  property string mode: ""
  property var challenges: []
  property var deck: []
  property int challengeIndex: 0
  property int score: 0
  property int streak: 0
  property int bestRunStreak: 0
  property int cleanAnswers: 0
  property bool hinted: false
  property string feedback: ""
  property real gameStartedAt: 0
  property real challengeStartedAt: 0
  property int remainingMs: 0
  property int keyfallRetries: 0
  property real keyfallProgress: 0
  property int finalScore: 0
  property int finalStreak: 0
  property int finalClean: 0
  property int finalElapsedMs: 0
  property bool newBest: false
  property int feedbackPulse: 0
  property int celebrationPulse: 0
  property int wrongPulse: 0
  property int lastPoints: 0
  property string celebrationMessage: ""
  property int entrancePulse: 0
  readonly property var currentChallenge: deck.length > 0
    ? deck[challengeIndex % deck.length] : null
  readonly property var expectedKeys: currentChallenge ? currentChallenge.keys : []
  readonly property bool running: screen === "sprint" || screen === "rescue" || screen === "keyfall"
  readonly property int runTarget: mode === "rescue" ? 6 : mode === "keyfall" ? 12 : 0
  readonly property int elapsedMs: gameStartedAt > 0 ? Math.max(0, Date.now() - gameStartedAt) : 0
  readonly property color modeAccent: mode === "keyfall" ? urgentColor
    : mode === "rescue" ? Qt.lighter(accentColor, 1.35) : accentColor
  readonly property bool frenzy: mode === "sprint" && streak >= 5
  readonly property string resultRank: finalScore >= 4000 ? "S"
    : finalScore >= 2500 ? "A" : finalScore >= 1400 ? "B"
    : finalScore >= 600 ? "C" : "D"

  function modeStats(id) {
    var safe = ArcadeLogic.mergeStats(stats)
    return safe.modes ? safe.modes[id] : safe[id]
  }

  function modeName(id) {
    if (id === "sprint") return "SHORTCUT SPRINT"
    if (id === "rescue") return "WINDOW RESCUE"
    return "KEYFALL"
  }

  function formatTime(ms) {
    var seconds = Math.max(0, Math.ceil(Number(ms) / 1000))
    var minutes = Math.floor(seconds / 60)
    var remainder = seconds % 60
    return minutes > 0 ? minutes + ":" + (remainder < 10 ? "0" : "") + remainder : seconds + "s"
  }

  function openHub() {
    ticker.stop()
    challenges = ArcadeLogic.buildChallenges(course)
    screen = "hub"
    mode = ""
    feedback = ""
    hinted = false
    keyfallProgress = 0
    entrancePulse++
  }

  function startGame(id) {
    if (challenges.length === 0) challenges = ArcadeLogic.buildChallenges(course)
    if (challenges.length === 0) {
      feedback = "No keyboard challenges are available in this course yet."
      return
    }
    mode = id
    deck = ArcadeLogic.shuffled(challenges, Math.random)
    challengeIndex = 0
    score = 0
    streak = 0
    bestRunStreak = 0
    cleanAnswers = 0
    hinted = false
    feedback = "Press H whenever you want a hint."
    gameStartedAt = Date.now()
    challengeStartedAt = gameStartedAt
    remainingMs = id === "sprint" ? 60000 : 0
    keyfallRetries = 0
    keyfallProgress = 0
    screen = id
    entrancePulse++
    ticker.restart()
  }

  function handleControlKey(key) {
    if (screen === "hub") {
      if (key === "1") startGame("sprint")
      else if (key === "2") startGame("rescue")
      else if (key === "3") startGame("keyfall")
      return
    }
    if (screen === "results" && (key === "RETURN" || key === "SPACE" || key === "R")) {
      startGame(mode)
    }
  }

  function showHint() {
    if (!running || !currentChallenge || hinted) return
    hinted = true
    feedback = mode === "keyfall"
      ? "Card frozen. Match the revealed keys to keep moving."
      : "Hint revealed. Finish this one for practice, not points."
    feedbackPulse++
  }

  function handleKeyPress(direct, keys) {
    if (!running || !currentChallenge || !direct) return
    if (["SUPER", "CTRL", "ALT", "SHIFT"].indexOf(direct) !== -1) return
    var actual = ArcadeLogic.keySignature(keys)
    if (actual === currentChallenge.signature) {
      completeChallenge()
      return
    }
    feedback = "Close. Nothing lost; try again or press H for the answer."
    feedbackPulse++
    wrongPulse++
  }

  function completeChallenge() {
    var wasHinted = hinted
    var answerTime = Math.max(0, Date.now() - challengeStartedAt)
    var points = ArcadeLogic.scoreAnswer(mode, answerTime, streak, wasHinted)
    lastPoints = points
    score += points
    if (!wasHinted) {
      streak++
      cleanAnswers++
      bestRunStreak = Math.max(bestRunStreak, streak)
    }
    feedback = wasHinted ? "Locked in. That shortcut will come faster next time."
      : points + " points · clean shortcut!"
    celebrationMessage = wasHinted ? "MEMORY LOCKED"
      : streak >= 7 ? "UNSTOPPABLE!" : streak >= 4 ? "ON FIRE!" : "NICE!"
    celebrationPulse++
    effectRequested(wasHinted ? "hint" : "success")
    feedbackPulse++
    challengeIndex++
    hinted = false
    challengeStartedAt = Date.now()
    keyfallRetries = 0
    keyfallProgress = 0

    if (mode === "rescue" && challengeIndex >= runTarget) finishGame(true)
    else if (mode === "keyfall" && challengeIndex >= runTarget) finishGame(true)
  }

  function finishGame(cleared) {
    if (!running) return
    ticker.stop()
    finalScore = score
    finalStreak = bestRunStreak
    finalClean = cleanAnswers
    finalElapsedMs = Math.max(0, Date.now() - gameStartedAt)
    var before = modeStats(mode)
    newBest = score > before.bestScore
    var nextStats = ArcadeLogic.recordResult(stats, mode, score, bestRunStreak, cleared)
    statsCommitted(nextStats)
    screen = "results"
    effectRequested("finish")
  }

  onActiveChanged: {
    activeHostChanged(active)
    if (active) openHub()
    else ticker.stop()
  }
  onCelebrationPulseChanged: if (celebrationPulse > 0) celebrationAnimation.restart()
  onWrongPulseChanged: if (wrongPulse > 0) wrongFlashAnimation.restart()

  Timer {
    id: ticker
    interval: 50
    repeat: true
    onTriggered: {
      if (root.screen === "sprint") {
        root.remainingMs = Math.max(0, 60000 - (Date.now() - root.gameStartedAt))
        if (root.remainingMs <= 0) root.finishGame(true)
      } else if (root.screen === "keyfall" && !root.hinted) {
        var fallDuration = 7000 + (root.keyfallRetries * 2500)
        root.keyfallProgress = Math.min(1, (Date.now() - root.challengeStartedAt) / fallDuration)
        if (root.keyfallProgress >= 1) {
          root.keyfallRetries++
          root.hinted = true
          root.feedback = "Caught at the line. The answer is revealed; no life or points lost."
          root.feedbackPulse++
        }
      }
    }
  }

  component ArcadeButton: Rectangle {
    id: button
    property string label: ""
    property bool primary: false
    signal clicked()
    implicitWidth: Math.max(150, buttonText.implicitWidth + 34)
    implicitHeight: 46 * root.textScale
    radius: 8
    color: mouse.pressed ? root.foregroundColor
      : mouse.containsMouse ? root.accentColor
      : primary ? root.accentColor : root.backgroundColor
    border.width: 1
    border.color: primary ? root.accentColor : root.mutedColor
    scale: mouse.pressed ? 0.97 : mouse.containsMouse ? 1.04 : 1
    Behavior on scale {
      enabled: !root.reducedMotion
      NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
    }
    Text {
      id: buttonText
      anchors.centerIn: parent
      text: button.label
      color: (mouse.containsMouse || mouse.pressed || button.primary)
        ? root.backgroundColor : root.foregroundColor
      font.family: "monospace"
      font.pixelSize: 12 * root.textScale
      font.weight: Font.Bold
      font.letterSpacing: 0.8
    }
    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: button.clicked()
    }
  }

  component KeyPill: Rectangle {
    required property string keyLabel
    implicitWidth: Math.max(42, keyText.implicitWidth + 22)
    implicitHeight: 38 * root.textScale
    radius: 7
    color: root.modeAccent
    border.width: 2
    border.color: Qt.lighter(root.modeAccent, 1.35)
    Text {
      id: keyText
      anchors.centerIn: parent
      text: parent.keyLabel
      color: root.backgroundColor
      font.family: "monospace"
      font.pixelSize: 13 * root.textScale
      font.weight: Font.Bold
    }
  }

  component StatChip: Rectangle {
    id: statChip
    property string label: ""
    property string value: ""
    property color chipColor: root.modeAccent
    implicitWidth: chipRow.implicitWidth + 26
    implicitHeight: 42 * root.textScale
    radius: height / 2
    color: Qt.rgba(chipColor.r, chipColor.g, chipColor.b, 0.13)
    border.width: 1
    border.color: Qt.rgba(chipColor.r, chipColor.g, chipColor.b, 0.55)
    RowLayout {
      id: chipRow
      anchors.centerIn: parent
      spacing: 8
      Text {
        text: statChip.label
        color: root.mutedColor
        font.family: "monospace"
        font.pixelSize: 9 * root.textScale
        font.weight: Font.Bold
        font.letterSpacing: 0.8
      }
      Text {
        text: statChip.value
        color: statChip.chipColor
        font.family: "monospace"
        font.pixelSize: 15 * root.textScale
        font.weight: Font.Black
      }
    }
  }

  Rectangle {
    anchors.fill: parent
    color: root.backgroundColor
    opacity: 0.96
  }

  Repeater {
    model: 28
    Rectangle {
      id: ambientDot
      required property int index
      readonly property real seedX: ((index * 47) % 101) / 100
      readonly property real seedY: ((index * 71) % 97) / 96
      x: seedX * root.width
      y: seedY * root.height
      width: index % 5 === 0 ? 4 : 2
      height: width
      radius: width / 2
      color: index % 4 === 0 ? root.modeAccent : root.foregroundColor
      opacity: 0.08 + (index % 5) * 0.035
      SequentialAnimation on opacity {
        running: root.active && !root.reducedMotion
        loops: Animation.Infinite
        NumberAnimation { to: 0.34; duration: 900 + ambientDot.index * 37 }
        NumberAnimation { to: 0.07; duration: 1100 + ambientDot.index * 29 }
      }
    }
  }

  Rectangle {
    id: frame
    anchors.centerIn: parent
    width: Math.min(parent.width - 64, 1120)
    height: Math.min(parent.height - 64, 760)
    radius: 18
    color: Qt.rgba(root.backgroundColor.r, root.backgroundColor.g, root.backgroundColor.b, 0.98)
    border.width: 2
    border.color: root.screen === "hub" ? root.accentColor : root.modeAccent
    scale: root.active ? 1 : 0.96
    Behavior on border.color { ColorAnimation { duration: 220 } }

    Rectangle {
      id: wrongFlash
      anchors.fill: parent
      radius: parent.radius
      color: "transparent"
      border.width: 5
      border.color: root.urgentColor
      opacity: 0
      z: 40
    }
    SequentialAnimation {
      id: wrongFlashAnimation
      NumberAnimation { target: wrongFlash; property: "opacity"; to: 0.75; duration: root.reducedMotion ? 0 : 70 }
      NumberAnimation { target: wrongFlash; property: "opacity"; to: 0; duration: root.reducedMotion ? 0 : 320 }
    }

    Rectangle {
      id: celebrationBanner
      anchors.horizontalCenter: parent.horizontalCenter
      y: 82
      z: 50
      width: Math.max(230, celebrationLabel.implicitWidth + 52)
      height: 66
      radius: 33
      color: Qt.rgba(root.modeAccent.r, root.modeAccent.g, root.modeAccent.b, 0.94)
      border.width: 3
      border.color: Qt.lighter(root.modeAccent, 1.4)
      opacity: 0
      scale: 0.7
      RowLayout {
        anchors.centerIn: parent
        spacing: 10
        Text {
          text: root.lastPoints > 0 ? "+" + root.lastPoints : "✓"
          color: root.backgroundColor
          font.family: "monospace"
          font.pixelSize: 22 * root.textScale
          font.weight: Font.Black
        }
        Text {
          id: celebrationLabel
          text: root.celebrationMessage
          color: root.backgroundColor
          font.family: "monospace"
          font.pixelSize: 15 * root.textScale
          font.weight: Font.Black
          font.letterSpacing: 0.8
        }
      }
    }
    SequentialAnimation {
      id: celebrationAnimation
      ParallelAnimation {
        NumberAnimation { target: celebrationBanner; property: "opacity"; to: 1; duration: root.reducedMotion ? 0 : 90 }
        NumberAnimation { target: celebrationBanner; property: "scale"; to: 1.08; duration: root.reducedMotion ? 0 : 180; easing.type: Easing.OutBack }
      }
      PauseAnimation { duration: root.reducedMotion ? 0 : 330 }
      ParallelAnimation {
        NumberAnimation { target: celebrationBanner; property: "opacity"; to: 0; duration: root.reducedMotion ? 0 : 260 }
        NumberAnimation { target: celebrationBanner; property: "scale"; to: 0.92; duration: root.reducedMotion ? 0 : 260 }
      }
    }

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: 28
      spacing: 18

      RowLayout {
        Layout.fillWidth: true
        spacing: 14
        Rectangle {
          Layout.preferredWidth: 48
          Layout.preferredHeight: 48
          radius: 13
          color: Qt.rgba(root.modeAccent.r, root.modeAccent.g, root.modeAccent.b, 0.16)
          border.width: 1
          border.color: root.modeAccent
          Text {
            anchors.centerIn: parent
            text: root.screen === "hub" ? "⌨" : root.mode === "sprint" ? "⚡"
              : root.mode === "rescue" ? "▦" : "▼"
            color: root.modeAccent
            font.pixelSize: 24 * root.textScale
            font.weight: Font.Black
          }
        }
        ColumnLayout {
          Layout.fillWidth: true
          spacing: 1
          Text {
            text: root.screen === "hub" ? "SHORTCUT ARCADE"
              : root.screen === "results" ? "RUN COMPLETE"
              : root.modeName(root.mode)
            color: root.foregroundColor
            font.family: "monospace"
            font.pixelSize: 25 * root.textScale
            font.weight: Font.Black
            font.letterSpacing: 1.2
          }
          Text {
            text: root.screen === "hub" ? "BUILD INSTINCT. CHASE YOUR BEST."
              : root.screen === "results" ? "YOUR MUSCLE MEMORY JUST LEVELED UP"
              : root.mode === "sprint" ? "SPEED + ACCURACY"
              : root.mode === "rescue" ? "RESTORE THE DESKTOP"
              : "BEAT THE RECALL LINE"
            color: root.modeAccent
            font.family: "monospace"
            font.pixelSize: 9 * root.textScale
            font.weight: Font.Bold
            font.letterSpacing: 1.4
          }
        }
        Rectangle {
          implicitWidth: headerKeys.implicitWidth + 22
          implicitHeight: 34
          radius: 17
          color: Qt.rgba(root.foregroundColor.r, root.foregroundColor.g, root.foregroundColor.b, 0.07)
          RowLayout {
            id: headerKeys
            anchors.centerIn: parent
            spacing: 12
            Text {
              text: root.running ? "H  HINT" : root.screen === "hub" ? "1  2  3  PLAY" : "R  REPLAY"
              color: root.foregroundColor
              font.family: "monospace"
              font.pixelSize: 10 * root.textScale
              font.weight: Font.Bold
            }
            Text {
              text: "ESC  BACK"
              color: root.mutedColor
              font.family: "monospace"
              font.pixelSize: 10 * root.textScale
              font.weight: Font.Bold
            }
          }
        }
      }

      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        ColumnLayout {
          anchors.fill: parent
          spacing: 20
          visible: root.screen === "hub"
          opacity: visible ? 1 : 0
          scale: visible ? 1 : 0.97
          Behavior on opacity { NumberAnimation { duration: root.reducedMotion ? 0 : 220 } }
          Behavior on scale { NumberAnimation { duration: root.reducedMotion ? 0 : 260; easing.type: Easing.OutCubic } }

          Text {
            Layout.fillWidth: true
            text: "Three ways to turn Omarchy shortcuts into muscle memory. Hints keep every run moving and never take away points."
            color: root.mutedColor
            wrapMode: Text.WordWrap
            font.pixelSize: 15 * root.textScale
          }

          RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 16

            Repeater {
              model: [
                { id: "sprint", number: "01", icon: "⚡", name: "SHORTCUT SPRINT", detail: "60 seconds of rapid recall. Speed and clean streaks build the score.", tag: "QUICK · 60 SEC" },
                { id: "rescue", number: "02", icon: "▦", name: "WINDOW RESCUE", detail: "Repair a simulated desktop one shortcut at a time. No countdown.", tag: "CALM · 6 TASKS" },
                { id: "keyfall", number: "03", icon: "▼", name: "KEYFALL", detail: "Clear falling prompts before the line. Misses turn into guided retries.", tag: "FLOW · 12 CARDS" }
              ]

              Rectangle {
                id: gameCard
                required property var modelData
                readonly property color cardAccent: modelData.id === "keyfall" ? root.urgentColor
                  : modelData.id === "rescue" ? Qt.lighter(root.accentColor, 1.35) : root.accentColor
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 0
                radius: 14
                color: cardMouse.containsMouse
                  ? Qt.rgba(cardAccent.r, cardAccent.g, cardAccent.b, 0.16)
                  : Qt.rgba(root.foregroundColor.r, root.foregroundColor.g, root.foregroundColor.b, 0.035)
                border.width: cardMouse.containsMouse ? 2 : 1
                border.color: cardMouse.containsMouse ? cardAccent
                  : Qt.rgba(cardAccent.r, cardAccent.g, cardAccent.b, 0.45)
                scale: cardMouse.containsMouse ? 1.025 : 1
                Behavior on scale {
                  enabled: !root.reducedMotion
                  NumberAnimation { duration: 160; easing.type: Easing.OutBack }
                }

                Rectangle {
                  width: 5
                  height: parent.height - 32
                  anchors.left: parent.left
                  anchors.leftMargin: 12
                  anchors.verticalCenter: parent.verticalCenter
                  radius: 3
                  color: gameCard.cardAccent
                  opacity: cardMouse.containsMouse ? 1 : 0.55
                }

                ColumnLayout {
                  anchors.fill: parent
                  anchors.leftMargin: 30
                  anchors.rightMargin: 20
                  anchors.topMargin: 18
                  anchors.bottomMargin: 18
                  spacing: 12

                  Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 112

                    Text {
                      anchors.left: parent.left
                      anchors.top: parent.top
                      text: gameCard.modelData.number
                      color: gameCard.cardAccent
                      opacity: 0.7
                      font.family: "monospace"
                      font.pixelSize: 11 * root.textScale
                      font.weight: Font.Black
                    }

                    Rectangle {
                      anchors.centerIn: parent
                      width: 92
                      height: 92
                      radius: 46
                      color: Qt.rgba(gameCard.cardAccent.r, gameCard.cardAccent.g, gameCard.cardAccent.b, 0.1)
                      border.width: 2
                      border.color: Qt.rgba(gameCard.cardAccent.r, gameCard.cardAccent.g, gameCard.cardAccent.b, 0.65)
                      visible: gameCard.modelData.id === "sprint"
                      Text {
                        anchors.centerIn: parent
                        text: "60"
                        color: gameCard.cardAccent
                        font.family: "monospace"
                        font.pixelSize: 30 * root.textScale
                        font.weight: Font.Black
                      }
                      Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: 5
                        width: 8
                        height: 8
                        radius: 4
                        color: gameCard.cardAccent
                      }
                    }

                    Item {
                      anchors.centerIn: parent
                      width: 150
                      height: 92
                      visible: gameCard.modelData.id === "rescue"
                      Repeater {
                        model: 3
                        Rectangle {
                          id: fallingPreview
                          required property int index
                          width: 82
                          height: 48
                          x: index * 28
                          y: index * 18
                          radius: 6
                          color: root.backgroundColor
                          border.width: 2
                          border.color: gameCard.cardAccent
                          Rectangle {
                            width: parent.width
                            height: 11
                            radius: 5
                            color: Qt.rgba(gameCard.cardAccent.r, gameCard.cardAccent.g, gameCard.cardAccent.b, 0.35)
                          }
                        }
                      }
                    }

                    Item {
                      anchors.centerIn: parent
                      width: 150
                      height: 100
                      visible: gameCard.modelData.id === "keyfall"
                      Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 3
                        color: gameCard.cardAccent
                      }
                      Repeater {
                        model: 3
                        Rectangle {
                          required property int index
                          width: 34
                          height: 22
                          radius: 5
                          x: 12 + index * 49
                          y: 8 + index * 22
                          color: Qt.rgba(gameCard.cardAccent.r, gameCard.cardAccent.g, gameCard.cardAccent.b, 0.24)
                          border.width: 1
                          border.color: gameCard.cardAccent
                          SequentialAnimation on y {
                            running: root.active && !root.reducedMotion
                            loops: Animation.Infinite
                            NumberAnimation { to: 72; duration: 1400 }
                            PropertyAction { value: 4 }
                          }
                        }
                      }
                    }
                  }
                  Text {
                    Layout.fillWidth: true
                    text: gameCard.modelData.name
                    color: root.foregroundColor
                    wrapMode: Text.WordWrap
                    font.family: "monospace"
                    font.pixelSize: 18 * root.textScale
                    font.weight: Font.Black
                  }
                  Text {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    text: gameCard.modelData.detail
                    color: root.mutedColor
                    wrapMode: Text.WordWrap
                    font.pixelSize: 14 * root.textScale
                  }
                  Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    radius: 8
                    color: cardMouse.containsMouse ? gameCard.cardAccent
                      : Qt.rgba(gameCard.cardAccent.r, gameCard.cardAccent.g, gameCard.cardAccent.b, 0.1)
                    border.width: 1
                    border.color: gameCard.cardAccent
                    Text {
                      anchors.centerIn: parent
                      text: cardMouse.containsMouse ? "PLAY NOW  →" : "ENTER GAME"
                      color: cardMouse.containsMouse ? root.backgroundColor : gameCard.cardAccent
                      font.family: "monospace"
                      font.pixelSize: 10 * root.textScale
                      font.weight: Font.Black
                      font.letterSpacing: 0.9
                    }
                  }
                  Text {
                    text: gameCard.modelData.tag
                    color: gameCard.cardAccent
                    font.family: "monospace"
                    font.pixelSize: 10 * root.textScale
                    font.weight: Font.Bold
                    font.letterSpacing: 0.7
                  }
                  Text {
                    text: "PERSONAL BEST  " + root.modeStats(gameCard.modelData.id).bestScore
                    color: root.foregroundColor
                    font.family: "monospace"
                    font.pixelSize: 13 * root.textScale
                    font.weight: Font.Bold
                  }
                }

                MouseArea {
                  id: cardMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.startGame(gameCard.modelData.id)
                }
              }
            }
          }

          Text {
            Layout.fillWidth: true
            text: root.feedback || root.challenges.length + " course shortcuts ready to practice."
            color: root.feedback ? root.urgentColor : root.mutedColor
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 12 * root.textScale
          }
          Text {
            Layout.fillWidth: true
            text: "PRESS 1, 2, OR 3 TO LAUNCH"
            color: root.accentColor
            horizontalAlignment: Text.AlignHCenter
            font.family: "monospace"
            font.pixelSize: 10 * root.textScale
            font.weight: Font.Bold
            font.letterSpacing: 1.3
          }
        }

        ColumnLayout {
          anchors.fill: parent
          spacing: 16
          visible: root.running
          opacity: visible ? 1 : 0
          scale: visible ? 1 : 0.97
          Behavior on opacity { NumberAnimation { duration: root.reducedMotion ? 0 : 220 } }
          Behavior on scale { NumberAnimation { duration: root.reducedMotion ? 0 : 260; easing.type: Easing.OutCubic } }

          RowLayout {
            Layout.fillWidth: true
            spacing: 10
            StatChip { label: "SCORE"; value: String(root.score) }
            StatChip {
              label: root.frenzy ? "FRENZY" : "STREAK"
              value: root.frenzy ? "×" + root.streak : String(root.streak)
              chipColor: root.frenzy ? root.urgentColor : root.modeAccent
            }
            StatChip {
              visible: root.mode !== "sprint"
              label: "CLEAN"
              value: String(root.cleanAnswers)
            }
            Item { Layout.fillWidth: true }
            Rectangle {
              implicitWidth: timerText.implicitWidth + 28
              implicitHeight: 46 * root.textScale
              radius: 12
              color: root.mode === "sprint" && root.remainingMs < 10000
                ? Qt.rgba(root.urgentColor.r, root.urgentColor.g, root.urgentColor.b, 0.18)
                : Qt.rgba(root.modeAccent.r, root.modeAccent.g, root.modeAccent.b, 0.1)
              border.width: 2
              border.color: root.mode === "sprint" && root.remainingMs < 10000
                ? root.urgentColor : root.modeAccent
              Text {
                id: timerText
                anchors.centerIn: parent
                text: root.mode === "sprint" ? root.formatTime(root.remainingMs)
                  : (Math.min(root.challengeIndex + 1, root.runTarget) + " / " + root.runTarget)
                color: root.mode === "sprint" && root.remainingMs < 10000
                  ? root.urgentColor : root.foregroundColor
                font.family: "monospace"
                font.pixelSize: 18 * root.textScale
                font.weight: Font.Black
              }
            }
          }

          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 8
            radius: 4
            color: Qt.rgba(root.foregroundColor.r, root.foregroundColor.g, root.foregroundColor.b, 0.12)
            Rectangle {
              height: parent.height
              radius: parent.radius
              color: root.modeAccent
              width: root.mode === "sprint"
                ? parent.width * (root.remainingMs / 60000)
                : parent.width * Math.min(1, root.challengeIndex / root.runTarget)
              Behavior on width {
                enabled: !root.reducedMotion
                NumberAnimation { duration: 160 }
              }
            }
          }

          Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Item {
              anchors.fill: parent
              visible: root.mode === "sprint"

              Rectangle {
                anchors.fill: parent
                radius: 16
                gradient: Gradient {
                  GradientStop { position: 0; color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16) }
                  GradientStop { position: 0.52; color: root.backgroundColor }
                  GradientStop { position: 1; color: Qt.rgba(root.urgentColor.r, root.urgentColor.g, root.urgentColor.b, root.frenzy ? 0.18 : 0.05) }
                }
                border.width: root.frenzy ? 2 : 1
                border.color: root.frenzy ? root.urgentColor : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45)
              }

              Repeater {
                model: 11
                Rectangle {
                  id: speedLine
                  required property int index
                  width: 44 + index * 11
                  height: 3
                  radius: 2
                  x: index % 2 === 0 ? 24 : parent.width - width - 24
                  y: 28 + index * (parent.height - 60) / 11
                  color: root.frenzy ? root.urgentColor : root.accentColor
                  opacity: 0.12 + index * 0.025
                  SequentialAnimation on x {
                    running: root.running && !root.reducedMotion
                    loops: Animation.Infinite
                    NumberAnimation {
                      to: speedLine.index % 2 === 0 ? 54 : speedLine.parent.width - speedLine.width - 54
                      duration: 700 + speedLine.index * 45
                    }
                    NumberAnimation {
                      to: speedLine.index % 2 === 0 ? 24 : speedLine.parent.width - speedLine.width - 24
                      duration: 700 + speedLine.index * 45
                    }
                  }
                }
              }

              Canvas {
                id: sprintDial
                anchors.centerIn: parent
                width: Math.min(parent.width * 0.58, parent.height * 0.9)
                height: width
                onPaint: {
                  var ctx = getContext("2d")
                  ctx.reset()
                  var cx = width / 2
                  var cy = height / 2
                  var radius = width / 2 - 18
                  ctx.lineWidth = 10
                  ctx.lineCap = "round"
                  ctx.strokeStyle = Qt.rgba(root.foregroundColor.r, root.foregroundColor.g, root.foregroundColor.b, 0.09)
                  ctx.beginPath()
                  ctx.arc(cx, cy, radius, 0, Math.PI * 2)
                  ctx.stroke()
                  ctx.strokeStyle = root.frenzy ? root.urgentColor : root.accentColor
                  ctx.beginPath()
                  ctx.arc(cx, cy, radius, -Math.PI / 2,
                    -Math.PI / 2 + Math.PI * 2 * Math.max(0, root.remainingMs / 60000))
                  ctx.stroke()
                }
                Connections {
                  target: root
                  function onRemainingMsChanged() { sprintDial.requestPaint() }
                  function onFrenzyChanged() { sprintDial.requestPaint() }
                }
              }

              Rectangle {
                anchors.centerIn: parent
                width: sprintDial.width - 58
                height: width
                radius: width / 2
                color: Qt.rgba(root.backgroundColor.r, root.backgroundColor.g, root.backgroundColor.b, 0.92)
                border.width: 1
                border.color: Qt.rgba(root.modeAccent.r, root.modeAccent.g, root.modeAccent.b, 0.4)

                ColumnLayout {
                  anchors.centerIn: parent
                  width: parent.width - 54
                  spacing: 10
                  Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.frenzy ? "FRENZY ×" + root.streak : "RECALL THIS"
                    color: root.frenzy ? root.urgentColor : root.accentColor
                    font.family: "monospace"
                    font.pixelSize: 10 * root.textScale
                    font.weight: Font.Black
                    font.letterSpacing: 1.4
                  }
                  Text {
                    Layout.fillWidth: true
                    text: root.currentChallenge ? root.currentChallenge.prompt : ""
                    color: root.foregroundColor
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: 20 * root.textScale
                    font.weight: Font.DemiBold
                  }
                  Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.currentChallenge ? root.currentChallenge.category.toUpperCase() : ""
                    color: root.mutedColor
                    font.family: "monospace"
                    font.pixelSize: 9 * root.textScale
                    font.weight: Font.Bold
                  }
                }
              }
            }

            Item {
              anchors.fill: parent
              visible: root.mode === "rescue"

              Rectangle {
                anchors.fill: parent
                radius: 16
                gradient: Gradient {
                  GradientStop { position: 0; color: Qt.rgba(root.modeAccent.r, root.modeAccent.g, root.modeAccent.b, 0.2) }
                  GradientStop { position: 0.45; color: root.backgroundColor }
                  GradientStop { position: 1; color: Qt.rgba(root.foregroundColor.r, root.foregroundColor.g, root.foregroundColor.b, 0.06) }
                }
                border.width: 1
                border.color: Qt.rgba(root.modeAccent.r, root.modeAccent.g, root.modeAccent.b, 0.55)
              }

              Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 38
                radius: 16
                color: Qt.rgba(root.backgroundColor.r, root.backgroundColor.g, root.backgroundColor.b, 0.88)
                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: 16
                  anchors.rightMargin: 16
                  Text {
                    text: "OMARCHY RESCUE DESKTOP"
                    color: root.modeAccent
                    font.family: "monospace"
                    font.pixelSize: 9 * root.textScale
                    font.weight: Font.Black
                    font.letterSpacing: 1.1
                  }
                  Item { Layout.fillWidth: true }
                  Repeater {
                    model: 6
                    Rectangle {
                      required property int index
                      width: 10
                      height: 10
                      radius: 5
                      color: index < root.challengeIndex ? root.modeAccent
                        : index === root.challengeIndex ? root.foregroundColor : root.mutedColor
                      opacity: index <= root.challengeIndex ? 1 : 0.28
                    }
                  }
                }
              }

              Rectangle {
                width: parent.width * 0.28
                height: width
                radius: width / 2
                x: parent.width * 0.08
                y: parent.height * 0.28
                color: Qt.rgba(root.modeAccent.r, root.modeAccent.g, root.modeAccent.b, 0.08)
              }
              Rectangle {
                width: parent.width * 0.2
                height: width
                radius: width / 2
                x: parent.width * 0.7
                y: parent.height * 0.5
                color: Qt.rgba(root.urgentColor.r, root.urgentColor.g, root.urgentColor.b, 0.06)
              }

              GridLayout {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 18
                width: Math.min(parent.width - 70, 780)
                columns: 3
                rowSpacing: 16
                columnSpacing: 16

                Repeater {
                  model: 6
                  Rectangle {
                    id: rescueTile
                    required property int index
                    readonly property bool rescued: index < root.challengeIndex
                    readonly property bool activeTile: index === root.challengeIndex
                    Layout.fillWidth: true
                    Layout.preferredHeight: 118
                    radius: 10
                    color: rescued
                      ? Qt.rgba(root.modeAccent.r, root.modeAccent.g, root.modeAccent.b, 0.19)
                      : Qt.rgba(root.backgroundColor.r, root.backgroundColor.g, root.backgroundColor.b, 0.92)
                    border.width: activeTile ? 3 : rescued ? 2 : 1
                    border.color: rescued || activeTile ? root.modeAccent
                      : Qt.rgba(root.foregroundColor.r, root.foregroundColor.g, root.foregroundColor.b, 0.18)
                    scale: activeTile && !root.reducedMotion ? 1.035 : 1
                    opacity: index > root.challengeIndex ? 0.64 : 1
                    Behavior on scale {
                      NumberAnimation { duration: 220; easing.type: Easing.OutBack }
                    }

                    SequentialAnimation on rotation {
                      running: rescueTile.activeTile && !root.reducedMotion
                      loops: Animation.Infinite
                      NumberAnimation { to: -0.7; duration: 420 }
                      NumberAnimation { to: 0.7; duration: 420 }
                      NumberAnimation { to: 0; duration: 420 }
                    }

                    Rectangle {
                      anchors.top: parent.top
                      anchors.left: parent.left
                      anchors.right: parent.right
                      height: 24
                      radius: 9
                      color: rescueTile.rescued || rescueTile.activeTile
                        ? Qt.rgba(root.modeAccent.r, root.modeAccent.g, root.modeAccent.b, 0.38)
                        : Qt.rgba(root.foregroundColor.r, root.foregroundColor.g, root.foregroundColor.b, 0.07)
                      Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 9
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        Repeater {
                          model: 3
                          Rectangle {
                            required property int index
                            width: 6
                            height: 6
                            radius: 3
                            color: index === 0 ? root.urgentColor : root.mutedColor
                            opacity: 0.75
                          }
                        }
                      }
                    }

                    Column {
                      anchors.centerIn: parent
                      anchors.verticalCenterOffset: 11
                      spacing: 7
                      Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: rescueTile.rescued ? "✓" : rescueTile.activeTile ? "!"
                          : String(rescueTile.index + 1)
                        color: rescueTile.rescued || rescueTile.activeTile ? root.modeAccent : root.mutedColor
                        font.pixelSize: 23 * root.textScale
                        font.weight: Font.Black
                      }
                      Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: rescueTile.rescued ? "RESTORED"
                          : rescueTile.activeTile ? "SIGNAL LOST" : "AWAITING SIGNAL"
                        color: rescueTile.rescued || rescueTile.activeTile
                          ? root.foregroundColor : root.mutedColor
                        font.family: "monospace"
                        font.pixelSize: 9 * root.textScale
                        font.weight: Font.Bold
                        font.letterSpacing: 0.7
                      }
                    }
                  }
                }
              }

              Text {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 12
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.challengeIndex === 0 ? "DESKTOP DISTRESS SIGNAL DETECTED"
                  : root.challengeIndex < 6 ? root.challengeIndex + " WINDOW" +
                    (root.challengeIndex === 1 ? "" : "S") + " BACK ONLINE"
                  : "DESKTOP STABLE"
                color: root.modeAccent
                font.family: "monospace"
                font.pixelSize: 9 * root.textScale
                font.weight: Font.Black
                font.letterSpacing: 1.2
              }
            }

            Rectangle {
              id: fallLane
              anchors.fill: parent
              visible: root.mode === "keyfall"
              radius: 14
              gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(root.urgentColor.r, root.urgentColor.g, root.urgentColor.b, 0.12) }
                GradientStop { position: 0.45; color: root.backgroundColor }
                GradientStop { position: 1; color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.13) }
              }
              border.width: 1
              border.color: Qt.rgba(root.urgentColor.r, root.urgentColor.g, root.urgentColor.b, 0.55)

              Repeater {
                model: 18
                Rectangle {
                  required property int index
                  x: ((index * 53) % 97) / 100 * fallLane.width
                  y: ((index * 31) % 83) / 100 * fallLane.height
                  width: index % 4 === 0 ? 3 : 2
                  height: width
                  radius: width / 2
                  color: index % 3 === 0 ? root.urgentColor : root.foregroundColor
                  opacity: 0.1 + (index % 4) * 0.07
                }
              }

              Repeater {
                model: 5
                Rectangle {
                  required property int index
                  x: fallLane.width / 2 + (index - 2) * fallLane.width * 0.1
                  y: fallLane.height * 0.18
                  width: 1
                  height: fallLane.height * 0.78
                  transformOrigin: Item.Top
                  rotation: (index - 2) * 12
                  color: Qt.rgba(root.urgentColor.r, root.urgentColor.g, root.urgentColor.b, 0.13)
                }
              }
              Repeater {
                model: 7
                Rectangle {
                  required property int index
                  width: fallLane.width * (0.35 + index * 0.1)
                  height: 1
                  anchors.horizontalCenter: parent.horizontalCenter
                  y: fallLane.height * (0.23 + index * 0.09)
                  color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.12 + index * 0.02)
                }
              }
              Rectangle {
                id: recallGlow
                x: 24
                width: parent.width - 48
                height: 9
                y: parent.height - 75
                radius: 5
                color: root.urgentColor
                opacity: 0.18
                SequentialAnimation on opacity {
                  running: root.running && !root.reducedMotion
                  loops: Animation.Infinite
                  NumberAnimation { to: 0.4; duration: 500 }
                  NumberAnimation { to: 0.12; duration: 500 }
                }
              }
              Rectangle {
                x: 24
                width: parent.width - 48
                height: 3
                y: parent.height - 72
                color: root.urgentColor
              }
              Text {
                anchors.right: parent.right
                anchors.rightMargin: 28
                y: parent.height - 64
                text: "RECALL LINE"
                color: root.urgentColor
                font.family: "monospace"
                font.pixelSize: 9 * root.textScale
                font.weight: Font.Bold
              }
              Repeater {
                model: 3
                Rectangle {
                  required property int index
                  width: challengeCard.width - 28 - index * 24
                  height: challengeCard.height
                  x: challengeCard.x + (challengeCard.width - width) / 2
                  y: challengeCard.y - 12 - index * 13
                  radius: 12
                  color: Qt.rgba(root.urgentColor.r, root.urgentColor.g, root.urgentColor.b, 0.045 + index * 0.02)
                  border.width: 1
                  border.color: Qt.rgba(root.urgentColor.r, root.urgentColor.g, root.urgentColor.b, 0.12)
                }
              }
              Rectangle {
                id: challengeCard
                width: Math.min(parent.width - 100, 570)
                height: 142
                x: (parent.width - width) / 2
                y: root.hinted ? (parent.height - height) / 2
                  : 22 + root.keyfallProgress * Math.max(0, parent.height - height - 100)
                radius: 12
                gradient: Gradient {
                  GradientStop { position: 0; color: Qt.rgba(root.urgentColor.r, root.urgentColor.g, root.urgentColor.b, root.hinted ? 0.2 : 0.12) }
                  GradientStop { position: 1; color: root.backgroundColor }
                }
                border.width: root.hinted ? 3 : 2
                border.color: root.hinted ? root.accentColor : root.urgentColor
                Behavior on y {
                  enabled: !root.reducedMotion
                  NumberAnimation { duration: 65 }
                }
                ColumnLayout {
                  anchors.fill: parent
                  anchors.margins: 18
                  spacing: 5
                  RowLayout {
                    Layout.fillWidth: true
                    Text {
                      Layout.fillWidth: true
                      text: root.hinted ? "CARD FROZEN · LEARN IT" : "INCOMING SHORTCUT"
                      color: root.hinted ? root.accentColor : root.urgentColor
                      font.family: "monospace"
                      font.pixelSize: 9 * root.textScale
                      font.weight: Font.Black
                      font.letterSpacing: 1
                    }
                    Text {
                      text: root.currentChallenge ? root.currentChallenge.category.toUpperCase() : ""
                      color: root.mutedColor
                      font.family: "monospace"
                      font.pixelSize: 9 * root.textScale
                      font.weight: Font.Bold
                    }
                  }
                  Text {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    text: root.currentChallenge ? root.currentChallenge.prompt : ""
                    color: root.foregroundColor
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.pixelSize: 18 * root.textScale
                    font.weight: Font.DemiBold
                  }
                }
              }
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 10
            Text {
              Layout.fillWidth: true
              text: root.currentChallenge
                ? (root.mode === "rescue" ? "Rescue task: " : "") + root.currentChallenge.prompt
                : ""
              visible: root.mode === "rescue"
              color: root.foregroundColor
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
              font.pixelSize: 20 * root.textScale
              font.weight: Font.DemiBold
            }

            RowLayout {
              Layout.alignment: Qt.AlignHCenter
              spacing: 8
              visible: root.hinted
              Repeater {
                model: root.expectedKeys
                KeyPill { required property string modelData; keyLabel: modelData }
              }
            }

            RowLayout {
              Layout.fillWidth: true
              Text {
                Layout.fillWidth: true
                text: root.feedback
                color: root.hinted ? root.accentColor : root.mutedColor
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: 13 * root.textScale
              }
              ArcadeButton {
                label: root.hinted ? "HINT SHOWN" : "SHOW HINT  H"
                primary: !root.hinted
                enabled: !root.hinted
                opacity: enabled ? 1 : 0.55
                onClicked: root.showHint()
              }
            }
          }
        }

        Repeater {
          model: 30
          Rectangle {
            id: confetti
            required property int index
            visible: root.screen === "results"
            width: 5 + index % 4
            height: 12 + index % 5
            radius: 2
            x: ((index * 73) % 97) / 100 * parent.width
            y: ((index * 41) % 89) / 100 * parent.height
            rotation: index * 31
            color: index % 3 === 0 ? root.modeAccent
              : index % 3 === 1 ? root.urgentColor : root.foregroundColor
            opacity: 0.35 + (index % 5) * 0.1
            SequentialAnimation on y {
              running: confetti.visible && !root.reducedMotion
              loops: Animation.Infinite
              NumberAnimation { to: confetti.parent.height + 20; duration: 2600 + confetti.index * 53 }
              PropertyAction { value: -20 }
            }
            RotationAnimation on rotation {
              running: confetti.visible && !root.reducedMotion
              from: confetti.index * 31
              to: confetti.index * 31 + 360
              duration: 1800 + confetti.index * 29
              loops: Animation.Infinite
            }
          }
        }

        ColumnLayout {
          anchors.centerIn: parent
          width: Math.min(parent.width, 760)
          spacing: 20
          visible: root.screen === "results"
          opacity: visible ? 1 : 0
          scale: visible ? 1 : 0.9
          Behavior on opacity { NumberAnimation { duration: root.reducedMotion ? 0 : 220 } }
          Behavior on scale { NumberAnimation { duration: root.reducedMotion ? 0 : 360; easing.type: Easing.OutBack } }

          Text {
            Layout.fillWidth: true
            text: root.newBest ? "NEW PERSONAL BEST!" : root.modeName(root.mode) + " COMPLETE"
            color: root.newBest ? root.accentColor : root.foregroundColor
            horizontalAlignment: Text.AlignHCenter
            font.family: "monospace"
            font.pixelSize: 28 * root.textScale
            font.weight: Font.Black
          }

          Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 132
            Layout.preferredHeight: 132
            radius: 66
            color: Qt.rgba(root.modeAccent.r, root.modeAccent.g, root.modeAccent.b, 0.16)
            border.width: 4
            border.color: root.modeAccent
            scale: root.screen === "results" ? 1 : 0.5
            Behavior on scale {
              enabled: !root.reducedMotion
              NumberAnimation { duration: 420; easing.type: Easing.OutBack }
            }
            Column {
              anchors.centerIn: parent
              spacing: -5
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.resultRank
                color: root.modeAccent
                font.family: "monospace"
                font.pixelSize: 58 * root.textScale
                font.weight: Font.Black
              }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "RANK"
                color: root.mutedColor
                font.family: "monospace"
                font.pixelSize: 9 * root.textScale
                font.weight: Font.Bold
                font.letterSpacing: 1.4
              }
            }
          }

          Text {
            Layout.fillWidth: true
            text: root.finalScore.toLocaleString()
            color: root.foregroundColor
            horizontalAlignment: Text.AlignHCenter
            font.family: "monospace"
            font.pixelSize: 42 * root.textScale
            font.weight: Font.Black
          }
          Text {
            Layout.fillWidth: true
            text: "FINAL SCORE"
            color: root.mutedColor
            horizontalAlignment: Text.AlignHCenter
            font.family: "monospace"
            font.pixelSize: 10 * root.textScale
            font.weight: Font.Bold
            font.letterSpacing: 1.5
          }

          RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 44
            Repeater {
              model: [
                ["CLEAN", root.finalClean],
                ["BEST STREAK", root.finalStreak],
                ["TIME", root.formatTime(root.finalElapsedMs)]
              ]
              ColumnLayout {
                required property var modelData
                Text {
                  Layout.alignment: Qt.AlignHCenter
                  text: parent.modelData[1]
                  color: root.foregroundColor
                  font.family: "monospace"
                  font.pixelSize: 25 * root.textScale
                  font.weight: Font.Black
                }
                Text {
                  Layout.alignment: Qt.AlignHCenter
                  text: parent.modelData[0]
                  color: root.mutedColor
                  font.family: "monospace"
                  font.pixelSize: 10 * root.textScale
                  font.weight: Font.Bold
                }
              }
            }
          }
          Text {
            Layout.fillWidth: true
            text: root.finalClean === 0
              ? "Hints kept the run moving. Replay it and see which answers arrive before you need them."
              : "You recalled " + root.finalClean + " shortcut" + (root.finalClean === 1 ? "" : "s") + " cleanly."
            color: root.mutedColor
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 15 * root.textScale
          }
          RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 14
            ArcadeButton {
              label: "PLAY AGAIN"
              primary: true
              onClicked: root.startGame(root.mode)
            }
            ArcadeButton {
              label: "CHOOSE A GAME"
              onClicked: root.openHub()
            }
          }
        }
      }
    }
  }
}
