import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const NOW = 1_800_000_000_000;
const DAY = 86_400_000;
class Clock extends Date {
  static now() { return NOW; }
}
const context = vm.createContext({ Date: Clock });
vm.runInContext(await readFile(new URL("../app/ArcadeLogic.js", import.meta.url), "utf8"), context);
const plain = (value: any): any => JSON.parse(JSON.stringify(value));
const course = JSON.parse(await readFile(new URL("../courses/omarchy-basics.json", import.meta.url), "utf8"));
const challenges = plain(context.buildChallenges(course));
const challengeFor = (action: string) => challenges.find((challenge: any) => challenge.action === action);
const terminal = challengeFor("launch-terminal");
const emptyRecord = { bestScore: 0, bestClean: 0, bestElapsedMs: 0, splits: [], plays: 0 };
const attempt = (overrides: object = {}) => ({
  hinted: false, wrongAttempts: 0, elapsedMs: 1200, sessionId: "session-1", ...overrides,
});
const run = (overrides: object = {}) => ({
  mode: "rescue", score: 510, streak: 6, clean: 6, total: 6, elapsedMs: 6000,
  deckKey: context.deckKey("rescue", context.rescueDeck(challenges), "standard"),
  splits: [1000, 2000, 3000, 4000, 5000, 6000], competitive: true, ...overrides,
});
const recordAttempt = (stats: any, challenge = terminal, overrides: object = {}, now = NOW) =>
  plain(context.recordAttempt(stats, challenge, attempt(overrides), now));

test("normalizes shortcut keys without mutating inputs", () => {
  assert.deepEqual(plain(context.normalizeKeys(["a", "+", "shift", "SUPER", "a", "ctrl", "Alt"])),
    ["SUPER", "CTRL", "ALT", "SHIFT", "A"]);
  assert.deepEqual(plain(context.normalizeKeys(" alt + x + super + X ")), ["SUPER", "ALT", "X"]);
  assert.deepEqual(plain(context.normalizeKeys([null, 4, "", "+"])), []);
  assert.equal(context.keySignature(["shift", "+", "ctrl", "+", "k"]), "CTRL+SHIFT+K");
  assert.equal(context.keySignature(null), "");
});

test("bundled course yields 40 canonical, standalone, course-derived challenges", () => {
  const before = structuredClone(course);
  const built = plain(context.buildChallenges(course));
  assert.deepEqual(course, before);
  assert.equal(built.length, 40);
  assert.equal(new Set(built.map((challenge: any) => challenge.signature)).size, 40);
  assert.equal(built.filter((challenge: any) => challenge.signature === "SUPER+W").length, 1);
  for (const challenge of built) {
    const lesson = course.lessons.find((item: any) => item.id === challenge.lessonId);
    const step = lesson.steps.find((item: any) => item.id === challenge.id);
    assert.deepEqual(challenge.keys, plain(context.normalizeKeys(step.keys)));
    assert.equal(challenge.signature, context.keySignature(step.keys));
    assert.equal(challenge.lessonTitle, lesson.title);
    assert.ok(challenge.prompt.length > 0 && challenge.prompt.length < 70, challenge.prompt);
    assert.doesNotMatch(challenge.prompt, /other direction|neighbor|HEXON|just opened|practice terminal/i);
    assert.ok(["starter", "intermediate", "advanced"].includes(challenge.difficulty));
    assert.ok(["apps", "windows", "workspaces", "system", "capture"].includes(challenge.category));
    assert.notEqual(challenge.action, "custom");
    assert.equal(typeof challenge.detail, "string");
  }
  assert.equal(challengeFor("focus-right").prompt, "Focus the window on the right");
  assert.equal(challengeFor("narrow").prompt, "Make the floating window narrower");
  assert.equal(challengeFor("close-window").category, "windows");
  assert.equal(challengeFor("share-menu").category, "capture");
  assert.equal(challengeFor("launch-terminal").category, "apps");
  assert.equal(challengeFor("activity-monitor").category, "system");
});

test("canonical coverage matches every playable course combination across all five categories", () => {
  const eligible = course.lessons.filter((lesson: any) => lesson.kind !== "welcome")
    .flatMap((lesson: any) => lesson.steps)
    .filter((step: any) => !["welcome", "tour", "practice"].includes(step.kind)
      && context.arcadePlayableKeys(step.keys));
  const sourceSignatures = [...new Set(eligible.map((step: any) => context.keySignature(step.keys)))].sort();
  assert.deepEqual(challenges.map((challenge: any) => challenge.signature).sort(), sourceSignatures);
  const counts = challenges.reduce((result: Record<string, number>, challenge: any) => {
    result[challenge.category] = (result[challenge.category] || 0) + 1;
    return result;
  }, {});
  assert.deepEqual(counts, { workspaces: 8, system: 13, apps: 8, windows: 9, capture: 2 });
  assert.equal(new Set(challenges.map((challenge: any) => challenge.action)).size, 40);
});

