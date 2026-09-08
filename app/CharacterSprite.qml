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
  property var pack: null
  property string pose: "idle"
  property bool talking: false
  property bool flying: false
  property int facing: 1
  property int landmarkFacing: facing
  property bool reducedMotion: false
  property bool animated: true
  property int previewFrame: -1
  property bool showLandmarks: false

  readonly property var manifest: pack ? pack.manifest : config
  readonly property string assetDirectory: pack ? pack.assetUrl : assetRoot
  readonly property var registration: manifest.renderer || ({})
  readonly property var poses: registration.poses || ({})
  readonly property var sprites: manifest.sprites || ({})
  readonly property bool isFlyingSprite: flying && !!sprites.flight
  readonly property string activePose: isFlyingSprite ? "flight" : pose
  readonly property var geometry: poses[activePose] || ({})
  readonly property var speech: geometry.speech || null
  readonly property bool pointing: activePose === "point" || activePose === "point-up"
  readonly property bool independentSpeech: !!poses.idle?.speech
  readonly property bool speechOverlay: !isFlyingSprite && speech !== null && (talking || speech.restFrame !== undefined)
  readonly property string speechRole: speech && speech.sprite ? speech.sprite : "talk"
  readonly property string animationRole: isFlyingSprite ? "flight"
    : speechOverlay && talking ? speechRole : talking && !pointing ? "talk" : activePose
  readonly property var animationSprite: sprites[animationRole] || ({})
  readonly property int frameCount: Math.max(1, Number(animationSprite.frames || 1))
  readonly property int currentFrame: previewFrame >= 0 ? Math.min(frameCount - 1, previewFrame)
    : reducedMotion ? 0
    : frameAt(animationSprite, elapsed)
  readonly property var blink: manifest.blink || ({})
  readonly property int blinkPhase: (independentSpeech ? blinkElapsed : elapsed) % Math.max(1, Number(blink.periodMs || 1))
  readonly property bool blinking: pointing && (!talking || speechOverlay)
    && previewFrame < 0 && !reducedMotion && !!manifest.blink
    && blinkPhase >= Number(blink.startMs)
    && blinkPhase < Number(blink.startMs) + Number(blink.durationMs)
  readonly property string bodyName: isFlyingSprite ? "flight"
    : pointing ? activePose + (blinking && sprites[activePose + "-blink"] ? "-blink" : "")
    : talking && !speechOverlay ? "talk" : "idle"
  readonly property var bodySprite: sprites[bodyName] || ({})
  readonly property int bodyFrame: speechOverlay ? (previewFrame >= 0 && !talking
      ? Math.min(Number(bodySprite.frames || 1) - 1, previewFrame)
      : frameAt(bodySprite, reducedMotion || previewFrame >= 0 ? 0 : independentSpeech ? blinkElapsed : elapsed))
    : Math.min(Number(bodySprite.frames || 1) - 1, currentFrame)
  readonly property bool animationActive: visible && opacity > 0 && animated
    && !reducedMotion && previewFrame < 0 && !errorMessage
    && (!isFlyingSprite || frameCount > 1)
  readonly property string errorMessage: !assetDirectory || manifest.formatVersion !== 1 || !manifest.id || !manifest.sprites
    ? "Character assets are not configured with a validated version 1 pack"
    : !poses[activePose] ? "Missing pose registration: " + activePose
    : !sprites[bodyName] ? "Missing sprite role: " + bodyName
    : speechOverlay && !sprites[speechRole] ? "Missing speech sprite role: " + speechRole
    : body.status === Image.Error ? "Cannot load sprite: " + body.source
    : speechOverlay && mouth.status === Image.Error ? "Cannot load speech sprite: " + mouth.source
    : ""
  readonly property real pointTipX: tip("point", "x")
  readonly property real pointTipY: tip("point", "y")
  readonly property real upTipX: tip("point-up", "x")
  readonly property real upTipY: tip("point-up", "y")
  // Flight artwork already contains exhaust. Other sockets follow the same
  // registration and facing transform as the body, in canvas-local pixels.
  readonly property var flameSockets: !manifest.effects?.thrusters || isFlyingSprite ? []
    : (geometry.flameSockets || []).map(function(socket) {
      return { x: registeredCoordinate(geometry, socket, "x"),
        y: registeredCoordinate(geometry, socket, "y") }
    })
  property real elapsed: 0
  property real blinkElapsed: 0
  readonly property int speechFrame: !talking && speech && speech.restFrame !== undefined ? speech.restFrame : currentFrame
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
    if (!poses || !poses[previousPose] || !animated || reducedMotion || previewFrame >= 0 || !visible) {
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
    // Read path and root from one catalog entry: separately bound legacy
    // properties can otherwise briefly combine different packs on selection.
    var selected = pack
    var metadata = selected ? selected.manifest : config
    var directory = selected ? selected.assetUrl : assetRoot
    var sprite = metadata.sprites ? metadata.sprites[name] : null
    return directory && sprite ? directory + "/" + sprite.path.split("/").map(encodeURIComponent).join("/") : ""
  }

  function frameAt(sprite, time) {
    var count = Math.max(1, Number(sprite.frames || 1))
    var timeline = sprite.timeline || []
    if (timeline.length) {
      var duration = timeline.reduce(function(total, entry) { return total + entry.durationMs }, 0)
      var position = time % duration
      for (var i = 0; i < timeline.length; i++) {
        position -= timeline[i].durationMs
        if (position < 0) return Math.min(count - 1, timeline[i].frame)
      }
    }
    return Math.floor(time * Number(sprite.fps || 0) / 1000) % count
  }

  onPackChanged: { elapsed = 0; blinkElapsed = 0; resetPoseTransition() }
  onConfigChanged: if (!pack) { elapsed = 0; blinkElapsed = 0; resetPoseTransition() }
  onAssetRootChanged: if (!pack) resetPoseTransition()
  onActivePoseChanged: { elapsed = 0; transitionPose() }
  onFacingChanged: transitionPose()
  onTalkingChanged: elapsed = 0
  onReducedMotionChanged: { elapsed = 0; blinkElapsed = 0; resetPoseTransition() }
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
      if (root.isPresented()) {
        root.elapsed += interval
        root.blinkElapsed += interval
      }
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
      width: Number(root.sprites[root.previousPose]?.frameWidth || 224)
      height: Number(root.sprites[root.previousPose]?.frameHeight || 192)
      scale: Number(root.previousGeometry.scale || 1)
      transformOrigin: Item.TopLeft
      source: parent.visible ? root.spriteSource(root.previousPose) : ""
      sourceClipRect: Qt.rect(0, 0, width, height)
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
        width: Number(root.bodySprite.frameWidth || 224)
        height: Number(root.bodySprite.frameHeight || 192)
        source: root.spriteSource(root.bodyName)
        sourceClipRect: Qt.rect(root.bodyFrame * width, 0, width, height)
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
        source: visible ? root.spriteSource(root.speechRole) : ""
        sourceClipRect: root.speech
          ? Qt.rect(root.speechFrame * Number(root.sprites[root.speechRole]?.frameWidth || 1) + root.speech.source.x,
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
      y: Number(root.registration.baseline ?? 190)
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
      x: (root.facing < 0 ? 224 - Number(root.registration.bodyAnchorX ?? 112)
        : Number(root.registration.bodyAnchorX ?? 112)) - 1
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
