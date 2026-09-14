import assert from "node:assert/strict";
import { copyFile, mkdtemp, mkdir, open, readFile, readdir, rename, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
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

test("an open theme loader follows colors and wallpaper replacements", { timeout: 20000 }, async () => {
  const directory = await mkdtemp(join(tmpdir(), "learn-theme-"));
  let child: ReturnType<typeof spawn> | undefined;
  let closed: Promise<void> | undefined;
  let log = "";
  try {
    const themeDirectory = join(directory, "theme");
    const colors = join(themeDirectory, "colors.toml");
    const name = join(directory, "theme.name");
    const runtime = join(directory, "runtime");
    const imageDirectory = join(directory, "images");
    const background = join(directory, "background #current");
    const firstImage = join(imageDirectory, "first.png");
    const secondImage = join(imageDirectory, "second.png");
    await mkdir(themeDirectory);
    await mkdir(imageDirectory);
    await mkdir(runtime, { mode: 0o700 });
    await writeFile(colors, 'background = "#111111"\nforeground = "#eeeeee"\naccent = "#7799ff"\n');
    await writeFile(name, "dark");
    await copyFile(resolve("share/icons/hicolor/256x256/apps/learn-omarchy.png"), firstImage);
    await copyFile(resolve("assets/splash/learn-omarchy-poster.png"), secondImage);
    const firstWidth = (await readFile(firstImage)).readUInt32BE(16);
    const secondWidth = (await readFile(secondImage)).readUInt32BE(16);
    assert.notEqual(firstWidth, secondWidth);
    await symlink(firstImage, background);
    const fixture = join(directory, "shell.qml");
    await writeFile(fixture, `import QtQuick
import Quickshell
import Quickshell.Io
import ${JSON.stringify(pathToFileURL(resolve("app")).href)} as App
ShellRoot {
  App.OmarchyTheme {
    id: theme
    themeDirectory: ${JSON.stringify(themeDirectory)}
    themeNamePath: ${JSON.stringify(name)}
    wallpaperEnabled: true
    wallpaperPath: ${JSON.stringify(background)}
  }
  Window {
    width: 320; height: 240; visible: true
    Image {
      id: wallpaper
      anchors.fill: parent
      source: theme.wallpaperSource
      cache: false
    }
  }
  IpcHandler {
    target: "themeTest"
    function status(): string {
      return JSON.stringify({colors:theme.colors, diagnostic:theme.diagnostic,
        wallpaperSource:theme.wallpaperSource.toString(),
        wallpaperReady:wallpaper.status === Image.Ready, wallpaperWidth:wallpaper.sourceSize.width})
    }
    function disableWallpaper(): string { theme.wallpaperEnabled = false; return theme.wallpaperSource.toString() }
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
      let lastState: unknown;
      for (let attempt = 0; attempt < 60; attempt++) {
        const reply = spawnSync("qs", ["ipc", "--pid", String(child!.pid), "call", "themeTest", "status"],
          { env, encoding: "utf8", timeout: 500 });
        if (reply.status === 0) {
          const state = JSON.parse(reply.stdout);
          lastState = state;
          if (field === "wallpaper" ? state.wallpaperReady && state.wallpaperWidth === Number(expected)
            : field === "diagnostic" ? state.diagnostic !== "" : state.colors[field] === expected) return state;
        }
        assert.equal(child!.exitCode, null, log);
        await delay(40);
      }
      assert.fail(`Theme update timed out (${field}=${expected}): ${JSON.stringify(lastState)}\n${log}`);
    }
    await waitFor("#111111");
    const firstWallpaper = await waitFor(String(firstWidth), "wallpaper");
    assert.equal(fileURLToPath(firstWallpaper.wallpaperSource), background);
    await symlink(secondImage, background + ".next");
    await rename(background + ".next", background);
    const nextWallpaper = await waitFor(String(secondWidth), "wallpaper");
    assert.notEqual(firstWallpaper.wallpaperSource, nextWallpaper.wallpaperSource);
    await copyFile(firstImage, secondImage);
    const rewrittenWallpaper = await waitFor(String(firstWidth), "wallpaper");
    assert.notEqual(nextWallpaper.wallpaperSource, rewrittenWallpaper.wallpaperSource);
    const replacement = await open(colors, "w");
    try {
      await delay(100);
      await replacement.write('background = "#ffffff"\nforeground = "#333333"\naccent = "#a84466"\n');
    } finally { await replacement.close(); }
    const light = await waitFor("#ffffff");
    assert.equal(light.colors.accent, "#a84466");
    await writeFile(colors, "invalid theme");
    await waitFor("", "diagnostic");
    await writeFile(colors, 'background = "#222222"\nforeground = "#eeeeee"\n');
    assert.equal((await waitFor("#222222")).diagnostic, "");
    const disabled = spawnSync("qs", ["ipc", "--pid", String(child.pid), "call", "themeTest", "disableWallpaper"],
      { env, encoding: "utf8", timeout: 1000 });
    assert.equal(disabled.status, 0, disabled.stderr);
    assert.equal(disabled.stdout.trim(), "");
  } finally {
    if (child && child.exitCode === null) child.kill("SIGKILL");
    if (closed) await closed;
    await rm(directory, { recursive: true, force: true });
  }
});