test("unknown custom course semantics stay unknown and duplicate signatures collapse", () => {
  const custom = {
    lessons: [
      { id: "welcome", kind: "welcome", steps: [{ id: "skip", keys: ["SUPER", "A"], instruction: "Skip" }] },
      { id: "windows", title: "Window Management", steps: [
        { id: "custom-open", practicePrompt: "Ask HEXON to open the notes", detail: "HEXON watches.",
          keys: ["SUPER", "+", "RETURN"] },
        { id: "duplicate", instruction: "Open another set of notes", keys: ["RETURN", "SUPER"] },
        { id: "custom", instruction: "Focus the document editor", keys: ["CTRL", "A"] },
        { id: "skip-practice", kind: "practice", instruction: "Skip", keys: ["CTRL", "P"] },
        { id: "skip-tour", kind: "tour", instruction: "Skip", keys: ["SUPER", "T"] },
        { id: "skip-empty", instruction: "Skip", keys: ["+"] },
        { id: "skip-no-prompt", keys: ["SUPER", "Q"] },
      ] },
    ],
  };
  const before = structuredClone(custom);
  const built = plain(context.buildChallenges(custom));
  assert.deepEqual(custom, before);
  assert.equal(built.length, 2);
  assert.deepEqual(built[0], {
    id: "custom-open", lessonId: "windows", lessonTitle: "Window Management",
    prompt: "Ask your guide to open the notes", detail: "your guide watches.",
    keys: ["SUPER", "RETURN"], signature: "SUPER+RETURN",
    category: "general", action: "custom", difficulty: "intermediate",
  });
  assert.equal(built[1].prompt, "Focus the document editor");
  assert.equal(built[1].category, "general", "lesson names must not silently infer action semantics");
  assert.deepEqual(plain(context.rescueDeck(built)), []);
  assert.deepEqual(plain(context.buildChallenges(null)), []);
  assert.deepEqual(plain(context.buildChallenges({ lessons: "bad" })), []);
});

test("recognized metadata wins over unknown duplicates and keys still come from course steps", () => {
  const custom = { lessons: [
    { id: "custom", steps: [{ id: "first", instruction: "Do something custom", keys: ["SUPER", "RETURN"] }] },
    { id: "everyday-apps", steps: [{ id: "launch-terminal", keys: ["SUPER", "RETURN"] }] },
  ] };
  assert.equal(context.buildChallenges(custom).length, 1);
  assert.equal(context.buildChallenges(custom)[0].action, "launch-terminal");
  custom.lessons[1].steps[0].keys = ["SUPER", "CTRL", "X"];
  assert.equal(context.buildChallenges(custom)[1].signature, "SUPER+CTRL+X");
  assert.equal(context.buildChallenges(custom)[1].action, "launch-terminal");
});

test("rejects reserved controls, modifiers, unsupported keys and unusable multi-key chords", () => {
  const excluded = [
    ...["SUPER", "CTRL", "ALT", "SHIFT", "ESCAPE", "H", "P",
      "PRINT", "VOLUMEUP", "XF86AUDIOLOWERVOLUME", "F12"].map(key => [key]),
    ["SUPER", "SHIFT"], ["SUPER", 1], ["SUPER", "F12"], ["SUPER", "A", "B"],
  ];
  const supported = [["SUPER", "ESCAPE"], ["SUPER", "SPACE"], ["ALT", "TAB"],
    ["CTRL", "H"], ["CTRL", "P"], ["CTRL", "R"], ["A"], ["SUPER", "MINUS"],
    ["RETURN"], ["SPACE"], ["TAB"], ["R"], ["LEFT"], ["RIGHT"], ["1"], ["2"], ["3"]];
  const build = (keys: any[]) => plain(context.buildChallenges({ lessons: [{
    id: "custom", steps: keys.map((keys, i) => ({ id: String(i), instruction: "Custom action", keys })),
  }] }));
  assert.deepEqual(build(excluded), []);
  assert.equal(build(supported).length, supported.length);
});

test("Rescue offers six complete missions built from canonical course shortcuts", () => {
  const missions = plain(context.rescueMissions(challenges));
  assert.deepEqual(missions.map((mission: any) => mission.id), [
    "terminal-workspace",
    "layout-triage",
    "workspace-sort",
    "scratchpad-recovery",
    "file-window-shaping",
    "browser-workspace-recovery",
  ]);
  for (const mission of missions) {
    assert.equal(mission.steps.length, 6);
    assert.ok(mission.title.length > 0 && mission.brief.length > 0 && mission.success.length > 0);
    assert.ok(mission.callsign.length > 0 && mission.destination.length > 0 && mission.arrival.length > 0);
    for (const step of mission.steps) {
      assert.ok(step.prompt.length > 0 && step.label.length > 0);
      assert.deepEqual(step.challenge, challenges.find((item: any) => item.id === step.challenge.id));
      assert.equal(step.challenge.action, step.action);
    }
  }

  const terminalMission = plain(context.rescueDeck(challenges, "terminal-workspace"));
  assert.deepEqual(terminalMission.map((challenge: any) => challenge.action),
    ["launch-terminal", "float", "widen", "fullscreen", "send-workspace-2", "workspace-2"]);
  assert.deepEqual(terminalMission.map((challenge: any) => challenge.signature),
    ["SUPER+RETURN", "SUPER+T", "SUPER+EQUAL", "SUPER+F", "SUPER+SHIFT+2", "SUPER+2"]);
  assert.match(terminalMission[4].prompt, /follow it/);

  const first = plain(context.chooseRescueMission(challenges, () => 0, ""));
  const next = plain(context.chooseRescueMission(challenges, () => 0, first.id));
  assert.equal(first.id, "terminal-workspace");
  assert.equal(next.id, "layout-triage");
  assert.notEqual(next.id, first.id);
  assert.equal(context.rescueMissions(challenges.filter((item: any) => item.action !== "float")).length, 4);
  assert.deepEqual(plain(context.rescueDeck(challenges, "missing")), []);
  assert.equal(context.chooseRescueMission([], () => 0, ""), null);
  assert.deepEqual(plain(context.rescueMissions(null)), []);
  assert.deepEqual(plain(context.rescueDeck(null)), []);
});

