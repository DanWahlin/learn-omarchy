import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { constants } from "node:fs";
import { mkdir, mkdtemp, open, rmdir, unlink } from "node:fs/promises";
import { connect } from "node:net";
import { homedir } from "node:os";
import { isAbsolute, join } from "node:path";
import { pathToFileURL } from "node:url";

export const MAX_TIMING_BYTES = 256 * 1024;
export const MAX_AUDIO_BYTES = 64 * 1024 * 1024;
const IPC_TIMEOUT_MS = 1500;
const IPC_RETRY_MS = 40;
const STOP_TIMEOUT_MS = 750;

export function parseArguments(args) {
  const values = {};
  for (let index = 0; index < args.length; index += 2) {
    const name = args[index];
    if (!["--audio", "--volume", "--speed"].includes(name) ||
        name in values || index + 1 >= args.length) {
      throw new Error("Usage: play-timed-speech.mjs --audio ABS --volume NUMBER --speed NUMBER");
    }
    values[name] = args[index + 1];
  }
  const audio = values["--audio"];
  const volume = Number(values["--volume"]);
  const speed = Number(values["--speed"]);
  if (typeof audio !== "string" || !isAbsolute(audio) || audio.includes("\0") ||
      !values["--volume"]?.trim() || !Number.isFinite(volume) || volume < 0 || volume > 100 ||
      !values["--speed"]?.trim() || !Number.isFinite(speed) || speed < 0.01 || speed > 100) {
    throw new Error("Audio must be absolute, volume 0–100, and speed 0.01–100.");
  }
  return { audio, volume, speed };
}

export function validateTiming(value, audioHash) {
  if (!value || value.version !== 1 || typeof value.audioHash !== "string" ||
      !/^[a-f0-9]{64}$/i.test(value.audioHash) ||
      value.audioHash.toLowerCase() !== audioHash.toLowerCase()) {
    throw new Error("Unsupported timing version or stale/invalid audio hash.");
  }
  if (typeof value.text !== "string" || !value.text.trim() ||
      !Array.isArray(value.words) || value.words.length === 0) {
    throw new Error("Timing must contain original text and word boundaries.");
  }
  let previousOffset = 0;
  let previousTime = 0;
  const words = value.words.map((word) => {
    if (!word || !Number.isFinite(word.startMs) || word.startMs < previousTime ||
        !Number.isSafeInteger(word.endOffset) || word.endOffset <= previousOffset ||
        word.endOffset > value.text.length) {
      throw new Error("Timing words must have ordered finite times and increasing UTF-16 offsets.");
    }
    const preceding = value.text.charCodeAt(word.endOffset - 1);
    const following = value.text.charCodeAt(word.endOffset);
    if (preceding >= 0xd800 && preceding <= 0xdbff && following >= 0xdc00 && following <= 0xdfff) {
      throw new Error("Timing offset splits a UTF-16 surrogate pair.");
    }
    previousOffset = word.endOffset;
    previousTime = word.startMs;
    return { startMs: word.startMs, endOffset: word.endOffset };
  });
  if (previousOffset !== value.text.length) throw new Error("Timing does not cover the full text.");
  return { text: value.text, words };
}

async function readBounded(path, limit, onChunk) {
  const file = await open(path, constants.O_RDONLY | constants.O_NONBLOCK);
  try {
    const stat = await file.stat();
    if (!stat.isFile() || stat.size > limit) throw new Error(`File is not regular or exceeds ${limit} bytes.`);
    const chunks = [];
    let total = 0;
    while (true) {
      const buffer = Buffer.alloc(Math.min(64 * 1024, limit + 1 - total));
      const { bytesRead } = await file.read(buffer);
      if (!bytesRead) break;
      total += bytesRead;
      if (total > limit) throw new Error(`File exceeds ${limit} bytes.`);
      if (onChunk) onChunk(buffer.subarray(0, bytesRead));
      else chunks.push(buffer.subarray(0, bytesRead));
    }
    return Buffer.concat(chunks);
  } finally {
    await file.close();
  }
}

export async function loadTiming(audio) {
  let bytes;
  try {
    bytes = await readBounded(`${audio}.timing.json`, MAX_TIMING_BYTES);
  } catch (error) {
    if (error.code === "ENOENT") return { reason: "missing-timing" };
    return { reason: "invalid-timing", diagnostic: error.message };
  }
  try {
    const metadata = JSON.parse(bytes.toString("utf8"));
    const hash = createHash("sha256");
    await readBounded(audio, MAX_AUDIO_BYTES, (chunk) => hash.update(chunk));
    return { timing: validateTiming(metadata, hash.digest("hex")) };
  } catch (error) {
    return { reason: "invalid-timing", diagnostic: error.message };
  }
}

export function mpvArguments({ audio, volume, speed }, socketPath) {
  const args = ["--no-video", "--really-quiet", `--volume=${volume}`, `--speed=${speed}`];
  if (socketPath) {
    args.push("--pause=no", "--idle=no", "--keep-open=no", "--loop-file=no",
      `--input-ipc-server=${socketPath}`);
  }
  return [...args, "--", audio];
}

