import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, readdir, rm, symlink, writeFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const project = fileURLToPath(new URL("../", import.meta.url));

test("all narration processes load with real Quickshell types and the reusable caption component", async () => {
  const source = await readFile(new URL("../app/shell.qml", import.meta.url), "utf8");
  const start = source.indexOf("  Process {\n    id: welcomeSpeech");
  const end = source.indexOf("  Process {", source.indexOf("    id: audioProcess", start));
  assert.ok(start >= 0 && end > start);
  const directory = await mkdtemp(join(project, ".audio-processes-"));
  try {
    const runtime = join(directory, "runtime");
    await mkdir(runtime, { mode: 0o700 });
    const path = join(directory, "shell.qml");
    await writeFile(path, `import QtQuick
import Quickshell
import Quickshell.Io
import "${new URL("../app/", import.meta.url).href}"
ShellRoot {
  id: root
  property string audioProcessPath: ""
  property bool audioPaused: false
  CaptionReveal { id: lessonReveal }
  CaptionReveal { id: wrapupReveal }
  function welcomeSpeechExited(code, generation) {}
  function receiveWelcomePlayback(raw, generation, stage) {}
  function lessonWrapupExited(code, generation) {}
  function receiveLessonPlayback(raw, generation, stepId, stage) {}
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

test("the complete shell instantiates offscreen with isolated state and no desktop connection", async () => {
  const directory = await mkdtemp(join(project, ".shell-startup-"));
  try {
    const runtime = join(directory, "runtime");
    await mkdir(runtime, { mode: 0o700 });
    const app = join(project, "app");
    for (const name of await readdir(app)) {
      if (name !== "shell.qml") await symlink(join(app, name), join(directory, name));
    }
    // Layer-shell windows require a compositor backend. Substitute only that
    // boundary; instantiate all production bindings, views and speech state.
    const source = (await readFile(join(app, "shell.qml"), "utf8"))
      .replace(/\bPanelWindow \{/g, "TestPanel {")
      .replace(/\b(ShortcutInhibitor|IdleInhibitor) \{/g, "TestInhibitor {")
      .replace(/^\s*anchors \{\s*top: true[;\s]*bottom: true[;\s]*left: true[;\s]*right: true\s*\}/gm, "")
      .replace(/^\s*exclusionMode:.*$/gm, "")
      .replace(/^\s*WlrLayershell\.\w+:.*(?:\n\s*\? WlrKeyboardFocus.*)?$/gm, "");
    const path = join(directory, "shell.qml");
    await writeFile(path, source.slice(0, source.lastIndexOf("}")) + `
  component TestPanel: Item {
    property var screen
    property color color
    property var mask
    property Item contentItem: this
    width: 1200
    height: 800
  }
  component TestInhibitor: QtObject {
    property var window
    property bool enabled: false
    property bool active: false
    signal cancelled()
  }
  Timer {
    interval: 300
    running: true
    onTriggered: {
      console.log("COMPLETE_SHELL_LOADED")
      Qt.quit()
    }
  }
}`);
    const env = {
      ...process.env, QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software",
      QT_QPA_PLATFORMTHEME: "generic", QT_QUICK_CONTROLS_STYLE: "Basic",
      XDG_RUNTIME_DIR: runtime, HOME: directory,
      XDG_CONFIG_HOME: join(directory, "config"), XDG_CACHE_HOME: join(directory, "cache"),
      XDG_STATE_HOME: join(directory, "state"), XDG_DATA_HOME: join(directory, "data"),
      LEARN_OMARCHY_ROOT: directory, LEARN_OMARCHY_COURSE: join(directory, "absent-course.json"),
      LEARN_OMARCHY_COURSE_DIR: directory, LEARN_OMARCHY_CHARACTER: "",
      DBUS_SESSION_BUS_ADDRESS: `unix:path=${directory}/no-bus`,
    };
    delete env.WAYLAND_DISPLAY;
    delete env.DISPLAY;
    delete env.HYPRLAND_INSTANCE_SIGNATURE;
    const result = spawnSync("qs", ["--no-color", "--path", path], { env, encoding: "utf8", timeout: 10000 });
    const output = result.stdout + result.stderr;
    assert.equal(result.error, undefined, String(result.error));
    assert.equal(result.status, 0, output);
    assert.match(output, /COMPLETE_SHELL_LOADED/);
    assert.doesNotMatch(output, /ReferenceError|TypeError|Cannot assign|is not a type|Binding loop|Failed to load configuration/);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
