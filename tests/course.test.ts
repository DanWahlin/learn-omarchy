import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { parseCourseJson, validateCourse, type Course } from "../src/course.ts";

test("welcome lessons reuse the standalone flow and cannot contain hidden course actions", async () => {
  const original = JSON.parse(await readFile(new URL("../courses/omarchy-basics.json", import.meta.url), "utf8"));
  assert.deepEqual(parseCourseJson(JSON.stringify(original)).errors, []);
  for (const mutate of [
    (course: any) => { course.lessons[0].kind = "unknown"; },
    (course: any) => { course.lessons[0].steps = [course.lessons[1].steps[0]]; },
    (course: any) => { course.lessons[0].steps = null; },
    (course: any) => { course.lessons.push(course.lessons.shift()); },
  ]) {
    const course = structuredClone(original);
    mutate(course);
    assert.ok(parseCourseJson(JSON.stringify(course)).errors.length > 0);
  }
});

test("every taught topic has a wrap-up and malformed narration metadata is rejected", async () => {
  const original = JSON.parse(await readFile(new URL("../courses/omarchy-basics.json", import.meta.url), "utf8"));
  for (const lesson of original.lessons.filter((lesson: any) => lesson.kind !== "welcome")) {
    assert.ok(lesson.wrapUp.text.trim());
    assert.match(lesson.wrapUp.audio, /^audio\/wrapup-.*\.mp3$/);
  }
  for (const mutate of [
    (course: any) => { course.wrapUp.assisted.text = ""; },
    (course: any) => { course.wrapUp.explored.audio = "../outside.mp3"; },
    (course: any) => { delete course.wrapUp.assisted; },
    (course: any) => { course.lessons[1].wrapUp = { text: "Done." }; },
  ]) {
    const course = structuredClone(original);
    mutate(course);
    assert.ok(parseCourseJson(JSON.stringify(course)).errors.length > 0);
  }
});

test("owned-window presentation and scratchpad visibility metadata reject unsafe combinations", async () => {
  const original = JSON.parse(await readFile(new URL("../courses/omarchy-basics.json", import.meta.url), "utf8"));
  for (const mutate of [
    (step: any) => { step.windowSize = { width: -1, height: 600 }; },
    (step: any) => { step.windowSize = { width: 1200, height: 640 }; step.completion = { type: "action-success" }; },
    (step: any) => { step.completion = { type: "hyprland-event", events: ["activespecial"], target: "tutorial-window", windowState: { specialVisible: true } }; },
    (step: any) => { step.completion = { type: "hyprland-event", events: ["activespecial"], target: "tutorial-window", windowState: { specialWorkspace: "scratchpad", specialVisible: "yes" } }; },
  ]) {
    const course = structuredClone(original);
    const step = course.lessons.flatMap((lesson: any) => lesson.steps).find((step: any) => step.id === "launch-terminal");
    mutate(step);
    assert.ok(validateCourse(course).length > 0);
  }
});

test("practice prompts are optional for external courses but reject empty or oversized goals", async () => {
  const original = JSON.parse(await readFile(new URL("../courses/omarchy-basics.json", import.meta.url), "utf8"));
  for (const prompt of ["", "   ", "x".repeat(241), "First\nSecond", 123, null]) {
    const course = structuredClone(original);
    course.lessons[1].steps[0].practicePrompt = prompt;
    assert.ok(validateCourse(course).some(error => error.includes(".practicePrompt")));
  }
  for (const lesson of original.lessons)
    for (const step of lesson.steps) delete step.practicePrompt;
  assert.deepEqual(validateCourse(original), [], "existing courses can fall back to their full instruction");
});

test("secondary notes are optional but must be short single-paragraph text", async () => {
  const original = JSON.parse(await readFile(new URL("../courses/omarchy-basics.json", import.meta.url), "utf8"));
  for (const note of ["", "x".repeat(141), "First line\nSecond line", 123]) {
    const course = structuredClone(original);
    course.lessons[1].steps[0].note = note;
    assert.ok(parseCourseJson(JSON.stringify(course)).errors.some(error => error.includes(".note")));
  }
  const course = structuredClone(original);
  course.lessons[1].steps[0].note = "Your windows stay open.";
  assert.deepEqual(parseCourseJson(JSON.stringify(course)).errors, []);
});

