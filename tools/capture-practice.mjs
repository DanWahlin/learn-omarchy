import { spawn } from "node:child_process";
import { mkdir, mkdtemp, readFile, readdir, writeFile, rm, stat } from "node:fs/promises";
import { isAbsolute, join, resolve } from "node:path";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";

async function artifactDirectory(prefix) {
  const base = resolve(".learn-omarchy-practice");
  await mkdir(base, { recursive: true, mode: 0o700 });
  return mkdtemp(join(base, prefix));
}

export async function screenshotDirectory(env = process.env) {
  if (env.OMARCHY_SCREENSHOT_DIR) return resolve(env.OMARCHY_SCREENSHOT_DIR);
  const home = env.HOME || "";
  if (env.XDG_PICTURES_DIR)
    return resolve(env.XDG_PICTURES_DIR.replace(/\$\{HOME\}|\$HOME/g, home));
  try {
    const userDirs = await readFile(join(home, ".config", "user-dirs.dirs"), "utf8");
    const match = /^XDG_PICTURES_DIR="([^"]+)"$/m.exec(userDirs);
    if (match) return resolve(match[1].replace(/\$\{HOME\}|\$HOME/g, home));
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
  return resolve(home, "Pictures");
}

export async function recordingDirectory(env = process.env) {
  if (env.OMARCHY_SCREENRECORD_DIR) return resolve(env.OMARCHY_SCREENRECORD_DIR);
  const home = env.HOME || "";
  if (env.XDG_VIDEOS_DIR)
    return resolve(env.XDG_VIDEOS_DIR.replace(/\$\{HOME\}|\$HOME/g, home));
  try {
    const userDirs = await readFile(join(home, ".config", "user-dirs.dirs"), "utf8");
    const match = /^XDG_VIDEOS_DIR="([^"]+)"$/m.exec(userDirs);
    if (match) return resolve(match[1].replace(/\$\{HOME\}|\$HOME/g, home));
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
  return resolve(home, "Videos");
}

export async function watchScreenshots() {
  const directory = await screenshotDirectory();
  const observed = new Map();
  const pending = new Set();
  const reported = new Map();
  let stopping = false;
  const stop = () => { stopping = true; };
  process.on("SIGTERM", stop);
  process.on("SIGINT", stop);

  async function scan(emitNew) {
    let names;
    try {
      names = await readdir(directory);
    } catch (error) {
      if (error.code === "ENOENT") return;
      throw error;
    }
    for (const name of names) {
      if (!/^screenshot-\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\.png$/.test(name)) continue;
      if (emitNew && observed.has(name) && !pending.has(name)) continue;
      const path = join(directory, name);
      const info = await stat(path);
      if (!info.isFile() || info.size === 0) continue;
      const version = `${info.mtimeMs}:${info.size}`;
      if (observed.get(name) !== version) {
        observed.set(name, version);
        if (!emitNew) reported.set(name, version);
        else pending.add(name);
        continue;
      }
      if (!emitNew || reported.get(name) === version) continue;
      pending.delete(name);
      reported.set(name, version);
      console.log(path);
    }
  }

  try {
    await scan(false);
    while (!stopping) {
      await new Promise(resolveDelay => setTimeout(resolveDelay, 250));
      await scan(true);
    }
  } finally {
    process.off("SIGTERM", stop);
    process.off("SIGINT", stop);
  }
}

