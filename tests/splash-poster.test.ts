import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { copyFile, mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { decodePoster, poster, preparePoster, recolorPoster } from "../tools/prepare-splash-poster.mjs";

const assets = new URL("../assets/splash/", import.meta.url);

test("the shell's poster URL loads through real Quickshell outside its configuration directory", async () => {
  const shell = readFileSync(new URL("../app/shell.qml", import.meta.url), "utf8");
  const source = shell.match(/        SplashScreen \{[\s\S]*?\n          source: ([^\n]+)/)?.[1];
  assert.ok(source, "the shell must explicitly provide the poster's filesystem URL");
  const directory = await mkdtemp(fileURLToPath(new URL("../.sp-", import.meta.url)));
  try {
    const appRoot = join(directory, "asset root #1");
    const config = join(directory, "config");
    const runtime = join(directory, "runtime");
    await mkdir(join(appRoot, "assets/splash"), { recursive: true });
    await mkdir(config);
    await mkdir(join(config, "components"));
    for (const name of ["SplashScreen", "SplashArtwork"])
      await copyFile(new URL(`../app/${name}.qml`, import.meta.url), join(config, "components", `${name}.qml`));
    await writeFile(join(config, "components/qmldir"),
      "SplashScreen 1.0 SplashScreen.qml\nSplashArtwork 1.0 SplashArtwork.qml\n");
    await mkdir(runtime, { mode: 0o700 });
    await copyFile(new URL(poster.output, assets), join(appRoot, "assets/splash", poster.output));
    const path = join(config, "shell.qml");
    await writeFile(path, `import QtQuick
import Quickshell
import "components"
ShellRoot {
  id: root
  property string appRoot: ${JSON.stringify(appRoot)}
  Window {
    width: 1200; height: 800; visible: true
    SplashScreen {
      id: splash
      anchors.fill: parent
      source: ${source}
      active: true
      ready: false
      onImageFailed: console.error("POSTER_LOAD_FAILED")
    }
  }
  Timer {
    interval: 50; running: true; repeat: true
    property int attempts: 0
    onTriggered: {
      for (var child of splash.children) {
        if (child.objectName === "splashArtwork" && child.artworkReady &&
            child.sourceSize.width === 1536 && child.sourceSize.height === 1024) {
          console.log("POSTER_LOADED", splash.source)
          Qt.quit()
          return
        }
      }
      if (++attempts >= 50) { console.error("POSTER_LOAD_TIMEOUT"); Qt.quit() }
    }
  }
}`);
    const env = { ...process.env, QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software",
      QT_QPA_PLATFORMTHEME: "generic", XDG_RUNTIME_DIR: runtime,
      XDG_CONFIG_HOME: config, XDG_CACHE_HOME: join(directory, "cache"),
      DBUS_SESSION_BUS_ADDRESS: `unix:path=${directory}/no-bus` };
    delete env.WAYLAND_DISPLAY;
    delete env.DISPLAY;
    const result = spawnSync("qs", ["--no-color", "--path", path],
      { env, encoding: "utf8", timeout: 10000 });
    assert.equal(result.error, undefined, String(result.error));
    const log = result.stdout + result.stderr;
    assert.equal(result.status, 0, log);
    const loadedUrl = log.match(/POSTER_LOADED (file:\/\/[^\n]+)/)?.[1];
    assert.ok(loadedUrl, log);
    assert.equal(fileURLToPath(loadedUrl), join(appRoot, "assets/splash", poster.output));
    assert.doesNotMatch(log, /qs-blackhole|POSTER_LOAD_FAILED|POSTER_LOAD_TIMEOUT|Binding loop|ERROR/);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("illustrated splash is reproducible, attributed, and matches its approved master", () => {
  const source = readFileSync(new URL(poster.source, assets));
  const output = readFileSync(new URL(poster.output, assets));
  const provenance = JSON.parse(readFileSync(new URL("poster.provenance.json", assets), "utf8"));
  assert.equal(provenance.license, "CC-BY-4.0");
  assert.equal(provenance.sourceProvenance, "provenance.json");
  assert.equal(provenance.sourceSha256, createHash("sha256").update(source).digest("hex"));
  assert.equal(provenance.outputSha256, createHash("sha256").update(output).digest("hex"));
  const original = decodePoster(fileURLToPath(new URL(poster.source, assets)));
  const prepared = decodePoster(output);
  assert.deepEqual(prepared, decodePoster(preparePoster()));
  assert.equal(prepared.length, poster.width * poster.height * 3);
  assert.deepEqual(prepared, original);
});

test("warm boot flames become magenta without recoloring cyan exhaust or Ollie's feathers", () => {
  const pixels = Buffer.alloc(poster.width * poster.height * 3);
  function place(x: number, y: number, color: number[]) {
    const offset = (y * poster.width + x) * 3;
    pixels.set(color, offset);
    return offset;
  }
  const fire = place(240, 760, [255, 180, 60]);
  const exhaust = place(240, 810, [30, 180, 255]);
  const feather = place(1300, 380, [255, 180, 60]);
  const result = recolorPoster(pixels);
  assert.deepEqual([...result.subarray(fire, fire + 3)], [255, 60, 255]);
  assert.deepEqual(result.subarray(exhaust, exhaust + 3), pixels.subarray(exhaust, exhaust + 3));
  assert.deepEqual(result.subarray(feather, feather + 3), pixels.subarray(feather, feather + 3));
  assert.throws(() => recolorPoster(Buffer.alloc(3)), /1536 by 1024/);
});
