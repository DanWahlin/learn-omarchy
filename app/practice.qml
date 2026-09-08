import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
  id: root
  readonly property string mode: Quickshell.env("LEARN_OMARCHY_PRACTICE_MODE")
  OmarchyTheme {
    id: theme
    fallbackColors: ({
      background: Quickshell.env("LEARN_OMARCHY_PRACTICE_BACKGROUND"),
      foreground: Quickshell.env("LEARN_OMARCHY_PRACTICE_FOREGROUND"),
      accent: Quickshell.env("LEARN_OMARCHY_PRACTICE_ACCENT"),
      urgent: Quickshell.env("LEARN_OMARCHY_PRACTICE_ERROR")
    })
  }
  IpcHandler {
    target: "practice"
    function cancel(): void { session.cancel() }
    function status(): string { return session.status() }
  }
  FloatingWindow {
    id: practiceWindow
    title: "Learn Omarchy - practice"
    implicitWidth: 760
    implicitHeight: 500
    minimumSize: Qt.size(460, 400)
    color: theme.colors.background
    visible: true
    onClosed: session.cancel()
    PracticeSession {
      id: session
      anchors.fill: parent
      mode: root.mode
      textScale: Number(Quickshell.env("LEARN_OMARCHY_PRACTICE_SCALE") || "1")
      backgroundColor: theme.colors.background
      foreground: theme.colors.foreground
      accent: theme.colors.accent
      muted: theme.colors.muted
      errorColor: theme.colors.urgent
      onCompleted: {
        console.log("LEARN_PRACTICE_RESULT:" + JSON.stringify({ mode: root.mode, completed: true }))
        Qt.quit()
      }
      onCancelled: Qt.quit()
      onFailed: function(message) { console.warn(message); Qt.quit() }
    }
  }
  IdleInhibitor {
    window: practiceWindow
    enabled: session.running && root.mode !== "screen-lock"
  }
}