function observePosition(socketPath, emit, diagnostic) {
  let socket;
  let retry;
  let deadline;
  let stopped = false;
  let connected = false;
  let buffer = "";
  const stop = () => {
    stopped = true;
    clearTimeout(retry);
    clearTimeout(deadline);
    socket?.destroy();
  };
  const fallback = (reason) => {
    if (stopped) return;
    stop();
    diagnostic(`Playback timing unavailable: ${reason}. Audio continues.`);
    emit({ type: "fallback", reason });
  };
  const attempt = () => {
    if (stopped) return;
    socket = connect(socketPath);
    socket.on("connect", () => {
      connected = true;
      socket.write(`${JSON.stringify({ command: ["observe_property", 1, "time-pos"], request_id: 1 })}\n`);
    });
    socket.on("data", (chunk) => {
      buffer += chunk.toString("utf8");
      if (buffer.length > 64 * 1024) return fallback("invalid-ipc-response");
      let newline;
      while (!stopped && (newline = buffer.indexOf("\n")) >= 0) {
        const line = buffer.slice(0, newline);
        buffer = buffer.slice(newline + 1);
        let message;
        try {
          message = JSON.parse(line);
        } catch {
          return fallback("invalid-ipc-response");
        }
        if (message?.request_id === 1 && message.error && message.error !== "success") {
          return fallback("unsupported-ipc");
        }
        if (message?.event === "end-file" && message.reason === "eof") {
          stop();
          return;
        }
        if (message?.event === "property-change" && message.name === "time-pos" &&
            typeof message.data === "number" && Number.isFinite(message.data) &&
            message.data >= 0 && Number.isFinite(message.data * 1000)) {
          clearTimeout(deadline);
          emit({ type: "position", positionMs: message.data * 1000 });
        }
      }
    });
    socket.on("error", () => {
      // Startup races are normal: mpv creates its socket after it starts.
    });
    socket.on("close", () => {
      if (stopped) return;
      if (connected) fallback("ipc-disconnected");
      else retry = setTimeout(attempt, IPC_RETRY_MS);
    });
  };
  deadline = setTimeout(() => fallback("ipc-unavailable"), IPC_TIMEOUT_MS);
  attempt();
  return stop;
}

export async function playTimedSpeech(options, {
  emit = (event) => process.stdout.write(`${JSON.stringify(event)}\n`),
  diagnostic = (message) => process.stderr.write(`${message}\n`),
} = {}) {
  let child;
  let directory;
  let socketPath;
  let stopObserver;
  let stopTimer;
  let interrupted;
  let playbackError = false;
  const interrupt = (signal) => {
    if (interrupted) return;
    interrupted = signal;
    stopObserver?.();
    if (child && child.exitCode === null && child.signalCode === null) {
      child.kill(signal);
      stopTimer = setTimeout(() => child.kill("SIGKILL"), STOP_TIMEOUT_MS);
    }
  };
  const terminate = () => interrupt("SIGTERM");
  const cancel = () => interrupt("SIGINT");
  const stdoutError = (error) => {
    diagnostic(`Playback event output failed: ${error.message}`);
    playbackError = true;
    interrupt("SIGTERM");
  };
  process.on("SIGTERM", terminate);
  process.on("SIGINT", cancel);
  process.stdout.on("error", stdoutError);
  try {
    const metadata = await loadTiming(options.audio);
    if (interrupted) return interrupted === "SIGINT" ? 130 : 143;
    if (metadata.timing) {
      emit({ type: "timing", ...metadata.timing });
      try {
        const runtime = process.env.XDG_RUNTIME_DIR;
        const base = runtime && isAbsolute(runtime) ? runtime : join(homedir(), ".cache", "learn-omarchy");
        if (base !== runtime) await mkdir(base, { recursive: true, mode: 0o700 });
        directory = await mkdtemp(join(base, "learn-speech-"));
        socketPath = join(directory, "mpv.sock");
        if (Buffer.byteLength(socketPath) > 103) {
          socketPath = undefined;
          throw new Error("Runtime directory is too long for a Unix socket path.");
        }
      } catch (error) {
        diagnostic(`Playback timing unavailable: ${error.message}. Audio continues.`);
        emit({ type: "fallback", reason: "ipc-unavailable" });
      }
    } else {
      if (metadata.diagnostic) diagnostic(`Invalid speech timing: ${metadata.diagnostic}`);
      emit({ type: "fallback", reason: metadata.reason });
    }
    if (interrupted) return interrupted === "SIGINT" ? 130 : 143;
    const result = await new Promise((resolve) => {
      child = spawn("mpv", mpvArguments(options, socketPath), { stdio: ["ignore", "ignore", "pipe"] });
      child.stderr.on("data", (chunk) => diagnostic(chunk.toString("utf8").trimEnd()));
      child.on("error", (error) => {
        diagnostic(`Unable to start mpv: ${error.message}`);
        playbackError = true;
      });
      child.on("close", (code, signal) => {
        stopObserver?.();
        clearTimeout(stopTimer);
        if (interrupted) resolve(interrupted === "SIGINT" ? 130 : 143);
        else if (playbackError) resolve(1);
        else if (code !== null) {
          if (code !== 0) diagnostic(`mpv exited with status ${code}.`);
          resolve(code);
        } else {
          diagnostic(`mpv terminated by ${signal}.`);
          resolve(signal === "SIGINT" ? 130 : signal === "SIGTERM" ? 143 : 1);
        }
      });
      if (socketPath) stopObserver = observePosition(socketPath, emit, diagnostic);
    });
    return result;
  } finally {
    stopObserver?.();
    clearTimeout(stopTimer);
    if (socketPath) await unlink(socketPath).catch((error) => {
      if (error.code !== "ENOENT") diagnostic(`Unable to remove playback socket: ${error.message}`);
    });
    if (directory) await rmdir(directory).catch((error) => diagnostic(`Unable to remove playback directory: ${error.message}`));
    process.off("SIGTERM", terminate);
    process.off("SIGINT", cancel);
    process.stdout.off("error", stdoutError);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    process.exitCode = await playTimedSpeech(parseArguments(process.argv.slice(2)));
  } catch (error) {
    console.error(`Speech playback failed: ${error.message}`);
    process.exitCode = 1;
  }
}
