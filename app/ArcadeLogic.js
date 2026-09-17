var ARCADE_MODIFIERS = ["SUPER", "CTRL", "ALT", "SHIFT"];
var ARCADE_MODES = ["sprint", "rescue", "keyfall"];
var ARCADE_STAT_FIELDS = ["bestScore", "bestStreak", "plays", "clears"];
var ARCADE_SCORING_VERSION = 2;
var ARCADE_DAY_MS = 86400000;
var ARCADE_MAX_COUNT = 1000000000;
var ARCADE_MAX_RECALL_MS = 600000;
var ARCADE_MAX_TIME = 8640000000000000;
var ARCADE_HISTORY_LIMIT = 24;
var ARCADE_SESSION_LIMIT = 32;
var ARCADE_SKILL_LIMIT = 512;
var ARCADE_RECORD_LIMIT = 100;
var ARCADE_RESERVED_KEYS = ["ESCAPE", "H", "P"];
var ARCADE_RESCUE_MISSIONS = [
    {
        id: "terminal-workspace",
        title: "Build a terminal workspace",
        callsign: "TERMINAL RUN",
        destination: "KEPLER OUTPOST",
        arrival: "Kepler Outpost reached. Terminal systems are online.",
        brief: "Open a terminal, shape it for focused work, and move it to workspace 2.",
        success: "Your terminal workspace is ready on workspace 2.",
        initialLabel: "Workspace 1 · ready for a terminal",
        steps: [
            { action: "launch-terminal", prompt: "Open a terminal for this workspace",
                label: "Terminal opened · tiled on workspace 1" },
            { action: "float", prompt: "Detach the terminal into a floating window",
                label: "Terminal detached · floating" },
            { action: "widen", prompt: "Give the floating terminal more room",
                label: "Terminal widened for focused work" },
            { action: "fullscreen", prompt: "Make the terminal fullscreen",
                label: "Terminal fullscreen on workspace 1" },
            { action: "send-workspace-2", prompt: "Move the terminal to workspace 2 and follow it",
                label: "Terminal moved and followed to workspace 2", settledWorkspace: 1,
                settledLabel: "Mission setup: returned to workspace 1 · terminal stays on 2" },
            { action: "workspace-2", prompt: "Switch back to your terminal on workspace 2",
                label: "Workspace 2 · terminal ready" }
        ]
    },
    {
        id: "layout-triage",
        title: "Tidy a crowded workspace",
        callsign: "TIDY VECTOR",
        destination: "ORBITAL RELAY",
        arrival: "Orbital Relay reached. The workspace is stable.",
        brief: "Open two apps, practice focus and swapping, change the split, then close the extra window.",
        success: "The workspace is tidy and the browser is ready.",
        initialLabel: "Workspace 1 · empty layout",
        steps: [
            { action: "launch-terminal", prompt: "Open a terminal for the task",
                label: "Terminal opened · full tiled space" },
            { action: "launch-browser", prompt: "Open a browser beside the terminal",
                label: "Browser opened · two tiled windows" },
            { action: "cycle-focus", prompt: "Move focus back to the terminal",
                label: "Terminal focused" },
            { action: "swap-right", prompt: "Swap the terminal with the window on its right",
                label: "Terminal and browser swapped" },
            { action: "toggle-split", prompt: "Change the tiled windows' split direction",
                label: "Layout changed to a stacked split" },
            { action: "close-window", prompt: "Close the focused terminal",
                label: "Terminal closed · browser remains" }
        ]
    },
    {
        id: "workspace-sort",
        title: "Sort work across two spaces",
        callsign: "TWIN ORBIT",
        destination: "BINARY STATION",
        arrival: "Binary Station reached. Both workspaces are in position.",
        brief: "Place the browser on workspace 2, keep a terminal on workspace 1, and practice moving between them.",
        success: "Your browser and terminal are organized across two workspaces.",
        initialLabel: "Workspace 1 · ready to organize",
        steps: [
            { action: "launch-browser", prompt: "Open a browser on workspace 1",
                label: "Browser opened on workspace 1" },
            { action: "send-workspace-2", prompt: "Move the browser to workspace 2 and follow it",
                label: "Browser moved and followed to workspace 2" },
            { action: "workspace-1", prompt: "Return to workspace 1",
                label: "Workspace 1 · ready for another app" },
            { action: "launch-terminal", prompt: "Open a terminal on workspace 1",
                label: "Terminal opened on workspace 1" },
            { action: "workspace-2", prompt: "Switch to the browser on workspace 2",
                label: "Workspace 2 · browser ready" },
            { action: "last-workspace", prompt: "Return to the last workspace you visited",
                label: "Workspace 1 · terminal ready" }
        ]
    },
    {
        id: "scratchpad-recovery",
        title: "Rescue a hidden terminal",
        callsign: "SHADOW RECOVERY",
        destination: "LUNA VAULT",
        arrival: "Luna Vault reached. The hidden terminal is secure.",
        brief: "Stash a terminal, reveal it, then hide the scratchpad before closing the browser.",
        success: "Your terminal is safely stashed and the browser workspace is clear.",
        initialLabel: "Workspace 1 · ready for a temporary terminal",
        steps: [
            { action: "launch-terminal", prompt: "Open a temporary terminal",
                label: "Terminal opened on workspace 1" },
            { action: "stash-window", prompt: "Move the terminal into the scratchpad",
                label: "Terminal stashed · workspace 1 is clear" },
            { action: "launch-browser", prompt: "Open a browser while the terminal is hidden",
                label: "Browser opened · terminal remains hidden" },
            { action: "toggle-scratchpad", prompt: "Reveal the hidden scratchpad",
                label: "Scratchpad terminal revealed above the browser" },
            { action: "toggle-scratchpad", prompt: "Hide the scratchpad to return to the browser",
                label: "Scratchpad hidden · browser focused" },
            { action: "close-window", prompt: "Close the focused browser",
                label: "Browser closed · terminal safe in the hidden scratchpad" }
        ]
    },
    {
        id: "file-window-shaping",
        title: "Shape a file workspace",
        callsign: "CARGO SHAPE",
        destination: "ATLAS DEPOT",
        arrival: "Atlas Depot reached. The file workspace is ready.",
        brief: "Open Files and a terminal, focus Files, then practice floating and resizing it.",
        success: "The file manager is floating at a comfortable working size.",
        initialLabel: "Workspace 1 · ready for file work",
        steps: [
            { action: "launch-files", prompt: "Open the file manager",
                label: "Files opened on workspace 1" },
            { action: "launch-terminal", prompt: "Open a terminal beside Files",
                label: "Terminal opened · two tiled windows" },
            { action: "cycle-focus", prompt: "Move focus back to Files",
                label: "Files focused" },
            { action: "float", prompt: "Detach Files into a floating window",
                label: "Files detached · floating" },
            { action: "widen", prompt: "Make the floating Files window wider",
                label: "Files widened" },
            { action: "narrow", prompt: "Bring the Files window back to a compact width",
                label: "Files resized to a compact working width" }
        ]
    },
    {
        id: "browser-workspace-recovery",
        title: "Recover a browser workspace",
        callsign: "RETURN VECTOR",
        destination: "NOVA ARCHIVE",
        arrival: "Nova Archive reached. The browser workspace is safely closed.",
        brief: "Fullscreen a browser, step away to another workspace, then return and close it safely.",
        success: "The browser workspace is closed and your file workspace remains available.",
        initialLabel: "Workspace 1 · ready for focused browsing",
        steps: [
            { action: "launch-browser", prompt: "Open a browser on workspace 1",
                label: "Browser opened on workspace 1" },
            { action: "fullscreen", prompt: "Make the browser fullscreen",
                label: "Browser fullscreen on workspace 1" },
            { action: "next-workspace", prompt: "Switch to the next workspace",
                label: "Workspace 2 · browser remains on 1" },
            { action: "launch-files", prompt: "Open the file manager on workspace 2",
                label: "Files opened on workspace 2" },
            { action: "previous-workspace", prompt: "Return to the previous workspace",
                label: "Workspace 1 · fullscreen browser restored" },
            { action: "close-window", prompt: "Close the focused browser",
                label: "Browser closed · workspace 1 is clear" }
        ]
    }
];

