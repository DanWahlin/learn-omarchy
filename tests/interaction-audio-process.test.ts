import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

test("interaction process preemption waits for exit, mute stops playback, and failures are explicit", async () => {
  const project = fileURLToPath(new URL("../", import.meta.url));
  const directory = await mkdtemp(join(project, ".interaction-audio-test-"));
  try {
    const runtime = join(directory, "runtime");
    const bin = join(directory, "bin");
    await mkdir(runtime, { mode: 0o700 });
    await mkdir(bin);
    const log = join(directory, "player.jsonl");
    // Exercise real Quickshell process lifecycle, never a live audio device.
    await writeFile(join(bin, "mpv"), `#!${process.execPath}
import { appendFileSync } from "node:fs";
const args = process.argv.slice(2);
const record = (type) => appendFileSync(process.env.INTERACTION_TEST_LOG, JSON.stringify({ type, args }) + "\\n");
record("start");
if (args.at(-1).endsWith("interaction-wrong.wav"))
  setTimeout(() => { record("exit"); process.exit(7); }, 80);
process.on("SIGTERM", () => setTimeout(() => { record("exit"); process.exit(0); }, 60));
setTimeout(() => { record("exit"); process.exit(0); }, 2000);
`, { mode: 0o755 });
    const path = join(directory, "shell.qml");
    await writeFile(path, `import QtQuick
import Quickshell
import "${new URL("../app/", import.meta.url).href}"
ShellRoot {
  InteractionAudio {
    id: audio
    appRoot: ${JSON.stringify(project)}
    coalesceMs: 10
    volume: 32
    onCueStarted: console.log("CUE", kind)
    onPlaybackFailed: function(kind, message) { console.log("CUE_FAILURE", kind, message) }
  }
  Timer { interval: 10; running: true; onTriggered: audio.notify("correct") }
  Timer { interval: 180; running: true; onTriggered: audio.notify("module-complete") }
  Timer { interval: 450; running: true; onTriggered: audio.enabled = false }
  Timer { interval: 650; running: true; onTriggered: {
    console.log("AUDIO_IDLE", !audio.busy)
    audio.enabled = true
    audio.play("wrong")
  } }
  Timer { interval: 950; running: true; onTriggered: {
    console.log("FAILURE_RECOVERED", !audio.busy && audio.lastError.indexOf("7") >= 0)
    Qt.quit()
  } }
}`);
    const env = { ...process.env, QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software",
      QT_QPA_PLATFORMTHEME: "generic", XDG_RUNTIME_DIR: runtime,
      XDG_CONFIG_HOME: join(directory, "config"), XDG_CACHE_HOME: join(directory, "cache"),
      DBUS_SESSION_BUS_ADDRESS: `unix:path=${directory}/no-bus`,
      PATH: `${bin}:${process.env.PATH}`, INTERACTION_TEST_LOG: log };
    delete env.WAYLAND_DISPLAY;
    delete env.DISPLAY;
    const result = spawnSync("qs", ["--no-color", "--path", path], { env, encoding: "utf8", timeout: 10000 });
    assert.equal(result.error, undefined, String(result.error));
    assert.equal(result.status, 0, result.stdout + result.stderr);
    assert.match(result.stdout + result.stderr, /AUDIO_IDLE true/);
    assert.match(result.stdout + result.stderr, /CUE_FAILURE wrong Player exited unsuccessfully \(7\)/);
    assert.match(result.stdout + result.stderr, /FAILURE_RECOVERED true/);
    const contents = await readFile(log, "utf8").catch(error => {
      throw new Error(`${error}\n${result.stdout}\n${result.stderr}`);
    });
    const events = contents.trim().split("\n").map(line => JSON.parse(line));
    assert.deepEqual(events.map(event => event.type), ["start", "exit", "start", "exit", "start", "exit"]);
    assert.match(events[0].args.at(-1), /interaction-correct\.wav$/);
    assert.match(events[2].args.at(-1), /interaction-module-complete\.wav$/);
    assert.ok(events[0].args.includes("--volume=32"));
    assert.ok(events[0].args.includes("--no-config"));
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