test("bundled course is valid and covers the core curriculum", async () => {
  const json = await readFile(
    new URL("../courses/omarchy-basics.json", import.meta.url),
    "utf8",
  );
  const result = parseCourseJson(json);

  assert.deepEqual(result.errors, []);
  assert.ok((result.course?.lessons.length ?? 0) >= 7);
  assert.ok(
    (result.course?.lessons.reduce((total, lesson) => total + lesson.steps.length, 0) ?? 0) >= 18,
  );

  const barPanels = result.course?.lessons.find((lesson) => lesson.id === "bar-panels");
  assert.ok(barPanels);
  assert.ok(
    barPanels.steps.filter(step => ["audio-panel", "network-panel", "power-panel", "calendar-panel"].includes(step.id)).every(
      (step) =>
        step.completion.type === "hyprland-layer-open" &&
        step.completion.namespace === "omarchy-keyboard-panel",
    ),
  );

  const expectedShortcuts = new Map([
    ["tour-workspace-two", "SUPER + 2"],
    ["tour-workspace-one", "SUPER + 1"],
    ["tour-omarchy-menu", "SUPER + SPACE"],
    ["open-root-menu", "SUPER + SPACE"],
    ["open-apps", "SUPER + ALT + SPACE"],
    ["open-keybindings", "SUPER + K"],
    ["launch-terminal", "SUPER + RETURN"],
    ["close-terminal", "SUPER + W"],
    ["launch-browser", "SUPER + SHIFT + RETURN"],
    ["launch-files", "SUPER + SHIFT + F"],
    ["close-files", "SUPER + W"],
    ["windows-open-first", "SUPER + RETURN"],
    ["windows-open-second", "SUPER + RETURN"],
    ["windows-focus-next", "ALT + TAB"],
    ["windows-float", "SUPER + T"],
    ["windows-resize", "SUPER + EQUAL"],
    ["windows-resize-back", "SUPER + MINUS"],
    ["windows-split", "SUPER + J"],
    ["windows-split-restore", "SUPER + J"],
    ["windows-fullscreen", "SUPER + F"],
    ["windows-close-one", "SUPER + W"],
    ["windows-close-two", "SUPER + W"],
    ["workspaces-home", "SUPER + 1"],
    ["workspaces-open-terminal", "SUPER + RETURN"],
    ["workspaces-jump", "SUPER + 2"],
    ["workspaces-back", "SUPER + CTRL + TAB"],
    ["windows-exit-fullscreen", "SUPER + F"],
    ["windows-retile", "SUPER + T"],
    ["windows-focus-right", "SUPER + RIGHT"],
    ["windows-swap", "SUPER + SHIFT + RIGHT"],
    ["workspaces-stash", "SUPER + ALT + S"],
    ["workspaces-restore", "SUPER + SHIFT + 2"],
    ["workspaces-reveal-before-restore", "SUPER + S"],
    ["workspaces-close", "SUPER + W"],
    ["workspaces-send", "SUPER + SHIFT + 2"],
    ["next-workspace", "SUPER + TAB"],
    ["previous-workspace", "SUPER + SHIFT + TAB"],
    ["workspaces-scratchpad", "SUPER + S"],
    ["workspaces-scratchpad-hide", "SUPER + S"],
    ["audio-panel", "SUPER + CTRL + A"],
    ["network-panel", "SUPER + CTRL + W"],
    ["power-panel", "SUPER + CTRL + P"],
    ["calendar-panel", "SUPER + CTRL + ALT + D"],
    ["background-menu", "SUPER + CTRL + SPACE"],
    ["theme-menu", "SUPER + SHIFT + CTRL + SPACE"],
    ["toggle-menu", "SUPER + CTRL + O"],
    ["clipboard-history", "SUPER + CTRL + V"],
    ["helpers-emoji", "SUPER + CTRL + E"],
    ["helpers-reminder", "SUPER + CTRL + R"],
    ["capture-menu", "SUPER + CTRL + C"],
    ["share-menu", "SUPER + CTRL + S"],
    ["hardware-menu", "SUPER + CTRL + H"],
    ["display-panel", "SUPER + CTRL + D"],
    ["system-menu", "SUPER + ESCAPE"],
    ["tools-monitor-open", "SUPER + CTRL + T"],
    ["tools-monitor-close", "SUPER + W"],
    ["tools-calculator-open", "SUPER + CTRL + Q"],
    ["tools-calculator-close", "SUPER + W"],
    ["finale-home", "SUPER + 1"],
    ["finale-terminal", "SUPER + RETURN"],
    ["finale-browser", "SUPER + SHIFT + RETURN"],
    ["finale-send-browser", "SUPER + SHIFT + 2"],
    ["finale-back-to-one", "SUPER + 1"],
    ["finale-close-terminal", "SUPER + W"],
    ["finale-to-two", "SUPER + 2"],
    ["finale-close-browser", "SUPER + W"],
  ]);
  const allSteps = result.course?.lessons.flatMap((lesson) => lesson.steps) ?? [];
  const tourSteps = allSteps.filter((step) => step.kind === "tour");
  assert.equal(result.course?.lessons[0]?.id, "welcome");
  assert.equal(result.course?.lessons[0]?.kind, "welcome");
  assert.equal(result.course?.lessons[1]?.id, "omarchy-tour");
  assert.ok(tourSteps.length >= 3);
  assert.ok(
    tourSteps.every(
      (step) => step.completion.type === "narration-complete" && typeof step.audio === "string",
    ),
  );
  const keyedSteps = allSteps.filter((step) => !step.kind);
  assert.ok(keyedSteps.every((step) => step.keys.length > 0), "every non-tour activity teaches a real hotkey");

  assert.equal(keyedSteps?.length, expectedShortcuts.size);
  keyedSteps?.forEach((step) => {
    assert.equal(step.keys.join(" "), expectedShortcuts.get(step.id), step.id);
  });

  const appLaunches = result.course?.lessons.find((lesson) => lesson.id === "everyday-apps");
  assert.ok(appLaunches);
  assert.ok(
    appLaunches.steps.every(
      (step) =>
        step.completion.type === (step.id.startsWith("close-") ? "hyprland-event" : "hyprland-window-activated"),
    ),
  );
  const windowTargets = new Map([
    ["close-terminal", "launch-terminal"],
    ["close-files", "launch-files"],
    ["windows-focus-next", "windows-open-first"],
    ["windows-float", "windows-open-first"],
    ["windows-fullscreen", "windows-open-first"],
    ["windows-close-one", "windows-open-second"],
    ["windows-close-two", "windows-open-first"],
    ["workspaces-send", "workspaces-open-terminal"],
    ["finale-send-browser", "finale-browser"],
    ["finale-close-terminal", "finale-terminal"],
    ["finale-close-browser", "finale-browser"],
  ]);
  for (const [stepId, launchId] of windowTargets) {
    assert.equal(allSteps.find((step) => step.id === stepId)?.windowFromStep, launchId);
  }
});

