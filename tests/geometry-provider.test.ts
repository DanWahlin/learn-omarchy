import assert from "node:assert/strict";
import test from "node:test";
import { createContext, runInContext } from "node:vm";
import { readFile, mkdir, writeFile, cp, readdir, rm, symlink } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const provider = new URL("../integrations/omarchy/learn-omarchy.geometry/", import.meta.url);
const geometry = createContext({});
runInContext(await readFile(new URL("Geometry.js", provider), "utf8"), geometry);
const snapshot = (bar: any) => JSON.parse(JSON.stringify(geometry.snapshot(bar)));

function item(x = 10, y = 3, width = 30, height = 24): any {
  return { x, y, width, height, visible: true, opacity: 1, children: [],
    mapToItem(_target: unknown, px: number, py: number) { return { x: this.x + px, y: this.y + py }; } };
}

function fixture(position = "top", name = "DP-1", width = 1600, height = 900): any {
  const vertical = ["left", "right"].includes(position);
  const window = { screen: { name, width, height }, width: vertical ? 32 : width,
    height: vertical ? height : 32, visible: true,
    anchors: { top: position === "top" || vertical, bottom: position === "bottom" || vertical,
      left: position === "left" || !vertical, right: position === "right" || !vertical },
    margins: { top: 0, bottom: 0, left: 0, right: 0 } };
  const slot = { ...item(), activeItem: item(), moduleName: "omarchy.clock", window };
  return { manifest: { id: "omarchy.bar" }, position, barHidden: false, moduleSlots: [slot],
    slotWindow(slot: any) { return slot.window; } };
}

test("all four bar edges use window-local to screen-local logical offsets", () => {
  for (const [edge, x, y] of [["top", 10, 3], ["bottom", 10, 871], ["left", 10, 3], ["right", 1578, 3]] as const) {
    const screen = snapshot(fixture(edge)).screens[0];
    assert.equal(screen.width, 1600);
    assert.equal(screen.height, 900);
    assert.deepEqual(screen.widgets[0], { x, y, width: 30, height: 24, id: "omarchy.clock", visible: true, itemVisible: true });
  }
});

test("unequal screens and refreshed slots are not inferred from monitor order", () => {
  const bar = fixture("bottom", "portrait", 900, 1600);
  const second = fixture("bottom", "scaled", 1280, 720);
  bar.moduleSlots.unshift(second.moduleSlots[0]);
  let screens = snapshot(bar).screens;
  assert.deepEqual(screens.map((s: any) => [s.name, s.widgets[0].y]), [["scaled", 691], ["portrait", 1571]]);
  bar.moduleSlots[0].x = 80;
  bar.moduleSlots.reverse();
  screens = snapshot(bar).screens;
  assert.equal(screens[1].widgets[0].x, 80);
});

test("hidden parked bars and invisible active widgets cannot become visible targets", () => {
  for (const edge of ["top", "bottom", "left", "right"]) {
    const bar = fixture(edge);
    bar.barHidden = true;
    bar.moduleSlots[0].window.margins[edge] = -32;
    assert.equal(snapshot(bar).screens[0].widgets[0].visible, false);
  }
  const bar = fixture();
  bar.moduleSlots[0].activeItem.visible = false;
  assert.equal(snapshot(bar).screens[0].widgets[0].itemVisible, false);
  bar.moduleSlots[0].activeItem.visible = true;
  bar.moduleSlots[0].activeItem.opacity = 0;
  assert.equal(snapshot(bar).screens[0].widgets[0].visible, false);
});

