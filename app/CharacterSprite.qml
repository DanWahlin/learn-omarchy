pragma ComponentBehavior: Bound
import QtQuick

// All geometry is expressed in the nominal 224 x 192 canvas. Scale the item,
// rather than its width/height, when embedding it at another presentation size.
Item {
  id: root
  implicitWidth: 224
  implicitHeight: 192
  width: implicitWidth
  height: implicitHeight

  property string assetRoot: ""
  property var config: ({})
  property string pose: "idle"
  property bool talking: false
  property bool flying: false
  property int facing: 1
  property int landmarkFacing: facing
  property bool reducedMotion: false
  property bool animated: true
  property int previewFrame: -1
  property bool showLandmarks: false

  readonly property var registration: config.renderer || ({})
  readonly property var poses: registration.poses || ({})
  readonly property bool isFlyingSprite: flying && Number(config.flightFrames || 0) > 0
  readonly property string activePose: isFlyingSprite ? "flight" : pose
  readonly property var geometry: poses[activePose] || ({})
  readonly property var speech: geometry.speech || null
  readonly property bool pointing: activePose === "point" || activePose === "point-up"
  readonly property bool speechOverlay: talking && pointing && speech !== null
  readonly property int frameCount: isFlyingSprite ? Math.max(1, Number(config.flightFrames))
    : talking && (!pointing || speechOverlay) ? 8 : pointing ? 2 : 16
  readonly property int currentFrame: previewFrame >= 0 ? Math.min(frameCount - 1, previewFrame)
    : reducedMotion ? 0
    : isFlyingSprite ? Math.floor(elapsed * Number(config.flightFrameRate || 1) / 1000) % frameCount
    : talking ? Math.floor(elapsed / 125) % frameCount
    : pointing ? (blinkPhase >= 3050 && blinkPhase < 3150 ? 1 : 0)
    : blinkPhase < 3000 ? 0 : blinkPhase < 3050 ? 11 : blinkPhase < 3150 ? 12 : 13
  readonly property int blinkPhase: elapsed % 3200
  readonly property bool blinking: pointing && (!talking || speechOverlay)
    && (previewFrame >= 0 ? !talking && currentFrame === 1
      : !reducedMotion && blinkPhase >= 3050 && blinkPhase < 3150)
  readonly property string bodyName: isFlyingSprite ? "flight"
    : pointing ? activePose + (blinking && config.pointBlink ? "-blink" : "")
    : talking ? "talk" : "idle"
  readonly property int bodyFrame: pointing ? 0 : currentFrame
  readonly property bool animationActive: visible && opacity > 0 && animated
    && !reducedMotion && previewFrame < 0 && !errorMessage
    && (!isFlyingSprite || frameCount > 1)
  readonly property string errorMessage: !assetRoot || !config.prefix ? "Character assets are not configured"
    : !poses[activePose] ? "Missing pose registration: " + activePose
    : body.status === Image.Error ? "Cannot load sprite: " + body.source
    : speechOverlay && mouth.status === Image.Error ? "Cannot load speech sprite: " + mouth.source
    : ""
  readonly property real pointTipX: tip("point", "x")
  readonly property real pointTipY: tip("point", "y")
  readonly property real upTipX: tip("point-up", "x")
  readonly property real upTipY: tip("point-up", "y")
  // Flight artwork already contains exhaust. Other sockets follow the same
  // registration and facing transform as the body, in canvas-local pixels.
  readonly property var flameSockets: config.flames === false || isFlyingSprite ? []
    : (geometry.flameSockets || []).map(function(socket) {
      return { x: registeredCoordinate(geometry, socket, "x"),
        y: registeredCoordinate(geometry, socket, "y") }
    })
  property int elapsed: 0
  property string displayedPose: ""
  property int displayedFacing: 1
  property string previousPose: ""
  property int previousFacing: 1
  property real poseBlend: 1
  readonly property var previousGeometry: poses[previousPose] || ({})

  function resetPoseTransition() {
    poseTransition.stop()
    displayedPose = activePose
    displayedFacing = facing
    previousPose = ""
    poseBlend = 1
  }

  function transitionPose() {
    if (displayedPose === activePose && displayedFacing === facing) return
    var keepOutgoingPose = poseTransition.running && poseBlend === 0
    poseTransition.stop()
    if (!keepOutgoingPose) {
      previousPose = displayedPose
      previousFacing = displayedFacing
    }
    displayedPose = activePose
    displayedFacing = facing
    if (!poses[previousPose] || !animated || reducedMotion || previewFrame >= 0 || !visible) {
      resetPoseTransition()
      return
    }
    poseBlend = 0
    poseTransition.restart()
  }

  function isPresented() {
    for (var item = root; item; item = item.parent) {
      if (!item.visible || item.opacity <= 0) return false
    }
    return root.Window.window !== null && root.Window.window.visible
  }

  function tip(name, axis) {
    var p = poses[name]
    if (!p || !p.tip) return 0
    return registeredCoordinate(p, p.tip, axis, landmarkFacing)
  }

  function registeredCoordinate(p, point, axis, direction) {
    var value = Number(p.offset[axis]) + Number(point[axis]) * Number(p.scale)
    var mirrored = (direction === undefined ? facing : direction) < 0
    return axis === "x" && mirrored ? 224 - value : value
  }

  function spriteSource(name) {
    return assetRoot && config.prefix ? assetRoot + "/sprites/" + config.prefix + "-" + name + ".png" : ""
  }

  onConfigChanged: { elapsed = 0; resetPoseTransition() }
  onAssetRootChanged: resetPoseTransition()
  onActivePoseChanged: { elapsed = 0; transitionPose() }
  onFacingChanged: transitionPose()
  onTalkingChanged: elapsed = 0
  onReducedMotionChanged: { elapsed = 0; resetPoseTransition() }
  onAnimatedChanged: if (!animated) resetPoseTransition()
  onPreviewFrameChanged: if (previewFrame >= 0) resetPoseTransition()
  onVisibleChanged: if (!visible) resetPoseTransition()
  Component.onCompleted: resetPoseTransition()

  NumberAnimation {
    id: poseTransition
    target: root
    property: "poseBlend"
    to: 1
    duration: 220
    easing.type: Easing.InOutSine
    onFinished: root.previousPose = ""
  }

  Timer {
    interval: 50
    repeat: true
    running: root.animationActive
    onTriggered: {
      // Ancestor visibility can be reentrant during layer construction.
      // Inspect it on a frame instead of binding the timer to the whole tree.
      if (root.isPresented()) root.elapsed = (root.elapsed + interval) % 96000
    }
  }

  // A frozen outgoing pose bridges the silhouette change without restarting
  // its blink, speech, or wing animation during the transition.
  Item {
    width: 224
    height: 192
    visible: root.previousPose !== "" && root.poseBlend < 1
    opacity: 1 - root.poseBlend
    transform: Scale { origin.x: 112; xScale: root.previousFacing < 0 ? -1 : 1 }
    Image {
      x: Number(root.previousGeometry.offset?.x || 0)
      y: Number(root.previousGeometry.offset?.y || 0)
      width: Number(root.previousGeometry.frameWidth || 224)
      height: 192
      scale: Number(root.previousGeometry.scale || 1)
      transformOrigin: Item.TopLeft
      source: parent.visible ? root.spriteSource(root.previousPose) : ""
      sourceClipRect: Qt.rect(0, 0, width, 192)
      smooth: false
      mipmap: false
    }
  }

  Item {
    width: 224
    height: 192
    opacity: root.poseBlend
    transform: Scale { origin.x: 112; xScale: root.facing < 0 ? -1 : 1 }

    Item {
      x: Number(root.geometry.offset?.x || 0)
      y: Number(root.geometry.offset?.y || 0)
      scale: Number(root.geometry.scale || 1)
      transformOrigin: Item.TopLeft

      Image {
        id: body
        width: Number(root.geometry.frameWidth || 224)
        height: 192
        source: root.spriteSource(root.bodyName)
        sourceClipRect: Qt.rect(root.bodyFrame * width, 0, width, 192)
        smooth: false
        mipmap: false
        asynchronous: false
        cache: true
      }

      Image {
        id: mouth
        visible: root.speechOverlay
        x: root.speech ? root.speech.destination.x : 0
        y: root.speech ? root.speech.destination.y : 0
        width: root.speech ? root.speech.destination.width : 0
        height: root.speech ? root.speech.destination.height : 0
        source: visible ? root.spriteSource(root.speech.sprite || "talk") : ""
        sourceClipRect: root.speech
          ? Qt.rect(root.currentFrame * Number(root.speech.frameWidth || 192) + root.speech.source.x,
            root.speech.source.y, root.speech.source.width, root.speech.source.height)
          : Qt.rect(0, 0, 1, 1)
        smooth: false
        mipmap: false
      }
    }
  }

  Item {
    anchors.fill: parent
    visible: root.showLandmarks
    Rectangle {
      anchors.fill: parent
      color: "transparent"
      border.color: "#808080"
    }
    Rectangle {
      x: 0
      y: Number(root.registration.baseline || 190)
      width: 224
      height: 1
      color: "#33ccff"
    }
    Repeater {
      model: [
        { x: root.pointTipX, y: root.pointTipY, color: "#ff5577" },
        { x: root.upTipX, y: root.upTipY, color: "#55ff99" }
      ]
      delegate: Item {
        id: marker
        required property var modelData
        x: modelData.x
        y: modelData.y
        Rectangle { x: -5; y: -1; width: 11; height: 2; color: marker.modelData.color }
        Rectangle { x: -1; y: -5; width: 2; height: 11; color: marker.modelData.color }
      }
    }
    Rectangle {
      x: (root.facing < 0 ? 224 - Number(root.registration.bodyAnchorX || 112)
        : Number(root.registration.bodyAnchorX || 112)) - 1
      width: 1
      height: 192
      color: "#33ccff"
    }
    Repeater {
      model: root.flameSockets
      delegate: Rectangle {
        required property var modelData
        x: modelData.x - 2
        y: modelData.y - 2
        width: 4
        height: 4
        color: "#ffaa33"
      }
    }
  }
}