export async function watchRecordings(env = process.env) {
  const directory = await recordingDirectory(env);
  const marker = env.OMARCHY_SCREENRECORD_MARKER || "/tmp/omarchy-screenrecord-filename";
  const observed = new Map();
  const pending = new Set();
  const reported = new Map();
  let stopping = false;
  let activePath = "";
  let completedPath = "";
  let ignoringExistingRecording = false;
  const stop = () => { stopping = true; };
  process.on("SIGTERM", stop);
  process.on("SIGINT", stop);

  async function readMarker() {
    try {
      return (await readFile(marker, "utf8")).trim();
    } catch (error) {
      if (error.code === "ENOENT") return "";
      throw error;
    }
  }

  async function scan(emitNew, recordingActive) {
    let names;
    try {
      names = await readdir(directory);
    } catch (error) {
      if (error.code === "ENOENT") return;
      throw error;
    }
    for (const name of names) {
      if (!/^screenrecording-\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\.mp4$/.test(name)) continue;
      if (emitNew && observed.has(name) && !pending.has(name)) continue;
      const path = join(directory, name);
      const info = await stat(path);
      if (!info.isFile() || info.size === 0) continue;
      const version = `${info.mtimeMs}:${info.size}`;
      if (observed.get(name) !== version) {
        observed.set(name, version);
        if (!emitNew) reported.set(name, version);
        else pending.add(name);
        continue;
      }
      if (!emitNew || recordingActive || reported.get(name) === version) continue;
      if (!completedPath || resolve(path) !== resolve(completedPath)) continue;
      pending.delete(name);
      reported.set(name, version);
      console.log(JSON.stringify({ event: "saved", path }));
      completedPath = "";
    }
  }

  try {
    activePath = await readMarker();
    await scan(false, activePath !== "");
    if (activePath) {
      ignoringExistingRecording = true;
      console.log(JSON.stringify({ event: "already-active" }));
    }
    while (!stopping) {
      await new Promise(resolveDelay => setTimeout(resolveDelay, 250));
      const nextActivePath = await readMarker();
      if (nextActivePath && !activePath) {
        if (!ignoringExistingRecording) console.log(JSON.stringify({ event: "started" }));
        completedPath = "";
      } else if (!nextActivePath && activePath) {
        if (ignoringExistingRecording) {
          ignoringExistingRecording = false;
          observed.clear();
          pending.clear();
          reported.clear();
          await scan(false, false);
        } else {
          completedPath = activePath;
        }
      }
      activePath = nextActivePath;
      await scan(true, activePath !== "");
    }
  } finally {
    process.off("SIGTERM", stop);
    process.off("SIGINT", stop);
  }
}

export const sessionActions = {
  qr: ["prepare"],
  dictation: ["check"],
  "dictation-corrections": ["inspect"],
  "web-app": ["create", "open", "remove"],
  transcode: ["prepare", "convert"],
  sharing: ["prepare"],
};