test("workspace cells use actual nonuniform delegates and sparse workspace identities", () => {
  const bar = fixture("bottom");
  const slot = bar.moduleSlots[0];
  slot.moduleName = "omarchy.workspaces";
  slot.activeItem.workspaceIds = () => [1, 7, 10];
  slot.activeItem.workspaceById = () => null;
  slot.activeItem.children = [{ children: [item(), ...[1, 7, 10].map((id, i) => ({
    ...item(40 + i * i * 33, 1, 20 + i * 5, 30), modelData: id, workspace: null, pressed() {},
  }))] }];
  const cells = snapshot(bar).screens[0].widgets.filter((w: any) => w.workspaceId);
  assert.deepEqual(cells.map((w: any) => [w.workspaceId, w.x, w.width]), [[1, 40, 20], [7, 73, 25], [10, 172, 30]]);
  delete slot.activeItem.workspaceById;
  assert.equal(snapshot(bar).screens[0].widgets.length, 1);
});

test("missing capabilities custom geometry and invalid transforms fail closed", () => {
  for (const mutate of [
    (b: any) => { b.manifest.id = "custom.bar"; },
    (b: any) => { b.slotWindow = undefined; },
    (b: any) => { b.moduleSlots = []; },
    (b: any) => { b.moduleSlots[0].window.anchors.top = false; },
    (b: any) => { b.moduleSlots[0].window.margins.left = 12; },
    (b: any) => { b.moduleSlots[0].window.width -= 50; },
    (b: any) => { b.moduleSlots[0].mapToItem = (_: any, x: number, y: number) => ({ x: -y, y: x }); },
  ]) {
    const bar = fixture();
    mutate(bar);
    assert.throws(() => snapshot(bar), /unsupported|unavailable|supported|no live/);
  }
});

test("popup records use the exact card not its full-screen layer; unsupported cards are omitted", () => {
  const bar = fixture();
  const widget = bar.moduleSlots[0].activeItem;
  const window = bar.moduleSlots[0].window;
  widget.opened = true;
  const popup = { bar, open: true, visible: true, screen: window.screen, width: 1600, height: 900,
    anchors: { top: true, bottom: true, left: true, right: true },
    margins: { top: 0, bottom: 0, left: 0, right: 0 },
    cardOrigin: { x: 600, y: 45 }, contentWidth: 380, contentHeight: 560 };
  widget.data = [{ item: { data: [popup] } }];
  const get = (namespace = "omarchy-keyboard-panel") =>
    JSON.parse(JSON.stringify(geometry.snapshot(bar, () => namespace))).screens[0].widgets;
  assert.deepEqual(get()[1], { id: "panel:omarchy-keyboard-panel", x: 600, y: 45,
    width: 380, height: 560, visible: true, itemVisible: true });
  assert.equal(get("custom-panel").length, 1);
  popup.width = 800;
  assert.equal(get().length, 1);
  popup.width = 1600;
  popup.open = false;
  assert.equal(get().length, 1);
  assert.equal(geometry.snapshot(bar, () => { throw new Error("unsupported namespace"); }).screens[0].widgets.length, 1);
});

test("provider has no timers processes commands filesystem or mutation APIs", async () => {
  const service = await readFile(new URL("Service.qml", provider), "utf8");
  assert.match(service, /target: "learnGeometry"/);
  assert.match(service, /function snapshot\(\): string/);
  for (const filename of ["Service.qml", "SnapshotProvider.qml", "Geometry.js"]) {
    const text = await readFile(new URL(filename, provider), "utf8");
    assert.doesNotMatch(text, /\b(Process|Timer|FileView|XMLHttpRequest|runCommand|exec|setInterval)\b/);
  }
});

