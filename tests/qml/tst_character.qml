import QtQuick
import QtTest
import "../../app" as App

Item {
  width: 400
  height: 320
  Item {
    id: host
    anchors.fill: parent
    App.CharacterSprite { id: sprite; anchors.centerIn: parent }
  }
  TestCase {
    name: "CharacterPresentation"
    when: windowShown
    function init() {
      host.visible = true
      host.opacity = 1
      sprite.animated = true
      sprite.reducedMotion = false
      sprite.previewFrame = -1
      sprite.pose = "idle"
      sprite.talking = false
      sprite.flying = false
      sprite.facing = 1
      sprite.landmarkFacing = 1
      sprite.pack = null
      sprite.resetPoseTransition()
    }
    function configure(name) {
      var request = new XMLHttpRequest()
      request.open("GET", Qt.resolvedUrl("../../assets/characters/" + name + "/character.json"), false)
      request.send()
      sprite.assetRoot = ""
      sprite.config = JSON.parse(request.responseText)
      sprite.assetRoot = Qt.resolvedUrl("../../assets/characters/" + name).toString()
      tryCompare(sprite, "errorMessage", "")
    }
    function test_presentation_data() { return [{ tag: "HEXON", name: "ohm-1" }, { tag: "OLLIE", name: "owl" }] }
    function test_presentation(data) {
      configure(data.name)
      var start = sprite.elapsed
      tryVerify(function() { return sprite.elapsed !== start })
      host.visible = false
      var hiddenFrame = sprite.elapsed
      wait(160)
      compare(sprite.elapsed, hiddenFrame)
      host.visible = true
      tryVerify(function() { return sprite.elapsed !== hiddenFrame })
      host.opacity = 0
      var transparentFrame = sprite.elapsed
      wait(160)
      compare(sprite.elapsed, transparentFrame)
      host.opacity = 1
      sprite.reducedMotion = true
      var reducedFrame = sprite.elapsed
      wait(160)
      compare(sprite.elapsed, reducedFrame)
      compare(sprite.currentFrame, 0)
      sprite.reducedMotion = false
      sprite.previewFrame = 3
      wait(160)
      compare(sprite.elapsed, reducedFrame)
      compare(sprite.currentFrame, 3)
      sprite.previewFrame = -1
      sprite.pose = "point"
      sprite.talking = true
      tryVerify(function() { return sprite.elapsed !== reducedFrame })
      verify(sprite.speechOverlay)
      compare(sprite.errorMessage, "")
    }

    function test_poseTransitions_data() {
      return [{ tag: "HEXON", name: "ohm-1" }, { tag: "OLLIE", name: "owl" }]
    }

    function test_poseTransitions(data) {
      configure(data.name)
      failOnWarning(/.*/)
      sprite.pose = "point-up"
      compare(sprite.previousPose, "idle")
      compare(sprite.poseBlend, 0)
      wait(90)
      verify(sprite.poseBlend > 0 && sprite.poseBlend < 1)
      tryCompare(sprite, "poseBlend", 1, 400)
      compare(sprite.previousPose, "")
      sprite.pose = "idle"
      compare(sprite.previousPose, "point-up")
      tryCompare(sprite, "poseBlend", 1, 400)
      sprite.flying = true
      sprite.facing = -1
      compare(sprite.previousPose, "idle")
      compare(sprite.previousFacing, 1)
      tryCompare(sprite, "poseBlend", 1, 400)
      sprite.flying = false
      sprite.pose = "point-up"
      compare(sprite.previousPose, "flight")
      tryCompare(sprite, "poseBlend", 1, 400)
      compare(sprite.errorMessage, "")
    }

    function test_flightFacingDoesNotMoveLandingLandmarks() {
      configure("ohm-1")
      sprite.landmarkFacing = -1
      var x = sprite.upTipX
      var y = sprite.upTipY
      sprite.flying = true
      sprite.facing = -1
      compare(sprite.upTipX, x)
      compare(sprite.upTipY, y)
      sprite.facing = 1
      compare(sprite.upTipX, x)
      compare(sprite.upTipY, y)
    }

    function test_staticModesDoNotLeaveHalfBlendedSprites() {
      configure("ohm-1")
      sprite.pose = "point"
      sprite.reducedMotion = true
      compare(sprite.poseBlend, 1)
      compare(sprite.previousPose, "")
      sprite.reducedMotion = false
      sprite.pose = "idle"
      sprite.previewFrame = 0
      compare(sprite.poseBlend, 1)
      sprite.previewFrame = -1
      sprite.pose = "point-up"
      sprite.animated = false
      compare(sprite.poseBlend, 1)
      compare(sprite.previousPose, "")
    }

    function test_thirdPackSingleFrameRolesDoNotAssumeOfficialStripLengths() {
      configure("ohm-1")
      var geometry = { frameWidth: 224, scale: 1, offset: { x: 0, y: 0 },
        tip: { x: 165, y: 75 } }
      var single = { path: "sprites/ohm-1-point.png", frameWidth: 224, frameHeight: 192, frames: 1 }
      sprite.config = {
        formatVersion: 1, id: "third-coach", displayName: "Third coach",
        sprites: { idle: single, talk: single, point: single, "point-up": single },
        effects: { thrusters: false },
        renderer: { baseline: 154, bodyAnchorX: 99,
          poses: { idle: geometry, point: geometry, "point-up": geometry } }
      }
      sprite.animated = false
      compare(sprite.frameCount, 1)
      compare(sprite.spriteSource("idle"), sprite.assetRoot + "/sprites/ohm-1-point.png")
      compare(sprite.flameSockets.length, 0)
      sprite.elapsed = 3100
      compare(sprite.currentFrame, 0)
      sprite.previewFrame = 12
      compare(sprite.currentFrame, 0)
      sprite.talking = true
      compare(sprite.frameCount, 1)
      compare(sprite.currentFrame, 0)
      sprite.pose = "point"
      compare(sprite.frameCount, 1)
      compare(sprite.speechOverlay, false)
      sprite.flying = true
      compare(sprite.isFlyingSprite, false)
      compare(sprite.errorMessage, "")
    }

    function test_metadataTimelinesAndRates() {
      configure("ohm-1")
      sprite.animated = false
      sprite.elapsed = 5199
      compare(sprite.currentFrame, 0)
      sprite.elapsed = 5200
      compare(sprite.currentFrame, 11)
      sprite.elapsed = 5250
      compare(sprite.currentFrame, 12)
      sprite.elapsed = 5350
      compare(sprite.currentFrame, 13)
      sprite.elapsed = 5400
      compare(sprite.currentFrame, 0)
      sprite.talking = true
      sprite.elapsed = 250
      compare(sprite.currentFrame, 2)
      sprite.pose = "point-up"
      sprite.elapsed = 300
      sprite.blinkElapsed = 5300
      compare(sprite.bodyName, "point-up-blink")
      verify(sprite.speechOverlay)
      compare(sprite.currentFrame, 3)
      sprite.reducedMotion = true
      compare(sprite.currentFrame, 0)
      compare(sprite.bodyName, "point-up")
      compare(sprite.frameAt({ frames: 3, fps: 5 }, 400), 2)
      compare(sprite.frameAt({ frames: 3, fps: 5 }, 600), 0)
      compare(sprite.frameAt({ frames: 2,
        timeline: [{ frame: 1, durationMs: 100 }, { frame: 0, durationMs: 200 }] }, 300), 1)
    }

    function test_invalidConfigurationReportsCanonicalContract() {
      sprite.config = { prefix: "legacy" }
      verify(sprite.errorMessage.indexOf("validated version 1") >= 0)
    }

    function test_chestSpeechNeverDrivesTheEyesOrRestartsTheirBlink() {
      configure("ohm-1")
      sprite.animated = false
      sprite.blinkElapsed = 1000
      compare(sprite.bodyName, "idle")
      compare(sprite.bodyFrame, 0)
      compare(sprite.speechFrame, 1)
      sprite.talking = true
      compare(sprite.blinkElapsed, 1000)
      for (var time = 0; time < 4000; time += 100) {
        sprite.elapsed = time
        compare(sprite.bodyName, "idle")
        compare(sprite.bodyFrame, 0)
      }
      sprite.blinkElapsed = 5250
      compare(sprite.bodyFrame, 12)
      sprite.talking = false
      compare(sprite.blinkElapsed, 5250)
      compare(sprite.bodyFrame, 12)
      compare(sprite.speechFrame, 1)
      sprite.pose = "point"
      compare(sprite.bodyName, "point-blink")
      sprite.talking = true
      compare(sprite.bodyName, "point-blink")
      compare(sprite.speech.destination.y, 92)
      compare(sprite.speech.destination.height, 13)
      sprite.reducedMotion = true
      compare(sprite.bodyName, "point")
      compare(sprite.speechFrame, 0)
      sprite.talking = false
      compare(sprite.speechFrame, 1)
      sprite.reducedMotion = false
      sprite.pose = "idle"
      sprite.previewFrame = 12
      compare(sprite.bodyFrame, 12)
      sprite.previewFrame = -1
      configure("owl")
      sprite.pose = "idle"
      sprite.talking = true
      compare(sprite.independentSpeech, false)
      compare(sprite.bodyName, "talk")
      compare(sprite.speechOverlay, false)
    }

    function test_atomicPackSwitchesKeepPathsAndDimensionsTogether() {
      configure("owl")
      var owl = { manifest: sprite.config, assetUrl: sprite.assetRoot }
      configure("ohm-1")
      var singleManifest = JSON.parse(JSON.stringify(sprite.config))
      singleManifest.id = "single-frame"
      singleManifest.sprites.idle = {
        path: "sprites/ohm-1-point.png", frameWidth: 224, frameHeight: 192, frames: 1
      }
      singleManifest.renderer.poses.idle = singleManifest.renderer.poses.point
      var single = { manifest: singleManifest, assetUrl: sprite.assetRoot }
      sprite.animated = false
      failOnWarning(/.*/)
      // Deliberately unusable legacy inputs prove that pack takes precedence.
      sprite.pack = owl
      sprite.config = ({})
      sprite.assetRoot = "file:///not-a-character-pack"
      for (var i = 0; i < 20; i++) {
        var selected = i % 2 ? owl : single
        sprite.pack = selected
        compare(sprite.frameCount, i % 2 ? 16 : 1)
        compare(sprite.bodySprite.frameWidth, i % 2 ? 192 : 224)
        compare(sprite.spriteSource("idle"), selected.assetUrl + "/" + selected.manifest.sprites.idle.path)
        compare(sprite.previousPose, "")
        compare(sprite.errorMessage, "")
        wait(1)
        compare(sprite.errorMessage, "")
      }
      configure("ohm-1")
    }
  }
}
