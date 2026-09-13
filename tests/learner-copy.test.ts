import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import type { Course } from "../src/course.ts";

const course: Course = JSON.parse(await readFile(new URL("../courses/omarchy-basics.json", import.meta.url), "utf8"));
const steps = new Map(course.lessons.flatMap(lesson => lesson.steps).map(step => [step.id, step]));
const instruction = (id: string) => steps.get(id)!.instruction;
const detail = (id: string) => steps.get(id)!.detail!;
const completion = (id: string) => steps.get(id)!.completionMessage!;

test("every shortcut practice step has a concrete goal instead of a Help-button label", () => {
  for (const step of steps.values()) {
    if (!step.help) continue;
    assert.ok(step.practicePrompt && step.practicePrompt.length <= 240, step.id);
    assert.notEqual(step.practicePrompt, step.help.label.replace(/ for me$/i, "") + ".", step.id);
    assert.doesNotMatch(step.practicePrompt, /^(Take me there|Switch for me|Show me how|Open it|Close it|Move it)\.?$/i, step.id);
    assert.doesNotMatch(step.practicePrompt, /\bSuper\b|\bControl\b|\bShift\b|\bAlt\b/, step.id);
  }
  assert.match(steps.get("workspaces-home")!.practicePrompt!, /workspace one/);
  assert.match(steps.get("workspaces-send")!.practicePrompt!, /terminal.*workspace two/);
  assert.match(steps.get("workspaces-restore")!.practicePrompt!, /terminal.*scratchpad.*workspace two/);
  assert.match(steps.get("open-keybindings")!.practicePrompt!, /Read only.*runs that shortcut/);
  assert.match(steps.get("hardware-menu")!.practicePrompt!, /selecting.*immediately/);
});

