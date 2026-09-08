import QtQuick
import QtTest
import "../../app" as App

Item {
    width: 1200
    height: 800
    App.SplashScreen {
        id: splash
        width: 1200
        height: 800
        displayDuration: 80
    }
    SignalSpy { id: finished; target: splash; signalName: "finished" }
    TestCase {
        name: "StartupSplash"
        when: windowShown
        function init() {
            splash.active = false
            splash.ready = false
            splash.reducedMotion = false
            finished.clear()
        }
        function test_waitsForReadinessAndFinishesOnce() {
            splash.active = true
            wait(120)
            compare(finished.count, 0)
            splash.ready = true
            compare(finished.count, 1)
            splash.dismiss()
            splash.ready = false
            splash.ready = true
            compare(finished.count, 1)
        }
        function test_dismissalAndReducedMotionDoNotAddADelay() {
            splash.ready = true
            splash.active = true
            splash.dismiss()
            compare(finished.count, 1)
            splash.active = false
            finished.clear()
            splash.reducedMotion = true
            splash.active = true
            compare(finished.count, 1)
        }
        function test_cancellationDoesNotFireLater() {
            splash.active = true
            splash.active = false
            splash.ready = true
            wait(120)
            compare(finished.count, 0)
        }
        function test_artworkFitsSmallAndPortraitScreens() {
            splash.width = 460
            splash.height = 700
            splash.active = true
            var images = splash.children.filter(function(child) { return "fillMode" in child })
            compare(images.length, 1)
            var image = images[0]
            verify(image.x >= 0 && image.y >= 0)
            verify(image.x + image.width <= splash.width)
            verify(image.y + image.height <= splash.height)
        }
    }
}
