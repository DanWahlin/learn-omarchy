import QtQuick
import QtQuick.Controls as Controls
import QtTest
import "../../app" as App
import "../../app/ThemeColors.js" as Colors

Item {
    id: root
    width: 800
    height: 600
    App.ThemePalette { id: appPalette }
    property var colors: ({background:appPalette.backgroundColor.toString(), foreground:appPalette.foregroundColor.toString(),
        accent:appPalette.accentColor.toString(), muted:appPalette.mutedColor.toString()})
    Controls.ComboBox { id: combo; App.ThemePalette { target: combo; colors: root.colors } model: ["One", "Two"] }
    Controls.TextArea { id: field; y: 60; App.ThemePalette { target: field; colors: root.colors } text: "Sample text" }
    Controls.ScrollBar { id: bar; y: 150; App.ThemePalette { target: bar; colors: root.colors } }
    TestCase {
        name: "UnifiedThemePalette"
        when: windowShown
        function test_lightAndDarkPalettes_data() {
            return [
                {tag:"dark", background:"#16161e", foreground:"#c0caf5", accent:"#7aa2f7", muted:"#565f89"},
                {tag:"light", background:"#faf4ed", foreground:"#575279", accent:"#d7827e", muted:"#9893a5"}
            ]
        }
        function test_lightAndDarkPalettes(data) {
            failOnWarning(/.*/)
            appPalette.backgroundColor = data.background
            appPalette.foregroundColor = data.foreground
            appPalette.accentColor = data.accent
            appPalette.mutedColor = data.muted
            wait(10)
            compare(combo.palette.window, appPalette.backgroundColor)
            compare(combo.palette.highlight, appPalette.accentColor)
            compare(field.palette.base, appPalette.backgroundColor)
            compare(bar.palette.highlight, appPalette.accentColor)
            verify(Colors.contrast(String(appPalette.text), data.background) >= 4.5)
            verify(Colors.contrast(String(appPalette.highlightedText), data.accent) >= 4.5)
            verify(Colors.contrast(String(appPalette.placeholderText), data.background) >= 4.5)
            verify(Colors.contrast(String(combo.palette.buttonText), String(combo.palette.button)) >= 4.5)
            verify(Colors.contrast(String(combo.palette.dark), String(combo.palette.button)) >= 3)
            combo.popup.open()
            wait(20)
            compare(combo.popup.palette.window, appPalette.backgroundColor)
            combo.popup.close()
        }
        function test_parserDoesNotCarryColorsAcrossThemes() {
            var first = Colors.parse('background = "#ffffff"\nforeground = "#000000"\nyellow = "#ffff00"', {})
            verify(Colors.contrast(first.instruction, first.background) >= 4.5)
            var second = Colors.parse('background = "#101010"\naccent = "#aa88ff"', {})
            compare(second.foreground, Colors.defaults.foreground)
            verify(Colors.contrast(second.instruction, second.background) >= 4.5)
            compare(Colors.parse('background = "#ffffff"\n[other]\nbackground = "#000000"', {}).background, "#ffffff")
            var rejected = false
            try { Colors.parse("not colors", {}) } catch (error) { rejected = true }
            verify(rejected)
        }
    }
}
