import QtQuick
import QtTest

Item {
  id: harness
  width: 640
  height: 480
  property var fixture

  TestCase {
    name: "SystemVolumeShortcuts"
    when: windowShown

    function initTestCase() {
      var xhr = new XMLHttpRequest()
      xhr.open("GET", Qt.resolvedUrl("../../app/shell.qml"), false)
      xhr.send()
      var source = xhr.responseText
      var start = source.indexOf("  component SystemVolumeShortcut:")
      var end = source.indexOf("  Process {", start)
      verify(start >= 0 && end > start)
      fixture = Qt.createQmlObject("import QtQuick\nimport QtQuick.Controls\nItem { id: root; width: 640; height: 480\n"
        + "property bool keyboardExclusive: true\nproperty bool shortcutInhibitionActive: true\n"
        + "property var actions: []\n"
        + "function queueSystemVolume(action) { actions = actions.concat([action]) }\n"
        + source.match(/^  function handleSystemVolumeKey\([^\n]*\) \{[\s\S]*?^  \}/m)[0] + "\n"
        + "property alias slider: slider\nSlider { id: slider; y: 60; width: 200; from: 0; to: 100; value: 50\n"
        + "Keys.onPressed: function(event) { root.handleSystemVolumeKey(event) } }\n"
        + "property alias input: input\nTextInput { id: input; focus: true; width: 200; height: 40 }\n"
        + source.slice(start, end) + "\n}", harness)
    }

    function init() {
      failOnWarning(/.*/)
      fixture.keyboardExclusive = true
      fixture.shortcutInhibitionActive = true
      fixture.actions = []
      fixture.input.text = ""
      fixture.input.forceActiveFocus()
      wait(20)
    }

    function test_volumeKeysWorkEvenWithATextFieldFocused() {
      keyClick(Qt.Key_VolumeUp)
      keyClick(Qt.Key_VolumeDown)
      keyClick(Qt.Key_VolumeMute)
      keyClick(Qt.Key_VolumeUp, Qt.AltModifier)
      keyClick(Qt.Key_VolumeDown, Qt.AltModifier)
      compare(JSON.stringify(fixture.actions), JSON.stringify([5, -5, "mute-toggle", 1, -1]))
      compare(fixture.input.text, "")
    }

    function test_releasedKeysAndInactiveInhibitorsDoNotDoubleAdjustVolume() {
      fixture.keyboardExclusive = false
      keyClick(Qt.Key_VolumeUp)
      compare(fixture.actions.length, 0)
      fixture.keyboardExclusive = true
      fixture.shortcutInhibitionActive = false
      keyClick(Qt.Key_VolumeDown)
      compare(fixture.actions.length, 0)
    }

    function test_unrelatedShortcutsAreNotIntercepted() {
      keyClick(Qt.Key_VolumeMute, Qt.ShiftModifier)
      keyClick(Qt.Key_A)
      compare(fixture.actions.length, 0)
      compare(fixture.input.text, "a")
    }

    function test_directLayerPathWorksOnSettingsSlidersWithoutApplicationShortcuts() {
      var shortcuts = []
      for (var object of fixture.data) {
        if (object.sequence !== undefined && object.context !== undefined) {
          shortcuts.push(object)
          object.enabled = false
        }
      }
      fixture.slider.forceActiveFocus()
      keyClick(Qt.Key_VolumeDown)
      keyClick(Qt.Key_VolumeMute)
      compare(JSON.stringify(fixture.actions), JSON.stringify([-5, "mute-toggle"]))
      compare(fixture.slider.value, 50)
      for (var shortcut of shortcuts) shortcut.enabled = Qt.binding(function() {
        return fixture.keyboardExclusive && fixture.shortcutInhibitionActive
      })
    }
  }
}
