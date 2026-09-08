import assert from "node:assert/strict";
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { runInNewContext } from "node:vm";
import test from "node:test";

const store = readFileSync(new URL("../app/CharacterPackStore.qml", import.meta.url), "utf8");
const lab = readFileSync(new URL("../experiments/hexon-lab/shell.qml", import.meta.url), "utf8");
const functions = [...store.matchAll(/^  function \w+\([^\n]*\) \{[\s\S]*?^  \}/gm)]
  .map(match => match[0]).join("\n");

function harness() {
  const callbacks: (() => void)[] = [];
  const warnings: string[] = [];
  const context: any = {
    _snapshot: { version: 1, packs: [], diagnostics: [], fallbackId: null },
    _generation: 0, _pending: false, _loading: false, _stopping: false, _awaitingExit: false,
    _ready: false, _failure: "",
    requestedId: "ohm-1", appRoot: "/app with spaces", bundledRoot: "/bundled", userRoot: "/user",
    worker: { generation: 0, command: [], running: false },
    timeout: {
      generation: 0, running: false, starts: 0, stops: 0,
      restart() { this.running = true; this.starts++; },
      stop() { this.running = false; this.stops++; },
    },
    Qt: { callLater(callback: () => void) { callbacks.push(callback); } },
    console: { warn(...args: unknown[]) { warnings.push(args.join(" ")); } },
  };
  Object.defineProperty(context, "selectedPack", {
    get() { return context.resolveSelection(context._snapshot.packs, context.requestedId, context._snapshot.fallbackId); },
  });
  runInNewContext(functions, context);
  return { context, warnings, callbacks };
}

const pack = (id: string, narration: object = { mode: "own", audioSet: id }) => ({
  id, assetUrl: `file:///packs/${id}`, manifest: { formatVersion: 1, id, displayName: id, narration },
});
const catalog = (packs = [pack("ohm-1"), pack("owl"), pack("third")], fallbackId: string | null = "ohm-1") =>
  JSON.stringify({ version: 1, packs, diagnostics: [], fallbackId });

