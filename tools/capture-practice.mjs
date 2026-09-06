import { spawn } from "node:child_process";
import { mkdir, mkdtemp, readFile, writeFile, rm, rmdir, stat } from "node:fs/promises";
import { join, resolve } from "node:path";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";

export function validRegion(value) {
  const match = /^(-?\d+),(-?\d+) ([1-9]\d*)x([1-9]\d*)$/.exec(value);
  return Boolean(match && match.slice(1).every(part => Number.isSafeInteger(Number(part))));
}

export function recorderArguments(region, output) {
  if (!validRegion(region)) throw new Error("Invalid recording region");
  const [x, y, width, height] = region.match(/-?\d+/g);
  return ["-w", "region", "-region", `${width}x${height}+${x}+${y}`,
    "-f", "30", "-k", "h264", "-fallback-cpu-encoding", "yes", "-o", output];
}

async function artifactDirectory(prefix) {
  const base = resolve(".learn-omarchy-practice");
  await mkdir(base, { recursive: true, mode: 0o700 });
  return mkdtemp(join(base, prefix));
}

async function capture() {
  let child;
  let cancelled = false;
  const cancel = () => { cancelled = true; if (child) child.kill("SIGTERM"); };
  process.on("SIGTERM", cancel);
  process.on("SIGINT", cancel);
  const directory = process.env.XDG_RUNTIME_DIR
    ? await mkdtemp(join(process.env.XDG_RUNTIME_DIR, "learn-omarchy-capture."))
    : await artifactDirectory("learn-omarchy-capture.");
  const path = join(directory, "practice.png");
  let saved = false;
  const run = (command, args) => new Promise((resolveRun, reject) => {
    if (cancelled) { resolveRun({ code: 2, output: "", error: "" }); return; }
    child = spawn(command, args, { stdio: ["ignore", "pipe", "pipe"] });
    let output = "", error = "";
    child.stdout.setEncoding("utf8").on("data", data => { output += data; });
    child.stderr.setEncoding("utf8").on("data", data => { error += data; });
    child.on("error", reject);
    child.on("close", code => { child = null; resolveRun({ code, output: output.trim(), error: error.trim() }); });
  });
  try {
    const selection = await run("slurp", []);
    if (cancelled || (selection.code === 1 && (!selection.error || selection.error === "selection cancelled"))) {
      process.exitCode = 2;
      return;
    }
    if (selection.code !== 0 || !validRegion(selection.output)) throw new Error(selection.error || "Invalid capture region");
    const result = await run("grim", ["-g", selection.output, path]);
    if (cancelled) { process.exitCode = 2; return; }
    if (result.code !== 0) throw new Error(result.error || "Screenshot capture failed");
    if ((await stat(path)).size === 0) throw new Error("Screenshot is empty");
    saved = true;
    console.log(path);
  } finally {
    if (!saved) {
      await rm(path, { force: true });
      await rmdir(directory);
    }
    process.off("SIGTERM", cancel);
    process.off("SIGINT", cancel);
  }
}

export const sessionActions = {
  "screen-recording": ["select", "start", "stop"],
  ocr: ["extract"],
  qr: ["prepare", "extract"],
  dictation: ["check"],
  "web-app": ["create", "open", "remove"],
  transcode: ["prepare", "convert"],
  sharing: ["prepare"],
};

// One worker owns one private artifact directory and only the children it spawned.
export async function practiceSession(mode) {
  if (!Object.hasOwn(sessionActions, mode)) throw new Error("Unsupported practice session");
  const directory = await artifactDirectory("session.");
  const children = new Set();
  let recorder = null, recordingDone = null, region = "", stopping = false;
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
      child.kill(child === recorder ? "SIGINT" : "SIGTERM");
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
        if (mode === "screen-recording") {
          if (action === "select") {
            if (recorder) throw new Error("Stop your recording before selecting again");
            region = "";
            const selected = await start("slurp", []).done;
            if (selected.code === 1 && !selected.output) { emit({ action, cancelled: true }); continue; }
            if (selected.code !== 0 || !validRegion(selected.output)) throw new Error(selected.error || "Invalid region");
            region = selected.output;
            result = { region };
          } else if (action === "start") {
            if (!region || recorder) throw new Error("Select and review a region first");
            // The kernel stops this recorder even if the coach force-kills our worker.
            const job = start("setpriv", ["--pdeathsig", "SIGINT", "--", "gpu-screen-recorder",
              ...recorderArguments(region, path("recording.mp4"))]);
            recorder = job.child;
            recordingDone = job.done;
            // Report startup failures instead of presenting a running recorder.
            const early = await Promise.race([job.done, new Promise(resolveWait => setTimeout(() => resolveWait(null), 250))]);
            if (early) { recorder = null; throw new Error(early.error || "Recorder stopped before starting"); }
            job.done.then(result => {
              if (recorder !== job.child || stopping) return;
              recorder = null;
              emit({ action: "stop", error: result.error || "Recording stopped unexpectedly. Select a region and retry." });
            }).catch(() => {});
            result = { recording: true };
          } else {
            if (!recorder) throw new Error("Start a recording first");
            const ownedRecorder = recorder;
            recorder = null;
            ownedRecorder.kill("SIGINT");
            const timeout = setTimeout(() => ownedRecorder.kill("SIGKILL"), 5000);
            const stopped = await recordingDone;
            clearTimeout(timeout);
            if (stopped.code !== 0 && stopped.signal !== "SIGINT") throw new Error(stopped.error || "Recording failed");
            result = await inspect("recording.mp4");
          }
        } else if (mode === "ocr" || mode === "qr") {
          if (action === "prepare") {
            await run("qrencode", ["-o", path("sample.png"), "-s", "8", "OMARCHY SAFE SAMPLE"]);
            result = { image: path("sample.png") };
          } else {
            const selected = await start("slurp", []).done;
            if (selected.code === 1 && !selected.output) { emit({ action, cancelled: true }); continue; }
            if (selected.code !== 0 || !validRegion(selected.output)) throw new Error(selected.error || "Invalid region");
            await run("grim", ["-g", selected.output, path("selection.png")]);
            const text = mode === "ocr"
              ? await run("tesseract", [path("selection.png"), "stdout", "--psm", "6"])
              : await run("zbarimg", ["--quiet", "--raw", path("selection.png")]);
            // Never expose arbitrary recognized screen contents in the lesson or logs.
            if (text.trim() !== "OMARCHY SAFE SAMPLE") throw new Error("The sample wasn't recognized. Select only the sample card and retry.");
            result = { text, path: path("selection.png") };
          }
        } else if (mode === "dictation") {
          await run("voxtype", ["--version"]);
          result = { available: true };
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
        if (action === "start") recorder = null;
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
  (process.argv[2] === "--session" ? practiceSession(process.argv[3]) : capture()).catch(error => {
    console.error("Practice capture:", error.message);
    process.exitCode = 1;
  });
}