test("first-use orientation defines the keys and concepts a new learner needs", () => {
  assert.match(instruction("tour-welcome"), /You'll use the Super key for many of Omarchy's keyboard shortcuts/);
  assert.match(instruction("tour-welcome"), /On a Mac keyboard, that's Command/);
  assert.match(instruction("tour-welcome"), /On a Windows keyboard, it's the Windows-logo key/);
  assert.doesNotMatch(instruction("tour-welcome"), /Alt|Option/);
  assert.match(instruction("launch-terminal"), /Return is the Enter key/);
  assert.match(detail("launch-terminal"), /terminal is a window where you can type commands/);
  assert.match(detail("windows-focus-next"), /Focus means/);
  assert.match(instruction("upkeep-install"), /Arch User Repository, or AUR/);
});

test("the opening tour visibly points at the desktop bar it describes", () => {
  const step = steps.get("tour-welcome")!;
  assert.equal(step.pose, "point", "talk-only poses suppress the tour outline");
  assert.equal(step.highlight.shape, "rectangle");
  assert.ok(step.highlight.width > 1000);
  for (const id of ["omarchy.menu", "omarchy.workspaces", "omarchy.clock", "omarchy.audio", "omarchy.power"])
    assert.ok(step.highlight.barWidgets!.includes(id));
});

test("rehearsals and preview tools describe what they actually do", () => {
  assert.match(instruction("sharing-practice"), /Nothing will be sent/);
  assert.match(instruction("web-app-practice"), /doesn't add anything to your Apps menu/);
  assert.match(detail("dictation-practice"), /doesn't start your microphone/);
  assert.match(detail("dictation-practice"), /not whether dictation produced it/);
  assert.match(completion("capture-practice"), /saved image itself is unchanged/);
  assert.match(completion("display-panel"), /apply immediately/);
  assert.doesNotMatch(completion("display-panel"), /before you commit/);
  assert.equal(steps.get("apps-search-practice")!.actionLabel, "Start search");
  assert.match(instruction("apps-search-practice"), /Open the Apps menu with Super, Alt, and Space/);
  assert.match(detail("apps-search-practice"), /no separate exercise window opens/);
  assert.doesNotMatch(detail("apps-search-practice"), /choose Finish exercise/);
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
  assert.match(instruction("open-apps"), /Alt is the Option key/);
  assert.match(instruction("capture-native-workflow"), /No Print key/);
  assert.match(instruction("dictation-practice"), /don't need an F9 key/);
  assert.match(instruction("upkeep-install"), /don't install anything/);
  assert.match(instruction("upkeep-defaults"), /keep your current settings/);
  assert.match(instruction("upkeep-updates"), /not running an update/);
  assert.match(instruction("upkeep-recovery"), /don't restart anything/);
  assert.match(completion("open-root-menu"), /course will close it when you continue/);
  assert.doesNotMatch(completion("open-root-menu"), /Release Keys|Capture Keys/);
  assert.match(instruction("clipboard-practice"), /Shift and Enter to copy it without pasting/);
  assert.match(detail("clipboard-history"), /normally pastes/);
  assert.doesNotMatch(completion("apps-search-practice"), /found a terminal through search/);
  for (const id of ["tour-workspaces", "tour-clock", "tour-status"])
    assert.doesNotMatch(detail(id), /choose Skip/);
});

test("lesson content stays focused on Omarchy instead of keyboard-capture mechanics", () => {
  for (const step of steps.values()) {
    for (const field of ["instruction", "detail", "note", "completionMessage", "practicePrompt"] as const) {
      const text = step[field];
      if (typeof text !== "string") continue;
      assert.doesNotMatch(text, /Release Keys|Capture Keys|keyboard capture/i, `${step.id}.${field}`);
    }
  }
});

test("hardware-dependent and multi-monitor guidance is explicit", () => {
  const power = course.lessons.flatMap(lesson => lesson.steps).find(step => step.id === "power-panel");
  const capture = course.lessons.flatMap(lesson => lesson.steps).find(step => step.id === "capture-native-workflow");
  assert.ok(power);
  assert.equal(power.optional, true);
  assert.match(`${power.detail} ${power.note}`, /without a battery/i);
  assert.ok(capture);
  assert.match(capture.detail, /focused monitor, not the entire multi-monitor desktop/i);
});

test("secondary notes are concise and keep important cautions visible", () => {
  for (const step of steps.values()) {
    if (step.note) {
      assert.ok(step.note.length <= 140, step.id);
      assert.ok(step.note.split(/\s+/).length <= 18, step.id);
      assert.doesNotMatch(step.note, /[\r\n]/);
    }
  }
  assert.equal(steps.get("tour-workspace-two")!.note, "Your windows stay open when you switch workspaces.");
  assert.match(steps.get("display-panel")!.note!, /apply immediately/);
  assert.match(steps.get("clipboard-practice")!.note!, /replaces your clipboard/);
  assert.match(steps.get("lock-practice")!.note!, /password/);
  assert.match(steps.get("capture-practice")!.note!, /not private windows/);
  assert.equal(steps.get("finale-to-two")!.note, undefined);
  assert.equal(steps.get("finale-to-two")!.detail, undefined);
});

test("hardware orientation describes Trigger controls and warns before opening", () => {
  assert.match(instruction("hardware-menu"), /selecting an action can change device behavior immediately/);
  assert.match(instruction("hardware-menu"), /don't select an action/);
  assert.match(steps.get("hardware-menu")!.note!, /selecting a hardware action.*immediately/);
  assert.match(detail("hardware-menu"), /Trigger > Hardware/);
  assert.match(detail("hardware-menu"), /Depending on your hardware/);
  for (const label of ["Laptop Display", "Mirror Display", "Hybrid GPU", "Touchpad", "Touchpad Haptics", "Touchscreen"])
    assert.ok(detail("hardware-menu").includes(label), label);
  assert.match(detail("hardware-menu"), /Audio, Bluetooth, and Display have separate panels/);
  assert.match(detail("hardware-menu"), /Setup > Input or Setup > Keybindings/);
  assert.match(completion("hardware-menu"), /Install and Update sit alongside Trigger at the root/);
  assert.doesNotMatch(completion("hardware-menu"), /one level up/);
});

test("the shortcut guide prominently warns that results execute commands", () => {
  assert.match(instruction("open-keybindings"), /Read only for this lesson/);
  assert.match(instruction("open-keybindings"), /Enter or clicking a result runs that shortcut/);
  assert.match(instruction("open-keybindings"), /close windows or lock your screen/);
  assert.match(steps.get("open-keybindings")!.note!, /Read only.*Enter or clicking a result runs the shortcut/);
  assert.match(detail("open-keybindings"), /without activating a result/);
  assert.match(completion("open-keybindings"), /Looking is enough for this lesson/);
});

test("native recordings describe combined inputs using the actual menu labels", () => {
  for (const label of [
    "With no audio", "With desktop audio", "With desktop + microphone audio",
    "With desktop + microphone audio + webcam"
  ]) assert.ok(detail("recording-intro").includes(`"${label}"`), label);
  assert.match(detail("recording-intro"), /when a webcam is available/);
  assert.match(instruction("recording-intro"), /Microphone includes desktop audio; webcam includes both/);
  assert.match(steps.get("recording-intro")!.note!, /Webcam includes desktop and microphone audio/);
  assert.match(detail("recording-intro"), /practice recording is silent and limited to a region/);
  assert.doesNotMatch(detail("recording-intro"), /No audio, desktop audio, microphone, and webcam are different choices/);
});

test("native search cancellation clears entered text before closing", () => {
  const cancellationCopy = [
    detail("clipboard-history"), detail("upkeep-defaults"), detail("helpers-reminder"),
    completion("helpers-reminder"), steps.get("helpers-reminder")!.note!, detail("share-menu")
  ];
  for (const text of cancellationCopy) {
    assert.match(text, /Escape clears typed text; press (?:it )?again to close, or once if empty/);
    assert.doesNotMatch(text, /Escape cancels|Escape to leave without scheduling/);
  }
});

test("dictation replacements use the installed configuration, not a nonexistent setup menu", () => {
  assert.match(instruction("dictation-corrections"), /No edits for this lesson/);
  assert.match(instruction("dictation-corrections"), /back up the file first/);
  assert.match(detail("dictation-corrections"), /~\/\.config\/voxtype\/config\.toml/);
  assert.match(detail("dictation-corrections"), /commented \[text\] replacements example/);
  assert.match(detail("dictation-corrections"), /Install > AI > Dictation installs the tool; it isn't a configuration menu/);
  assert.match(detail("dictation-corrections"), /Remove > Dictation removes it/);
  assert.doesNotMatch(detail("dictation-corrections"), /Find dictation setup/);
});

test("workspace orientation allows the active marker to replace the number", () => {
  assert.match(instruction("tour-workspaces"), /may replace its number with an icon/);
  assert.match(completion("tour-workspace-two"), /active marker at workspace two's position/);
  assert.match(completion("tour-workspace-two"), /icon instead of a number/);
  for (const text of [instruction("tour-workspaces"), completion("tour-workspace-two")])
    assert.doesNotMatch(text, /highlighted number|number is now highlighted/);
});

test("Display lists actual conditional controls and separates resolution configuration", () => {
  assert.match(instruction("display-panel"), /changes apply immediately.*leave the controls unchanged/);
  assert.match(detail("display-panel"), /text size and scale, brightness where supported/);
  assert.match(detail("display-panel"), /display enable\/disable controls when multiple displays are available/);
  assert.match(detail("display-panel"), /Resolution is configured separately under Setup > Monitors/);
  for (const text of [instruction("display-panel"), completion("display-panel"), steps.get("display-panel")!.note!])
    assert.doesNotMatch(text, /resolution/i);
});

test("Compose replaces normal Caps Lock behavior while retaining sequential presses", () => {
  assert.match(instruction("compose-intro"), /Caps Lock as the Compose key by default, instead of toggling capital letters/);
  assert.match(instruction("compose-intro"), /Tap and release Caps Lock, then m, then s/);
  assert.match(instruction("compose-intro"), /separate presses/);
  assert.doesNotMatch(instruction("compose-intro"), /second job/);
});
