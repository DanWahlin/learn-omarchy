import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { parseCourseJson, validateCourse } from "../src/course.ts";

const parsed = parseCourseJson(await readFile(new URL("../courses/omarchy-basics.json", import.meta.url), "utf8"));
const course = parsed.course;

test("expanded curriculum remains valid with unique activity IDs", () => {
  assert.deepEqual(parsed.errors, []);
  assert.ok(course);
  const ids = course.lessons.flatMap(lesson => lesson.steps.map(step => step.id));
  assert.equal(new Set(ids).size, ids.length);
});

test("Compose and recording are real core exercises rather than narrated mentions", () => {
  assert.ok(course);
  for (const mode of ["compose", "screen-recording"]) {
    const lesson = course.lessons.find(item => item.steps.some(step => step.practice === mode));
    assert.ok(lesson, mode);
    assert.notEqual(lesson.optional, true);
    const step = lesson.steps.find(item => item.practice === mode)!;
    assert.equal(step.kind, "practice");
    assert.equal(step.completion.type, "practice-result");
    assert.notEqual(step.optional, true);
    assert.deepEqual(step.keys, [], "Sequential typing and recording controls aren't held course chords");
  }
});

test("specialized capture and productivity tasks remain optional", () => {
  assert.ok(course);
  for (const mode of ["ocr", "qr", "dictation", "web-app", "transcode", "sharing"]) {
    const lesson = course.lessons.find(item => item.steps.some(step => step.practice === mode));
    assert.ok(lesson, mode);
    const step = lesson.steps.find(item => item.practice === mode)!;
    assert.ok(lesson.optional || step.optional, mode);
  }
});

test("system orientation introduces maintenance without applying changes", () => {
  assert.ok(course);
  const lesson = course.lessons.find(item => item.id === "apps-and-upkeep");
  assert.ok(lesson);
  assert.deepEqual(lesson.steps.map(step => step.id), [
    "upkeep-install", "upkeep-remove", "upkeep-defaults", "upkeep-updates", "upkeep-recovery",
  ]);
  for (const step of lesson.steps) {
    assert.equal(step.kind, "tour");
    assert.equal(step.completion.type, "narration-complete");
    assert.equal(step.help, undefined);
    assert.equal(step.cleanup, undefined);
  }
});

test("curriculum commands never perform broad destructive demonstrations", () => {
  assert.ok(course);
  for (const step of course.lessons.flatMap(lesson => lesson.steps)) {
    for (const command of [step.help?.command, step.cleanup]) {
      if (!command) continue;
      const source = command.join(" ");
      assert.doesNotMatch(source, /\b(pkill|killall)\b/, step.id);
      assert.doesNotMatch(source, /omarchy(?: |-)(?:reinstall|remove-preinstalls|system-factory-reset|hyprland-window-close-all)\b/, step.id);
    }
  }
});

test("Windows requires resize but permits skipping layout-dependent split exercises", () => {
  assert.ok(course);
  const windows = course.lessons.find(lesson => lesson.id === "windows")!;
  for (const [id, expected] of [
    ["windows-resize", "resized"], ["windows-resize-back", "resized"],
    ["windows-split", "splitChanged"], ["windows-split-restore", "splitChanged"],
  ]) {
    const step = windows.steps.find(item => item.id === id)!;
    assert.ok(step);
    assert.equal(step.optional === true, expected === "splitChanged", "custom layouts must not block core completion");
    assert.notEqual(windows.optional, true);
    assert.equal(step.completion.type, "hyprland-event");
    if (step.completion.type !== "hyprland-event") throw new Error("Expected window outcome");
    assert.equal(step.completion.target, "tutorial-window");
    assert.equal(step.completion.windowState![expected], true);
    assert.match(step.help!.command.join(" "), /\{tutorialWindow\}/);
    if (expected === "splitChanged") {
      assert.ok(step.pairWithStep);
      assert.match(step.help!.command.join(" "), /hl\.get_window\("\{peerWindow\}"\)/);
      assert.match(step.help!.command.join(" "), /assert\(active and active\.address == target\.address/);
    }
    assert.equal(step.audio, "audio/" + id + ".mp3");
    assert.equal(step.completionAudio, "audio/" + id + "-done.mp3");
  }
});

test("advanced windows and notifications are explicit optional introductions without host commands", () => {
  assert.ok(course);
  for (const id of ["advanced-windows", "notifications"]) {
    const lesson = course.lessons.find(item => item.id === id)!;
    assert.ok(lesson.optional);
    for (const step of lesson.steps) {
      assert.equal(step.kind, "tour");
      assert.equal(step.completion.type, "narration-complete");
      assert.deepEqual(step.keys, []);
      assert.equal(step.help, undefined);
      assert.equal(step.cleanup, undefined);
      assert.equal(step.audio, "audio/" + step.id + ".mp3");
      assert.ok(step.shortcuts?.length);
    }
  }
});

test("new verification and narration metadata fail closed on malformed course content", () => {
  assert.ok(course);
  for (const mutate of [
    (step: any) => { step.pairWithStep = "missing"; },
    (step: any) => { step.pairWithStep = step.windowFromStep; },
    (step: any) => { delete step.pairWithStep; },
    (step: any) => { step.completion.windowState.splitChanged = false; },
    (step: any) => { step.completion.windowState.resized = "yes"; },
    (step: any) => { step.audio = "../outside.mp3"; },
    (step: any) => { step.shortcuts = [{ keys: [], action: "" }]; },
  ]) {
    const altered = structuredClone(course);
    mutate(altered.lessons.flatMap(lesson => lesson.steps).find(step => step.id === "windows-split"));
    assert.ok(validateCourse(altered).length > 0);
  }
  const altered = structuredClone(course);
  const tour = altered.lessons.flatMap(lesson => lesson.steps).find(step => step.id === "notifications-history")!;
  delete tour.audio;
  assert.ok(validateCourse(altered).some(error => error.includes("audio is required")));
});