test("every rescue mission has executable window and workspace preconditions", () => {
  const missions = plain(context.rescueMissions(challenges));
  assert.equal(missions.reduce((total: number, mission: any) => total + mission.steps.length, 0), 36);
  assert.equal(new Set(missions.flatMap((mission: any) =>
    mission.steps.map((step: any) => step.challenge.signature))).size, 19);
  for (const mission of missions) {
    let workspace = 1;
    let previous = 1;
    let scratchpadVisible = false;
    let windows: any[] = [];
    let focused: any = null;
    let stacked = false;
    const regularFocus = () => windows.filter(window => window.workspace === workspace).at(-1) || null;
    const visit = (target: number) => {
      if (workspace !== target) [previous, workspace] = [workspace, target];
      scratchpadVisible = false;
      focused = regularFocus();
    };
    for (const step of mission.steps) {
      const location = `${mission.id}: ${step.action}`;
      if (step.action.startsWith("launch-")) {
        focused = { app: step.action.slice(7), workspace, floating: false, fullscreen: false };
        windows.push(focused);
      } else if (step.action === "cycle-focus") {
        const peers = windows.filter(window => window.workspace === focused?.workspace && window !== focused);
        assert.ok(peers.length > 0, `${location} needs another window in the same workspace, not below the scratchpad`);
        focused = peers[0];
      } else if (step.action === "stash-window") {
        assert.ok(focused, location);
        focused.workspace = "scratchpad";
        scratchpadVisible = false;
        focused = regularFocus();
      } else if (step.action === "toggle-scratchpad") {
        const stashed = windows.filter(window => window.workspace === "scratchpad");
        assert.ok(stashed.length > 0, location);
        scratchpadVisible = !scratchpadVisible;
        focused = scratchpadVisible ? stashed.at(-1) : regularFocus();
      } else if (step.action === "workspace-1" || step.action === "workspace-2") {
        visit(Number(step.action.slice(-1)));
      } else if (step.action === "next-workspace") {
        visit(workspace + 1);
      } else if (step.action === "previous-workspace") {
        assert.ok(workspace > 1, location);
        visit(workspace - 1);
      } else if (step.action === "last-workspace") {
        assert.notEqual(previous, workspace, location);
        visit(previous);
      } else {
        assert.ok(focused, `${location} needs a focused window`);
        assert.ok(focused.workspace === workspace ||
          (scratchpadVisible && focused.workspace === "scratchpad"), location);
        if (step.action === "send-workspace-2") {
          focused.workspace = 2;
          visit(2);
        } else if (step.action === "float") {
          assert.equal(focused.fullscreen, false, location);
          focused.floating = !focused.floating;
        } else if (step.action === "widen" || step.action === "narrow") {
          assert.equal(focused.floating, true, location);
          assert.equal(focused.fullscreen, false, location);
        } else if (step.action === "fullscreen") {
          focused.fullscreen = !focused.fullscreen;
        } else if (step.action === "swap-right" || step.action === "toggle-split") {
          const tiled = windows.filter(window => window.workspace === workspace && !window.floating);
          assert.ok(tiled.length >= 2 && tiled.includes(focused), location);
          if (step.action === "swap-right") {
            assert.equal(stacked, false, location);
            const index = tiled.indexOf(focused);
            assert.ok(index < tiled.length - 1, `${location} needs a right-hand neighbor`);
            const a = windows.indexOf(focused);
            const b = windows.indexOf(tiled[index + 1]);
            [windows[a], windows[b]] = [windows[b], windows[a]];
          } else stacked = !stacked;
        } else if (step.action === "close-window") {
          windows = windows.filter(window => window !== focused);
          focused = regularFocus();
        } else assert.fail(`Missing mission precondition check: ${location}`);
      }
      if (step.settledWorkspace !== undefined) {
        assert.match(step.settledLabel, /Mission setup: returned to workspace/);
        visit(step.settledWorkspace);
      }
    }
    if (mission.id === "scratchpad-recovery") {
      assert.deepEqual(windows.map(window => [window.app, window.workspace]), [["terminal", "scratchpad"]]);
      assert.equal(scratchpadVisible, false);
    }
  }
});

test("random rescue selection reaches every mission and never immediately repeats when alternatives exist", () => {
  const missions = plain(context.rescueMissions(challenges));
  const random = context.seededRandom("rescue-rotation");
  const seen = new Set<string>();
  let previous = "";
  for (let i = 0; i < 300; i++) {
    const mission = context.chooseRescueMission(challenges, random, previous);
    assert.notEqual(mission.id, previous);
    seen.add(mission.id);
    previous = mission.id;
  }
  assert.deepEqual([...seen].sort(), missions.map((mission: any) => mission.id).sort());
  for (const [index, mission] of missions.entries()) {
    assert.equal(context.chooseRescueMission(challenges, () => (index + 0.5) / missions.length).id, mission.id);
    const savedDeck = plain(context.rescueDeck(challenges, mission.id));
    const savedKey = context.deckKey("rescue", savedDeck, "standard");
    context.chooseRescueMission(challenges, random, mission.id);
    assert.deepEqual(plain(context.rescueDeck(challenges, mission.id)), savedDeck);
    assert.equal(context.deckKey("rescue", savedDeck, "standard"), savedKey);
  }
  const singleMissionPool = challenges.filter((challenge: any) =>
    ["launch-browser", "send-workspace-2", "workspace-1", "launch-terminal", "workspace-2", "last-workspace"]
      .includes(challenge.action));
  assert.equal(context.rescueMissions(singleMissionPool).length, 1);
  assert.equal(context.chooseRescueMission(singleMissionPool, () => 0.999, "workspace-sort").id, "workspace-sort");
});

test("seeded random and shuffles are reproducible and do not mutate their source", () => {
  const source = [1, 2, 3, 4];
  const values = [0.5, 0.25, 0];
  assert.deepEqual(plain(context.shuffled(source, () => values.shift())), [2, 4, 1, 3]);
  assert.deepEqual(source, [1, 2, 3, 4]);
  assert.deepEqual(plain(context.shuffled(source, () => Number.NaN)), [2, 3, 4, 1]);
  assert.deepEqual(plain(context.shuffled("bad")), []);
  for (const seed of ["daily-2026-09-12", 42, "", null]) {
    const a = context.seededRandom(seed);
    const b = context.seededRandom(seed);
    const outputs = Array.from({ length: 100 }, () => a());
    assert.deepEqual(outputs, Array.from({ length: 100 }, () => b()));
    assert.ok(outputs.every(value => value >= 0 && value < 1));
  }
  assert.notEqual(context.seededRandom("a")(), context.seededRandom("b")());
  assert.deepEqual(plain(context.shuffled(challenges, context.seededRandom("sprint"))),
    plain(context.shuffled(challenges, context.seededRandom("sprint"))));
});