// Metadata identifies course steps, never supplies keys. Aliases collapse repeated
// lesson activities into one standalone action; edited course keys remain authoritative.
var ARCADE_CATALOG = [
    { steps: ["omarchy-tour/tour-workspace-two", "workspaces/workspaces-jump"],
        action: "workspace-2", category: "workspaces", difficulty: "starter", prompt: "Switch to workspace 2" },
    { steps: ["omarchy-tour/tour-workspace-one", "workspaces/workspaces-home"],
        action: "workspace-1", category: "workspaces", difficulty: "starter", prompt: "Switch to workspace 1" },
    { steps: ["omarchy-tour/tour-omarchy-menu", "menus-and-apps/open-root-menu"],
        action: "omarchy-menu", category: "system", difficulty: "starter", prompt: "Open the Omarchy menu" },
    { steps: ["menus-and-apps/open-apps"],
        action: "apps-menu", category: "apps", difficulty: "starter", prompt: "Open the Apps menu" },
    { steps: ["menus-and-apps/open-keybindings"],
        action: "shortcut-guide", category: "system", difficulty: "starter", prompt: "Open the shortcut guide",
        detail: "In the real guide, activating a result runs its shortcut." },
    { steps: ["everyday-apps/launch-terminal", "windows/windows-open-first", "windows/windows-open-second", "workspaces/workspaces-open-terminal"],
        action: "launch-terminal", category: "apps", difficulty: "starter", prompt: "Open a terminal" },
    { steps: ["everyday-apps/close-terminal", "everyday-apps/close-files", "windows/windows-close-one", "windows/windows-close-two", "workspaces/workspaces-close", "useful-tools/tools-monitor-close", "useful-tools/tools-calculator-close"],
        action: "close-window", category: "windows", difficulty: "starter", prompt: "Close the focused window",
        detail: "On your desktop, save work and check which window has focus first." },
    { steps: ["everyday-apps/launch-browser"],
        action: "launch-browser", category: "apps", difficulty: "starter", prompt: "Launch the browser",
        detail: "Your browser settings determine whether a new window opens." },
    { steps: ["everyday-apps/launch-files"],
        action: "launch-files", category: "apps", difficulty: "starter", prompt: "Open the file manager" },
    { steps: ["windows/windows-split", "windows/windows-split-restore"],
        action: "toggle-split", category: "windows", difficulty: "intermediate", prompt: "Toggle the tiled windows' split direction",
        detail: "This action needs tiled windows in the dwindle layout." },
    { steps: ["windows/windows-focus-next"],
        action: "cycle-focus", category: "windows", difficulty: "starter", prompt: "Focus the next window on this workspace" },
    { steps: ["windows/windows-float", "windows/windows-retile"],
        action: "float", category: "windows", difficulty: "intermediate", prompt: "Make the tiled window float",
        detail: "The same shortcut returns a floating window to tiling." },
    { steps: ["advanced-windows/advanced-window-pop", "advanced-windows/advanced-window-restore"],
        action: "pop-out", category: "windows", difficulty: "intermediate", prompt: "Pop the focused window out",
        detail: "The same shortcut unpins and retiles a popped-out window." },
    { steps: ["windows/windows-resize"],
        action: "widen", category: "windows", difficulty: "intermediate", prompt: "Make the floating window wider",
        detail: "Uses the physical key immediately left of Backspace; size limits can prevent resizing." },
    { steps: ["windows/windows-resize-back"],
        action: "narrow", category: "windows", difficulty: "intermediate", prompt: "Make the floating window narrower",
        detail: "Uses the physical key two places left of Backspace; size limits can prevent resizing." },
    { steps: ["windows/windows-fullscreen", "windows/windows-exit-fullscreen"],
        action: "fullscreen", category: "windows", difficulty: "starter", prompt: "Make the focused window fullscreen",
        detail: "Repeat the shortcut to leave fullscreen." },
    { steps: ["windows/windows-focus-right"],
        action: "focus-right", category: "windows", difficulty: "intermediate", prompt: "Focus the window on the right" },
    { steps: ["windows/windows-swap"],
        action: "swap-right", category: "windows", difficulty: "advanced", prompt: "Swap the focused window with the window on the right" },
    { steps: ["workspaces/workspaces-back"],
        action: "last-workspace", category: "workspaces", difficulty: "intermediate", prompt: "Return to the last workspace you visited" },
    { steps: ["workspaces/workspaces-send", "workspaces/workspaces-restore"],
        action: "send-workspace-2", category: "workspaces", difficulty: "intermediate", prompt: "Move the focused window to workspace 2 and follow it",
        detail: "Both the window and your active workspace move to workspace 2." },
    { steps: ["workspaces/next-workspace"],
        action: "next-workspace", category: "workspaces", difficulty: "starter", prompt: "Switch to the next workspace in order" },
    { steps: ["workspaces/previous-workspace"],
        action: "previous-workspace", category: "workspaces", difficulty: "intermediate", prompt: "Switch to the previous workspace in order" },
    { steps: ["workspaces/workspaces-stash"],
        action: "stash-window", category: "workspaces", difficulty: "advanced", prompt: "Move the focused window into the scratchpad" },
    { steps: ["workspaces/workspaces-scratchpad", "workspaces/workspaces-scratchpad-hide", "workspaces/workspaces-reveal-before-restore"],
        action: "toggle-scratchpad", category: "workspaces", difficulty: "intermediate", prompt: "Show the hidden scratchpad",
        detail: "The same shortcut hides a visible scratchpad without closing its windows." },
    { steps: ["bar-panels/audio-panel"],
        action: "audio-panel", category: "system", difficulty: "intermediate", prompt: "Open the Audio panel" },
    { steps: ["bar-panels/network-panel"],
        action: "network-panel", category: "system", difficulty: "intermediate", prompt: "Open the Network panel" },
    { steps: ["bar-panels/power-panel"],
        action: "power-panel", category: "system", difficulty: "intermediate", prompt: "Open the Power panel",
        detail: "On the real desktop, this panel requires a battery." },
    { steps: ["bar-panels/calendar-panel"],
        action: "calendar-panel", category: "system", difficulty: "advanced", prompt: "Open the calendar" },
    { steps: ["bar-panels/background-menu"],
        action: "background-menu", category: "system", difficulty: "intermediate", prompt: "Open the Background switcher" },
    { steps: ["bar-panels/theme-menu"],
        action: "theme-menu", category: "system", difficulty: "advanced", prompt: "Open the Theme menu" },
    { steps: ["bar-panels/toggle-menu"],
        action: "toggle-menu", category: "system", difficulty: "intermediate", prompt: "Open the Toggle menu" },
    { steps: ["clipboard-and-helpers/clipboard-history"],
        action: "clipboard-history", category: "apps", difficulty: "intermediate", prompt: "Open clipboard history" },
    { steps: ["capture-and-share/capture-menu"],
        action: "capture-menu", category: "capture", difficulty: "intermediate", prompt: "Open the Capture menu" },
    { steps: ["setup-and-install/hardware-menu"],
        action: "hardware-menu", category: "system", difficulty: "intermediate", prompt: "Open the Hardware menu" },
    { steps: ["setup-and-install/display-panel"],
        action: "display-panel", category: "system", difficulty: "intermediate", prompt: "Open the Display panel" },
    { steps: ["setup-and-install/system-menu"],
        action: "system-menu", category: "system", difficulty: "starter", prompt: "Open the System menu",
        detail: "Opening the menu does not select Lock, Logout, Restart, or Shutdown." },
    { steps: ["productivity-extras/helpers-emoji"],
        action: "emoji-picker", category: "apps", difficulty: "intermediate", prompt: "Open the emoji picker" },
    { steps: ["productivity-extras/helpers-reminder"],
        action: "reminder-prompt", category: "apps", difficulty: "intermediate", prompt: "Open the reminder prompt" },
    { steps: ["useful-tools/tools-monitor-open"],
        action: "activity-monitor", category: "system", difficulty: "intermediate", prompt: "Open the activity monitor" },
    { steps: ["useful-tools/tools-calculator-open"],
        action: "calculator", category: "apps", difficulty: "intermediate", prompt: "Open the calculator" },
    { steps: ["create-and-share/share-menu"],
        action: "share-menu", category: "capture", difficulty: "intermediate", prompt: "Open the Share menu",
        detail: "Opening the menu alone sends nothing." }
];

function arcadeObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

function arcadeValidInteger(value, maximum) {
    return typeof value === "number" && isFinite(value) && value >= 0 &&
        Math.floor(value) === value && value <= maximum;
}

function arcadeInteger(value) {
    return arcadeValidInteger(value, ARCADE_MAX_COUNT) ? value : 0;
}

function arcadeTime(value) {
    return arcadeValidInteger(value, ARCADE_MAX_TIME) ? value : 0;
}

function arcadeText(value) {
    return typeof value === "string" ?
        value.replace(/HEXON/gi, "your guide").replace(/^\s+|\s+$/g, "").slice(0, 2000) : "";
}

function normalizeKeys(keys) {
    var source = Array.isArray(keys) ? keys : (typeof keys === "string" ? keys.split("+") : []);
    var seen = Object.create(null);
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
    if (!Array.isArray(keys) || keys.length > 16) return false;
    return keys.every(function(value) {
        if (typeof value !== "string") return false;
        var key = value.replace(/^\s+|\s+$/g, "").toUpperCase();
        return key === "+" || ARCADE_MODIFIERS.indexOf(key) >= 0 ||
            ["SPACE", "RETURN", "TAB", "ESCAPE", "LEFT", "RIGHT", "UP", "DOWN",
             "MINUS", "EQUAL", "COMMA"].indexOf(key) >= 0 || /^[A-Z0-9]$/.test(key);
    });
}

