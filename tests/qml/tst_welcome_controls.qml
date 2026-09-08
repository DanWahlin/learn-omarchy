import QtQuick
import QtTest

Item {
  id: harness
  width: 1920
  height: 1200
  property var fixture
  TestCase {
    name: "WelcomeControlsGeometry"
    when: windowShown
    function initTestCase() {
      var xhr = new XMLHttpRequest()
      xhr.open("GET", Qt.resolvedUrl("../../app/shell.qml"), false)
      xhr.send()
      var source = xhr.responseText
      var start = source.indexOf("        Rectangle {\n          id: welcomeToolbarOutline")
      var end = source.indexOf("        GridLayout {\n          id: controls", start)
      verify(start >= 0 && end > start)
      fixture = Qt.createQmlObject("import QtQuick\nItem { id: root; width: 1920; height: 1200\n"
        + "property string phase: 'welcome'\nproperty string welcomeStage: 'controls-flight'\n"
        + "property color instruction: 'cyan'\n"
        + "property alias toolbar: controls\nproperty alias outline: welcomeToolbarOutline\n"
        + "Item { id: controls; x: 1696; y: 42; width: 200; height: 44 }\n"
        + source.slice(start, end) + "\n}", harness)
    }
    function test_outlineTracksRealToolbarBoundsIncludingWrappedRows() {
      for (var bounds of [[1696, 42, 200, 44], [100, 42, 156, 100], [500, 42, 280, 60]]) {
        fixture.toolbar.x = bounds[0]
        fixture.toolbar.y = bounds[1]
        fixture.toolbar.width = bounds[2]
        fixture.toolbar.height = bounds[3]
        compare(fixture.outline.x, bounds[0] - 8)
        compare(fixture.outline.y, bounds[1] - 8)
        compare(fixture.outline.width, bounds[2] + 16)
        compare(fixture.outline.height, bounds[3] + 16)
      }
    }
    function test_outlineOnlyAppearsForTheControlsStop() {
      fixture.phase = "welcome"
      for (var stage of ["welcome", "controls-flight", "controls", "menu-flight"]) {
        fixture.welcomeStage = stage
        compare(fixture.outline.visible, stage === "controls-flight" || stage === "controls")
      }
      fixture.welcomeStage = "controls"
      fixture.phase = "settings"
      verify(!fixture.outline.visible)
    }
  }
}
