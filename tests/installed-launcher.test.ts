import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdtemp, mkdir, readFile, writeFile, rm, readdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

const revision = "a".repeat(64);
const sha256 = (content: string) => createHash("sha256").update(content).digest("hex");

// Recreates the managed plugin copy that releases before 0.2.4 installed.
async function installLegacyIntegration(target: string) {
  const files: Record<string, string> = {
    "manifest.json": JSON.stringify({ id: "learn-omarchy.geometry", schemaVersion: 1, kinds: ["service"],
      entryPoints: { service: `releases/${revision}/Service.qml` } }),
    [`releases/${revision}/Service.qml`]: "import QtQuick\nItem {}\n",
    [`releases/${revision}/Geometry.js`]: "function snapshot() {}\n",
  };
  await mkdir(join(target, "releases", revision), { recursive: true });
  for (const [name, content] of Object.entries(files)) await writeFile(join(target, name), content);
  await writeFile(join(target, ".learn-omarchy-owner.json"), JSON.stringify({ id: "learn-omarchy.geometry",
    installer: "learn-omarchy", version: 1,
    files: Object.fromEntries(Object.entries(files).map(([name, content]) => [name, sha256(content)])) }));
  return join(target, `releases/${revision}/Service.qml`);
}

test("the installed launcher leaves desktop plugins alone and uninstall retires the old integration", async () => {
  const directory = await mkdtemp(join(tmpdir(), "learn-installed-launcher-"));
  const home = join(directory, "home");
  const mocks = join(directory, "commands");
  const root = join(directory, "usr/share/learn-omarchy");
  const launcher = join(directory, "usr/bin/learn-omarchy");
  const plugins = join(home, ".config/omarchy/plugins");
  const target = join(plugins, "learn-omarchy.geometry");
  const log = join(directory, "commands.jsonl");
  const started = join(directory, "started.json");
  try {
    const packaged = spawnSync("make", ["install", `DESTDIR=${directory}`, "PREFIX=/usr"], { encoding: "utf8" });
    assert.equal(packaged.status, 0, packaged.stderr);
    await mkdir(home);
    await mkdir(mocks);
    await writeFile(join(mocks, "package.json"), '{"type":"module"}');
    const mock = `#!${process.execPath}
import fs from "node:fs";
import path from "node:path";
import {spawnSync} from "node:child_process";
const name = path.basename(process.argv[1]);
const args = process.argv.slice(2);
const home = process.env.HOME;
const target = home + "/.config/omarchy/plugins/learn-omarchy.geometry";
fs.appendFileSync(process.env.MOCK_LOG, JSON.stringify([name, ...args]) + "\\n");
if (name === "qs") {
  fs.writeFileSync(process.env.MOCK_STARTED, JSON.stringify({
    args, root: process.env.LEARN_OMARCHY_ROOT, course: process.env.LEARN_OMARCHY_COURSE
  }));
} else if (name === "mpv") {
  process.exit(0);
} else if (name === "sudo") {
  const result = spawnSync(args[0], args.slice(1), {stdio:"inherit", env:process.env});
  process.exit(result.status ?? 1);
} else if (name === "pacman") {
  if (args.join(" ") === "-Q learn-omarchy") process.exit(0);
  if (args.join(" ") !== "-R learn-omarchy") process.exit(11);
  if (fs.existsSync(home + "/cancel-uninstall")) process.exit(1);
  fs.rmSync(process.env.MOCK_APP_ROOT + "/tools/remove-legacy-integration.mjs");
  fs.writeFileSync(home + "/package-removed", "yes");
} else if (args.join(" ") === "plugin list --json") {
  console.log(JSON.stringify(fs.existsSync(target) ?
    [{id:"learn-omarchy.geometry", kinds:["service"], firstParty:false, enabled:true, active:false}] : []));
} else if (args.join(" ") === "plugin remove learn-omarchy.geometry --yes") {
  fs.renameSync(target, path.dirname(target) + "/.removed-integration-" + Date.now());
} else {
  console.error("Unexpected mock command");
  process.exit(10);
}
`;
    for (const command of ["omarchy", "qs", "mpv", "sudo", "pacman"])
      await writeFile(join(mocks, command), mock, { mode: 0o755 });
    const env: NodeJS.ProcessEnv = { ...process.env, HOME: home, XDG_STATE_HOME: join(home, "state"),
      XDG_CONFIG_HOME: join(home, ".config"), PATH: `${mocks}:${process.env.PATH}`,
      MOCK_LOG: log, MOCK_STARTED: started, MOCK_APP_ROOT: root, TMPDIR: directory };
    for (const name of ["LEARN_OMARCHY_ROOT", "LEARN_OMARCHY_COURSE", "LEARN_OMARCHY_COURSE_DIR", "LEARN_OMARCHY_CHARACTER"])
      delete env[name];
    const launch = (...args: string[]) => spawnSync(launcher, args, {
      env, cwd: directory, encoding: "utf8", timeout: 30000,
    });
    const calls = async () => (await readFile(log, "utf8").catch(() => "")).trim().split("\n").filter(Boolean)
      .map(line => JSON.parse(line).slice(0, 3));

    assert.equal(launch("--help").status, 0);
    assert.deepEqual(await readdir(home), [], "help doesn't touch the desktop");
    assert.equal(launch("--remove-integration").status, 2, "the retired option is rejected");

    const progress = join(home, "state/learn-omarchy/progress.json");
    await installLegacyIntegration(target);
    const upgraded = launch();
    assert.equal(upgraded.status, 0, upgraded.stderr);
    const start = JSON.parse(await readFile(started, "utf8"));
    assert.deepEqual(start.args, ["--no-duplicate", "--path", join(root, "app")]);
    assert.equal(start.root, root);
    assert.equal(start.course, join(root, "courses/omarchy-basics.json"));
    assert.deepEqual(await calls(), [["qs", "--no-duplicate", "--path"]],
      "launching never queries or changes desktop plugins");
    assert.ok((await readdir(plugins)).includes("learn-omarchy.geometry"), "an old integration stays until uninstall");
    await writeFile(progress, '{"saved":"progress"}');

    assert.match(launch("--uninstall").stderr, /from a terminal/, "unattended removal changes nothing");
    const command = "'" + launcher.replace(/'/g, "'\\''") + "' --uninstall";
    const uninstall = () => spawnSync("script", ["--quiet", "--return", "--command", command, "/dev/null"],
      { env, cwd: directory, encoding: "utf8", timeout: 30000 });
    await writeFile(join(home, "cancel-uninstall"), "yes");
    assert.notEqual(uninstall().status, 0);
    assert.ok((await readdir(plugins)).includes("learn-omarchy.geometry"), "cancelling package removal changes nothing");
    await rm(join(home, "cancel-uninstall"));
    const uninstalled = uninstall();
    assert.equal(uninstalled.status, 0, uninstalled.stdout + uninstalled.stderr);
    assert.equal(await readFile(join(home, "package-removed"), "utf8"), "yes");
    assert.equal(await readFile(progress, "utf8"), '{"saved":"progress"}');
    assert.ok(!(await readdir(plugins)).includes("learn-omarchy.geometry"),
      "cleanup works after the package removes its original helper");
    assert.ok(!(await readdir(directory)).some(name => name.startsWith("learn-omarchy-uninstall.")),
      "the private cleanup copy is removed");

    const service = await installLegacyIntegration(target);
    await writeFile(service, "// User customization\n");
    await writeFile(join(root, "tools/remove-legacy-integration.mjs"),
      await readFile(new URL("../tools/remove-legacy-integration.mjs", import.meta.url)));
    const modified = uninstall();
    assert.equal(modified.status, 0, "a modified old integration never blocks uninstalling");
    assert.match(modified.stdout + modified.stderr, /locally modified/);
    assert.equal(await readFile(service, "utf8"), "// User customization\n", "user changes are preserved");
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
