#!/usr/bin/env node
// Removes the retired learn-omarchy.geometry shell plugin that earlier releases
// installed. Omarchy 4.0.3+ no longer gives third-party plugins the bar and
// menu objects it measured, so it can't work. Only an unchanged copy that this
// app installed is removed; anything else is left alone.
import { createHash } from "node:crypto";
import { lstat, readFile, readdir } from "node:fs/promises";
import { isAbsolute, join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { setTimeout } from "node:timers/promises";

const id = "learn-omarchy.geometry";
const ownerFile = ".learn-omarchy-owner.json";
const hash = content => createHash("sha256").update(content).digest("hex");
const args = process.argv.slice(2);
const quiet = args.includes("--quiet");
const report = message => { if (!quiet) console.log(message); };

function command(program, commandArgs) {
  const result = spawnSync(program, commandArgs, { encoding: "utf8", timeout: 15000 });
  if (result.error || result.status !== 0)
    throw new Error(`${program} ${commandArgs.join(" ")} failed: ${result.error?.message || result.stderr || result.stdout}`);
  return result.stdout;
}

async function stat(path) {
  try { return await lstat(path); }
  catch (error) { if (error.code === "ENOENT") return null; throw error; }
}

async function installedFiles(folder) {
  const manifest = JSON.parse(await readFile(join(folder, "manifest.json"), "utf8"));
  const revision = String(manifest?.entryPoints?.service || "").match(/^releases\/([a-f0-9]{64})\/Service\.qml$/)?.[1];
  if (manifest?.id !== id || !revision) throw new Error(`Refusing unrecognized plugin: ${folder}`);
  const files = {};
  async function walk(relative) {
    for (const name of (await readdir(join(folder, relative))).sort()) {
      const key = relative ? `${relative}/${name}` : name;
      const info = await lstat(join(folder, key));
      if (!relative && key === ownerFile && info.isFile()) continue;
      if (info.isDirectory() && !info.isSymbolicLink() && (key === "releases" || key === `releases/${revision}`)) await walk(key);
      else if (info.isFile() && (key === "manifest.json" || key.startsWith(`releases/${revision}/`))) files[key] = hash(await readFile(join(folder, key)));
      else throw new Error(`Refusing unexpected plugin entry: ${join(folder, key)}`);
    }
  }
  await walk("");
  return files;
}

async function requireOwnedAndUnchanged(folder) {
  const ownerPath = join(folder, ownerFile);
  const ownerStat = await stat(ownerPath);
  if (!ownerStat?.isFile() || ownerStat.isSymbolicLink()) throw new Error(`Refusing unowned plugin: ${folder}`);
  const owner = JSON.parse(await readFile(ownerPath, "utf8"));
  const files = await installedFiles(folder);
  const expected = owner?.files && typeof owner.files === "object" ? owner.files : {};
  const same = Object.keys(files).length === Object.keys(expected).length &&
    Object.keys(files).every(key => expected[key] === files[key]);
  if (owner.id !== id || owner.installer !== "learn-omarchy" || owner.version !== 1 || !same)
    throw new Error(`Refusing locally modified or conflicting plugin: ${folder}`);
}

function registered(folder) {
  const plugins = JSON.parse(command("omarchy", ["plugin", "list", "--json"]));
  if (!Array.isArray(plugins)) throw new Error("Unsupported Omarchy plugin discovery response");
  const matches = plugins.filter(plugin => plugin && plugin.id === id);
  if (matches.length > 1) throw new Error(`Ambiguous plugin registration for ${id}`);
  const plugin = matches[0];
  if (plugin && (plugin.firstParty === true ||
      (plugin.manifestPath && resolve(plugin.manifestPath) !== join(folder, "manifest.json"))))
    throw new Error(`Plugin id ${id} is registered to a different integration`);
  return plugin;
}

async function remove() {
  if (args.some(arg => arg !== "--quiet")) throw new Error("Usage: remove-legacy-integration.mjs [--quiet]");
  if (process.getuid?.() === 0) throw new Error("Run as your regular user, not root");
  if (!process.env.HOME || !isAbsolute(process.env.HOME)) throw new Error("HOME must be an absolute user home");
  const folder = join(resolve(process.env.HOME), ".config", "omarchy", "plugins", id);
  const info = await stat(folder);
  if (!info) { report("No retired desktop integration is installed."); return; }
  if (!info.isDirectory() || info.isSymbolicLink()) throw new Error(`Refusing non-directory or symlink: ${folder}`);
  await requireOwnedAndUnchanged(folder);
  registered(folder);
  // Omarchy disables the service and backs up non-git plugin folders.
  command("omarchy", ["plugin", "remove", id, "--yes"]);
  if (await stat(folder)) throw new Error("The retired integration folder was not removed");
  for (let attempt = 0; attempt < 20; attempt++) {
    if (!registered(folder)) { report(`Removed the retired desktop integration ${id}.`); return; }
    await setTimeout(100);
  }
  throw new Error("The integration was removed, but the desktop has not confirmed it was unloaded");
}

remove().catch(error => {
  console.error(`learn-omarchy: couldn't remove the retired desktop integration: ${error.message}`);
  process.exitCode = 1;
});
