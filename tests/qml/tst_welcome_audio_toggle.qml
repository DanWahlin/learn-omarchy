import QtQuick
import QtTest

Item {
  id: harness
  property var fixture

  TestCase {
    name: "WelcomeAudioToggle"
    when: windowShown

    function initTestCase() {
      var xhr = new XMLHttpRequest()
      xhr.open("GET", Qt.resolvedUrl("../../app/shell.qml"), false)
      xhr.send()
      var source = xhr.responseText
      var methods = ["toggleAudio", "welcomeCaptionShown", "stopWelcomeSpeech", "welcomeSpeechExited"]
        .map(function(name) { return source.match(new RegExp("^  function " + name + "\\([^\\n]*\\) \\{[\\s\\S]*?^  \\}", "m"))[0] }).join("\n")
      var reveal = source.match(/  CaptionReveal \{\n    id: welcomeReveal[\s\S]*?\n  \}/)[0]
      fixture = Qt.createQmlObject(
        'import QtQuick\nimport "../../app"\nItem { id: root\n'
        + 'property string phase: "welcome"; property string welcomeStage: "controls"\n'
        + 'property bool audioEnabled: true; property bool speechEnabled: true\n'
        + 'readonly property bool narrationEnabled: audioEnabled && speechEnabled\n'
        + 'property bool synchronizedWelcomeText: true; property bool reducedMotion: false\n'
        + 'property bool welcomeReadingActive: false; property bool welcomeCaptionVisible: true\n'
        + 'property bool welcomeNarrationStarted: false; property bool welcomeNarrationFinished: false\n'
        + 'property bool welcomeSpeechStopping: false; property bool introActive: false\n'
        + 'property bool currentStepIsTour: false; property int introGeneration: 1\n'
        + 'property int readingWordsPerMinute: 200; property int narrationRestMs: 900\n'
        + 'property var welcomeNarration: ({})\n'
        + 'property string welcomeText: "These are the Learn Omarchy controls: Settings, keyboard capture, mute narration, and Exit."\n'
        + 'property alias welcomeReadingStartOffset: welcomeReveal.readingStartOffset\n'
        + 'property alias welcomeReadingElapsed: welcomeReveal.readingElapsed\n'
        + 'readonly property int welcomeRevealEnd: welcomeReveal.revealEnd\n'
        + 'property alias reveal: welcomeReveal; property alias speech: welcomeSpeech; property alias readTimer: welcomeReadTimer\n'
        + 'function welcomeInstruction() { return welcomeText }\nfunction welcomeAudioPath() { return "/test.mp3" }\n'
        + 'function captionText(text) { return text }\nfunction readingDuration(text) { return 10000 }\n'
        + 'function timedSpeechCommand(path) { return [path] }\nfunction persistSettings() {}\n'
        + 'function stopAudio() {}\nfunction scheduleTourAdvance(duration) {}\nfunction tourFallbackDuration() { return 0 }\n'
        + 'QtObject { id: welcomeSpeech; property bool running: false; property int generation: -1\n'
        + 'property int captionGeneration: -1; property string stage: ""; property var command: []\n'
        + 'property int starts: 0; onRunningChanged: if (running) starts++ }\n'
        + 'QtObject { id: audioProcess; property bool running: false }\n'
        + 'QtObject { id: sfxProcess; property bool running: false }\n'
        + 'QtObject { id: tourAdvanceTimer; property bool running: false }\n'
        + 'Timer { id: welcomeReadTimer; property int generation: -1; property string stage: "" }\n'
        + reveal + "\n" + methods + "\n}", harness)
    }

    function test_mutingAndUnmutingPreserveReadingWithoutRestartingSpeech() {
      failOnWarning(/.*/)
      fixture.welcomeCaptionShown()
      compare(fixture.speech.starts, 1)
      var text = fixture.welcomeText
      var words = []
      var matches = text.match(/\S+/g)
      var offset = 0
      for (var word of matches) {
        offset = text.indexOf(word, offset) + word.length
        words.push({ startMs: words.length * 200, endOffset: offset })
      }
      fixture.reveal.receive(JSON.stringify({ type: "timing", text: text, words: words }), fixture.speech.captionGeneration)
      fixture.reveal.receive('{"type":"position","positionMs":1200}', fixture.speech.captionGeneration)
      var spokenEnd = fixture.welcomeRevealEnd
      verify(spokenEnd > 0)
      fixture.toggleAudio()
      verify(!fixture.speech.running)
      verify(fixture.welcomeRevealEnd >= spokenEnd)
      wait(400)
      var readingEnd = fixture.welcomeRevealEnd
      fixture.toggleAudio()
      verify(fixture.audioEnabled)
      verify(fixture.welcomeRevealEnd >= readingEnd)
      fixture.welcomeSpeechExited(143, 1, "controls")
      fixture.welcomeCaptionShown()
      compare(fixture.speech.starts, 1)
      verify(!fixture.speech.running)
      tryVerify(function() { return fixture.welcomeRevealEnd > readingEnd })
      fixture.readTimer.stop()
    }
  }
}
