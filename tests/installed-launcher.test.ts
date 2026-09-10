import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, mkdir, readFile, writeFile, rm, readdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

test("one installed package automatically prepares and updates its integration without the checkout", async () => {
  const directory = await mkdtemp(join(tmpdir(), "learn-installed-launcher-"));
  const home = join(directory, "home");
  const mocks = join(directory, "commands");
  const root = join(directory, "usr/share/learn-omarchy");
  const launcher = join(directory, "usr/bin/learn-omarchy");
  const target = join(home, ".config/omarchy/plugins/learn-omarchy.geometry");
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
    args, root: process.env.LEARN_OMARCHY_ROOT, course: process.env.LEARN_OMARCHY_COURSE,
    error: process.env.LEARN_OMARCHY_INTEGRATION_ERROR
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
  fs.rmSync(process.env.MOCK_APP_ROOT + "/tools/install-geometry-provider.mjs");
  fs.writeFileSync(home + "/package-removed", "yes");
} else if (fs.existsSync(home + "/unavailable")) {
  console.error("Desktop integration is temporarily unavailable");
  process.exit(7);
} else if (args.join(" ") === "plugin list --json") {
  const enabled = fs.existsSync(home + "/enabled");
  console.log(JSON.stringify(fs.existsSync(home + "/discovered") && fs.existsSync(target) ?
    [{id:"learn-omarchy.geometry", kinds:["service"], firstParty:false, enabled, active:false}] : []));
} else if (args.join(" ") === "learnGeometry capabilities") {
  console.log(JSON.stringify({shellAvailable:true, barAvailable:true, manifestId:"",
    slotsAvailable:false, windowMappingAvailable:false}));
} else if (args.join(" ") === "plugin --help") {
  console.log("omarchy plugin enable\\nomarchy plugin list");
} else if (args[0] === "plugin" && args[1] === "validate") {
  const manifest = JSON.parse(fs.readFileSync(path.join(args[2], "manifest.json"), "utf8"));
  if (!fs.existsSync(path.join(args[2], manifest.entryPoints.service))) process.exit(8);
} else if (args.join(" ") === "shell rescanPlugins") {
  fs.writeFileSync(home + "/discovered", "yes");
} else if (args.join(" ") === "plugin enable learn-omarchy.geometry") {
  if (!fs.existsSync(home + "/discovered")) process.exit(9);
  fs.writeFileSync(home + "/enabled", "yes");
} else if (args.join(" ") === "plugin remove learn-omarchy.geometry --yes") {
  fs.renameSync(target, path.dirname(target) + "/.removed-integration-" + Date.now());
  fs.rmSync(home + "/enabled", {force:true});
} else {
  console.error("Unexpected mock command");
  process.exit(10);
}
`;
    for (const command of ["omarchy", "omarchy-shell", "qs", "mpv", "sudo", "pacman"])
      await writeFile(join(mocks, command), mock, { mode: 0o755 });
    const env: NodeJS.ProcessEnv = { ...process.env, HOME: home, XDG_STATE_HOME: join(home, "state"),
      XDG_CONFIG_HOME: join(home, ".config"), PATH: `${mocks}:${process.env.PATH}`,
      MOCK_LOG: log, MOCK_STARTED: started, MOCK_APP_ROOT: root, TMPDIR: directory };
    delete env.LEARN_OMARCHY_ROOT;
    delete env.LEARN_OMARCHY_COURSE;
    delete env.LEARN_OMARCHY_COURSE_DIR;
    delete env.LEARN_OMARCHY_CHARACTER;
    delete env.LEARN_OMARCHY_INTEGRATION_ERROR;
    const launch = (...args: string[]) => spawnSync(launcher, args, {
      env, cwd: directory, encoding: "utf8", timeout: 30000,
    });
    assert.equal(launch("--help").status, 0);
    assert.deepEqual(await readdir(home), [], "help doesn't configure the desktop");
    const first = launch();
    assert.equal(first.status, 0, first.stderr);
    assert.equal(await readFile(join(home, "enabled"), "utf8"), "yes");
    const firstStart = JSON.parse(await readFile(started, "utf8"));
    assert.deepEqual(firstStart.args, ["--no-duplicate", "--path", join(root, "app")]);
    assert.equal(firstStart.root, root);
    assert.equal(firstStart.course, join(root, "courses/omarchy-basics.json"));
    assert.equal(firstStart.error, "");
    const entry = async () => JSON.parse(await readFile(join(target, "manifest.json"), "utf8")).entryPoints.service;
    const initialEntry = await entry();
    const calls = async () => (await readFile(log, "utf8")).trim().split("\n").map(line => JSON.parse(line));
    const before = (await calls()).length;
    assert.equal(launch().status, 0);
    assert.deepEqual((await calls()).slice(before).map(call => call.slice(0, 3)),
      [["omarchy", "plugin", "list"], ["omarchy-shell", "learnGeometry", "capabilities"],
        ["qs", "--no-duplicate", "--path"]],
      "normal reopening doesn't reinstall, reload, or re-enable the service");

    const bundled = join(root, "integrations/omarchy/learn-omarchy.geometry/Geometry.js");
    await writeFile(bundled, await readFile(bundled, "utf8") + "\n// Installed package update.\n");
    const upgraded = launch();
    assert.equal(upgraded.status, 0, upgraded.stderr);
    const updatedEntry = await entry();
    assert.notEqual(updatedEntry, initialEntry);
    assert.match(await readFile(join(target, updatedEntry.replace("Service.qml", "Geometry.js")), "utf8"),
      /Installed package update/);

    await writeFile(join(home, "unavailable"), "yes");
    const unavailable = launch();
    assert.equal(unavailable.status, 0, "the application still starts with fallback geometry");
    assert.match(unavailable.stderr, /temporarily unavailable/);
    assert.match(JSON.parse(await readFile(started, "utf8")).error, /temporarily unavailable/);
    await rm(join(home, "unavailable"));
    assert.equal(launch().status, 0);
    assert.equal(JSON.parse(await readFile(started, "utf8")).error, "", "successful retry clears the startup error");

    const service = join(target, updatedEntry);
    const managed = await readFile(service);
    await writeFile(service, "// User customization\n");
    assert.equal(launch().status, 0);
    assert.match(JSON.parse(await readFile(started, "utf8")).error, /locally modified/);
    assert.notEqual(launch("--remove-integration").status, 0);
    assert.equal(await readFile(service, "utf8"), "// User customization\n");
    await writeFile(service, managed);
    const progress = join(home, "state/learn-omarchy/progress.json");
    await writeFile(progress, '{"saved":"progress"}');
    const removed = launch("--remove-integration");
    assert.equal(removed.status, 0, removed.stderr);
    assert.equal(await readFile(progress, "utf8"), '{"saved":"progress"}');
    assert.equal(launch("--remove-integration").status, 0);
    assert.equal(launch().status, 0);
    assert.match(launch("--uninstall").stderr, /from a terminal/, "unattended removal cannot partially modify the integration");
    const command = "'" + launcher.replace(/'/g, "'\\''") + "' --uninstall";
    const uninstall = () => spawnSync("script", ["--quiet", "--return", "--command", command, "/dev/null"],
      { env, cwd: directory, encoding: "utf8", timeout: 30000 });
    await writeFile(join(home, "cancel-uninstall"), "yes");
    const cancelled = uninstall();
    assert.notEqual(cancelled.status, 0);
    assert.equal(await readFile(join(home, "enabled"), "utf8"), "yes", "cancelling package removal leaves integration active");
    await rm(join(home, "cancel-uninstall"));
    const uninstalled = uninstall();
    assert.equal(uninstalled.status, 0, uninstalled.stdout + uninstalled.stderr);
    assert.equal(await readFile(join(home, "package-removed"), "utf8"), "yes");
    assert.equal(await readFile(progress, "utf8"), '{"saved":"progress"}');
    assert.ok(!(await readdir(join(home, ".config/omarchy/plugins"))).includes("learn-omarchy.geometry"),
      "cleanup still works after the package removes its original helper");
    assert.ok(!(await readdir(directory)).some(name => name.startsWith("learn-omarchy-uninstall.")),
      "the private cleanup copy is removed on both cancellation and success");
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
