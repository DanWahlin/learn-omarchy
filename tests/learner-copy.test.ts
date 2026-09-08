import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import type { Course } from "../src/course.ts";

const course: Course = JSON.parse(await readFile(new URL("../courses/omarchy-basics.json", import.meta.url), "utf8"));
const steps = new Map(course.lessons.flatMap(lesson => lesson.steps).map(step => [step.id, step]));
const instruction = (id: string) => steps.get(id)!.instruction;
const detail = (id: string) => steps.get(id)!.detail!;
const completion = (id: string) => steps.get(id)!.completionMessage!;

test("first-use orientation defines the keys and concepts a new learner needs", () => {
  assert.match(instruction("tour-welcome"), /Super is the Windows key/);
  assert.match(instruction("launch-terminal"), /Return is the Enter key/);
  assert.match(detail("launch-terminal"), /terminal is a window where you can type commands/);
  assert.match(detail("windows-focus-next"), /Focus means/);
  assert.match(instruction("upkeep-install"), /Arch User Repository, or AUR/);
});

test("rehearsals and preview tools describe what they actually do", () => {
  assert.match(instruction("sharing-practice"), /Nothing will be sent/);
  assert.match(instruction("web-app-practice"), /doesn't add anything to your Apps menu/);
  assert.match(detail("dictation-practice"), /doesn't start your microphone/);
  assert.match(detail("dictation-practice"), /not whether dictation produced it/);
  assert.match(completion("capture-practice"), /saved image itself is unchanged/);
  assert.match(completion("display-panel"), /apply immediately/);
  assert.doesNotMatch(completion("display-panel"), /before you commit/);
});

test("completion messages reinforce outcomes without claiming mastery or unperformed work", () => {
  const finale = course.lessons.find(lesson => lesson.id === "first-real-session")!;
  assert.doesNotMatch(finale.wrapUp!.text, /without touching the mouse|you did every/);
  assert.match(finale.wrapUp!.text, /Super and K/);
  assert.equal(steps.has("finale-graduate"), false);
  for (const step of steps.values()) {
    assert.doesNotMatch(step.completionMessage || "",
      /more.*than most people|Spotless|status crew|You completed the real task/);
  }
});

test("the tour teaches the hotkey outcome before pointing out the bar-icon alternative", () => {
  const tour = course.lessons.find(lesson => lesson.id === "omarchy-tour")!;
  const hotkeyIndex = tour.steps.findIndex(step => step.id === "tour-omarchy-menu");
  const hotkey = tour.steps[hotkeyIndex];
  const icon = tour.steps[hotkeyIndex + 1];
  assert.equal(hotkey.highlight.target, "panel");
  assert.equal(hotkey.highlight.barWidgets, undefined, "the menu result cannot target its launcher icon");
  assert.match(hotkey.completionMessage!, /menu in the center/);
  assert.deepEqual(hotkey.cleanup, ["omarchy", "menu", "close"]);
  assert.equal(icon.id, "tour-menu-icon");
  assert.equal(icon.kind, "tour");
  assert.deepEqual(icon.keys, []);
  assert.deepEqual(icon.highlight.barWidgets, ["omarchy.menu"]);
  assert.match(icon.instruction, /also click this icon/);
});

test("workspace orientation leads into two real Super-key actions before continuing along the bar", () => {
  const tour = course.lessons.find(lesson => lesson.id === "omarchy-tour")!;
  const start = tour.steps.findIndex(step => step.id === "tour-workspaces");
  assert.deepEqual(tour.steps.slice(start, start + 4).map(step => step.id),
    ["tour-workspaces", "tour-workspace-two", "tour-workspace-one", "tour-clock"]);
  for (const [id, workspace] of [["tour-workspace-two", 2], ["tour-workspace-one", 1]] as const) {
    const step = steps.get(id)!;
    assert.notEqual(step.kind, "tour", "an action must wait for the workspace, not narration or Next");
    assert.deepEqual(step.keys, ["SUPER", "+", String(workspace)]);
    assert.deepEqual(step.completion, { type: "hyprland-workspace-is", id: workspace });
    assert.equal(step.highlight.target, "workspace");
    assert.equal(step.highlight.workspaceId, workspace);
    assert.deepEqual(step.help!.command,
      ["hyprctl", "eval", `hl.dispatch(hl.dsp.focus({ workspace = "${workspace}" }))`]);
    assert.match(step.instruction, /[Hh]old Super.*top row.*release both keys/i);
    assert.ok(step.audio && step.completionAudio);
  }
  assert.match(detail("tour-workspace-one"), /If you started elsewhere/);
  assert.doesNotMatch(instruction("tour-omarchy-menu"), /first hotkey/);
});

test("scratchpad restoration first reveals and focuses the window that native shortcuts will move", () => {
  const lesson = course.lessons.find(lesson => lesson.id === "workspaces")!;
  const hide = lesson.steps.findIndex(step => step.id === "workspaces-scratchpad-hide");
  assert.deepEqual(lesson.steps.slice(hide, hide + 3).map(step => step.id),
    ["workspaces-scratchpad-hide", "workspaces-reveal-before-restore", "workspaces-restore"]);
  const reveal = steps.get("workspaces-reveal-before-restore")!;
  assert.deepEqual(reveal.keys, ["SUPER", "+", "S"]);
  assert.equal(reveal.windowFromStep, "workspaces-open-terminal");
  assert.equal(reveal.completion.target, "tutorial-window");
  assert.deepEqual(reveal.completion.windowState, { specialWorkspace: "scratchpad", focused: true });
});

test("essential cautions and keyboard alternatives are in the spoken instruction", () => {
  assert.match(instruction("tour-welcome"), /Alt is the Option key/);
  assert.match(instruction("capture-native-workflow"), /No Print key/);
  assert.match(instruction("dictation-practice"), /don't need an F9 key/);
  assert.match(instruction("upkeep-install"), /don't install anything/);
  assert.match(instruction("upkeep-defaults"), /keep your current settings/);
  assert.match(instruction("upkeep-updates"), /not running an update/);
  assert.match(instruction("upkeep-recovery"), /don't restart anything/);
  assert.match(completion("open-root-menu"), /Release Keys before typing/);
  assert.match(instruction("clipboard-practice"), /Shift and Enter to copy it without pasting/);
  assert.match(detail("clipboard-history"), /normally pastes/);
  assert.doesNotMatch(completion("apps-search-practice"), /found a terminal through search/);
  for (const id of ["tour-workspaces", "tour-clock", "tour-status"])
    assert.doesNotMatch(detail(id), /choose Skip/);
});
