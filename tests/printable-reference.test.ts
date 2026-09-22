import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { parseCourseJson, validateCourse, type Course, type ReferenceEntry } from "../src/course.ts";
import { escapeHtml, renderCheatSheet, shortcutSections } from "../tools/generate-cheat-sheet.mjs";

const parsed = parseCourseJson(await readFile(new URL("../courses/omarchy-basics.json", import.meta.url), "utf8"));
assert.deepEqual(parsed.errors, []);
const course = parsed.course!;
const normalize = (keys: string[]) => keys.filter(key => key !== "+").map(key => key.toUpperCase()).sort().join("|");
const entriesFor = (id: string) => course.lessons.flatMap(lesson => lesson.references!).filter(entry => entry.stepIds.includes(id));
const textFor = (id: string) => entriesFor(id).map(entry => `${entry.keys.join(" ")} ${entry.action} ${entry.caution || ""}`).join("\n");

test("versioned printable covers every lesson, activity and native taught chord", () => {
  const sections = shortcutSections(course);
  assert.equal(sections.length, course.lessons.length);
  const html = renderCheatSheet(course);
  for (const lesson of course.lessons) {
    const section = sections.find(section => section.id === lesson.id)!;
    assert.ok(section.entries.length, lesson.id);
    const covered = new Set(section.entries.flatMap(entry => entry.stepIds));
    assert.deepEqual([...covered].sort(), lesson.steps.map(step => step.id).sort(), lesson.id);
    for (const entry of section.entries) {
      assert.ok(html.includes(`data-step-ids="${escapeHtml(JSON.stringify(entry.stepIds))}"`));
    }
    for (const step of lesson.steps.filter(step => step.keys.length)) {
      const direction = Boolean(step.directionFromStep || step.swapWithStep);
      const keys = step.keys.map(key => direction && ["LEFT", "RIGHT", "UP", "DOWN"].includes(key) ? "ARROW" : key);
      assert.ok(section.entries.some(entry => entry.stepIds.includes(step.id) &&
        entry.kind === "chord" && normalize(entry.keys) === normalize(keys)), step.id);
    }
  }
  const firstOptional = sections.findIndex(section => section.optional);
  assert.ok(firstOptional > 0);
  assert.ok(sections.slice(firstOptional).every(section => section.optional));
});

test("all embedded practices and formerly prose-only skills have substantive reference entries", () => {
  for (const step of course.lessons.flatMap(lesson => lesson.steps).filter(step => step.practice)) {
    assert.ok(entriesFor(step.id).length, step.id);
    assert.ok(textFor(step.id).length > 40, step.id);
  }
  for (const [id, expression] of [
    ["helpers-universal-copy", /SUPER \+ C[\s\S]*SUPER \+ V/],
    ["clipboard-practice", /SHIFT \+ (ENTER|RETURN)/i],
    ["compose-practice", /CAPS\s*LOCK/i],
    ["capture-native-workflow", /PRINT/i],
    ["recording-intro", /ALT \+ PRINT/i],
    ["ocr-practice", /SUPER \+ CTRL \+ PRINT/i],
    ["lock-practice", /SUPER \+ CTRL \+ L/],
    ["dictation-practice", /SUPER \+ CTRL \+ X[\s\S]*F9/],
    ["upkeep-install", /AUR|Arch User Repository/],
    ["upkeep-remove", /dependenc/i],
    ["upkeep-defaults", /default/i],
    ["upkeep-updates", /snapshot[\s\S]*backup/i],
    ["upkeep-recovery", /config|back\s*up/i],
    ["tools-disk-usage-open", /inspect|review/i],
    ["web-app-practice", /[Ii]nstall[\s\S]*[Rr]emove/],
    ["transcode-practice", /original/i],
    ["sharing-practice", /recipient/i],
  ] as const) assert.match(textFor(id), expression, id);
  const compose = entriesFor("compose-practice");
  assert.ok(compose.some(entry => entry.kind === "sequence" && /s\b/.test(entry.keys.join(" "))));
  assert.ok(compose.some(entry => entry.kind === "sequence" && /h\b/.test(entry.keys.join(" "))));
  assert.match(textFor("windows-resize-back"), /SHIFT[\s\S]*ALT[\s\S]*CTRL/);
});

test("print descriptions explain real targets, toggles and sensitive actions, not guided-only guarantees", () => {
  const html = renderCheatSheet(course);
  assert.doesNotMatch(html, /Only the terminal opened for this activity will close|Only our two practice terminals will change positions/);
  assert.match(textFor("close-terminal"), /focused|active/i);
  assert.match(textFor("windows-swap"), /focused|active/i);
  assert.match(textFor("windows-float"), /toggl|float[\s\S]*til/i);
  assert.match(textFor("workspaces-scratchpad"), /toggl|show[\s\S]*hide/i);
  assert.match(textFor("workspaces-send"), /follow/i);
  assert.match(textFor("clipboard-practice"), /without.*past|copy.only/i);
  assert.match(textFor("dictation-practice"), /Voxtype/);
  assert.match(textFor("sharing-practice"), /nothing|does not send|not send|no.*send/i);
  assert.match(textFor("capture-practice"), /nothing is uploaded/i);
  assert.match(textFor("advanced-window-pop"), /disposable|lesson/i);
  for (const id of ["background-menu", "theme-menu"]) {
    assert.match(textFor(id), /Escape clears search text; press again to close, or once if empty/);
    assert.doesNotMatch(textFor(id), /Escape cancels/);
  }
});

