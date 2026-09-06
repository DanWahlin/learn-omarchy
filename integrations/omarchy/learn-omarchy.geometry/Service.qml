import Quickshell.Io
import Quickshell.Wayland

SnapshotProvider {
  id: root
  panelNamespace: function(window) { return window.WlrLayershell.namespace }

  IpcHandler {
    target: "learnGeometry"

    function snapshot(): string {
      return root.snapshot()
    }

    function capabilities(): string {
      return root.capabilities()
    }
  }
}