test("scoring rewards clean recall and retries never receive streak or speed bonuses", () => {
  for (const mode of ["sprint", "rescue", "keyfall"]) {
    assert.equal(context.scoreAnswer(mode, 100, 5, true), 0);
    assert.equal(context.scoreAnswer(mode, 100, 5, true, 3), 0);
    const first = context.scoreAnswer(mode, 100, 5, false);
    const retry = context.scoreAnswer(mode, 100, 5, false, 1);
    assert.ok(Number.isInteger(first) && first > 0);
    assert.ok(retry > 0 && retry < first);
    assert.equal(retry, context.scoreAnswer(mode, 5000, 99, false, 9));
    assert.ok(context.scoreAnswer(mode, 100, 4, false) > context.scoreAnswer(mode, 100, 3, false));
  }
  assert.ok(context.scoreAnswer("sprint", 100, 3, false) > context.scoreAnswer("sprint", 5000, 3, false));
  assert.ok(context.scoreAnswer("keyfall", 100, 3, false) > context.scoreAnswer("keyfall", 5000, 3, false));
  assert.equal(context.scoreAnswer("rescue", 10, 2, false), context.scoreAnswer("rescue", 9999, 2, false));
  for (const bad of [null, "fast", Number.NaN, Infinity, -1]) {
    assert.ok(Number.isFinite(context.scoreAnswer("sprint", bad, bad, false, bad)));
  }
});

test("achievement labels are independent of mode scoring scales and require real clean counts", () => {
  for (const mode of ["sprint", "rescue", "keyfall"]) {
    assert.equal(context.resultLabel(mode, 6, 6), "Perfect recall");
    assert.equal(context.resultLabel(mode, 2, 6), "Independent recall");
    assert.equal(context.resultLabel(mode, 0, 6), "Practice complete");
    assert.equal(context.resultLabel(mode, 0, 0), "Practice complete");
    assert.equal(context.resultLabel(mode, Infinity, 6), "Practice complete");
    assert.equal(context.resultLabel(mode, 7, 6), "Practice complete");
  }
});

test("v1 migration preserves legacy totals without turning them into comparable records", () => {
  const old = {
    version: 1,
    sprint: { bestScore: 12345, bestStreak: 12, plays: 20, clears: 4 },
    rescue: { bestScore: 510, bestStreak: 6, plays: 7, clears: 1 },
    keyfall: { bestScore: 999, bestStreak: 3, plays: 5, clears: 0 },
    records: { [run().deckKey]: { bestScore: 999999, plays: 1 } },
    skills: { [terminal.signature]: { attempts: 10, firstTry: 10 } },
  };
  const before = structuredClone(old);
  const migrated = plain(context.mergeStats(old));
  assert.deepEqual(old, before);
  assert.equal(migrated.version, 2);
  for (const mode of ["sprint", "rescue", "keyfall"]) assert.deepEqual(migrated[mode], old[mode as keyof typeof old]);
  assert.deepEqual(migrated.skills, {});
  assert.deepEqual(migrated.records, {});
  assert.deepEqual(plain(context.bestForDeck(migrated, run().deckKey)), emptyRecord);
  assert.deepEqual(plain(context.mergeStats(migrated)), migrated);
  assert.deepEqual(plain(context.mergeStats("bad")), plain(context.defaultStats()));
  const future = plain(context.mergeStats({ ...old, version: 99 }));
  assert.deepEqual(future.records, {});
  assert.deepEqual(future.skills, {});
});

test("legacy recordResult remains immutable and cannot create v2 records", () => {
  const stats = context.mergeStats({ version: 1, sprint: { bestScore: 200, bestStreak: 4, plays: 2, clears: 1 } });
  const before = plain(stats);
  const result = plain(context.recordResult(stats, "sprint", 150, 7, true));
  assert.deepEqual(plain(stats), before);
  assert.deepEqual(result.sprint, { bestScore: 200, bestStreak: 7, plays: 3, clears: 2 });
  assert.deepEqual(result.records, {});
  assert.deepEqual(plain(context.recordResult(stats, "unknown", 999, 999, true)), before);
});

test("deck keys include scoring version, mode, ordered signatures, IDs and pace", () => {
  const deck = plain(context.rescueDeck(challenges));
  const key = context.deckKey("rescue", deck, "standard");
  assert.match(key, /^arcade-v2\|rescue\|/);
  assert.equal(key, context.deckKey("rescue", structuredClone(deck), "standard"));
  assert.notEqual(key, context.deckKey("rescue", deck.slice().reverse(), "standard"));
  assert.notEqual(key, context.deckKey("rescue", deck.slice(0, -1), "standard"));
  assert.notEqual(key, context.deckKey("rescue", deck, "relaxed"));
  assert.notEqual(key, context.deckKey("sprint", deck, "standard"));
  assert.notEqual(key, context.deckKey("rescue", [{ ...deck[0], id: "changed" }, ...deck.slice(1)], "standard"));
  assert.notEqual(key, context.deckKey("rescue", [{ ...deck[0], keys: ["SUPER", "X"], signature: "SUPER+X" }, ...deck.slice(1)], "standard"));
  assert.equal(context.deckKey("unknown", deck, "standard"), "");
  assert.equal(context.deckKey("rescue", [], "standard"), "");
  assert.equal(context.deckKey("rescue", [{ ...deck[0], signature: "bad" }], "standard"), "");
  const sprint = context.shuffled(challenges, context.seededRandom("fixed"));
  const sprintKey = context.deckKey("sprint", sprint, "standard");
  assert.equal(JSON.parse(sprintKey.split("|").slice(2).join("|"))[1].length, 40);
});

