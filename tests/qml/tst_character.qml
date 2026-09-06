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
    function test_presentation_data() { return [{ tag: "HEXON", name: "hexon" }, { tag: "OLLIE", name: "owl" }] }
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
      return [{ tag: "HEXON", name: "hexon" }, { tag: "OLLIE", name: "owl" }]
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
      configure("hexon")
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
      configure("hexon")
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
  }
}
