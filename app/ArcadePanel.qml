pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "ArcadeLogic.js" as ArcadeLogic
import "ThemeColors.js" as ThemeColors

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
  readonly property real fontScale: textScale * 1.25
  required property bool reducedMotion
  property bool active: false
  property var pressedKeys: []
  property string storageNotice: ""
  property string guideName: "Ohm1"
  property url guideSource: ""
  property var guidePack: null
  property string appRoot: ""
  property url wallpaperSource: ""
  property string wallpaperNotice: ""
  property bool keyboardCaptureAvailable: true

  signal closeRequested()
  signal statsCommitted(var value)
  signal effectRequested(string name)
  signal activeHostChanged(bool isActive)
  signal clearInputRequested()
  signal keyfallMissed()

  Keys.onEscapePressed: event => {
    root.handleEscape()
    event.accepted = true
  }

  property string screen: "hub"
  property string mode: ""
  property var challenges: []
  property var workingStats: ArcadeLogic.mergeStats(stats)
  property var deck: []
  property var queue: []
  property int challengeIndex: 0
  property int answeredCount: 0
  property int score: 0
  property int streak: 0
  property int bestRunStreak: 0
  property int cleanAnswers: 0
  property int wrongAttempts: 0
  property int lastAwardedPoints: 0
  property string lastRescueReaction: ""
  property bool challengeEngaged: false
  property bool hinted: false
  property bool hintVisible: false
  property string assistanceReason: ""
  property bool competitive: true
  property bool targeted: false
  property string feedback: ""
  property string selectedCategory: "all"
  property string selectedPace: "standard"
  property string runPace: "standard"
  property string runDeckKey: ""
  property string sessionId: ""
  property var previousBest: ({ bestScore: 0, plays: 0, splits: [] })
  property var splits: []
  property var weakRunIds: []
  property var retriedIds: []
  property var regainedIds: []
  property real elapsedMs: 0
  property real challengeElapsedMs: 0
  property real lastTickAt: 0
  property real responseRemainingMs: 0
  property bool responsePending: false
  property int remainingMs: 60000
  property real keyfallProgress: 0
  property int rescueCompleted: 0
  property var rescueMission: null
  property string lastRescueMissionId: ""
  property int finalScore: 0
  property int finalStreak: 0
  property int finalClean: 0
  property int finalElapsedMs: 0
  property bool newBest: false
  property bool newBestPace: false
  property int navigationIndex: 0
  readonly property int arrivalDwellMs: 1400
  readonly property bool rescueArrivalPending: mode === "rescue" && responsePending
    && runTarget > 0 && rescueCompleted >= runTarget
  readonly property int responseDwellMs: mode === "rescue"
    ? rescueArrivalPending ? 1200 : 850 : 700
  readonly property int fallDurationMs: runPace === "relaxed" ? 11000 : runPace === "fast" ? 5000 : 7500
  readonly property bool running: screen === "sprint" || screen === "rescue" || screen === "keyfall"
  readonly property var currentEntry: mode === "sprint"
    ? (deck.length ? { challenge: deck[challengeIndex % deck.length], retry: false } : null)
    : (queue[challengeIndex] || null)
  readonly property var currentChallenge: currentEntry ? currentEntry.challenge : null
  readonly property var currentRescueStep: mode === "rescue" && rescueMission
    && Array.isArray(rescueMission.steps) ? (rescueMission.steps[challengeIndex] || null) : null
  readonly property string currentPrompt: currentRescueStep ? currentRescueStep.prompt
    : currentChallenge ? currentChallenge.prompt : ""
  readonly property string currentDetail: currentChallenge ? currentChallenge.detail : ""
  readonly property var expectedKeys: currentChallenge ? currentChallenge.keys : []
  readonly property bool isRetry: !!(currentEntry && currentEntry.retry)
  readonly property int runTarget: mode === "sprint" ? 0 : queue.length
  readonly property int regainedRecall: regainedIds.length
  readonly property var mastery: ArcadeLogic.masterySummary(workingStats, challenges)
  readonly property var learningMilestones: {
    var practiced = mastery.practiced > 0
    var independent = mastery.independent + mastery.mastered > 0
    var retained = mastery.mastered > 0
    var skills = workingStats.skills || ({})
    Object.keys(skills).forEach(function(signature) {
      var skill = skills[signature]
      practiced = practiced || skill.attempts > 0
      independent = independent || skill.firstTry > 0
      var sessions = skill.successfulSessions || []
      if (sessions.length >= 2 && sessions[sessions.length - 1].at - sessions[0].at >= 86400000)
        retained = true
    })
    return [
      { id: "first-practice", label: "First practice", earned: practiced },
      { id: "independent-recall", label: "Independent recall", earned: independent },
      { id: "retained-days", label: "Retained across days", earned: retained }
    ]
  }
  readonly property var recommendation: ArcadeLogic.recommendedPractice(challenges, workingStats)
  readonly property var categories: ["all"].concat(mastery.byCategory.map(function(item) { return item.category }))
  readonly property color surfaceColor: {
    var base = Qt.rgba(backgroundColor.r, backgroundColor.g, backgroundColor.b, 1)
    var candidate = Qt.tint(base, Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.035))
    return ThemeColors.contrast(String(foregroundColor), String(candidate)) >= 4.5 &&
      ThemeColors.contrast(String(mutedColor), String(candidate)) >= 4.5 &&
      ThemeColors.contrast(String(urgentColor), String(candidate)) >= 4.5 ? candidate : base
  }
  readonly property color raisedColor: Qt.tint(surfaceColor, Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.09))
  readonly property color lineColor: Qt.tint(surfaceColor, Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.22))
  readonly property color inkAccent: backgroundColor.hslLightness > 0.6 ? Qt.darker(accentColor, 1.8) : accentColor
  readonly property color buttonInk: accentColor.hslLightness > 0.6 ? "#131820" : "#ffffff"
  readonly property color modeAccent: screen === "hub" ? accentColor : colorForMode(mode)
  readonly property color modeInk: inkForColor(modeAccent)
  readonly property color modeButtonInk: modeAccent.hslLightness > 0.6 ? "#131820" : "#ffffff"
  readonly property real playViewportHeight: scroller.availableHeight
  readonly property bool compactLayout: width < 900 || height < 700
  readonly property real dialogMargin: width < 900 ? 12 : 32
  readonly property real contentMargin: width < 900 ? 20 : 32
  readonly property real nonPlayWidth: 1180 * textScale
  readonly property real completionWidth: 820 * textScale
  readonly property var currentPage: screen === "hub" ? hubPageLoader.item
    : screen === "paused" ? pausedPageLoader.item
    : screen === "complete" ? completePageLoader.item
    : screen === "results" ? resultsPageLoader.item : playPageLoader.item
  readonly property var navigationControls: currentPage ? currentPage.controls.concat([backButton]) : [backButton]
  readonly property var selectedControl: navigationControls[navigationIndex] || null
  readonly property string resultTitle: ArcadeLogic.resultLabel(mode, finalClean, answeredCount)
  readonly property string paceLabel: {
    if (!competitive) return "Practice pace · assisted runs never overwrite a challenge record."
    if (!previousBest.plays) return "First race on this deck. Your completed answers will set its pace."
    var past = 0
    for (var i = 0; i < previousBest.splits.length; i++) {
      if (previousBest.splits[i] <= elapsedMs) past++
    }
    return "Best-score run pace: " + past + " answers by now · you " + (answeredCount >= past ? "+" : "") + (answeredCount - past)
  }
  function modeName(id) {
    return id === "sprint" ? "Shortcut Sprint" : id === "rescue" ? "Window Rescue" : "Keyfall"
  }
  function arcadeAssetUrl(name) {
    if (!appRoot) return Qt.resolvedUrl("../assets/arcade/" + name)
    return "file://" + (appRoot + "/assets/arcade/" + name)
      .split("/").map(encodeURIComponent).join("/")
  }
  function colorForMode(id) {
    if (id !== "rescue" && id !== "keyfall") return accentColor
    var hue = Math.max(0, accentColor.hslHue)
    var shift = id === "rescue" ? -0.12 : 0.12
    return Qt.hsla((hue + shift + 1) % 1, Math.max(0.45, accentColor.hslSaturation),
      backgroundColor.hslLightness > 0.6 ? 0.36 : 0.7, 1)
  }
  function inkForColor(value) {
    return ThemeColors.readable(String(value), String(surfaceColor))
  }
  function textOnColor(value) { return ThemeColors.onColor(String(value)) }
  function modeStats(id) { return ArcadeLogic.mergeStats(workingStats)[id] }
  function categoryLabel(value) { return value === "all" ? "All topics" : value.charAt(0).toUpperCase() + value.slice(1) }
  function formatTime(ms) {
    var seconds = Math.max(0, Math.ceil(ms / 1000))
    return seconds >= 60 ? Math.floor(seconds / 60) + ":" + (seconds % 60 < 10 ? "0" : "") + seconds % 60 : seconds + "s"
  }
  function rescueReactionForAction(action, finalStep) {
    if (finalStep && rescueMission && rescueMission.arrival) return rescueMission.arrival
    if (action === "launch-terminal") return "Terminal systems online."
    if (action === "launch-browser") return "Browser link established."
    if (action === "launch-files") return "Cargo files online."
    if (action === "float") return "Window released from the grid."
    if (action === "widen") return "Viewport expanded."
    if (action === "narrow") return "Viewport tightened."
    if (action === "fullscreen") return "Full-screen lock confirmed."
    if (action === "send-workspace-2") return "Workspace jump complete."
    if (action === "workspace-1" || action === "workspace-2"
        || action === "last-workspace" || action === "next-workspace"
        || action === "previous-workspace") return "Navigation vector confirmed."
    if (action === "cycle-focus" || action === "focus-right") return "Focus lock confirmed."
    if (action === "swap-right" || action === "toggle-split") return "Layout stabilized."
    if (action === "stash-window" || action === "toggle-scratchpad") return "Recovery system confirmed."
    if (action === "close-window") return "Window cleared safely."
    return "Flight system confirmed."
  }
  function commit(value) {
    workingStats = value
    statsCommitted(value)
  }
  function cycleCategory() { selectedCategory = categories[(categories.indexOf(selectedCategory) + 1) % categories.length] }
  function cyclePace() {
    var paces = ["relaxed", "standard", "fast"]
    selectedPace = paces[(paces.indexOf(selectedPace) + 1) % paces.length]
  }
  function openHub() {
    if (screen === "hub" && currentPage && typeof currentPage.detailView === "string")
      currentPage.detailView = ""
    navigationIndex = 0
    screen = "hub"
    challenges = ArcadeLogic.buildChallenges(course)
    feedback = ""
    hinted = false
    hintVisible = false
    assistanceReason = ""
    responsePending = false
    clearInputRequested()
  }
  function startGame(id) {
    challenges = ArcadeLogic.buildChallenges(course)
    var available = challenges.filter(function(item) { return selectedCategory === "all" || item.category === selectedCategory })
    var missionData = id === "rescue"
      ? ArcadeLogic.chooseRescueMission(challenges, Math.random, lastRescueMissionId) : null
    var chosen = id === "rescue"
      ? missionData ? missionData.steps.map(function(step) { return step.challenge; }) : []
      : ArcadeLogic.shuffled(available, Math.random)
    if (chosen.length === 0) {
      feedback = id === "rescue" ? "This course does not include a complete simulated rescue mission. Try Sprint or Keyfall."
        : "No shortcuts in this topic yet. Choose another topic."
      return
    }
    if (id === "keyfall") {
      var base = chosen.slice()
      chosen = []
      for (var i = 0; i < 12; i++) chosen.push(base[i % base.length])
    }
    if (missionData) lastRescueMissionId = missionData.id
    prepareGame(id, chosen, false, selectedPace, missionData)
  }
  function prepareGame(id, chosen, isTargeted, pace, missionData) {
    mode = id
    deck = chosen.slice()
    rescueMission = id === "rescue" ? missionData : null
    targeted = isTargeted
    runPace = id === "keyfall" ? pace : "standard"
    runDeckKey = ArcadeLogic.deckKey(mode, deck, runPace)
    previousBest = ArcadeLogic.bestForDeck(workingStats, runDeckKey)
    queue = deck.map(function(item) { return { challenge: item, retry: false } })
    challengeIndex = 0
    answeredCount = 0
    score = 0
    streak = 0
    bestRunStreak = 0
    cleanAnswers = 0
    wrongAttempts = 0
    lastAwardedPoints = 0
    lastRescueReaction = ""
    challengeEngaged = false
    hinted = false
    hintVisible = false
    assistanceReason = ""
    competitive = !isTargeted
    responsePending = false
    elapsedMs = 0
    challengeElapsedMs = 0
    remainingMs = 60000
    keyfallProgress = 0
    rescueCompleted = 0
    splits = []
    weakRunIds = []
    retriedIds = []
    regainedIds = []
    feedback = ""
    sessionId = String(Date.now()) + "-" + String(Math.random()).slice(2)
    lastTickAt = Date.now()
    screen = mode
    clearInputRequested()
  }
  function raceDeck() { prepareGame(mode, deck, targeted, runPace, rescueMission) }
  function showResults() {
    if (screen === "complete") screen = "results"
  }
  function practiceThose(ids, requestedMode) {
    var source = challenges.filter(function(item) { return ids.indexOf(item.id) >= 0 })
    if (!source.length) return
    var practiceMode = requestedMode || "keyfall"
    if (practiceMode === "rescue" && rescueMission) {
      prepareGame("rescue", deck, true, "standard", rescueMission)
      return
    }
    var practiceDeck = ArcadeLogic.practiceDeck(source, workingStats, source.length, Math.random, "all")
    prepareGame(practiceMode, practiceDeck, true, practiceMode === "keyfall" ? "relaxed" : runPace)
  }
  function updateClock(now) {
    var delta = Math.max(0, now - lastTickAt)
    lastTickAt = now
    if (!running || !active) return
    if (!hinted || mode === "sprint") {
      elapsedMs += delta
      if (!responsePending) challengeElapsedMs += delta
    }
    if (mode === "sprint") {
      remainingMs = Math.max(0, 60000 - elapsedMs)
      if (remainingMs <= 0) {
        elapsedMs = 60000
        finishGame()
        return
      }
    }
    if (responsePending) {
      responseRemainingMs -= delta
      if (responseRemainingMs <= 0) advanceChallenge()
    } else if (mode === "keyfall" && !hinted) {
      keyfallProgress = Math.max(0, Math.min(1, (challengeElapsedMs - arrivalDwellMs) / fallDurationMs))
      if (keyfallProgress >= 1) {
        assistanceReason = "timeout"
        keyfallMissed()
        showHint(true)
      }
    }
  }
  function pauseGame(forcePause) {
    if (!running) return
    if (mode === "sprint" && forcePause !== true) return
    updateClock(Date.now())
    if (!running) return
    competitive = false
    screen = "paused"
    clearInputRequested()
  }
  function resumeGame() {
    if (screen !== "paused" || !active) return
    lastTickAt = Date.now()
    screen = mode
    clearInputRequested()
  }
  function handleEscape() {
    if (screen === "hub") {
      if (currentPage && typeof currentPage.detailView === "string" && currentPage.detailView !== "") {
        currentPage.detailView = ""
        navigationIndex = 0
        Qt.callLater(function() { if (root.selectedControl) root.ensureControlVisible(root.selectedControl) })
      } else closeRequested()
    }
    else openHub()
  }
  function selectControl(delta) {
    var controls = navigationControls
    if (!controls.length) return
    for (var tries = 0; tries < controls.length; tries++) {
      navigationIndex = (navigationIndex + delta + controls.length) % controls.length
      var item = controls[navigationIndex]
      if (item && item.enabled && item.visible) {
        item.forceActiveFocus(Qt.TabFocusReason)
        ensureControlVisible(item)
        return
      }
    }
  }
  function ensureControlVisible(item) {
    if (!item || !body) return
    var point = item.mapToItem(body, 0, 0)
    var top = scrollContent.contentY
    if (point.y < top) top = point.y - 8
    else if (point.y + item.height > top + scroller.availableHeight)
      top = point.y + item.height - scroller.availableHeight + 8
    var maximum = Math.max(0, scrollContent.contentHeight - scroller.availableHeight)
    scrollContent.contentY = Math.max(0, Math.min(maximum, top))
  }
  function focusNavigationControl(item) {
    if (running) return
    var index = navigationControls.indexOf(item)
    if (index >= 0) {
      navigationIndex = index
      ensureControlVisible(item)
    }
  }
  function handleControlKey(key) {
    if (!active) return
    key = String(key).toUpperCase()
    if (key === "ESCAPE") { handleEscape(); return }
    if (running) {
      if (key === "H") showHint()
      else if (key === "P" && mode !== "sprint") pauseGame()
      return
    }
    if (screen === "paused" && key === "P") { resumeGame(); return }
    if (screen === "hub" && ["1", "2", "3"].indexOf(key) >= 0) {
      startGame(["sprint", "rescue", "keyfall"][Number(key) - 1])
      return
    }
    if (["TAB", "RIGHT", "DOWN"].indexOf(key) >= 0) selectControl(1)
    else if (["BACKTAB", "LEFT", "UP"].indexOf(key) >= 0) selectControl(-1)
    else if (["RETURN", "ENTER", "SPACE"].indexOf(key) >= 0 && selectedControl && selectedControl.enabled)
      selectedControl.clicked()
  }
  function showHint(clockUpdated) {
    if (!running || !currentChallenge || responsePending) return
    challengeEngaged = true
    if (hinted) {
      hintVisible = !hintVisible
      feedback = hintVisible
        ? mode === "keyfall" ? (wrongAttempts > 0
          ? "Signal rebuilt in Practice. Match the revealed keys; no points are removed."
          : "Hint opened in Practice. Match the revealed keys; no points are removed.")
        : mode === "rescue" ? "Keys revealed. Complete this action for practice, not points."
        : "Keys revealed. The Sprint timer keeps running; this answer earns practice, not points."
        : "Hint hidden. This answer remains practice and earns no points."
      clearInputRequested()
      return
    }
    if (clockUpdated !== true) updateClock(Date.now())
    if (!running || hinted) return
    if (!assistanceReason) assistanceReason = "hint"
    hinted = true
    hintVisible = true
    competitive = false
    streak = 0
    markWeak(currentChallenge.id)
    feedback = mode === "keyfall" ? (assistanceReason === "timeout"
      ? "Time to practice. Try the revealed keys; your points are safe."
      : wrongAttempts > 0
      ? "Signal missed. Try the revealed keys in Practice."
      : "Hint opened in Practice. Match the revealed keys; no points are removed.")
      : mode === "rescue" ? "Keys revealed. Complete this action for practice, not points."
      : "Keys revealed. The Sprint timer keeps running; this answer earns practice, not points."
    clearInputRequested()
    effectRequested("hint")
  }
  function markWeak(id) {
    if (weakRunIds.indexOf(id) < 0) weakRunIds = weakRunIds.concat([id])
  }
  function handleKeyPress(direct, keys) {
    if (!running || !active || !currentChallenge || responsePending || !direct) return
    if (["SUPER", "CTRL", "ALT", "SHIFT"].indexOf(direct) >= 0) return
    challengeEngaged = true
    updateClock(Date.now())
    if (!running || responsePending) return
    if (ArcadeLogic.keySignature(keys) === currentChallenge.signature) completeChallenge()
    else {
      wrongAttempts++
      streak = 0
      markWeak(currentChallenge.id)
      feedback = "Not that combination yet. No points lost. Try again, or learn this with H."
      if (mode === "keyfall") {
        if (!hinted) {
          assistanceReason = "miss"
          keyfallMissed()
          showHint()
        } else {
          hintVisible = true
          feedback = "Match the revealed keys. No points lost."
          clearInputRequested()
        }
      }
    }
  }
  function scheduleRetry(challenge) {
    if (retriedIds.indexOf(challenge.id) >= 0 || queue.length >= deck.length + 6) return
    var next = queue.slice()
    var at = challengeIndex + 1
    var intervening = 0
    while (at < next.length && intervening < 2) {
      if (next[at].challenge.id !== challenge.id) intervening++
      at++
    }
    if (intervening < 2) {
      var fillers = challenges.filter(function(item) {
        return item.id !== challenge.id &&
          (selectedCategory === "all" || item.category === selectedCategory)
      })
      var fillerIndex = 0
      while (intervening < 2 && fillers.length && next.length < deck.length + 5) {
        var filler = fillers[fillerIndex % fillers.length]
        next.push({ challenge: filler, retry: false })
        intervening++
        fillerIndex++
        at++
      }
    }
    if (intervening < 2 || next.length >= deck.length + 6) return
    if (next[at] && next[at].challenge.id === challenge.id)
      next[at] = { challenge: challenge, retry: true }
    else next.splice(at, 0, { challenge: challenge, retry: true })
    queue = next
    retriedIds = retriedIds.concat([challenge.id])
  }
  function completeChallenge() {
    if (!running || responsePending || !currentChallenge) return
    var challenge = currentChallenge
    var clean = !hinted && wrongAttempts === 0
    var points = ArcadeLogic.scoreAnswer(mode, challengeElapsedMs, streak, hinted, wrongAttempts)
    var finalRescueStep = mode === "rescue" && challengeIndex === queue.length - 1
    score += points
    if (clean) {
      cleanAnswers++
      streak++
      bestRunStreak = Math.max(bestRunStreak, streak)
      if (isRetry && regainedIds.indexOf(challenge.id) < 0) regainedIds = regainedIds.concat([challenge.id])
    } else {
      streak = 0
      markWeak(challenge.id)
      if (mode === "keyfall") scheduleRetry(challenge)
    }
    commit(ArcadeLogic.recordAttempt(workingStats, challenge, {
      hinted: hinted, wrongAttempts: wrongAttempts, elapsedMs: Math.round(challengeElapsedMs), sessionId: sessionId
    }, Date.now()))
    answeredCount++
    if (mode === "rescue") rescueCompleted++
    lastAwardedPoints = points
    lastRescueReaction = mode === "rescue"
      ? rescueReactionForAction(currentRescueStep ? currentRescueStep.action : "", finalRescueStep) : ""
    splits = splits.concat([Math.round(elapsedMs)])
    feedback = mode === "rescue"
      ? guideName + ": " + lastRescueReaction + (points > 0 ? " +" + points + " points." : " Practice logged.")
      : clean ? (isRetry ? "Recalled independently on the retry. " : "First-try recall. ") + "+" + points + " points."
      : hinted ? (mode === "keyfall" && wrongAttempts > 0
        ? "Recovered after a miss. Practice saved."
        : "Practiced with a hint. Learning saved; no score claimed.")
      : "You found it. Learning saved; not a first-try answer."
    responsePending = true
    responseRemainingMs = responseDwellMs
    effectRequested(clean ? "success" : "hint")
    clearInputRequested()
  }
  function advanceChallenge() {
    if (!running || !responsePending) return
    responsePending = false
    challengeIndex++
    if (mode !== "sprint" && challengeIndex >= queue.length) { finishGame(); return }
    hinted = false
    hintVisible = false
    assistanceReason = ""
    wrongAttempts = 0
    lastAwardedPoints = 0
    lastRescueReaction = ""
    challengeEngaged = false
    challengeElapsedMs = 0
    keyfallProgress = 0
    feedback = ""
    clearInputRequested()
  }
  function finishGame() {
    if (!running) return
    finalScore = score
    finalStreak = bestRunStreak
    finalClean = cleanAnswers
    finalElapsedMs = Math.round(elapsedMs)
    newBest = competitive && score > previousBest.bestScore
    newBestPace = competitive && previousBest.plays && score === previousBest.bestScore &&
      finalElapsedMs < previousBest.bestElapsedMs
    commit(ArcadeLogic.recordRun(workingStats, {
      mode: mode, score: score, streak: bestRunStreak, clean: cleanAnswers,
      total: answeredCount, elapsedMs: finalElapsedMs, deckKey: runDeckKey,
      splits: splits, competitive: competitive
    }, Date.now()))
    responsePending = false
    screen = "complete"
    clearInputRequested()
    effectRequested("finish")
  }

  onStatsChanged: workingStats = ArcadeLogic.mergeStats(stats)
  onCourseChanged: if (screen === "hub") challenges = ArcadeLogic.buildChallenges(course)
  onActiveChanged: {
    activeHostChanged(active)
    if (!active && running) pauseGame(true)
    else if (active && challenges.length === 0) challenges = ArcadeLogic.buildChallenges(course)
  }
  onScreenChanged: {
    navigationIndex = 0
    scrollContent.contentY = 0
  }
  Component.onCompleted: challenges = ArcadeLogic.buildChallenges(course)

  Timer {
    interval: 40
    repeat: true
    running: root.active && root.running
    onTriggered: root.updateClock(Date.now())
  }
  Rectangle { anchors.fill: parent; color: Qt.rgba(root.backgroundColor.r, root.backgroundColor.g, root.backgroundColor.b, 1) }
  Image {
    id: wallpaper
    objectName: "arcadeWallpaper"
    anchors.fill: parent
    source: root.wallpaperSource
    sourceSize: Qt.size(Math.max(1, Math.ceil(root.width * Screen.devicePixelRatio)),
      Math.max(1, Math.ceil(root.height * Screen.devicePixelRatio)))
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    cache: true
    visible: status === Image.Ready
    onStatusChanged: {
      root.wallpaperNotice = status === Image.Error
        ? "The theme wallpaper could not be loaded. Using the theme color instead." : ""
      if (status === Image.Error) console.warn("learn-omarchy:", root.wallpaperNotice, source)
    }
  }
  Rectangle {
    anchors.fill: parent
    visible: wallpaper.status === Image.Ready
    color: root.backgroundColor
    opacity: root.running ? 0.32 : 0.16
  }
  Rectangle {
    objectName: "arcadeFrame"
    width: Math.min(root.width - root.dialogMargin * 2,
      root.running || root.screen === "hub" ? 1680
        : root.screen === "complete" ? root.completionWidth : root.nonPlayWidth)
    height: root.running ? root.height - root.dialogMargin * 2
      : Math.min(root.height - root.dialogMargin * 2,
        body.implicitHeight + headerRow.implicitHeight + frameLayout.spacing + root.contentMargin * 2)
    anchors.centerIn: parent
    color: root.surfaceColor
    radius: 2
    border.color: root.modeInk
    border.width: 2
    ArcadeBezel {
      objectName: "arcadeCabinetBezel"
      anchors.fill: parent
      anchors.margins: -9
      accent: root.modeAccent
      marquee: true
    }
    ColumnLayout {
      id: frameLayout
      anchors.fill: parent
      anchors.margins: root.contentMargin
      spacing: root.compactLayout ? 16 : 24
      RowLayout {
        id: headerRow
        Layout.fillWidth: true
        Loader {
          id: guidePortrait
          objectName: "arcadeGuidePortrait"
          Layout.preferredWidth: (root.compactLayout ? 76 : 96) * root.textScale
          Layout.preferredHeight: (root.compactLayout ? 65 : 84) * root.textScale
          visible: !!root.guidePack && root.screen === "hub"
          active: visible
          sourceComponent: Item {
            Accessible.role: Accessible.Graphic
            Accessible.name: root.guideName + ", your guide"
            CharacterSprite {
              objectName: "arcadeGuide"
              anchors.centerIn: parent
              pack: root.guidePack
              animated: false
              previewFrame: 0
              reducedMotion: true
              scale: Math.min(guidePortrait.width / 224, guidePortrait.height / 192)
            }
          }
        }
        ColumnLayout {
          Layout.fillWidth: true
          spacing: 3
          ArcadePixelText {
            objectName: "arcadeTitle"
            Layout.fillWidth: true
            text: root.screen === "hub" ? "Learn Omarchy Arcade" : root.modeName(root.mode)
            color: root.modeInk
            font.pixelSize: (root.width < 700 ? 20 : 24) * root.fontScale
          }
          Text {
            objectName: "arcadeSafetyLine"
            Layout.fillWidth: true
            visible: root.screen !== "complete" && root.screen !== "results"
            text: root.running
              ? root.mode === "sprint"
                ? "Shortcuts affect only this game · H hint · timer keeps running"
                : "Shortcuts affect only this game · H hint · P pause"
              : "Shortcuts affect only this game"
            color: root.mutedColor
            font.pixelSize: 11 * root.fontScale
            wrapMode: Text.WordWrap
          }
        }
        ArcadeButton {
          id: backButton
          objectName: "arcadeCloseButton"
          arcade: root
          square: true
          text: "×"
          accessibleName: root.screen === "hub" ? "Close arcade" : "Return to arcade hub"
          Accessible.description: root.running
            ? "Leave this round and return to the arcade hub" : root.screen === "hub" ? "Return to the course menu" : "Close this game"
          navigationSelected: !root.running && root.selectedControl === backButton
          onClicked: {
            if (root.running) root.openHub()
            else if (root.screen === "hub") root.closeRequested()
            else root.openHub()
          }
        }
      }
      ScrollView {
        id: scroller
        objectName: "arcadeScroll"
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        Flickable {
          id: scrollContent
          contentHeight: body.implicitHeight
          contentWidth: width
          boundsBehavior: Flickable.StopAtBounds
          ColumnLayout {
            id: body
            width: scroller.availableWidth
            spacing: 12
            Text {
              objectName: "arcadeRuntimeNotice"
              Layout.fillWidth: true
              visible: !root.running && (root.storageNotice.length > 0 || root.wallpaperNotice.length > 0)
              text: [root.storageNotice, root.wallpaperNotice].filter(function(text) { return text.length > 0 }).join("\n")
              color: root.mutedColor
              font.pixelSize: 12 * root.fontScale
              wrapMode: Text.WordWrap
            }
            Item {
              id: page
              Layout.fillWidth: true
              implicitHeight: root.currentPage ? root.currentPage.implicitHeight : 0

              Loader {
                id: hubPageLoader
                objectName: "arcadeHubPageLoader"
                anchors.left: parent.left
                anchors.right: parent.right
                active: true
                visible: root.screen === "hub"
                sourceComponent: hubPage
              }
              Loader {
                id: playPageLoader
                objectName: "arcadePlayPageLoader"
                anchors.left: parent.left
                anchors.right: parent.right
                active: true
                visible: ["rescue", "sprint", "keyfall"].indexOf(root.screen) >= 0
                sourceComponent: playPage
              }
              Loader {
                id: pausedPageLoader
                objectName: "arcadePausedPageLoader"
                anchors.left: parent.left
                anchors.right: parent.right
                active: true
                visible: root.screen === "paused"
                sourceComponent: pausedPage
              }
              Loader {
                id: completePageLoader
                objectName: "arcadeCompletePageLoader"
                anchors.left: parent.left
                anchors.right: parent.right
                active: true
                visible: root.screen === "complete"
                sourceComponent: completePage
              }
              Loader {
                id: resultsPageLoader
                objectName: "arcadeResultsPageLoader"
                anchors.left: parent.left
                anchors.right: parent.right
                active: true
                visible: root.screen === "results"
                sourceComponent: resultsPage
              }
            }
            Text {
              objectName: "arcadeNavigationHint"
              Layout.fillWidth: true
              Layout.topMargin: root.compactLayout ? 0 : 4
              visible: !root.running && root.screen !== "results"
              text: root.screen === "complete" ? "Enter to see results · Esc to return to the arcade hub"
                : root.screen === "paused" ? (root.keyboardCaptureAvailable
                  ? "Tab or arrow keys to choose · Enter to confirm · P to resume"
                  : "Click Resume to restore keyboard capture")
                : "Tab or arrow keys to choose · Enter to confirm · Esc to go back"
              color: root.mutedColor
              font.pixelSize: 11 * root.fontScale
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }
          }
        }
      }
      ArcadeRescueJourney {
        objectName: "arcadeRescueFlight"
        Layout.fillWidth: true
        Layout.preferredHeight: root.height < 800 ? 66 : implicitHeight
        visible: root.screen === "rescue"
        arcade: root
        showBurst: false
        completedActions: root.rescueCompleted
        totalSteps: root.runTarget
      }
    }
  }
  Component { id: hubPage; ArcadeHub { arcade: root } }
  Component { id: playPage; ArcadePlayfield { arcade: root } }
  Component { id: completePage; ArcadeRoundComplete { arcade: root } }
  Component { id: resultsPage; ArcadeResults { arcade: root } }
  Component {
    id: pausedPage
    ColumnLayout {
      readonly property var controls: [resumeButton, quitButton]
      spacing: 0
      ColumnLayout {
        objectName: "arcadePauseContent"
        Layout.fillWidth: true
        Layout.maximumWidth: 820 * root.textScale
        Layout.alignment: Qt.AlignHCenter
        spacing: 16 * root.textScale
        Text {
          Layout.fillWidth: true
          text: "PAUSED"
          color: root.modeInk
          font.pixelSize: 11 * root.fontScale
          font.weight: Font.Bold
          font.letterSpacing: 1
        }
        ArcadePixelText {
          Layout.fillWidth: true
          text: "Your round is paused"
          color: root.foregroundColor
          font.pixelSize: 22 * root.fontScale
        }
        Text {
          Layout.fillWidth: true
          text: root.keyboardCaptureAvailable
            ? "Take a break. Your completed shortcuts are saved. Resume whenever you're ready."
            : "Keyboard capture was interrupted. Click Resume to restore it and continue safely."
          color: root.mutedColor
          font.pixelSize: 16 * root.fontScale
          wrapMode: Text.WordWrap
        }
        GridLayout {
          Layout.fillWidth: true
          columns: root.compactLayout ? 1 : 2
          columnSpacing: 10
          rowSpacing: 10
          ArcadeButton {
            id: resumeButton
            objectName: "arcadeResumeButton"
            Layout.fillWidth: root.compactLayout
            arcade: root
            text: root.keyboardCaptureAvailable ? "Resume practice · Enter / P" : "Resume and restore keys"
            primary: true
            navigationSelected: root.selectedControl === resumeButton
            onClicked: root.resumeGame()
          }
          ArcadeButton {
            id: quitButton
            Layout.fillWidth: root.compactLayout
            arcade: root
            text: "Quit to hub"
            navigationSelected: root.selectedControl === quitButton
            onClicked: root.openHub()
          }
        }
      }
    }
  }
}