test("comparable records retain score-run ghost splits while preserving legacy bests", () => {
  const legacy = context.mergeStats({ version: 1, rescue: { bestScore: 777, bestStreak: 7, plays: 10, clears: 2 } });
  const before = plain(legacy);
  let stats = plain(context.recordRun(legacy, run(), NOW));
  assert.deepEqual(plain(legacy), before);
  assert.deepEqual(stats.rescue, { bestScore: 777, bestStreak: 7, plays: 11, clears: 3 });
  assert.deepEqual(plain(context.bestForDeck(stats, run().deckKey)), {
    bestScore: 510, bestClean: 6, bestElapsedMs: 6000, splits: run().splits, plays: 1,
  });
  stats = plain(context.recordRun(stats, run({ score: 400, elapsedMs: 5000, splits: [500, 1000, 2000, 3000, 4000, 5000] }), NOW));
  assert.equal(context.bestForDeck(stats, run().deckKey).bestElapsedMs, 6000);
  const faster = [500, 1000, 2000, 3000, 4000, 5000];
  stats = plain(context.recordRun(stats, run({ elapsedMs: 5000, splits: faster }), NOW));
  const best = plain(context.bestForDeck(stats, run().deckKey));
  assert.deepEqual(best, { bestScore: 510, bestClean: 6, bestElapsedMs: 5000, splits: faster, plays: 3 });
  best.splits[0] = 9999;
  assert.equal(context.bestForDeck(stats, run().deckKey).splits[0], 500);
  assert.deepEqual(plain(context.mergeStats(JSON.parse(JSON.stringify(stats)))), stats);
  assert.deepEqual(plain(context.bestForDeck(stats, context.deckKey("rescue", context.rescueDeck(challenges), "relaxed"))), emptyRecord);
});

test("noncompetitive and malformed runs cannot establish comparable personal bests", () => {
  const stats = plain(context.recordRun(null, run({ competitive: false }), NOW));
  assert.equal(stats.rescue.plays, 1);
  assert.equal(stats.rescue.bestScore, 0);
  assert.deepEqual(stats.records, {});
  for (const override of [
    { competitive: "true" }, { deckKey: "arcade-v1|rescue|old" }, { deckKey: "arcade-v2|rescue|invalid" },
    { deckKey: context.deckKey("sprint", challenges, "standard") },
    { score: Infinity }, { score: "510" }, { clean: 7 }, { clean: -1 }, { total: 0 },
    { total: Number.NaN }, { streak: 7 }, { elapsedMs: -1 }, { elapsedMs: Infinity },
  ]) {
    const result = plain(context.recordRun(null, run(override), NOW));
    assert.deepEqual(result.records, {}, JSON.stringify(override));
  }
  assert.deepEqual(plain(context.recordRun(null, run({ mode: "unknown" }), NOW)), plain(context.defaultStats()));
  assert.deepEqual(plain(context.recordRun(null, run(), Number.NaN)), plain(context.defaultStats()));
  assert.equal(context.recordRun(null, run({ clean: 7 }), NOW).rescue.clears, 0);
});

test("partial or extended Rescue and Keyfall runs cannot compete against a different deck length", () => {
  for (const mode of ["rescue", "keyfall"]) {
    const deckKey = context.deckKey(mode, context.rescueDeck(challenges), "standard");
    for (const total of [1, 5, 7]) {
      const stats = context.recordRun(null, run({
        mode, deckKey, total, clean: total, streak: total,
        splits: Array.from({ length: total }, () => 6000),
      }), NOW);
      assert.deepEqual(plain(stats.records), {}, `${mode} length ${total} must not count against a six-card deck`);
      assert.equal(stats[mode].clears, 0);
      assert.equal(stats[mode].plays, 1);
    }
  }
});

test("timed Sprint records answers below and above its deck length with comparable replay splits", () => {
  const deck = challenges.slice(0, 9);
  const deckKey = context.deckKey("sprint", deck, "60s");
  for (const total of [2, 12]) {
    const splits = Array.from({ length: total }, (_, index) => Math.floor((index + 1) * 60000 / total));
    const result = run({
      mode: "sprint", deckKey, total, clean: total, streak: total, elapsedMs: 60000, splits,
    });
    const stats = context.recordRun(null, result, NOW);
    assert.deepEqual(plain(context.bestForDeck(stats, deckKey)), {
      bestScore: 510, bestClean: total, bestElapsedMs: 60000, splits, plays: 1,
    });
    assert.equal(stats.sprint.clears, 1);
    assert.equal(stats.sprint.plays, 1);
    const replay = context.recordRun(stats, result, NOW + DAY);
    assert.equal(context.bestForDeck(replay, deckKey).plays, 2);
    assert.deepEqual(plain(context.bestForDeck(context.mergeStats(plain(replay)), deckKey).splits), splits);
    assert.equal(context.bestForDeck(replay, context.deckKey("sprint", deck, "90s")).plays, 0);
  }
});

test("malformed ghost splits are discarded rather than used as impossible pace targets", () => {
  for (const splits of [[2000, 1000], [1, 2, 3, 4, 5, 7000], [1, 2, 3, 4, 5, Infinity], "bad", [-1]]) {
    const stats = context.recordRun(null, run({ splits }), NOW);
    assert.deepEqual(plain(context.bestForDeck(stats, run().deckKey).splits), []);
    assert.equal(context.bestForDeck(stats, run().deckKey).bestScore, 510);
  }
});

