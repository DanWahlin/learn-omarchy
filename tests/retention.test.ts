import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import vm from "node:vm";
import test from "node:test";
import { parseCourseJson } from "../src/course.ts";
import { renderCheatSheet, shortcutSections } from "../tools/generate-cheat-sheet.mjs";

const context = vm.createContext({});
vm.runInContext(await readFile(new URL("../app/Retention.js", import.meta.url), "utf8"), context);
const course = parseCourseJson(await readFile(new URL("../courses/omarchy-basics.json", import.meta.url), "utf8")).course!;
const plain = (value: unknown) => JSON.parse(JSON.stringify(value));
const results = Object.fromEntries(course.lessons.flatMap(lesson => lesson.steps.map(step => [step.id, "practiced"])));

test("mixed practice requires introduced safe lessons and preserves IDs, dependencies and order", () => {
  assert.deepEqual(plain(context.mixedPracticePlan(course, {}, {}, 3)), []);
  const plan: string[] = plain(context.mixedPracticePlan(course, results, {}, 3, () => 0));
  assert.equal(plan.length, 3);
  assert.equal(new Set(plan).size, plan.length);
  assert.deepEqual(plan, plain(context.mixedPracticePlan(course, results, {}, 3, () => 0)));
  for (const id of plan) {
    const index = context.lessonIndex(course, id);
    assert.equal(course.lessons[index].id, id);
    assert.equal(course.lessons[index].mixedPractice, true);
  }
  const reversed = { ...course, lessons: course.lessons.slice().reverse() };
  for (const id of plan) assert.equal(reversed.lessons[context.lessonIndex(reversed, id)].id, id);
  assert.equal(context.lessonIndex(course, "removed-lesson"), -1);
});

test("mixed practice cannot opt a lock, microphone, capture or unknown practice task in", () => {
  for (const practice of ["screen-lock", "dictation", "screen-recording", "capture", "sharing", "future"]) {
    const altered = structuredClone(course);
    altered.lessons = [{
      ...course.lessons.find(lesson => lesson.id === "windows")!,
      steps: [{ id: "unsafe", kind: "practice", practice } as any],
      mixedPractice: true,
    }];
    assert.deepEqual(plain(context.mixedPracticePlan(altered, { unsafe: "practiced" }, {}, 3)), [], practice);
  }
});

test("skipped or newly added required activities prevent review until explored; credits survive result changes", () => {
  const partial = { ...results, "windows-resize": "skipped" };
  const withoutCredit = plain(context.mixedPracticePlan(course, partial, {}, 99, () => 0));
  assert.ok(!withoutCredit.includes("windows"));
  const credited = plain(context.mixedPracticePlan(course, partial, { "windows-resize": true }, 99, () => 0));
  assert.ok(credited.includes("windows"));
  assert.equal(plain(context.mixedPracticePlan(course, results, {}, 1, () => 1)).length, 1);
});

test("optional split activities do not exclude a custom-layout learner from mixed review", () => {
  const customLayoutResults = { ...results, "windows-split": "skipped", "windows-split-restore": "skipped" };
  const plan = plain(context.mixedPracticePlan(course, customLayoutResults, {}, 99, () => 0));
  assert.ok(plan.includes("windows"));
});

test("printable reference is generated from explicit source and retains each lesson's context", async () => {
  const html = renderCheatSheet(course);
  assert.equal(await readFile(new URL("../courses/omarchy-shortcuts.html", import.meta.url), "utf8"), html);
  const entries = shortcutSections(course).flatMap(section => section.entries);
  for (const stepId of ["windows-resize", "windows-resize-back", "windows-split", "notifications-history", "advanced-window-mouse"])
    assert.ok(entries.some(entry => entry.stepIds.includes(stepId)), stepId);
  assert.match(html, /@media print/);
  assert.match(html, /window\.print\(\)/);
  assert.doesNotMatch(html, /<script|<iframe|<img|<link|@import/);
});

test("printable content escapes curriculum HTML and never treats commands as markup", () => {
  const altered = structuredClone(course);
  altered.title = '<img src=x onerror="alert(1)">';
  altered.lessons[2].references![0].action = "<script>bad()</script>";
  const html = renderCheatSheet(altered);
  assert.doesNotMatch(html, /<script|<img/);
  assert.match(html, /&lt;img/);
  assert.match(html, /&lt;script&gt;/);
});

test("printable directional exercises use a layout-relative arrow, never the authored seed", () => {
  const entries = shortcutSections(course).flatMap(section => section.entries);
  for (const id of ["windows-focus-right", "windows-swap"]) {
    const entry = entries.find(item => item.stepIds.includes(id))!;
    assert.ok(entry.keys.includes("ARROW"), id);
    assert.ok(!entry.keys.some(key => ["LEFT", "RIGHT", "UP", "DOWN"].includes(key)), id);
    assert.match(entry.action + " " + entry.caution, /direction|neighbor/i);
    assert.doesNotMatch(entry.action + " " + entry.caution, /only.*practice/i);
  }
  const altered = structuredClone(course);
  const step = altered.lessons.flatMap(lesson => lesson.steps).find(item => item.id === "windows-focus-right")!;
  step.keys = ["SUPER", "+", "DOWN"];
  assert.deepEqual(shortcutSections(altered), shortcutSections(course), "changing a seed must not change the printed shortcut");
});

test("printable footer describes the loaded course instead of claiming the bundled source path", () => {
  const custom = { ...course, id: "custom-course", title: "My custom course" };
  const html = renderCheatSheet(custom);
  assert.match(html, /Generated from the loaded course/);
  assert.match(html, /My custom course/);
  assert.doesNotMatch(html, /courses\/omarchy-basics\.json/);
});
