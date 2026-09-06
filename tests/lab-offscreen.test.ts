import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { cp, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import test from "node:test";

const available = spawnSync("qs", ["--version"], { encoding: "utf8" }).status === 0;

for (const packaged of [false, true]) {
test(`isolated ${packaged ? "installed" : "checkout"} lab discovers, plays, cancels, refreshes and recovers community packs`,
  { skip: !available && "Quickshell is not installed", timeout: 40000 }, async () => {
    const directory = await mkdtemp(resolve(".ql-"));
    let child: ReturnType<typeof spawn> | undefined;
    let exited: Promise<void> | undefined;
    let log = "";
    try {
      const appRoot = packaged ? join(directory, "usr/share/learn-omarchy") : process.cwd();
      if (packaged) {
        const installation = spawnSync("make", ["install", `DESTDIR=${directory}`, "PREFIX=/usr"],
          { encoding: "utf8", timeout: 15000 });
        assert.equal(installation.status, 0, installation.stderr || installation.stdout);
      }
      const env = { ...process.env, HOME: join(directory, "home"), TMPDIR: directory,
        XDG_RUNTIME_DIR: join(directory, "r"), XDG_DATA_HOME: join(directory, "data"),
        XDG_CONFIG_HOME: join(directory, "config"), XDG_CACHE_HOME: join(directory, "cache"),
        XDG_STATE_HOME: join(directory, "state"),
        QT_QPA_PLATFORM: "offscreen", QT_QPA_PLATFORMTHEME: "generic", QT_QUICK_CONTROLS_STYLE: "Basic",
        QML_XHR_ALLOW_FILE_READ: "1", QT_QUICK_BACKEND: "software",
        DBUS_SESSION_BUS_ADDRESS: `unix:path=${directory}/no-session-bus`,
        CHARACTER_LAB_APP_ROOT: appRoot, CHARACTER_LAB_ROOT: join(appRoot, "assets/characters"),
        CHARACTER_LAB_CHARACTER: "spark",
      };
      for (const key of ["WAYLAND_DISPLAY", "DISPLAY", "QS_CONFIG_PATH", "QS_CONFIG_NAME", "QS_MANIFEST"])
        delete env[key];
      for (const key of ["HOME", "XDG_RUNTIME_DIR", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME"])
        await mkdir(env[key], { recursive: true, mode: 0o700 });
      const installed = join(env.XDG_DATA_HOME, "learn-omarchy/characters/spark");
      await cp(resolve("examples/characters/spark"), installed, { recursive: true });

      child = spawn("qs", ["--no-duplicate", "--no-color", "--path", join(appRoot, "character-lab.qml")],
        { env, stdio: ["ignore", "pipe", "pipe"] });
      child.stdout!.on("data", data => { log += data; });
      child.stderr!.on("data", data => { log += data; });
      exited = new Promise(resolveExit => child!.once("close", () => resolveExit()));
      const launchError = new Promise<never>((_, reject) => child!.once("error", reject));
      function ipc(name: string, ...args: string[]) {
        const response = spawnSync("qs", ["ipc", "--pid", String(child!.pid),
          "call", "hexon-lab", name, ...args], { env, encoding: "utf8", timeout: 1500 });
        return response.status === 0 ? response.stdout.trim() : "";
      }
      async function waitStatus(predicate: (status: any) => boolean, timeout = 8000) {
        const deadline = Date.now() + timeout;
        do {
          const response = ipc("status");
          if (response.startsWith("{")) {
            const status = JSON.parse(response);
            if (predicate(status)) return status;
          }
          assert.equal(child!.exitCode, null, `Lab exited before becoming responsive:\n${log}`);
          await delay(60);
        } while (Date.now() < deadline);
        assert.fail(`Lab status timed out:\n${ipc("status")}\n${log}`);
      }

      const ready = await Promise.race([
        waitStatus(s => s.character === "spark" && s.packs.includes("hexon") && s.packs.includes("owl")),
        launchError,
      ]);
      assert.equal(ready.frameCount, 1, "the starter does not need official strip frame counts");
      assert.equal(ready.introAvailable, true);
      assert.equal(ipc("intro"), "ok");
      await waitStatus(s => s.introActive && s.introRunning);
      assert.equal(ipc("stop"), "ok");
      await waitStatus(s => !s.introActive && !s.introRunning);
      assert.equal(ipc("intro"), "ok");
      await waitStatus(s => !s.introActive && !s.introRunning, 5000);
      assert.equal(ipc("pose", "point"), "ok");
      assert.equal(ipc("speech", "true"), "ok");
      assert.equal(ipc("facing", "-1"), "ok");
      const pointing = await waitStatus(s => s.pose === "point" && s.talking);
      assert.equal(pointing.facing, -1);
      assert.equal(ipc("reset"), "ok");
      await waitStatus(s => s.pose === "idle" && s.facing === 1 && !s.talking);

      for (const id of ["hexon", "owl"]) {
        assert.equal(ipc("character", id), "ok");
        await waitStatus(s => s.character === id && s.introAvailable);
        assert.equal(ipc("intro"), "ok");
        await waitStatus(s => s.introRunning);
        assert.equal(ipc("motion"), "ok");
        const finished = await waitStatus(s => !s.introActive && !s.introRunning);
        assert.match(finished.introError, /Reduced motion/);
        assert.equal(ipc("motion"), "ok");
      }

      assert.equal(ipc("character", "spark"), "ok");
      const manifestPath = join(installed, "character.json");
      const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
      delete manifest.intro;
      await writeFile(manifestPath, JSON.stringify(manifest));
      assert.equal(ipc("refresh"), "ok");
      await waitStatus(s => s.character === "spark" && !s.introAvailable);
      assert.equal(ipc("intro"), "ok", "missing intros use the production player's fallback");
      const fallback = await waitStatus(s => !s.introRunning && /no intro sequence/.test(s.introError));
      assert.equal(fallback.introActive, false);

      manifest.intro = { sequence: "intro/sequence.json" };
      await writeFile(manifestPath, JSON.stringify(manifest));
      await writeFile(join(installed, "intro/sequence.json"), '{"version":999}');
      assert.equal(ipc("refresh"), "ok");
      await waitStatus(s => s.diagnostics.some((message: string) => message.includes("intro disabled")));
      assert.equal(ipc("intro"), "ok");
      await waitStatus(s => !s.introRunning && /no intro sequence/.test(s.introError));

      await rm(installed, { recursive: true });
      assert.equal(ipc("refresh"), "ok");
      const recovery = await waitStatus(s => s.character === "hexon" && !s.packs.includes("spark"));
      assert.match(recovery.notice, /spark.*unavailable/);
      assert.doesNotMatch(log, /ReferenceError|TypeError|Binding loop|Cannot assign to non-existent property|Failed to load configuration/);
    } finally {
      if (child && child.exitCode === null && child.signalCode === null) child.kill("SIGTERM");
      if (exited) await exited;
      await rm(directory, { recursive: true, force: true });
    }
  });
}