function arcadePlayableKeys(keys) {
    if (!arcadeRecognizesKeys(keys)) return false;
    var normalized = normalizeKeys(keys);
    var mainKeys = normalized.filter(function(key) { return ARCADE_MODIFIERS.indexOf(key) < 0; });
    return mainKeys.length === 1 &&
        !(normalized.length === 1 && ARCADE_RESERVED_KEYS.indexOf(mainKeys[0]) >= 0);
}

function arcadeMetadata(lessonId, stepId) {
    var identity = lessonId + "/" + stepId;
    for (var i = 0; i < ARCADE_CATALOG.length; i++) {
        if (ARCADE_CATALOG[i].steps.indexOf(identity) >= 0) return ARCADE_CATALOG[i];
    }
    return null;
}

function buildChallenges(course) {
    if (!arcadeObject(course) || !Array.isArray(course.lessons)) return [];
    var challenges = [];
    var positions = Object.create(null);
    var curated = Object.create(null);
    course.lessons.forEach(function(lesson) {
        if (!arcadeObject(lesson) || lesson.kind === "welcome" || !Array.isArray(lesson.steps)) return;
        lesson.steps.forEach(function(step) {
            if (!arcadeObject(step) || ["welcome", "tour", "practice"].indexOf(step.kind) >= 0 ||
                !arcadePlayableKeys(step.keys)) return;
            var keys = normalizeKeys(step.keys);
            var signature = keys.join("+");
            var lessonId = arcadeText(lesson.id);
            var id = arcadeText(step.id) || lessonId + ":" + signature;
            var metadata = arcadeMetadata(lessonId, id);
            var prompt = metadata ? metadata.prompt :
                (arcadeText(step.practicePrompt) || arcadeText(step.instruction));
            if (!prompt) return;
            var challenge = {
                id: id, lessonId: lessonId, lessonTitle: arcadeText(lesson.title),
                prompt: prompt, detail: metadata ? (metadata.detail || "") : arcadeText(step.detail),
                keys: keys, signature: signature,
                category: metadata ? metadata.category : "general",
                action: metadata ? metadata.action : "custom",
                difficulty: metadata ? metadata.difficulty : "intermediate"
            };
            // A known action wins over an earlier custom variant of the same chord.
            if (positions[signature] !== undefined) {
                if (metadata && !curated[signature]) challenges[positions[signature]] = challenge;
            } else {
                positions[signature] = challenges.length;
                challenges.push(challenge);
            }
            if (metadata) curated[signature] = true;
        });
    });
    return challenges;
}

function arcadeCanonical(challenges) {
    var seen = Object.create(null);
    return (Array.isArray(challenges) ? challenges : []).filter(function(challenge) {
        if (!arcadeObject(challenge) || !arcadePlayableKeys(challenge.keys)) return false;
        var signature = keySignature(challenge.keys);
        if (challenge.signature !== signature || seen[signature]) return false;
        seen[signature] = true;
        return true;
    });
}

function arcadeRandom(random) {
    var value = Number(random());
    return isFinite(value) && value >= 0 && value < 1 ? value : 0;
}

function shuffled(items, random) {
    var result = Array.isArray(items) ? items.slice() : [];
    var nextRandom = typeof random === "function" ? random : Math.random;
    for (var i = result.length - 1; i > 0; i--) {
        var j = Math.floor(arcadeRandom(nextRandom) * (i + 1));
        var item = result[i];
        result[i] = result[j];
        result[j] = item;
    }
    return result;
}

function seededRandom(seed) {
    var text = typeof seed === "string" || (typeof seed === "number" && isFinite(seed)) ? String(seed) : "arcade";
    var state = 2166136261;
    for (var i = 0; i < text.length; i++) {
        state ^= text.charCodeAt(i);
        state = (state + (state << 1) + (state << 4) + (state << 7) +
            (state << 8) + (state << 24)) >>> 0;
    }
    return function() {
        state = (1664525 * state + 1013904223) >>> 0;
        return state / 4294967296;
    };
}

