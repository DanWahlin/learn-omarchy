import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

test("welcome and lesson wrap-up processes load with the real Quickshell types", async () => {
  const source = await readFile(new URL("../app/shell.qml", import.meta.url), "utf8");
  const start = source.indexOf("  Process {\n    id: welcomeSpeech");
  const end = source.indexOf("  Process {\n    id: audioProcess", start);
  assert.ok(start >= 0 && end > start);
  const directory = await mkdtemp(join(tmpdir(), "learn-audio-processes-"));
  try {
    const runtime = join(directory, "runtime");
    await mkdir(runtime, { mode: 0o700 });
    const path = join(directory, "shell.qml");
    await writeFile(path, `import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
  id: root
  function welcomeSpeechExited(code, generation) {}
  function receiveWelcomePlayback(raw, generation, stage) {}
  function lessonWrapupExited(code, generation) {}
${source.slice(start, end)}
  Component.onCompleted: Qt.callLater(function() {
    console.log("AUDIO_PROCESSES_LOADED");
    Qt.quit();
  })
}`);
    const env = { ...process.env, QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software",
      QT_QPA_PLATFORMTHEME: "generic", XDG_RUNTIME_DIR: runtime,
      XDG_CONFIG_HOME: join(directory, "config"), XDG_CACHE_HOME: join(directory, "cache"),
      DBUS_SESSION_BUS_ADDRESS: `unix:path=${directory}/no-bus` };
    delete env.WAYLAND_DISPLAY;
    delete env.DISPLAY;
    const result = spawnSync("qs", ["--no-color", "--path", path], { env, encoding: "utf8", timeout: 10000 });
    assert.equal(result.error, undefined, String(result.error));
    assert.equal(result.status, 0, result.stdout + result.stderr);
    assert.match(result.stdout + result.stderr, /AUDIO_PROCESSES_LOADED/);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