test("tutorial window references must name an earlier launch in the same lesson", async () => {
  const json = await readFile(new URL("../courses/omarchy-basics.json", import.meta.url), "utf8");
  for (const reference of [undefined, "", "missing", "launch-files", "close-terminal", "finale-terminal"]) {
    const { course } = parseCourseJson(json);
    assert.ok(course);
    const step = course.lessons.flatMap((lesson) => lesson.steps)
      .find((step) => step.id === "close-terminal");
    assert.ok(step);
    step.windowFromStep = reference;
    assert.ok(validateCourse(course).some((error) => error.includes("windowFromStep")));
  }
});

const loadStep = async (id: string) => {
  const { course, errors } = parseCourseJson(
    await readFile(new URL("../courses/omarchy-basics.json", import.meta.url), "utf8"),
  );
  assert.deepEqual(errors, []);
  assert.ok(course);
  const step = course.lessons.flatMap((lesson) => lesson.steps).find((step) => step.id === id);
  assert.ok(step, id);
  return { course, step };
};

test("fallback reference viewports require finite positive dimensions", async () => {
  const { course } = await loadStep("tour-welcome");
  for (const value of [null, [], {}, { width: 0, height: 720 }, { width: 1280, height: -1 },
    { width: Infinity, height: 720 }, { width: "1280", height: 720 }]) {
    Object.assign(course, { referenceViewport: value });
    assert.ok(validateCourse(course).some(error => error.includes("referenceViewport")));
  }
  course.referenceViewport = { width: 1280, height: 720 };
  assert.deepEqual(validateCourse(course), []);
});

