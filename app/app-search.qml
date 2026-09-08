import QtQuick
import Quickshell

ShellRoot {
  AppSearchSession {
    id: session
    onCompleted: {
      console.log("LEARN_PRACTICE_RESULT:" + JSON.stringify({ mode: "app-search", completed: true }))
      Qt.quit()
    }
    onFailed: function(message) {
      console.warn("learn-omarchy app search:", message)
      Qt.quit()
    }
  }
  Component.onCompleted: session.start()
}
