import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { compileIntroSequence, introAssetPaths, sampleIntroSequence, validateIntroSequence } from "../src/intro-sequence.ts";

const readSequence = (pack: string) => JSON.parse(readFileSync(new URL(`../${pack}/intro/sequence.json`, import.meta.url), "utf8"));
const base = () => ({
  version: 1,
  layers: [],
  character: { x: 0, y: 0, offsetX: 0, offsetY: 0, visible: true },
  steps: [
    { type: "tween", target: "character", to: { x: 0.5 }, duration: 100, easing: "linear" },
    { type: "parallel", branches: [
      [{ type: "tween", target: "character", to: { y: 1 }, duration: 200 }],
      [{ type: "wait", duration: 50 }, { type: "set", target: "character", to: { facing: -1 } }],
    ] },
    { type: "set", target: "character", to: { pose: "point" } },
  ],
});
const sample = (timeline: unknown, time: number, width = 1000, height = 800, sizes?: unknown) =>
  sampleIntroSequence(timeline, time, width, height, sizes) as Record<string, Record<string, any>>;

test("sequential/parallel tracks join at the longest branch, then set once", () => {
  const timeline = compileIntroSequence(base()) as { duration: number };
  assert.equal(timeline.duration, 300);
  assert.equal(sample(timeline, 50).character.x, 250);
  assert.equal(sample(timeline, 150).character.y, 200);
  assert.equal(sample(timeline, 149).character.facing, 1);
  assert.equal(sample(timeline, 150).character.facing, -1);
  assert.equal(sample(timeline, 299).character.pose, "idle");
  assert.equal(sample(timeline, 300).character.pose, "point");
  assert.equal(sample(timeline, 999).character.pose, "point");
  assert.equal(sample(timeline, 50, 2000).character.x, 500);
});

test("official and independent third sequence are valid with bounded durations and local art", () => {
  for (const pack of ["assets/characters/hexon", "assets/characters/owl", "examples/characters/spark"]) {
    const sequence = readSequence(pack);
    assert.deepEqual(validateIntroSequence(sequence), [], pack);
    const timeline = compileIntroSequence(sequence) as { duration: number };
    assert.ok(timeline.duration > 2000 && timeline.duration <= 8000);
    assert.equal(sample(timeline, timeline.duration).character.visible, true);
    for (const path of introAssetPaths(sequence)) {
      assert.ok(path.startsWith("sprites/"));
      assert.ok(readFileSync(new URL(`../${pack}/${path}`, import.meta.url)).length > 0);
    }
  }
  assert.deepEqual(introAssetPaths(readSequence("examples/characters/spark")), []);
});

test("legacy composition retains native aspect, viewport clamps, hatch and ground handoff", () => {
  const timeline = compileIntroSequence(readSequence("assets/characters/hexon"));
  const sizes = { hull: { width: 279, height: 640 }, hatch: { width: 279, height: 640 } };
  const landed = sample(timeline, 2400, 1920, 1080, sizes);
  assert.equal(landed.hull.height, 540);
  assert.equal(landed.hull.width, 540 * 279 / 640);
  assert.equal(landed.hull.y, 530);
  assert.equal(landed.hatch.opacity, 1);
  assert.equal(landed.character.x, 960 - 112);
  assert.equal(landed.character.y, 530 + 0.7 * 540 - 188);
  const final = sample(timeline, 6800, 1920, 1080, sizes);
  assert.equal(final.character.x, 960 + 158);
  assert.equal(final.character.y, 1080 - 214);
  assert.equal(final.character.flying, false);
  assert.ok(final.hull.y + final.hull.height < 0);
  assert.equal(sample(timeline, 2400, 800, 500, sizes).hull.height, 360);
  assert.equal(sample(timeline, 2400, 3000, 2000, sizes).hull.height, 700);
});

test("OLLIE grows around bottom pivot, reveals on declared perch, and takes off before handoff", () => {
  const timeline = compileIntroSequence(readSequence("assets/characters/owl"));
  const sizes = { canopy: { width: 565, height: 520 } };
  assert.equal(sample(timeline, 0, 1920, 1080, sizes).canopy.scale, 0.1);
  const revealed = sample(timeline, 1500, 1920, 1080, sizes);
  assert.equal(revealed.canopy.scale, 1);
  assert.equal(revealed.character.opacity, 1);
  assert.equal(revealed.character.x, revealed.canopy.x + revealed.canopy.width * 0.84 - 112);
  const final = sample(timeline, 3700, 1920, 1080, sizes);
  assert.equal(final.character.flying, true);
  assert.equal(final.character.y, revealed.character.y - 32);
  assert.equal(final.canopy.opacity, 0);
});

