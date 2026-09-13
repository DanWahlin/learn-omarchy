pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

Rectangle {
  id: root
  required property var arcade
  property int completedActions: 0
  readonly property var mission: arcade.rescueMission
  readonly property var sceneState: buildSceneState()
  readonly property int activeWorkspace: sceneState.workspace
  readonly property string desktopState: sceneState.status
  readonly property var terminalWindow: windowForKind("terminal")
  readonly property int terminalWorkspace: terminalWindow ? terminalWindow.workspace : 0
  readonly property bool terminalVisible: windowIsVisible(terminalWindow)
  readonly property bool floating: !!terminalWindow && terminalWindow.mode === "floating"
  readonly property bool fullscreen: !!terminalWindow && terminalWindow.mode === "fullscreen"
  readonly property int visibleWindowCount: visibleWindows(sceneState).length
  readonly property string currentAction: arcade.currentRescueStep ? arcade.currentRescueStep.action : ""
  readonly property string ghostKind: currentAction === "launch-terminal" ? "terminal"
    : currentAction === "launch-browser" ? "browser"
    : currentAction === "launch-files" ? "files" : ""
  readonly property bool ghostRequested: ghostKind !== "" && !arcade.responsePending
  readonly property var ghostGeometry: ghostRect()
  implicitHeight: Math.max(164, 156 * arcade.textScale)
  radius: 12
  color: Qt.tint(arcade.surfaceColor,
    Qt.rgba(arcade.modeAccent.r, arcade.modeAccent.g, arcade.modeAccent.b, 0.08))
  border.color: Qt.tint(arcade.surfaceColor,
    Qt.rgba(arcade.modeAccent.r, arcade.modeAccent.g, arcade.modeAccent.b, 0.42))
  border.width: 2
  clip: true
  Accessible.role: Accessible.Grouping
  Accessible.name: "Simulated desktop. " + desktopState

  function freshState() {
    return {
      workspace: 1,
      previousWorkspace: 1,
      split: "vertical",
      focusId: "",
      scratchpadVisible: false,
      windows: [],
      status: mission ? mission.initialLabel : "Simulated desktop ready"
    }
  }

  function appKind(action) {
    return action === "launch-browser" ? "browser" : action === "launch-files" ? "files" : "terminal"
  }

  function appTitle(kind) {
    return kind === "browser" ? "Browser" : kind === "files" ? "Files" : "Terminal"
  }

  function windowForId(state, id) {
    for (var i = 0; i < state.windows.length; i++)
      if (state.windows[i].id === id) return state.windows[i]
    return null
  }

  function windowForKind(kind) {
    for (var i = 0; i < sceneState.windows.length; i++)
      if (sceneState.windows[i].kind === kind) return sceneState.windows[i]
    return null
  }

  function windowIsVisible(windowData) {
    return !!windowData && (windowData.workspace === activeWorkspace
      || (windowData.workspace === 0 && sceneState.scratchpadVisible))
  }

  function visibleWindows(state) {
    return state.windows.filter(function(windowData) {
      return windowData.workspace === state.workspace
        || (windowData.workspace === 0 && state.scratchpadVisible)
    })
  }

  function ghostRect() {
    var tiled = workspaceWindows(sceneState, activeWorkspace, true)
    if (tiled.length === 1 && sceneState.split === "vertical")
      return { x: 0.51, y: 0.04, width: 0.47, height: 0.92 }
    if (tiled.length === 1)
      return { x: 0.02, y: 0.52, width: 0.96, height: 0.44 }
    return { x: 0.02, y: 0.04, width: 0.96, height: 0.92 }
  }

  function workspaceWindows(state, workspace, tiledOnly) {
    return state.windows.filter(function(windowData) {
      return windowData.workspace === workspace && (!tiledOnly || windowData.mode === "tiled")
    })
  }

  function setRect(windowData, x, y, width, height) {
    windowData.x = x
    windowData.y = y
    windowData.width = width
    windowData.height = height
  }

  function retile(state, workspace) {
    var tiled = workspaceWindows(state, workspace, true)
    if (tiled.length === 1) {
      setRect(tiled[0], 0.02, 0.04, 0.96, 0.92)
    } else if (tiled.length >= 2 && state.split === "vertical") {
      setRect(tiled[0], 0.02, 0.04, 0.47, 0.92)
      setRect(tiled[1], 0.51, 0.04, 0.47, 0.92)
    } else if (tiled.length >= 2) {
      setRect(tiled[0], 0.02, 0.04, 0.96, 0.44)
      setRect(tiled[1], 0.02, 0.52, 0.96, 0.44)
    }
  }

  function focusFallback(state) {
    var visible = visibleWindows(state)
    state.focusId = visible.length ? visible[visible.length - 1].id : ""
  }

  function addApp(state, action) {
    var kind = appKind(action)
    var windowData = {
      id: kind + "-" + state.windows.length,
      kind: kind,
      title: appTitle(kind),
      workspace: state.workspace,
      mode: "tiled",
      x: 0.02, y: 0.04, width: 0.96, height: 0.92
    }
    state.windows.push(windowData)
    state.focusId = windowData.id
    retile(state, state.workspace)
  }

  function switchWorkspace(state, workspace) {
    state.previousWorkspace = state.workspace
    state.workspace = workspace
    focusFallback(state)
  }

  function applyAction(state, action) {
    if (action === "launch-terminal" || action === "launch-browser" || action === "launch-files") {
      addApp(state, action)
      return
    }

    var focused = windowForId(state, state.focusId)
    if (action === "close-window") {
      if (focused) {
        var workspace = focused.workspace
        state.windows = state.windows.filter(function(windowData) { return windowData.id !== focused.id })
        if (workspace > 0) retile(state, workspace)
      }
      focusFallback(state)
    } else if (action === "float" && focused) {
      focused.mode = focused.mode === "floating" ? "tiled" : "floating"
      if (focused.mode === "floating") {
        setRect(focused, 0.22, 0.12, 0.56, 0.76)
        retile(state, focused.workspace)
      }
      else retile(state, focused.workspace)
    } else if (action === "widen" && focused) {
      focused.mode = "floating"
      setRect(focused, 0.12, 0.12, 0.76, 0.76)
    } else if (action === "narrow" && focused) {
      focused.mode = "floating"
      setRect(focused, 0.27, 0.12, 0.46, 0.76)
    } else if (action === "fullscreen" && focused) {
      focused.mode = focused.mode === "fullscreen" ? "tiled" : "fullscreen"
      if (focused.mode === "fullscreen") setRect(focused, 0, 0, 1, 1)
      else retile(state, focused.workspace)
    } else if (action === "send-workspace-2" && focused) {
      var sourceWorkspace = focused.workspace
      focused.workspace = 2
      state.previousWorkspace = state.workspace
      state.workspace = 2
      retile(state, sourceWorkspace)
      if (focused.mode === "tiled") retile(state, 2)
      state.focusId = focused.id
    } else if (action === "workspace-1") {
      switchWorkspace(state, 1)
    } else if (action === "workspace-2") {
      switchWorkspace(state, 2)
    } else if (action === "last-workspace") {
      var destination = state.previousWorkspace
      state.previousWorkspace = state.workspace
      state.workspace = destination
      focusFallback(state)
    } else if (action === "next-workspace") {
      switchWorkspace(state, Math.min(2, state.workspace + 1))
    } else if (action === "previous-workspace") {
      switchWorkspace(state, Math.max(1, state.workspace - 1))
    } else if (action === "cycle-focus") {
      var visible = visibleWindows(state)
      if (visible.length) {
        var current = visible.indexOf(focused)
        state.focusId = visible[(current + 1 + visible.length) % visible.length].id
      }
    } else if (action === "swap-right" && focused) {
      var tiled = workspaceWindows(state, state.workspace, true)
      if (tiled.length > 1) {
        var first = state.windows.indexOf(tiled[0])
        var second = state.windows.indexOf(tiled[1])
        var held = state.windows[first]
        state.windows[first] = state.windows[second]
        state.windows[second] = held
        retile(state, state.workspace)
      }
    } else if (action === "toggle-split") {
      state.split = state.split === "vertical" ? "horizontal" : "vertical"
      retile(state, state.workspace)
    } else if (action === "stash-window" && focused) {
      var oldWorkspace = focused.workspace
      focused.workspace = 0
      focused.mode = "scratchpad"
      setRect(focused, 0.2, 0.12, 0.6, 0.76)
      state.scratchpadVisible = false
      retile(state, oldWorkspace)
      focusFallback(state)
    } else if (action === "toggle-scratchpad") {
      state.scratchpadVisible = !state.scratchpadVisible
      var scratchpads = workspaceWindows(state, 0, false)
      if (state.scratchpadVisible && scratchpads.length)
        state.focusId = scratchpads[scratchpads.length - 1].id
      else focusFallback(state)
    } else if (action === "focus-right") {
      var candidates = visibleWindows(state)
      if (candidates.length) {
        var rightmost = candidates[0]
        for (var i = 1; i < candidates.length; i++)
          if (candidates[i].x > rightmost.x) rightmost = candidates[i]
        state.focusId = rightmost.id
      }
    }
  }

  function buildSceneState() {
    var state = freshState()
    if (!mission || !Array.isArray(mission.steps)) return state
    var count = Math.min(completedActions, mission.steps.length)
    for (var i = 0; i < count; i++) {
      applyAction(state, mission.steps[i].action)
      state.status = mission.steps[i].label
    }
    if (!arcade.responsePending && count > 0) {
      var settled = mission.steps[count - 1]
      if (settled.settledWorkspace !== undefined) switchWorkspace(state, settled.settledWorkspace)
      if (settled.settledLabel) state.status = settled.settledLabel
    }
    return state
  }

  Rectangle {
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: 50
    color: Qt.tint(root.arcade.surfaceColor,
      Qt.rgba(root.arcade.modeAccent.r, root.arcade.modeAccent.g, root.arcade.modeAccent.b, 0.1))
    opacity: 0.78
  }

  Rectangle {
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.margins: 7
    width: 3
    radius: 2
    color: root.arcade.modeAccent
    opacity: 0.24
  }

  Rectangle {
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.margins: 7
    width: 3
    radius: 2
    color: root.arcade.modeAccent
    opacity: 0.24
  }

  RowLayout {
    id: topbar
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.margins: 12
    spacing: 8
    Repeater {
      model: 2
      Rectangle {
        required property int index
        width: 34
        height: 28
        radius: 5
        color: root.activeWorkspace === index + 1 ? root.arcade.modeAccent : root.arcade.surfaceColor
        border.color: root.arcade.lineColor
        Text {
          anchors.centerIn: parent
          text: String(parent.index + 1)
          color: root.activeWorkspace === parent.index + 1
            ? root.arcade.modeButtonInk : root.arcade.mutedColor
          font.pixelSize: 12 * root.arcade.fontScale
        }
      }
    }
    Text {
      Layout.fillWidth: true
      text: root.mission ? "NAV CONSOLE · " + root.mission.callsign
        + " · " + root.mission.title.toUpperCase() : "NAV CONSOLE · SIMULATED DESKTOP"
      color: root.arcade.mutedColor
      font.pixelSize: 10 * root.arcade.fontScale
      font.weight: Font.Bold
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideRight
    }
  }

  Item {
    id: desktop
    anchors.top: topbar.bottom
    anchors.bottom: status.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.margins: 10

    Repeater {
      model: 5
      Rectangle {
        required property int index
        x: desktop.width * (index + 1) / 6
        width: 1
        height: desktop.height
        color: Qt.rgba(root.arcade.modeAccent.r, root.arcade.modeAccent.g,
          root.arcade.modeAccent.b, 0.035)
      }
    }

    Text {
      anchors.centerIn: parent
      width: parent.width - 24
      visible: root.visibleWindowCount === 0 && !root.ghostRequested
      text: root.sceneState.windows.length
        ? "This workspace is clear.\nYour other windows are still safe."
        : "This workspace is ready."
      color: root.arcade.mutedColor
      font.pixelSize: 13 * root.arcade.fontScale
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
    }

    Rectangle {
      id: ghostWindow
      objectName: "rescueGhostWindow"
      x: desktop.width * root.ghostGeometry.x
      y: desktop.height * root.ghostGeometry.y
      width: desktop.width * root.ghostGeometry.width
      height: desktop.height * root.ghostGeometry.height
      radius: 7
      color: Qt.rgba(root.arcade.surfaceColor.r, root.arcade.surfaceColor.g,
        root.arcade.surfaceColor.b, 0.72)
      border.color: root.arcade.modeAccent
      border.width: 2
      opacity: root.ghostRequested ? 0.52 : 0
      visible: opacity > 0

      Behavior on opacity {
        enabled: !root.arcade.reducedMotion
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
      }

      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 2
        height: 24
        radius: 4
        color: Qt.rgba(root.arcade.modeAccent.r, root.arcade.modeAccent.g,
          root.arcade.modeAccent.b, 0.12)
        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: 9
          text: root.appTitle(root.ghostKind)
          color: root.arcade.modeInk
          font.pixelSize: 10 * root.arcade.fontScale
          font.weight: Font.DemiBold
        }
        Text {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.rightMargin: 8
          text: "NEXT"
          color: root.arcade.mutedColor
          font.pixelSize: 8 * root.arcade.fontScale
          font.weight: Font.Bold
        }
      }

      ColumnLayout {
        anchors.centerIn: parent
        width: parent.width - 32
        spacing: 8
        Text {
          Layout.fillWidth: true
          text: root.ghostKind === "terminal" ? ">_"
            : root.ghostKind === "browser" ? "WWW" : "FILES"
          color: root.arcade.modeInk
          font.family: "monospace"
          font.pixelSize: 26 * root.arcade.fontScale
          font.weight: Font.Bold
          horizontalAlignment: Text.AlignHCenter
        }
        Text {
          Layout.fillWidth: true
          text: "Waiting to open"
          color: root.arcade.mutedColor
          font.pixelSize: 11 * root.arcade.fontScale
          horizontalAlignment: Text.AlignHCenter
        }
      }
    }

    Repeater {
      model: 3
      Rectangle {
        id: appWindow
        required property int index
        readonly property var windowData: root.sceneState.windows[index] || null
        readonly property bool shown: root.windowIsVisible(windowData)
        objectName: windowData && windowData.kind === "terminal"
          ? "rescueTerminal" : windowData ? "rescueWindow-" + windowData.id : ""
        opacity: shown ? 1 : 0
        visible: opacity > 0
        x: windowData ? desktop.width * windowData.x : 0
        y: windowData ? desktop.height * windowData.y : 0
        width: windowData ? desktop.width * windowData.width : 0
        height: windowData ? desktop.height * windowData.height : 0
        z: !windowData ? 0 : root.sceneState.focusId === windowData.id ? 3
          : windowData.mode === "floating" || windowData.mode === "scratchpad"
            || windowData.mode === "fullscreen" ? 2 : 1
        radius: windowData && windowData.mode === "fullscreen" ? 3 : 7
        color: root.arcade.surfaceColor
        border.color: windowData && root.sceneState.focusId === windowData.id
          ? root.arcade.modeInk : root.arcade.lineColor
        border.width: windowData && root.sceneState.focusId === windowData.id ? 2 : 1

        Behavior on x { enabled: !root.arcade.reducedMotion; NumberAnimation { duration: 180 } }
        Behavior on y { enabled: !root.arcade.reducedMotion; NumberAnimation { duration: 180 } }
        Behavior on width { enabled: !root.arcade.reducedMotion; NumberAnimation { duration: 180 } }
        Behavior on height { enabled: !root.arcade.reducedMotion; NumberAnimation { duration: 180 } }
        Behavior on opacity {
          enabled: !root.arcade.reducedMotion
          NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: 2
          height: 24
          radius: 4
          color: Qt.tint(root.arcade.surfaceColor,
            Qt.rgba(root.arcade.modeAccent.r, root.arcade.modeAccent.g,
              root.arcade.modeAccent.b, 0.12))
          Text {
            anchors.left: parent.left
            anchors.right: modeLabel.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 9
            text: appWindow.windowData ? appWindow.windowData.title : ""
            color: root.arcade.foregroundColor
            font.pixelSize: 10 * root.arcade.fontScale
            font.weight: Font.DemiBold
            elide: Text.ElideRight
          }
          Text {
            id: modeLabel
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: 8
            text: !appWindow.windowData ? ""
              : appWindow.windowData.mode === "scratchpad" ? "SCRATCHPAD"
              : appWindow.windowData.mode === "fullscreen" ? "FULLSCREEN"
              : appWindow.windowData.mode === "floating" ? "FLOATING" : "TILED"
            color: root.arcade.mutedColor
            font.pixelSize: 8 * root.arcade.fontScale
            font.weight: Font.Bold
          }
        }

        Text {
          anchors.fill: parent
          anchors.topMargin: 34
          anchors.leftMargin: 12
          anchors.rightMargin: 12
          visible: appWindow.windowData && appWindow.windowData.kind === "terminal"
          text: "omarchy ~\n\n$ _"
          color: root.arcade.modeInk
          opacity: 0.86
          font.family: "monospace"
          font.pixelSize: 10 * root.arcade.fontScale
          wrapMode: Text.WordWrap
          clip: true
        }

        Item {
          id: browserContent
          visible: appWindow.windowData && appWindow.windowData.kind === "browser"
          anchors.fill: parent
          anchors.topMargin: 30
          anchors.leftMargin: 8
          anchors.rightMargin: 8
          anchors.bottomMargin: 8
          clip: true

          Rectangle {
            id: browserToolbar
            objectName: browserContent.visible ? "rescueBrowserToolbar" : ""
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 32
            radius: 6
            color: Qt.tint(root.arcade.surfaceColor,
              Qt.rgba(root.arcade.modeAccent.r, root.arcade.modeAccent.g,
                root.arcade.modeAccent.b, 0.08))
            border.color: root.arcade.lineColor

            Row {
              id: browserNavigation
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: 10
              spacing: 6
              Repeater {
                model: 3
                Rectangle {
                  required property int index
                  width: 8
                  height: 8
                  radius: 4
                  color: index === 0 ? root.arcade.modeAccent : root.arcade.lineColor
                  opacity: index === 0 ? 0.8 : 1
                }
              }
            }

            Rectangle {
              id: browserAddress
              objectName: browserContent.visible ? "rescueBrowserAddress" : ""
              anchors.left: browserNavigation.right
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: 12
              anchors.rightMargin: 10
              height: 20
              radius: 10
              color: root.arcade.surfaceColor
              border.color: Qt.tint(root.arcade.surfaceColor,
                Qt.rgba(root.arcade.modeAccent.r, root.arcade.modeAccent.g,
                  root.arcade.modeAccent.b, 0.22))
              Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                text: "omarchy.local/start"
                color: root.arcade.mutedColor
                font.family: "monospace"
                font.pixelSize: 8 * root.arcade.fontScale
                elide: Text.ElideRight
              }
            }
          }

          Rectangle {
            id: browserPage
            objectName: browserContent.visible ? "rescueBrowserPage" : ""
            readonly property bool compact: width < 430
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: browserToolbar.bottom
            anchors.bottom: parent.bottom
            anchors.topMargin: 8
            radius: 6
            color: Qt.tint(root.arcade.surfaceColor,
              Qt.rgba(root.arcade.modeAccent.r, root.arcade.modeAccent.g,
                root.arcade.modeAccent.b, 0.045))
            border.color: Qt.tint(root.arcade.surfaceColor,
              Qt.rgba(root.arcade.modeAccent.r, root.arcade.modeAccent.g,
                root.arcade.modeAccent.b, 0.14))
            clip: true

            ColumnLayout {
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              anchors.leftMargin: browserPage.compact ? 18 : 26
              anchors.topMargin: browserPage.compact ? 16 : 24
              anchors.bottomMargin: 18
              width: browserPage.compact ? parent.width - 36 : parent.width * 0.48
              spacing: browserPage.compact ? 8 : 12

              Text {
                Layout.fillWidth: true
                text: "OMARCHY"
                color: root.arcade.modeInk
                font.family: "monospace"
                font.pixelSize: 9 * root.arcade.fontScale
                font.weight: Font.Bold
                font.letterSpacing: 1.2
              }
              Text {
                Layout.fillWidth: true
                text: "A focused desktop,\nyour way."
                color: root.arcade.foregroundColor
                font.pixelSize: (browserPage.compact ? 14 : 18) * root.arcade.fontScale
                font.weight: Font.Bold
                wrapMode: Text.WordWrap
              }
              Text {
                Layout.fillWidth: true
                Layout.fillHeight: true
                text: "Fast, calm, and keyboard-first."
                color: root.arcade.mutedColor
                font.pixelSize: 9 * root.arcade.fontScale
                wrapMode: Text.WordWrap
              }
              Rectangle {
                Layout.preferredWidth: 88 * root.arcade.textScale
                Layout.preferredHeight: 26 * root.arcade.textScale
                radius: 6
                color: root.arcade.modeAccent
                Text {
                  anchors.centerIn: parent
                  text: "EXPLORE"
                  color: root.arcade.modeButtonInk
                  font.pixelSize: 8 * root.arcade.fontScale
                  font.weight: Font.Bold
                  font.letterSpacing: 0.8
                }
              }
            }

            Rectangle {
              objectName: browserContent.visible ? "rescueBrowserPreview" : ""
              visible: !browserPage.compact
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              anchors.margins: 22
              width: parent.width * 0.4
              radius: 8
              color: Qt.tint(root.arcade.surfaceColor,
                Qt.rgba(root.arcade.modeAccent.r, root.arcade.modeAccent.g,
                  root.arcade.modeAccent.b, 0.1))
              border.color: root.arcade.modeAccent
              border.width: 1

              Rectangle {
                anchors.left: parent.left
                anchors.right: parent.horizontalCenter
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.margins: 10
                anchors.rightMargin: 5
                radius: 5
                color: root.arcade.surfaceColor
                border.color: root.arcade.lineColor
                Rectangle {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  height: parent.height * 0.22
                  radius: 5
                  color: Qt.rgba(root.arcade.modeAccent.r,
                    root.arcade.modeAccent.g, root.arcade.modeAccent.b, 0.18)
                }
              }
              Column {
                anchors.left: parent.horizontalCenter
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.margins: 10
                anchors.leftMargin: 5
                spacing: 8
                Repeater {
                  model: 3
                  Rectangle {
                    required property int index
                    width: parent.width
                    height: (parent.height - 16) / 3
                    radius: 5
                    color: root.arcade.surfaceColor
                    border.color: index === 0 ? root.arcade.modeAccent : root.arcade.lineColor
                  }
                }
              }
            }
          }
        }

        Text {
          anchors.fill: parent
          anchors.topMargin: 34
          anchors.leftMargin: 12
          anchors.rightMargin: 12
          visible: appWindow.windowData && appWindow.windowData.kind === "files"
          text: "HOME / PROJECTS\n\nDocuments\nDownloads\nPictures"
          color: root.arcade.modeInk
          opacity: 0.86
          font.family: "monospace"
          font.pixelSize: 10 * root.arcade.fontScale
          wrapMode: Text.WordWrap
          clip: true
        }
      }
    }
  }

  RowLayout {
    id: status
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.margins: 12
    spacing: 8
    Text {
      text: "SYSTEM STATUS"
      color: root.arcade.modeInk
      font.family: "monospace"
      font.pixelSize: 9 * root.arcade.fontScale
      font.weight: Font.Bold
      font.letterSpacing: 0.7
    }
    Text {
      Layout.fillWidth: true
      text: root.desktopState
      color: root.arcade.foregroundColor
      font.pixelSize: 12 * root.arcade.fontScale
      wrapMode: Text.WordWrap
    }
  }
}
