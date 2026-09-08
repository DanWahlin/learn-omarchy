import QtQuick
import "ThemeColors.js" as ThemeColors

Palette {
    id: root
    property var target: null
    property var colors: ({})
    property color backgroundColor: colors.background || "#1a1b26"
    property color foregroundColor: colors.foreground || "#c0caf5"
    property color accentColor: colors.accent || "#7aa2f7"
    property color mutedColor: colors.muted || "#8992b7"
    readonly property color readableText: ThemeColors.readable(String(foregroundColor), String(backgroundColor))
    readonly property color secondaryText: ThemeColors.readable(String(mutedColor), String(backgroundColor))
    window: backgroundColor
    windowText: readableText
    base: backgroundColor
    alternateBase: Qt.tint(backgroundColor, Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.08))
    text: readableText
    brightText: readableText
    button: Qt.tint(backgroundColor, Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.14))
    buttonText: ThemeColors.readable(String(foregroundColor), String(button))
    highlight: accentColor
    highlightedText: ThemeColors.onColor(String(accentColor))
    placeholderText: secondaryText
    toolTipBase: backgroundColor
    toolTipText: readableText
    link: ThemeColors.readable(String(accentColor), String(backgroundColor))
    linkVisited: link
    light: Qt.lighter(backgroundColor, 1.3)
    midlight: Qt.lighter(backgroundColor, 1.15)
    mid: button
    dark: secondaryText
    shadow: Qt.darker(backgroundColor, 1.6)
    accent: accentColor
    disabled {
        text: secondaryText
        buttonText: secondaryText
        windowText: secondaryText
        highlight: mutedColor
        highlightedText: ThemeColors.onColor(String(mutedColor))
    }
    // Qt controls copy an assigned Palette value. Apply roles to their native
    // palette after input bindings settle so later theme changes stay live.
    function applyToTarget() {
        if (!target) return
        var roles = ["window", "windowText", "base", "alternateBase", "text", "brightText", "button", "buttonText",
            "highlight", "highlightedText", "placeholderText", "toolTipBase", "toolTipText",
            "link", "linkVisited", "light", "midlight", "mid", "dark", "shadow", "accent"]
        for (var role of roles) target.palette[role] = root[role]
        for (var disabledRole of ["text", "buttonText", "windowText", "highlight", "highlightedText"])
            target.palette.disabled[disabledRole] = root.disabled[disabledRole]
    }
    onTargetChanged: Qt.callLater(applyToTarget)
    onBackgroundColorChanged: Qt.callLater(applyToTarget)
    onForegroundColorChanged: Qt.callLater(applyToTarget)
    onAccentColorChanged: Qt.callLater(applyToTarget)
    onMutedColorChanged: Qt.callLater(applyToTarget)
    Component.onCompleted: Qt.callLater(applyToTarget)
}