function scoreAnswer(mode, elapsedMs, streak, hinted, wrongAttempts) {
    if (hinted) return 0;
    var wrong = wrongAttempts === undefined ? 0 :
        (arcadeValidInteger(wrongAttempts, ARCADE_MAX_COUNT) ? wrongAttempts : 1);
    // Retries earn encouragement, but never speed or clean-streak bonuses.
    if (wrong > 0) return mode === "rescue" ? 35 : (mode === "keyfall" ? 45 : 50);
    var elapsed = arcadeValidInteger(elapsedMs, ARCADE_MAX_TIME) ?
        Math.min(elapsedMs, ARCADE_MAX_RECALL_MS) : ARCADE_MAX_RECALL_MS;
    var cleanStreak = Math.min(arcadeInteger(streak), 1000);
    if (mode === "rescue") return 75 + Math.min(cleanStreak, 20) * 4;
    if (mode === "keyfall") return 90 + Math.max(0, 210 - Math.floor(elapsed / 35)) + cleanStreak * 12;
    return 100 + Math.max(0, 180 - Math.floor(elapsed / 50)) + cleanStreak * 16;
}

function defaultStats() {
    var result = { version: 2, skills: {}, records: {} };
    ARCADE_MODES.forEach(function(mode) {
        // These bests are legacy-only. v2 records must be read through bestForDeck.
        result[mode] = { bestScore: 0, bestStreak: 0, plays: 0, clears: 0 };
    });
    return result;
}

function arcadeDefaultSkill() {
    return { attempts: 0, assisted: 0, unassisted: 0, firstTry: 0, lastSeenAt: 0,
        bestRecallMs: 0, meanRecallMs: 0, successfulSessions: [], history: [] };
}

function arcadeSessionId(value) {
    return typeof value === "string" && value.length <= 128 && value.trim() ? value : "";
}

function arcadeSessions(source, firstTry, lastSeenAt) {
    var sessions = [];
    var seen = Object.create(null);
    (Array.isArray(source) ? source : []).forEach(function(entry) {
        if (!arcadeObject(entry) || !arcadeSessionId(entry.sessionId) ||
            !arcadeValidInteger(entry.at, ARCADE_MAX_TIME) || entry.at > lastSeenAt) return;
        var index = seen[entry.sessionId];
        if (index !== undefined) sessions[index].at = Math.min(sessions[index].at, entry.at);
        else {
            seen[entry.sessionId] = sessions.length;
            sessions.push({ sessionId: entry.sessionId, at: entry.at });
        }
    });
    sessions.sort(function(a, b) { return a.at - b.at || a.sessionId.localeCompare(b.sessionId); });
    var limit = Math.min(ARCADE_SESSION_LIMIT, firstTry);
    if (limit === 0) return [];
    // Retain the first session as spacing evidence plus the most recent sessions.
    if (sessions.length <= limit) return sessions;
    return limit === 1 ? [sessions[0]] : [sessions[0]].concat(sessions.slice(-(limit - 1)));
}

function arcadeSkill(value) {
    var result = arcadeDefaultSkill();
    if (!arcadeObject(value)) return result;
    result.attempts = arcadeInteger(value.attempts);
    result.assisted = Math.min(result.attempts, arcadeInteger(value.assisted));
    result.unassisted = Math.min(result.attempts - result.assisted, arcadeInteger(value.unassisted));
    result.firstTry = Math.min(result.unassisted, arcadeInteger(value.firstTry));
    result.lastSeenAt = arcadeTime(value.lastSeenAt);
    if (result.firstTry > 0) {
        result.bestRecallMs = arcadeValidInteger(value.bestRecallMs, ARCADE_MAX_RECALL_MS) ? value.bestRecallMs : 0;
        result.meanRecallMs = typeof value.meanRecallMs === "number" && isFinite(value.meanRecallMs) &&
            value.meanRecallMs >= result.bestRecallMs && value.meanRecallMs <= ARCADE_MAX_RECALL_MS ? value.meanRecallMs : result.bestRecallMs;
    }
    result.successfulSessions = arcadeSessions(value.successfulSessions, result.firstTry, result.lastSeenAt);
    result.history = (Array.isArray(value.history) ? value.history : []).filter(function(entry) {
        return arcadeObject(entry) && arcadeSessionId(entry.sessionId) &&
            arcadeValidInteger(entry.at, ARCADE_MAX_TIME) && entry.at <= result.lastSeenAt &&
            typeof entry.hinted === "boolean" && arcadeValidInteger(entry.wrongAttempts, ARCADE_MAX_COUNT) &&
            arcadeValidInteger(entry.elapsedMs, ARCADE_MAX_RECALL_MS);
    }).map(function(entry) {
        return { at: entry.at, sessionId: entry.sessionId, hinted: entry.hinted,
            wrongAttempts: entry.wrongAttempts, elapsedMs: entry.elapsedMs,
            clean: entry.hinted === false && entry.wrongAttempts === 0 };
    }).sort(function(a, b) { return a.at - b.at; }).slice(-Math.min(ARCADE_HISTORY_LIMIT, result.attempts));
    if (!result.attempts) result.history = [];
    return result;
}

function arcadeEmptyRecord() {
    return { bestScore: 0, bestClean: 0, bestElapsedMs: 0, splits: [], plays: 0 };
}

function arcadeSplits(value, elapsedMs) {
    if (!Array.isArray(value) || value.length > 1000) return [];
    var previous = 0;
    var valid = value.every(function(split) {
        var okay = arcadeValidInteger(split, ARCADE_MAX_TIME) && split >= previous && split <= elapsedMs;
        previous = split;
        return okay;
    });
    return valid ? value.slice() : [];
}

function arcadeRecord(value) {
    var result = arcadeEmptyRecord();
    if (!arcadeObject(value)) return result;
    result.bestScore = arcadeInteger(value.bestScore);
    result.bestClean = arcadeInteger(value.bestClean);
    result.bestElapsedMs = arcadeTime(value.bestElapsedMs);
    result.plays = arcadeInteger(value.plays);
    result.splits = arcadeSplits(value.splits, result.bestElapsedMs);
    return result.plays ? result : arcadeEmptyRecord();
}

