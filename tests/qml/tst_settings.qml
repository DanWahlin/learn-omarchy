import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import QtTest

Item {
  id: root
  width: 1920
  height: 1200

  property string appRoot: Qt.resolvedUrl("../..").toString().replace(/\/$/, "")
  property string phase: "settings"
  property string settingsMode: "settings"
  property real textScale: 1
  property var characterIndex: []
  property string characterName: "owl"
  property string characterNotice: ""
  property string introNotice: ""
  property string integrationNotice: ""
  property int characterPick: 1
  property bool speechEnabled: true
  property bool synchronizedWelcomeText: true
  property bool effectsEnabled: true
  property bool audioEnabled: true
  property bool motionReduced: false
  readonly property bool reducedMotion: motionReduced
  property bool autoAdvance: true
  property real speechVolume: 80
  property real effectsVolume: 45
  property real speechRate: 1
  property bool resetJustDone: false
  property bool resetConfirmPending: false
  property bool resetOptionsExpanded: false
  onResetConfirmPendingChanged: if (resetConfirmPending) resetOptionsExpanded = true
  property int completedCount: 1
  property var course: ({ lessons: new Array(11) })
  property color foreground: "#c0caf5"
  property color background: "#1a1b26"
  property color accent: "#7aa2f7"
  property color instruction: "#e0af68"
  property color urgent: "#f7768e"
  property color muted: "#a0a9c9"
  property color panelColor: background
  property color panelBorder: "#414868"
  property color subtleFill: "#24283b"
  property Palette controlPalette: Palette { highlightedText: "black" }
  QtObject {
    id: appTheme
    property var colors: ({background:root.background.toString(),foreground:root.foreground.toString(),
      accent:root.accent.toString(),muted:root.muted.toString()})
  }
  property bool keyboardExclusive: true
  property bool currentStepIsTour: false
  property bool introActive: false
  property string welcomeStage: ""
  property string characterState: "hidden"
  property var currentStep: null
  property bool actionRunning: false
  property bool exerciseRunning: false
  property string outcomeAddress: ""
  property int savedCount: 0
  property int refreshCount: 0
  property var fixture

  Item { id: sfxProcess; property bool running: false }
  Item {
    id: characterStore
    property string fallbackId: "ohm-1"
    property string narrationNotice: ""
    property var diagnostics: []
  }
  Item {
    id: overlay
    anchors.fill: parent
    property var highlight: null
  }

  function colorWithAlpha(color, alpha) { return Qt.rgba(color.r, color.g, color.b, alpha) }
  function persistSettings() { savedCount++ }
  function stopAudio() {}
  function stopWelcomeSpeech() {}
  function finishWelcome() { welcomeStage = "" }
  function toggleAudio() { audioEnabled = !audioEnabled; persistSettings() }
  function closeSettings() { phase = "menu" }
  function chooseCharacter(id) { characterName = id; persistSettings() }
  function refreshCharacters() { refreshCount++ }
  function currentAudioPath() { return "" }
  function requestResetProgress() { resetConfirmPending = true }
  function handleKeyPressed(event) {}
  function handleSystemVolumeKey(event) { return false }
  function updateActiveKeys(event, pressed) {}

  function readSource(path) {
    var xhr = new XMLHttpRequest()
    xhr.open("GET", Qt.resolvedUrl(path), false)
    xhr.send()
    return xhr.responseText
  }

  function descendants(item, predicate) {
    var result = []
    if (predicate(item)) result.push(item)
    for (var child of item.children || [])
      result = result.concat(descendants(child, predicate))
    return result
  }

  function button(label) {
    var matches = descendants(fixture, function(item) { return "label" in item && item.label === label && "clicked" in item })
    return matches.length ? matches[0] : null
  }

  TestCase {
    name: "ProductionSettingsLayout"
    when: windowShown

    function initTestCase() {
      root.characterIndex = JSON.parse(root.readSource("../../assets/characters/index.json")).characters.map(function(entry) {
        var directory = "../../assets/characters/" + entry.id
        return { id: entry.id, assetUrl: Qt.resolvedUrl(directory).toString(),
          manifest: JSON.parse(root.readSource(directory + "/character.json")) }
      })
      var source = root.readSource("../../app/shell.qml")
      verify(source.length > 1000)
      var components = source.slice(source.indexOf("  component UiPanel:"), source.indexOf("  component Keycap:"))
      var start = source.indexOf("        UiPanel {\n          id: characterPanel")
      var panel = source.slice(start, source.indexOf("        UiPanel {\n          id: topicPanel", start))
      start = source.indexOf("        GridLayout {\n          id: controls")
      var controls = source.slice(start, source.indexOf("        UiPanel {\n          id: pausePanel", start))
      verify(panel.length > 1000)
      root.fixture = Qt.createQmlObject(
        "import QtQuick\nimport QtQuick.Layouts\nimport QtQuick.Controls as Controls\nimport \"../../app\"\n"
        + "Item { width: root.width; height: root.height\n"
        + "property alias panel: characterPanel\nproperty alias header: settingsHeader\n"
        + "property alias footer: settingsFooter\nproperty alias scroll: settingsScroll\n"
        + "property alias controls: controls\n"
        + components + panel + controls + "\n}", overlay)
      wait(100)
    }

    function test_welcomeOnlyShowsTheFourExplainedToolbarIcons() {
      root.phase = "welcome"
      root.welcomeStage = "controls"
      root.keyboardExclusive = true
      root.audioEnabled = true
      root.currentStep = null
      wait(30)
      var controls = root.descendants(root.fixture.controls, function(item) {
        return "label" in item && "clicked" in item && item.visible
      })
      compare(controls.map(function(item) { return item.label }).join("|"), "SETTINGS|RELEASE KEYS|MUTE|EXIT")
    }

    function test_welcomeCaptionSyncCanBeDisabledWithoutChangingSpeech() {
      root.synchronizedWelcomeText = true
      var speech = root.speechEnabled
      var control = findChild(root.fixture, "typeTextSwitch")
      verify(control !== null)
      compare(control.text, "Fade captions")
      compare(control.checked, true)
      var saves = root.savedCount
      control.checked = false
      control.toggled()
      compare(root.synchronizedWelcomeText, false)
      compare(root.speechEnabled, speech)
      compare(root.savedCount, saves + 1)
      control.checked = true
      control.toggled()
      compare(root.synchronizedWelcomeText, true)
    }

    function init() {
      failOnWarning(/.*/)
      root.phase = "settings"
      root.settingsMode = "settings"
      root.textScale = 1
      root.resetConfirmPending = false
      root.resetOptionsExpanded = false
      root.audioEnabled = true
      root.speechEnabled = true
      root.effectsEnabled = true
      root.speechVolume = 80
      root.effectsVolume = 45
      root.currentStepIsTour = false
      root.keyboardExclusive = true
      root.audioEnabled = true
      root.introActive = false
      root.welcomeStage = ""
      root.currentStep = null
      root.characterNotice = ""
      root.introNotice = ""
      characterStore.diagnostics = []
      overlay.highlight = null
      root.width = 1920
      root.height = 1200
      fixture.scroll.contentY = 0
      wait(100)
    }

    function test_manifestPreviewDoesNotDependOnPackIdOrFilename() {
      var original = root.characterIndex
      var pack = JSON.parse(JSON.stringify(original[0]))
      pack.id = "external-demo"
      pack.manifest.displayName = "External Demo"
      pack.manifest.preview.frame = 1
      root.characterIndex = [pack]
      wait(50)
      var sprite = pack.manifest.sprites[pack.manifest.preview.sprite]
      var previews = root.descendants(fixture.panel, function(item) {
        return "sourceClipRect" in item && item.sourceClipRect.width > 0
      })
      compare(previews.length, 1)
      compare(previews[0].source.toString(), pack.assetUrl + "/" + sprite.path)
      compare(previews[0].sourceClipRect.x, sprite.frameWidth)
      compare(previews[0].sourceClipRect.width, sprite.frameWidth)
      compare(previews[0].sourceClipRect.height, sprite.frameHeight)
      root.characterIndex = original
    }

    function test_emptyCatalogKeepsNoticeAndRefreshVisible() {
      var original = root.characterIndex
      root.characterIndex = []
      root.characterNotice = "No valid character packs are available."
      wait(50)
      var refresh = root.button("REFRESH COACHES")
      verify(refresh !== null && refresh.visible)
      var before = root.refreshCount
      refresh.clicked()
      compare(root.refreshCount, before + 1)
      var notices = root.descendants(fixture.panel, function(item) {
        return "text" in item && item.text.indexOf("No valid character packs") >= 0
      })
      verify(notices.length > 0 && notices[0].visible)
      root.characterIndex = original
    }

    function test_firstRunHidesMaintenanceControls() {
      root.settingsMode = "first-run"
      characterStore.diagnostics = [{message: "Developer diagnostic"}]
      wait(50)
      verify(!root.button("REFRESH COACHES").visible)
      var details = root.descendants(fixture.panel, function(item) {
        return "label" in item && item.label.indexOf("COACH PACK DETAILS") >= 0
      })
      compare(details.length, 1)
      verify(!details[0].visible)
    }

    function test_packMetadataAndButtonLabelsAreLiteralPlainText() {
      var original = root.characterIndex
      var pack = JSON.parse(JSON.stringify(original[0]))
      pack.manifest.displayName = "<b>雪 & $&</b>"
      pack.manifest.description = "<i>A coach with Unicode: café</i>"
      root.characterIndex = [pack]
      root.characterNotice = "<b>Unavailable: 雪</b>"
      var diagnostic = "<i>Missing sprite: <example></i>"
      characterStore.diagnostics = [{ message: diagnostic }]
      var refresh = root.button("REFRESH COACHES")
      refresh.label = "<b>Refresh 雪</b>"
      wait(50)
      var labels = [pack.manifest.displayName, pack.manifest.description, root.characterNotice, diagnostic, refresh.label]
      for (var label of labels) {
        var matches = root.descendants(fixture.panel, function(item) {
          return "textFormat" in item && item.text === label
        })
        verify(matches.length > 0, label)
        for (var match of matches) compare(match.textFormat, Text.PlainText, label)
      }
      refresh.label = "REFRESH COACHES"
      root.characterIndex = original
    }

    function test_packDiagnosticsAreAvailableWithoutClutteringSettings() {
      characterStore.diagnostics = [
        "ohm-1: author is unresolved; review attribution and redistribution rights",
        "ohm-1: license is unresolved; review attribution and redistribution rights"
      ]
      root.characterNotice = "A selected pack is unavailable; using HEXON."
      wait(30)
      var details = root.descendants(fixture.panel, function(item) {
        return item.objectName === "packDetails"
      })[0]
      verify(!details.visible)
      var notices = root.descendants(fixture.panel, function(item) {
        return "text" in item && item.text === root.characterNotice
      })
      verify(notices.length > 0 && notices[0].visible)
      var toggle = root.button("SHOW COACH PACK DETAILS (2)")
      verify(toggle !== null && toggle.visible)
      toggle.forceActiveFocus(Qt.TabFocusReason)
      keyClick(Qt.Key_Space)
      tryCompare(details, "visible", true)
      compare(details.text, characterStore.diagnostics.join("\n"))
      mouseClick(root.button("HIDE COACH PACK DETAILS (2)"))
      tryCompare(details, "visible", false)
      mouseClick(root.button("SHOW COACH PACK DETAILS (2)"))
      tryCompare(details, "visible", true)
      root.phase = "menu"
      wait(20)
      root.phase = "settings"
      wait(20)
      verify(!details.visible)
      characterStore.diagnostics = []
      wait(20)
      verify(!root.button("SHOW COACH PACK DETAILS (0)").visible)
    }

    function test_resetRequiresExplicitConfirmationAndCanBeCancelled() {
      verify(!root.button("RESET PROGRESS").visible)
      mouseClick(root.button("SHOW RESET OPTIONS"))
      wait(30)
      verify(root.button("RESET PROGRESS").visible)
      root.button("RESET PROGRESS").forceActiveFocus(Qt.TabFocusReason)
      wait(30)
      mouseClick(root.button("RESET PROGRESS"))
      verify(root.resetConfirmPending)
      verify(root.button("CONFIRM RESET").visible)
      verify(root.button("CANCEL").visible)
      var prompts = root.descendants(fixture.panel, function(item) {
        return "text" in item && item.text.indexOf("Reset all lesson progress, including the tour?") === 0
      })
      verify(prompts.length === 1 && prompts[0].visible)
      wait(6200)
      verify(root.resetConfirmPending, "confirmation must not silently expire");
      root.button("CANCEL").forceActiveFocus(Qt.TabFocusReason)
      wait(30)
      mouseClick(root.button("CANCEL"))
      verify(!root.resetConfirmPending)
      verify(root.button("RESET PROGRESS").visible)
      compare(root.completedCount, 1)
    }

    function test_regionsStaySeparated_data() {
      return [
        { tag: "desktop", w: 1920, h: 1200, scale: 1, firstRun: false },
        { tag: "laptop", w: 1280, h: 720, scale: 1, firstRun: false },
        { tag: "large-text", w: 1280, h: 720, scale: 1.3, firstRun: false },
        { tag: "narrow", w: 640, h: 720, scale: 1.3, firstRun: false },
        { tag: "first-run", w: 1280, h: 720, scale: 1, firstRun: true },
        { tag: "first-run-narrow", w: 640, h: 720, scale: 1.3, firstRun: true }
      ]
    }

    function test_regionsStaySeparated(data) {
      root.width = data.w
      root.height = data.h
      root.textScale = data.scale
      root.settingsMode = data.firstRun ? "first-run" : "settings"
      wait(150)
      var panel = fixture.panel
      var header = fixture.header.mapToItem(panel, 0, 0)
      var scroll = fixture.scroll.mapToItem(panel, 0, 0)
      var footer = fixture.footer.mapToItem(panel, 0, 0)
      verify(panel.x >= 0 && panel.y >= 0)
      verify(panel.x + panel.width <= root.width + 1)
      verify(panel.y + panel.height <= root.height + 1)
      verify(scroll.y >= header.y + fixture.header.height + 19)
      verify(footer.y >= scroll.y + fixture.scroll.height + 19)
      verify(footer.y + fixture.footer.height <= panel.height - 23)
      verify(fixture.scroll.height > 100)
      compare(fixture.controls.visible, false)
      var done = root.button(data.firstRun ? "EXIT" : "DONE")
      verify(done !== null && done.visible)
      var donePoint = done.mapToItem(panel, 0, 0)
      verify(donePoint.y >= footer.y)
      verify(donePoint.x + done.width <= panel.width - 23)
      var sliders = root.descendants(fixture, function(item) { return "from" in item && "to" in item && "moved" in item })
      compare(sliders.length, 4)
      for (var slider of sliders) {
        if (!data.firstRun) {
          verify(slider.height >= 32)
          verify(slider.handle.height <= slider.height)
        }
      }
      if (data.firstRun) compare(findChild(fixture, "narrationVolumePreference").visible, false)
    }

    function test_audioUsesVolumeSlidersAndOnlyShowsUnmuteWhenNeeded() {
      compare(root.button("MUTE ALL"), null)
      compare(root.button("SPEECH ON"), null)
      compare(root.button("EFFECTS ON"), null)
      var notice = findChild(fixture, "audioMutedNotice")
      verify(!notice.visible)
      root.audioEnabled = false
      wait(20)
      verify(notice.visible)
      root.button("UNMUTE").clicked()
      verify(root.audioEnabled)
      var narration = findChild(fixture, "narrationVolumePreference")
      narration.adjusted(0)
      compare(root.speechVolume, 0)
      compare(root.speechEnabled, false)
      compare(narration.displayValue, "Off")
      narration.adjusted(65)
      compare(root.speechEnabled, true)
      compare(narration.displayValue, "65%")
      var effects = findChild(fixture, "effectsVolumePreference")
      sfxProcess.running = true
      effects.adjusted(0)
      compare(root.effectsEnabled, false)
      compare(sfxProcess.running, false)
      compare(effects.displayValue, "Off")
      effects.adjusted(75)
      compare(root.effectsEnabled, true)
      compare(root.effectsVolume, 75)
    }

    function test_readingPreferencesUseSwitchesAndSaveTheirValues() {
      for (var entry of [["reduceMotionSwitch", "motionReduced"], ["autoAdvanceSwitch", "autoAdvance"]]) {
        var control = findChild(fixture, entry[0])
        verify(control !== null)
        var value = !root[entry[1]]
        var saved = root.savedCount
        control.checked = value
        control.toggled()
        compare(root[entry[1]], value)
        compare(root.savedCount, saved + 1)
      }
      var footerButtons = root.descendants(fixture.footer, function(item) {
        return "label" in item && "clicked" in item && item.visible
      })
      compare(footerButtons.length, 1)
      compare(footerButtons[0].label, "DONE")
    }

    function test_collapsingResetOptionsCancelsPendingConfirmation() {
      root.button("SHOW RESET OPTIONS").clicked()
      root.button("RESET PROGRESS").clicked()
      verify(root.resetConfirmPending)
      root.button("HIDE RESET OPTIONS").clicked()
      verify(!root.resetOptionsExpanded)
      verify(!root.resetConfirmPending)
      verify(!root.button("RESET PROGRESS").visible)
    }

    function test_footerDoesNotScrollAndDoneWorks() {
      root.height = 720
      wait(100)
      var before = fixture.footer.mapToItem(fixture.panel, 0, 0)
      fixture.scroll.contentY = fixture.scroll.contentHeight - fixture.scroll.height
      wait(50)
      var after = fixture.footer.mapToItem(fixture.panel, 0, 0)
      compare(after.y, before.y)
      mouseClick(root.button("DONE"))
      compare(root.phase, "menu")
    }

    function test_focusedControlsAreRevealed() {
      root.width = 640
      root.height = 720
      root.textScale = 1.3
      wait(150)
      var reset = root.button("RESET PROGRESS")
      root.resetOptionsExpanded = true
      wait(20)
      reset.forceActiveFocus(Qt.TabFocusReason)
      wait(100)
      var position = reset.mapToItem(fixture.scroll, 0, 0)
      verify(position.y >= -1)
      verify(position.y + reset.height <= fixture.scroll.height + 1)
      verify(fixture.scroll.contentY > 0)
    }

    function test_toolbarStaysCompactWhenChangingSides() {
      root.phase = "waiting"
      root.currentStepIsTour = true
      for (var i = 0; i < 3; i++) {
        overlay.highlight = { anchor: "top-right" }
        wait(50)
        compare(fixture.controls.x, 24)
        compare(fixture.controls.width, fixture.controls.implicitWidth)
        verify(fixture.controls.width < 900)
        overlay.highlight = { anchor: "top-left" }
        wait(50)
        compare(fixture.controls.x, root.width - fixture.controls.width - 24)
        compare(fixture.controls.width, fixture.controls.implicitWidth)
        verify(fixture.controls.width < 900)
      }
    }

    function test_toolbarIconsKeepLabelsTargetsAndTooltips() {
      root.phase = "waiting"
      root.currentStep = { help: { label: "Help" } }
      root.introActive = true
      root.welcomeStage = "scene"
      wait(50)
      var buttons = root.descendants(fixture.controls, function(item) {
        return "icon" in item && item.visible
      })
      compare(buttons.length, 7)
      for (var button of buttons) {
        verify(button.icon !== "")
        verify(button.label !== "")
        verify(button.width >= 44 && button.height >= 44)
        compare(button.Accessible.name, button.label)
        var images = root.descendants(button, function(item) { return "sourceSize" in item })
        compare(images.length, 1)
        tryCompare(images[0], "status", Image.Ready)
        var tooltip = root.descendants(button, function(item) { return item.objectName === "buttonTooltip" })[0]
        button.forceActiveFocus(Qt.TabFocusReason)
        tryCompare(tooltip, "visible", true)
        keyClick(Qt.Key_Tab)
        mouseMove(fixture, 10, root.height - 10)
        tryCompare(tooltip, "visible", false)
        mouseMove(button, button.width / 2, button.height / 2)
        tryCompare(tooltip, "visible", true)
        mouseMove(fixture, 10, root.height - 10)
        tryCompare(tooltip, "visible", false)
      }
    }

    function test_toolbarStateIconsAndTextActions() {
      root.phase = "waiting"
      wait(50)
      var buttons = root.descendants(fixture.controls, function(item) { return "icon" in item })
      var audio = buttons.filter(function(item) { return item.label === "MUTE" })[0]
      compare(audio.icon, "volume")
      mouseClick(audio)
      compare(root.audioEnabled, false)
      compare(audio.label, "UNMUTE")
      compare(audio.icon, "muted")
      compare(root.button("RELEASE KEYS").icon, "keyboard")
      root.keyboardExclusive = false
      compare(root.button("CAPTURE KEYS").icon, "keyboard-off")
      compare(root.button("PAUSE").icon, "pause")
      root.phase = "paused"
      compare(root.button("RESUME").icon, "play")
      root.phase = "settings"
      compare(root.button("DONE").icon, "")
    }

    function test_leftDockTooltipRemainsOnscreen() {
      root.phase = "waiting"
      root.currentStepIsTour = true
      overlay.highlight = { anchor: "top-right" }
      wait(50)
      var capture = root.button("RELEASE KEYS")
      capture.forceActiveFocus(Qt.TabFocusReason)
      var tooltip = root.descendants(capture, function(item) { return item.objectName === "buttonTooltip" })[0]
      tryCompare(tooltip, "visible", true)
      var position = tooltip.mapToItem(root, 0, 0)
      verify(position.x >= 0)
      verify(position.x + tooltip.width <= root.width)
    }
  }
}