test("pack store consumes only centralized CLI results; main and lab share one renderer", () => {
  assert.doesNotMatch(store + lab, /FileView|index\.json|\/character\.json/);
  assert.match(store, /"node", "--experimental-strip-types", appRoot \+ "\/tools\/character-packs\.ts"/);
  assert.match(store, /"discover", "--bundled-root", bundledRoot/);
  assert.match(store, /if \(userRoot\) command\.push\("--user-root", userRoot\)/);
  assert.match(lab, /App\.CharacterPackStore\s*\{/);
  assert.equal((lab.match(/App\.CharacterSprite\s*\{/g) || []).length, 1);
  assert.match(lab, /App\.IntroPlayer\s*\{/);
  assert.match(lab, /pack: packStore\.selectedPack/);
  assert.match(lab, /assetRoot: packStore\.selectedPack \? packStore\.selectedPack\.assetUrl : ""/);
  for (const name of ["intro", "reset", "stop", "refresh"]) {
    assert.match(lab, new RegExp(`function ${name}\\(`));
  }
  assert.match(lab, /onVisibleChanged: if \(!visible\) root\.stopIntro\(\)/);
  assert.match(lab, /onScreenChanged: if \(root\.introActive\) root\.stopIntro\(\)/);
});

test("the lab can preview missing and invalid-intro fallbacks through the shared player", () => {
  const calls: string[] = [];
  const c: any = {
    packStore: { selectedPack: { intro: null } },
    stopIntro() { calls.push("stop"); },
    introPlayer: { play() { calls.push("play"); } },
    demoRunning: true, introError: "previous failure", introActive: false,
  };
  const playIntro = lab.match(/^  function playIntro\(\) \{[\s\S]*?^  \}/m)![0];
  runInNewContext(playIntro, c);
  assert.equal(c.playIntro(), "ok");
  assert.deepEqual(calls, ["stop", "play"]);
  assert.equal(c.introActive, true);
  assert.equal(c.demoRunning, false);
  assert.equal(c.introError, "");
  c.packStore.selectedPack = null;
  assert.equal(c.playIntro(), "no-character");
  assert.deepEqual(calls, ["stop", "play"]);
});

test("all lab text, including reusable buttons and pack diagnostics, renders as plain text", () => {
  const labels = [...lab.matchAll(/\bText\s*\{([^}]+)/g)];
  assert.ok(labels.length >= 6);
  for (const label of labels) {
    assert.match(label[1], /textFormat:\s*Text\.PlainText/,
      "Markup-looking Unicode pack names and diagnostic messages must remain literal");
  }
});

test("selection honors the latest requested ID, third-party packs, and the CLI fallback", () => {
  const { context: c } = harness();
  c.acceptResult(catalog(), "", 0);
  assert.equal(c.selectedPack.id, "ohm-1");
  assert.equal(c.select("third"), true);
  assert.equal(c.requestedId, "third");
  assert.equal(c.selectedPack.id, "third");
  assert.equal(c.select("missing"), false);
  assert.equal(c.requestedId, "missing");
  assert.equal(c.selectedPack.id, "ohm-1");
  c.acceptResult(catalog([pack("owl")], "owl"), "", 0);
  assert.equal(c.selectedPack.id, "owl");
  c.acceptResult(catalog([], null), "", 0);
  assert.equal(c.selectedPack, null);
  assert.equal(c._ready, true);
});

test("the CLI owns default user-root resolution while explicit overrides stay literal", () => {
  assert.match(store, /property string userRoot: ""/);
  assert.doesNotMatch(store, /Quickshell\.env|XDG_DATA_HOME|\.local\/share/);
  const { context: c } = harness();
  c.userRoot = "";
  c.refresh();
  assert.deepEqual(Array.from(c.worker.command), [
    "node", "--experimental-strip-types", "/app with spaces/tools/character-packs.ts",
    "discover", "--bundled-root", "/bundled",
  ]);
  c.finishDiscovery(catalog(), "", 1);
  c.userRoot = "/custom root/characters";
  c.refresh();
  assert.deepEqual(Array.from(c.worker.command).slice(-2), ["--user-root", "/custom root/characters"]);
});

test("refresh preserves the last valid snapshot on process failure or malformed JSON", () => {
  const { context: c, warnings } = harness();
  c.acceptResult(catalog(), "", 0);
  const snapshot = c._snapshot;
  c.acceptResult("{invalid", "", 0);
  assert.equal(c._snapshot, snapshot);
  assert.match(c._failure, /Cannot read/);
  c.acceptResult("{}", "", 0);
  assert.equal(c._snapshot, snapshot);
  c.acceptResult("", "Worker failed", 0);
  assert.equal(c._snapshot, snapshot);
  assert.equal(c._failure, "Worker failed");
  assert.equal(warnings.length, 3);
  c.acceptResult(catalog(), "", 0);
  assert.equal(c._failure, "");
});

test("queued refresh rejects stale catalogs and selection changes do not restart discovery", () => {
  const { context: c, callbacks } = harness();
  c.refresh();
  assert.equal(c.worker.command[2], "/app with spaces/tools/character-packs.ts");
  assert.equal(c.worker.generation, 1);
  c.select("third");
  assert.equal(c._generation, 1);
  c.refresh();
  assert.equal(c._pending, true);
  c.finishDiscovery(catalog([pack("ohm-1")]), "", 1);
  assert.equal(c._snapshot.packs.length, 0, "stale discovery cannot replace the catalog");
  callbacks.shift()!();
  assert.equal(c.worker.generation, 2);
  c.select("owl");
  c.finishDiscovery(catalog(), "", 2);
  assert.equal(c.selectedPack.id, "owl");
  assert.equal(c._loading, false);
});

test("a refresh between worker completion and the queued restart does not launch twice", () => {
  const { context: c, callbacks } = harness();
  c.refresh();
  c.refresh();
  c.finishDiscovery(catalog(), "", 1);
  c.refresh();
  assert.equal(c.worker.generation, 3);
  assert.equal(c._loading, true);
  callbacks.shift()!();
  assert.equal(c.worker.generation, 3);
  c.finishDiscovery(catalog(), "", 3);
  assert.equal(c._ready, true);
});

test("a timed-out worker retains its request fields until exit before pending refresh starts", () => {
  const { context: c, callbacks } = harness();
  c.acceptResult(catalog(), "", 0);
  const snapshot = c._snapshot;
  c.refresh();
  c.discoveryStarted(1);
  c.expireDiscovery(1);
  assert.equal(c._stopping, true);
  assert.equal(c._loading, true);
  assert.equal(c.worker.running, false, "cancellation has been requested");
  assert.equal(c._snapshot, snapshot);
  assert.match(c._failure, /timed out/);

  c.refresh();
  c.refresh();
  c.startPendingDiscovery();
  assert.equal(c.worker.generation, 1, "do not reuse request fields while the old exit is outstanding");
  assert.equal(c.timeout.starts, 1);
  assert.equal(callbacks.length, 0);
  c.finishDiscovery(catalog([pack("obsolete")], "obsolete"), "", c.worker.generation);
  assert.equal(c._snapshot, snapshot, "cancelled output must never replace a valid catalog");
  assert.equal(c._loading, false);
  assert.equal(c._stopping, false);
  assert.equal(c._awaitingExit, false);
  callbacks.shift()!();
  assert.equal(c.worker.generation, 3);
  assert.equal(c.timeout.generation, 3);
  assert.equal(c.timeout.starts, 2);
  assert.equal(c._loading, true);
  const stops = c.timeout.stops;
  c.finishDiscovery(catalog([pack("obsolete")], "obsolete"), "", 1);
  c.expireDiscovery(1);
  assert.equal(c.timeout.stops, stops, "late old callbacks cannot stop the newer timeout");
  assert.equal(c.timeout.running, true);
  assert.equal(c.worker.running, true);
  assert.equal(c._snapshot, snapshot);
  c.finishDiscovery(catalog([pack("third")], "third"), "", 3);
  assert.equal(c.selectedPack.id, "third");
  assert.equal(c._failure, "");
});

test("a queued refresh waits for timeout cancellation even when running clears before exit", () => {
  const { context: c, callbacks } = harness();
  c.refresh();
  c.discoveryStarted(1);
  c.refresh();
  c.worker.running = false;
  c.expireDiscovery(1);
  assert.equal(c._stopping, true);
  assert.equal(c._awaitingExit, true);
  assert.equal(callbacks.length, 0);
  c.finishDiscovery(catalog([pack("obsolete")], "obsolete"), "", 1);
  assert.equal(c._snapshot.packs.length, 0);
  callbacks.shift()!();
  assert.equal(c.worker.generation, 2);
  c.finishDiscovery(catalog(), "", 2);
  assert.equal(c.selectedPack.id, "ohm-1");
});

test("failed launches without a started process release the queue without waiting for an exit", () => {
  const { context: c, callbacks } = harness();
  c.refresh();
  c.worker.running = false;
  c.expireDiscovery(1);
  assert.equal(c._stopping, false);
  assert.equal(c._loading, false);
  assert.equal(c._ready, true);
  assert.match(c._failure, /could not start/);
  c.refresh();
  c.refresh();
  c.worker.running = false;
  c.expireDiscovery(2);
  assert.equal(c._stopping, false);
  assert.equal(c._loading, false);
  callbacks.shift()!();
  assert.equal(c.worker.generation, 3);
  c.finishDiscovery(catalog(), "", 3);
  assert.equal(c.selectedPack.id, "ohm-1");
  assert.equal(c._failure, "");
});

test("own, silent, and borrowed narration resolve without speaking the wrong coach name", () => {
  const { context: c, warnings } = harness();
  c.acceptResult(catalog([pack("third")], "third"), "", 0);
  assert.equal(c.audioPath("audio/welcome.mp3", "I am HEXON", "/course"), "/course/audio/third/welcome.mp3");
  assert.equal(c.audioPath("done.mp3", "", "/course/"), "/course/third/done.mp3");
  c.acceptResult(catalog([pack("third", { mode: "silent" })], "third"), "", 0);
  assert.equal(c.audioPath("audio/welcome.mp3", "Hello", "/course"), "");
  for (const audioSet of ["ohm-1", "owl"]) {
    c.acceptResult(catalog([pack("third", { mode: "borrowed", audioSet })], "third"), "", 0);
    assert.equal(c.audioPath("audio/welcome.mp3", "Press Super", "/course"), `/course/audio/${audioSet}/welcome.mp3`);
    for (const text of ["I am HEXON", "Hexon's next step", "I'm Archie", "ARCHIE can help", "I'm Ohm", "Meet Ohm-1", "OMARI can help", "ollie says hello", "Meet OLLIE"]) {
      assert.equal(c.audioPath("audio/welcome.mp3", text, "/course"), "");
    }
  }
  assert.equal(c.audioPath("", "Hello", "/course"), "");
  c.acceptResult(catalog([], null), "", 0);
  assert.equal(c.audioPath("audio/welcome.mp3", "Hello", "/course"), "");
  assert.equal(warnings.length, 0, "intentional text-only fallback does not emit per-clip warnings");
});

test("lab launcher accepts user pack IDs and preserves explicit roots without launching a desktop", () => {
  const directory = resolve(`.lab-launcher-test-${process.pid}`);
  mkdirSync(directory);
  try {
    writeFileSync(resolve(directory, "qs"), `#!/usr/bin/env node
console.log(JSON.stringify({ args: process.argv.slice(2), root: process.env.CHARACTER_LAB_ROOT,
  appRoot: process.env.CHARACTER_LAB_APP_ROOT, character: process.env.CHARACTER_LAB_CHARACTER }));
`, { mode: 0o755 });
    const launch = (id: string) => spawnSync("bash", ["bin/hexon-lab", id], {
      encoding: "utf8",
      env: { ...process.env, PATH: `${directory}:${process.env.PATH}`, CHARACTER_LAB_ROOT: "/custom pack root" },
    });
    const result = launch("third-coach");
    assert.equal(result.status, 0, result.stderr);
    const data = JSON.parse(result.stdout);
    assert.equal(data.character, "third-coach");
    assert.equal(data.root, "/custom pack root");
    assert.equal(data.appRoot, process.cwd());
    assert.deepEqual(data.args, ["--no-duplicate", "--path", resolve("character-lab.qml")]);
    assert.equal(launch("../bad").status, 2);
    for (const invalid of ["1coach", "coach--name", "coach-", "a".repeat(65)]) {
      assert.equal(launch(invalid).status, 2, invalid);
    }
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