function arcadeRecordKey(key) {
    if (typeof key !== "string" || key.length > 65536 ||
        key.indexOf("arcade-v" + ARCADE_SCORING_VERSION + "|") !== 0) return false;
    var parts = key.split("|");
    if (ARCADE_MODES.indexOf(parts[1]) < 0) return false;
    try {
        var payload = JSON.parse(parts.slice(2).join("|"));
        return Array.isArray(payload) && payload.length === 2 && typeof payload[0] === "string" &&
            Array.isArray(payload[1]) && payload[1].length > 0 && payload[1].every(function(identity) {
                return Array.isArray(identity) && identity.length === 2 && typeof identity[0] === "string" &&
                    typeof identity[1] === "string" && identity[1] === keySignature(identity[1]) &&
                    arcadePlayableKeys(identity[1].split("+"));
            });
    } catch (error) {
        return false;
    }
}

function mergeStats(value) {
    var result = defaultStats();
    if (!arcadeObject(value)) return result;
    ARCADE_MODES.forEach(function(mode) {
        var source = arcadeObject(value[mode]) ? value[mode] : {};
        ARCADE_STAT_FIELDS.forEach(function(field) { result[mode][field] = arcadeInteger(source[field]); });
    });
    // v1 and unknown versions cannot establish comparable records or learning evidence.
    if (value.version !== 2) return result;
    if (arcadeObject(value.skills)) {
        Object.keys(value.skills).filter(function(signature) {
            return signature === keySignature(signature) && arcadePlayableKeys(signature.split("+"));
        }).sort(function(a, b) {
            return arcadeTime(value.skills[b] && value.skills[b].lastSeenAt) -
                arcadeTime(value.skills[a] && value.skills[a].lastSeenAt) || a.localeCompare(b);
        }).slice(0, ARCADE_SKILL_LIMIT).forEach(function(signature) {
            result.skills[signature] = arcadeSkill(value.skills[signature]);
        });
    }
    if (arcadeObject(value.records)) {
        Object.keys(value.records).filter(arcadeRecordKey).slice(-ARCADE_RECORD_LIMIT).forEach(function(key) {
            result.records[key] = arcadeRecord(value.records[key]);
        });
    }
    return result;
}

function deckKey(mode, deck, pace) {
    if (ARCADE_MODES.indexOf(mode) < 0 || !Array.isArray(deck) || !deck.length) return "";
    var identities = [];
    for (var i = 0; i < deck.length; i++) {
        var item = deck[i];
        if (!arcadeObject(item) || !arcadePlayableKeys(item.keys) ||
            item.signature !== keySignature(item.keys)) return "";
        identities.push([arcadeText(item.id), item.signature]);
    }
    var speed = typeof pace === "string" ? pace :
        (typeof pace === "number" && isFinite(pace) ? String(pace) : "standard");
    var key = "arcade-v" + ARCADE_SCORING_VERSION + "|" + mode + "|" + JSON.stringify([speed, identities]);
    return key.length <= 65536 ? key : "";
}

function bestForDeck(stats, key) {
    return arcadeRecordKey(key) && arcadeObject(stats) && stats.version === 2 &&
        arcadeObject(stats.records) ? arcadeRecord(stats.records[key]) : arcadeEmptyRecord();
}

function recordAttempt(stats, challenge, attempt, nowMs) {
    var result = mergeStats(stats);
    var now = nowMs === undefined ? Date.now() : nowMs;
    if (!arcadeCanonical([challenge]).length || !arcadeObject(attempt) ||
        typeof attempt.hinted !== "boolean" || !arcadeValidInteger(attempt.wrongAttempts, ARCADE_MAX_COUNT) ||
        !arcadeValidInteger(attempt.elapsedMs, ARCADE_MAX_TIME) ||
        !arcadeSessionId(attempt.sessionId) || !arcadeValidInteger(now, ARCADE_MAX_TIME)) return result;
    var signature = challenge.signature;
    var skill = result.skills[signature] || arcadeDefaultSkill();
    if (skill.attempts >= ARCADE_MAX_COUNT) return result;
    var elapsed = Math.min(attempt.elapsedMs, ARCADE_MAX_RECALL_MS);
    var clean = !attempt.hinted && attempt.wrongAttempts === 0;
    skill.attempts += 1;
    if (attempt.hinted) skill.assisted += 1;
    else skill.unassisted += 1;
    if (clean) {
        skill.firstTry += 1;
        skill.bestRecallMs = skill.firstTry === 1 ? elapsed : Math.min(skill.bestRecallMs, elapsed);
        skill.meanRecallMs += (elapsed - skill.meanRecallMs) / skill.firstTry;
        skill.successfulSessions = arcadeSessions(skill.successfulSessions.concat([
            { sessionId: attempt.sessionId, at: now }
        ]), skill.firstTry, Math.max(skill.lastSeenAt, now));
    }
    skill.lastSeenAt = Math.max(skill.lastSeenAt, now);
    skill.history.push({ at: now, sessionId: attempt.sessionId, hinted: attempt.hinted,
        wrongAttempts: attempt.wrongAttempts, elapsedMs: elapsed, clean: clean });
    result.skills[signature] = arcadeSkill(skill);
    return mergeStats(result);
}