test("explicit installer uses only mock HOME, discovers before enabling, preserves upgrades and refuses conflicts", async () => {
  const root = resolve(`.geometry-provider-test-${randomUUID()}`);
  const home = join(root, "home");
  const bin = join(root, "bin");
  const packageRoot = join(root, "installed-app");
  const target = join(home, ".config/omarchy/plugins/learn-omarchy.geometry");
  const log = join(root, "commands.jsonl");
  try {
    await mkdir(bin, { recursive: true });
    await mkdir(home);
    await mkdir(join(packageRoot, "tools"), { recursive: true });
    await cp(fileURLToPath(provider), join(packageRoot, "integrations/omarchy/learn-omarchy.geometry"), { recursive: true });
    await cp(new URL("../tools/install-geometry-provider.mjs", import.meta.url), join(packageRoot, "tools/install-geometry-provider.mjs"));
    const mock = `#!${process.execPath}
import fs from 'node:fs';
import path from 'node:path';
const args = process.argv.slice(2);
fs.appendFileSync(process.env.MOCK_LOG, JSON.stringify([path.basename(process.argv[1]), ...args]) + '\\n');
if (args.join(' ') === 'plugin --help') console.log('omarchy plugin enable\\nomarchy plugin list');
else if (args[1] === 'validate') {
  const manifest = JSON.parse(fs.readFileSync(path.join(args[2], 'manifest.json'), 'utf8'));
  if (!fs.existsSync(path.join(args[2], manifest.entryPoints.service))) process.exit(4);
}
else if (args.join(' ') === 'shell rescanPlugins') fs.writeFileSync(process.env.HOME + '/discovered', 'yes');
else if (args.join(' ') === 'plugin list --json') console.log(JSON.stringify(fs.existsSync(process.env.HOME + '/discovered') ? [{id:'learn-omarchy.geometry', kinds:['service'], firstParty:false, enabled:fs.existsSync(process.env.HOME + '/enabled')}] : []));
else if (args.join(' ') === 'plugin enable learn-omarchy.geometry') {
  if (!fs.existsSync(process.env.HOME + '/discovered')) process.exit(2);
  fs.writeFileSync(process.env.HOME + '/enabled', 'yes');
} else process.exit(3);
`;
    for (const name of ["omarchy", "omarchy-shell"]) {
      await writeFile(join(bin, name), mock, { mode: 0o755 });
    }
    await writeFile(join(bin, "package.json"), '{"type":"module"}');
    const run = () => spawnSync(process.execPath, [join(packageRoot, "tools/install-geometry-provider.mjs")], {
      env: { ...process.env, HOME: home, PATH: `${bin}:${process.env.PATH}`, MOCK_LOG: log }, encoding: "utf8",
    });
    const first = run();
    assert.equal(first.status, 0, first.stderr);
    assert.match(first.stdout, /Installed and enabled/);
    const entryPoint = async (folder = target) =>
      JSON.parse(await readFile(join(folder, "manifest.json"), "utf8")).entryPoints.service;
    const firstEntry = await entryPoint();
    assert.match(firstEntry, /^releases\/[a-f0-9]{64}\/Service\.qml$/);
    assert.equal(await readFile(join(target, firstEntry), "utf8"), await readFile(new URL("Service.qml", provider), "utf8"));
    const firstOwner = JSON.parse(await readFile(join(target, ".learn-omarchy-owner.json"), "utf8"));
    assert.equal(firstOwner.files[firstEntry], createHash("sha256").update(await readFile(join(target, firstEntry))).digest("hex"));
    assert.ok(firstOwner.files[firstEntry.replace("Service.qml", "Geometry.js")]);
    assert.ok(firstOwner.files["manifest.json"]);
    assert.equal(firstOwner.files["Service.qml"], undefined);
    const calls = (await readFile(log, "utf8")).trim().split("\n").map(line => JSON.parse(line));
    assert.ok(calls.findIndex(c => c[2] === "rescanPlugins") < calls.findIndex(c => c[2] === "enable"));
    assert.equal(run().status, 0);
    assert.equal(await entryPoint(), firstEntry);
    assert.equal((await readdir(join(target, ".."))).filter(name => name.includes(".backup-")).length, 0);
    const sourceFolder = join(packageRoot, "integrations/omarchy/learn-omarchy.geometry");
    const sourceService = join(packageRoot, "integrations/omarchy/learn-omarchy.geometry/Service.qml");
    await writeFile(sourceService, (await readFile(sourceService, "utf8")) + "\n// Updated package.\n");
    const upgraded = run();
    assert.equal(upgraded.status, 0, upgraded.stderr);
    const backups = (await readdir(join(target, ".."))).filter(name => name.includes(".backup-"));
    assert.equal(backups.length, 1);
    const upgradedEntry = await entryPoint();
    assert.notEqual(upgradedEntry, firstEntry);
    assert.doesNotMatch(await readFile(join(target, "..", backups[0], firstEntry), "utf8"), /Updated package/);
    assert.match(await readFile(join(target, upgradedEntry), "utf8"), /Updated package/);
    const sourceManifest = JSON.parse(await readFile(join(sourceFolder, "manifest.json"), "utf8"));
    sourceManifest.description += " Metadata-only update.";
    await writeFile(join(sourceFolder, "manifest.json"), JSON.stringify(sourceManifest));
    const metadataUpdate = run();
    assert.equal(metadataUpdate.status, 0, metadataUpdate.stderr);
    assert.equal(await entryPoint(), upgradedEntry, "generated manifest metadata must not change code URLs");
    const sourceHelper = join(sourceFolder, "Geometry.js");
    await writeFile(sourceHelper, (await readFile(sourceHelper, "utf8")) + "\n// Helper-only update.\n");
    const helperUpdate = run();
    assert.equal(helperUpdate.status, 0, helperUpdate.stderr);
    const helperEntry = await entryPoint();
    assert.notEqual(helperEntry, upgradedEntry, "dependency edits must invalidate the entry-point URL too");
    await mkdir(join(target, "unexpected"));
    assert.match(run().stderr, /unexpected plugin entry/);
    await rm(join(target, "unexpected"), { recursive: true });
    await mkdir(join(target, "releases", "a".repeat(64)));
    assert.match(run().stderr, /unexpected plugin entry/);
    await rm(join(target, "releases", "a".repeat(64)), { recursive: true });
    const installedHelper = join(target, helperEntry.replace("Service.qml", "Geometry.js"));
    const helperContent = await readFile(installedHelper);
    await rm(installedHelper);
    await symlink(sourceHelper, installedHelper);
    assert.match(run().stderr, /symlink/);
    await rm(installedHelper);
    await writeFile(installedHelper, helperContent);
    await writeFile(join(target, helperEntry), "// User modified this\n");
    const modified = run();
    assert.equal(modified.status, 1);
    assert.match(modified.stderr, /locally modified|conflicting/);
    assert.equal(await readFile(join(target, helperEntry), "utf8"), "// User modified this\n");
    // Existing version-1 ownership markers from the original flat installer
    // remain upgradeable, but still have to match every installed file.
    await rm(target, { recursive: true });
    await cp(sourceFolder, target, { recursive: true });
    const flatFiles: Record<string, string> = {};
    for (const name of (await readdir(target)).sort()) {
      flatFiles[name] = createHash("sha256").update(await readFile(join(target, name))).digest("hex");
    }
    await writeFile(join(target, ".learn-omarchy-owner.json"), JSON.stringify({
      id: "learn-omarchy.geometry", installer: "learn-omarchy", version: 1, files: flatFiles,
    }));
    const flatUpgrade = run();
    assert.equal(flatUpgrade.status, 0, flatUpgrade.stderr);
    assert.equal(await entryPoint(), helperEntry, "flat upgrades produce the same deterministic revision");
    const owned = JSON.parse(await readFile(join(target, ".learn-omarchy-owner.json"), "utf8"));
    delete owned.files[helperEntry.replace("Service.qml", "Geometry.js")];
    await writeFile(join(target, ".learn-omarchy-owner.json"), JSON.stringify(owned));
    assert.match(run().stderr, /locally modified|conflicting/);
    await rm(target, { recursive: true });
    await mkdir(target);
    await writeFile(join(target, "manifest.json"), '{"id":"different.owner"}');
    assert.match(run().stderr, /unowned/);
    await rm(target, { recursive: true });
    await symlink(packageRoot, target);
    assert.match(run().stderr, /symlink/);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