// One worker owns one private artifact directory and only the children it spawned.
export async function practiceSession(mode) {
  if (!Object.hasOwn(sessionActions, mode)) throw new Error("Unsupported practice session");
  const directory = await artifactDirectory("session.");
  const children = new Set();
  let stopping = false;
  const path = name => join(directory, name);
  const emit = result => console.log(JSON.stringify(result));
  function start(command, args) {
    const child = spawn(command, args, { stdio: ["ignore", "pipe", "pipe"] });
    children.add(child);
    let output = "", error = "";
    const done = new Promise((resolveDone, reject) => {
      child.stdout.on("data", data => { output += data; });
      child.stderr.on("data", data => { error += data; });
      child.once("error", error => reject(new Error(error.code === "ENOENT"
        ? `${command} is unavailable. Return and skip, or retry after setting up the tool yourself.`
        : error.message)));
      child.once("close", (code, signal) => {
        children.delete(child);
        resolveDone({ code, signal, output: output.trim(), error: error.trim() });
      });
    });
    return { child, done };
  }
  async function run(command, args) {
    const result = await start(command, args).done;
    if (result.code !== 0) throw new Error(result.error || `${command} unavailable or failed. Return and skip, or retry.`);
    return result.output;
  }
  async function inspect(name) {
    const output = path(name);
    const info = JSON.parse(await run("ffprobe", ["-v", "error", "-show_entries", "format=duration,size", "-of", "json", output]));
    if (!(Number(info.format?.duration) > 0) || !(Number(info.format?.size) > 0)) throw new Error("No playable media was saved");
    return { path: output, bytes: Number(info.format.size) };
  }
  async function shutdown() {
    if (stopping) return;
    stopping = true;
    for (const child of children) {
      child.kill("SIGTERM");
      const timeout = setTimeout(() => { if (children.has(child)) child.kill("SIGKILL"); }, 3000);
      timeout.unref();
      child.once("close", () => clearTimeout(timeout));
    }
    // Artifacts are retained for inspection, but demo launcher entries never survive exit.
    await rm(path("demo.desktop"), { force: true });
  }
  process.on("SIGTERM", shutdown);
  process.on("SIGINT", shutdown);
  const lines = createInterface({ input: process.stdin });
  const signalClose = () => { lines.close(); process.stdin.destroy(); };
  process.on("SIGTERM", signalClose);
  process.on("SIGINT", signalClose);
  try {
    for await (const line of lines) {
      let action = "";
      try {
        const request = JSON.parse(line);
        action = request.action;
        if (stopping || !sessionActions[mode].includes(action)) throw new Error("Action is not allowed in this exercise");
        let result = {};
        if (mode === "qr") {
          if (action === "prepare") {
            await run("qrencode", ["-o", path("sample.png"), "-s", "8", "OMARCHY SAFE SAMPLE"]);
            result = { image: path("sample.png") };
          }
        } else if (mode === "dictation") {
          await run("voxtype", ["--version"]);
          result = { available: true };
        } else if (mode === "dictation-corrections") {
          const home = process.env.HOME;
          const config = home && isAbsolute(home) ? join(home, ".config", "voxtype", "config.toml") : "";
          let source = "sample";
          let replacementsDocumented = false;
          try {
            if (!config) throw Object.assign(new Error("No home directory"), { code: "ENOENT" });
            const text = await readFile(config, "utf8");
            source = "config";
            replacementsDocumented = /^\s*(?:#\s*)?\[text\]\s*$/m.test(text) &&
              /^\s*(?:#\s*)?replacements\s*=/m.test(text);
          } catch (error) {
            if (error.code !== "ENOENT" && error.code !== "ENOTDIR" && error.code !== "EACCES") throw error;
          }
          result = { source, replacementsDocumented };
        } else if (mode === "web-app") {
          if (action === "create") {
            await writeFile(path("demo.desktop"), "[Desktop Entry]\nType=Link\nName=Omarchy practice demo\nURL=https://example.org\n", { flag: "wx", mode: 0o600 });
            result = { path: path("demo.desktop") };
          } else if (action === "open") {
            await readFile(path("demo.desktop"), "utf8");
            result = { opened: true };
          } else {
            await rm(path("demo.desktop"));
            result = { removed: true };
          }
        } else if (mode === "transcode") {
          if (action === "prepare") {
            await run("ffmpeg", ["-nostdin", "-v", "error", "-n", "-f", "lavfi", "-i", "testsrc2=size=640x360:rate=15", "-t", "2", "-an", "-c:v", "libx264", "-crf", "10", path("original.mp4")]);
            result = await inspect("original.mp4");
          } else {
            if (![180, 240].includes(request.height)) throw new Error("Choose a supported output resolution");
            await run("ffmpeg", ["-nostdin", "-v", "error", "-y", "-i", path("original.mp4"), "-an", "-vf", `scale=-2:${request.height}`, "-c:v", "libx264", "-crf", "32", path("smaller.mp4")]);
            result = await inspect("smaller.mp4");
            const original = await stat(path("original.mp4"));
            if (result.bytes >= original.size) throw new Error("This output isn't smaller. Try the lower resolution.");
            result.originalBytes = original.size;
          }
        } else if (mode === "sharing") {
          await writeFile(path("share-note.txt"), "OMARCHY SAFE SAMPLE\nA harmless practice note. No private information.\n", { flag: "wx", mode: 0o600 });
          result = { path: path("share-note.txt") };
        }
        emit({ action, ...result });
      } catch (error) {
        emit({ action, error: error.message });
      }
    }
  } finally {
    await shutdown();
    process.off("SIGTERM", shutdown);
    process.off("SIGINT", shutdown);
    process.off("SIGTERM", signalClose);
    process.off("SIGINT", signalClose);
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  (process.argv[2] === "--session" ? practiceSession(process.argv[3])
    : process.argv[2] === "--watch-screenshots" ? watchScreenshots()
    : process.argv[2] === "--watch-recordings" ? watchRecordings()
    : Promise.reject(new Error("expected --session, --watch-screenshots, or --watch-recordings"))).catch(error => {
    console.error("Practice capture:", error.message);
    process.exitCode = 1;
  });
}
