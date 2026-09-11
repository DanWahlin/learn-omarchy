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
        fadeDuration: 160
    }
    SignalSpy { id: finished; target: splash; signalName: "finished" }
    SignalSpy { id: failed; target: splash; signalName: "imageFailed" }
    TestCase {
        name: "StartupSplash"
        when: windowShown
        function init() {
            splash.active = false
            splash.ready = false
            splash.reducedMotion = false
            splash.source = Qt.resolvedUrl("../../assets/splash/learn-omarchy-poster.png")
            splash.width = 1200
            splash.height = 800
            finished.clear()
            failed.clear()
        }
        function test_waitsForReadinessAndFinishesOnce() {
            splash.active = true
            wait(120)
            compare(finished.count, 0)
            splash.ready = true
            compare(finished.count, 0)
            verify(splash.transitioning)
            tryCompare(finished, "count", 1)
            splash.dismiss()
            splash.ready = false
            splash.ready = true
            compare(finished.count, 1)
        }
        function test_dismissalFadesButReducedMotionDoesNotAddADelay() {
            splash.ready = true
            splash.active = true
            splash.dismiss()
            compare(finished.count, 0)
            tryCompare(finished, "count", 1)
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
        function test_fadeRetainsTheSplashUntilItsOpacityReachesZero() {
            splash.ready = true
            splash.active = true
            splash.dismiss()
            wait(60)
            verify(splash.opacity > 0 && splash.opacity < 1)
            verify(splash.visible)
            compare(finished.count, 0)
            splash.dismiss()
            tryCompare(finished, "count", 1)
            compare(splash.opacity, 0)
        }
        function test_cancellationDuringFadeDoesNotFinishAndReplayResetsOpacity() {
            splash.ready = true
            splash.active = true
            splash.dismiss()
            wait(40)
            splash.active = false
            wait(180)
            compare(finished.count, 0)
            splash.active = true
            compare(splash.opacity, 1)
            verify(!splash.transitioning)
        }
        function test_enablingReducedMotionFinishesAnActiveFadeOnce() {
            splash.ready = true
            splash.active = true
            splash.dismiss()
            verify(splash.transitioning)
            splash.reducedMotion = true
            compare(finished.count, 1)
            verify(!splash.transitioning)
            wait(180)
            compare(finished.count, 1)
        }
        function test_artworkFitsWithoutCropping_data() {
            return [
                {tag:"portrait", w:460, h:700},
                {tag:"laptop", w:1280, h:720},
                {tag:"desktop", w:1920, h:1200},
                {tag:"wide", w:2560, h:1440},
                {tag:"short", w:640, h:320}
            ]
        }
        function test_artworkFitsWithoutCropping(data) {
            failOnWarning(/.*/)
            splash.width = data.w
            splash.height = data.h
            splash.active = true
            var image = findChild(splash, "splashArtwork")
            verify(image !== null)
            tryCompare(image, "artworkReady", true)
            verify(image.x >= 0 && image.y >= 0)
            verify(image.x + image.width <= splash.width)
            verify(image.y + image.height <= splash.height - 64)
            verify(image.paintedWidth <= image.width + 1)
            verify(image.paintedHeight <= image.height + 1)
            verify(Math.abs(image.paintedWidth / image.paintedHeight - 1.5) < 0.001)
            compare(image.fillMode, Image.PreserveAspectFit)
        }
        function test_illustratedBrandingUsesTheAvailableScreen() {
            failOnWarning(/.*/)
            splash.active = true
            var art = findChild(splash, "splashArtwork")
            tryCompare(art, "artworkReady", true)
            verify(art.source.toString().endsWith("/assets/splash/learn-omarchy-poster.png"))
            verify(art.paintedHeight > splash.height * 0.9)
            verify(art.paintedWidth > splash.width * 0.9)
            compare(art.smooth, true)
            compare(art.mipmap, true)
            compare(splash.color.toString(), "#020c1a")
            verify(!findChild(splash, "splashFallback").visible)
        }
        function test_assetFailureShowsFallbackAndRecoversWithoutABindingLoop() {
            failOnWarning(/.*/)
            splash.active = true
            var art = findChild(splash, "splashArtwork")
            tryCompare(art, "artworkReady", true)
            ignoreWarning(/.*Cannot open:.*missing-splash-regression\.png/)
            splash.source = Qt.resolvedUrl("../../assets/splash/missing-splash-regression.png")
            tryCompare(failed, "count", 1)
            verify(art.artworkError.indexOf("Cannot load splash illustration") >= 0)
            verify(findChild(splash, "splashFallback").visible)
            splash.ready = true
            splash.dismiss()
            tryCompare(finished, "count", 1)
            splash.source = Qt.resolvedUrl("../../assets/splash/learn-omarchy-poster.png")
            tryCompare(art, "artworkReady", true)
            for (var active of [false, true, false, true]) {
                splash.active = active
                wait(20)
            }
            compare(art.artworkError, "")
            compare(failed.count, 1)
        }
    }
}
