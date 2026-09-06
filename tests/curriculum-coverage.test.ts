import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { parseCourseJson } from "../src/course.ts";

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
