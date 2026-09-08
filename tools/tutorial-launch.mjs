import { spawn, fork, execFileSync } from "node:child_process";
import { access, lstat, mkdtemp, readFile, realpath, rm } from "node:fs/promises";
import { constants } from "node:fs";
import { basename, delimiter, isAbsolute, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const TOKEN_PATTERN = /^[a-zA-Z0-9-]{16,128}$/;
const KINDS = new Set(["terminal", "browser", "activity"]);

export function classifyLaunchCommand(command) {
  if (!Array.isArray(command) || !command.length || command.some(argument => typeof argument !== "string")) {
    throw new Error("Unsupported tutorial launch command.");
  }
  const forms = [
    ["terminal", ["omarchy", "launch", "terminal"]],
    ["terminal", ["omarchy-launch-terminal"]],
    ["browser", ["omarchy", "launch", "browser"]],
    ["browser", ["omarchy-launch-browser"]],
    ["activity", ["omarchy-launch-or-focus-tui", "btop"]],
    ["activity", ["btop"]],
    ["activity", ["xdg-terminal-exec", "btop"]],
    ["activity", ["xdg-terminal-exec", "-e", "btop"]],
    ["activity", ["xdg-terminal-exec", "--app-id=org.learn-omarchy.toolbox", "--title=Learn Omarchy activity", "-e", "btop"]],
  ];
  for (const [kind, form] of forms) {
    if (command.length === form.length && command.every((argument, index) => argument === form[index])) return kind;
  }
  throw new Error("Unsupported tutorial launch command. No application was launched.");
}

export function parseArguments(args) {
  const options = {};
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--") {
      const kind = classifyLaunchCommand(args.slice(i + 1));
      if (options.kind && options.kind !== kind) throw new Error("Tutorial launch kind does not match the native command.");
      options.kind = kind;
      break;
    }
    if (args[i] === "--check" && !options.check) {
      options.check = true;
      continue;
    }
    if (args[i] === "--detach" && !options.detach) {
      options.detach = true;
      continue;
    }
    const flags = { "--kind": "kind", "--token": "token", "--profile-root": "profileRoot" };
    const key = Object.hasOwn(flags, args[i]) ? flags[args[i]] : undefined;
    if (!key || options[key] !== undefined || !args[i + 1] || args[i + 1].startsWith("--")) {
      throw new Error("Usage: tutorial-launch.mjs --token TOKEN [--kind terminal|browser|activity] [--check|--detach] [--profile-root DIRECTORY] [-- NATIVE_COMMAND ...]");
    }
    options[key] = args[++i];
  }
  if (options.check && options.detach) throw new Error("--check and --detach cannot be combined.");
  validateOptions(options);
  return options;
}

function validateOptions({ kind, token }) {
  if (!KINDS.has(kind)) throw new Error("Unsupported tutorial launch kind.");
  if (typeof token !== "string" || !TOKEN_PATTERN.test(token)) throw new Error("Invalid tutorial launch token.");
}

