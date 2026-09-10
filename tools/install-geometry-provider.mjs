#!/usr/bin/env node
import { createHash, randomUUID } from "node:crypto";
import { lstat, mkdir, readFile, readdir, rename, rm, writeFile } from "node:fs/promises";
import { dirname, isAbsolute, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import { setTimeout } from "node:timers/promises";

const id = "learn-omarchy.geometry";
const ownerFile = ".learn-omarchy-owner.json";
const source = fileURLToPath(new URL(`../integrations/omarchy/${id}/`, import.meta.url));
const hash = (content) => createHash("sha256").update(content).digest("hex");
const args = process.argv.slice(2);
const quiet = args.includes("--quiet");
const report = message => { if (!quiet) console.log(message); };

function command(program, args) {
  const result = spawnSync(program, args, { encoding: "utf8", timeout: 15000 });
  if (result.error || result.status !== 0) {
    throw new Error(`${program} ${args.join(" ")} failed: ${result.error?.message || result.stderr || result.stdout}`);
  }
  return result.stdout;
}

async function stat(path) {
  try { return await lstat(path); }
  catch (error) { if (error.code === "ENOENT") return null; throw error; }
}

async function safeDirectory(path) {
  const parent = dirname(path);
  if (parent !== path) await safeDirectory(parent);
  const info = await stat(path);
  if (info && (!info.isDirectory() || info.isSymbolicLink())) {
    throw new Error(`Refusing non-directory or symlink: ${path}`);
  }
}

async function payload(folder, installed = false) {
  const manifestPath = join(folder, "manifest.json");
  const manifestStat = await lstat(manifestPath);
  if (!manifestStat.isFile() || manifestStat.isSymbolicLink()) throw new Error(`Refusing unexpected plugin entry: ${manifestPath}`);
  const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
  const entryPoint = manifest?.entryPoints?.service;
  const revision = installed && typeof entryPoint === "string"
    ? entryPoint.match(/^releases\/([a-f0-9]{64})\/Service\.qml$/)?.[1] : null;
  if (manifest?.id !== id || manifest.schemaVersion !== 1
    || JSON.stringify(manifest.kinds) !== '["service"]'
    || Object.keys(manifest.entryPoints || {}).length !== 1
    || (entryPoint !== "Service.qml" && !revision)) {
    throw new Error("Plugin manifest identity does not match the read-only service");
  }
  const files = {};
  const codePrefix = revision ? `releases/${revision}/` : "";
  async function walk(relative = "") {
    for (const name of (await readdir(join(folder, relative))).sort()) {
      const key = relative ? `${relative}/${name}` : name;
      const path = join(folder, key);
      const info = await lstat(path);
      if (info.isSymbolicLink()) throw new Error(`Refusing symlink plugin entry: ${path}`);
      if (installed && key === ownerFile && info.isFile()) continue;
      if (info.isDirectory() && revision && (key === "releases" || key === `releases/${revision}`)) {
        await walk(key);
      } else if (info.isFile() && (key === "manifest.json"
        || (key.startsWith(codePrefix) && /^[A-Za-z0-9_-][A-Za-z0-9._-]*\.(qml|js)$/.test(key.slice(codePrefix.length))))) {
        files[key] = await readFile(path);
      } else {
        throw new Error(`Refusing unexpected plugin entry: ${path}`);
      }
    }
  }
  await walk();
  if (!files[entryPoint]) throw new Error("Plugin service entry point is missing");
  return files;
}

function fingerprints(files) {
  return Object.fromEntries(Object.keys(files).sort().map((name) => [name, hash(files[name])]));
}

function releasePayload(sourceFiles) {
  const code = Object.fromEntries(Object.entries(sourceFiles).filter(([name]) => name !== "manifest.json"));
  // Every QML/JS dependency gets a fresh URL together. Generated metadata and
  // ownership bookkeeping never affect the deterministic code revision.
  const revision = hash(JSON.stringify(fingerprints(code)));
  const prefix = `releases/${revision}/`;
  const manifest = JSON.parse(sourceFiles["manifest.json"].toString());
  manifest.entryPoints.service = `${prefix}Service.qml`;
  return {
    "manifest.json": Buffer.from(JSON.stringify(manifest, null, 2) + "\n"),
    ...Object.fromEntries(Object.entries(code).map(([name, content]) => [`${prefix}${name}`, content])),
  };
}

function sameFingerprints(left, right) {
  if (!left || typeof left !== "object" || Array.isArray(left)) return false;
  const keys = Object.keys(right);
  return Object.keys(left).length === keys.length && keys.every((key) => left[key] === right[key]);
}

function listed() {
  const plugins = JSON.parse(command("omarchy", ["plugin", "list", "--json"]));
  if (!Array.isArray(plugins)) throw new Error("Unsupported Omarchy plugin discovery response");
  const matches = plugins.filter((plugin) => plugin && plugin.id === id);
  if (matches.length > 1) throw new Error(`Ambiguous plugin registration for ${id}`);
  return matches[0];
}

function checkRegistration(plugin, target) {
  if (!plugin) return;
  if (!Array.isArray(plugin.kinds) || !plugin.kinds.includes("service") || plugin.firstParty === true ||
      (plugin.manifestPath && resolve(plugin.manifestPath) !== join(target, "manifest.json"))) {
    throw new Error(`Plugin id ${id} is registered to a conflicting integration`);
  }
}

function serviceReadiness() {
  // listPlugins.active identifies the selected bar, not a running service.
  const result = spawnSync("omarchy-shell", ["learnGeometry", "capabilities"], {
    encoding: "utf8", timeout: 2000, maxBuffer: 64 * 1024,
  });
  if (result.error || result.status !== 0) {
    return { ready: false, reason: `Geometry service is not responding: ${
      result.error?.message || result.stderr?.trim() || result.stdout?.trim() || `exit ${result.status}`}` };
  }
  let capabilities;
  try { capabilities = JSON.parse(result.stdout); }
  catch (error) {
    if (!(error instanceof SyntaxError)) throw error;
    return { ready: false, reason: "Geometry service returned invalid capability JSON." };
  }
  if (!capabilities || typeof capabilities !== "object" || Array.isArray(capabilities) ||
      !["shellAvailable", "barAvailable", "slotsAvailable", "windowMappingAvailable"]
        .every(key => typeof capabilities[key] === "boolean") ||
      typeof capabilities.activeBarId !== "string" || typeof capabilities.manifestId !== "string") {
    return { ready: false, reason: "Geometry service returned an unsupported capability response." };
  }
  return capabilities.shellAvailable
    ? { ready: true }
    : { ready: false, reason: "Geometry service is waiting for its desktop shell connection." };
}

async function ownedPayload(target) {
  const ownerPath = join(target, ownerFile);
  const ownerStat = await stat(ownerPath);
  if (!ownerStat?.isFile() || ownerStat.isSymbolicLink()) throw new Error(`Refusing unowned plugin: ${target}`);
  const owner = JSON.parse(await readFile(ownerPath, "utf8"));
  const installed = await payload(target, true);
  if (owner.id !== id || owner.installer !== "learn-omarchy" || owner.version !== 1
    || !sameFingerprints(owner.files, fingerprints(installed))) {
    throw new Error(`Refusing locally modified or conflicting plugin: ${target}`);
  }
  return installed;
}

async function install() {
  if (args.length === 1 && ["--help", "-h"].includes(args[0])) {
    console.log("Usage: node tools/install-geometry-provider.mjs [--quiet] [--remove]\nPrepares the bundled read-only integration for the current user. --remove safely removes an unchanged managed integration. Never use sudo.");
    return;
  }
  if (new Set(args).size !== args.length || args.some(arg => !["--quiet", "--remove"].includes(arg)))
    throw new Error("Unknown argument; use --help");
  if (process.getuid?.() === 0) throw new Error("Do not run this user-level installer as root or with sudo");
  if (!process.env.HOME || !isAbsolute(process.env.HOME)) throw new Error("HOME must be an absolute user home");
  const plugins = join(resolve(process.env.HOME), ".config", "omarchy", "plugins");
  const target = join(plugins, id);
  await safeDirectory(target);
  const existing = await stat(target);
  const installed = existing ? await ownedPayload(target) : null;
  if (args.includes("--remove")) {
    if (!existing) { report("No managed integration is installed."); return; }
    checkRegistration(listed(), target);
    await ownedPayload(target);
    // Omarchy disables the service and backs up non-git plugin folders.
    command("omarchy", ["plugin", "remove", id, "--yes"]);
    if (await stat(target)) throw new Error("The managed integration folder was not removed");
    for (let attempt = 0; attempt < 20; attempt++) {
      if (!listed()) { report(`Removed managed integration ${id}; learning progress is unchanged.`); return; }
      await setTimeout(100);
    }
    throw new Error("The integration was removed, but the desktop has not confirmed it was unloaded");
  }
  const files = releasePayload(await payload(source));
  const sums = fingerprints(files);
  const registered = listed();
  checkRegistration(registered, target);
  if (!existing && registered) throw new Error(`Plugin id ${id} is already registered elsewhere; refusing conflict`);
  const unchanged = installed && sameFingerprints(fingerprints(installed), sums);
  if (unchanged && registered?.enabled === true && serviceReadiness().ready) {
    report(`Integration ${id} is already ready.`);
    return;
  }
  const help = command("omarchy", ["plugin", "--help"]);
  if (!help.includes("omarchy plugin enable") || !help.includes("omarchy plugin list")) {
    throw new Error("This Omarchy version does not expose supported plugin enable/list commands");
  }
  command("omarchy", ["plugin", "validate", source]);
  if (!unchanged) {
    await mkdir(plugins, { recursive: true });
    const stage = join(plugins, `.${id}.stage-${randomUUID()}`);
    let backup;
    await mkdir(stage, { mode: 0o700 });
    try {
      for (const [name, content] of Object.entries(files)) {
        await mkdir(dirname(join(stage, name)), { recursive: true });
        await writeFile(join(stage, name), content, { flag: "wx", mode: 0o644 });
      }
      await writeFile(join(stage, ownerFile), JSON.stringify({ id, installer: "learn-omarchy", version: 1, files: sums }, null, 2) + "\n",
        { flag: "wx", mode: 0o600 });
      command("omarchy", ["plugin", "validate", stage]);
      if (existing) {
        if (!sameFingerprints(fingerprints(await ownedPayload(target)), fingerprints(installed)))
          throw new Error("The managed integration changed during setup; refusing to overwrite it");
        backup = join(plugins, `.${id}.backup-${randomUUID()}`);
        await rename(target, backup);
      } else if (await stat(target)) {
        throw new Error(`Plugin appeared during installation; refusing to overwrite ${target}`);
      }
      try { await rename(stage, target); }
      catch (error) { if (backup) await rename(backup, target); throw error; }
      if (backup) report(`Previous owned version preserved at ${backup}`);
    } finally {
      await rm(stage, { recursive: true, force: true });
    }
  }
  // This is the same rescan used by Omarchy's own plugin installer. It changes
  // plugin discovery only; activation uses the supported plugin manager.
  command("omarchy-shell", ["shell", "rescanPlugins"]);
  let plugin;
  for (let attempt = 0; attempt < 20; attempt++) {
    plugin = listed();
    if (plugin) break;
    await setTimeout(100);
  }
  checkRegistration(plugin, target);
  if (!plugin) {
    throw new Error(`Installed ${target}, but the running shell did not discover the service. It was not enabled.`);
  }
  command("omarchy", ["plugin", "enable", id]);
  let readiness = { ready: false, reason: "The integration is not enabled." };
  for (let attempt = 0; attempt < 20; attempt++) {
    const active = listed();
    checkRegistration(active, target);
    readiness = active?.enabled === true ? serviceReadiness()
      : { ready: false, reason: "The integration is not enabled." };
    if (readiness.ready) {
      report(`Installed and enabled ${id} at ${target}`);
      return;
    }
    await setTimeout(100);
  }
  throw new Error(`The desktop integration isn't ready. ${readiness.reason}`);
}

install().catch((error) => {
  console.error(`Geometry provider installation failed: ${error.message}`);
  process.exitCode = 1;
});
