import assert from "node:assert/strict";
import { cp, mkdir, readFile, rm, symlink, writeFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { resolve, join } from "node:path";
import { homedir } from "node:os";
import test from "node:test";
import { defaultUserPackRoot, discoverCharacterPacks, loadCharacterPack, PACK_LIMITS, validateCharacterManifest, validatePackPath } from "../src/character-packs.ts";

const bundledRoot = resolve("assets/characters");
const exampleRoot = resolve("examples/characters/spark");
async function example() { return JSON.parse(await readFile(join(exampleRoot, "character.json"), "utf8")); }
async function fixture(t: { after: (callback: () => Promise<void>) => void }) {
  const root = resolve(`tests/.character-packs-${randomUUID()}`);
  await mkdir(root, { recursive: true });
  t.after(() => rm(root, { recursive: true, force: true }));
  return root;
}
async function copyExample(destination: string, id = "spark") {
  await cp(exampleRoot, destination, { recursive: true });
  const manifest = await example(); manifest.id = id;
  await writeFile(join(destination, "character.json"), JSON.stringify(manifest));
  return manifest;
}
async function save(root: string, manifest: any) { await writeFile(join(root, "character.json"), JSON.stringify(manifest)); }

test("default user root honors only absolute XDG/HOME paths and falls back to the OS home", () => {
  const home = resolve("tests/home"), xdg = resolve("tests/xdg");
  assert.equal(defaultUserPackRoot({ HOME: home, XDG_DATA_HOME: xdg }), join(xdg, "learn-omarchy", "characters"));
  for (const XDG_DATA_HOME of [undefined, "", "relative/xdg"]) {
    assert.equal(defaultUserPackRoot({ HOME: home, XDG_DATA_HOME }), join(home, ".local/share/learn-omarchy/characters"));
  }
  for (const HOME of [undefined, "", "relative/home"])
    assert.equal(defaultUserPackRoot({ HOME }), join(homedir(), ".local/share/learn-omarchy/characters"));
});

test("bundled packs preserve IDs, registration, voice metadata and asset filenames", async () => {
  const catalog = await discoverCharacterPacks({ bundledRoot });
  assert.equal(catalog.version, 1);
  assert.equal(catalog.fallbackId, "hexon");
  assert.deepEqual(catalog.invalidBundledIds, []);
  for (const id of ["hexon", "owl"]) {
    const pack = catalog.packs.find(item => item.id === id)!;
    assert.ok(pack);
    assert.equal(pack.manifest.id, id);
    assert.equal(pack.manifest.sprites.idle.frames, 16);
    assert.deepEqual(pack.manifest.sprites.idle.timeline, [
      { frame: 0, durationMs: 3000 }, { frame: 11, durationMs: 50 },
      { frame: 12, durationMs: 100 }, { frame: 13, durationMs: 50 },
    ]);
    assert.equal(pack.manifest.sprites.talk.fps, 8);
    assert.equal(pack.manifest.sprites.talk.frames, 8);
    assert.equal(pack.manifest.sprites.idle.path, `sprites/${id}-idle.png`);
    assert.equal(pack.manifest.author.status, "unresolved");
    assert.equal(pack.manifest.license.status, "unresolved");
    assert.ok(pack.diagnostics.some(message => message.includes("license is unresolved")));
    assert.ok(pack.assetUrl.startsWith("file:///"));
    assert.ok(!pack.assetUrl.endsWith("/"));
    assert.ok(pack.runtimeFiles.includes("character.json"));
    assert.ok(!pack.runtimeFiles.includes("sprites.conf"));
    for (const role of ["point-mid", "point-up-mid"]) {
      assert.equal(pack.manifest.sprites[role], undefined);
      assert.ok(!pack.runtimeFiles.includes(`sprites/${id}-${role}.png`));
    }
  }
  const hexon = catalog.packs.find(pack => pack.id === "hexon")!.manifest;
  assert.deepEqual(hexon.narration, { mode: "own", audioSet: "hexon", voices: {
    azure: "en-US-Andrew:DragonHDLatestNeural", edge: "en-US-GuyNeural",
  } });
  assert.equal(hexon.motion.tourFlight, "upright");
  assert.equal(catalog.packs.find(pack => pack.id === "owl")!.manifest.sprites.speech.frameHeight, 30);
});

test("third-party static single-frame example discovers without a catalog or renderer registration", async t => {
  const root = await fixture(t);
  await copyExample(join(root, "spark"));
  await copyExample(join(root, "amber"), "amber");
  const catalog = await discoverCharacterPacks({ bundledRoot, userRoot: root });
  assert.deepEqual(catalog.packs.map(pack => pack.id), catalog.packs.map(pack => pack.id).toSorted());
  const pack = catalog.packs.find(item => item.id === "spark")!;
  assert.ok(pack);
  assert.equal(pack.manifest.sprites.idle.frames, 1);
  assert.deepEqual(pack.manifest.narration, { mode: "borrowed", audioSet: "hexon" });
  assert.equal(pack.manifest.license.identifier, "CC0-1.0");
  assert.equal(catalog.fallbackId, "hexon");
});

test("talk strips must fit their shared idle pose registration", async () => {
  const manifest = await example();
  manifest.sprites.talk.frameWidth = manifest.sprites.idle.frameWidth - 1;
  assert.throws(() => validateCharacterManifest(manifest), /talk frameWidth must match idle/);
});

test("reserved bundled IDs cannot be overridden even when the bundled pack is broken", async t => {
  const root = await fixture(t);
  const bundles = join(root, "bundles"), users = join(root, "users");
  await mkdir(bundles); await mkdir(users);
  await writeFile(join(bundles, "index.json"), JSON.stringify({ formatVersion: 1, characters: [{ id: "hexon" }, { id: "future-coach" }] }));
  await copyExample(join(users, "hexon"), "hexon");
  await copyExample(join(users, "future-coach"), "future-coach");
  await copyExample(join(users, "spark"));
  const result = await discoverCharacterPacks({ bundledRoot: bundles, userRoot: users });
  assert.deepEqual(result.packs.map(pack => pack.id), ["spark"]);
  assert.deepEqual(result.invalidBundledIds, ["future-coach", "hexon"]);
  assert.equal(result.fallbackId, "spark");
  assert.equal(result.diagnostics.filter(message => message.includes("reserved")).length, 2);
});

test("empty or malformed catalogs and packs yield diagnostics rather than crashes", async t => {
  const root = await fixture(t);
  await writeFile(join(root, "index.json"), "{bad");
  const result = await discoverCharacterPacks({ bundledRoot: root, userRoot: join(root, "missing") });
  assert.deepEqual(result.packs, []);
  assert.equal(result.fallbackId, null);
  assert.ok(result.diagnostics.some(message => message.includes("invalid JSON")));
  const packRoot = join(root, "broken"); await mkdir(packRoot);
  await writeFile(join(packRoot, "character.json"), "[]");
  await assert.rejects(loadCharacterPack(packRoot), /must be an object/);
  await writeFile(join(packRoot, "character.json"), " ".repeat(PACK_LIMITS.manifestBytes + 1));
  await assert.rejects(loadCharacterPack(packRoot), /no larger than/);
});

test("malformed bundled catalogs still reserve future official directory IDs", async t => {
  const root = await fixture(t);
  const bundles = join(root, "bundles"), users = join(root, "users");
  await mkdir(bundles); await mkdir(users);
  await mkdir(join(bundles, "future-coach"));
  await copyExample(join(users, "future-coach"), "future-coach");
  await copyExample(join(users, "spark"));
  for (const index of ["{bad", JSON.stringify({ formatVersion: 1, characters: [{ id: "../invalid" }] })]) {
    await writeFile(join(bundles, "index.json"), index);
    const catalog = await discoverCharacterPacks({ bundledRoot: bundles, userRoot: users });
    assert.deepEqual(catalog.packs.map(pack => pack.id), ["spark"]);
    assert.ok(catalog.diagnostics.some(message => message.includes("future-coach") && message.includes("reserved")));
    assert.ok(catalog.invalidBundledIds.length > 0);
  }
});

test("an oversized invalid bundled root disables user discovery instead of allowing impersonation", async t => {
  const root = await fixture(t);
  const bundles = join(root, "bundles"), users = join(root, "users");
  await mkdir(bundles); await mkdir(users);
  await writeFile(join(bundles, "index.json"), "{bad");
  for (let i = 0; i < PACK_LIMITS.catalogEntries; i++) await mkdir(join(bundles, `coach-${i}`));
  await copyExample(join(users, "spark"));
  const catalog = await discoverCharacterPacks({ bundledRoot: bundles, userRoot: users });
  assert.deepEqual(catalog.packs, []);
  assert.ok(catalog.diagnostics.some(message => message.includes("user discovery disabled")));
});

test("manifest metadata, lifecycle, narration and registration are validated strictly", async () => {
  const baseline = await example();
  const invalid: [string, (manifest: any) => void][] = [
    ["version", value => value.formatVersion = 2],
    ["ID", value => value.id = "../other"],
    ["displayName", value => value.displayName = ""],
    ["description", value => delete value.description],
    ["author", value => value.author = { status: "declared", name: null }],
    ["license", value => value.license = { status: "declared" }],
    ["preview", value => value.preview.frame = 1],
    ["missing pose", value => delete value.sprites.talk],
    ["obsolete midpoint", value => value.sprites["point-mid"] = structuredClone(value.sprites.point)],
    ["obsolete upward midpoint", value => value.sprites["point-up-mid"] = structuredClone(value.sprites["point-up"])],
    ["frame count", value => value.sprites.idle.frames = 0],
    ["timeline", value => value.sprites.idle.timeline = [{ frame: 1, durationMs: 100 }]],
    ["fps", value => value.sprites.talk.fps = Infinity],
    ["canvas", value => value.renderer.canvas.width = 100000],
    ["scale", value => value.renderer.poses.point.scale = -1],
    ["registration", value => value.renderer.poses.point.baseline = 4],
    ["offset", value => value.renderer.poses.point.offset.x = NaN],
    ["tip", value => value.renderer.poses.point.tip.x = 1000],
    ["crop", value => value.renderer.poses.point.speech.source.width = 224],
    ["speech", value => value.renderer.poses.point.speech.sprite = "../../other"],
    ["flight", value => value.motion.tourFlight = "sprite"],
    ["effects", value => value.effects.thrusters = "false"],
    ["blink", value => value.blink = { periodMs: 100, startMs: 90, durationMs: 40 }],
    ["narration", value => value.narration = { mode: "borrowed", audioSet: "arbitrary" }],
    ["own audio", value => value.narration = { mode: "own", audioSet: "owl" }],
    ["executable reference", value => value.script = "run.sh"],
  ];
  for (const [name, change] of invalid) {
    const manifest = structuredClone(baseline); change(manifest);
    assert.throws(() => validateCharacterManifest(manifest), undefined, name);
  }
  for (const narration of [{ mode: "silent" }, { mode: "own", audioSet: "spark" }, { mode: "borrowed", audioSet: "owl" }]) {
    const manifest = structuredClone(baseline); manifest.narration = narration;
    assert.doesNotThrow(() => validateCharacterManifest(manifest));
  }
});

test("paths reject traversal, absolute paths, encoded URLs and executable references", () => {
  for (const path of ["../evil.png", "/evil.png", "https://x/image.png", "sprites/%2e%2e/image.png", "sprites/image.png?x=1",
    "sprites/../image.png", "sprites\\image.png", "C:/image.png", "./sprites/image.png", "sprites//image.png",
    "sprites/run.qml", "sprites/run.sh", "sprites/image.svg", "sprites/#image.png"])
    assert.throws(() => validatePackPath(path, ".png"), /Unsafe/);
  assert.doesNotThrow(() => validatePackPath("sprites/my-original_1.png", ".png"));
});

test("unreferenced executable files and excessive filesystem entries are rejected", async t => {
  const root = await fixture(t);
  await copyExample(root);
  for (const extension of ["qml", "js", "mjs", "cjs", "sh", "py"]) {
    const file = join(root, `unreferenced.${extension}`);
    await writeFile(file, "never execute this");
    await assert.rejects(loadCharacterPack(root), /executable files/);
    await rm(file);
  }
  await mkdir(join(root, "extras"));
  for (let i = 0; i < PACK_LIMITS.packEntries; i++) await writeFile(join(root, "extras", `extra-${i}.txt`), "");
  await assert.rejects(loadCharacterPack(root), /filesystem entries/);
});

test("user discovery visits at most 64 pack directories", async t => {
  const root = await fixture(t);
  for (let i = 0; i <= PACK_LIMITS.userPacks; i++) await mkdir(join(root, `pack-${String(i).padStart(3, "0")}`));
  const result = await discoverCharacterPacks({ bundledRoot, userRoot: root });
  assert.equal(result.diagnostics.filter(message => /^User pack pack-/.test(message)).length, PACK_LIMITS.userPacks);
  assert.ok(result.diagnostics.some(message => message.includes("limited to 64")));
  assert.ok(Buffer.byteLength(JSON.stringify(result)) < PACK_LIMITS.outputBytes);
});

test("asset and discovery directory symlinks cannot escape their roots", async t => {
  const root = await fixture(t);
  const users = join(root, "users"); await mkdir(users);
  const packRoot = join(users, "spark");
  const manifest = await copyExample(packRoot);
  const outside = join(root, "outside.png");
  await cp(join(packRoot, manifest.sprites.idle.path), outside);
  await rm(join(packRoot, manifest.sprites.idle.path));
  await symlink(outside, join(packRoot, manifest.sprites.idle.path));
  await assert.rejects(loadCharacterPack(packRoot), /symlink escapes/);
  await copyExample(join(root, "outsider"), "outsider");
  await symlink(join(root, "outsider"), join(users, "outsider"));
  const result = await discoverCharacterPacks({ bundledRoot, userRoot: users });
  assert.ok(!result.packs.some(pack => ["spark", "outsider"].includes(pack.id)));
  assert.ok(result.diagnostics.some(message => message.includes("directory symlink escapes")));
});

test("metadata symlink escapes reject packs while intro symlink escapes disable only intro", async t => {
  const root = await fixture(t);
  const packRoot = join(root, "spark");
  const manifest = await copyExample(packRoot);
  const outsideManifest = join(root, "outside.json");
  await writeFile(outsideManifest, JSON.stringify(manifest));
  await rm(join(packRoot, "character.json"));
  await symlink(outsideManifest, join(packRoot, "character.json"));
  await assert.rejects(loadCharacterPack(packRoot), /symlink escapes/);
  await rm(join(packRoot, "character.json")); await save(packRoot, manifest);
  const sequence = join(packRoot, manifest.intro.sequence);
  const outsideSequence = join(root, "outside-sequence.json");
  await cp(sequence, outsideSequence);
  await rm(sequence); await symlink(outsideSequence, sequence);
  const pack = await loadCharacterPack(packRoot);
  assert.equal(pack.intro, null);
  assert.ok(pack.diagnostics.some(diagnostic => diagnostic.includes("intro disabled") && diagnostic.includes("symlink escapes")));
  assert.ok(!pack.runtimeFiles.includes(manifest.intro.sequence));
});

test("PNG dimensions, content and size caps are enforced", async t => {
  const root = await fixture(t);
  const manifest = await copyExample(root);
  manifest.sprites.idle.frames = 2; manifest.sprites.idle.fps = 8;
  await save(root, manifest);
  await assert.rejects(loadCharacterPack(root), /dimensions do not match/);
  manifest.sprites.idle.frames = 1; await save(root, manifest);
  const imagePath = join(root, manifest.sprites.idle.path);
  const original = await readFile(imagePath);
  const noPixels = Buffer.concat([original.subarray(0, 33), original.subarray(original.length - 12)]);
  await writeFile(imagePath, noPixels);
  await assert.rejects(loadCharacterPack(root), /incomplete PNG/);
  const corruptPixels = Buffer.from(original); corruptPixels[45] ^= 1;
  await writeFile(imagePath, corruptPixels);
  await assert.rejects(loadCharacterPack(root), /checksum/);
  const corrupt = Buffer.from(original); corrupt[corrupt.length - 1] ^= 1;
  await writeFile(imagePath, corrupt);
  await assert.rejects(loadCharacterPack(root), /checksum/);
  await writeFile(imagePath, original.subarray(0, 40));
  await assert.rejects(loadCharacterPack(root), /invalid PNG/);
  await writeFile(imagePath, Buffer.alloc(PACK_LIMITS.imageBytes + 1));
  await assert.rejects(loadCharacterPack(root), /no larger than/);
});

test("aggregate pixel budget is checked before inflating optional intro images", async t => {
  const root = await fixture(t);
  const manifest = await copyExample(root);
  const sequenceFile = join(root, manifest.intro.sequence);
  const sequence = JSON.parse(await readFile(sequenceFile, "utf8"));
  sequence.layers.push({ id: "large-image", type: "image", images: ["sprites/large.png"], width: 100, height: 100 });
  await writeFile(sequenceFile, JSON.stringify(sequence));
  const image = await readFile(join(root, manifest.sprites.idle.path));
  // A header at the per-image limit exceeds the remaining pack budget. Checking
  // this before checksums/inflation avoids allocating an enormous test image.
  image.writeUInt32BE(8192, 16);
  image.writeUInt32BE(4096, 20);
  await writeFile(join(root, "sprites", "large.png"), image);
  const pack = await loadCharacterPack(root);
  assert.equal(pack.intro, null);
  assert.ok(pack.diagnostics.some(diagnostic => diagnostic.includes("aggregate decoded-pixel budget")));
  assert.ok(!pack.runtimeFiles.includes("sprites/large.png"));
});

test("optional missing, unsafe, oversized or invalid intro never rejects valid graphics", async t => {
  const root = await fixture(t);
  const manifest = await copyExample(root);
  for (const intro of [undefined, { sequence: "../evil.json" }, { sequence: "missing.json" }, { sequence: "bad.json" }, { sequence: "huge.json" }, { script: "run.qml" }]) {
    manifest.intro = intro; await save(root, manifest);
    await writeFile(join(root, "bad.json"), '{"formatVersion":999}');
    await writeFile(join(root, "huge.json"), " ".repeat(PACK_LIMITS.sequenceBytes + 1));
    const pack = await loadCharacterPack(root);
    assert.equal(pack.intro, null);
    assert.ok(pack.diagnostics.some(message => /intro/.test(message)));
    assert.ok(!pack.runtimeFiles.includes("bad.json") && !pack.runtimeFiles.includes("huge.json"));
  }
});

test("CLI discover emits machine-readable JSON and validate rejects bad input", async t => {
  const root = await fixture(t);
  const discovery = spawnSync(process.execPath, ["--experimental-strip-types", "tools/character-packs.ts", "discover",
    "--bundled-root", bundledRoot, "--user-root", root], { encoding: "utf8" });
  assert.equal(discovery.status, 0, discovery.stderr);
  assert.equal(JSON.parse(discovery.stdout).fallbackId, "hexon");
  const validation = spawnSync(process.execPath, ["--experimental-strip-types", "tools/character-packs.ts", "validate", root], { encoding: "utf8" });
  assert.equal(validation.status, 1);
  assert.match(validation.stderr, /Character packs:/);
});

test("CLI check-bundled reports warnings without failing and rejects invalid catalogs", async t => {
  const root = await fixture(t);
  const run = (path: string) => spawnSync(process.execPath,
    ["--experimental-strip-types", "tools/character-packs.ts", "check-bundled", "--bundled-root", path], { encoding: "utf8" });
  const valid = run(bundledRoot);
  assert.equal(valid.status, 0, valid.stderr);
  assert.match(valid.stdout, /license is unresolved/);
  assert.match(valid.stdout, /Validated bundled character packs:/);
  const invalid = run(root);
  assert.equal(invalid.status, 1);
  assert.match(invalid.stdout, /No valid character packs/);
  assert.match(invalid.stderr, /validation failed/);
});
