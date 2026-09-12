import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const context = vm.createContext({});
vm.runInContext(await readFile(new URL("../app/ArcadeLogic.js", import.meta.url), "utf8"), context);
const plain = (value: unknown) => JSON.parse(JSON.stringify(value));

test("normalizes shortcut keys and creates stable signatures", () => {
  assert.deepEqual(plain(context.normalizeKeys(["a", "+", "shift", "SUPER", "a", "ctrl", "Alt"])),
    ["SUPER", "CTRL", "ALT", "SHIFT", "A"]);
  assert.deepEqual(plain(context.normalizeKeys(" alt + x + super + X ")), ["SUPER", "ALT", "X"]);
  assert.deepEqual(plain(context.normalizeKeys([null, 4, "", "+"])), []);
  assert.equal(context.keySignature(["shift", "+", "ctrl", "+", "k"]), "CTRL+SHIFT+K");
});

test("extracts safe unique challenges without mutating the course", () => {
  const course = {
    lessons: [
      { id: "welcome", kind: "welcome", title: "Welcome", steps: [
        { id: "skip-welcome", instruction: "No", keys: ["SUPER", "+", "W"] },
      ] },
      { id: "omarchy-tour", title: "Tour", steps: [
        { id: "skip-tour", kind: "tour", instruction: "No", keys: ["SUPER", "+", "T"] },
      ] },
      { id: "windows", title: "Window Management", steps: [
        { id: "open", practicePrompt: "Ask HEXON to open it", instruction: "Fallback",
          detail: "HEXON watches.", keys: ["return", "+", "SUPER", "RETURN"] },
        { id: "duplicate", practicePrompt: "Ask HEXON to open it",
          keys: ["SUPER", "+", "RETURN"] },
        { id: "same-keys-new-prompt", instruction: "Open another terminal.",
          keys: ["SUPER", "+", "RETURN"] },
        { id: "skip-practice", kind: "practice", instruction: "No", keys: ["CTRL", "+", "P"] },
        { id: "skip-empty", instruction: "No", keys: ["+"] },
        { id: "skip-no-prompt", keys: ["SUPER", "+", "Q"] },
        { id: "skip-volume", instruction: "Turn it up.", keys: ["VOLUMEUP"] },
        { id: "skip-hardware-volume", instruction: "Turn it down.", keys: ["XF86AUDIOLOWERVOLUME"] },
        { id: "skip-print", instruction: "Take a shot.", keys: ["PRINT"] },
        { id: "skip-unknown", instruction: "Unknown.", keys: ["SUPER", "+", "F12"] },
        { id: "skip-malformed", instruction: "Malformed.", keys: ["SUPER", 1] },
      ] },
      { id: "screen-capture", title: "Screenshots", steps: [
        { id: "shot", instruction: "Close capture.", detail: 12, keys: ["ESCAPE"] },
      ] },
    ],
  };
  const before = structuredClone(course);
  const challenges = plain(context.buildChallenges(course));

  assert.deepEqual(course, before);
  assert.deepEqual(challenges, [
    {
      id: "open", lessonId: "windows", lessonTitle: "Window Management",
      prompt: "Ask your guide to open it", detail: "your guide watches.",
      keys: ["SUPER", "RETURN"], signature: "SUPER+RETURN", category: "windows",
    },
    {
      id: "same-keys-new-prompt", lessonId: "windows", lessonTitle: "Window Management",
      prompt: "Open another terminal.", detail: "",
      keys: ["SUPER", "RETURN"], signature: "SUPER+RETURN", category: "windows",
    },
    {
      id: "shot", lessonId: "screen-capture", lessonTitle: "Screenshots",
      prompt: "Close capture.", detail: "", keys: ["ESCAPE"], signature: "ESCAPE", category: "capture",
    },
  ]);
  assert.deepEqual(plain(context.buildChallenges(null)), []);
  assert.deepEqual(plain(context.buildChallenges({ lessons: "bad" })), []);
});

test("derives all supported categories from lesson identity", () => {
  const lessons = [
    ["workspace-navigation", "Desktops", "workspaces"],
    ["window-layouts", "Tiles", "windows"],
    ["favorite-apps", "Launchers", "apps"],
    ["system-settings", "Preferences", "system"],
    ["screen-recording", "Video", "capture"],
    ["compose", "Characters", "general"],
  ].map(([id, title]) => ({ id, title, steps: [{ id, instruction: `Recall ${id}`, keys: ["A"] }] }));
  assert.deepEqual(plain(context.buildChallenges({ lessons })).map((item: any) => item.category),
    ["workspaces", "windows", "apps", "system", "capture", "general"]);
});

