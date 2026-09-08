import QtQuick
import "Geometry.js" as Geometry

Item {
  property var shell: null
  property var panelNamespace: null

  function capabilities(): string {
    var bar = shell ? shell.bar : null
    return JSON.stringify({
      shellAvailable: shell !== null,
      barAvailable: !!bar,
      activeBarId: shell ? shell.activeBarId : "",
      manifestId: bar && bar.manifest ? bar.manifest.id : "",
      slotsAvailable: !!(bar && bar.moduleSlots),
      windowMappingAvailable: !!(bar && typeof bar.slotWindow === "function")
    })
  }

  function snapshot(): string {
    try {
      return JSON.stringify(Geometry.snapshot(shell ? shell.bar : null, panelNamespace, shell ? shell.activeBarId : undefined, shell))
    } catch (error) {
      return "learnGeometry unavailable: " + error.message
    }
  }
}