test("attempts separate hinted copying, retries and clean independent recall", () => {
  const original = context.defaultStats();
  let stats = recordAttempt(original);
  assert.deepEqual(plain(original), plain(context.defaultStats()));
  const before = structuredClone(stats);
  stats = recordAttempt(stats, terminal, { hinted: true, elapsedMs: 10 }, NOW + 100);
  assert.deepEqual(before.skills[terminal.signature], {
    attempts: 1, assisted: 0, unassisted: 1, firstTry: 1, lastSeenAt: NOW,
    bestRecallMs: 1200, meanRecallMs: 1200,
    successfulSessions: [{ sessionId: "session-1", at: NOW }],
    history: [{ at: NOW, sessionId: "session-1", hinted: false, wrongAttempts: 0, elapsedMs: 1200, clean: true }],
  });
  stats = recordAttempt(stats, terminal, { wrongAttempts: 2, elapsedMs: 20 }, NOW + 200);
  stats = recordAttempt(stats, terminal, { elapsedMs: 2400, sessionId: "session-2" }, NOW + 300);
  const skill = stats.skills[terminal.signature];
  assert.equal(skill.attempts, 4);
  assert.equal(skill.assisted, 1);
  assert.equal(skill.unassisted, 3);
  assert.equal(skill.firstTry, 2);
  assert.equal(skill.bestRecallMs, 1200);
  assert.equal(skill.meanRecallMs, 1800);
  assert.equal(skill.successfulSessions.length, 2);
  assert.deepEqual(skill.history.map((entry: any) => entry.clean), [true, false, false, true]);
  assert.equal(skill.lastSeenAt, NOW + 300);
});

test("skill identity survives challenge ID changes and duplicate course variants", () => {
  let stats = recordAttempt(null);
  stats = recordAttempt(stats, { ...terminal, id: "different-lesson-terminal" });
  assert.deepEqual(Object.keys(stats.skills), [terminal.signature]);
  assert.equal(stats.skills[terminal.signature].attempts, 2);
});

test("invalid attempt input is rejected conservatively and large valid recall times are bounded", () => {
  for (const override of [
    { hinted: "false" }, { wrongAttempts: -1 }, { wrongAttempts: 0.5 }, { wrongAttempts: Number.NaN },
    { elapsedMs: Infinity }, { elapsedMs: -1 }, { elapsedMs: "100" },
    { sessionId: "" }, { sessionId: null }, { sessionId: "x".repeat(129) },
  ]) {
    assert.deepEqual(recordAttempt(null, terminal, override), plain(context.defaultStats()), JSON.stringify(override));
  }
  assert.deepEqual(recordAttempt(null, { ...terminal, signature: "invalid" }), plain(context.defaultStats()));
  assert.deepEqual(recordAttempt(null, terminal, {}, -1), plain(context.defaultStats()));
  assert.equal(recordAttempt(null, terminal, { elapsedMs: DAY }).skills[terminal.signature].bestRecallMs, 600000);
});

test("same-session repetitions and unspaced new sessions do not establish mastery", () => {
  let stats = recordAttempt(null, terminal, {}, NOW - 3 * DAY);
  stats = recordAttempt(stats, terminal, {}, NOW - DAY);
  let summary = plain(context.masterySummary(stats, challenges));
  assert.equal(summary.practiced, 1);
  assert.equal(summary.independent, 1);
  assert.equal(summary.mastered, 0);
  assert.equal(stats.skills[terminal.signature].successfulSessions.length, 1);
  let closeTogether = recordAttempt(null, terminal, {}, NOW - DAY);
  closeTogether = recordAttempt(closeTogether, terminal, { sessionId: "second" }, NOW - DAY + 1000);
  assert.equal(context.masterySummary(closeTogether, challenges).mastered, 0);
  stats = recordAttempt(stats, terminal, { sessionId: "separate-day" }, NOW);
  summary = plain(context.masterySummary(stats, challenges));
  assert.equal(summary.mastered, 1);
  assert.equal(summary.independent, 0);
  assert.equal(summary.learning, 0);
  assert.equal(summary.due, 0);
  assert.equal(summary.byCategory.find((item: any) => item.category === "apps").mastered, 1);
});

test("hinted or wrong answers across spaced sessions never establish mastery", () => {
  for (const override of [{ hinted: true }, { wrongAttempts: 1 }]) {
    let stats = recordAttempt(null, terminal, override, NOW - DAY);
    stats = recordAttempt(stats, terminal, { ...override, sessionId: "second" }, NOW);
    const summary = plain(context.masterySummary(stats, challenges));
    assert.equal(summary.mastered, 0);
    assert.equal(summary.independent, 0);
    assert.equal(summary.learning, 1);
    assert.deepEqual(summary.weakIds, [terminal.id]);
    assert.deepEqual(stats.skills[terminal.signature].successfulSessions, []);
  }
  let stats = recordAttempt(null, terminal, {}, NOW - 2 * DAY);
  stats = recordAttempt(stats, terminal, { sessionId: "second" }, NOW - DAY);
  assert.equal(context.masterySummary(stats, challenges).mastered, 1);
  stats = recordAttempt(stats, terminal, { hinted: true, sessionId: "third" }, NOW);
  assert.equal(context.masterySummary(stats, challenges).mastered, 0, "a fresh struggle must not still read as mastery");
  assert.equal(context.masterySummary(stats, challenges).learning, 1);
});