test("every window mutation and focus step is bound to an owned launch and exact Help selector", async () => {
  const { course } = await loadStep("windows-float");
  const protectedSteps = course.lessons.flatMap((lesson) => lesson.steps)
    .filter((step) => step.help?.command.some((part) => /hl\.dsp\.(window\.(close|float|fullscreen|move)|focus\(\{ window)/.test(part)));
  assert.ok(protectedSteps.length >= 17);
  for (const step of protectedSteps) {
    assert.ok(step.windowFromStep, step.id);
    assert.ok(step.help?.command.some((part) => part.includes('window = "{tutorialWindow}"')), step.id);
    assert.equal(step.completion.type, "hyprland-event");
    if (step.completion.type !== "hyprland-event") continue;
    assert.equal(step.completion.target, "tutorial-window", step.id);
    if (step.completion.events.includes("closewindow")) {
      assert.equal(step.completion.windowState, undefined, step.id);
    } else {
      assert.ok(step.completion.windowState, step.id);
    }
  }
});

test("semantic outcomes verify focus, float, fullscreen, and the destination workspace", async () => {
  for (const [id, expected, action] of [
    ["windows-focus-next", { focused: true }, 'hl.dsp.focus({ window = "{tutorialWindow}" })'],
    ["windows-float", { floating: true }, 'action = "enable"'],
    ["windows-fullscreen", { fullscreen: true }, 'action = "set"'],
    ["workspaces-send", { workspace: 2, focused: true }, 'workspace = "2"'],
    ["finale-send-browser", { workspace: 2, focused: true }, 'workspace = "2"'],
  ] as const) {
    const { step } = await loadStep(id);
    assert.equal(step.completion.type, "hyprland-event");
    if (step.completion.type !== "hyprland-event") continue;
    assert.deepEqual(step.completion.windowState, expected, id);
    assert.ok(step.help?.command.some((part) => part.includes(action)), id);
    assert.ok(!step.help?.command.some((part) => part.includes('"toggle"')), id);
  }
});

test("all protected steps reject missing, later, nonlaunch, self, or cross-lesson references", async () => {
  const { course } = await loadStep("windows-float");
  const protectedSteps = course.lessons.flatMap((lesson) => lesson.steps).filter((step) => step.windowFromStep);
  assert.ok(protectedSteps.length >= 18);
  for (const step of protectedSteps) {
    const original = step.windowFromStep;
    const foreignLaunch = step.id.startsWith("finale-") ? "windows-open-first" : "finale-terminal";
    for (const reference of [undefined, "", 12, "missing", step.id, "finale-graduate", foreignLaunch]) {
      Object.assign(step, { windowFromStep: reference });
      assert.ok(validateCourse(course).some((error) => error.includes("windowFromStep")), `${step.id}: ${reference}`);
    }
    step.windowFromStep = original;
  }
  const { course: laterCourse, step } = await loadStep("close-terminal");
  step.windowFromStep = "launch-files";
  assert.ok(validateCourse(laterCourse).some((error) => error.includes("earlier window-launch")));
});

test("window state validation rejects malformed values, unsupported fields, and wrong ownership", async () => {
  for (const state of [
    null, [], true, "", {}, { minimized: true },
    { floating: "true" }, { floating: 1 }, { fullscreen: null }, { focused: 0 },
    { workspace: 0 }, { workspace: 11 }, { workspace: 1.5 }, { workspace: "2" },
    { workspace: NaN }, { workspace: Infinity }, { workspace: undefined }, { swapped: false },
    { floating: true, fullscreen: false, typo: true },
  ]) {
    const { course, step } = await loadStep("windows-float");
    Object.assign(step.completion, { windowState: state });
    assert.ok(validateCourse(course).some((error) => error.includes("windowState")), JSON.stringify(state));
  }
  for (const target of [undefined, "", "active-window", null, ["tutorial-window"]]) {
    const { course, step } = await loadStep("windows-float");
    Object.assign(step.completion, { target });
    assert.ok(validateCourse(course).some((error) => error.includes("target")), JSON.stringify(target));
  }
  const { course, step } = await loadStep("windows-float");
  delete step.windowFromStep;
  assert.ok(validateCourse(course).some((error) => error.includes("windowFromStep")));
});

test("window state accepts explicit true and false and workspace boundaries", async () => {
  for (const state of [
    { floating: false }, { fullscreen: false }, { focused: false },
    { floating: true, fullscreen: true, focused: true, workspace: 1 },
    { floating: false, fullscreen: false, focused: false, workspace: 10 },
  ]) {
    const { course, step } = await loadStep("windows-float");
    Object.assign(step.completion, { windowState: state });
    assert.deepEqual(validateCourse(course), [], JSON.stringify(state));
  }
});

test("post-close state queries and state on other completion types are rejected", async () => {
  for (const events of [["closewindow"], ["closewindow", "activewindowv2"]]) {
    const { course, step } = await loadStep("windows-float");
    Object.assign(step.completion, { events });
    assert.ok(validateCourse(course).some((error) => error.includes('after "closewindow"')));
  }
  for (const id of ["launch-terminal", "open-root-menu", "workspaces-home", "tour-welcome"]) {
    const { course, step } = await loadStep(id);
    Object.assign(step.completion, { windowState: { focused: true } });
    assert.ok(validateCourse(course).some((error) => error.includes('only valid for "hyprland-event"')), id);
  }
});

test("event names and payload expressions are validated before use", async () => {
  for (const events of [[], [" "], ["closewindow", null], "closewindow"]) {
    const { course, step } = await loadStep("close-terminal");
    Object.assign(step.completion, { events });
    assert.ok(validateCourse(course).some((error) => error.includes(".events")));
  }
  for (const dataPattern of ["[", "", " ", 42, null]) {
    const { course, step } = await loadStep("close-terminal");
    Object.assign(step.completion, { dataPattern });
    assert.ok(validateCourse(course).some((error) => error.includes(".dataPattern")));
  }
});

test("application ID patterns are optional valid regexes limited to launch completion", async () => {
  for (const appIdPattern of ["[", "", " ", 42, null, []]) {
    const { course, step } = await loadStep("launch-files");
    Object.assign(step.completion, { appIdPattern });
    assert.ok(validateCourse(course).some((error) => error.includes("appIdPattern")), JSON.stringify(appIdPattern));
  }
  for (const appIdPattern of [undefined, "^org\\.gnome\\.Nautilus$", "Nautilus"]) {
    const { course, step } = await loadStep("launch-files");
    Object.assign(step.completion, { appIdPattern });
    assert.deepEqual(validateCourse(course), []);
  }
  const { course, step } = await loadStep("close-terminal");
  Object.assign(step.completion, { appIdPattern: "^kitty$" });
  assert.ok(validateCourse(course).some((error) => error.includes('only valid for "hyprland-window-activated"')));
});

test("bundled file launch filters Nautilus but configurable terminal and browser defaults remain supported", async () => {
  const { course, step } = await loadStep("launch-files");
  assert.equal(step.completion.type, "hyprland-window-activated");
  if (step.completion.type !== "hyprland-window-activated") return;
  assert.ok(step.completion.appIdPattern);
  const pattern = new RegExp(step.completion.appIdPattern, "i");
  for (const appId of ["org.gnome.Nautilus", "org.gnome.nautilus", "Nautilus", "nautilus"]) assert.ok(pattern.test(appId), appId);
  for (const appId of ["kitty", "org.gnome.Nautilus.other", "not-nautilus", "chromium"]) assert.ok(!pattern.test(appId), appId);
  const configurable = course.lessons.flatMap((lesson) => lesson.steps)
    .filter((step) => step.help?.command[0] === "omarchy" &&
      ["terminal", "browser"].includes(step.help.command[2] ?? ""));
  assert.equal(configurable.length, 7);
  for (const step of configurable) {
    assert.equal(step.completion.type, "hyprland-window-activated");
    if (step.completion.type === "hyprland-window-activated") {
      assert.equal(step.completion.appIdPattern, undefined, step.id);
    }
  }
});

test("bundled highlights select semantic windows, panels, and workspace destinations", async () => {
  const { course } = await loadStep("windows-float");
  for (const step of course.lessons.flatMap((lesson) => lesson.steps)) {
    if (step.kind) continue;
    const completion = step.completion;
    assert.ok(step.highlight.target, step.id);
    if (completion.type === "hyprland-layer-open") assert.equal(step.highlight.target, "panel", step.id);
    if (completion.type === "hyprland-window-activated") assert.equal(step.highlight.target, "window", step.id);
    if (completion.type === "hyprland-workspace-is") {
      assert.equal(step.highlight.target, "workspace", step.id);
      assert.equal(step.highlight.workspaceId, completion.id, step.id);
    }
    if (completion.type === "hyprland-event" && completion.windowState?.workspace) {
      assert.equal(completion.windowState.focused, true, step.id);
      assert.equal(step.highlight.target, "workspace", step.id);
      assert.equal(step.highlight.workspaceId, completion.windowState.workspace, step.id);
    }
  }
});

test("workspace tour highlights the whole group rather than a single destination", async () => {
  const { step } = await loadStep("tour-workspaces");
  assert.equal(step.kind, "tour");
  assert.equal(step.highlight.dynamic, "workspaces");
  assert.equal(step.highlight.target, undefined);
  assert.equal(step.highlight.workspaceId, undefined);
  assert.deepEqual(step.highlight.barWidgets, ["omarchy.menu", "omarchy.workspaces"]);
});

test("bar widget targets require usable identifiers", async () => {
  for (const barWidgets of [null, [], "", [" "], [1], {}]) {
    const { course, step } = await loadStep("tour-clock");
    Object.assign(step.highlight, { barWidgets });
    assert.ok(validateCourse(course).some((error) => error.includes("barWidgets")));
  }
});

test("reminders open, detect and close the reminder surface, not the menu", async () => {
  const { step } = await loadStep("helpers-reminder");
  assert.deepEqual(step.help?.command, ["omarchy-shell", "shell", "summon", "omarchy.reminders"]);
  assert.deepEqual(step.cleanup, ["omarchy-shell", "shell", "hide", "omarchy.reminders"]);
  assert.deepEqual(step.completion, { type: "hyprland-layer-open", namespace: "omarchy-reminders" });
  assert.match(step.detail || "", /minutes first/);
});

test("semantic highlights validate target and workspace IDs while preserving geometry fallback", async () => {
  for (const target of ["active-window", "", null, 1, ["window"]]) {
    const { course, step } = await loadStep("windows-float");
    Object.assign(step.highlight, { target });
    assert.ok(validateCourse(course).some((error) => error.includes("highlight.target")));
  }
  for (const workspaceId of [0, 11, -1, 1.5, "2", null, NaN, Infinity]) {
    const { course, step } = await loadStep("workspaces-home");
    Object.assign(step.highlight, { workspaceId });
    assert.ok(validateCourse(course).some((error) => error.includes("workspaceId")));
  }
  for (const target of [undefined, "window", "panel"]) {
    const { course, step } = await loadStep("workspaces-home");
    Object.assign(step.highlight, { target });
    assert.ok(validateCourse(course).some((error) => error.includes('requires target "workspace"')));
  }
  for (const target of [undefined, "window", "workspace", "panel"]) {
    const { course, step } = await loadStep("windows-float");
    Object.assign(step.highlight, { target });
    assert.deepEqual(validateCourse(course), []);
  }
  const { course, step } = await loadStep("workspaces-home");
  step.highlight.workspaceId = 10;
  assert.deepEqual(validateCourse(course), []);
  Object.assign(step.highlight, { width: undefined });
  assert.ok(validateCourse(course).some((error) => error.includes("highlight.width")));
});

test("hands-on tasks are verified exercises and optional activities don't block the core", async () => {
  const { course } = await loadStep("clipboard-practice");
  const practices = course.lessons.flatMap(lesson => lesson.steps).filter(step => step.kind === "practice");
  assert.deepEqual(practices.map(step => step.practice).sort(), ["app-search", "capture", "clipboard", "compose", "dictation", "ocr", "qr", "screen-lock", "screen-recording", "sharing", "transcode", "web-app"]);
  for (const step of practices) {
    assert.equal(step.completion.type, "practice-result");
    assert.deepEqual(step.keys, []);
    assert.equal(step.help, undefined);
  }
  assert.equal(practices.find(step => step.practice === "screen-lock")?.optional, true);
  assert.equal(course.lessons.find(lesson => lesson.id === "bar-panels")?.optional, true);
  assert.equal(course.lessons.find(lesson => lesson.id === "productivity-extras")?.optional, true);
});

test("practice contracts reject commands and misleading completion detectors", async () => {
  for (const change of [
    { practice: "unknown" }, { practice: ["clipboard"] },
    { keys: ["SUPER", "+", "C"] }, { actionLabel: "" },
    { help: { label: "fake", command: ["true"] } }, { cleanup: ["true"] },
    { completion: { type: "action-success" } },
    { completion: { type: "practice-result", windowState: { focused: true } } },
    { completionMessage: 42 }, { optional: "yes" }, { pose: "talk" },
  ]) {
    const { course, step } = await loadStep("clipboard-practice");
    Object.assign(step, change);
    assert.ok(validateCourse(course).length > 0, JSON.stringify(change));
  }
});

test("all step kinds validate shared fields once", () => {
  for (const kind of [undefined, "tour", "practice"] as const) {
    const template: Course = {
      schemaVersion: 2, id: "shared-fields", title: "Shared fields", description: "Validation fixture",
      lessons: [{
        id: "lesson", title: "Lesson", description: "Lesson", icon: "book", estimatedMinutes: 1,
        steps: [{
          id: "step", instruction: "Follow the instruction.", kind,
          keys: kind ? [] : ["SUPER", "+", "SPACE"],
          audio: "audio/instruction.mp3",
          completionAudio: "audio/completed.mp3", completionMessage: "Completed.",
          highlight: { shape: "rectangle", anchor: "center", x: 0, y: 0, width: 100, height: 100, borderWidth: 2 },
          ...(kind === "practice"
            ? { practice: "clipboard", actionLabel: "Practice", completion: { type: "practice-result" } }
            : kind === "tour"
              ? { completion: { type: "narration-complete" } }
              : { help: { label: "Help", command: ["example"] }, completion: { type: "action-success" } }),
        }],
      }],
    };
    assert.deepEqual(validateCourse(template), []);
    for (const [change, field] of [
      [{ audio: "../outside.mp3" }, ".audio"],
      [{ completionAudio: "../outside.mp3" }, ".completionAudio"],
      [{ completionMessage: "" }, ".completionMessage"],
      [{ highlight: null }, ".highlight"],
      [{ completion: null }, ".completion must be an object"],
      [{ cleanup: "not-an-argument-array" }, ".cleanup"],
    ] as const) {
      const course = structuredClone(template);
      const step = course.lessons[0].steps[0];
      Object.assign(step, change);
      const errors = validateCourse(course).filter(error => error.includes(field));
      assert.equal(errors.length, 1, `${kind}: ${JSON.stringify(change)}: ${errors.join(", ")}`);
    }
    delete template.lessons[0].steps[0].completionMessage;
    assert.ok(validateCourse(template).some(error => error.includes("requires a completionMessage")), kind);
  }
});

test("swap requires distinct earlier launch references and a verified pair", async () => {
  for (const change of [
    { swapWithStep: "missing" }, { swapWithStep: undefined },
    { windowFromStep: "windows-open-first", swapWithStep: "windows-open-first" },
    { completion: { type: "hyprland-event", events: ["activewindowv2"], target: "tutorial-window", windowState: { focused: true } } },
  ]) {
    const { course, step } = await loadStep("windows-swap");
    Object.assign(step, change);
    assert.ok(validateCourse(course).some(error => error.includes("swapWithStep")), JSON.stringify(change));
  }
});

test("directional focus requires an earlier distinct source and one arrow", async () => {
  for (const change of [
    { directionFromStep: "missing" }, { directionFromStep: "windows-open-second" },
    { directionFromStep: 42 }, { keys: ["SUPER", "+", "A"] },
    { keys: ["SUPER", "+", "LEFT", "+", "RIGHT"] },
    { completion: { type: "hyprland-event", events: ["activewindowv2"], target: "tutorial-window", windowState: { floating: false } } },
  ]) {
    const { course, step } = await loadStep("windows-focus-right");
    Object.assign(step, change);
    assert.ok(validateCourse(course).length > 0, JSON.stringify(change));
  }
});

test("Help and cleanup tutorial selectors require launch references without a targeted completion", async () => {
  for (const field of ["help", "cleanup"] as const) {
    const { course, step } = await loadStep("workspaces-home");
    const command = ["example", "{tutorialWindow}"];
    if (field === "help") step.help = { label: "Help", command };
    else step.cleanup = command;
    assert.ok(validateCourse(course).some((error) => error.includes("windowFromStep")), field);
  }
});

test("rejects shell strings and unsafe audio paths", () => {
  const errors = validateCourse({
    schemaVersion: 2,
    id: "unsafe",
    title: "Unsafe",
    description: "Unsafe course",
    lessons: [
      {
        id: "lesson",
        title: "Lesson",
        description: "Lesson description",
        icon: "01",
        estimatedMinutes: 1,
        steps: [
          {
            id: "step",
            instruction: "Do something",
            keys: ["SUPER", "+", "A"],
            audio: "../outside.mp3",
            help: { label: "Help", command: "rm -rf /" },
            completion: { type: "action-success" },
            highlight: {
              shape: "rectangle",
              anchor: "center",
              x: 0,
              y: 0,
              width: 200,
              height: 100,
              borderWidth: 4,
            },
          },
        ],
      },
    ],
  });

  assert.ok(errors.some((error) => error.includes("safe path")));
  assert.ok(errors.some((error) => error.includes("array of non-empty strings")));
});

test("requires a label for button-driven steps", () => {
  const errors = validateCourse({
    schemaVersion: 2,
    id: "button",
    title: "Button",
    description: "Button course",
    lessons: [
      {
        id: "lesson",
        title: "Lesson",
        description: "Lesson description",
        icon: "01",
        estimatedMinutes: 1,
        steps: [
          {
            id: "step",
            instruction: "Explore",
            keys: [],
            help: { label: "Open", command: ["example"] },
            completion: { type: "action-success", delayMs: 100 },
            highlight: {
              shape: "circle",
              anchor: "center",
              x: 0,
              y: 0,
              width: 100,
              height: 100,
              borderWidth: 4,
            },
          },
        ],
      },
    ],
  });

  assert.ok(errors.some((error) => error.includes("actionLabel")));
});

test("requires equal dimensions for circle highlights", () => {
  const errors = validateCourse({
    schemaVersion: 2,
    id: "circle",
    title: "Circle",
    description: "Circle course",
    lessons: [
      {
        id: "lesson",
        title: "Lesson",
        description: "Lesson description",
        icon: "01",
        estimatedMinutes: 1,
        steps: [
          {
            id: "step",
            instruction: "Find the target",
            keys: ["A"],
            help: { label: "Show", command: ["example"] },
            completion: { type: "hyprland-layer-open", namespace: "example" },
            highlight: {
              shape: "circle",
              anchor: "center",
              x: 0,
              y: 0,
              width: 100,
              height: 80,
              borderWidth: 4,
            },
          },
        ],
      },
    ],
  });

  assert.ok(errors.some((error) => error.includes("equal width and height")));
});

test("rejects noncanonical and unsupported shortcut labels", () => {
  const course = {
    schemaVersion: 2,
    id: "keys",
    title: "Keys",
    description: "Key validation",
    lessons: [
      {
        id: "lesson",
        title: "Lesson",
        description: "Lesson description",
        icon: "01",
        estimatedMinutes: 1,
        steps: [
          {
            id: "step",
            instruction: "Press the shortcut",
            keys: ["super", "+", "F1"],
            help: { label: "Run", command: ["example"] },
            completion: { type: "action-success" },
            highlight: {
              shape: "rectangle",
              anchor: "center",
              x: 0,
              y: 0,
              width: 100,
              height: 80,
              borderWidth: 4,
            },
          },
        ],
      },
    ],
  };

  const errors = validateCourse(course);

  assert.ok(errors.some((error) => error.includes("canonical uppercase label")));
  assert.ok(errors.some((error) => error.includes('"F1" is not supported')));
});