test("print content is independent of guided text and marks only genuinely optional material", () => {
  const altered = structuredClone(course);
  for (const step of altered.lessons.flatMap(lesson => lesson.steps)) {
    step.instruction = "Only course windows will change.";
    if (step.practicePrompt) step.practicePrompt = "Only course windows will change.";
    if (step.note) step.note = "Only course windows will change.";
    if (step.detail) step.detail = "Only course windows will change.";
  }
  assert.equal(renderCheatSheet(altered), renderCheatSheet(course));
  const entries = shortcutSections(course).flatMap(section => section.entries);
  for (const id of ["windows-split", "lock-practice", "ocr-practice"]) {
    assert.ok(entries.filter(entry => entry.stepIds.includes(id)).every(entry => entry.optional), id);
  }
  assert.ok(entries.filter(entry => entry.stepIds.includes("recording-practice")).every(entry => !entry.optional));
  assert.doesNotMatch(renderCheatSheet(course), /Optional references are introductions, not verified exercises/);
});

test("reference sources are explicit, version pinned and printed with no remote resources", async () => {
  assert.equal(course.reference!.platform, "Omarchy");
  assert.equal(course.reference!.version, "4.0.3");
  for (const source of course.reference!.sources) {
    if (source.url === undefined) {
      assert.ok(source.path);
      assert.ok((await readFile(new URL("../" + source.path, import.meta.url), "utf8")).length > 0);
      assert.ok(renderCheatSheet(course).includes("Bundled source: " + escapeHtml(source.path)));
      continue;
    }
    const url = new URL(source.url);
    assert.equal(url.hostname, "github.com");
    assert.ok(url.pathname.startsWith("/basecamp/omarchy/"));
    assert.ok(url.pathname.includes("/v4.0.3/"), source.url);
    assert.ok(renderCheatSheet(course).includes(escapeHtml(source.url)));
  }
  const html = renderCheatSheet(course);
  assert.match(html, /Omarchy 4\.0\.3 defaults/);
  assert.match(html, /Sources and version scope/);
  assert.doesNotMatch(html, /<script|<img|<iframe|<link|@import|url\(/i);
  assert.doesNotMatch(html, /—/);
});

test("missing coverage, source drift and malformed reference metadata fail closed", () => {
  const mutations: ((copy: Course) => void)[] = [
    copy => { delete copy.lessons[1].references; },
    copy => { copy.lessons[0].references = []; },
    copy => { copy.lessons[1].references!.forEach(entry => { entry.stepIds = entry.stepIds.filter(id => id !== "tour-welcome"); }); },
    copy => { copy.lessons[1].references![0].stepIds.push("not-a-step"); },
    copy => { copy.lessons[1].references![0].stepIds.push("launch-terminal"); },
    copy => { copy.lessons[1].references![0].sourceIds = ["unknown-source"]; },
    copy => { copy.lessons[1].references![0].sourceIds = []; },
    copy => { copy.lessons[1].references![0].keys = []; },
    copy => { copy.lessons[1].references![0].action = ""; },
    copy => { copy.lessons[1].references![0].kind = "invalid" as ReferenceEntry["kind"]; },
    copy => { copy.reference!.sources[0].url = "javascript:alert(1)"; },
    copy => { copy.reference!.sources[0].url = "https://user:password@example.org"; },
    copy => { copy.reference!.sources[0] = { id: "hotkeys", title: "Unsafe source", path: "../outside" }; },
    copy => { copy.reference!.sources[0] = { id: "hotkeys", title: "Unsafe source", path: "/absolute/path" }; },
    copy => { copy.reference!.sources.push(copy.reference!.sources[0]); },
    copy => { copy.reference!.verifiedOn = "2026-02-30"; },
    copy => { delete copy.reference; },
    copy => { copy.lessons[1].steps[0].shortcuts = [{ keys: ["SUPER"], action: "Duplicate source" }]; },
  ];
  for (const mutate of mutations) {
    const copy = structuredClone(course);
    mutate(copy);
    assert.ok(validateCourse(copy).length, String(mutate));
    assert.throws(() => renderCheatSheet(copy), undefined, String(mutate));
  }
  const added = structuredClone(course);
  added.lessons[1].steps.push({ ...added.lessons[1].steps[0], id: "new-unreviewed-activity" });
  assert.ok(validateCourse(added).some(error => error.includes('missing activity "new-unreviewed-activity"')));
});

test("legacy custom courses remain supported but cannot inherit guided-only safety promises", () => {
  const legacy = structuredClone(course);
  delete legacy.reference;
  for (const lesson of legacy.lessons) delete lesson.references;
  assert.deepEqual(validateCourse(legacy), []);
  const html = renderCheatSheet(legacy);
  assert.match(html, /Unreviewed course reference/);
  assert.match(html, /may be incomplete/);
  assert.doesNotMatch(html, /Only the terminal opened for this activity will close|Only our two practice terminals/);
});
