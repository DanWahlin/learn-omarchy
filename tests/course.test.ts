import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { parseCourseJson, validateCourse } from "../src/course.ts";

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
    barPanels.steps.every(
      (step) =>
        step.completion.type === "hyprland-layer-open" &&
        step.completion.namespace === "omarchy-keyboard-panel",
    ),
  );

  const expectedShortcuts = new Map([
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
    ["windows-fullscreen", "SUPER + F"],
    ["windows-close-one", "SUPER + W"],
    ["windows-close-two", "SUPER + W"],
    ["workspaces-open-terminal", "SUPER + RETURN"],
    ["workspaces-jump", "SUPER + 2"],
    ["workspaces-back", "SUPER + 1"],
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
  assert.equal(result.course?.lessons[0]?.id, "omarchy-tour");
  assert.ok(tourSteps.length >= 3);
  assert.ok(
    tourSteps.every(
      (step) => step.completion.type === "narration-complete" && typeof step.audio === "string",
    ),
  );
  const keyedSteps = allSteps.filter((step) => step.kind !== "tour");
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
