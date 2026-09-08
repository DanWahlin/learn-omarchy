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
    function refresh() { colorFile.reload() }
    onFallbackColorsChanged: {
        if (loadedText) apply(loadedText)
        else colors = ThemeColors.normalized(fallbackColors)
    }
    property FileView colorSource: FileView {
        id: colorFile
        path: root.themeDirectory + "/colors.toml"
        watchChanges: true
        printErrors: false
        onLoaded: root.apply(text())
        onFileChanged: reload()
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
        onFileChanged: { reload(); root.refresh() }
    }
}
