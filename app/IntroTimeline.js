// Trusted, shared application code: imported by QML and the Node adapter.
var LIMITS = { layers: 24, actions: 256, depth: 4, duration: 30000, strings: 240 };
var EASINGS = ["linear", "inQuad", "outQuad", "inOutSine", "outCubic", "outBack"];
var BUILTIN_SOUNDS = ["rocket-land.opus", "rocket-liftoff.opus", "birds-welcome.opus"];
var THEME_COLORS = ["accent", "instruction", "foreground", "background", "muted", "urgent"];
var PROPS = ["x", "y", "offsetX", "offsetY", "opacity", "scale", "rotation", "visible",
             "pose", "facing", "flying", "text", "frame", "progress"];
var CHARACTER_PROPS = ["x", "y", "offsetX", "offsetY", "opacity", "scale", "rotation",
                       "visible", "pose", "facing", "flying"];
var NUMERIC_PROPS = ["x", "y", "offsetX", "offsetY", "opacity", "scale", "rotation", "progress"];

function object(value) { return value !== null && typeof value === "object" && !Array.isArray(value); }
function finite(value, min, max) { return typeof value === "number" && isFinite(value) && value >= min && value <= max; }
function own(value, key) { return Object.prototype.hasOwnProperty.call(value, key); }
function keys(value, allowed, path, errors) {
    if (!object(value)) { errors.push(path + " must be an object"); return false; }
    Object.keys(value).forEach(function(key) {
        if (allowed.indexOf(key) < 0) errors.push(path + ": unknown field " + key);
    });
    return true;
}
function assetPath(value) {
    return typeof value === "string" && value.length > 0 && value.length <= 240 &&
        /^[a-zA-Z0-9_.\/-]+$/.test(value) && value[0] !== "/" &&
        value.split("/").every(function(part) { return part !== "" && part !== "." && part !== ".."; }) &&
        /\.png$/.test(value);
}
function color(value) {
    return typeof value === "string" && (/^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(value) ||
        (value.indexOf("theme:") === 0 && THEME_COLORS.indexOf(value.substring(6)) >= 0));
}
function validateIntroSequence(value) {
    var errors = [];
    if (!keys(value, ["version", "layers", "character", "steps"], "sequence", errors)) return errors;
    if (value.version !== 1) errors.push("sequence.version must be 1");
    if (!Array.isArray(value.layers) || value.layers.length > LIMITS.layers) errors.push("layers must be an array of at most 24 layers");
    var layers = Array.isArray(value.layers) ? value.layers.slice(0, LIMITS.layers) : [];
    var targets = { character: { type: "character" } };
    var dependencies = {};
    layers.forEach(function(layer, i) {
        var path = "layers[" + i + "]";
        if (!keys(layer, ["id", "type", "images", "effect", "count", "colors", "background", "border", "period", "amplitude",
                          "width", "height", "aspect", "anchorX", "anchorY", "z", "fontSize", "typewriter", "state"], path, errors)) return;
        if (typeof layer.id !== "string" || !/^[a-z][a-z0-9-]{0,39}$/.test(layer.id) ||
            own(targets, layer.id) || ["constructor", "prototype", "__proto__"].indexOf(layer.id) >= 0) {
            errors.push(path + ".id must be a unique safe layer ID"); return;
        }
        targets[layer.id] = layer;
        dependencies[layer.id] = [];
        if (["image", "text", "effect"].indexOf(layer.type) < 0) errors.push(path + ".type is unsupported");
        if (layer.type === "image") {
            if (!Array.isArray(layer.images) || !layer.images.length || layer.images.length > 16 ||
                !layer.images.every(assetPath)) errors.push(path + ".images must contain 1–16 safe pack-relative image paths");
        } else if (own(layer, "images")) errors.push(path + ".images requires image type");
        if (layer.type === "effect" && ["specks", "plume", "burst", "strip"].indexOf(layer.effect) < 0)
            errors.push(path + ".effect is unsupported");
        if (own(layer, "effect") && layer.type !== "effect") errors.push(path + ".effect requires effect type");
        ["width", "height"].forEach(function(key) {
            if (!own(layer, key)) return;
            var size = layer[key];
            if (typeof size === "number") {
                if (!finite(size, 1, 4096)) errors.push(path + "." + key + " must be 1–4096 pixels");
            } else if (keys(size, ["viewport", "min", "max", "axis"], path + "." + key, errors)) {
                if (!finite(size.viewport, 0.001, 2) || !finite(size.min, 1, 4096) ||
                    !finite(size.max, size.min, 4096)) errors.push(path + "." + key + " has invalid viewport bounds");
                if (own(size, "axis") && ["width", "height"].indexOf(size.axis) < 0) errors.push(path + "." + key + ".axis is invalid");
            }
        });
        var bounds = { aspect: [0.05, 20], anchorX: [0, 1], anchorY: [0, 1], z: [-20, 20],
                       count: [1, 64], period: [100, 10000], amplitude: [0, 300], fontSize: [8, 64] };
        Object.keys(bounds).forEach(function(key) {
            if (own(layer, key) && (!finite(layer[key], bounds[key][0], bounds[key][1]) ||
                (key === "count" && layer[key] % 1 !== 0))) errors.push(path + "." + key + " is out of bounds");
        });
        if (own(layer, "typewriter") && typeof layer.typewriter !== "boolean") errors.push(path + ".typewriter must be boolean");
        if (own(layer, "colors") && (!Array.isArray(layer.colors) || layer.colors.length < 1 || layer.colors.length > 4 ||
            !layer.colors.every(color)))
            errors.push(path + ".colors must contain 1–4 hex colors or fixed theme tokens");
        ["background", "border"].forEach(function(key) {
            if (own(layer, key) && !color(layer[key])) errors.push(path + "." + key + " must be a hex color or fixed theme token");
        });
    });
    function state(props, target, tween, path) {
        if (!keys(props, target === "character" ? CHARACTER_PROPS : PROPS.filter(function(p) {
            return ["pose", "facing", "flying"].indexOf(p) < 0;
        }), path, errors)) return [];
        var definition = targets[target];
        Object.keys(props).forEach(function(key) {
            var v = props[key];
            if (tween && NUMERIC_PROPS.indexOf(key) < 0) errors.push(path + "." + key + " cannot be tweened");
            if (key === "x" || key === "y") {
                if (typeof v === "number") {
                    if (!finite(v, -2, 3)) errors.push(path + "." + key + " must be viewport-relative -2–3");
                } else if (keys(v, ["layer", "anchor", "offset"], path + "." + key, errors)) {
                    if (typeof v.layer !== "string" || !own(targets, v.layer) || v.layer === "character" || v.layer === target)
                        errors.push(path + "." + key + " references an unknown/self layer");
                    else if (target !== "character") dependencies[target].push(v.layer);
                    if (!finite(v.anchor, 0, 1) || (own(v, "offset") && !finite(v.offset, -4096, 4096)))
                        errors.push(path + "." + key + " has invalid anchor/offset");
                }
            } else if (key === "visible" || key === "flying") {
                if (typeof v !== "boolean") errors.push(path + "." + key + " must be boolean");
            } else if (key === "pose") {
                if (["idle", "point", "point-up"].indexOf(v) < 0) errors.push(path + ".pose is unsupported");
            } else if (key === "facing") {
                if (v !== 1 && v !== -1) errors.push(path + ".facing must be ±1");
            } else if (key === "text") {
                if (!definition || definition.type !== "text" || typeof v !== "string" || v.length > LIMITS.strings ||
                    /[\u0000-\u0008\u000b-\u001f]/.test(v) || v.replace(/\{displayName\}/g, "").match(/[{}]/))
                    errors.push(path + ".text must be bounded plain text; only {displayName} is substituted");
            } else if (key === "frame") {
                if (!definition || definition.type !== "image" || !finite(v, 0, (definition.images || []).length - 1) || v % 1)
                    errors.push(path + ".frame must index this layer's images");
            } else {
                var bounds = { opacity: [0, 1], scale: [0.01, 8], rotation: [-360, 360],
                    offsetX: [-4096, 4096], offsetY: [-4096, 4096], progress: [0, 1] };
                if (own(bounds, key) && !finite(v, bounds[key][0], bounds[key][1])) errors.push(path + "." + key + " is out of bounds");
            }
        });
        return Object.keys(props).map(function(key) { return target + "." + key; });
    }
    if (own(value, "character")) state(value.character, "character", false, "character");
    layers.forEach(function(layer, i) {
        if (object(layer) && typeof layer.id === "string" && own(dependencies, layer.id) && own(layer, "state"))
            state(layer.state, layer.id, false, "layers[" + i + "].state");
    });
    var count = 0;
    function steps(list, depth, path) {
        var duration = 0, writes = [];
        if (!Array.isArray(list) || list.length > LIMITS.actions) { errors.push(path + " must be a bounded step array"); return { duration: 0, writes: [] }; }
        if (depth > LIMITS.depth) { errors.push(path + " exceeds parallel nesting limit"); return { duration: 0, writes: [] }; }
        list.forEach(function(action, i) {
            count++;
            if (count > LIMITS.actions) return;
            var p = path + "[" + i + "]";
            if (!object(action)) { errors.push(p + " must be an action object"); return; }
            if (action.type === "parallel") {
                keys(action, ["type", "branches"], p, errors);
                if (!Array.isArray(action.branches) || !action.branches.length || action.branches.length > 8) {
                    errors.push(p + ".branches requires 1–8 step arrays"); return;
                }
                var longest = 0, branchWrites = [];
                action.branches.forEach(function(branch, j) {
                    var result = steps(branch, depth + 1, p + ".branches[" + j + "]");
                    result.writes.forEach(function(key) {
                        if (branchWrites.indexOf(key) >= 0) errors.push(p + ": parallel branches conflict on " + key);
                    });
                    branchWrites = branchWrites.concat(result.writes);
                    longest = Math.max(longest, result.duration);
                });
                writes = writes.concat(branchWrites);
                duration += longest;
            } else if (action.type === "wait") {
                keys(action, ["type", "duration"], p, errors);
                if (!finite(action.duration, 0, LIMITS.duration)) errors.push(p + ".duration is invalid");
                else duration += action.duration;
            } else if (action.type === "sound") {
                keys(action, ["type", "cue"], p, errors);
                if (BUILTIN_SOUNDS.indexOf(action.cue) < 0) errors.push(p + ".cue is not an allowlisted built-in sound");
            } else if (action.type === "set" || action.type === "tween") {
                keys(action, action.type === "set" ? ["type", "target", "to"] : ["type", "target", "to", "duration", "easing"], p, errors);
                if (typeof action.target !== "string" || !own(targets, action.target)) errors.push(p + ".target is unknown");
                else writes = writes.concat(state(action.to, action.target, action.type === "tween", p + ".to"));
                if (action.type === "tween") {
                    if (!finite(action.duration, 1, LIMITS.duration)) errors.push(p + ".duration must be 1–30000ms");
                    else duration += action.duration;
                    if (own(action, "easing") && EASINGS.indexOf(action.easing) < 0) errors.push(p + ".easing is unsupported");
                }
            } else errors.push(p + ".type is unsupported");
        });
        return { duration: duration, writes: writes.filter(function(v, i, all) { return all.indexOf(v) === i; }) };
    }
    var result = steps(value.steps, 0, "steps");
    if (count > LIMITS.actions) errors.push("sequence exceeds 256 actions");
    if (result.duration > LIMITS.duration) errors.push("sequence exceeds 30000ms");
    var visiting = {}, visited = {};
    function visit(id) {
        if (visiting[id]) { errors.push("cyclic layer attachment at " + id); return; }
        if (visited[id]) return;
        visiting[id] = true;
        (dependencies[id] || []).forEach(visit);
        visiting[id] = false; visited[id] = true;
    }
    Object.keys(dependencies).forEach(visit);
    return errors;
}
function introAssetPaths(value) {
    if (validateIntroSequence(value).length) return [];
    var paths = [];
    value.layers.forEach(function(layer) {
        (layer.images || []).forEach(function(path) { if (paths.indexOf(path) < 0) paths.push(path); });
    });
    return paths;
}
function copy(value) { return JSON.parse(JSON.stringify(value)); }
function defaults(character) {
    return { x: character ? 0.5 : 0, y: character ? 0.75 : 0,
        offsetX: character ? -112 : 0, offsetY: character ? -192 : 0,
        opacity: 1, scale: 1, rotation: 0, visible: !character,
        pose: "idle", facing: 1, flying: false, text: "", frame: 0, progress: 0, textAt: 0 };
}
function assign(target, source) { Object.keys(source || {}).forEach(function(key) { target[key] = source[key]; }); }
function compile(sequence) {
    var errors = validateIntroSequence(sequence);
    if (errors.length) throw new Error(errors.join("; "));
    var initial = { character: defaults(true) }, events = [], sounds = [];
    assign(initial.character, copy(sequence.character || {}));
    sequence.layers.forEach(function(layer) { initial[layer.id] = defaults(false); assign(initial[layer.id], copy(layer.state || {})); });
    function walk(steps, start) {
        var time = start;
        steps.forEach(function(step) {
            if (step.type === "parallel") {
                var end = time;
                step.branches.forEach(function(branch) { end = Math.max(end, walk(branch, time)); });
                time = end;
            } else if (step.type === "wait") time += step.duration;
            else if (step.type === "sound") sounds.push({ at: time, cue: step.cue, order: sounds.length });
            else {
                events.push({ at: time, duration: step.type === "tween" ? step.duration : 0,
                    target: step.target, to: copy(step.to), easing: step.easing || "linear", order: events.length });
                if (step.type === "tween") time += step.duration;
            }
        });
        return time;
    }
    var duration = walk(sequence.steps, 0);
    events.sort(function(a, b) { return a.at - b.at || a.order - b.order; });
    sounds.sort(function(a, b) { return a.at - b.at || a.order - b.order; });
    var endState = copy(initial);
    events.forEach(function(event) {
        event.from = {};
        Object.keys(event.to).forEach(function(key) {
            event.from[key] = endState[event.target][key];
            endState[event.target][key] = event.to[key];
        });
    });
    return { initial: initial, events: events, sounds: sounds, duration: duration, layers: copy(sequence.layers) };
}
function ease(name, t) {
    if (t <= 0) return 0;
    if (t >= 1) return 1;
    if (name === "inQuad") return t * t;
    if (name === "outQuad") return 1 - (1 - t) * (1 - t);
    if (name === "inOutSine") return -(Math.cos(Math.PI * t) - 1) / 2;
    if (name === "outCubic") return 1 - Math.pow(1 - t, 3);
    if (name === "outBack") { var c = 1.70158; return 1 + (c + 1) * Math.pow(t - 1, 3) + c * Math.pow(t - 1, 2); }
    return t;
}
function sample(timeline, elapsed, width, height, nativeSizes) {
    var states = copy(timeline.initial);
    timeline.events.forEach(function(event) {
        if (elapsed < event.at) return;
        var t = event.duration ? Math.min(1, (elapsed - event.at) / event.duration) : 1;
        var progress = ease(event.easing, t);
        Object.keys(event.to).forEach(function(key) {
            var to = event.to[key], from = event.from[key];
            states[event.target][key] = t >= 1 ? to :
                (key === "x" || key === "y") ? { mixFrom: from, mixTo: to, mix: progress } :
                from + (to - from) * progress;
            if (key === "text") states[event.target].textAt = event.at;
        });
    });
    var geometry = {}, definitions = {};
    timeline.layers.forEach(function(layer) { definitions[layer.id] = layer; });
    function size(value, viewport, fallback) {
        if (typeof value === "number") return value;
        if (value && value.axis) viewport = value.axis === "width" ? width : height;
        return value ? Math.max(value.min, Math.min(value.max, viewport * value.viewport)) : fallback;
    }
    function coordinate(value, axis) {
        if (typeof value === "number") return value * (axis === "x" ? width : height);
        if (own(value, "mix")) return coordinate(value.mixFrom, axis) * (1 - value.mix) + coordinate(value.mixTo, axis) * value.mix;
        var attached = layout(value.layer);
        return attached[axis] + attached[axis === "x" ? "width" : "height"] * value.anchor + (value.offset || 0);
    }
    function layout(id) {
        if (geometry[id]) return geometry[id];
        var layer = definitions[id] || {}, state = states[id], native = (nativeSizes || {})[id] || {};
        var h = id === "character" ? 192 : size(layer.height, height, native.height || 100);
        var w = id === "character" ? 224 : size(layer.width, width, h * (layer.aspect || (native.height ? native.width / native.height : 1)));
        var result = copy(state);
        result.width = w; result.height = h;
        result.x = coordinate(state.x, "x") + state.offsetX - w * (layer.anchorX || 0);
        result.y = coordinate(state.y, "y") + state.offsetY - h * (layer.anchorY || 0);
        geometry[id] = result;
        return result;
    }
    Object.keys(states).forEach(layout);
    return geometry;
}
