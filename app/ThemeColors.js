var defaults = {
    background: "#1a1b26", foreground: "#c0caf5", accent: "#7aa2f7",
    muted: "#8992b7", urgent: "#f7768e", instruction: "#e0af68"
}

function valid(value) { return typeof value === "string" && /^#[0-9a-f]{6}$/i.test(value) }

function luminance(value) {
    var channels = [1, 3, 5].map(function(offset) {
        var channel = parseInt(value.substring(offset, offset + 2), 16) / 255
        return channel <= 0.04045 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4)
    })
    return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
}

function contrast(a, b) {
    var first = luminance(a), second = luminance(b)
    return (Math.max(first, second) + 0.05) / (Math.min(first, second) + 0.05)
}

function onColor(background) {
    return contrast("#ffffff", background) > contrast("#000000", background) ? "#ffffff" : "#000000"
}

function readable(color, background) {
    if (contrast(color, background) >= 4.5) return color
    var target = onColor(background)
    for (var step = 1; step <= 20; step++) {
        var result = "#"
        for (var offset of [1, 3, 5]) {
            var from = parseInt(color.substring(offset, offset + 2), 16)
            var to = parseInt(target.substring(offset, offset + 2), 16)
            result += Math.round(from + (to - from) * step / 20).toString(16).padStart(2, "0")
        }
        if (contrast(result, background) >= 4.5) return result
    }
    return target
}

function normalized(values) {
    var next = {}
    for (var key in defaults) next[key] = valid(values && values[key]) ? values[key] : defaults[key]
    for (var textRole of ["foreground", "muted", "urgent", "instruction"])
        next[textRole] = readable(next[textRole], next.background)
    return next
}

function parse(raw, fallback) {
    var next = Object.assign({}, defaults, fallback || {})
    var found = false, instruction = false, section = ""
    var aliases = { background: "background", foreground: "foreground", accent: "accent",
        muted: "muted", dark_foreground: "muted", red: "urgent", yellow: "instruction" }
    for (var line of String(raw || "").split("\n")) {
        var header = line.match(/^\s*\[([^\]]+)\]/)
        if (header) { section = header[1]; continue }
        if (section !== "") continue
        var match = line.match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["'](#[0-9a-fA-F]{6})["']\s*(?:#.*)?$/)
        if (!match || !aliases[match[1]]) continue
        next[aliases[match[1]]] = match[2]
        found = true
        if (match[1] === "yellow") instruction = true
    }
    if (!found) throw new Error("Theme contains no supported color values")
    if (!instruction) next.instruction = next.accent
    return normalized(next)
}