test("extracts only labels handled by arcade keyboard input", () => {
  const allowed = [
    "SUPER", "CTRL", "ALT", "SHIFT", "SPACE", "RETURN", "TAB", "ESCAPE",
    "LEFT", "RIGHT", "UP", "DOWN", "MINUS", "EQUAL", "COMMA",
    ..."ABCDEFGHIJKLMNOPQRSTUVWXYZ", ..."0123456789",
  ];
  const lessons = allowed.map(label => ({
    id: `allowed-${label}`, title: "Keys",
    steps: [{ id: label, instruction: label, keys: [label] }],
  }));
  assert.deepEqual(plain(context.buildChallenges({ lessons })).map((item: any) => item.signature), allowed);
});

test("shuffles a copy deterministically and clamps invalid random values", () => {
  const source = [1, 2, 3, 4];
  const values = [0.5, 0.25, 0];
  assert.deepEqual(plain(context.shuffled(source, () => values.shift())), [2, 4, 1, 3]);
  assert.deepEqual(source, [1, 2, 3, 4]);
  assert.deepEqual(plain(context.shuffled(source, () => Number.NaN)), [2, 3, 4, 1]);
  assert.deepEqual(plain(context.shuffled("bad", () => 0)), []);
});

test("hinted answers are forgiving while game modes reward their intended behavior", () => {
  for (const mode of ["sprint", "rescue", "keyfall"]) {
    assert.equal(context.scoreAnswer(mode, 100, 5, true), 0);
    assert.ok(Number.isInteger(context.scoreAnswer(mode, 100, 5, false)));
    assert.ok(context.scoreAnswer(mode, 100, 5, false) > 0);
  }
  assert.ok(context.scoreAnswer("sprint", 100, 3, false) > context.scoreAnswer("sprint", 5000, 3, false));
  assert.ok(context.scoreAnswer("sprint", 100, 4, false) > context.scoreAnswer("sprint", 100, 3, false));
  assert.ok(context.scoreAnswer("keyfall", 100, 3, false) > context.scoreAnswer("keyfall", 5000, 3, false));
  assert.ok(context.scoreAnswer("keyfall", 100, 4, false) > context.scoreAnswer("keyfall", 100, 3, false));
  assert.ok(context.scoreAnswer("rescue", 999999, 2, false) < context.scoreAnswer("sprint", 0, 2, false));
  assert.equal(context.scoreAnswer("rescue", 10, 2, false), context.scoreAnswer("rescue", 9999, 2, false));
  assert.ok(context.scoreAnswer("unknown", -1, -3, false) > 0);
});

test("creates defaults and sanitizes unknown persisted stats", () => {
  const expected = {
    version: 1,
    sprint: { bestScore: 0, bestStreak: 0, plays: 0, clears: 0 },
    rescue: { bestScore: 0, bestStreak: 0, plays: 0, clears: 0 },
    keyfall: { bestScore: 0, bestStreak: 0, plays: 0, clears: 0 },
  };
  assert.deepEqual(plain(context.defaultStats()), expected);
  assert.deepEqual(plain(context.mergeStats({
    version: 99,
    sprint: { bestScore: 12, bestStreak: -1, plays: 2.5, clears: "4", extra: 8 },
    rescue: null,
    keyfall: { bestScore: Number.POSITIVE_INFINITY, bestStreak: 3, plays: 4, clears: 2 },
    extraMode: { plays: 100 },
  })), {
    ...expected,
    sprint: { bestScore: 12, bestStreak: 0, plays: 0, clears: 0 },
    keyfall: { bestScore: 0, bestStreak: 3, plays: 4, clears: 2 },
  });
  assert.deepEqual(plain(context.mergeStats("bad")), expected);
});

test("records sanitized results immutably and preserves existing bests", () => {
  const stats = {
    version: 1,
    sprint: { bestScore: 200, bestStreak: 4, plays: 2, clears: 1 },
    rescue: { bestScore: 50, bestStreak: 1, plays: 1, clears: 0 },
    keyfall: { bestScore: 0, bestStreak: 0, plays: 0, clears: 0 },
  };
  const before = structuredClone(stats);
  const result = plain(context.recordResult(stats, "sprint", 150, 7, true));
  assert.deepEqual(stats, before);
  assert.notStrictEqual(context.recordResult(stats, "sprint", 1, 1, false), stats);
  assert.deepEqual(result.sprint, { bestScore: 200, bestStreak: 7, plays: 3, clears: 2 });
  assert.deepEqual(result.rescue, stats.rescue);

  const sanitized = plain(context.recordResult(stats, "rescue", -5, 2.5, "yes"));
  assert.deepEqual(sanitized.rescue, { bestScore: 50, bestStreak: 1, plays: 2, clears: 0 });
  assert.deepEqual(plain(context.recordResult(stats, "unknown", 999, 999, true)), stats);
});
