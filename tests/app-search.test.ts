import assert from "node:assert/strict";
import { readFile, mkdtemp, writeFile, chmod, rm } from "node:fs/promises";
import { createContext, runInContext } from "node:vm";
import { spawnSync } from "node:child_process";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import test from "node:test";

const source = await readFile(new URL("../app/AppSearchSession.qml", import.meta.url), "utf8");
function session() {
  let completed = 0;
  const errors: string[] = [];
  const state = createContext({ active: false, ready: false, menuSeen: false, initialWindows: [], baselinePending: false,
    terminalAddress: "", baselineProcess: { running: false }, completed() { completed++; },
    failed(message: string) { errors.push(message); } });
  runInContext(Array.from(source.matchAll(/^  function \w+\([^\n]*\) \{[\s\S]*?^  \}/gm),
    match => match[0]).join("\n"), state);
  return { state, errors, completed: () => completed };
}

test("inline app search observes native task completion without controlling any windows", () => {
  const { state, completed } = session();
  state.start();
  state.acceptBaseline(0, JSON.stringify([{ address: "0xaaa" }]));
  const event = (name: string, data: string) => state.observe({ name, data });
  event("openwindow", "bbb,1,com.mitchellh.ghostty,Terminal");
  assert.equal(state.terminalAddress, "", "opening a terminal before the menu doesn't complete search");
  event("openlayer", "omarchy-menu");
  event("openwindow", "aaa,1,com.mitchellh.ghostty,Terminal");
  assert.equal(state.terminalAddress, "", "existing windows cannot count");
  event("openwindow", "bbb,1,browser,Web");
  assert.equal(state.terminalAddress, "");
  event("openwindow", "ccc,1,com.mitchellh.ghostty,Terminal");
  assert.equal(state.terminalAddress, "0xccc");
  event("closewindow", "aaa");
  assert.equal(completed(), 0);
  event("closewindow", "ccc");
  assert.equal(completed(), 1);
  event("closewindow", "ccc");
  assert.equal(completed(), 1);
  assert.doesNotMatch(source, /execDetached|hl\.dispatch|dsp\.window\.close|FloatingWindow|PanelWindow/);
});

test("invalid baseline and events cannot silently finish the inline exercise", () => {
  for (const [code, text] of [[1, "[]"], [0, "{}"], [0, "bad"], [0, '[{"address":"not-a-window"}]']] as const) {
    const { state, errors, completed } = session();
    state.start();
    state.acceptBaseline(code, text);
    assert.equal(state.ready, false);
    assert.equal(state.active, false);
    assert.equal(errors.length, 1);
    assert.equal(completed(), 0);
  }
  const { state } = session();
  state.start();
  state.active = false;
  state.acceptBaseline(0, "[]");
  assert.equal(state.ready, false);
});

test("app-search launcher selects a nonvisual observer instead of the exercise window", async () => {
  const directory = await mkdtemp(resolve("tests/.learn-search-launch-"));
  try {
    const qs = join(directory, "qs");
    await writeFile(qs, '#!/bin/sh\nprintf "%s\\n" "$@"\n');
    await chmod(qs, 0o700);
    const result = spawnSync("bash", ["bin/learn-omarchy-practice", "app-search"], {
      encoding: "utf8", env: { ...process.env, PATH: directory + ":" + process.env.PATH },
    });

    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /\/app\/app-search\.qml/);
    assert.doesNotMatch(result.stdout, /\/app\/practice\.qml/);
    const entry = await readFile(new URL("../app/app-search.qml", import.meta.url), "utf8");
    assert.doesNotMatch(entry, /FloatingWindow|PanelWindow|PracticeContent|QtMultimedia/);
    assert.match(entry, /LEARN_PRACTICE_RESULT/);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("the nonvisual session loads with actual Quickshell types and completes without creating a window", async () => {
  const directory = await mkdtemp(resolve("tests/.learn-search-qml-"));
  try {
    const fixture = join(directory, "shell.qml");
    await writeFile(fixture, `import QtQuick
import Quickshell
import ${JSON.stringify(pathToFileURL(resolve("app")).href)} as App
ShellRoot {
  App.AppSearchSession {
    id: session
    onCompleted: { console.log("NONVISUAL_SEARCH_COMPLETE"); Qt.quit(); }
  }
  Component.onCompleted: Qt.callLater(function() {
    session.active = true;
    session.acceptBaseline(0, "[]");
    session.observe({name:"openlayer", data:"omarchy-menu"});
    session.observe({name:"openwindow", data:"abc,1,ghostty,Terminal"});
    session.observe({name:"closewindow", data:"abc"});
  })
}`);
    const result = spawnSync("qs", ["--no-color", "--path", fixture], {
      encoding: "utf8", timeout: 10000,
      env: { ...process.env, QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software",
        QT_QPA_PLATFORMTHEME: "generic", XDG_RUNTIME_DIR: directory,
        XDG_CONFIG_HOME: join(directory, "config"), XDG_CACHE_HOME: join(directory, "cache"),
        HYPRLAND_INSTANCE_SIGNATURE: "learn-search-no-compositor", WAYLAND_DISPLAY: "",
        DBUS_SESSION_BUS_ADDRESS: `unix:path=${directory}/no-bus` },
    });

    assert.equal(result.status, 0, result.stdout + result.stderr);
    assert.match(result.stdout + result.stderr, /NONVISUAL_SEARCH_COMPLETE/);
    assert.doesNotMatch(result.stdout + result.stderr, /Failed to load configuration|PanelWindow backend/);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("the actual app-search entrypoint imports QtQuick and starts its observer", async () => {
  const directory = await mkdtemp(resolve("tests/.learn-search-entry-"));
  try {
    await writeFile(join(directory, "hyprctl"), "#!/bin/sh\nexit 1\n", { mode: 0o700 });
    const result = spawnSync("qs", ["--no-color", "--path", resolve("app/app-search.qml")], {
      encoding: "utf8", timeout: 10000,
      env: { ...process.env, PATH: directory + ":" + process.env.PATH,
        QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software",
        QT_QPA_PLATFORMTHEME: "generic", XDG_RUNTIME_DIR: directory,
        XDG_CONFIG_HOME: join(directory, "config"), XDG_CACHE_HOME: join(directory, "cache"),
        HYPRLAND_INSTANCE_SIGNATURE: "learn-search-no-compositor", WAYLAND_DISPLAY: "",
        DBUS_SESSION_BUS_ADDRESS: `unix:path=${directory}/no-bus` },
    });
    const output = result.stdout + result.stderr;
    assert.equal(result.status, 0, output);
    assert.match(output, /learn-omarchy app search:.*Couldn't inspect the desktop window list/);
    assert.doesNotMatch(output, /Failed to load configuration|Component is not a type|Non-existent attached object|PanelWindow backend/);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
