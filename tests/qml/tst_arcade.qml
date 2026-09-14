import QtQuick
import QtQuick.Controls
import QtTest
import "../../app" as App
import "../../app/ArcadeLogic.js" as Logic

Item {
  id: host
  width: 1280
  height: 820

  readonly property var fixture: ({
    lessons: [
      {
        id: "everyday-apps", title: "Everyday apps",
        steps: [
          { id: "launch-terminal", instruction: "Open a terminal", keys: ["SUPER", "RETURN"] },
          { id: "launch-browser", instruction: "Open a browser", keys: ["SUPER", "B"] }
        ]
      },
      {
        id: "windows", title: "Windows",
        steps: [
          { id: "windows-close-one", instruction: "Close the focused window", keys: ["SUPER", "W"] },
          { id: "windows-float", practicePrompt: "Toggle floating mode", keys: ["SUPER", "T"] },
          { id: "windows-resize", practicePrompt: "Widen the window", keys: ["SUPER", "EQUAL"] },
          { id: "windows-fullscreen", practicePrompt: "Go fullscreen", keys: ["SUPER", "F"] }
        ]
      },
      {
        id: "workspaces", title: "Workspaces",
        steps: [
          { id: "workspaces-send", instruction: "Send and follow", keys: ["SUPER", "SHIFT", "2"] },
          { id: "workspaces-jump", instruction: "Switch to workspace 2", keys: ["SUPER", "2"] },
          { id: "next-workspace", instruction: "Move to the next workspace", keys: ["SUPER", "RIGHT"] }
        ]
      }
    ]
  })
  property var testCourse: fixture
  property var testStats: Logic.defaultStats()

  App.ArcadePanel {
    id: arcade
    anchors.fill: parent
    course: host.testCourse
    stats: host.testStats
    backgroundColor: "#101018"
    foregroundColor: "#f2f2f2"
    accentColor: "#88ccff"
    mutedColor: "#9a9aaa"
    urgentColor: "#ff7777"
    textScale: 1
    reducedMotion: true
    Keys.onPressed: event => {
      var direct = event.key === Qt.Key_Return ? "RETURN" : event.key === Qt.Key_Tab ? "TAB"
        : event.key === Qt.Key_Space ? "SPACE" : event.key === Qt.Key_R ? "R" : ""
      if (!direct) return
      if (arcade.running)
        arcade.handleKeyPress(direct, event.modifiers & Qt.MetaModifier ? ["SUPER", direct] : [direct])
      else arcade.handleControlKey(direct)
      event.accepted = true
    }
    Keys.onReleased: event => { event.accepted = true }
  }
  SignalSpy { id: resultSpy; target: arcade; signalName: "statsCommitted" }
  SignalSpy { id: clearSpy; target: arcade; signalName: "clearInputRequested" }
  SignalSpy { id: closeSpy; target: arcade; signalName: "closeRequested" }
  SignalSpy { id: effectSpy; target: arcade; signalName: "effectRequested" }

  TestCase {
    name: "ShortcutArcade"
    when: windowShown

    function init() {
      failOnWarning(/.*/)
      arcade.active = false
      host.width = 1280
      host.height = 820
      host.testCourse = host.fixture
      host.testStats = Logic.defaultStats()
      arcade.workingStats = Logic.defaultStats()
      arcade.textScale = 1
      arcade.reducedMotion = true
      arcade.backgroundColor = "#101018"
      arcade.foregroundColor = "#f2f2f2"
      arcade.accentColor = "#88ccff"
      arcade.mutedColor = "#9a9aaa"
      arcade.selectedCategory = "all"
      arcade.selectedPace = "standard"
      arcade.pressedKeys = []
      arcade.guidePack = null
      arcade.wallpaperSource = ""
      arcade.openHub()
      arcade.active = true
      wait(1)
      resultSpy.clear()
      clearSpy.clear()
      closeSpy.clear()
      effectSpy.clear()
    }
    function cleanup() { arcade.active = false }
    function start(mode) {
      arcade.startGame(mode)
      compare(arcade.screen, mode)
    }
    function stepClock(ms) {
      arcade.lastTickAt = Date.now() - ms
      arcade.updateClock(Date.now())
    }
    function finishResponse() {
      if (arcade.responsePending) {
        arcade.responseRemainingMs = 0
        arcade.updateClock(Date.now())
      }
    }
    function answerCurrent(advance) {
      var keys = arcade.expectedKeys.slice()
      arcade.handleKeyPress(keys[keys.length - 1], keys)
      if (advance !== false) finishResponse()
    }
    function showResults() {
      compare(arcade.screen, "complete")
      arcade.handleControlKey("RETURN")
      compare(arcade.screen, "results")
    }
    function object(name) {
      var item = findChild(arcade, name)
      verify(item !== null, name + " exists")
      return item
    }
    function deckSignatures() { return arcade.deck.map(function(item) { return item.signature }).join("|") }

    function test_hubBuildsCourseChallenges() {
      compare(arcade.screen, "hub")
      compare(arcade.challenges.length, 9)
      compare(arcade.modeStats("sprint").bestScore, 0)
      compare(arcade.mastery.practiced, 0)
      compare(arcade.mastery.mastered, 0)
    }
    function test_arcadePagesStayPreloadedAndAreReusedAcrossNavigation() {
      var loaders = [
        object("arcadeHubPageLoader"),
        object("arcadePlayPageLoader"),
        object("arcadePausedPageLoader"),
        object("arcadeCompletePageLoader"),
        object("arcadeResultsPageLoader")
      ]
      var items = loaders.map(function(loader) {
        compare(loader.active, true)
        compare(loader.status, Loader.Ready)
        verify(loader.item !== null)
        return loader.item
      })

      arcade.startGame("rescue")
      compare(loaders[1].visible, true)
      compare(arcade.screen, "rescue")
      arcade.openHub()

      for (var i = 0; i < loaders.length; i++) compare(loaders[i].item, items[i])
    }
    function test_arcadeUsesLargerReadableText_data() {
      return [{ tag: "default", scale: 1 }, { tag: "larger-preference", scale: 1.3 }]
    }
    function test_arcadeUsesLargerReadableText(data) {
      arcade.textScale = data.scale
      wait(30)
      compare(object("arcadeTitle").text, "Learn Omarchy Arcade")
      verify(object("arcadeTitle").font.pixelSize >= 30 * data.scale)
      var description = object("arcadeGameDescription-rescue")
      verify(description.font.pixelSize >= Math.floor(16 * data.scale))
      verify(description.height >= description.contentHeight)
      verify(object("arcadePlay-rescue").contentItem.font.pixelSize >= Math.floor(16 * data.scale))
      start("keyfall")
      wait(30)
      var prompt = object("arcadePrompt")
      verify(prompt.font.pixelSize >= Math.floor(28 * 1.25 * data.scale))
      verify(prompt.height >= prompt.contentHeight)
    }
    function test_firstVisitHasOneStartingPointAndNoDashboard() {
      compare(arcade.selectedControl.objectName, "arcadePlay-rescue")
      var navigationHint = object("arcadeNavigationHint")
      compare(navigationHint.horizontalAlignment, Text.AlignHCenter)
      verify(Math.abs(navigationHint.x + navigationHint.width / 2 - navigationHint.parent.width / 2) <= 1)
      verify(object("arcadeModeCard-rescue").selectionHighlighted)
      verify(!object("arcadeModeCard-sprint").selectionHighlighted)
      verify(!object("arcadeModeCard-keyfall").selectionHighlighted)
      verify(object("arcadePlay-rescue").primary)
      verify(!object("arcadePlay-sprint").primary)
      verify(!object("arcadePlay-keyfall").primary)
      compare(object("arcadePlay-rescue").text, "Play")
      compare(object("arcadePlay-sprint").text, "Play")
      compare(object("arcadePlay-keyfall").text, "Play")
      verify(!object("arcadeOptions").visible)
      verify(!object("arcadeProgress").visible)
      verify(!object("arcadeTopicOption").visible)
      verify(!object("arcadePaceOption").visible)
      compare(arcade.navigationControls.length, 6)
      verify(arcade.navigationControls.every(function(control) { return control.visible }))
      arcade.handleControlKey("RETURN")
      compare(arcade.mode, "rescue")
      compare(arcade.screen, "rescue")
      compare(arcade.currentPage.controls.length, 0)
    }
    function test_optionalSettingsAndProgressAreProgressivelyDisclosed() {
      object("arcadeOptionsToggle").clicked()
      verify(object("arcadeOptions").visible)
      verify(!object("arcadeProgress").visible)
      compare(arcade.navigationControls.length, 8)
      var before = arcade.selectedPace
      object("arcadePaceOption").clicked()
      verify(arcade.selectedPace !== before)
      var category = arcade.selectedCategory
      object("arcadeTopicOption").clicked()
      verify(arcade.selectedCategory !== category)
      object("arcadeProgressToggle").clicked()
      verify(!object("arcadeOptions").visible)
      verify(object("arcadeProgress").visible)
      verify(!object("arcadeMilestone-first-practice").visible, "no wall of unearned badges on first visit")
      compare(arcade.navigationControls.length, 6)
      arcade.handleEscape()
      compare(arcade.screen, "hub")
      verify(!object("arcadeProgress").visible)
      compare(closeSpy.count, 0)
      arcade.handleEscape()
      compare(closeSpy.count, 1)
    }
    function test_progressStaysSavedButCollapsedWhenReturningToHub() {
      start("rescue")
      answerCurrent()
      arcade.openHub()
      verify(!object("arcadeProgress").visible)
      compare(arcade.mastery.practiced, 1)
      object("arcadeProgressToggle").clicked()
      verify(object("arcadeMilestone-first-practice").visible)
      verify(object("arcadeMilestone-first-practice").earned)
      arcade.openHub()
      verify(!object("arcadeProgress").visible)
      compare(arcade.mastery.practiced, 1)
    }
    function test_hubFrameFitsItsContentsOnTallDisplays() {
      host.height = 1600
      wait(20)
      verify(object("arcadeFrame").height < 900)
      verify(object("arcadeFrame").height > object("arcadeModeGrid").height)
      var scroller = object("arcadeScroll")
      verify(scroller.contentHeight <= scroller.height + 1)
      arcade.startGame("rescue")
      wait(20)
      verify(object("arcadeFrame").height >= host.height - arcade.dialogMargin * 2 - 1)
      compare(arcade.currentPage.controls.length, 0)
    }
    function test_gameDialogsUseConsistentFramesAndCloseControl() {
      host.width = 1600
      host.height = 1000
      arcade.startGame("rescue")
      wait(20)
      var frame = object("arcadeFrame")
      var close = object("arcadeCloseButton")
      compare(close.text, "×")
      verify(close.square)
      compare(close.Accessible.name, "Return to arcade hub")
      verify(frame.height >= host.height - arcade.dialogMargin * 2 - 1)
      var support = object("arcadeSupportPanel")
      verify(support.width <= 1040 * arcade.textScale + 1)
      close.clicked()
      compare(arcade.screen, "hub")

      arcade.startGame("rescue")
      arcade.pauseGame()
      wait(20)
      verify(frame.width <= arcade.nonPlayWidth + 1)
      verify(frame.height < host.height * 0.75)
      compare(close.Accessible.name, "Return to arcade hub")
      close.clicked()
      compare(arcade.screen, "hub")

      arcade.screen = "results"
      wait(20)
      var resultPreview = findChild(arcade.currentPage, "arcadeModePreview-rescue")
      var resultCopy = findChild(arcade.currentPage, "arcadeResultsCopy")
      verify(resultPreview !== null && resultCopy !== null)
      verify(frame.height < host.height * 0.85)
      verify(resultCopy.y > resultPreview.y + resultPreview.height)
      fuzzyCompare(resultPreview.x + resultPreview.width / 2,
        resultCopy.x + resultCopy.width / 2, 1)
      close.clicked()
      compare(arcade.screen, "hub")
    }
    function test_escapeAndCloseLeaveEveryActiveGame_data() {
      return [{ tag: "Rescue", mode: "rescue" }, { tag: "Sprint", mode: "sprint" }, { tag: "Keyfall", mode: "keyfall" }]
    }
    function test_escapeAndCloseLeaveEveryActiveGame(data) {
      arcade.startGame(data.mode)
      compare(arcade.screen, data.mode)
      keyClick(Qt.Key_Escape)
      compare(arcade.screen, "hub")
      arcade.startGame(data.mode)
      object("arcadeCloseButton").clicked()
      compare(arcade.screen, "hub")
    }
    function test_largeDisplayUsesMoreWidthAndBreathingRoom() {
      host.width = 1920
      host.height = 1080
      wait(30)
      var frame = object("arcadeFrame")
      verify(frame.width >= 1600)
      verify(frame.width <= host.width - arcade.dialogMargin * 2)
      var grid = object("arcadeModeGrid")
      compare(grid.columns, 3)
      verify(grid.columnSpacing >= 32)
      var rescue = object("arcadeModeCard-rescue")
      var sprint = object("arcadeModeCard-sprint")
      verify(sprint.x - rescue.x - rescue.width >= 32)
      verify(rescue.height >= 350)
      compare(frame.color.a, 1)
    }
    function test_wallpaperStaysPreloadedBehindOpaqueDialog() {
      arcade.wallpaperSource = Qt.resolvedUrl("../../assets/splash/learn-omarchy-poster.png")
      var background = object("arcadeWallpaper")
      tryCompare(background, "status", Image.Ready)
      compare(background.width, host.width)
      compare(background.height, host.height)
      compare(background.fillMode, Image.PreserveAspectCrop)
      compare(background.cache, true)
      verify(background.visible)
      compare(object("arcadeFrame").color.a, 1)
      compare(arcade.wallpaperNotice, "")
      arcade.active = false
      compare(background.source, arcade.wallpaperSource)
      compare(background.status, Image.Ready)
      arcade.active = true
      compare(background.status, Image.Ready)
    }
    function test_missingWallpaperReportsFallbackWithoutBlockingGames() {
      ignoreWarning(/.*Cannot open:.*/)
      ignoreWarning(/.*learn-omarchy:.*theme wallpaper could not be loaded.*/)
      arcade.wallpaperSource = Qt.resolvedUrl("../../assets/no-such-wallpaper.png")
      var background = object("arcadeWallpaper")
      tryCompare(background, "status", Image.Error)
      verify(!background.visible)
      verify(arcade.wallpaperNotice.indexOf("theme color") >= 0)
      start("rescue")
      compare(arcade.screen, "rescue")
      arcade.wallpaperSource = Qt.resolvedUrl("../../assets/splash/learn-omarchy-poster.png")
      tryCompare(background, "status", Image.Ready)
      compare(arcade.wallpaperNotice, "")
    }
    function test_earnedMilestonesDistinguishHintsFromIndependentRecall() {
      compare(arcade.learningMilestones.length, 3)
      verify(!object("arcadeMilestone-first-practice").earned)
      verify(!object("arcadeMilestone-independent-recall").earned)
      verify(!object("arcadeMilestone-retained-days").earned)
      start("rescue")
      arcade.showHint()
      answerCurrent()
      arcade.openHub()
      verify(object("arcadeMilestone-first-practice").earned)
      verify(!object("arcadeMilestone-independent-recall").earned)
      start("rescue")
      answerCurrent()
      arcade.openHub()
      verify(object("arcadeMilestone-independent-recall").earned)
      verify(!object("arcadeMilestone-retained-days").earned)
    }
    function test_retainedMilestoneSurvivesLaterMistakeWithoutNewPersistence() {
      var challenge = arcade.challenges[0]
      var now = Date.now()
      var first = Logic.recordAttempt(Logic.defaultStats(), challenge, {
        hinted: false, wrongAttempts: 0, elapsedMs: 1000, sessionId: "milestone-day-one"
      }, now - 86400001)
      var second = Logic.recordAttempt(first, challenge, {
        hinted: false, wrongAttempts: 0, elapsedMs: 1000, sessionId: "milestone-day-two"
      }, now)
      arcade.workingStats = second
      compare(arcade.mastery.mastered, 1)
      verify(object("arcadeMilestone-retained-days").earned)
      arcade.workingStats = Logic.recordAttempt(second, challenge, {
        hinted: true, wrongAttempts: 1, elapsedMs: 1000, sessionId: "milestone-later-practice"
      }, now)
      compare(arcade.mastery.mastered, 0)
      verify(object("arcadeMilestone-retained-days").earned)
      verify(object("arcadeMilestone-independent-recall").earned)
      compare(Object.keys(arcade.workingStats).sort().join(","), Object.keys(Logic.defaultStats()).sort().join(","))
    }
    function test_guideUsesSelectedPackStaticFrame_data() {
      return [{ tag: "Ohm1", pack: "ohm-1" }, { tag: "Ollie", pack: "owl" }]
    }
    function test_guideUsesSelectedPackStaticFrame(data) {
      var request = new XMLHttpRequest()
      var directory = "../../assets/characters/" + data.pack
      request.open("GET", Qt.resolvedUrl(directory + "/character.json"), false)
      request.send()
      arcade.guidePack = {
        manifest: JSON.parse(request.responseText),
        assetUrl: Qt.resolvedUrl(directory).toString()
      }
      var sprite = object("arcadeGuide")
      tryCompare(sprite, "errorMessage", "")
      var portrait = object("arcadeGuidePortrait")
      tryVerify(function() { return portrait.width >= 96 && portrait.height >= 84 && sprite.scale >= 0.42 })
      compare(sprite.width, 224)
      compare(sprite.height, 192)
      compare(sprite.previewFrame, 0)
      verify(!sprite.animated)
      verify(!sprite.animationActive)
      wait(100)
      compare(sprite.currentFrame, 0)
      start("rescue")
      wait(1)
      compare(findChild(arcade, "arcadeGuide"), null)
    }
    function test_numberKeysLaunchEachVisualMode() {
      var modes = ["sprint", "rescue", "keyfall"]
      for (var i = 0; i < modes.length; i++) {
        arcade.handleControlKey(String(i + 1))
        compare(arcade.screen, modes[i])
        compare(arcade.mode, modes[i])
        verify(arcade.running)
        compare(arcade.elapsedMs, 0)
        arcade.openHub()
      }
    }
    function test_hubSelectionStartsRoundDirectly() {
      arcade.startGame("sprint")
      compare(arcade.screen, "sprint")
      verify(arcade.running)
      compare(arcade.elapsedMs, 0)
      compare(arcade.answeredCount, 0)
      compare(resultSpy.count, 0)
      stepClock(1000)
      verify(arcade.elapsedMs >= 1000)
    }
    function test_hintAdvancesWithoutPoints() {
      start("sprint")
      var beforeHint = clearSpy.count
      arcade.showHint()
      compare(clearSpy.count, beforeHint + 1)
      verify(arcade.hinted)
      verify(arcade.hintVisible)
      verify(!arcade.competitive)
      var visibleHintTime = arcade.elapsedMs
      wait(120)
      verify(arcade.elapsedMs > visibleHintTime)
      arcade.showHint()
      verify(arcade.hinted)
      verify(!arcade.hintVisible)
      verify(!arcade.competitive)
      verify(arcade.feedback.indexOf("remains practice") >= 0)
      var hiddenHintTime = arcade.elapsedMs
      wait(120)
      verify(arcade.elapsedMs > hiddenHintTime)
      arcade.showHint()
      verify(arcade.hintVisible)
      answerCurrent()
      compare(arcade.challengeIndex, 1)
      compare(arcade.score, 0)
      compare(arcade.cleanAnswers, 0)
      compare(arcade.mastery.practiced, 1)
      compare(arcade.mastery.independent, 0)
      compare(arcade.mastery.mastered, 0)
      compare(resultSpy.count, 1)
    }
    function test_wrongChordDoesNotBreakRunOrSubtract() {
      start("sprint")
      answerCurrent()
      var before = arcade.score
      compare(arcade.streak, 1)
      arcade.handleKeyPress("X", ["SUPER", "X"])
      compare(arcade.challengeIndex, 1)
      compare(arcade.score, before)
      compare(arcade.streak, 0)
      compare(arcade.wrongAttempts, 1)
      verify(arcade.feedback.indexOf("No points lost") >= 0)
      answerCurrent()
      verify(arcade.score >= before)
      compare(arcade.cleanAnswers, 1)
      compare(arcade.streak, 0)
      compare(arcade.bestRunStreak, 1)
      compare(arcade.weakRunIds.length, 1)
    }
    function test_scoreBurstIsProminentInEveryGame_data() {
      return [
        { tag: "Sprint", mode: "sprint" },
        { tag: "Rescue", mode: "rescue" },
        { tag: "Keyfall", mode: "keyfall" }
      ]
    }
    function test_scoreBurstIsProminentInEveryGame(data) {
      start(data.mode)
      answerCurrent(false)
      var burst = object("arcadeScoreBurst")
      var label = object("arcadeScoreBurstLabel")
      tryVerify(function() { return burst.opacity > 0 }, 300)
      verify(label.text.indexOf("+" + arcade.lastAwardedPoints + " POINTS") === 0)
      verify(label.font.pixelSize >= 22 * arcade.fontScale)
      verify(burst.width >= label.implicitWidth + 40 * arcade.textScale)
    }
    function test_reducedMotionKeepsScoreBurstStationary() {
      arcade.reducedMotion = true
      start("sprint")
      answerCurrent(false)
      var burst = object("arcadeScoreBurst")
      tryVerify(function() { return burst.opacity > 0 }, 200)
      verify(!burst.motionEnabled)
      compare(burst.scale, 1)
      compare(burst.burstLift, 0)
    }
    function test_scoreBurstAnimatesWhenMotionIsEnabled() {
      arcade.reducedMotion = false
      start("sprint")
      answerCurrent(false)
      var burst = object("arcadeScoreBurst")
      tryVerify(function() { return burst.animationRunning }, 200)
      verify(burst.motionEnabled)
    }
    function test_scoreBurstDoesNotLeakIntoTheNextGame() {
      start("sprint")
      answerCurrent(false)
      var burst = object("arcadeScoreBurst")
      tryVerify(function() { return burst.opacity > 0 }, 200)
      arcade.startGame("keyfall")
      compare(arcade.screen, "keyfall")
      compare(burst.opacity, 0)
      verify(!burst.animationRunning)
    }
    function test_rescueCompletesSixTasks() {
      start("rescue")
      var flight = object("arcadeRescueFlight")
      var actions = ["launch-terminal", "float", "widen", "fullscreen", "send-workspace-2", "workspace-2"]
      for (var i = 0; i < 6; i++) {
        compare(arcade.currentChallenge.action, actions[i])
        answerCurrent(false)
        compare(arcade.rescueCompleted, i + 1)
        compare(flight.completedActions, i + 1)
        verify(arcade.responsePending)
        compare(arcade.challengeIndex, i)
        if (i === 5) {
          verify(flight.arrivalReached)
          compare(arcade.responseDwellMs, 1200)
        }
        finishResponse()
      }
      compare(arcade.screen, "complete")
      compare(object("arcadeRoundCompleteTitle").text, "Destination reached")
      compare(object("arcadeRoundCompleteDetail").text, arcade.rescueMission.success)
      var arrival = object("arcadeRescueArrival")
      verify(arrival.arrivalReached)
      compare(arrival.destination, arcade.rescueMission.destination)
      compare(arcade.currentPage.controls.length, 1)
      compare(arcade.finalClean, 6)
      compare(arcade.resultTitle, "Perfect recall")
      compare(resultSpy.count, 7)
      compare(Logic.bestForDeck(arcade.workingStats, arcade.runDeckKey).plays, 1)
      showResults()
    }
    function test_rescueFlightAdvancesForScoredAndGuidedPractice() {
      start("rescue")
      var flight = object("arcadeRescueFlight")
      var ship = findChild(flight, "rescueShip")
      compare(findChild(flight, "rescueShipImage").status, Image.Ready)
      compare(findChild(flight, "rescuePlanetImage").status, Image.Ready)
      verify(String(arcade.arcadeAssetUrl("rescue-ship.png")).indexOf("assets/arcade/rescue-ship.png") >= 0)
      compare(flight.callsign, arcade.rescueMission.callsign)
      compare(flight.destination, arcade.rescueMission.destination)
      compare(flight.completedActions, 0)
      compare(flight.shipProgress, 0)
      verify(!flight.arrivalReached)
      var startX = ship.x

      arcade.handleKeyPress("X", ["SUPER", "X"])
      compare(flight.completedActions, 0)
      compare(flight.shipProgress, 0)
      fuzzyCompare(ship.x, startX, 1)

      answerCurrent(false)
      compare(flight.completedActions, 1)
      compare(flight.shipProgress, 1 / 6)
      compare(flight.burstText, "+" + arcade.lastAwardedPoints)
      verify(arcade.lastAwardedPoints > 0)
      verify(arcade.lastRescueReaction.length > 0)
      verify(arcade.feedback.indexOf(arcade.guideName + ":") === 0)
      tryVerify(function() { return ship.x > startX }, 800)
      finishResponse()

      arcade.showHint()
      answerCurrent(false)
      compare(flight.completedActions, 2)
      compare(arcade.lastAwardedPoints, 0)
      compare(flight.burstText, "PRACTICE")
      verify(arcade.feedback.indexOf("Practice logged") >= 0)
    }
    function test_rescueAutomaticallyAdvancesWithoutKeyReleaseOrContinue() {
      start("rescue")
      for (var i = 0; i < 6; i++) {
        arcade.pressedKeys = arcade.expectedKeys.slice()
        answerCurrent(false)
        compare(arcade.answeredCount, i + 1)
        verify(arcade.responsePending)
        tryVerify(function() { return !arcade.responsePending }, 1500)
      }
      compare(arcade.screen, "complete")
      compare(arcade.finalClean, 6)
    }
    function test_rescueDesktopSemantics() {
      start("rescue")
      var scene = object("arcadeRescueScene")
      verify(!scene.terminalVisible)
      answerCurrent()
      verify(scene.terminalVisible)
      verify(!scene.floating)
      var terminal = object("rescueTerminal")
      answerCurrent()
      verify(scene.floating)
      var floatWidth = terminal.width
      answerCurrent()
      verify(terminal.width > floatWidth)
      answerCurrent()
      verify(scene.fullscreen)
      answerCurrent(false)
      compare(scene.activeWorkspace, 2)
      verify(scene.terminalVisible)
      verify(scene.desktopState.indexOf("followed") >= 0)
      finishResponse()
      compare(scene.terminalWorkspace, 2)
      compare(scene.activeWorkspace, 1)
      verify(!scene.terminalVisible)
      verify(scene.desktopState.indexOf("Mission setup") >= 0)
      answerCurrent(false)
      compare(scene.activeWorkspace, 2)
      verify(scene.terminalVisible)
    }
    function test_rescueUnavailableExplainsRatherThanRandomDeck() {
      host.testCourse = { lessons: [host.fixture.lessons[0]] }
      arcade.startGame("rescue")
      compare(arcade.screen, "hub")
      verify(arcade.feedback.indexOf("complete simulated rescue mission") >= 0)
    }
    function test_allRescueMissionsRenderDistinctSafeWalkthroughs() {
      var request = new XMLHttpRequest()
      request.open("GET", Qt.resolvedUrl("../../courses/omarchy-basics.json"), false)
      request.send()
      var fullCourse = JSON.parse(request.responseText)
      var fullChallenges = Logic.buildChallenges(fullCourse)
      var missions = Logic.rescueMissions(fullChallenges)
      var visibleCounts = {
        "terminal-workspace": [1, 1, 1, 1, 1, 1],
        "layout-triage": [1, 2, 2, 2, 2, 1],
        "workspace-sort": [1, 1, 0, 1, 1, 1],
        "scratchpad-recovery": [1, 0, 1, 2, 1, 0],
        "file-window-shaping": [1, 2, 2, 2, 2, 2],
        "browser-workspace-recovery": [1, 1, 0, 1, 1, 0]
      }
      var workspaces = {
        "terminal-workspace": [1, 1, 1, 1, 2, 2],
        "layout-triage": [1, 1, 1, 1, 1, 1],
        "workspace-sort": [1, 2, 1, 1, 2, 1],
        "scratchpad-recovery": [1, 1, 1, 1, 1, 1],
        "file-window-shaping": [1, 1, 1, 1, 1, 1],
        "browser-workspace-recovery": [1, 1, 2, 2, 1, 1]
      }
      compare(missions.length, 6)

      for (var mission of missions) {
        var missionDeck = mission.steps.map(function(step) { return step.challenge })
        arcade.prepareGame("rescue", missionDeck, false, "standard", mission)
        compare(arcade.rescueMission.id, mission.id)
        compare(arcade.currentPrompt, mission.steps[0].prompt)
        compare(arcade.screen, "rescue")
        var scene = object("arcadeRescueScene")

        for (var i = 0; i < mission.steps.length; i++) {
          compare(arcade.currentChallenge.action, mission.steps[i].action)
          compare(arcade.currentPrompt, mission.steps[i].prompt)
          answerCurrent(false)
          compare(scene.desktopState, mission.steps[i].label)
          compare(scene.visibleWindowCount, visibleCounts[mission.id][i])
          compare(scene.activeWorkspace, workspaces[mission.id][i])
          if (mission.id === "scratchpad-recovery" && i === 3)
            verify(object("rescueTerminal").z > object("rescueWindow-browser-1").z)
          if (mission.id === "file-window-shaping" && i === 4)
            verify(object("rescueWindow-files-0").z > object("rescueTerminal").z)
          finishResponse()
        }

        compare(arcade.screen, "complete")
        compare(object("arcadeRoundCompleteDetail").text, mission.success)
        arcade.openHub()
      }

      host.testCourse = fullCourse
      var previousMission = ""
      for (var run = 0; run < 8; run++) {
        arcade.startGame("rescue")
        verify(arcade.rescueMission.id !== previousMission)
        previousMission = arcade.rescueMission.id
        arcade.openHub()
      }
    }
    function test_keyfallTurnsDeadlineIntoHint() {
      start("keyfall")
      stepClock(arcade.arrivalDwellMs + arcade.fallDurationMs + 20)
      verify(arcade.hinted)
      verify(arcade.hintVisible)
      compare(arcade.challengeIndex, 0)
      compare(arcade.score, 0)
      verify(!arcade.competitive)
      compare(arcade.assistanceReason, "timeout")
      verify(arcade.feedback.indexOf("Time to practice") >= 0)
      arcade.showHint()
      verify(!arcade.hintVisible)
      compare(arcade.keyfallProgress, 1)
      arcade.showHint()
      verify(arcade.hintVisible)
    }
    function test_keyfallHintUsesPracticeBayWithoutMissEffect() {
      start("keyfall")
      var field = object("arcadeKeyfallField")
      var card = object("arcadePromptCard")
      arcade.showHint()
      verify(arcade.hinted)
      compare(arcade.wrongAttempts, 0)
      compare(field.recalledCount, 0)
      compare(field.practiceCount, 1)
      compare(object("arcadeKeyfallPhase").text, "LEARNING ASSIST ACTIVE")
      verify(!card.keyfallMissAnimating)
      verify(arcade.feedback.indexOf("Hint opened in Practice") >= 0)
    }
    function test_keyfallMissRebuildsInPracticeAndReturnsLater() {
      arcade.reducedMotion = false
      start("keyfall")
      var field = object("arcadeKeyfallField")
      var card = object("arcadePromptCard")
      arcade.handleKeyPress("X", ["SUPER", "X"])
      verify(arcade.hinted)
      compare(arcade.wrongAttempts, 1)
      compare(field.recalledCount, 0)
      compare(field.practiceCount, 1)
      compare(object("arcadeKeyfallPhase").text, "SIGNAL MISSED · PRACTICE MODE")
      verify(card.keyfallMissAnimating)
      verify(arcade.feedback.indexOf("Signal missed") >= 0)
      tryVerify(function() { return card.keyfallMissOpacity < 1 }, 200)
      tryVerify(function() { return !card.keyfallMissAnimating }, 600)
      fuzzyCompare(card.y, card.dockY, 2)
      answerCurrent(false)
      verify(arcade.feedback.indexOf("Recovered after a miss") >= 0)
      verify(arcade.queue.length > arcade.deck.length)
      finishResponse()
    }
    function test_keyfallCorrectAnswerLightsRecalledBay() {
      start("keyfall")
      var field = object("arcadeKeyfallField")
      answerCurrent(false)
      compare(field.recalledCount, 1)
      compare(field.practiceCount, 0)
      compare(object("arcadeKeyfallRecalledBay").border.width, 2)
      compare(object("arcadeKeyfallPracticeBay").border.width, 1)
    }
    function test_keyfallArrivalAndPace() {
      arcade.selectedPace = "relaxed"
      start("keyfall")
      compare(arcade.runPace, "relaxed")
      compare(arcade.deck.length, 12)
      stepClock(1000)
      compare(arcade.keyfallProgress, 0)
      stepClock(2000)
      verify(arcade.keyfallProgress > 0 && arcade.keyfallProgress < 0.3)
      verify(!arcade.hinted)
    }
    function test_keyfallSpacedRetryRegainsFreshRecall() {
      start("keyfall")
      var original = arcade.currentChallenge
      arcade.handleKeyPress("X", ["SUPER", "X"])
      verify(arcade.hinted)
      answerCurrent()
      var ids = []
      for (var i = 0; i < 5 && !arcade.isRetry; i++) {
        if (ids.indexOf(arcade.currentChallenge.id) < 0) ids.push(arcade.currentChallenge.id)
        answerCurrent()
      }
      verify(arcade.isRetry)
      compare(arcade.currentChallenge.id, original.id)
      verify(ids.length >= 2)
      compare(arcade.regainedRecall, 0)
      verify(!arcade.hinted)
      compare(arcade.wrongAttempts, 0)
      answerCurrent()
      compare(arcade.regainedRecall, 1)
      var history = arcade.workingStats.skills[original.signature]
      compare(history.assisted, 1)
      compare(history.firstTry, 1)
      compare(arcade.mastery.mastered, 0)
    }
    function test_keyfallSmallTopicStillSchedulesASpacedRetry() {
      var request = new XMLHttpRequest()
      request.open("GET", Qt.resolvedUrl("../../courses/omarchy-basics.json"), false)
      request.send()
      host.testCourse = JSON.parse(request.responseText)
      wait(1)
      arcade.selectedCategory = "capture"
      start("keyfall")
      var deckIds = []
      for (var deckItem of arcade.deck)
        if (deckIds.indexOf(deckItem.id) < 0) deckIds.push(deckItem.id)
      compare(deckIds.length, 2)
      var original = arcade.currentChallenge
      arcade.showHint()
      answerCurrent()
      var intervening = 0
      while (arcade.running && !arcade.isRetry && intervening < 4) {
        answerCurrent()
        intervening++
      }
      verify(arcade.isRetry)
      compare(arcade.currentChallenge.id, original.id)
      verify(intervening >= 2)
      answerCurrent()
      compare(arcade.regainedRecall, 1)
    }
    function test_keyfallAllAssistedIsBoundedAndNeverMastery() {
      start("keyfall")
      var attempts = 0
      while (arcade.running && attempts < 30) {
        arcade.showHint()
        answerCurrent()
        attempts++
      }
      compare(arcade.screen, "complete")
      compare(object("arcadeRoundCompleteTitle").text, "Round complete")
      verify(attempts <= 18)
      compare(arcade.finalClean, 0)
      compare(arcade.score, 0)
      compare(arcade.regainedRecall, 0)
      compare(arcade.mastery.mastered, 0)
      compare(Logic.bestForDeck(arcade.workingStats, arcade.runDeckKey).plays, 0)
    }
    function test_pauseResumeFreezesClockAndPreservesPrompt() {
      start("keyfall")
      stepClock(1500)
      var challenge = arcade.currentChallenge.id
      arcade.handleControlKey("P")
      compare(arcade.screen, "paused")
      verify(!arcade.running)
      verify(!arcade.competitive)
      var elapsed = arcade.elapsedMs
      wait(150)
      compare(arcade.elapsedMs, elapsed)
      arcade.handleControlKey("RETURN")
      compare(arcade.screen, "keyfall")
      compare(arcade.currentChallenge.id, challenge)
    }
    function test_sprintCannotPauseAndHintsDoNotStopTheTimer() {
      start("sprint")
      stepClock(1500)
      var beforePause = arcade.elapsedMs
      arcade.handleControlKey("P")
      compare(arcade.screen, "sprint")
      verify(arcade.running)
      stepClock(500)
      verify(arcade.elapsedMs >= beforePause + 500)
      arcade.showHint()
      verify(arcade.hinted)
      compare(object("arcadePromptEyebrow").text, "LEARN ZONE · TIMER RUNNING")
      var beforeHint = arcade.elapsedMs
      stepClock(600)
      verify(arcade.elapsedMs >= beforeHint + 600)
      verify(arcade.feedback.indexOf("timer keeps running") >= 0)
      verify(object("arcadeSafetyLine").text.indexOf("timer keeps running") >= 0)
      compare(object("arcadeSafetyLine").text.indexOf("P pause"), -1)
      arcade.pauseGame(true)
      compare(arcade.screen, "paused")
      arcade.handleControlKey("RETURN")
      compare(arcade.screen, "sprint")
    }
    function test_hostInactivePausesAndReopenDoesNotReset() {
      start("rescue")
      answerCurrent()
      var index = arcade.challengeIndex
      arcade.active = false
      compare(arcade.screen, "paused")
      var elapsed = arcade.elapsedMs
      wait(100)
      arcade.active = true
      compare(arcade.screen, "paused")
      compare(arcade.challengeIndex, index)
      compare(arcade.elapsedMs, elapsed)
      arcade.resumeGame()
      compare(arcade.screen, "rescue")
      arcade.openHub()
      arcade.active = false
      arcade.active = true
      compare(arcade.screen, "hub")
    }
    function test_abandoningActiveRunKeepsSkillProgressWithoutRunRecord() {
      start("sprint")
      var signature = arcade.currentChallenge.signature
      answerCurrent()
      compare(arcade.workingStats.skills[signature].attempts, 1)
      arcade.handleEscape()
      compare(arcade.screen, "hub")
      compare(arcade.mastery.practiced, 1)
      compare(arcade.workingStats.sprint.plays, 0)
      compare(Logic.bestForDeck(arcade.workingStats, arcade.runDeckKey).plays, 0)
      compare(resultSpy.count, 1)
    }
    function test_pausedQuitKeepsAnsweredSkillProgress() {
      start("keyfall")
      answerCurrent()
      arcade.pauseGame()
      arcade.handleControlKey("DOWN")
      arcade.handleControlKey("RETURN")
      compare(arcade.screen, "hub")
      compare(arcade.mastery.practiced, 1)
      compare(arcade.workingStats.keyfall.plays, 0)
      compare(resultSpy.count, 1)
    }
    function test_escapeFromGameResultsAndHub() {
      arcade.startGame("sprint")
      arcade.handleEscape()
      compare(arcade.screen, "hub")
      start("sprint")
      stepClock(60001)
      compare(arcade.screen, "complete")
      compare(arcade.finalElapsedMs, 60000)
      compare(object("arcadeRoundCompleteTitle").text, "Time's up")
      verify(!object("arcadeResultsPageLoader").visible)
      showResults()
      arcade.handleEscape()
      compare(arcade.screen, "hub")
      arcade.handleEscape()
      compare(closeSpy.count, 1)
    }
    function test_realButtonsAndArrowNavigationDoNotUseAnswerLetters() {
      verify(arcade.selectedControl instanceof Button)
      verify(arcade.selectedControl.Accessible.name.length > 0)
      arcade.handleControlKey("RIGHT")
      compare(arcade.navigationIndex, 1)
      verify(!object("arcadeModeCard-rescue").selectionHighlighted)
      verify(object("arcadeModeCard-sprint").selectionHighlighted)
      verify(!object("arcadeModeCard-keyfall").selectionHighlighted)
      verify(arcade.selectedControl.activeFocus)
      verify(findChild(arcade.selectedControl, "arcadeFocusRing").visible)
      arcade.handleControlKey("W")
      compare(arcade.screen, "hub")
      arcade.handleControlKey("RETURN")
      compare(arcade.mode, "sprint")
      compare(arcade.screen, "sprint")
      arcade.handleControlKey("H")
      compare(arcade.screen, "sprint")
      verify(arcade.hinted)
    }
    function test_hoveringModeCardSelectsAndHighlightsWholeCard() {
      var keyfallCard = object("arcadeModeCard-keyfall")
      tryVerify(function() { return keyfallCard.width > 100 && keyfallCard.height > 100 }, 1000)
      mouseMove(host, 1, 1)
      wait(20)
      mouseMove(keyfallCard, keyfallCard.width / 2, keyfallCard.height / 2)
      tryCompare(arcade.selectedControl, "objectName", "arcadePlay-keyfall")
      verify(keyfallCard.selectionHighlighted)
      compare(keyfallCard.border.width, 3)
      verify(!object("arcadeModeCard-rescue").selectionHighlighted)
      arcade.handleControlKey("LEFT")
      compare(arcade.selectedControl.objectName, "arcadePlay-sprint")
      verify(object("arcadeModeCard-sprint").selectionHighlighted)
      mouseMove(host, 1, 1)
    }
    function test_successDwellSurvivesReducedMotionAndIgnoresRepeatedAnswer() {
      start("rescue")
      answerCurrent(false)
      compare(arcade.answeredCount, 1)
      var saved = resultSpy.count
      wait(200)
      verify(arcade.responsePending)
      verify(arcade.feedback.indexOf(arcade.guideName + ":") === 0)
      verify(arcade.feedback.indexOf("points") >= 0)
      answerCurrent(false)
      compare(arcade.answeredCount, 1)
      compare(resultSpy.count, saved)
      verify(clearSpy.count >= 2)
    }
    function test_focusedControlForwardsRealChordBeforeButtonActivation() {
      start("rescue")
      var close = object("arcadeCloseButton")
      close.forceActiveFocus(Qt.TabFocusReason)
      verify(close.activeFocus)
      keyClick(Qt.Key_Return, Qt.MetaModifier)
      compare(arcade.screen, "rescue")
      compare(arcade.answeredCount, 1)
      verify(!arcade.hinted)
    }
    function test_bareCustomAnswerKeysBypassFocusedButtons_data() {
      return [
        { tag: "Return", name: "RETURN", key: Qt.Key_Return },
        { tag: "Space", name: "SPACE", key: Qt.Key_Space },
        { tag: "Tab", name: "TAB", key: Qt.Key_Tab },
        { tag: "R", name: "R", key: Qt.Key_R }
      ]
    }
    function test_bareCustomAnswerKeysBypassFocusedButtons(data) {
      host.testCourse = { lessons: [{ id: "custom", steps: [
        { id: "custom-answer", instruction: "A custom shortcut", keys: [data.name] }
      ] }] }
      start("sprint")
      object("arcadeCloseButton").forceActiveFocus(Qt.TabFocusReason)
      keyClick(data.key)
      compare(arcade.screen, "sprint")
      compare(arcade.answeredCount, 1)
      compare(arcade.cleanAnswers, 1)
      verify(!arcade.hinted)
    }
    function test_nativeTabAndEnterUseTheSameNavigation() {
      arcade.selectedControl.forceActiveFocus(Qt.TabFocusReason)
      keyClick(Qt.Key_Tab)
      compare(arcade.navigationIndex, 1)
      keyClick(Qt.Key_Return)
      compare(arcade.screen, "sprint")
      compare(arcade.mode, "sprint")
    }
    function test_pauseAlsoFreezesSuccessDwell() {
      start("rescue")
      answerCurrent(false)
      arcade.pauseGame()
      var remaining = arcade.responseRemainingMs
      wait(120)
      compare(arcade.responseRemainingMs, remaining)
      compare(arcade.challengeIndex, 0)
      arcade.resumeGame()
      finishResponse()
      compare(arcade.challengeIndex, 1)
    }
    function test_comparableReplayPreservesOrderAndPace() {
      start("sprint")
      var key = arcade.runDeckKey
      var order = deckSignatures()
      stepClock(2000)
      answerCurrent()
      stepClock(2000)
      answerCurrent()
      stepClock(60000)
      compare(arcade.screen, "complete")
      var record = Logic.bestForDeck(arcade.workingStats, key)
      compare(record.plays, 1)
      compare(record.splits.length, 2)
      arcade.selectedPace = "fast"
      arcade.raceDeck()
      compare(arcade.screen, "sprint")
      compare(arcade.runDeckKey, key)
      compare(deckSignatures(), order)
      compare(arcade.runPace, "standard")
      stepClock(3000)
      verify(arcade.paceLabel.indexOf("pace") >= 0)
      verify(arcade.previousBest.plays === 1)
    }
    function test_hintedReplayCannotReplaceComparableRecord() {
      start("sprint")
      answerCurrent()
      stepClock(60000)
      var key = arcade.runDeckKey
      var before = JSON.stringify(Logic.bestForDeck(arcade.workingStats, key))
      arcade.raceDeck()
      arcade.showHint()
      answerCurrent()
      stepClock(60000)
      compare(arcade.screen, "complete")
      compare(JSON.stringify(Logic.bestForDeck(arcade.workingStats, key)), before)
    }
    function test_keyfallReplayKeepsPaceAndUnmodifiedInitialDeck() {
      arcade.selectedPace = "fast"
      start("keyfall")
      var key = arcade.runDeckKey
      var order = deckSignatures()
      arcade.showHint()
      while (arcade.running) answerCurrent()
      arcade.selectedPace = "relaxed"
      arcade.raceDeck()
      compare(arcade.runPace, "fast")
      compare(arcade.runDeckKey, key)
      compare(deckSignatures(), order)
      compare(arcade.queue.length, 12)
      verify(arcade.competitive)
    }
    function test_modifiedHintLetterIsAnAnswerNotAControl() {
      host.testCourse = { lessons: [{ id: "custom", steps: [
        { id: "custom-h", instruction: "A custom action", keys: ["SUPER", "H"] }
      ] }] }
      start("sprint")
      arcade.handleKeyPress("H", ["SUPER", "H"])
      compare(arcade.answeredCount, 1)
      verify(!arcade.hinted)
      verify(arcade.competitive)
    }
    function test_targetedReplayOnlySelectedSkillsAndSeparateRecords() {
      start("sprint")
      arcade.showHint()
      var weakId = arcade.currentChallenge.id
      answerCurrent()
      stepClock(60000)
      arcade.practiceThose(arcade.weakRunIds, arcade.mode)
      compare(arcade.screen, "sprint")
      verify(arcade.targeted)
      verify(!arcade.competitive)
      compare(arcade.deck.length, 1)
      compare(arcade.deck[0].id, weakId)
      answerCurrent()
      stepClock(60000)
      compare(arcade.screen, "complete")
      compare(Logic.bestForDeck(arcade.workingStats, arcade.runDeckKey).plays, 0)
    }
    function test_rescuePracticeStaysInTheSameMission() {
      start("rescue")
      var missionId = arcade.rescueMission.id
      var missionDeck = deckSignatures()
      arcade.practiceThose([arcade.deck[0].id], arcade.mode)
      compare(arcade.screen, "rescue")
      compare(arcade.rescueMission.id, missionId)
      compare(deckSignatures(), missionDeck)
      compare(arcade.deck.length, 6)
      verify(arcade.targeted)
      verify(!arcade.competitive)
    }
    function test_resultsPracticeCountUsesSingularAndPluralLabels() {
      arcade.mode = "sprint"
      arcade.answeredCount = 1
      arcade.finalClean = 1
      arcade.weakRunIds = [arcade.challenges[0].id]
      arcade.screen = "results"
      wait(10)
      compare(object("arcadePracticeWeakButton").text, "Practice 1 shortcut")
      verify(object("arcadeResultTotalsLine").text.indexOf("1 of 1 on the first try") >= 0)
      compare(arcade.currentPage.controls.length, 3)
      verify(!object("arcadeFreshButton").visible)
      arcade.answeredCount = 2
      arcade.weakRunIds = [arcade.challenges[0].id, arcade.challenges[1].id]
      compare(object("arcadePracticeWeakButton").text, "Practice 2 shortcuts")
      verify(object("arcadeResultTotalsLine").text.indexOf("1 of 2 on the first try") >= 0)
      arcade.weakRunIds = []
      compare(arcade.currentPage.controls.length, 3)
      verify(object("arcadeFreshButton").visible)
    }
    function test_rescueResultsKeepOnlyRelevantMissionDetails() {
      start("rescue")
      arcade.finalScore = 510
      arcade.finalClean = 6
      arcade.answeredCount = 6
      arcade.finalElapsedMs = 45000
      arcade.weakRunIds = [arcade.challenges[0].id]
      arcade.screen = "results"
      wait(10)
      compare(object("arcadeResultTotalsLine").text, "6 of 6 actions on the first try")
      compare(object("arcadeResultTotalsLine").text.indexOf("active"), -1)
      verify(!object("arcadeRecordContext").visible)
      verify(!object("arcadePracticeSummary").visible)
      verify(!object("arcadeSafetyLine").visible)
      verify(!object("arcadeNavigationHint").visible)
      verify(!object("arcadeGuidePortrait").visible)
      compare(object("arcadePracticeWeakButton").text, "Practice this mission")
      compare(arcade.currentPage.controls.length, 3)
      arcade.finalClean = 5
      arcade.finalScore = 420
      wait(10)
      compare(object("arcadeResultTotalsLine").text, "5 of 6 actions on the first try")
      verify(object("arcadeResultTotalsLine").width >= object("arcadeResultTotalsLine").contentWidth - 1)
      verify(object("arcadeResultTotalsLine").height >= object("arcadeResultTotalsLine").contentHeight - 1)
    }
    function test_reducedMotionKeepsKeyfallPromptStationary() {
      start("keyfall")
      var card = object("arcadePromptCard")
      var y = card.y
      stepClock(4000)
      verify(arcade.keyfallProgress > 0)
      compare(card.y, y)
      arcade.showHint()
      compare(card.y, y)
    }
    function test_rescuePromptGetsBriefOneTimeEmphasis() {
      arcade.reducedMotion = false
      start("rescue")
      var card = object("arcadePromptCard")
      var cue = object("arcadePromptEmphasis")
      card.emphasize()
      tryVerify(function() { return card.emphasisRunning }, 200)
      verify(card.promptOpacity < 1)
      verify(card.promptOffset > 0)
      verify(cue.opacity > 0)
      tryVerify(function() { return !card.emphasisRunning }, 1000)
      compare(card.promptOpacity, 1)
      compare(card.promptOffset, 0)
      compare(cue.opacity, 0)

      var firstPrompt = arcade.currentPrompt
      answerCurrent()
      finishResponse()
      verify(arcade.currentPrompt !== firstPrompt)
      tryVerify(function() { return card.emphasisRunning }, 200)
    }
    function test_rescuePromptBreathesUntilTheLearnerInteracts() {
      arcade.reducedMotion = false
      start("rescue")
      var card = object("arcadePromptCard")
      var attention = object("arcadePromptAttention")
      var prompt = object("arcadePrompt")
      verify(card.attentionActive)
      verify(card.attentionRunning)
      verify(attention.opacity >= 0.12 && attention.opacity <= 0.38)
      verify(card.eyebrow.indexOf("NEXT ACTION") === 0)
      wait(500)
      verify(card.attentionTint > 0.32)
      verify(prompt.color !== arcade.foregroundColor)

      arcade.handleKeyPress("X", ["SUPER", "X"])
      verify(arcade.challengeEngaged)
      verify(!card.attentionActive)
      verify(!card.attentionRunning)
      compare(attention.opacity, 0)
      compare(prompt.color, arcade.foregroundColor)
      verify(object("arcadeRescueScene").ghostRequested)
    }
    function test_rescueLaunchGhostBecomesTheSimulatedApp() {
      var request = new XMLHttpRequest()
      request.open("GET", Qt.resolvedUrl("../../courses/omarchy-basics.json"), false)
      request.send()
      var fullCourse = JSON.parse(request.responseText)
      var fullChallenges = Logic.buildChallenges(fullCourse)
      var missions = Logic.rescueMissions(fullChallenges)
      var mission = missions[1]
      arcade.prepareGame("rescue", mission.steps.map(function(step) { return step.challenge }),
        false, "standard", mission)
      var scene = object("arcadeRescueScene")
      var ghost = object("rescueGhostWindow")
      compare(scene.ghostKind, "terminal")
      verify(scene.ghostRequested)
      compare(scene.visibleWindowCount, 0)
      compare(ghost.opacity, 0.52)

      answerCurrent(false)
      verify(!scene.ghostRequested)
      compare(scene.visibleWindowCount, 1)
      verify(scene.windowForKind("terminal") !== null)
      compare(ghost.opacity, 0)

      finishResponse()
      compare(scene.ghostKind, "browser")
      verify(scene.ghostRequested)
      compare(scene.ghostGeometry.x, 0.51)
      compare(scene.ghostGeometry.width, 0.47)
    }
    function test_rescueBrowserHasRecognizableResponsiveChrome() {
      host.width = 1920
      host.height = 1000
      wait(30)
      var request = new XMLHttpRequest()
      request.open("GET", Qt.resolvedUrl("../../courses/omarchy-basics.json"), false)
      request.send()
      var challenges = Logic.buildChallenges(JSON.parse(request.responseText))
      var mission = Logic.rescueMissions(challenges)[1]
      arcade.prepareGame("rescue", mission.steps.map(function(step) { return step.challenge }),
        false, "standard", mission)
      answerCurrent(false)
      finishResponse()
      answerCurrent(false)

      var toolbar = object("rescueBrowserToolbar")
      var address = object("rescueBrowserAddress")
      var page = object("rescueBrowserPage")
      var preview = object("rescueBrowserPreview")
      tryVerify(function() { return !page.compact }, 1000)
      verify(toolbar.visible)
      verify(address.visible)
      verify(page.visible)
      verify(preview.visible)
      verify(address.width > 100)
      tryVerify(function() { return page.height > 100 }, 1000)
      verify(preview.width > 100)

      host.width = 800
      tryVerify(function() { return page.compact }, 1000)
      verify(toolbar.visible)
      verify(page.visible)
      verify(!preview.visible)
      verify(page.width > 200)
    }
    function test_reducedMotionKeepsRescuePromptStatic() {
      start("rescue")
      wait(20)
      var card = object("arcadePromptCard")
      verify(!card.emphasisRunning)
      compare(card.promptOpacity, 1)
      compare(card.promptOffset, 0)
      compare(object("arcadePromptEmphasis").opacity, 0)
      verify(card.attentionActive)
      verify(!card.attentionRunning)
      compare(object("arcadePromptAttention").opacity, 0.28)
      verify(object("arcadePrompt").color !== arcade.foregroundColor)
      var flight = object("arcadeRescueFlight")
      var ship = findChild(flight, "rescueShip")
      verify(!flight.motionEnabled)
      answerCurrent(false)
      fuzzyCompare(ship.x, flight.shipX - ship.width / 2, 1)
    }
    function test_answerKeysOnlyAppearAfterHint() {
      start("rescue")
      var hintKeys = object("arcadeHintKeys")
      var hintDetail = object("arcadeHintDetail")
      verify(!hintKeys.visible)
      arcade.pressedKeys = ["SUPER"]
      arcade.pressedKeys = ["SUPER", "RETURN"]
      verify(!hintKeys.visible)
      arcade.showHint()
      verify(hintKeys.visible)
      compare(hintDetail.horizontalAlignment, Text.AlignHCenter)
      fuzzyCompare(hintKeys.x + hintKeys.width / 2, hintKeys.parent.width / 2, 1)
      compare(hintKeys.keys.join("+"), "SUPER+RETURN")
      compare(arcade.expectedKeys.join("+"), "SUPER+RETURN")
    }
    function test_responsiveReadingCards_data() {
      return [
        { tag: "compact-large-text", width: 800, height: 600, scale: 1.3, light: false },
        { tag: "laptop-large-text", width: 1024, height: 640, scale: 1.25, light: false },
        { tag: "desktop", width: 1280, height: 820, scale: 1, light: false },
        { tag: "wide-light", width: 1920, height: 1080, scale: 1, light: true }
      ]
    }
    function test_responsiveReadingCards(data) {
      host.width = data.width
      host.height = data.height
      arcade.textScale = data.scale
      if (data.light) {
        arcade.backgroundColor = "#f7f7fb"
        arcade.foregroundColor = "#182331"
        arcade.mutedColor = "#506070"
      }
      wait(10)
      var scroller = object("arcadeScroll")
      verify(scroller.width > 0 && scroller.height > 0)
      verify(scroller.contentWidth <= scroller.availableWidth + 1)
      if (data.width <= 1024) verify(scroller.contentHeight > scroller.height, "hub scrolls instead of clipping")
      start("keyfall")
      wait(10)
      var card = object("arcadePromptCard")
      var prompt = object("arcadePrompt")
      verify(prompt.width >= Math.min(data.width * 0.45, 720))
      tryVerify(function() { return prompt.height >= prompt.contentHeight - 1 }, 1000)
      tryVerify(function() { return card.height >= prompt.height + 36 }, 1000)
      compare(card.color.a, 1)
      verify(card.width <= scroller.availableWidth + 1)
      arcade.showHint()
      wait(10)
      verify(card.height >= prompt.height + 36)
    }
    function test_topicFilterDoesNotChangeRescueMission() {
      arcade.selectedCategory = "windows"
      arcade.startGame("sprint")
      verify(arcade.deck.every(function(item) { return item.category === "windows" }))
      arcade.openHub()
      arcade.startGame("rescue")
      compare(arcade.deck.length, 6)
      compare(arcade.deck[0].category, "apps")
    }
    function test_pauseExplainsHowToRestoreLostKeyboardCapture() {
      start("keyfall")
      arcade.pauseGame(true)
      arcade.keyboardCaptureAvailable = false
      wait(10)
      compare(object("arcadeNavigationHint").text, "Click Resume to restore keyboard capture")
      verify(object("arcadePauseContent") !== null)
      var resume = object("arcadeResumeButton")
      verify(resume.text.indexOf("restore") >= 0)
    }
    function test_tiedScoreWithFasterTimeHasHonestRecordCopy() {
      arcade.previousBest = { bestScore: 1000, bestClean: 2, bestElapsedMs: 5000, splits: [2000, 5000], plays: 1 }
      arcade.finalScore = 1000
      arcade.competitive = true
      arcade.newBest = false
      arcade.newBestPace = true
      arcade.screen = "results"
      wait(10)
      compare(object("arcadeRecordContext").text, "Matched your best score with a faster pace.")
    }
    function test_activePlayDoesNotMoveWhenARuntimeNoticeArrives() {
      start("keyfall")
      var prompt = object("arcadePromptCard")
      var before = prompt.mapToItem(arcade, 0, 0)
      arcade.storageNotice = "Progress could not be saved."
      wait(10)
      var after = prompt.mapToItem(arcade, 0, 0)
      compare(after.x, before.x)
      compare(after.y, before.y)
      verify(!object("arcadeRuntimeNotice").visible)
      arcade.openHub()
      verify(object("arcadeRuntimeNotice").visible)
    }
    function test_arcadeSurfacePreservesTextContrast() {
      arcade.backgroundColor = "#7a7934"
      arcade.foregroundColor = "#000000"
      arcade.mutedColor = "#000000"
      arcade.urgentColor = "#000000"
      wait(10)
      compare(arcade.surfaceColor.toString(), arcade.backgroundColor.toString())
    }
    function test_desktopModeCardsAlignAndHaveDistinctPreviews() {
      wait(10)
      var sprint = object("arcadeModeCard-sprint")
      var rescue = object("arcadeModeCard-rescue")
      var keyfall = object("arcadeModeCard-keyfall")
      compare(object("arcadeModeGrid").columns, 3)
      compare(sprint.y, rescue.y)
      compare(sprint.y, keyfall.y)
      compare(sprint.height, rescue.height)
      compare(sprint.height, keyfall.height)
      verify(sprint.cardAccent !== rescue.cardAccent)
      verify(rescue.cardAccent !== keyfall.cardAccent)
      var sprintPreview = findChild(sprint, "arcadeModePreview-sprint")
      var rescuePreview = findChild(rescue, "arcadeModePreview-rescue")
      var keyfallPreview = findChild(keyfall, "arcadeModePreview-keyfall")
      verify(sprintPreview !== null && sprintPreview.height >= 60)
      verify(findChild(sprintPreview, "sprintPreviewPlayer").visible)
      verify(findChild(sprintPreview, "sprintPreviewGhost").visible)
      verify(findChild(sprintPreview, "sprintPreviewFinish").visible)
      verify(rescuePreview !== null && rescuePreview.visible)
      compare(findChild(rescuePreview, "rescuePreviewShip").status, Image.Ready)
      compare(findChild(rescuePreview, "rescuePreviewPlanet").status, Image.Ready)
      compare(findChild(arcade, "rescueCabinetPreview"), null)
      verify(keyfallPreview !== null && keyfallPreview.visible)
      verify(findChild(keyfallPreview, "keyfallPreviewShortcut").visible)
      verify(findChild(keyfallPreview, "keyfallPreviewCatch").visible)
    }
    function test_compactArrowAndTabNavigationScrollsControlsIntoView() {
      host.width = 800
      host.height = 600
      arcade.textScale = 1.3
      wait(20)
      var scroller = object("arcadeScroll")
      for (var i = 1; i < arcade.navigationControls.length - 1; i++) {
        arcade.handleControlKey(i % 2 ? "DOWN" : "TAB")
        var selected = arcade.selectedControl
        var point = selected.mapToItem(scroller.contentItem, 0, 0)
        verify(selected.activeFocus)
        verify(point.y >= -1, "selected control top is in the viewport")
        verify(point.y + selected.height <= scroller.availableHeight + 1, "selected control bottom is in the viewport")
      }
      verify(scroller.contentItem.contentY > 0)
      for (var j = arcade.navigationIndex; j > 0; j--) arcade.handleControlKey("BACKTAB")
      var first = arcade.selectedControl.mapToItem(scroller.contentItem, 0, 0)
      verify(first.y >= -1)
      verify(first.y + arcade.selectedControl.height <= scroller.availableHeight + 1)
    }
    function test_desktopPlayUsesArenaRatherThanTopAlignedForm_data() {
      return [{ tag: "Sprint", mode: "sprint" }, { tag: "Rescue", mode: "rescue" }, { tag: "Keyfall", mode: "keyfall" }]
    }
    function test_desktopPlayUsesArenaRatherThanTopAlignedForm(data) {
      start(data.mode)
      wait(10)
      var arena = object("arcadeArena")
      var card = object("arcadePromptCard")
      tryVerify(function() { return arena.height >= 320 }, 1000)
      verify(arena.height >= arcade.playViewportHeight * 0.5)
      fuzzyCompare(card.x + card.width / 2, arena.width / 2, 1)
      verify(card.centered)
      if (data.mode === "rescue") {
        var scene = object("arcadeRescueScene")
        verify(scene.height >= 220)
        verify(scene.mapToItem(arcade, 0, scene.height).y <= arcade.height - arcade.dialogMargin)
        verify(scene.y >= card.y + card.height + 19)
        compare(arcade.currentPage.controls.length, 0)
        verify(object("arcadeSafetyLine").text.indexOf("H hint · P pause") >= 0)
      } else {
        verify(card.width <= (data.mode === "sprint" ? 980 * arcade.textScale : 800))
        verify(card.height + 150 <= arena.height)
        if (data.mode === "sprint") {
          var console = object("arcadeSprintRaceConsole")
          verify(object("arcadeSprintTrack").visible)
          verify(card.width > 900 * arcade.textScale)
          verify(object("arcadePrompt").font.pixelSize >= 34 * arcade.fontScale)
          verify(card.y >= 60)
          verify(card.y + card.height < console.y)
          verify(object("arcadeSafetyLine").text.indexOf("timer keeps running") >= 0)
          compare(object("arcadeSafetyLine").text.indexOf("P pause"), -1)
        } else {
          verify(object("arcadeKeyfallField").visible)
          verify(object("arcadeLearnDock").visible)
        }
      }
    }
    function test_sprintCircuitTracksCurrentAndGhostRecall() {
      start("sprint")
      var track = object("arcadeSprintTrack")
      compare(track.ghostCount, 0)
      compare(track.playerProgress, 0)
      verify(track.trackMaximum >= 12)
      verify(object("arcadeSprintPlayerRacer").width > object("arcadeSprintPlayerRacer").height)
      verify(object("arcadeSprintPlayerFinish").visible)
      answerCurrent()
      compare(arcade.answeredCount, 1)
      verify(track.playerProgress > 0)
      verify(track.paceStatus.indexOf("FIRST PACE") >= 0)
    }
    function test_reducedMotionStopsDecorativeArcadeMotion() {
      arcade.reducedMotion = true
      start("sprint")
      compare(object("arcadeSprintTrack").activeMotion, false)
      arcade.openHub()
      start("keyfall")
      compare(object("arcadeKeyfallField").activeMotion, false)
    }
    function test_keyfallFieldReflectsApproachAndLearningAssist() {
      start("keyfall")
      var field = object("arcadeKeyfallField")
      compare(field.approach, 0)
      verify(field.phaseLabel.indexOf("READ") >= 0)
      stepClock(4000)
      verify(field.approach > 0)
      arcade.showHint()
      verify(field.approach > 0)
      verify(field.phaseLabel.indexOf("LEARNING ASSIST") >= 0)
    }
    function test_keyfallMotionUsesLaneButReducedMotionIsStationary() {
      arcade.reducedMotion = false
      start("keyfall")
      wait(120)
      var card = object("arcadePromptCard")
      var initialY = card.y
      stepClock(6000)
      wait(150)
      verify(card.y > initialY + 30)
      arcade.reducedMotion = true
      wait(120)
      var fixedY = card.y
      stepClock(1000)
      compare(card.y, fixedY)
      arcade.showHint()
      compare(card.y, fixedY)
    }
  }
}