function recordRun(stats, run, nowMs) {
    var result = mergeStats(stats);
    var now = nowMs === undefined ? Date.now() : nowMs;
    if (!arcadeObject(run) || ARCADE_MODES.indexOf(run.mode) < 0 ||
        !arcadeValidInteger(now, ARCADE_MAX_TIME)) return result;
    var mode = result[run.mode];
    mode.plays = Math.min(ARCADE_MAX_COUNT, mode.plays + 1);
    var total = arcadeInteger(run.total);
    var clean = Math.min(total, arcadeInteger(run.clean));
    // Timed Sprint counts answers, which can stop before or repeat beyond its deck.
    if (run.mode !== "sprint" && run.competitive === true && arcadeRecordKey(run.deckKey)) {
        var identities = JSON.parse(run.deckKey.split("|").slice(2).join("|"))[1];
        if (identities.length !== total) return result;
    }
    if (total > 0 && arcadeValidInteger(run.clean, total) && clean === total) {
        mode.clears = Math.min(ARCADE_MAX_COUNT, mode.clears + 1);
    }
    var prefix = "arcade-v" + ARCADE_SCORING_VERSION + "|" + run.mode + "|";
    if (run.competitive !== true || !arcadeRecordKey(run.deckKey) ||
        run.deckKey.indexOf(prefix) !== 0 || !total ||
        !arcadeValidInteger(run.score, ARCADE_MAX_COUNT) ||
        !arcadeValidInteger(run.clean, total) || !arcadeValidInteger(run.total, ARCADE_MAX_COUNT) ||
        !arcadeValidInteger(run.streak, clean) || !arcadeValidInteger(run.elapsedMs, ARCADE_MAX_TIME)) return result;
    var record = bestForDeck(result, run.deckKey);
    // Ghost splits belong to the highest-score run, with fastest elapsed time
    // breaking score ties. bestClean is the independent-count high across runs.
    if (!record.plays || run.score > record.bestScore ||
        (run.score === record.bestScore && run.elapsedMs < record.bestElapsedMs)) {
        record.bestScore = run.score;
        record.bestElapsedMs = run.elapsedMs;
        var splits = arcadeSplits(run.splits, run.elapsedMs);
        record.splits = splits.length === total ? splits : [];
    }
    record.bestClean = Math.max(record.bestClean, clean);
    record.plays = Math.min(ARCADE_MAX_COUNT, record.plays + 1);
    // Refresh insertion order so bounded storage keeps recently played decks.
    delete result.records[run.deckKey];
    result.records[run.deckKey] = record;
    return mergeStats(result);
}

// Compatibility for old callers only: these scores remain in the legacy namespace.
function recordResult(stats, mode, score, streak, cleared) {
    var result = mergeStats(stats);
    if (ARCADE_MODES.indexOf(mode) < 0) return result;
    result[mode].plays = Math.min(ARCADE_MAX_COUNT, result[mode].plays + 1);
    if (cleared === true) result[mode].clears = Math.min(ARCADE_MAX_COUNT, result[mode].clears + 1);
    result[mode].bestScore = Math.max(result[mode].bestScore, arcadeInteger(score));
    result[mode].bestStreak = Math.max(result[mode].bestStreak, arcadeInteger(streak));
    return result;
}

function arcadeWeak(skill) {
    if (!skill || !skill.attempts) return false;
    var latest = skill.history.length ? skill.history[skill.history.length - 1] : null;
    return !skill.firstTry || skill.firstTry / skill.attempts < 0.65 || !latest || !latest.clean;
}

function arcadeMastered(skill) {
    if (!skill || arcadeWeak(skill) || skill.successfulSessions.length < 2) return false;
    var sessions = skill.successfulSessions;
    return sessions[sessions.length - 1].at - sessions[0].at >= ARCADE_DAY_MS;
}

function arcadeDue(skill, now) {
    return !!skill && skill.attempts > 0 &&
        now - skill.lastSeenAt >= ARCADE_DAY_MS * (arcadeMastered(skill) ? 7 : 1);
}

function masterySummary(stats, challenges) {
    var skills = mergeStats(stats).skills;
    var canonical = arcadeCanonical(challenges);
    var now = Date.now();
    var result = { total: canonical.length, practiced: 0, learning: 0, independent: 0,
        mastered: 0, due: 0, weakIds: [], byCategory: [] };
    var categories = Object.create(null);
    canonical.forEach(function(challenge) {
        var category = arcadeText(challenge.category) || "general";
        if (!categories[category]) {
            categories[category] = { category: category, total: 0, practiced: 0, mastered: 0 };
            result.byCategory.push(categories[category]);
        }
        var group = categories[category];
        group.total += 1;
        var skill = skills[challenge.signature];
        if (!skill || !skill.attempts) return;
        result.practiced += 1;
        group.practiced += 1;
        if (arcadeMastered(skill)) { result.mastered += 1; group.mastered += 1; }
        else if (!arcadeWeak(skill)) result.independent += 1;
        else result.learning += 1;
        if (arcadeDue(skill, now)) result.due += 1;
        if (arcadeWeak(skill)) result.weakIds.push(challenge.id);
    });
    return result;
}

