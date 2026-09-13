import QtQuick
import Quickshell
import Quickshell.Io
import "ThemeColors.js" as ThemeColors

QtObject {
    id: root
    property var fallbackColors: ({})
    property string stateHome: Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"
    property string themeDirectory: stateHome + "/omarchy/current/theme"
    property string themeNamePath: stateHome + "/omarchy/current/theme.name"
    property var colors: ThemeColors.normalized(fallbackColors)
    property string diagnostic: ""
    property string loadedText: ""
    property int refreshRetries: 0
    property bool wallpaperEnabled: false
    property string wallpaperPath: stateHome + "/omarchy/current/background"
    property int wallpaperRevision: 0
    readonly property url wallpaperSource: wallpaperEnabled && wallpaperPath
        ? "file://" + wallpaperPath.split("/").map(encodeURIComponent).join("/") + "?v=" + wallpaperRevision
        : ""

    onWallpaperEnabledChanged: if (wallpaperEnabled) wallpaperRevision++

    function apply(raw) {
        try {
            colors = ThemeColors.parse(raw, fallbackColors)
            loadedText = raw
            diagnostic = ""
        } catch (error) {
            diagnostic = "Theme colors unavailable: " + error
            console.warn("learn-omarchy:", diagnostic)
            colors = ThemeColors.normalized(fallbackColors)
            loadedText = ""
        }
    }
    function refresh() {
        refreshRetries = 3
        reloadTimer.restart()
    }
    property Timer reloadTimer: Timer {
        interval: 75
        onTriggered: colorFile.reload()
    }
    onFallbackColorsChanged: {
        if (loadedText) apply(loadedText)
        else colors = ThemeColors.normalized(fallbackColors)
    }
    property FileView colorSource: FileView {
        id: colorFile
        path: root.themeDirectory + "/colors.toml"
        watchChanges: true
        printErrors: false
        onLoaded: {
            root.apply(text())
            // Editors can notify on truncation before writing the replacement.
            if (root.diagnostic && root.refreshRetries > 0) {
                root.refreshRetries--
                root.reloadTimer.restart()
            }
        }
        onFileChanged: root.refresh()
        onLoadFailed: {
            root.loadedText = ""
            root.colors = ThemeColors.normalized(root.fallbackColors)
            root.diagnostic = "Theme colors unavailable; using the fallback palette."
            console.warn("learn-omarchy:", root.diagnostic)
        }
    }
    property FileView nameSource: FileView {
        path: root.themeNamePath
        watchChanges: true
        printErrors: false
        onFileChanged: { reload(); root.refresh(); root.wallpaperRevision++ }
    }
    property FileView wallpaperWatcher: FileView {
        path: root.wallpaperEnabled ? root.wallpaperPath : ""
        preload: false
        watchChanges: true
        printErrors: false
        onFileChanged: root.wallpaperRevision++
    }
    property FileView wallpaperDirectoryWatcher: FileView {
        path: root.wallpaperEnabled ? root.wallpaperPath.slice(0, root.wallpaperPath.lastIndexOf("/")) : ""
        preload: false
        watchChanges: true
        printErrors: false
        onFileChanged: {
            // Replacing the symlink does not modify its previously watched target.
            root.wallpaperWatcher.watchChanges = false
            root.wallpaperWatcher.watchChanges = true
            root.wallpaperRevision++
        }
    }
}