test("mastery summary counts unique skills and conservative one-day or seven-day review intervals", () => {
  let stats = recordAttempt(null, terminal, {}, NOW - DAY);
  const float = challengeFor("float");
  stats = recordAttempt(stats, float, {}, NOW - 8 * DAY);
  stats = recordAttempt(stats, float, { sessionId: "second" }, NOW - 7 * DAY);
  const summary = plain(context.masterySummary(stats, [...challenges, ...challenges]));
  assert.equal(summary.total, 40);
  assert.equal(summary.practiced, 2);
  assert.equal(summary.learning + summary.independent + summary.mastered, 2);
  assert.equal(summary.mastered, 1);
  assert.equal(summary.due, 2);
  assert.equal(summary.byCategory.reduce((sum: number, item: any) => sum + item.total, 0), 40);
  assert.deepEqual(plain(context.masterySummary(null, null)),
    { total: 0, practiced: 0, learning: 0, independent: 0, mastered: 0, due: 0, weakIds: [], byCategory: [] });
});

test("adaptive practice balances weak, new and familiar skills without signature bias", () => {
  const weak = terminal;
  const fresh = challengeFor("launch-files");
  const familiar = challengeFor("float");
  const pool = [weak, fresh, familiar];
  let stats = recordAttempt(null, weak, { hinted: true });
  stats = recordAttempt(stats, familiar);
  const before = structuredClone(stats);
  const deck = plain(context.practiceDeck([...pool, weak, weak], stats, 12, context.seededRandom("practice"), "all"));
  assert.deepEqual(stats, before);
  assert.equal(deck.length, 12);
  assert.equal(deck[0].signature, weak.signature);
  assert.equal(deck[1].signature, fresh.signature);
  assert.equal(deck[2].signature, familiar.signature);
  assert.equal(new Set(deck.slice(0, 3).map((item: any) => item.signature)).size, 3);
  for (let i = 1; i < deck.length; i++) assert.notEqual(deck[i].signature, deck[i - 1].signature);
  for (const item of pool) assert.equal(deck.filter((entry: any) => entry.signature === item.signature).length, 4);
  assert.deepEqual(deck, plain(context.practiceDeck([...pool, weak], stats, 12, context.seededRandom("practice"), "all")));
});

test("due review wins the first slot and category filtering is strict", () => {
  let stats = recordAttempt(null, terminal, {}, NOW - DAY);
  stats = recordAttempt(stats, challengeFor("float"));
  const deck = plain(context.practiceDeck(challenges, stats, 20, context.seededRandom("due")));
  assert.equal(deck[0].id, terminal.id);
  assert.equal(new Set(deck.map((item: any) => item.signature)).size, 20);
  const windows = plain(context.practiceDeck(challenges, stats, 30, context.seededRandom("windows"), "windows"));
  assert.ok(windows.every((item: any) => item.category === "windows"));
  for (let i = 1; i < windows.length; i++) assert.notEqual(windows[i].signature, windows[i - 1].signature);
  const starter = context.practiceDeck(challenges, null, 1, context.seededRandom("new"))[0];
  assert.equal(starter.difficulty, "starter");
});

test("fresh adaptive runs explore every category and signature without requiring saved progress", () => {
  const seen = new Set<string>();
  const orders = new Set<string>();
  for (let seed = 0; seed < 200; seed++) {
    const deck = plain(context.practiceDeck(challenges, null, 12, context.seededRandom(`fresh-${seed}`)));
    assert.equal(deck.length, 12);
    assert.equal(new Set(deck.map((challenge: any) => challenge.signature)).size, 12);
    assert.equal(deck[0].difficulty, "starter");
    for (const challenge of deck) seen.add(challenge.signature);
    orders.add(deck.map((challenge: any) => challenge.signature).join("|"));
  }
  assert.deepEqual([...seen].sort(), challenges.map((challenge: any) => challenge.signature).sort());
  assert.equal(orders.size, 200);
});

test("full adaptive passes and fresh shuffles preserve breadth and captured replay order", () => {
  const before = structuredClone(challenges);
  const random = context.seededRandom("fresh-runs");
  const saved = plain(context.shuffled(challenges, random));
  const savedKey = context.deckKey("sprint", saved, "standard");
  const fresh = plain(context.shuffled(challenges, random));
  assert.notDeepEqual(fresh, saved);
  assert.deepEqual(fresh.map((item: any) => item.signature).sort(),
    saved.map((item: any) => item.signature).sort());
  let stats = recordAttempt(null, saved[0], { hinted: true });
  stats = recordAttempt(stats, saved[1]);
  const adaptive = plain(context.practiceDeck(challenges, stats, 120, random));
  for (let start = 0; start < 120; start += 40) {
    assert.equal(new Set(adaptive.slice(start, start + 40).map((item: any) => item.signature)).size, 40);
  }
  for (let i = 1; i < adaptive.length; i++) assert.notEqual(adaptive[i].signature, adaptive[i - 1].signature);
  assert.deepEqual(challenges, before);
  assert.equal(context.deckKey("sprint", saved, "standard"), savedKey);
});

test("practice selection handles empty, malformed and tiny pools safely", () => {
  assert.deepEqual(plain(context.practiceDeck(null, null, 4)), []);
  assert.deepEqual(plain(context.practiceDeck(challenges, null, 4, null, "missing")), []);
  for (const count of [0, -1, 1.5, Infinity, "12", null]) {
    assert.deepEqual(plain(context.practiceDeck(challenges, null, count)), []);
  }
  assert.equal(context.practiceDeck(challenges, null, 999).length, 200);
  const one = plain(context.practiceDeck([terminal, terminal], null, 4, () => Number.NaN));
  assert.equal(one.length, 4);
  assert.ok(one.every((challenge: any) => challenge.signature === terminal.signature));
  const pair = [terminal, challengeFor("float")];
  const alternating = plain(context.practiceDeck(pair, null, 50, () => 0));
  for (let i = 1; i < alternating.length; i++) assert.notEqual(alternating[i].signature, alternating[i - 1].signature);
});

