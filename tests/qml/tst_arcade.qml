import QtQuick
import QtTest
import "../../app" as App

Item {
  width: 1280
  height: 820

  property var testCourse: ({
    lessons: [
      {
        id: "windows",
        title: "Windows",
        steps: [
          { id: "close", instruction: "Close the focused window", keys: ["SUPER", "W"] },
          { id: "float", practicePrompt: "Toggle floating mode", keys: ["SUPER", "ALT", "SPACE"] }
        ]
      },
      {
        id: "workspaces",
        title: "Workspaces",
        steps: [
          { id: "next", instruction: "Move to the next workspace", keys: ["SUPER", "RIGHT"] }
        ]
      }
    ]
  })
  property var testStats: ({
    version: 1,
    modes: {
      sprint: { bestScore: 0, bestStreak: 0, plays: 0, clears: 0 },
      rescue: { bestScore: 0, bestStreak: 0, plays: 0, clears: 0 },
      keyfall: { bestScore: 0, bestStreak: 0, plays: 0, clears: 0 }
    }
  })

  App.ArcadePanel {
    id: arcade
    anchors.fill: parent
    course: testCourse
    stats: testStats
    backgroundColor: "#101018"
    foregroundColor: "#f2f2f2"
    accentColor: "#88ccff"
    mutedColor: "#9a9aaa"
    urgentColor: "#ff7777"
    textScale: 1
    reducedMotion: true
  }

  SignalSpy { id: resultSpy; target: arcade; signalName: "statsCommitted" }

  TestCase {
    name: "ShortcutArcade"
    when: windowShown

    function init() {
      arcade.active = false
      arcade.active = true
      resultSpy.clear()
    }

    function answerCurrent() {
      var keys = arcade.expectedKeys.slice()
      arcade.handleKeyPress(keys[keys.length - 1], keys)
    }

    function test_hubBuildsCourseChallenges() {
      compare(arcade.screen, "hub")
      compare(arcade.challenges.length, 3)
      compare(arcade.modeStats("sprint").bestScore, 0)
    }

    function test_numberKeysLaunchEachVisualMode() {
      arcade.handleControlKey("1")
      compare(arcade.screen, "sprint")
      arcade.openHub()
      arcade.handleControlKey("2")
      compare(arcade.screen, "rescue")
      arcade.openHub()
      arcade.handleControlKey("3")
      compare(arcade.screen, "keyfall")
    }

    function test_hintAdvancesWithoutPoints() {
      arcade.startGame("sprint")
      arcade.showHint()
      verify(arcade.hinted)
      answerCurrent()
      compare(arcade.challengeIndex, 1)
      compare(arcade.score, 0)
      compare(arcade.cleanAnswers, 0)
    }

    function test_wrongChordDoesNotBreakRunOrSubtract() {
      arcade.startGame("sprint")
      arcade.handleKeyPress("X", ["SUPER", "X"])
      compare(arcade.challengeIndex, 0)
      compare(arcade.score, 0)
      compare(arcade.streak, 0)
      verify(arcade.feedback.indexOf("Nothing lost") !== -1)
    }

    function test_rescueCompletesSixTasks() {
      arcade.startGame("rescue")
      for (var index = 0; index < 6; index++) answerCurrent()
      compare(arcade.screen, "results")
      compare(arcade.finalClean, 6)
      compare(resultSpy.count, 1)
    }

    function test_keyfallTurnsDeadlineIntoHint() {
      arcade.startGame("keyfall")
      arcade.challengeStartedAt = Date.now() - 8000
      tryCompare(arcade, "hinted", true, 300)
      compare(arcade.challengeIndex, 0)
      compare(arcade.score, 0)
      verify(arcade.feedback.indexOf("no life") !== -1)
    }
  }
}
