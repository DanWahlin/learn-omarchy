import QtQuick
import QtQuick.Controls as Controls
import QtTest
import "../../app" as App
import "../../app/ThemeColors.js" as Colors

Item {
    id: root
    width: 640
    height: 480
    property color backgroundColor: "#16161e"
    property color foreground: "#c0caf5"
    property color accent: "#7aa2f7"
    property color muted: "#8992b7"

    component PracticePalette: App.ThemePalette {
        backgroundColor: root.backgroundColor
        foregroundColor: root.foreground
        accentColor: root.accent
        mutedColor: root.muted
    }

    Controls.Button {
        id: button
        text: "Finish exercise"
        PracticePalette { target: button }
    }
    Controls.TextArea {
        id: field
        y: 60
        text: "Practice text"
        PracticePalette { target: field }
    }
    Controls.ComboBox {
        id: combo
        y: 120
        model: ["Choose recipient", "My test phone"]
        PracticePalette { target: combo }
        PracticePalette { target: combo.popup }
    }
    Controls.ScrollView {
        id: scroll
        y: 180
        width: 240
        height: 120
        PracticePalette { target: scroll }
        Controls.ScrollBar.vertical: Controls.ScrollBar {
            id: bar
            PracticePalette { target: bar }
        }
        Text { text: "Scrollable practice content"; height: 400 }
    }

    TestCase {
        name: "PracticeThemeInstances"
        when: windowShown

        function test_independentPalettesStayLive() {
            failOnWarning(/.*/)
            var themes = [
                {background: "#faf4ed", foreground: "#575279", accent: "#d7827e", muted: "#9893a5"},
                {background: "#16161e", foreground: "#c0caf5", accent: "#7aa2f7", muted: "#565f89"},
                {background: "#ffffff", foreground: "#202020", accent: "#553399", muted: "#666666"}
            ]
            for (var theme of themes) {
                root.backgroundColor = theme.background
                root.foreground = theme.foreground
                root.accent = theme.accent
                root.muted = theme.muted
                wait(20)
                for (var control of [button, field, combo, scroll, bar]) {
                    compare(String(control.palette.window), theme.background)
                    compare(String(control.palette.highlight), theme.accent)
                    verify(Colors.contrast(String(control.palette.highlightedText), theme.accent) >= 4.5)
                    verify(Colors.contrast(String(control.palette.disabled.text), theme.background) >= 4.5)
                }
                combo.popup.open()
                wait(20)
                compare(String(combo.popup.palette.window), theme.background)
                compare(String(combo.popup.palette.highlight), theme.accent)
                combo.popup.close()
            }
        }
    }
}
