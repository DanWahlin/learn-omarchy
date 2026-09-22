import assert from "node:assert/strict";
import test from "node:test";
import { spawn, spawnSync } from "node:child_process";
import { copyFile, mkdir, mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { once } from "node:events";
import { resolve, join } from "node:path";
import { createContext, runInContext } from "node:vm";
import { pathToFileURL } from "node:url";
import { validRegion, recordingDirectory, screenshotDirectory, sessionActions } from "../tools/capture-practice.mjs";

const practiceSource = await readFile(new URL("../app/PracticeSession.qml", import.meta.url), "utf8");

test("capture verification is not reset after the preview starts loading", () => {
  assert.doesNotMatch(practiceSource, /content\.screenshot = path\s+content\.verified = false/);
});

function lockRuntime() {
  const context = createContext({
    lifecycle: "running", outcome: "cancelled", closingQueued: false,
    get running() { return this.lifecycle === "running"; },
    get closing() { return this.lifecycle === "closing"; },
    taskPending: false, capturePending: false, recordingPending: false, lockPending: false, lockStatusPending: false,
    lockObserved: false,
    content: { busy: true, verified: false, error: "", stopPlayback() {} },
    lockStatus: { running: false },
    lockCheckTimer: { running: true, stop() { this.running = false; } },
    lockObservationTimeout: { running: true, stop() { this.running = false; } },
  });
  context.root = context;
  runInContext(Array.from(practiceSource.matchAll(/^  function \w+\([^\n]*\) \{[\s\S]*?^  \}/gm), match => match[0]).join("\n"), context);
  return context;
}

test("lock practice requires compositor-secured locking followed by a real unlock", () => {
  const state = lockRuntime();
  state.handleLockStatus(0, JSON.stringify({ locked: false, sessionLocked: false, secure: false }));
  assert.equal(state.content.verified, false);
  state.handleLockStatus(0, JSON.stringify({ locked: true, sessionLocked: false, secure: false }));
  assert.equal(state.lockObserved, false);
  state.handleLockStatus(0, JSON.stringify({ locked: true, sessionLocked: true, secure: true }));
  assert.equal(state.lockObserved, true);
  assert.equal(state.lockObservationTimeout.running, false);
  assert.equal(state.content.verified, false);
  state.handleLockStatus(0, JSON.stringify({ locked: false, sessionLocked: false, secure: false }));
  assert.equal(state.content.verified, true);
  assert.equal(state.lockCheckTimer.running, false);
  assert.match(practiceSource, /command: \["omarchy-shell", "lock", "status"\]/);
});

test("screenshot watcher reports only new native Omarchy screenshots", async () => {
  const directory = await mkdtemp(resolve("tests/.screenshot-watch-"));
  const existing = join(directory, "screenshot-2026-09-21_23-00-00.png");
  const created = join(directory, "screenshot-2026-09-21_23-00-01.png");
  await writeFile(existing, "existing");
  assert.equal(await screenshotDirectory({ HOME: directory, OMARCHY_SCREENSHOT_DIR: directory }), directory);

  const watcher = spawn(process.execPath, ["tools/capture-practice.mjs", "--watch-screenshots"], {
    env: { ...process.env, OMARCHY_SCREENSHOT_DIR: directory },
    stdio: ["ignore", "pipe", "pipe"],
  });
  let output = "";
  watcher.stdout.setEncoding("utf8").on("data", data => { output += data; });
  try {
    await new Promise(resolveDelay => setTimeout(resolveDelay, 400));
    assert.equal(output, "");
    await writeFile(created, "new screenshot");
    for (let attempt = 0; attempt < 20 && !output.includes(created); attempt++)
      await new Promise(resolveDelay => setTimeout(resolveDelay, 100));
    assert.equal(output.trim(), created);
  } finally {
    watcher.kill("SIGTERM");
    await once(watcher, "exit");
    await rm(directory, { recursive: true, force: true });
  }
});

test("recording watcher follows native start and finalized-save transitions", async () => {
  const directory = await mkdtemp(resolve("tests/.recording-watch-"));
  const marker = join(directory, "active-recording");
  const existing = join(directory, "screenrecording-2026-09-21_23-00-00.mp4");
  const created = join(directory, "screenrecording-2026-09-21_23-00-01.mp4");
  const retake = join(directory, "screenrecording-2026-09-21_23-00-02.mp4");
  await writeFile(existing, "existing");
  await writeFile(marker, existing);
  assert.equal(await recordingDirectory({ HOME: directory, OMARCHY_SCREENRECORD_DIR: directory }), directory);

  const watcher = spawn(process.execPath, ["tools/capture-practice.mjs", "--watch-recordings"], {
    env: {
      ...process.env,
      OMARCHY_SCREENRECORD_DIR: directory,
      OMARCHY_SCREENRECORD_MARKER: marker,
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
  let output = "";
  watcher.stdout.setEncoding("utf8").on("data", data => { output += data; });
  const waitFor = async (needle: string) => {
    for (let attempt = 0; attempt < 30 && !output.includes(needle); attempt++)
      await new Promise(resolveDelay => setTimeout(resolveDelay, 100));
    assert.match(output, new RegExp(needle.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
  };
  try {
    await waitFor('"event":"already-active"');
    await writeFile(existing, "existing recording still growing");
    await rm(marker);
    await new Promise(resolveDelay => setTimeout(resolveDelay, 750));
    assert.doesNotMatch(output, /"event":"saved"/, "A recording active before the exercise is never claimed");

    await writeFile(marker, created);
    await writeFile(created, "recording");
    await waitFor('"event":"started"');
    await writeFile(created, "recording still growing");
    await new Promise(resolveDelay => setTimeout(resolveDelay, 750));
    assert.doesNotMatch(output, /"event":"saved"/, "Growing media is not reported before native recording stops");

    await rm(marker);
    await waitFor(`"event":"saved","path":"${created}"`);

    await writeFile(marker, retake);
    await writeFile(retake, "retake");
    await new Promise(resolveDelay => setTimeout(resolveDelay, 300));
    await rm(marker);
    await waitFor(`"event":"saved","path":"${retake}"`);
  } finally {
    watcher.kill("SIGTERM");
    await once(watcher, "exit");
    await rm(directory, { recursive: true, force: true });
  }
});

test("unavailable or malformed lock reporting never completes an exercise", () => {
  for (const [code, raw] of [[1, ""], [0, "{}"], [0, "false"], [0, "invalid"], [0, '{"locked":"true","sessionLocked":true,"secure":true}']]) {
    const state = lockRuntime();
    state.handleLockStatus(code, raw);
    assert.equal(state.content.verified, false);
    assert.equal(state.content.busy, false);
    assert.match(state.content.error, /skip this optional exercise/);
  }
});

test("closing practice waits for helper cleanup before destroying Quickshell processes", () => {
  const state = lockRuntime();
  const pending = () => ({ active: true, requested: true, get running() { return this.active; }, set running(value) { this.requested = value; } });
  state.captureProcess = pending();
  state.taskProcess = pending();
  state.recordingProcess = pending();
  state.lockProcess = { running: false };
  state.capturePending = true;
  state.taskPending = true;
  state.recordingPending = true;
  const callbacks: (() => void)[] = [];
  let cancelled = 0;
  state.cancelled = () => { cancelled++; };
  state.Qt = { callLater(callback: () => void) { callbacks.push(callback); } };
  state.cancel();
  assert.equal(state.captureProcess.requested, false);
  assert.equal(state.taskProcess.requested, false);
  assert.equal(state.recordingProcess.requested, false);
  assert.equal(cancelled, 0);
  state.captureProcess.active = false;
  state.finishClosing();
  assert.equal(callbacks.length, 0, "runningChanged alone is not an exit acknowledgement");
  state.capturePending = false;
  state.recordingProcess.active = false;
  state.recordingPending = false;
  state.taskProcess.active = false;
  state.finishClosing();
  assert.equal(callbacks.length, 0);
  state.taskPending = false;
  state.finishClosing();
  state.finishClosing();
  assert.equal(callbacks.length, 1);
  assert.equal(cancelled, 0);
  callbacks[0]();
  assert.equal(cancelled, 1);
  assert.equal(state.lifecycle, "closed");
  assert.doesNotMatch(practiceSource, /Qt\.quit|FloatingWindow|PanelWindow|execDetached|FileView|OmarchyTheme/);
});

test("real embedded sessions complete locally and wait for worker cleanup before Loader unload", async () => {
  const directory = await mkdtemp(resolve("tests/.embedded-practice-"));
  try {
    await mkdir(join(directory, "bin"));
    await writeFile(join(directory, "bin/learn-omarchy-practice"), `#!${process.execPath}
import { writeFileSync } from "node:fs";
process.on("SIGTERM", () => setTimeout(() => {
  writeFileSync(process.env.LEARN_SESSION_CLEANUP, "cleaned");
  process.exit(0);
}, 150));
console.log(JSON.stringify({action: "create", path: "/isolated/demo.desktop"}));
setInterval(() => {}, 1000);
`, { mode: 0o700 });
    const fixture = join(directory, "shell.qml");
    await writeFile(fixture, `import QtQuick
import Quickshell
import ${JSON.stringify(pathToFileURL(resolve("app")).href)} as App
ShellRoot {
  id: root
  property bool composed: false
  property bool rejected: false
  function check(ok, message) {
    if (!ok) { console.error("EMBEDDED_FAILURE: " + message); Qt.quit(); }
  }
  App.PracticeSession {
    id: compose
    mode: "compose"
    autoStart: false
    width: 760; height: 500
    onCompleted: {
      root.check(!running && !closing, "completion must follow cleanup");
      root.composed = true;
      worker.active = true;
    }
  }
  App.PracticeSession {
    id: invalid
    mode: "unsupported"
    autoStart: false
    onFailed: function(message) { root.rejected = message.indexOf("Unsupported") !== -1; }
  }
  Loader {
    id: worker
    active: false
    sourceComponent: App.PracticeSession {
      mode: "web-app"
      width: 760; height: 500
      onCancelled: {
        root.check(root.composed && root.rejected, "all lifecycles must run");
        worker.active = false;
        console.log("EMBEDDED_SESSION_CLEAN");
        Qt.quit();
      }
    }
  }
  Timer {
    interval: 20; running: worker.active; repeat: true
    onTriggered: {
      if (worker.item && JSON.parse(worker.item.status()).stage === 1 && worker.item.running) {
        worker.item.cancel();
        root.check(worker.item.closing, "cancel must be asynchronous");
      }
    }
  }
  Component.onCompleted: Qt.callLater(function() {
    invalid.start();
    compose.start();
    compose.finish();
    root.check(compose.running, "unverified cannot finish");
    var content = compose.children.find(function(child) { return child.objectName === "practiceContent"; });
    content.verified = true;
    compose.finish();
    root.check(compose.closing && !root.composed, "completion must unwind");
  })
}`);
    const result = spawnSync("qs", ["--no-color", "--path", fixture], {
      encoding: "utf8", timeout: 10000,
      env: { ...process.env, LEARN_OMARCHY_ROOT: directory,
        LEARN_SESSION_CLEANUP: join(directory, "cleanup"),
        QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software",
        QT_QPA_PLATFORMTHEME: "generic", QT_QUICK_CONTROLS_STYLE: "Basic",
        XDG_RUNTIME_DIR: directory, XDG_CONFIG_HOME: join(directory, "config"),
        XDG_CACHE_HOME: join(directory, "cache"), HYPRLAND_INSTANCE_SIGNATURE: "learn-no-compositor",
        WAYLAND_DISPLAY: "", DBUS_SESSION_BUS_ADDRESS: `unix:path=${directory}/no-bus` },
    });
    const output = result.stdout + result.stderr;
    assert.equal(result.status, 0, output);
    assert.match(output, /EMBEDDED_SESSION_CLEAN/);
    assert.doesNotMatch(output, /EMBEDDED_FAILURE|Failed to load configuration|ReferenceError|TypeError/);
    assert.equal(await readFile(join(directory, "cleanup"), "utf8"), "cleaned");
  } finally { await rm(directory, { recursive: true, force: true }); }
});

test("embedded cancellation handles a missing helper and cancellation during startup", async () => {
  const directory = await mkdtemp(resolve("tests/.embedded-startup-"));
  try {
    for (const immediate of [true, false]) {
      const fixture = join(directory, immediate ? "immediate.qml" : "missing.qml");
      await writeFile(fixture, `import QtQuick
import Quickshell
import ${JSON.stringify(pathToFileURL(resolve("app")).href)} as App
ShellRoot {
  App.PracticeSession {
    id: session
    mode: "web-app"
    autoStart: false
    onCancelled: { console.log("STARTUP_CANCELLED"); Qt.quit(); }
  }
  Timer { interval: 200; running: ${!immediate}; onTriggered: session.cancel() }
  Component.onCompleted: Qt.callLater(function() { session.start(); ${immediate ? "session.cancel();" : ""} })
}`);
      const result = spawnSync("qs", ["--no-color", "--path", fixture], {
        encoding: "utf8", timeout: 3000,
        env: { ...process.env, LEARN_OMARCHY_ROOT: directory,
          QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software",
          QT_QPA_PLATFORMTHEME: "generic", QT_QUICK_CONTROLS_STYLE: "Basic",
          XDG_RUNTIME_DIR: directory, XDG_CONFIG_HOME: join(directory, "config"),
          XDG_CACHE_HOME: join(directory, "cache"), HYPRLAND_INSTANCE_SIGNATURE: "learn-no-compositor",
          WAYLAND_DISPLAY: "", DBUS_SESSION_BUS_ADDRESS: `unix:path=${directory}/no-bus` },
      });
      const output = result.stdout + result.stderr;
      assert.equal(result.status, 0, output);
      assert.match(output, /STARTUP_CANCELLED/);
    }
  } finally { await rm(directory, { recursive: true, force: true }); }
});

test("capture accepts only explicit nonempty regions", () => {
  for (const region of ["0,0 400x300", "-1920,10 800x600"]) assert.equal(validRegion(region), true);
  for (const region of ["", "0,0 0x100", "fullscreen", "1,2 20x30; echo nope", "0,0 9e3x50", "9007199254740992,0 20x30"]) assert.equal(validRegion(region), false);
});

function captureEnv(directory: string, mode: string) {
  return {
    ...process.env,
    PATH: resolve("tests/fixtures/capture") + ":" + process.env.PATH,
    XDG_RUNTIME_DIR: directory,
    LEARN_CAPTURE_TEST_DIR: directory,
    LEARN_CAPTURE_TEST_MODE: mode,
  };
}

test("capture keeps a real image, distinguishes errors, and removes cancelled output", async () => {
  const directory = await mkdtemp(resolve("tests/.learn-capture-test-"));
  try {
    for (const mode of ["cancel", "error", "success"]) {
      const result = spawnSync(process.execPath, ["tools/capture-practice.mjs"], {
        env: captureEnv(directory, mode), encoding: "utf8",
      });
      assert.equal(result.status, mode === "cancel" ? 2 : mode === "error" ? 1 : 0, result.stderr);
      if (mode === "success") {
        const path = result.stdout.trim();
        assert.ok(path.startsWith(directory + "/learn-omarchy-capture."));
        const image = await readFile(path);
        assert.equal(image.subarray(1, 4).toString(), "PNG");
      } else {
        assert.deepEqual(await readdir(directory), []);
        assert.equal(result.stdout, "");
        if (mode === "error") assert.match(result.stderr, /Capture protocol unavailable/);
      }
    }
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("cancelling capture terminates its selector and cleans only its temporary directory", async () => {
  const directory = await mkdtemp(resolve("tests/.learn-capture-test-"));
  const capture = spawn(process.execPath, ["tools/capture-practice.mjs"], {
    env: captureEnv(directory, "wait"), stdio: "ignore",
  });
  const exited = once(capture, "exit");
  try {
    for (let i = 0; i < 100 && !(await readdir(directory)).includes("selector.pid"); i++) {
      await new Promise(resolve => setTimeout(resolve, 20));
    }
    const selectorPid = Number(await readFile(join(directory, "selector.pid"), "utf8"));
    assert.ok(selectorPid > 0);
    capture.kill("SIGTERM");
    const [code] = await exited;
    assert.equal(code, 2);
    assert.throws(() => process.kill(selectorPid, 0), { code: "ESRCH" });
    assert.deepEqual(await readdir(directory), ["selector.pid"]);
  } finally {
    if (capture.exitCode === null && capture.signalCode === null) {
      capture.kill("SIGTERM");
      await exited;
    }
    await rm(directory, { recursive: true, force: true });
  }
});

test("practice launcher rejects unsupported modes without opening a window", () => {
  const result = spawnSync("bin/learn-omarchy-practice", ["unknown"], { encoding: "utf8" });
  assert.equal(result.status, 2);
  assert.match(result.stderr, /Usage:/);
});

test("every curriculum practice mode reaches the launcher without opening a desktop window", async () => {
  const directory = await mkdtemp(resolve("tests/.practice-launcher-"));
  try {
    await writeFile(join(directory, "qs"), '#!/bin/sh\nprintf "%s" "$LEARN_OMARCHY_PRACTICE_MODE"\n', { mode: 0o700 });
    const course = JSON.parse(await readFile(new URL("../courses/omarchy-basics.json", import.meta.url), "utf8"));
    for (const step of course.lessons.flatMap(lesson => lesson.steps).filter(step => step.practice)) {
      const result = spawnSync("bin/learn-omarchy-practice", [step.practice], {
        encoding: "utf8", env: { ...process.env, PATH: directory + ":" + process.env.PATH },
      });
      assert.equal(result.status, 0, result.stderr);
      assert.equal(result.stdout, step.practice);
    }
  } finally { await rm(directory, { recursive: true, force: true }); }
});

test("local practice worker creates, previews, and removes only its isolated demo entry", async () => {
  const directory = await mkdtemp(resolve("tests/.practice-session-"));
  try {
    const result = spawnSync(process.execPath, [resolve("tools/capture-practice.mjs"), "--session", "web-app"], {
      cwd: directory, encoding: "utf8",
      input: ['{"action":"open"}', '{"action":"create"}', '{"action":"create"}', '{"action":"open"}', '{"action":"remove"}'].join("\n") + "\n",
    });
    assert.equal(result.status, 0, result.stderr);
    const results = result.stdout.trim().split("\n").map(line => JSON.parse(line));
    assert.ok(results[0].error, "Cannot preview a nonexistent entry");
    assert.ok(results[1].path.startsWith(directory));
    assert.ok(results[2].error, "Never overwrite an existing entry");
    assert.equal(results[3].opened, true);
    assert.equal(results[4].removed, true);
    await assert.rejects(readFile(results[1].path), { code: "ENOENT" });
  } finally { await rm(directory, { recursive: true, force: true }); }
});

test("worker rejects cross-mode actions and arbitrary executable requests", async () => {
  const directory = await mkdtemp(resolve("tests/.practice-session-"));
  try {
    for (const mode of Object.keys(sessionActions)) {
      const result = spawnSync(process.execPath, [resolve("tools/capture-practice.mjs"), "--session", mode], {
        cwd: directory, encoding: "utf8", input: '{"action":"exec","command":["false"]}\n',
      });
      assert.equal(result.status, 0, result.stderr);
      assert.match(JSON.parse(result.stdout).error, /not allowed/);
    }
  } finally { await rm(directory, { recursive: true, force: true }); }
});

test("transcode generates playable smaller output and preserves its original", async () => {
  const directory = await mkdtemp(resolve("tests/.practice-media-"));
  try {
    const result = spawnSync(process.execPath, [resolve("tools/capture-practice.mjs"), "--session", "transcode"], {
      cwd: directory, encoding: "utf8",
      input: '{"action":"prepare"}\n{"action":"convert","height":240}\n{"action":"convert","height":"240; false"}\n',
      timeout: 30000,
    });
    assert.equal(result.status, 0, result.stderr);
    const results = result.stdout.trim().split("\n").map(line => JSON.parse(line));
    assert.ok(results[0].bytes > 0, JSON.stringify(results));
    assert.ok(results[1].bytes > 0 && results[1].bytes < results[0].bytes);
    assert.equal((await readFile(results[0].path)).length, results[0].bytes);
    assert.equal(results[1].originalBytes, results[0].bytes);
    assert.match(results[2].error, /supported output resolution/);
    const qmlTest = join(directory, "tst_playback.qml");
    await writeFile(qmlTest, `import QtQuick
import QtTest
import "../../app" as App
Item {
  width: 760
  height: 680
  App.PracticeContent { id: practice; anchors.fill: parent; mode: "screen-recording" }
  TestCase {
    name: "SavedMediaPlayback"
    when: windowShown
    function test_recordingAndTranscodePlayback() {
      practice.observeRecordingSaved(${JSON.stringify(results[0].path)})
      verify(!practice.verified)
      practice.playMedia(practice.artifact)
      tryCompare(practice, "verified", true, 5000)
      practice.mode = "transcode"
      practice.handleTaskResult({ action: "prepare", path: ${JSON.stringify(results[0].path)}, bytes: ${results[0].bytes} })
      practice.playMedia(practice.original)
      tryCompare(practice, "originalPlayed", true, 5000)
      practice.handleTaskResult({ action: "convert", path: ${JSON.stringify(results[1].path)}, bytes: ${results[1].bytes}, originalBytes: ${results[0].bytes} })
      practice.playMedia(practice.artifact)
      tryCompare(practice, "outputPlayed", true, 5000)
      verify(!practice.verified, "Playback alone does not replace comparison")
      var review = findChild(practice, "reviewTranscode")
      verify(review.enabled)
      review.clicked()
      verify(practice.verified)
    }
  }
}
`);
    const ui = spawnSync("/usr/lib/qt6/bin/qmltestrunner", ["-input", qmlTest], {
      encoding: "utf8", timeout: 20000,
      env: { ...process.env, QT_QPA_PLATFORM: "offscreen", QT_QPA_PLATFORMTHEME: "generic", QT_QUICK_CONTROLS_STYLE: "Basic", QML_XHR_ALLOW_FILE_READ: "1" },
    });
    assert.equal(ui.status, 0, ui.stdout + ui.stderr);
  } finally { await rm(directory, { recursive: true, force: true }); }
});

test("QR sample really decodes to harmless text and sharing never sends", async () => {
  const directory = await mkdtemp(resolve("tests/.practice-samples-"));
  try {
    for (const mode of ["qr", "sharing"]) {
      const result = spawnSync(process.execPath, [resolve("tools/capture-practice.mjs"), "--session", mode], {
        cwd: directory, encoding: "utf8", input: '{"action":"prepare"}\n',
      });

      assert.equal(result.status, 0, result.stderr);
      const sample = JSON.parse(result.stdout);
      if (mode === "qr") {
        const decoded = spawnSync("zbarimg", ["--quiet", "--raw", sample.image], { encoding: "utf8" });
        assert.equal(decoded.status, 0);
        assert.equal(decoded.stdout.trim(), "OMARCHY SAFE SAMPLE");
      } else {
        assert.match(await readFile(sample.path, "utf8"), /No private information/);
        assert.equal(sample.delivered, undefined);
      }
    }
  } finally { await rm(directory, { recursive: true, force: true }); }
});

test("screen recording exercise completes through native watcher events and real playback", async () => {
  const directory = await mkdtemp(resolve("tests/.native-recording-exercise-"));
  const marker = join(directory, "active-recording");
  const recording = join(directory, "screenrecording-2026-09-21_23-00-01.mp4");
  const sample = join(directory, "sample.mp4");
  let shell;
  try {
    const generated = spawnSync("ffmpeg", [
      "-nostdin", "-v", "error", "-f", "lavfi", "-i",
      "color=blue:size=320x180:rate=15", "-t", "1.5", "-an", "-c:v", "libx264", sample,
    ], { encoding: "utf8" });
    assert.equal(generated.status, 0, generated.stderr);

    const fixture = join(directory, "shell.qml");
    await writeFile(fixture, `import QtQuick
import Quickshell
import ${JSON.stringify(pathToFileURL(resolve("app")).href)} as App
ShellRoot {
  id: root
  property int phase: 0
  function findObject(item, name) {
    if (!item) return null
    if (item.objectName === name) return item
    for (var index = 0; index < item.children.length; index++) {
      var found = findObject(item.children[index], name)
      if (found) return found
    }
    return null
  }
  App.PracticeSession {
    id: session
    mode: "screen-recording"
    autoStart: false
    width: 960
    height: 720
    onCompleted: {
      if (root.phase !== 4) console.error("NATIVE_RECORDING_FAILURE: completed in phase " + root.phase)
      else console.log("NATIVE_RECORDING_COMPLETE")
      Qt.quit()
    }
    onFailed: function(message) {
      console.error("NATIVE_RECORDING_FAILURE: " + message)
      Qt.quit()
    }
  }
  Timer {
    interval: 25
    running: true
    repeat: true
    onTriggered: {
      if (!session.running) return
      var content = root.findObject(session, "practiceContent")
      if (!content) return
      if (root.phase === 0) {
        root.phase = 1
        console.log("NATIVE_RECORDING_READY")
      } else if (root.phase === 1 && content.recording && content.stage === 1) {
        root.phase = 2
        console.log("NATIVE_RECORDING_STARTED")
      } else if (root.phase === 2 && content.stage === 2) {
        root.findObject(content, "playOutput").clicked()
        root.phase = 3
      } else if (root.phase === 3 && session.verified) {
        root.phase = 4
        root.findObject(content, "finishExercise").clicked()
      }
    }
  }
  Timer {
    interval: 15000
    running: true
    onTriggered: {
      console.error("NATIVE_RECORDING_FAILURE: timed out in phase " + root.phase)
      Qt.quit()
    }
  }
  Component.onCompleted: session.start()
}
`);

    shell = spawn("qs", ["--no-color", "--path", fixture], {
      env: {
        ...process.env,
        LEARN_OMARCHY_ROOT: resolve("."),
        OMARCHY_SCREENRECORD_DIR: directory,
        OMARCHY_SCREENRECORD_MARKER: marker,
        QT_QPA_PLATFORM: "offscreen",
        QT_QUICK_BACKEND: "software",
        QT_QPA_PLATFORMTHEME: "generic",
        QT_QUICK_CONTROLS_STYLE: "Basic",
        XDG_RUNTIME_DIR: directory,
        XDG_CONFIG_HOME: join(directory, "config"),
        XDG_CACHE_HOME: join(directory, "cache"),
        HYPRLAND_INSTANCE_SIGNATURE: "learn-no-compositor",
        WAYLAND_DISPLAY: "",
        DBUS_SESSION_BUS_ADDRESS: `unix:path=${directory}/no-bus`,
      },
      stdio: ["ignore", "pipe", "pipe"],
    });
    let output = "";
    shell.stdout.setEncoding("utf8").on("data", data => { output += data; });
    shell.stderr.setEncoding("utf8").on("data", data => { output += data; });
    const waitForOutput = async (needle: string) => {
      for (let attempt = 0; attempt < 100 && !output.includes(needle); attempt++)
        await new Promise(resolveDelay => setTimeout(resolveDelay, 50));
      assert.match(output, new RegExp(needle));
    };

    await waitForOutput("NATIVE_RECORDING_READY");
    await writeFile(marker, recording);
    await copyFile(sample, recording);
    await waitForOutput("NATIVE_RECORDING_STARTED");
    await rm(marker);
    await once(shell, "exit");
    assert.match(output, /NATIVE_RECORDING_COMPLETE/);
    assert.doesNotMatch(output, /NATIVE_RECORDING_FAILURE|Failed to load configuration|ReferenceError|TypeError/);
  } finally {
    if (shell && shell.exitCode === null && shell.signalCode === null) {
      shell.kill("SIGTERM");
      await once(shell, "exit");
    }
    await rm(directory, { recursive: true, force: true });
  }
});

test("unavailable dictation tools return guidance without starting a microphone", async () => {
  const directory = await mkdtemp(resolve("tests/.practice-missing-"));
  try {
    const result = spawnSync(process.execPath, [resolve("tools/capture-practice.mjs"), "--session", "dictation"], {
      cwd: directory, encoding: "utf8", env: { ...process.env, PATH: directory },
      input: '{"action":"check"}\n', timeout: 5000,
    });

    test("dictation correction inspection never edits or exposes the real config", async () => {
      const directory = await mkdtemp(resolve("tests/.dictation-config-"));
      try {
        const configDirectory = join(directory, ".config", "voxtype");
        await mkdir(configDirectory, { recursive: true });
        const config = join(configDirectory, "config.toml");
        const secret = '# [text]\n# replacements = { "cube control" = "kubectl" }\napi_key = "do-not-display"\n';
        await writeFile(config, secret);
        const result = spawnSync(process.execPath, [resolve("tools/capture-practice.mjs"), "--session", "dictation-corrections"], {
          cwd: directory, encoding: "utf8", env: { ...process.env, HOME: directory }, input: '{"action":"inspect"}\n',
        });
        assert.equal(result.status, 0, result.stderr);
        const response = JSON.parse(result.stdout);
        assert.deepEqual(response, { action: "inspect", source: "config", replacementsDocumented: true });
        assert.equal(await readFile(config, "utf8"), secret);
        assert.doesNotMatch(result.stdout + result.stderr, /api_key|do-not-display|cube control/);
      } finally {
        await rm(directory, { recursive: true, force: true });
      }
    });
    assert.equal(result.status, 0, result.stderr);
    const response = JSON.parse(result.stdout);
    assert.match(response.error, /voxtype is unavailable.*skip/);
    assert.equal(response.available, undefined);
  } finally { await rm(directory, { recursive: true, force: true }); }
});
