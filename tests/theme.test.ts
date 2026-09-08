import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { spawn, spawnSync } from "node:child_process";
import { setTimeout as delay } from "node:timers/promises";
import test from "node:test";

test("every reusable app component is registered for Quickshell launch", async () => {
  const registry = await readFile(resolve("app/qmldir"), "utf8");
  const registrations = new Map(registry.split("\n")
    .map(line => line.trim().split(/\s+/))
    .filter(parts => parts.length === 3)
    .map(([name, , file]) => [name, file]));
  for (const file of await readdir(resolve("app"))) {
    if (!/^[A-Z].*\.qml$/.test(file)) continue;
    assert.equal(registrations.get(file.slice(0, -4)), file,
      `${file} must be registered in app/qmldir so the real launcher can resolve it`);
  }
});

test("an open theme loader follows file changes and recovers from malformed input", { timeout: 20000 }, async () => {
  const directory = await mkdtemp(join(tmpdir(), "learn-theme-"));
  let child: ReturnType<typeof spawn> | undefined;
  let closed: Promise<void> | undefined;
  let log = "";
  try {
    const themeDirectory = join(directory, "theme");
    const colors = join(themeDirectory, "colors.toml");
    const name = join(directory, "theme.name");
    const runtime = join(directory, "runtime");
    await mkdir(themeDirectory);
    await mkdir(runtime, { mode: 0o700 });
    await writeFile(colors, 'background = "#111111"\nforeground = "#eeeeee"\naccent = "#7799ff"\n');
    await writeFile(name, "dark");
    const fixture = join(directory, "shell.qml");
    await writeFile(fixture, `import Quickshell
import Quickshell.Io
import ${JSON.stringify(pathToFileURL(resolve("app")).href)} as App
ShellRoot {
  App.OmarchyTheme {
    id: theme
    themeDirectory: ${JSON.stringify(themeDirectory)}
    themeNamePath: ${JSON.stringify(name)}
  }
  IpcHandler {
    target: "themeTest"
    function status(): string { return JSON.stringify({colors:theme.colors,diagnostic:theme.diagnostic}) }
  }
}`);
    const env = { ...process.env, QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software",
      QT_QPA_PLATFORMTHEME: "generic", XDG_RUNTIME_DIR: runtime,
      XDG_CONFIG_HOME: join(directory, "config"), XDG_CACHE_HOME: join(directory, "cache"),
      DBUS_SESSION_BUS_ADDRESS: `unix:path=${directory}/no-bus` };
    delete env.WAYLAND_DISPLAY;
    delete env.DISPLAY;
    child = spawn("qs", ["--no-color", "--path", fixture], { env, stdio: ["ignore", "pipe", "pipe"] });
    child.stdout!.on("data", data => { log += data; });
    child.stderr!.on("data", data => { log += data; });
    closed = new Promise(resolveClose => child!.once("close", () => resolveClose()));
    async function waitFor(expected: string, field = "background") {
      for (let attempt = 0; attempt < 60; attempt++) {
        const reply = spawnSync("qs", ["ipc", "--pid", String(child!.pid), "call", "themeTest", "status"],
          { env, encoding: "utf8", timeout: 500 });
        if (reply.status === 0) {
          const state = JSON.parse(reply.stdout);
          if (field === "diagnostic" ? state.diagnostic !== "" : state.colors[field] === expected) return state;
        }
        assert.equal(child!.exitCode, null, log);
        await delay(40);
      }
      assert.fail(`Theme update timed out: ${log}`);
    }
    await waitFor("#111111");
    await writeFile(colors, 'background = "#ffffff"\nforeground = "#333333"\naccent = "#a84466"\n');
    const light = await waitFor("#ffffff");
    assert.equal(light.colors.accent, "#a84466");
    await writeFile(colors, "invalid theme");
    await waitFor("", "diagnostic");
    await writeFile(colors, 'background = "#222222"\nforeground = "#eeeeee"\n');
    assert.equal((await waitFor("#222222")).diagnostic, "");
  } finally {
    if (child && child.exitCode === null) child.kill("SIGKILL");
    if (closed) await closed;
    await rm(directory, { recursive: true, force: true });
  }
});
