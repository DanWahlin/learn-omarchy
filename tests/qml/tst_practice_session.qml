import QtQuick
import QtTest

Item {
  id: root
  width: 760
  height: 320
  property var sessionComponent: null
  SignalSpy { id: completedSpy; signalName: "completed" }
  SignalSpy { id: cancelledSpy; signalName: "cancelled" }
  SignalSpy { id: failedSpy; signalName: "failed" }
  TestCase {
    name: "EmbeddedPracticeSession"
    when: windowShown
    property var session: null
    function initTestCase() {
      root.sessionComponent = Qt.createComponent("../../app/PracticeSession.qml")
      if (root.sessionComponent.status === Component.Error &&
          root.sessionComponent.errorString().indexOf('plugin "quickshell-coreplugin" not found') !== -1)
        return
      compare(root.sessionComponent.status, Component.Ready, root.sessionComponent.errorString())
    }
    function init() {
      if (root.sessionComponent.status !== Component.Ready) return
      session = createTemporaryObject(root.sessionComponent, root, { width: root.width, height: root.height, mode: "compose", autoStart: false })
      verify(session)
      completedSpy.target = session
      cancelledSpy.target = session
      failedSpy.target = session
      completedSpy.clear()
      cancelledSpy.clear()
      failedSpy.clear()
    }
    function test_startsOnlyWhenRequestedAndNeverFinishesUnverified() {
      if (!session) { skip("Quickshell plugins are built into qs; covered by the real-runtime Node test."); return }
      verify(!session.running)
      session.start()
      verify(session.running)
      session.finish()
      wait(10)
      compare(completedSpy.count, 0)
      verify(session.running)
      session.cancel()
      verify(session.closing)
      tryCompare(cancelledSpy, "count", 1)
      verify(!session.running)
      session.start()
      verify(!session.running, "Closed instances cannot restart stale callbacks")
    }
    function test_composeCompletionUnwindsBeforeParentMayUnload() {
      if (!session) { skip("Quickshell plugins are built into qs; covered by the real-runtime Node test."); return }
      session.start()
      session.focusPractice()
      var content = findChild(session, "practiceContent")
      var smile = findChild(content, "composeSmile")
      tryCompare(smile, "activeFocus", true)
      smile.text = "😄"
      findChild(content, "composeHeart").text = "❤️"
      verify(session.verified)
      session.finish()
      verify(session.closing)
      compare(completedSpy.count, 0)
      tryCompare(completedSpy, "count", 1)
      compare(cancelledSpy.count, 0)
      session.cancel()
      wait(10)
      compare(cancelledSpy.count, 0)
    }
    function test_lateLockObservationsCannotCompleteCancelledSession() {
      if (!session) { skip("Quickshell plugins are built into qs; covered by the real-runtime Node test."); return }
      session.start()
      var content = findChild(session, "practiceContent")
      content.busy = true
      session.lockObserved = true
      session.cancel()
      verify(session.closing)
      tryCompare(cancelledSpy, "count", 1)
      session.handleLockStatus(0, JSON.stringify({ locked: false, sessionLocked: false, secure: false }))
      verify(!session.verified)
      compare(completedSpy.count, 0)
    }
    function test_unsupportedModeFailsWithoutLaunchingAnything() {
      if (!session) { skip("Quickshell plugins are built into qs; covered by the real-runtime Node test."); return }
      session.mode = "unsupported"
      session.start()
      tryCompare(failedSpy, "count", 1)
      compare(cancelledSpy.count, 0)
      verify(failedSpy.signalArguments[0][0].indexOf("Unsupported") !== -1)
      verify(!session.taskPending && !session.capturePending && !session.lockPending)
    }
  }
}
