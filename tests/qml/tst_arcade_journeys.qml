import QtQuick
import QtTest
import "../../app" as App
import "../../app/ArcadeLogic.js" as Logic
import "../../app/ThemeColors.js" as Colors

Item {
  id: host
  width: 1600
  height: 1000
  property var fullCourse: ({ lessons: [] })

  App.ArcadePanel {
    id: arcade
    anchors.fill: parent
    course: host.fullCourse
    stats: Logic.defaultStats()
    backgroundColor: "#101018"
    foregroundColor: "#f2f2f2"
    accentColor: "#88ccff"
    mutedColor: "#9a9aaa"
    urgentColor: "#ff7777"
    textScale: 1
    reducedMotion: true
  }

  TestCase {
    name: "ArcadeFullCourseJourneys"
    when: windowShown

    function initTestCase() {
      var request = new XMLHttpRequest()
      request.open("GET", Qt.resolvedUrl("../../courses/omarchy-basics.json"), false)
      request.send()
      host.fullCourse = JSON.parse(request.responseText)
    }
    function init() {
      failOnWarning(/.*/)
      arcade.active = false
      host.width = 1600
      host.height = 1000
      arcade.textScale = 1
      arcade.reducedMotion = true
      arcade.backgroundColor = "#101018"
      arcade.foregroundColor = "#f2f2f2"
      arcade.accentColor = "#88ccff"
      arcade.mutedColor = "#9a9aaa"
      arcade.workingStats = Logic.defaultStats()
      arcade.selectedCategory = "all"
      arcade.selectedPace = "standard"
      arcade.openHub()
      arcade.active = true
      wait(20)
    }
    function cleanup() { arcade.active = false }
    function object(name) {
      var result = findChild(arcade, name)
      verify(result !== null, name)
      return result
    }
    function clock(ms) {
      arcade.lastTickAt = Date.now() - ms
      arcade.updateClock(Date.now())
    }
    function answer() {
      var before = arcade.answeredCount
      var keys = arcade.expectedKeys.slice()
      arcade.handleKeyPress(keys[keys.length - 1], keys)
      compare(arcade.answeredCount, before + 1)
      verify(arcade.responsePending)
    }
    function advance() {
      arcade.responseRemainingMs = 0
      arcade.updateClock(Date.now())
    }
    function signatures() { return arcade.deck.map(function(c) { return c.signature }).join("|") }

    function test_everyRescueMission_data() {
      var challenges = Logic.buildChallenges(host.fullCourse)
      var rows = []
      Logic.rescueMissions(challenges).forEach(function(mission) {
        for (var assist of ["clean", "hint", "wrong"]) rows.push({
          tag: mission.id + "-" + assist, mission: mission, assist: assist
        })
      })
      return rows
    }
    function test_everyRescueMission(data) {
      var mission = data.mission
      arcade.prepareGame("rescue", mission.steps.map(function(s) { return s.challenge }),
        false, "standard", mission)
      var original = signatures()
      for (var i = 0; i < mission.steps.length; i++) {
        compare(arcade.currentPrompt, mission.steps[i].prompt)
        if (i === 1 && data.assist === "hint") arcade.showHint()
        if (i === 1 && data.assist === "wrong")
          arcade.handleKeyPress("F12", ["CTRL", "ALT", "F12"])
        answer()
        compare(arcade.rescueCompleted, i + 1)
        if (mission.id === "scratchpad-recovery") {
          var scene = object("arcadeRescueScene")
          if (i === 3) {
            verify(scene.sceneState.scratchpadVisible)
            verify(scene.terminalVisible)
          } else if (i === 4) {
            verify(!scene.sceneState.scratchpadVisible)
            verify(!scene.terminalVisible)
            compare(scene.windowForId(scene.sceneState, scene.sceneState.focusId).kind, "browser")
          } else if (i === 5) {
            compare(scene.sceneState.windows.length, 1)
            compare(scene.terminalWorkspace, 0)
            verify(!scene.terminalVisible)
          }
        }
        if (i === 1 && data.assist === "hint") compare(arcade.lastAwardedPoints, 0)
        advance()
      }
      compare(arcade.screen, "complete")
      compare(arcade.finalClean, data.assist === "clean" ? 6 : 5)
      arcade.handleControlKey("RETURN")
      compare(arcade.screen, "results")
      verify(!object("arcadeRecordContext").visible)
      compare(arcade.currentPage.controls.length, 3)
      object("arcadeReplayButton").clicked()
      compare(arcade.screen, "rescue")
      compare(signatures(), original)
      compare(arcade.rescueMission.id, mission.id)
    }

    function test_keyfallFullRounds_data() {
      var rows = []
      for (var pace of ["relaxed", "standard", "fast"])
        for (var assist of ["clean", "hint", "wrong", "timeout"])
          rows.push({ tag: pace + "-" + assist, pace: pace, assist: assist })
      return rows
    }
    function test_keyfallFullRounds(data) {
      arcade.selectedPace = data.pace
      arcade.startGame("keyfall")
      var original = signatures()
      var originalId = arcade.currentChallenge.id
      var scoreBeforeHelp = 0
      var retries = 0
      for (var step = 0; arcade.running && step < 19; step++) {
        var assisted = step === 0 && data.assist !== "clean"
        if (step === 0) {
          if (data.assist === "hint") arcade.showHint()
          else if (data.assist === "wrong")
            arcade.handleKeyPress("F12", ["CTRL", "ALT", "F12"])
          else if (data.assist === "timeout") clock(arcade.arrivalDwellMs + arcade.fallDurationMs + 1)
        }
        if (assisted) {
          scoreBeforeHelp = arcade.score
          verify(arcade.hintVisible)
          compare(object("arcadeKeyfallField").practiceCount, 1)
        }
        if (arcade.isRetry) {
          retries++
          compare(arcade.currentChallenge.id, originalId)
          verify(!arcade.hinted)
          verify(step >= 3, "Retry follows at least two intervening prompts")
        }
        answer()
        if (assisted) {
          compare(arcade.score, scoreBeforeHelp)
          compare(arcade.lastAwardedPoints, 0)
        }
        var field = object("arcadeKeyfallField")
        compare(field.practiceCount + field.recalledCount, arcade.answeredCount)
        advance()
      }
      compare(arcade.screen, "complete")
      verify(arcade.answeredCount >= 12 && arcade.answeredCount <= 18)
      compare(retries, data.assist === "clean" ? 0 : 1)
      compare(arcade.regainedRecall, data.assist === "clean" ? 0 : 1)
      arcade.showResults()
      object("arcadeReplayButton").clicked()
      compare(signatures(), original)
      compare(arcade.runPace, data.pace)
      compare(arcade.queue.length, 12)
    }

    function test_sprintAllCanonicalChordsAndReplay() {
      arcade.startGame("sprint")
      var original = signatures()
      var count = arcade.deck.length
      var visited = {}
      for (var i = 0; i < count; i++) {
        visited[arcade.currentChallenge.signature] = true
        answer()
        advance()
      }
      compare(Object.keys(visited).length, count)
      clock(60000)
      compare(arcade.screen, "complete")
      compare(arcade.finalElapsedMs, 60000)
      arcade.showResults()
      object("arcadeReplayButton").clicked()
      compare(signatures(), original)
      compare(arcade.previousBest.splits.length, count)
      arcade.showHint()
      arcade.handleControlKey("P")
      compare(arcade.screen, "sprint")
      clock(60000)
      compare(arcade.screen, "complete")
      compare(Logic.bestForDeck(arcade.workingStats, arcade.runDeckKey).plays, 1)
    }

    function test_repeatedWrongKeyDoesNotHideRevealedAnswer() {
      arcade.startGame("keyfall")
      for (var i = 0; i < 3; i++) {
        arcade.handleKeyPress("F12", ["CTRL", "ALT", "F12"])
        verify(arcade.hintVisible)
        compare(arcade.score, 0)
        compare(object("arcadeKeyfallField").practiceCount, 1)
      }
      compare(arcade.wrongAttempts, 3)
    }
    function test_deferredBurstAndMissCannotSurviveRestart() {
      arcade.reducedMotion = false
      arcade.startGame("keyfall")
      arcade.handleKeyPress("F12", ["CTRL", "ALT", "F12"])
      verify(object("arcadePromptCard").keyfallMissAnimating)
      arcade.startGame("sprint")
      wait(450)
      verify(!object("arcadePromptCard").keyfallMissAnimating)
      compare(object("arcadePromptCard").opacity, 1)
      answer()
      arcade.startGame("rescue")
      wait(50)
      compare(object("arcadeScoreBurst").opacity, 0)
    }

    function test_readableResponsiveStages_data() {
      var rows = []
      for (var mode of ["rescue", "sprint", "keyfall"])
        for (var display of [
          { width: 1600, height: 1000, scale: 1, bg: "#101018", fg: "#ffffff", accent: "#ddaa33" },
          { width: 1280, height: 820, scale: 1.2, bg: "#f5f5f0", fg: "#182331", accent: "#397bdc" },
          { width: 1024, height: 720, scale: 1.1, bg: "#060b1e", fg: "#ffcead", accent: "#7d82d9" },
          { width: 800, height: 700, scale: 1.1, bg: "#141414", fg: "#ffffff", accent: "#654288" }
        ]) rows.push({ tag: mode + "-" + display.width, mode: mode, display: display })
      return rows
    }
    function test_readableResponsiveStages(data) {
      var display = data.display
      host.width = display.width
      host.height = display.height
      arcade.textScale = display.scale
      arcade.backgroundColor = display.bg
      arcade.foregroundColor = display.fg
      arcade.accentColor = display.accent
      arcade.startGame(data.mode)
      wait(80)
      verify(Colors.contrast(String(arcade.modeInk), String(arcade.surfaceColor)) >= 4.5)
      var card = object("arcadePromptCard")
      var prompt = object("arcadePrompt")
      verify(prompt.contentHeight <= prompt.height + 1)
      verify(card.width <= object("arcadeArena").width)
      if (data.mode === "rescue" && display.width >= 1024) {
        var scene = object("arcadeRescueScene")
        verify(scene.mapToItem(arcade, 0, scene.height).y <= arcade.height - arcade.dialogMargin,
          "The simulated desktop fits without hiding its status strip")
      }
      arcade.showHint()
      wait(40)
      verify(prompt.contentHeight <= prompt.height + 1)
      if (data.mode === "rescue") {
        var flight = object("arcadeRescueFlight")
        var scroller = object("arcadeScroll")
        var flightTop = flight.mapToItem(arcade, 0, 0).y
        verify(flight.visible)
        verify(flightTop >= scroller.mapToItem(arcade, 0, scroller.height).y,
          "Flight route stays below the desktop viewport")
        verify(flightTop + flight.height <= arcade.height - arcade.dialogMargin,
          "Flight route is visible without scrolling")
        scroller.contentItem.contentY = Math.max(0,
          scroller.contentItem.contentHeight - scroller.contentItem.height)
        wait(20)
        compare(flight.mapToItem(arcade, 0, 0).y, flightTop)
      }
      if (data.mode === "sprint") {
        var console = object("arcadeSprintRaceConsole")
        verify(card.y + card.height + 16 <= console.y, "Prompt and race stay separate")
      }
      answer()
      wait(20)
      var badge = object("arcadeScoreBurst")
      var label = object("arcadeScoreBurstLabel")
      compare(label.lines.length, 1)
      verify(badge.x >= 0 && badge.x + badge.width <= object("arcadeArena").width)
      arcade.finishGame()
      arcade.showResults()
      wait(50)
      verify(!object("arcadeRescueFlight").visible)
      compare(object("arcadeResultScore").lines.length, 1)
      verify(arcade.currentPage.controls.length <= 3)
      verify(!object("arcadeNavigationHint").visible)
    }
    function test_themeChangeUpdatesEveryGameAccent() {
      var previous = ["rescue", "sprint", "keyfall"].map(function(mode) { return String(arcade.colorForMode(mode)) })
      arcade.accentColor = "#eeaa44"
      for (var i = 0; i < 3; i++)
        verify(String(arcade.colorForMode(["rescue", "sprint", "keyfall"][i])) !== previous[i])
    }
    function test_sprintKeepsRacingPastFirstLapAndResetsImmediately() {
      arcade.reducedMotion = false
      arcade.startGame("sprint")
      var track = object("arcadeSprintTrack")
      var racer = object("arcadeSprintPlayerRacer")
      compare(track.lapFor(track.trackMaximum), 1)
      compare(track.progressFor(track.trackMaximum), 1)
      compare(track.lapFor(track.trackMaximum + 1), 2)
      compare(track.progressFor(track.trackMaximum + 1), 1 / track.trackMaximum)
      answer()
      advance()
      wait(300)
      arcade.startGame("sprint")
      compare(racer.x, -racer.width / 2)
    }
    function test_pixelScoreFitsLongTotals() {
      arcade.startGame("sprint")
      arcade.finishGame()
      arcade.showResults()
      for (var score of [0, 280, 10000, 123456789]) {
        arcade.finalScore = score
        wait(20)
        var label = object("arcadeResultScore")
        compare(label.lines.length, 1)
        verify(label.width <= label.parent.width - 16)
      }
    }
    function test_vectorMotionStopsOutsideActivePlay() {
      arcade.reducedMotion = false
      arcade.startGame("sprint")
      var grid = object("arcadeSprintVectorGrid")
      verify(grid.moving)
      wait(180)
      verify(grid.travel > 0)
      arcade.reducedMotion = true
      var stopped = grid.travel
      wait(180)
      compare(grid.travel, stopped)
      arcade.reducedMotion = false
      arcade.openHub()
      verify(!grid.moving)
      stopped = grid.travel
      wait(180)
      compare(grid.travel, stopped)
    }
  }
}