// Draw without replacement until the pool is exhausted. Slots rotate between
// due/weak review, new material (starter first), and familiar recall. Empty groups
// fall back to the remaining pool; a seeded shuffle breaks equal-priority ties.
// Starter priority applies to the opening card and new-material slots only, so
// short fresh runs can also discover intermediate and advanced shortcuts.
function practiceDeck(challenges, stats, count, random, category) {
    var size = count === undefined ? 12 : Math.min(arcadeInteger(count), 200);
    var pool = arcadeCanonical(challenges).filter(function(challenge) {
        return !category || category === "all" || challenge.category === category;
    });
    if (!size || !pool.length) return [];
    var skills = mergeStats(stats).skills;
    var now = Date.now();
    var deck = [];
    var remaining = [];
    var rank = { starter: 0, intermediate: 1, advanced: 2 };
    while (deck.length < size) {
        if (!remaining.length) remaining = shuffled(pool, random);
        var last = deck.length ? deck[deck.length - 1].signature : "";
        var available = remaining.filter(function(challenge) { return challenge.signature !== last || pool.length === 1; });
        if (!available.length) {
            // A final leftover cannot repeat the previous answer; start a new pass.
            remaining = shuffled(pool, random);
            available = remaining.filter(function(challenge) { return challenge.signature !== last; });
        }
        var slot = deck.length % 3;
        var candidates = available.filter(function(challenge) {
            var skill = skills[challenge.signature];
            if (slot === 0) return arcadeWeak(skill) || arcadeDue(skill, now);
            if (slot === 1) return !skill || !skill.attempts;
            return skill && skill.attempts && !arcadeWeak(skill) && !arcadeDue(skill, now);
        });
        if (!candidates.length) candidates = available;
        var chosen = candidates[0];
        function priority(challenge) {
            var skill = skills[challenge.signature];
            if (!skill || !skill.attempts) return slot === 1 || !deck.length ?
                10 - (rank[challenge.difficulty] === undefined ? 1 : rank[challenge.difficulty]) : 10;
            return (arcadeWeak(skill) ? 100 : 0) + (arcadeDue(skill, now) ? 50 : 0) +
                Math.min(30, Math.max(0, (now - skill.lastSeenAt) / ARCADE_DAY_MS));
        }
        for (var i = 1; i < candidates.length; i++) {
            if (priority(candidates[i]) > priority(chosen)) chosen = candidates[i];
        }
        deck.push(chosen);
        remaining.splice(remaining.indexOf(chosen), 1);
    }
    return deck;
}

function rescueMissions(challenges) {
    var canonical = arcadeCanonical(challenges);
    var byAction = Object.create(null);
    canonical.forEach(function(challenge) {
        if (!byAction[challenge.action]) byAction[challenge.action] = challenge;
    });
    return ARCADE_RESCUE_MISSIONS.map(function(definition) {
        var steps = [];
        for (var i = 0; i < definition.steps.length; i++) {
            var source = definition.steps[i];
            var challenge = byAction[source.action];
            if (!challenge) return null;
            steps.push({
                action: source.action,
                prompt: source.prompt,
                label: source.label,
                settledWorkspace: source.settledWorkspace,
                settledLabel: source.settledLabel,
                challenge: challenge
            });
        }
        return {
            id: definition.id,
            title: definition.title,
            callsign: definition.callsign,
            destination: definition.destination,
            arrival: definition.arrival,
            brief: definition.brief,
            success: definition.success,
            initialLabel: definition.initialLabel,
            steps: steps
        };
    }).filter(function(mission) { return !!mission; });
}

function chooseRescueMission(challenges, random, excludedId) {
    var missions = rescueMissions(challenges);
    if (!missions.length) return null;
    var alternatives = missions.filter(function(mission) {
        return missions.length === 1 || mission.id !== excludedId;
    });
    var nextRandom = typeof random === "function" ? random : Math.random;
    return alternatives[Math.floor(arcadeRandom(nextRandom) * alternatives.length)];
}

function rescueDeck(challenges, missionId) {
    var missions = rescueMissions(challenges);
    var mission = missions.filter(function(item) { return !missionId || item.id === missionId; })[0];
    return mission ? mission.steps.map(function(step) { return step.challenge; }) : [];
}

function recommendedPractice(challenges, stats) {
    var canonical = arcadeCanonical(challenges);
    var skills = mergeStats(stats).skills;
    var now = Date.now();
    var weak = canonical.filter(function(challenge) {
        return arcadeWeak(skills[challenge.signature]) || arcadeDue(skills[challenge.signature], now);
    });
    var fresh = canonical.filter(function(challenge) {
        return !skills[challenge.signature] || !skills[challenge.signature].attempts;
    });
    var pool = weak.length ? weak : fresh;
    if (!pool.length) return { category: "all", label: "Keep recall fresh",
        detail: canonical.length ? "No reviews are due. Choose any deck for more practice." : "No playable shortcuts are available in this course.", ids: [] };
    if (!weak.length) {
        var starters = pool.filter(function(challenge) { return challenge.difficulty === "starter"; });
        if (starters.length) pool = starters;
    }
    var counts = Object.create(null);
    var category = pool[0].category || "general";
    pool.forEach(function(challenge) {
        var name = challenge.category || "general";
        counts[name] = (counts[name] || 0) + 1;
        if (counts[name] > (counts[category] || 0)) category = name;
    });
    if (!weak.length && pool.some(function(challenge) { return challenge.category === "apps"; })) category = "apps";
    var selected = pool.filter(function(challenge) { return (challenge.category || "general") === category; });
    var labels = { apps: "app shortcuts", windows: "window shortcuts", workspaces: "workspace shortcuts",
        system: "system shortcuts", capture: "capture and sharing", general: "course shortcuts" };
    var needsRecall = selected.some(function(challenge) { return arcadeWeak(skills[challenge.signature]); });
    return {
        category: category,
        label: (weak.length ? "Review " : "Start with ") + (labels[category] || "course shortcuts"),
        detail: weak.length ? (needsRecall ? "Try these again without a hint, on the first attempt." :
            "These shortcuts are ready for spaced review.") : "Begin with a small theme. Every deck is available.",
        ids: selected.map(function(challenge) { return challenge.id; })
    };
}

function resultLabel(mode, clean, total) {
    var count = arcadeInteger(total);
    var independent = arcadeValidInteger(clean, count) ? clean : 0;
    if (count > 0 && independent === count) return "Perfect recall";
    return independent > 0 ? "Independent recall" : "Practice complete";
}