test("recommendations offer an unblocked starter theme and honestly target weak or due skills", () => {
  const starter = plain(context.recommendedPractice(challenges, null));
  assert.equal(starter.category, "apps");
  assert.match(starter.label, /Start with/);
  assert.match(starter.detail, /Every deck is available/);
  assert.ok(starter.ids.length > 0);
  assert.ok(starter.ids.every((id: string) => challenges.find((item: any) => item.id === id).difficulty === "starter"));
  const float = challengeFor("float");
  let stats = recordAttempt(null, float, { hinted: true });
  const weak = plain(context.recommendedPractice(challenges, stats));
  assert.equal(weak.category, "windows");
  assert.deepEqual(weak.ids, [float.id]);
  assert.match(weak.detail, /without a hint/);
  stats = recordAttempt(null, terminal, {}, NOW - DAY);
  const due = plain(context.recommendedPractice(challenges, stats));
  assert.equal(due.category, "apps");
  assert.deepEqual(due.ids, [terminal.id]);
  assert.match(due.detail, /spaced review/);
  assert.equal(context.recommendedPractice([terminal], recordAttempt(null)).category, "all");
  assert.deepEqual(plain(context.recommendedPractice([], null)), {
    category: "all", label: "Keep recall fresh", detail: "No playable shortcuts are available in this course.", ids: [],
  });
});

test("persisted numeric values, skill evidence, keys and split arrays are sanitized", () => {
  const polluted = JSON.parse('{"__proto__":{"attempts":9},"constructor":{"attempts":9}}');
  const value = {
    version: 2,
    sprint: { bestScore: 12, bestStreak: -1, plays: 2.5, clears: "4" },
    keyfall: { bestScore: Infinity, bestStreak: 3, plays: 4, clears: 2 },
    skills: {
      ...polluted,
      [terminal.signature]: {
        attempts: 3, assisted: 1, unassisted: 99, firstTry: 99,
        lastSeenAt: NOW, bestRecallMs: Infinity, meanRecallMs: Infinity,
        successfulSessions: [
          { sessionId: "same", at: NOW - DAY }, { sessionId: "same", at: NOW },
          { sessionId: "future", at: NOW + DAY }, { sessionId: "invalid", at: Infinity },
        ],
        history: [{ at: NOW, sessionId: "same", hinted: true, wrongAttempts: 1, elapsedMs: 100, clean: true }],
      },
    },
    records: {
      "__proto__": {},
      "arcade-v2|rescue|invalid": { plays: 1, bestScore: 9000 },
      [run().deckKey]: { bestScore: Infinity, bestClean: -1, bestElapsedMs: Infinity, plays: 1, splits: [Infinity] },
    },
  };
  const sanitized = plain(context.mergeStats(value));
  assert.deepEqual(sanitized.sprint, { bestScore: 12, bestStreak: 0, plays: 0, clears: 0 });
  assert.deepEqual(sanitized.keyfall, { bestScore: 0, bestStreak: 3, plays: 4, clears: 2 });
  assert.deepEqual(Object.keys(sanitized.skills), [terminal.signature]);
  const skill = sanitized.skills[terminal.signature];
  assert.equal(skill.unassisted, 2);
  assert.equal(skill.firstTry, 2);
  assert.equal(skill.meanRecallMs, 0);
  assert.equal(skill.successfulSessions.length, 1);
  assert.equal(skill.history[0].clean, false);
  assert.equal(context.masterySummary(sanitized, challenges).mastered, 0);
  assert.deepEqual(Object.keys(sanitized.records), [run().deckKey]);
  assert.deepEqual(sanitized.records[run().deckKey],
    { bestScore: 0, bestClean: 0, bestElapsedMs: 0, splits: [], plays: 1 });
  assert.equal(({} as any).attempts, undefined);
});

test("attempt history, successful sessions and deck records remain bounded", () => {
  let stats: any = null;
  for (let i = 0; i < 80; i++) {
    stats = recordAttempt(stats, terminal, { sessionId: `session-${i}` }, NOW - (80 - i) * DAY);
  }
  const skill = stats.skills[terminal.signature];
  assert.equal(skill.attempts, 80);
  assert.equal(skill.history.length, 24);
  assert.equal(skill.successfulSessions.length, 32);
  assert.equal(skill.successfulSessions[0].at, NOW - 80 * DAY);
  assert.equal(context.masterySummary(stats, challenges).mastered, 1);
  for (let i = 0; i < 110; i++) {
    const key = context.deckKey("rescue", context.rescueDeck(challenges), `pace-${i}`);
    stats = plain(context.recordRun(stats, run({ deckKey: key }), NOW));
  }
  assert.equal(Object.keys(stats.records).length, 100);
  assert.equal(context.bestForDeck(stats, context.deckKey("rescue", context.rescueDeck(challenges), "pace-0")).plays, 0);
  assert.equal(context.bestForDeck(stats, context.deckKey("rescue", context.rescueDeck(challenges), "pace-109")).plays, 1);
  assert.deepEqual(plain(context.mergeStats(stats)), stats);
});

test("custom-course skill storage keeps the most recently practiced 512 valid signatures", () => {
  const skills: Record<string, any> = {};
  const modifiers = ["SUPER", "CTRL", "ALT", "SHIFT"];
  let index = 0;
  for (let mask = 1; mask < 16; mask++) {
    for (const key of "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789") {
      const signature = [...modifiers.filter((_, bit) => mask & (1 << bit)), key].join("+");
      skills[signature] = { attempts: 1, assisted: 1, unassisted: 0, firstTry: 0, lastSeenAt: NOW + index++ };
    }
  }
  const before = structuredClone(skills);
  const normalized = plain(context.mergeStats({ version: 2, skills }));
  assert.deepEqual(skills, before);
  assert.equal(Object.keys(normalized.skills).length, 512);
  assert.equal(normalized.skills["SUPER+A"], undefined);
  assert.equal(normalized.skills["SUPER+CTRL+ALT+SHIFT+9"].attempts, 1);
  assert.deepEqual(plain(context.mergeStats(normalized)), normalized);
});
