import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, readdir, rm, symlink, writeFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import test from "node:test";

const project = fileURLToPath(new URL("../", import.meta.url));

function offscreenShell(source: string, body: string) {
  // Only replace compositor-owned windows and inhibitors, not application state or file I/O.
  source = source
    .replace(/\bPanelWindow \{/g, "TestPanel {")
    .replace(/\b(ShortcutInhibitor|IdleInhibitor) \{/g, "TestInhibitor {")
    .replace(/^\s*anchors \{\s*top: true[;\s]*bottom: true[;\s]*left: true[;\s]*right: true\s*\}/gm, "")
    .replace(/^\s*exclusionMode:.*$/gm, "")
    .replace(/^\s*WlrLayershell\.\w+:.*(?:\n\s*\? WlrKeyboardFocus.*)?$/gm, "");
  return source.slice(0, source.lastIndexOf("}")) + `
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
${body}
}`;
}

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
    const source = await readFile(join(app, "shell.qml"), "utf8");
    const path = join(directory, "shell.qml");
    await writeFile(path, offscreenShell(source, `
  Timer {
    interval: 300
    running: true
    onTriggered: {
      console.log("COMPLETE_SHELL_LOADED")
      Qt.quit()
    }
  }
`));
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

test("Settings reset clears real saved progress and remains cleared after Quickshell restarts", async () => {
  const directory = await mkdtemp(join(tmpdir(), "learn-reset-"));
  try {
    const runtime = join(directory, "runtime");
    const stateDirectory = join(directory, "state", "learn-omarchy");
    await mkdir(runtime, { mode: 0o700 });
    await mkdir(stateDirectory, { recursive: true });
    const app = join(project, "app");
    for (const name of await readdir(app)) {
      if (name !== "shell.qml") await symlink(join(app, name), join(directory, name));
    }
    const course = JSON.parse(await readFile(join(project, "courses/omarchy-basics.json"), "utf8"));
    const completed = ["welcome", "omarchy-tour", "workspaces"];
    const steps = Object.fromEntries(course.lessons
      .filter((lesson: { id: string }) => completed.includes(lesson.id))
      .flatMap((lesson: { steps: Array<{ id: string }> }) => lesson.steps.map(step => [step.id, "introduced"])));
    const progressPath = join(stateDirectory, "progress.json");
    const settingsPath = join(stateDirectory, "settings.json");
    await writeFile(progressPath, JSON.stringify({
      schemaVersion: 2, courses: { [course.id]: completed },
      details: { [course.id]: { steps, credits: Object.fromEntries(Object.keys(steps).map(id => [id, true])),
        bookmarks: { workspaces: "workspaces-home" } } },
    }));
    await writeFile(settingsPath, JSON.stringify({
      character: "ohm-1", welcomeSeen: true, tourSeen: true, audioEnabled: false, motionReduced: true,
    }));
    const initialProgress = await readFile(progressPath);
    const initialSettings = await readFile(settingsPath);
    const source = await readFile(join(app, "shell.qml"), "utf8");
    const path = join(directory, "shell.qml");
    const env = {
      ...process.env, QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software",
      QT_QPA_PLATFORMTHEME: "generic", QT_QUICK_CONTROLS_STYLE: "Basic",
      XDG_RUNTIME_DIR: runtime, HOME: directory,
      XDG_CONFIG_HOME: join(directory, "config"), XDG_CACHE_HOME: join(directory, "cache"),
      XDG_STATE_HOME: join(directory, "state"), XDG_DATA_HOME: join(directory, "data"),
      LEARN_OMARCHY_ROOT: project, LEARN_OMARCHY_COURSE: join(project, "courses/omarchy-basics.json"),
      LEARN_OMARCHY_COURSE_DIR: join(project, "courses"), LEARN_OMARCHY_CHARACTER: "",
      LEARN_OMARCHY_REDUCED_MOTION: "1",
      DBUS_SESSION_BUS_ADDRESS: `unix:path=${directory}/no-bus`,
    };
    delete env.WAYLAND_DISPLAY;
    delete env.DISPLAY;
    delete env.HYPRLAND_INSTANCE_SIGNATURE;
    for (const mode of ["reset", "restart", "failure-progress", "failure-settings"]) {
      const reset = mode !== "restart";
      const failure = mode.startsWith("failure-") ? mode.slice("failure-".length) : "";
      if (failure) {
        await writeFile(progressPath, initialProgress);
        await writeFile(settingsPath, initialSettings);
      }
      await writeFile(path, offscreenShell(source, `
  property int testStage: 0
  Timer {
    interval: 200
    running: true
    repeat: true
    onTriggered: {
      if (!root.course || !root.settingsResolved || !root.progressResolved || !characterStore.ready) return
      if (root.testStage === 0) {
        console.log("BEFORE_RESET", JSON.stringify(root.completedLessons))
        ${failure ? `${failure}File.path = ${JSON.stringify(stateDirectory)}` : ""}
        ${reset ? `root.openSettings("settings")
        root.requestResetProgress()
        root.requestResetProgress()` : ""}
        console.log("RESET_RETURN", JSON.stringify({
          resetJustDone: root.resetJustDone, progressError: root.progressSaveError, settingsError: root.settingsSaveError
        }))
        ${failure ? `root.requestResetProgress()
        root.requestResetProgress()
        console.log("RETRY_RETURN", JSON.stringify({
          resetJustDone: root.resetJustDone, progressError: root.progressSaveError, settingsError: root.settingsSaveError
        }))
        ${failure}File.path = root.${failure}Path
        root.requestResetProgress()
        root.requestResetProgress()
        console.log("RECOVER_RETURN", JSON.stringify({
          resetJustDone: root.resetJustDone, progressError: root.progressSaveError, settingsError: root.settingsSaveError
        }))` : ""}
        root.testStage++
      } else {
        console.log("AFTER_RESET", JSON.stringify({
          completed: root.completedLessons, steps: root.stepResults, credits: root.stepCredits,
          bookmarks: root.lessonBookmarks, welcomeSeen: root.welcomeSeen, savedCharacter: root.savedCharacter
        }))
        Qt.quit()
      }
    }
  }
`));
      const result = spawnSync("qs", ["--no-color", "--path", path], { env, encoding: "utf8", timeout: 15000 });
      const output = result.stdout + result.stderr;
      assert.equal(result.error, undefined, output + String(result.error));
      assert.equal(result.status, 0, output);
      assert.doesNotMatch(output, /ReferenceError|TypeError|Cannot assign|is not a type|Binding loop|Failed to load configuration/);
      const after = output.match(/AFTER_RESET (\{[^\n]+\})/);
      assert.ok(after, output);
      const returned = output.match(/RESET_RETURN (\{[^\n]+\})/);
      assert.ok(returned, output);
      const confirmation = JSON.parse(returned[1]);
      assert.equal(confirmation.resetJustDone, reset && !failure, output);
      if (failure) {
        assert.match(confirmation[failure + "Error"], /could not be saved/, output);
        const retry = output.match(/RETRY_RETURN (\{[^\n]+\})/);
        assert.ok(retry, output);
        assert.equal(JSON.parse(retry[1]).resetJustDone, false, output);
        const recovered = output.match(/RECOVER_RETURN (\{[^\n]+\})/);
        assert.ok(recovered, output);
        assert.deepEqual(JSON.parse(recovered[1]), { resetJustDone: true, progressError: "", settingsError: "" }, output);
      }
      const state = JSON.parse(after[1]);
      for (const id of completed) assert.notEqual(state.completed[id], true, output);
      assert.deepEqual(state.steps, {}, output);
      assert.deepEqual(state.credits, {}, output);
      assert.deepEqual(state.bookmarks, {}, output);
      assert.equal(state.welcomeSeen, false, output);
      assert.equal(state.savedCharacter, "", output);
      const progress = JSON.parse(await readFile(progressPath, "utf8"));
      assert.deepEqual(progress.courses[course.id], [], "the reset must reach the real file, not only memory");
      assert.deepEqual(progress.details[course.id], { steps: {}, credits: {}, bookmarks: {} });
      assert.equal(JSON.parse(await readFile(settingsPath, "utf8")).welcomeSeen, false);
    }
    for (const mode of ["start-and-skip", "restart"]) {
      await writeFile(path, offscreenShell(source, `
  property int testStage: 0
  Timer {
    interval: 200
    running: true
    repeat: true
    onTriggered: {
      if (!root.course || !root.settingsResolved || !root.progressResolved || !characterStore.ready) return
      if (root.testStage === 0) {
        root.finishSplash()
        ${mode === "start-and-skip" ? `root.openSettings("first-run")
        root.chooseCharacter("ohm-1")
        console.log("WELCOME_STARTED", JSON.stringify({
          phase: root.phase, completed: root.lessonCompleted(root.course.lessons[0]), seen: root.welcomeSeen
        }))
        root.finishWelcome()` : ""}
        root.testStage++
      } else {
        console.log("WELCOME_AFTER_RESET", JSON.stringify({
          completed: root.lessonCompleted(root.course.lessons[0]),
          tourCompleted: root.lessonCompleted(root.course.lessons[1]), seen: root.welcomeSeen
        }))
        Qt.quit()
      }
    }
  }
`));
      const result = spawnSync("qs", ["--no-color", "--path", path], { env, encoding: "utf8", timeout: 15000 });
      const output = result.stdout + result.stderr;
      assert.equal(result.error, undefined, output + String(result.error));
      assert.equal(result.status, 0, output);
      assert.doesNotMatch(output, /ReferenceError|TypeError|Cannot assign|is not a type|Binding loop|Failed to load configuration/);
      if (mode === "start-and-skip") {
        const started = output.match(/WELCOME_STARTED (\{[^\n]+\})/);
        assert.ok(started, output);
        assert.deepEqual(JSON.parse(started[1]), { phase: "welcome", completed: false, seen: true });
      }
      const after = output.match(/WELCOME_AFTER_RESET (\{[^\n]+\})/);
      assert.ok(after, output);
      assert.deepEqual(JSON.parse(after[1]), { completed: false, tourCompleted: false, seen: true });
      assert.deepEqual(JSON.parse(await readFile(progressPath, "utf8")).courses[course.id], []);
    }
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
