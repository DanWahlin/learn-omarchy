var ARCADE_MODIFIERS = ["SUPER", "CTRL", "ALT", "SHIFT"];
var ARCADE_MODES = ["sprint", "rescue", "keyfall"];
var ARCADE_STAT_FIELDS = ["bestScore", "bestStreak", "plays", "clears"];

function arcadeObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

function arcadeInteger(value) {
    return typeof value === "number" && isFinite(value) && value >= 0 &&
        Math.floor(value) === value ? value : 0;
}

function arcadeText(value) {
    return typeof value === "string" ? value.replace(/HEXON/gi, "your guide") : "";
}

function normalizeKeys(keys) {
    var source = Array.isArray(keys) ? keys : (typeof keys === "string" ? keys.split("+") : []);
    var seen = {};
    var remaining = [];
    source.forEach(function(value) {
        if (typeof value !== "string") return;
        var key = value.replace(/^\s+|\s+$/g, "").toUpperCase();
        if (!key || key === "+" || seen[key]) return;
        seen[key] = true;
        if (ARCADE_MODIFIERS.indexOf(key) < 0) remaining.push(key);
    });
    return ARCADE_MODIFIERS.filter(function(key) { return seen[key]; }).concat(remaining);
}

function keySignature(keys) {
    return normalizeKeys(keys).join("+");
}

function arcadeRecognizesKeys(keys) {
    if (!Array.isArray(keys)) return false;
    return keys.every(function(value) {
        if (typeof value !== "string") return false;
        var key = value.replace(/^\s+|\s+$/g, "").toUpperCase();
        return key === "+" || ARCADE_MODIFIERS.indexOf(key) >= 0 ||
            ["SPACE", "RETURN", "TAB", "ESCAPE", "LEFT", "RIGHT", "UP", "DOWN",
             "MINUS", "EQUAL", "COMMA"].indexOf(key) >= 0 ||
            /^[A-Z0-9]$/.test(key);
    });
}

function arcadeCategory(lesson) {
    var text = ((lesson && lesson.id) || "") + " " + ((lesson && lesson.title) || "");
    text = text.toLowerCase();
    if (/capture|screenshot|screen.?record|recording|ocr|qr code/.test(text)) return "capture";
    if (/workspace/.test(text)) return "workspaces";
    if (/window|tiling|layout|focus/.test(text)) return "windows";
    if (/app|application|browser|terminal|web/.test(text)) return "apps";
    if (/system|setting|install|package|update|notification|audio|network|bluetooth|power|lock/.test(text)) return "system";
    return "general";
}

function buildChallenges(course) {
    if (!arcadeObject(course) || !Array.isArray(course.lessons)) return [];
    var challenges = [];
    var seen = {};
    course.lessons.forEach(function(lesson) {
        if (!arcadeObject(lesson) || lesson.kind === "welcome" || !Array.isArray(lesson.steps)) return;
        lesson.steps.forEach(function(step) {
            if (!arcadeObject(step) || step.kind === "welcome" || step.kind === "tour" ||
                step.kind === "practice" || !arcadeRecognizesKeys(step.keys)) return;
            var keys = normalizeKeys(step.keys);
            var signature = keys.join("+");
            var preferred = typeof step.practicePrompt === "string" && step.practicePrompt.length ?
                step.practicePrompt : step.instruction;
            var prompt = arcadeText(preferred);
            if (!signature || !prompt) return;
            var duplicate = signature + "\n" + prompt;
            if (seen[duplicate]) return;
            seen[duplicate] = true;
            challenges.push({
                id: typeof step.id === "string" ? step.id : "",
                lessonId: typeof lesson.id === "string" ? lesson.id : "",
                lessonTitle: arcadeText(lesson.title),
                prompt: prompt,
                detail: arcadeText(step.detail),
                keys: keys,
                signature: signature,
                category: arcadeCategory(lesson)
            });
        });
    });
    return challenges;
}

function shuffled(items, random) {
    var result = Array.isArray(items) ? items.slice() : [];
    var nextRandom = typeof random === "function" ? random : Math.random;
    for (var i = result.length - 1; i > 0; i--) {
        var value = Number(nextRandom());
        if (!isFinite(value) || value < 0 || value >= 1) value = 0;
        var j = Math.floor(value * (i + 1));
        var item = result[i];
        result[i] = result[j];
        result[j] = item;
    }
    return result;
}

function scoreAnswer(mode, elapsedMs, streak, hinted) {
    if (hinted) return 0;
    var elapsed = typeof elapsedMs === "number" && isFinite(elapsedMs) && elapsedMs > 0 ?
        Math.min(elapsedMs, 600000) : 0;
    var cleanStreak = arcadeInteger(streak);
    cleanStreak = Math.min(cleanStreak, 1000);
    if (mode === "rescue") return 75 + Math.min(cleanStreak, 20) * 4;
    if (mode === "keyfall") {
        return 90 + Math.max(0, 210 - Math.floor(elapsed / 35)) + cleanStreak * 12;
    }
    return 100 + Math.max(0, 180 - Math.floor(elapsed / 50)) + cleanStreak * 16;
}

function defaultStats() {
    var result = { version: 1 };
    ARCADE_MODES.forEach(function(mode) {
        result[mode] = { bestScore: 0, bestStreak: 0, plays: 0, clears: 0 };
    });
    return result;
}

function mergeStats(value) {
    var result = defaultStats();
    if (!arcadeObject(value)) return result;
    ARCADE_MODES.forEach(function(mode) {
        var source = arcadeObject(value[mode]) ? value[mode] : {};
        ARCADE_STAT_FIELDS.forEach(function(field) {
            result[mode][field] = arcadeInteger(source[field]);
        });
    });
    return result;
}

function recordResult(stats, mode, score, streak, cleared) {
    var result = mergeStats(stats);
    if (ARCADE_MODES.indexOf(mode) < 0) return result;
    var cleanScore = arcadeInteger(score);
    var cleanStreak = arcadeInteger(streak);
    result[mode].plays += 1;
    if (cleared === true) result[mode].clears += 1;
    result[mode].bestScore = Math.max(result[mode].bestScore, cleanScore);
    result[mode].bestStreak = Math.max(result[mode].bestStreak, cleanStreak);
    return result;
}
