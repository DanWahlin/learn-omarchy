import QtQuick
import QtTest
import "../../integrations/omarchy/learn-omarchy.geometry" as Provider

Item {
  width: 1600
  height: 900
  id: harness

  Provider.SnapshotProvider {
    id: provider
    shell: host
    panelNamespace: function(window) { return window.testNamespace }
  }
  QtObject { id: host; property var bar: bar; property string activeBarId: "omarchy.bar" }
  QtObject {
    id: bar
    property var manifest: ({id: "omarchy.bar"})
    property string position: "bottom"
    property bool barHidden: false
    property var moduleSlots: [slot]
    function slotWindow(item) { return item === slot ? barWindow : null }
  }
  QtObject {
    id: barWindow
    property var screen: ({name: "DP-scaled", width: 1600, height: 900})
    property real width: 1600
    property real height: 32
    property bool visible: true
    property var anchors: ({top: false, bottom: true, left: true, right: true})
    property var margins: ({top: 0, bottom: 0, left: 0, right: 0})
  }
  Item {
    x: 11
    y: 2
    Item {
      id: slot
      x: 47
      width: 170
      height: 30
      property string moduleName: "omarchy.workspaces"
      property var activeItem: workspaceWidget
      Item {
        id: workspaceWidget
        anchors.fill: parent
        property bool opened: false
        function workspaceIds() { return [1, 7, 10] }
        function workspaceById(id) { return null }
        Loader {
          id: popupLoader
          active: workspaceWidget.opened
          sourceComponent: Item {
            QtObject {
              property var bar: host.bar
              property bool open: true
              property bool visible: true
              property string testNamespace: "omarchy-keyboard-panel"
              property var screen: barWindow.screen
              property real width: 1600
              property real height: 900
              property var anchors: ({top: true, bottom: true, left: true, right: true})
              property var margins: ({top: 0, bottom: 0, left: 0, right: 0})
              property point cardOrigin: Qt.point(600, 200)
              property real contentWidth: 380
              property real contentHeight: 560
            }
          }
        }
        Item {
          x: 4
          Repeater {
            model: [1, 7, 10]
            Item {
              required property int modelData
              required property int index
              property var workspace: null
              signal pressed(int button)
              x: index * index * 33
              width: 20 + index * 5
              height: 30
            }
          }
        }
      }
    }
  }
  TestCase {
    name: "ReadOnlyGeometryProvider"
    when: windowShown

    function init() {
      failOnWarning(/.*/)
      provider.shell = host
      host.activeBarId = "omarchy.bar"
      bar.manifest = {id: "omarchy.bar"}
      bar.barHidden = false
      barWindow.margins = {top: 0, bottom: 0, left: 0, right: 0}
      workspaceWidget.visible = true
      workspaceWidget.opened = false
      slot.x = 47
    }

    function test_hostStylePropertyInjectionWorksThroughTheBaseComponent() {
      provider.shell = null
      verify("shell" in provider)
      provider.shell = host
      var capabilities = JSON.parse(provider.capabilities())
      compare(capabilities.shellAvailable, true)
      compare(capabilities.barAvailable, true)
      compare(capabilities.manifestId, "omarchy.bar")
      compare(capabilities.slotsAvailable, true)
    }

    function test_stockBarCanPrecedeItsManifestWhileCustomBarsStillFailClosed() {
      bar.manifest = null
      compare(JSON.parse(provider.snapshot()).version, 1)
      host.activeBarId = "custom.bar"
      bar.manifest = {id:"omarchy.bar"}
      verify(provider.snapshot().indexOf("learnGeometry unavailable:") === 0)
    }
    function test_publicObjectsAndActualRepeaterDelegates() {
      var result = JSON.parse(provider.snapshot())
      compare(result.version, 1)
      compare(result.screens[0].name, "DP-scaled")
      compare(result.screens[0].width, 1600)
      var widgets = result.screens[0].widgets
      compare(widgets.length, 4)
      compare(widgets[0].x, 58)
      compare(widgets[0].y, 870)
      compare(widgets[1].workspaceId, 1)
      compare(widgets[1].x, 62)
      compare(widgets[2].workspaceId, 7)
      compare(widgets[2].x, 95)
      compare(widgets[3].workspaceId, 10)
      compare(widgets[3].x, 194)
      compare(widgets[3].width, 30)
      slot.x = 70
      compare(JSON.parse(provider.snapshot()).screens[0].widgets[0].x, 81)
    }

    function test_hiddenAndInactiveGeometryIsNotActionable() {
      workspaceWidget.visible = false
      var widgets = JSON.parse(provider.snapshot()).screens[0].widgets
      compare(widgets[0].itemVisible, false)
      compare(widgets[1].visible, false)
      workspaceWidget.visible = true
      bar.barHidden = true
      barWindow.margins = {top: 0, bottom: -32, left: 0, right: 0}
      compare(JSON.parse(provider.snapshot()).screens[0].widgets[0].visible, false)
    }

    function test_capabilityFailuresReturnNonJsonForConsumerFallback() {
      bar.manifest = {id: "custom.bar"}
      verify(provider.snapshot().indexOf("learnGeometry unavailable:") === 0)
    }

    function test_publicDataAndLoaderExposeExactCardWithoutOpeningAnything() {
      workspaceWidget.opened = true
      tryCompare(popupLoader, "status", Loader.Ready)
      var widgets = JSON.parse(provider.snapshot()).screens[0].widgets
      compare(widgets.length, 5)
      compare(widgets[4].id, "panel:omarchy-keyboard-panel")
      compare(widgets[4].x, 600)
      compare(widgets[4].y, 200)
      compare(widgets[4].width, 380)
      compare(widgets[4].height, 560)
    }
  }
}