// Desktop Exec is not a shell command. Only double-quoted words and escaped
// characters are decoded; field codes are checked separately by the adapter.
export function parseDesktopExec(value) {
  const result = [];
  let word = "", quoted = false, started = false;
  for (let i = 0; i < value.length; i++) {
    const character = value[i];
    if (character === "\\") {
      if (++i === value.length) throw new Error("Incomplete desktop Exec escape.");
      word += value[i];
      started = true;
    } else if (character === '"') {
      quoted = !quoted;
      started = true;
    } else if (/\s/.test(character) && !quoted) {
      if (started) result.push(word);
      word = "";
      started = false;
    } else {
      if (!quoted && /['`$;|&<>]/.test(character)) throw new Error("Unsupported desktop Exec syntax.");
      word += character;
      started = true;
    }
  }
  if (quoted) throw new Error("Unclosed desktop Exec quote.");
  if (started) result.push(word);
  if (!result[0] || result.some(part => part.includes("\0"))) throw new Error("Invalid desktop Exec.");
  return result;
}

export function desktopCommand(content) {
  let main = false;
  const fields = new Map();
  for (const line of content.split(/\r?\n/)) {
    if (line.startsWith("[")) main = line.trim() === "[Desktop Entry]";
    if (!main || line.startsWith("#") || !line.includes("=")) continue;
    const index = line.indexOf("=");
    const key = line.slice(0, index);
    if (!["Type", "Hidden", "Exec"].includes(key)) continue;
    if (fields.has(key)) throw new Error("Ambiguous desktop entry.");
    fields.set(key, line.slice(index + 1));
  }
  if (fields.get("Type") !== "Application" || fields.get("Hidden") === "true" || !fields.get("Exec")) {
    throw new Error("The configured browser has no usable desktop Exec.");
  }
  return parseDesktopExec(fields.get("Exec"));
}

function query(command, args, env) {
  return execFileSync(command, args, {
    env, encoding: "utf8", timeout: 5000, maxBuffer: 128 * 1024, stdio: ["ignore", "pipe", "pipe"],
  });
}

async function executable(command, env) {
  const paths = isAbsolute(command) ? [command]
    : (env.PATH || "/usr/local/bin:/usr/bin:/bin").split(delimiter).filter(Boolean).map(dir => join(dir, command));
  for (const path of paths) {
    try {
      await access(path, constants.X_OK);
      return resolve(path);
    } catch (error) {
      if (error.code !== "ENOENT" && error.code !== "ENOTDIR") throw error;
    }
  }
  throw new Error(`Required executable is unavailable: ${command}`);
}

async function defaultBrowser(env, runQuery, read) {
  const queryEnv = { ...env };
  delete queryEnv.BROWSER;
  let id = "";
  try { id = runQuery("xdg-settings", ["get", "default-web-browser"], queryEnv).trim(); }
  catch (error) {
    if (error.code !== "ENOENT" && !Number.isInteger(error.status)) throw error;
  }
  if (!id) {
    try { id = runQuery("xdg-mime", ["query", "default", "x-scheme-handler/https"], queryEnv).trim(); }
    catch (error) {
      if (error.code !== "ENOENT" && !Number.isInteger(error.status)) throw error;
    }
  }
  if (!/^[a-zA-Z0-9][a-zA-Z0-9_.-]*\.desktop$/.test(id)) {
    throw new Error("Cannot safely resolve the configured browser desktop ID. Open it yourself, or Skip.");
  }
  const home = env.HOME || "";
  const directories = [
    env.XDG_DATA_HOME || (home && join(home, ".local/share")),
    ...(env.XDG_DATA_DIRS || "/usr/local/share:/usr/share").split(delimiter),
  ].filter(path => path && isAbsolute(path));
  for (const directory of directories) {
    try { return desktopCommand(await read(join(directory, "applications", id), "utf8")); }
    catch (error) { if (error.code !== "ENOENT") throw error; }
  }
  throw new Error(`The configured browser desktop entry (${id}) is unavailable. Open it yourself, or Skip.`);
}

export async function prepareLaunch(options, dependencies = {}) {
  validateOptions(options);
  const env = dependencies.env || process.env;
  const runQuery = dependencies.query || query;
  const findExecutable = dependencies.executable || (command => executable(command, env));
  const appId = `org.learn-omarchy.${options.kind}.t${options.token}`;
  if (options.kind !== "browser") {
    let command;
    try {
      command = runQuery("xdg-terminal-exec", ["--print-cmd=\\0"], env).split("\0");
      if (command.at(-1) === "") command.pop();
    } catch {
      throw new Error("Cannot resolve the configured terminal safely. Open it yourself, or Skip.");
    }
    const name = basename(command[0] || "");
    let args;
    if (name === "ghostty" && command.slice(1).every(arg => /^--gtk-single-instance=(true|false|detect)$/.test(arg))) {
      args = ["--gtk-single-instance=false", `--class=${appId}`, "--initial-window=true", "--quit-after-last-window-closed=true"];
      if (options.kind === "activity") args.push("--title=Learn Omarchy activity", "--window-width=120", "--window-height=36", "-e", "btop");
    } else if (name === "foot" && command.length === 1) {
      args = [`--app-id=${appId}`];
      if (options.kind === "activity") args.push("--title=Learn Omarchy activity", "--window-size-chars=120x36", "btop");
    } else {
      throw new Error(`The configured terminal (${name || "unknown"}) has no supported independent launch adapter. Open it yourself, or Skip.`);
    }
    if (options.kind === "activity") await findExecutable("btop");
    return { kind: options.kind, token: options.token, appId, executable: await findExecutable(command[0]), args };
  }
  const command = await defaultBrowser(env, runQuery, dependencies.readFile || readFile);
  const name = basename(command[0]);
  const binaries = {
    "google-chrome": "/opt/google/chrome/chrome",
    "google-chrome-stable": "/opt/google/chrome/chrome",
    "chromium": "/usr/lib/chromium/chromium",
    "chromium-browser": "/usr/lib/chromium/chromium",
  };
  // Bypass launcher scripts that load user flags (including profile selection
  // and background mode). Never silently substitute another browser family.
  if (!Object.hasOwn(binaries, name) ||
      ![name, `/usr/bin/${name}`].includes(command[0]) ||
      !command.slice(1).every(arg => ["%u", "%U", "%f", "%F", "--new-window", "--incognito"].includes(arg))) {
    throw new Error(`The configured browser (${name}) has no supported isolated launch adapter. Open it yourself, or Skip; your existing browser was not changed.`);
  }
  return {
    kind: options.kind, token: options.token,
    executable: await findExecutable(binaries[name]),
    args: ["--no-first-run", "--no-default-browser-check", "--disable-background-mode", "--disable-sync", "--disable-background-networking", "--new-window", "about:blank"],
    profileRoot: resolve(options.profileRoot || "."),
  };
}

export async function launchPrepared(plan, dependencies = {}) {
  validateOptions(plan);
  const env = { ...(dependencies.env || process.env), LEARN_OMARCHY_WINDOW_TOKEN: plan.token };
  const spawnProcess = dependencies.spawn || spawn;
  const signalSource = dependencies.signals || process;
  let profile, profileIdentity, child;
  const args = [...plan.args];
  if (plan.kind === "browser") {
    profile = await mkdtemp(join(await realpath(plan.profileRoot), ".learn-omarchy-browser-"));
    profileIdentity = await lstat(profile);
    args.unshift(`--user-data-dir=${profile}`);
    env.XDG_CONFIG_HOME = profile;
    delete env.CHROME_USER_FLAGS;
    delete env.CHROMIUM_FLAGS;
  }
  async function cleanup() {
    if (!profile) return;
    try {
      const current = await lstat(profile);
      if (!current.isDirectory() || current.isSymbolicLink() ||
          current.dev !== profileIdentity.dev || current.ino !== profileIdentity.ino ||
          await realpath(profile) !== profile) {
        throw new Error("Refusing cleanup of a replaced tutorial browser profile.");
      }
      await rm(profile, { recursive: true, force: true });
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
  }
  const handlers = new Map();
  let cancellationTimer;
  try {
    // The helper is detached by the caller, not by its child. Staying attached
    // to this fresh process lets the helper clean up only its own profile.
    child = spawnProcess(plan.executable, args, { env, stdio: ["ignore", "ignore", "pipe"], shell: false });
    child.once("spawn", () => dependencies.onStarted?.({ ok: true, state: "spawned", kind: plan.kind, appId: plan.appId, pid: child.pid }));
    let diagnostics = "";
    child.stderr?.on("data", data => { diagnostics = (diagnostics + data.toString()).slice(-4096); });
    for (const signal of ["SIGTERM", "SIGINT", "SIGHUP"]) {
      const handler = () => {
        child.kill(signal);
        if (!cancellationTimer) {
          cancellationTimer = setTimeout(() => child.kill("SIGKILL"), 5000);
          cancellationTimer.unref();
        }
      };
      handlers.set(signal, handler);
      signalSource.on(signal, handler);
    }
    return await new Promise((resolveResult, reject) => {
      child.once("error", reject);
      child.once("close", (code, signal) => {
        if (code !== 0 && !signal) reject(new Error(`Tutorial ${plan.kind} exited (${code}): ${diagnostics.trim() || "no diagnostic output"}`));
        else resolveResult({ code: code ?? 1, signal, appId: plan.appId });
      });
    });
  } finally {
    clearTimeout(cancellationTimer);
    for (const [signal, handler] of handlers) signalSource.removeListener(signal, handler);
    await cleanup();
  }
}

export async function launchDetached(options, dependencies = {}) {
  validateOptions(options);
  const forkWorker = dependencies.fork || fork;
  const signals = dependencies.signals || process;
  const args = ["--worker", "--kind", options.kind, "--token", options.token];
  if (options.profileRoot) args.push("--profile-root", resolve(options.profileRoot));
  const worker = forkWorker(fileURLToPath(import.meta.url), args, {
    detached: true, stdio: ["ignore", "ignore", "ignore", "ipc"],
  });
  return await new Promise((resolveResult, reject) => {
    const handlers = new Map();
    const timer = setTimeout(() => {
      worker.kill("SIGTERM");
      finish(new Error("Tutorial launch timed out before the application started."));
    }, 15000);
    function finish(error, result) {
      clearTimeout(timer);
      for (const [signal, handler] of handlers) signals.removeListener(signal, handler);
      worker.removeListener("message", onMessage);
      worker.removeListener("error", onError);
      worker.removeListener("exit", onExit);
      if (worker.connected) worker.disconnect();
      worker.unref();
      if (error) reject(error);
      else resolveResult(result);
    }
    function onMessage(message) {
      if (message?.ok === true && message.state === "spawned" &&
          Number.isSafeInteger(message.pid) && message.pid > 0) finish(null, message);
      else if (message?.ok === false) finish(new Error(message.error || "Tutorial launch failed."));
    }
    function onError(error) { finish(error); }
    function onExit() { finish(new Error("Tutorial launch worker exited before the application started.")); }
    for (const signal of ["SIGTERM", "SIGINT", "SIGHUP"]) {
      const handler = () => {
        worker.kill(signal);
        finish(new Error("Tutorial launch cancelled before startup was acknowledged."));
      };
      handlers.set(signal, handler);
      signals.on(signal, handler);
    }
    worker.on("message", onMessage);
    worker.once("error", onError);
    worker.once("exit", onExit);
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const workerMode = process.argv[2] === "--worker" && typeof process.send === "function";
  try {
    const options = parseArguments(process.argv.slice(workerMode ? 3 : 2));
    if (options.detach) {
      console.log(JSON.stringify(await launchDetached(options)));
    } else {
      const plan = await prepareLaunch(options);
      if (options.check) {
        console.log(JSON.stringify({ ok: true, kind: plan.kind, appId: plan.appId }));
      } else {
        const result = await launchPrepared(plan, {
          onStarted: workerMode ? message => {
            if (process.connected) process.send(message);
          } : undefined,
        });
        process.exitCode = result.code;
      }
    }
  } catch (error) {
    const result = { ok: false, error: error.message };
    if (workerMode && process.connected) process.send(result);
    else console.error(JSON.stringify(result));
    process.exitCode = 2;
  }
  if (workerMode && process.connected) process.disconnect();
}
