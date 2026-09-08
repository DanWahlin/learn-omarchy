import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { chmod, mkdir, mkdtemp, readFile, readdir, rm, stat, truncate, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import test from "node:test";
import {
  loadTiming, MAX_AUDIO_BYTES, MAX_TIMING_BYTES, mpvArguments, parseArguments, validateTiming,
} from "../tools/play-timed-speech.mjs";

const player = resolve("tools/play-timed-speech.mjs");
const audioBytes = Buffer.from("fake local MP3 fixture; never sent to an audio player");
const hash = createHash("sha256").update(audioBytes).digest("hex");
const metadata = {
  version: 1, audioHash: hash, text: "Hello HEXON.",
  words: [{ startMs: 0, endOffset: 5 }, { startMs: 500, endOffset: 12 }],
};
const delay = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

async function fixture() {
  const directory = resolve(await mkdtemp(".timed-speech-test-"));
  const audio = join(directory, "welcome clip.mp3");
  await writeFile(audio, audioBytes);
  return { directory, audio, cleanup: () => rm(directory, { recursive: true, force: true }) };
}

test("argument parsing and ordinary playback arguments preserve paths, volume, and speed", () => {
  const options = parseArguments(["--audio", "/a/welcome clip.mp3", "--volume", "63", "--speed", "1.5"]);
  assert.deepEqual(mpvArguments(options), [
    "--no-video", "--really-quiet", "--volume=63", "--speed=1.5", "--", "/a/welcome clip.mp3",
  ]);
  for (const args of [
    [], ["--audio", "relative.mp3", "--volume", "1", "--speed", "1"],
    ["--audio", "/a.mp3", "--volume", "NaN", "--speed", "1"],
    ["--audio", "/a.mp3", "--volume", "101", "--speed", "1"],
    ["--audio", "/a.mp3", "--volume", "1", "--speed", "0"],
    ["--audio", "/a.mp3", "--volume", "1", "--speed", "Infinity"],
    ["--audio", "/a.mp3", "--volume", "1", "--speed", "1", "--extra", "x"],
    ["--audio", "/a.mp3", "--audio", "/b.mp3", "--volume", "1", "--speed", "1"],
  ]) assert.throws(() => parseArguments(args));
});

test("validation requires hash, complete ordered finite UTF-16 timing, and original text", () => {
  assert.deepEqual(validateTiming(metadata, hash), { text: metadata.text, words: metadata.words });
  for (const value of [
    null, {}, { ...metadata, version: 2 }, { ...metadata, audioHash: "0".repeat(64) },
    { ...metadata, text: "" }, { ...metadata, words: [] },
    { ...metadata, words: [{ startMs: -1, endOffset: 12 }] },
    { ...metadata, words: [{ startMs: Infinity, endOffset: 12 }] },
    { ...metadata, words: [{ startMs: NaN, endOffset: 12 }] },
    { ...metadata, words: [{ startMs: 0, endOffset: 5 }] },
    { ...metadata, words: [{ startMs: 0, endOffset: 13 }] },
    { ...metadata, words: [{ startMs: 0, endOffset: 1.5 }, { startMs: 1, endOffset: 12 }] },
    { ...metadata, words: [{ startMs: 2, endOffset: 5 }, { startMs: 1, endOffset: 12 }] },
    { ...metadata, words: [{ startMs: 0, endOffset: 5 }, { startMs: 1, endOffset: 5 }] },
    { ...metadata, text: "😀 hi", words: [{ startMs: 0, endOffset: 1 }, { startMs: 1, endOffset: 5 }] },
  ]) assert.throws(() => validateTiming(value, hash), JSON.stringify(value));
  assert.deepEqual(validateTiming({
    ...metadata, text: "😀 hi", words: [{ startMs: 0, endOffset: 2 }, { startMs: 0, endOffset: 5 }],
  }, hash).words, [{ startMs: 0, endOffset: 2 }, { startMs: 0, endOffset: 5 }]);
});

test("sidecar loading hashes final audio and bounds both input files", async () => {
  const f = await fixture();
  try {
    assert.deepEqual(await loadTiming(f.audio), { reason: "missing-timing" });
    await writeFile(`${f.audio}.timing.json`, JSON.stringify(metadata));
    assert.deepEqual(await loadTiming(f.audio), { timing: { text: metadata.text, words: metadata.words } });
    await writeFile(f.audio, "changed after timing was generated");
    assert.equal((await loadTiming(f.audio)).reason, "invalid-timing");
    await writeFile(f.audio, audioBytes);
    await writeFile(`${f.audio}.timing.json`, "{");
    assert.equal((await loadTiming(f.audio)).reason, "invalid-timing");
    await truncate(`${f.audio}.timing.json`, MAX_TIMING_BYTES + 1);
    assert.match((await loadTiming(f.audio)).diagnostic, /exceeds/);
    await writeFile(`${f.audio}.timing.json`, JSON.stringify(metadata));
    await truncate(f.audio, MAX_AUDIO_BYTES + 1);
    assert.match((await loadTiming(f.audio)).diagnostic, /exceeds/);
  } finally {
    await f.cleanup();
  }
});

async function startPlayer(mode: string, timing: unknown = metadata, exitCode = 0,
  options: { readOnlyCwd?: boolean; longRuntime?: boolean } = {}) {
  const f = await fixture();
  const callerDirectory = options.readOnlyCwd ? join(f.directory, "caller") : f.directory;
  if (options.readOnlyCwd) await mkdir(callerDirectory, { mode: 0o500 });
  const runtime = options.longRuntime ? join(f.directory, "long".repeat(30)) : f.directory;
  if (options.longRuntime) await mkdir(runtime, { mode: 0o700 });
  if (timing !== null) await writeFile(`${f.audio}.timing.json`, JSON.stringify(timing));
  await writeFile(join(f.directory, "package.json"), '{"type":"commonjs"}');
  const executable = join(f.directory, "mpv");
  await writeFile(executable, `#!${process.execPath}
const fs = require("node:fs");
const net = require("node:net");
const report = name => require("node:path").join(process.env.FAKE_DIRECTORY, name);
const args = process.argv.slice(2);
const mode = process.env.FAKE_MODE;
const socket = args.find(arg => arg.startsWith("--input-ipc-server="))?.split("=")[1];
fs.writeFileSync(report("started.json"), JSON.stringify({ args, pid: process.pid, socket }));
if (mode === "ignore-term") process.on("SIGTERM", () => {});
if (socket && mode !== "no-socket") {
  const server = net.createServer(connection => {
    connection.on("error", () => {});
    connection.on("data", data => {
      fs.writeFileSync(report("observed.json"), data);
      if (mode === "unsupported") {
        connection.write(JSON.stringify({request_id: 1, error: "command not found"}) + "\\n");
      } else if (mode === "malformed") {
        connection.write("not json\\n");
      } else if (mode === "disconnect") {
        connection.end();
      } else if (mode !== "no-position") {
        const values = [null, 0.125, 0.125, 0.05, 0.9];
        values.forEach((data, index) => setTimeout(() => {
          connection.write(JSON.stringify({event: "property-change", name: "time-pos", data}) + "\\n");
        }, index * 15));
        if (mode === "eof") setTimeout(() => {
          connection.end(JSON.stringify({event: "end-file", reason: "eof"}) + "\\n");
        }, 90);
      }
    });
  });
  server.listen(socket);
}
const duration = ["cancel", "ignore-term"].includes(mode) ? 10000 :
  ["no-socket", "no-position"].includes(mode) ? 1900 : 240;
setTimeout(() => {
  fs.writeFileSync(report("finished"), "audio completed");
  process.exit(Number(process.env.FAKE_EXIT));
}, duration);
`);
  await chmod(executable, 0o700);
  const child = spawn(process.execPath, [player, "--audio", f.audio, "--volume", "61", "--speed", "1.75"], {
    cwd: callerDirectory,
    env: { ...process.env, PATH: f.directory, XDG_RUNTIME_DIR: runtime,
      FAKE_DIRECTORY: f.directory, FAKE_MODE: mode, FAKE_EXIT: String(exitCode) },
    stdio: ["ignore", "pipe", "pipe"],
  });
  let stdout = "";
  let stderr = "";
  child.stdout.on("data", (chunk) => { stdout += chunk; });
  child.stderr.on("data", (chunk) => { stderr += chunk; });
  const finished = new Promise<{ code: number | null; signal: string | null }>((resolve, reject) => {
    child.once("error", reject);
    child.once("close", (code, signal) => resolve({ code, signal }));
  });
  const events = () => stdout.trim().split("\n").filter(Boolean).map((line) => JSON.parse(line));
  return {
    ...f, callerDirectory, runtime, child, finished, events, stderr: () => stderr,
    cleanup: async () => {
      if (child.exitCode === null && child.signalCode === null) child.kill("SIGTERM");
      await finished;
      await f.cleanup();
    },
  };
}

async function waitForFile(path: string) {
  for (let attempt = 0; attempt < 200; attempt++) {
    try {
      return await readFile(path, "utf8");
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
      await delay(10);
    }
  }
  throw new Error(`Timed out waiting for fixture ${path}`);
}

async function assertClean(directory: string) {
  assert.deepEqual((await readdir(directory)).filter((name) => name.startsWith("learn-speech-")), []);
}

async function waitForFallback(f: Awaited<ReturnType<typeof startPlayer>>) {
  for (let attempt = 0; attempt < 180; attempt++) {
    if (f.events().some((event) => event.type === "fallback")) return;
    await delay(10);
  }
  assert.fail("Expected IPC fallback promptly, before audio finishes");
}

test("absent and invalid metadata still play audio using ordinary mpv arguments", async () => {
  for (const timing of [null, { ...metadata, audioHash: "0".repeat(64) }, { ...metadata, words: [] }]) {
    const f = await startPlayer("plain", timing);
    try {
      assert.deepEqual(await f.finished, { code: 0, signal: null }, f.stderr());
      assert.deepEqual(f.events(), [{ type: "fallback", reason: timing === null ? "missing-timing" : "invalid-timing" }]);
      const started = JSON.parse(await readFile(join(f.directory, "started.json"), "utf8"));
      assert.deepEqual(started.args, mpvArguments({ audio: f.audio, volume: 61, speed: 1.75 }));
      assert.equal(await readFile(join(f.directory, "finished"), "utf8"), "audio completed");
      if (timing === null) assert.equal(f.stderr(), "");
      else assert.match(f.stderr(), /Invalid speech timing/);
      await assertClean(f.directory);
    } finally {
      await f.cleanup();
    }
  }
});

test("IPC reports only actual media positions, including pauses and backwards seeks", async () => {
  const f = await startPlayer("positions");
  try {
    assert.equal((await f.finished).code, 0);
    const events = f.events();
    assert.deepEqual(events[0], { type: "timing", text: metadata.text, words: metadata.words });
    assert.deepEqual(events.filter((event) => event.type === "position"), [
      { type: "position", positionMs: 125 }, { type: "position", positionMs: 125 },
      { type: "position", positionMs: 50 }, { type: "position", positionMs: 900 },
    ]);
    const started = JSON.parse(await readFile(join(f.directory, "started.json"), "utf8"));
    assert.ok(started.args.includes("--speed=1.75"));
    assert.ok(started.args.includes("--pause=no"));
    assert.deepEqual(JSON.parse(await readFile(join(f.directory, "observed.json"), "utf8")),
      { command: ["observe_property", 1, "time-pos"], request_id: 1 });
    await assertClean(f.directory);
  } finally {
    await f.cleanup();
  }
});

test("normal media EOF does not report a timing failure before the player exits", async () => {
  const f = await startPlayer("eof");
  try {
    assert.equal((await f.finished).code, 0);
    assert.ok(f.events().some(event => event.type === "position"));
    assert.equal(f.events().some(event => event.type === "fallback"), false);
    await assertClean(f.directory);
  } finally {
    await f.cleanup();
  }
});

test("read-only caller cwd is untouched while a private runtime directory supports timing", async () => {
  const f = await startPlayer("cancel", metadata, 0, { readOnlyCwd: true });
  try {
    const started = JSON.parse(await waitForFile(join(f.directory, "started.json")));
    await waitForFile(join(f.directory, "observed.json"));
    assert.ok(started.socket.startsWith(`${f.runtime}/learn-speech-`));
    assert.equal((await stat(resolve(started.socket, ".."))).mode & 0o777, 0o700);
    assert.deepEqual(await readdir(f.callerDirectory), []);
    f.child.kill("SIGTERM");
    assert.equal((await f.finished).code, 143);
    await assertClean(f.runtime);
  } finally {
    await f.cleanup();
  }
});

test("an overly long runtime socket path falls back without losing audio", async () => {
  const f = await startPlayer("plain", metadata, 0, { longRuntime: true });
  try {
    assert.equal((await f.finished).code, 0);
    assert.deepEqual(f.events().filter((event) => event.type === "fallback"),
      [{ type: "fallback", reason: "ipc-unavailable" }]);
    const started = JSON.parse(await readFile(join(f.directory, "started.json"), "utf8"));
    assert.deepEqual(started.args, mpvArguments({ audio: f.audio, volume: 61, speed: 1.75 }));
    assert.equal(await readFile(join(f.directory, "finished"), "utf8"), "audio completed");
    assert.match(f.stderr(), /too long/);
    await assertClean(f.runtime);
  } finally {
    await f.cleanup();
  }
});

test("missing, unsupported, broken, and silent IPC fall back without stopping playback", async () => {
  for (const [mode, reason] of [
    ["no-socket", "ipc-unavailable"], ["no-position", "ipc-unavailable"],
    ["unsupported", "unsupported-ipc"], ["malformed", "invalid-ipc-response"], ["disconnect", "ipc-disconnected"],
  ]) {
    const f = await startPlayer(mode);
    try {
      await waitForFallback(f);
      assert.equal(f.child.exitCode, null, "IPC fallback must leave audio running");
      assert.equal((await f.finished).code, 0);
      assert.deepEqual(f.events().filter((event) => event.type === "fallback"), [{ type: "fallback", reason }]);
      assert.equal(f.events().filter((event) => event.type === "position").length, 0);
      assert.equal(await readFile(join(f.directory, "finished"), "utf8"), "audio completed");
      assert.match(f.stderr(), /Audio continues/);
      await assertClean(f.directory);
    } finally {
      await f.cleanup();
    }
  }
});

test("SIGINT/SIGTERM cancel only the owned player and clean private IPC directories", async () => {
  for (const [mode, signal, expectedCode, timing] of [
    ["cancel", "SIGTERM", 143, metadata], ["cancel", "SIGINT", 130, metadata],
    ["ignore-term", "SIGTERM", 143, metadata], ["cancel", "SIGTERM", 143, null],
  ] as const) {
    const f = await startPlayer(mode, timing);
    try {
      const started = JSON.parse(await waitForFile(join(f.directory, "started.json")));
      if (timing) {
        await waitForFile(join(f.directory, "observed.json"));
        const socketDirectory = resolve(f.directory, started.socket, "..");
        assert.equal((await stat(socketDirectory)).mode & 0o777, 0o700);
      }
      f.child.kill(signal);
      assert.deepEqual(await f.finished, { code: expectedCode, signal: null });
      assert.throws(() => process.kill(started.pid, 0), { code: "ESRCH" });
      await assertClean(f.directory);
    } finally {
      await f.cleanup();
    }
  }
});

test("playback failures propagate mpv status with useful diagnostics", async () => {
  const f = await startPlayer("plain", null, 7);
  try {
    assert.deepEqual(await f.finished, { code: 7, signal: null });
    assert.match(f.stderr(), /mpv exited with status 7/);
  } finally {
    await f.cleanup();
  }
});

test("a missing mpv executable returns failure rather than pretending playback succeeded", async () => {
  const f = await fixture();
  try {
    await writeFile(`${f.audio}.timing.json`, JSON.stringify(metadata));
    const child = spawn(process.execPath, [player, "--audio", f.audio, "--volume", "50", "--speed", "1"], {
      cwd: f.directory, env: { ...process.env, PATH: f.directory, XDG_RUNTIME_DIR: f.directory },
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stderr = "";
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    const code = await new Promise((resolve) => child.on("close", resolve));
    assert.equal(code, 1);
    assert.match(stderr, /Unable to start mpv/);
    await assertClean(f.directory);
  } finally {
    await f.cleanup();
  }
});
