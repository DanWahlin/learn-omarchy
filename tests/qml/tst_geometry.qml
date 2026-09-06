import QtQuick
import QtTest

Item {
  id: harness
  width: 2000
  height: 1400
  property var fixture

  TestCase {
    name: "AdaptiveTargetGeometry"
    when: windowShown

    function initTestCase() {
      var xhr = new XMLHttpRequest()
      xhr.open("GET", Qt.resolvedUrl("../../app/shell.qml"), false)
      xhr.send()
      var source = xhr.responseText
      var functions = source.match(/^  function (estimatedTargetGeometry|highlightWidth|logicalMonitorSize|projectWindowGeometry)\([^\n]*\) \{[\s\S]*?^  \}/gm)
      verify(functions && functions.length === 4)
      var start = source.indexOf("        readonly property bool windowOnThisMonitor:")
      var bindings = source.slice(start, source.indexOf("        readonly property real tourCenterX:", start))
      var leftEdge = source.match(/        function leftEdgePointX\([^\n]*\) \{[\s\S]*?\n        \}/)
      start = source.indexOf("        Rectangle {\n          id: tourOutline")
      var outline = source.slice(start, source.indexOf("        Rectangle {\n          id: tourCaption", start))
      verify(bindings.length > 100 && leftEdge !== null)
      fixture = Qt.createQmlObject(
        "import QtQuick\nItem { id: root; width: 1920; height: 1200\n"
        + "property var course: ({})\nproperty var targetWindowGeometry: null\n"
        + "property var targetMonitorGeometry: null\nproperty bool currentStepHasNoVisibleTarget: false\n"
        + "property string phase:'waiting'\nproperty bool currentStepIsTour:true\nproperty bool currentTourTalks:false\n"
        + "property string characterState:'tour-point'\nproperty real lessonContentOpacity:1\nproperty bool reducedMotion:true\n"
        + "property real textScale:1\nproperty color accent:'blue'\nproperty color instruction:'yellow'\n"
        + "property color foreground:'white'\nproperty color muted:'gray'\nproperty color panelColor:'black'\n"
        + "property var currentStep: ({completion:{type:'hyprland-layer-open'},highlight:{target:'panel',shape:'rectangle',anchor:'center',x:0,y:0,width:340,height:760}})\n"
        + "property var widgetRect: null\nproperty alias overlay: overlay\n"
        + "function barWorkspaceCount() { return 5 }\nfunction currentWorkspaceId() { return 1 }\n"
        + "function colorWithAlpha(color, alpha) { return Qt.rgba(color.r,color.g,color.b,alpha) }\n"
        + "function barTargetGeometry() { return widgetRect }\n"
        + functions.join("\n")
        + "\nQtObject { id: screenScope; property var modelData: ({name:'DP-1'}) }\n"
        + "Item { id: overlay; anchors.fill: parent\n"
        + "property alias estimateText: estimateLabel\n"
        + "property var hyprlandMonitor: ({id:1})\nproperty var highlight: root.currentStep.highlight\n"
        + "function workspaceSlot() { return 0 }\n" + leftEdge[0] + "\n" + bindings + "\n" + outline
        + "\n} }", harness)
    }

    function init() {
      failOnWarning(/.*/)
      fixture.width = 1920
      fixture.height = 1200
      fixture.widgetRect = null
      fixture.targetWindowGeometry = null
      fixture.targetMonitorGeometry = null
      fixture.currentStepHasNoVisibleTarget = false
      fixture.currentStep = {completion:{type:"hyprland-layer-open"},
        highlight:{target:"panel",shape:"rectangle",anchor:"center",x:0,y:0,width:340,height:760}}
    }

    function test_estimatesAdaptButNeverBecomeExactPointers_data() {
      return [
        {tag:"laptop", w:1280, h:720},
        {tag:"portrait", w:1080, h:1920},
        {tag:"large", w:2560, h:1440},
        {tag:"small", w:640, h:480}
      ]
    }

    function test_estimatesAdaptButNeverBecomeExactPointers(data) {
      fixture.width = data.w
      fixture.height = data.h
      compare(fixture.overlay.targetIsEstimated, true)
      compare(fixture.overlay.hasReliableCompletionTarget, false)
      verify(fixture.overlay.targetBoundsX >= 0)
      verify(fixture.overlay.targetBoundsY >= 0)
      verify(fixture.overlay.targetBoundsX + fixture.overlay.fittedHighlightWidth <= data.w)
      verify(fixture.overlay.targetBoundsY + fixture.overlay.fittedHighlightHeight <= data.h)
    }

    function test_liveGeometryReplacesEstimatesAndTracksViewportChanges() {
      fixture.targetMonitorGeometry = {id:1,x:1920,y:0,width:3840,height:2400,scale:2,transform:0}
      fixture.targetWindowGeometry = {at:[2200,200],size:[500,600]}
      compare(fixture.overlay.targetIsEstimated, false)
      compare(fixture.overlay.hasReliableCompletionTarget, true)
      compare(fixture.overlay.targetBoundsX, 280)
      compare(fixture.overlay.fittedHighlightWidth, 500)
      fixture.width = 960
      fixture.height = 600
      compare(fixture.overlay.targetBoundsX, 140)
      compare(fixture.overlay.fittedHighlightWidth, 250)
      fixture.currentStepHasNoVisibleTarget = true
      compare(fixture.overlay.hasReliableCompletionTarget, false)
    }

    function test_realPopupBoundsTakePrecedenceOverItsLayerSurface() {
      fixture.targetMonitorGeometry = {id:1,x:1920,y:0,width:1920,height:1200,scale:1,transform:0}
      fixture.targetWindowGeometry = {at:[1920,0],size:[1920,1200]}
      fixture.widgetRect = {x:800,y:200,width:340,height:700,panel:true}
      compare(fixture.overlay.usesWindowTarget, false)
      compare(fixture.overlay.targetIsEstimated, false)
      compare(fixture.overlay.targetBoundsX, 800)
      compare(fixture.overlay.fittedHighlightWidth, 340)
      compare(fixture.overlay.targetPointX, 800)
    }

    function test_estimatedCellsRemainDistinctFromMeasuredCells() {
      fixture.widgetRect = {x:100,y:0,width:28,height:30,estimated:true}
      compare(fixture.overlay.targetIsEstimated, true)
      compare(fixture.overlay.hasReliableCompletionTarget, false)
      fixture.widgetRect = {x:100,y:0,width:28,height:30}
      compare(fixture.overlay.targetIsEstimated, false)
      compare(fixture.overlay.hasReliableCompletionTarget, true)
    }

    function test_estimateBadgeStaysVisibleEvenWhenTheAreaFillsTheScreen() {
      fixture.width = 640
      fixture.height = 480
      fixture.currentStep = {completion:{type:"hyprland-layer-open"},
        highlight:{target:"panel",shape:"rectangle",anchor:"center",x:0,y:0,width:1920,height:1200}}
      var badge = fixture.overlay.estimateText.parent
      verify(badge.visible)
      compare(fixture.overlay.estimateText.text, "Estimated area")
      var position = badge.mapToItem(fixture.overlay, 0, 0)
      verify(position.x >= 0 && position.y >= 0)
      verify(position.x + badge.width <= fixture.width)
      verify(position.y + badge.height <= fixture.height)
      fixture.widgetRect = {x:100,y:100,width:300,height:200}
      compare(badge.visible, false)
    }
  }
}