test("invalid input cannot add commands, expressions, target paths, or remote/traversal images", () => {
  const invalid: unknown[] = [
    null, {}, { ...base(), version: 2 }, { ...base(), script: "exit()" },
    { ...base(), steps: [{ type: "eval", text: "evil()" }] },
    { ...base(), steps: [{ type: "set", target: "character.x", to: { x: 1 } }] },
    { ...base(), character: { x: "width / 2" } },
    { ...base(), character: { x: Infinity } },
    { ...base(), character: { opacity: NaN } },
    { ...base(), character: { scale: 99 } },
    { ...base(), character: { pose: "run" } },
    { ...base(), character: { facing: 0 } },
    { ...base(), steps: [{ type: "tween", target: "character", to: { visible: true }, duration: 10 }] },
    { ...base(), steps: [{ type: "tween", target: "character", to: { x: 1 }, duration: 10, easing: "function()" }] },
  ];
  for (const path of ["../other.png", "/root/image.png", "https://x/a.png", "sprites/../../a.png",
    "sprites/a%2fpng", "sprites/a.qml", "sprites/a.svg", "sprites/a.webp", "sprites/a.jpg", "sprites/a.jpeg"]) {
    invalid.push({ ...base(), layers: [{ id: "image", type: "image", images: [path] }] });
  }
  for (const value of invalid) {
    assert.ok(validateIntroSequence(value).length, JSON.stringify(value));
    assert.deepEqual(introAssetPaths(value), []);
  }
});

test("bounds, conflicting parallel writes, image frame indices and reference cycles are rejected", () => {
  const invalid = [
    { ...base(), steps: [{ type: "wait", duration: 30001 }] },
    { ...base(), steps: Array.from({ length: 257 }, () => ({ type: "wait", duration: 1 })) },
    { ...base(), layers: Array.from({ length: 25 }, (_, i) => ({ id: `layer-${i}`, type: "effect", effect: "specks" })) },
    { ...base(), layers: [{ id: "pixels", type: "effect", effect: "specks", count: 65 }] },
    { ...base(), layers: [{ id: "pixels", type: "effect", effect: "specks", width: { viewport: 1, min: 100, max: 50 } }] },
    { ...base(), layers: [{ id: "label", type: "text", state: { text: "{config.secret}" } }] },
    { ...base(), layers: [{ id: "image", type: "image", images: ["sprites/a.png"], state: { frame: 1 } }] },
    { ...base(), character: { x: { layer: "missing", anchor: 0.5 } } },
    { ...base(), layers: [
      { id: "a", type: "text", state: { x: { layer: "b", anchor: 0.5 } } },
      { id: "b", type: "text", state: { y: { layer: "a", anchor: 0.5 } } },
    ] },
    { ...base(), steps: [{ type: "parallel", branches: [
      [{ type: "tween", target: "character", to: { x: 1 }, duration: 100 }],
      [{ type: "set", target: "character", to: { x: 0 } }],
    ] }] },
  ];
  let deep: any = { type: "wait", duration: 1 };
  for (let i = 0; i < 5; i++) deep = { type: "parallel", branches: [[deep]] };
  invalid.push({ ...base(), steps: [deep] });
  for (const value of invalid) assert.ok(validateIntroSequence(value).length, JSON.stringify(value));
});

test("generic player has no character/scene inference or dynamic pack execution", () => {
  const source = ["IntroPlayer.qml", "IntroEffect.qml", "IntroTimeline.js"]
    .map(file => readFileSync(new URL(`../app/${file}`, import.meta.url), "utf8")).join("\n");
  assert.doesNotMatch(source, /hexon|ollie|introKind|characterFlames|createQmlObject|\beval\s*\(/i);
  assert.doesNotMatch(source, /(?:===?|!==?)\s*["'](?:rocket|tree)["']/);
});

test("sound cues are explicit built-ins, scheduled once, and not pack asset paths", () => {
  const sequence = readSequence("assets/characters/hexon");
  const timeline = compileIntroSequence(sequence) as { sounds: { at: number; cue: string }[] };
  assert.equal(timeline.sounds.length, 2);
  assert.equal(timeline.sounds[0].at, 0);
  assert.equal(timeline.sounds[0].cue, "rocket-land.opus");
  assert.equal(timeline.sounds[1].at, 4400);
  assert.equal(timeline.sounds[1].cue, "rocket-liftoff.opus");
  assert.ok(introAssetPaths(sequence).every(path => path.endsWith(".png")));
  for (const cue of ["../rocket-land.opus", "https://host/sound.opus", "/etc/file", "other.opus"]) {
    assert.ok(validateIntroSequence({ ...base(), steps: [{ type: "sound", cue }] }).length);
  }
});

test("scenery colors accept only fixed palette tokens or bounded hex literals", () => {
  const layer = { id: "pixels", type: "effect", effect: "specks",
    colors: ["theme:instruction", "theme:foreground", "#123456", "#88123456"],
    background: "theme:background", border: "theme:accent" };
  assert.deepEqual(validateIntroSequence({ ...base(), layers: [layer] }), []);
  for (const value of ["theme:config.secret", "theme:constructor", "theme:missing", "{foreground}", "red", "Qt.rgba(1,0,0,1)"]) {
    assert.ok(validateIntroSequence({ ...base(), layers: [{ ...layer, colors: [value] }] }).length);
    assert.ok(validateIntroSequence({ ...base(), layers: [{ ...layer, background: value }] }).length);
    assert.ok(validateIntroSequence({ ...base(), layers: [{ ...layer, border: value }] }).length);
  }
});
