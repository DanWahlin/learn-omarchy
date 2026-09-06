import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { inflateSync } from "node:zlib";
import { runInNewContext } from "node:vm";
import test from "node:test";

const assetRoot = new URL("../assets/characters/", import.meta.url);
const characters = JSON.parse(readFileSync(new URL("index.json", assetRoot), "utf8")).characters;

// Decode the shipped 8-bit RGBA PNGs without adding an image-library dependency.
function png(url: URL) {
  const file = readFileSync(url);
  assert.equal(file.subarray(0, 8).toString("hex"), "89504e470d0a1a0a");
  const width = file.readUInt32BE(16);
  const height = file.readUInt32BE(20);
  assert.equal(file[24], 8, "sprite bit depth");
  assert.equal(file[25], 6, "sprite RGBA format");
  assert.equal(file[28], 0, "noninterlaced sprites");
  const chunks: Buffer[] = [];
  for (let offset = 8; offset < file.length;) {
    const length = file.readUInt32BE(offset);
    if (file.toString("ascii", offset + 4, offset + 8) === "IDAT") {
      chunks.push(file.subarray(offset + 8, offset + 8 + length));
    }
    offset += length + 12;
  }
  const raw = inflateSync(Buffer.concat(chunks));
  const stride = width * 4;
  assert.equal(raw.length, height * (stride + 1));
  const pixels = Buffer.alloc(width * height * 4);
  for (let y = 0; y < height; y++) {
    const filter = raw[y * (stride + 1)];
    assert.ok(filter <= 4);
    for (let x = 0; x < stride; x++) {
      const left = x >= 4 ? pixels[y * stride + x - 4] : 0;
      const above = y > 0 ? pixels[(y - 1) * stride + x] : 0;
      const corner = y > 0 && x >= 4 ? pixels[(y - 1) * stride + x - 4] : 0;
      const prediction = left + above - corner;
      const a = Math.abs(prediction - left);
      const b = Math.abs(prediction - above);
      const c = Math.abs(prediction - corner);
      const paeth = a <= b && a <= c ? left : b <= c ? above : corner;
      const delta = [0, left, above, Math.floor((left + above) / 2), paeth][filter];
      pixels[y * stride + x] = (raw[y * (stride + 1) + x + 1] + delta) & 255;
    }
  }
  return {
    width, height, pixels,
    alpha(x: number, y: number) { return pixels[(y * width + x) * 4 + 3]; },
    crop(x: number, y: number, w: number, h: number) {
      return Buffer.concat(Array.from({ length: h }, (_, row) =>
        pixels.subarray(((y + row) * width + x) * 4, ((y + row) * width + x + w) * 4)));
    },
  };
}

test("character index has unique safe IDs and both production coaches", () => {
  const ids = characters.map((character: { id: string }) => character.id);
  assert.deepEqual(ids.toSorted(), ["hexon", "owl"]);
  assert.equal(new Set(ids).size, ids.length);
  for (const id of ids) assert.match(id, /^[a-z0-9-]+$/);
});

for (const { id } of characters) {
  const manifest = JSON.parse(readFileSync(new URL(`${id}/character.json`, assetRoot), "utf8"));
  const sprite = (pose: string) => png(new URL(`${id}/sprites/${id}-${pose}.png`, assetRoot));

  test(`${id}: registered body baselines, anchors, tips and speech crops are valid`, () => {
    assert.equal(manifest.prefix, id);
    const { renderer } = manifest;
    assert.deepEqual(renderer.canvas, { width: 224, height: 192 });
    assert.ok(renderer.registrationNote.length > 0);
    for (const [name, p] of Object.entries(renderer.poses) as [string, any][]) {
      assert.ok(p.scale > 0 && p.scale < 2);
      assert.ok(Number.isFinite(p.offset.x) && Number.isFinite(p.offset.y));
      const image = sprite(name);
      assert.equal(image.height, 192);
      assert.equal(image.width, p.frameWidth * (name === "idle" ? 16 : name === "flight" ? manifest.flightFrames : 1));
      if (name === "flight") continue;
      let soleRow = image.height - 1;
      while (soleRow >= 0 && !Array.from({ length: p.frameWidth }, (_, x) =>
        image.alpha(x, soleRow)).some(alpha => alpha >= 128)) soleRow--;
      assert.equal(p.baseline, soleRow, `${name} baseline matches actual opaque soles`);
      assert.ok(Math.abs(p.baseline * p.scale + p.offset.y - renderer.baseline) < 0.01, `${name} sole baseline`);
      assert.ok(Math.abs(p.bodyAnchorX * p.scale + p.offset.x - renderer.bodyAnchorX) < 0.01, `${name} torso anchor`);
      if (name === "idle") continue;
      for (const axis of ["x", "y"]) {
        const tip = p.tip[axis] * p.scale + p.offset[axis];
        assert.ok(tip >= 0 && tip <= (axis === "x" ? 224 : 192));
      }
      let opaqueTip = false;
      for (let y = p.tip.y - 3; y <= p.tip.y + 3; y++)
        for (let x = p.tip.x - 3; x <= p.tip.x + 3; x++)
          opaqueTip ||= image.alpha(x, y) > 127;
      assert.ok(opaqueTip, `${name} tip is on the pointing limb, not empty canvas`);
      for (const kind of ["source", "destination"]) {
        const box = p.speech[kind];
        assert.ok(box.width > 0 && box.height > 0);
        assert.ok(box.x >= 0 && box.y >= 0);
        assert.ok(box.x + box.width <= (kind === "source" ? (p.speech.frameWidth || 192) : 224));
        assert.ok(box.y + box.height <= 192);
      }
      const talk = sprite(p.speech.sprite || "talk");
      const box = p.speech.source;
      assert.notDeepEqual(talk.crop(box.x, box.y, box.width, box.height),
        talk.crop(box.x + (p.speech.frameWidth || 192), box.y, box.width, box.height), "registered speech crop changes expression");
      for (const suffix of ["-blink", "-mid"]) {
        const alternate = sprite(name + suffix);
        assert.equal(alternate.width, 224);
        assert.equal(alternate.height, 192);
      }
    }
  });

  test(`${id}: existing strips retain their frame counts and unique artwork`, () => {
    for (const [name, count, unique] of [
      ["idle", 16, 3], ["talk", 8, 3], ["flight", id === "owl" ? 2 : 1, id === "owl" ? 2 : 1],
    ] as const) {
      const image = sprite(name);
      const frameWidth = name === "flight" ? 256 : 192;
      assert.equal(image.width, frameWidth * count);
      const frames = Array.from({ length: count }, (_, frame) =>
        image.crop(frame * frameWidth, 0, frameWidth, 192).toString("base64"));
      assert.equal(new Set(frames).size, unique, `${name} unique frames`);
      if (name === "idle") {
        assert.equal(frames[0], frames[10]);
        assert.equal(frames[11], frames[13]);
        assert.notEqual(frames[11], frames[12]);
      }
    }
  });
}

test("OLLIE speech preserves both eyes and replaces the complete native beak in both pointing poses", () => {
  const manifest = JSON.parse(readFileSync(new URL("owl/character.json", assetRoot), "utf8"));
  const speech = png(new URL("owl/sprites/owl-speech.png", assetRoot));
  const idle = png(new URL("owl/sprites/owl-idle.png", assetRoot));
  const talk = png(new URL("owl/sprites/owl-talk.png", assetRoot));
  assert.equal(speech.width, 22 * 8);
  assert.equal(speech.height, 30);
  for (let frame = 0; frame < 8; frame++) {
    for (let y = 0; y < 192; y++) {
      for (let x = 0; x < 192; x++) {
        const inPatch = x >= 90 && x < 112 && y >= 88 && y < 118;
        const alpha = inPatch ? speech.alpha(frame * 22 + x - 90, y - 88) : 0;
        assert.ok(alpha === 0 || alpha === 255, "mask keeps hard pixel-art edges");
        if (alpha === 0) {
          assert.deepEqual(talk.crop(frame * 192 + x, y, 1, 1), idle.crop(x, y, 1, 1),
            `frame ${frame}: eyes/body outside the beak mask remain unchanged at ${x},${y}`);
        } else {
          const [r, g, b] = speech.crop(frame * 22 + x - 90, y - 88, 1, 1);
          assert.ok(!(g > r * 1.2 && b > r * 1.2 && g > 60),
            `frame ${frame}: no turquoise eye fragment in the speech patch at ${x},${y}`);
        }
      }
    }
    for (const [name, bounds] of [
      ["point", [91, 78, 107, 96]], ["point-blink", [91, 78, 107, 96]],
      ["point-up", [93, 76, 107, 94]], ["point-up-blink", [93, 76, 107, 94]],
    ] as const) {
      const pose = manifest.renderer.poses[name.replace(/-blink$/, "")];
      const { destination, source } = pose.speech;
      assert.equal(pose.speech.sprite, "speech");
      assert.equal(pose.speech.frameWidth, 22);
      assert.equal(destination.width, source.width, "do not squeeze the beak separately from the head");
      assert.equal(destination.height, source.height);
      const body = png(new URL(`owl/sprites/owl-${name}.png`, assetRoot));
      const pending = [[99, 86]];
      const visited = new Set<string>();
      let beakPixels = 0;
      while (pending.length) {
        const [x, y] = pending.pop()!;
        const key = `${x},${y}`;
        if (visited.has(key) || x < bounds[0] || x > bounds[2] || y < bounds[1] || y > bounds[3]) continue;
        visited.add(key);
        const [r, g, b] = body.crop(x, y, 1, 1);
        if (!((r < 140 && g < 140 && b < 140) || (r > 140 && g < 210 && b < 120))) continue;
        beakPixels++;
        assert.equal(speech.alpha(frame * 22 + x - destination.x, y - destination.y), 255,
          `${name} frame ${frame}: no detached native beak edge left at ${x},${y}`);
        pending.push([x - 1, y], [x + 1, y], [x, y - 1], [x, y + 1]);
      }
      assert.ok(beakPixels > 100, "check the connected beak, not nearby disconnected eye outlines");
    }
  }
});

test("speech overlays select their registered strip and stride, with the original talk fallback", () => {
  const renderer = readFileSync(new URL("../app/CharacterSprite.qml", import.meta.url), "utf8");
  assert.match(renderer, /spriteSource\(root\.speech\.sprite \|\| "talk"\)/);
  assert.match(renderer, /root\.currentFrame \* Number\(root\.speech\.frameWidth \|\| 192\)/);
  assert.match(renderer, /smooth: false/);
});

test("HEXON cleanup removes only the audited stray locations, retaining flight particles", () => {
  for (const pose of ["point", "point-up", "point-blink", "point-up-blink", "point-mid", "point-up-mid"]) {
    const image = png(new URL(`hexon/sprites/hexon-${pose}.png`, assetRoot));
    for (const [x, y] of [[189, 23], [152, 160], [110, 164]]) assert.equal(image.alpha(x, y), 0);
  }
  const flight = png(new URL("hexon/sprites/hexon-flight.png", assetRoot));
  for (const [x, y] of [[110, 170], [97, 175], [189, 178], [101, 182]]) assert.equal(flight.alpha(x, y), 0);
  for (const [x, y] of [[51, 120], [79, 104], [31, 132]]) assert.ok(flight.alpha(x, y) > 0);
});

test("flame sockets register idle and both pointing poses without adding exhaust to flight or OLLIE", () => {
  for (const { id } of characters) {
    const config = JSON.parse(readFileSync(new URL(`${id}/character.json`, assetRoot), "utf8"));
    for (const [name, pose] of Object.entries(config.renderer.poses) as [string, any][]) {
      const sockets = pose.flameSockets || [];
      assert.equal(sockets.length, id === "hexon" && name !== "flight" ? 2 : 0);
      const image = png(new URL(`${id}/sprites/${id}-${name}.png`, assetRoot));
      for (const socket of sockets) {
        assert.ok(image.alpha(socket.x, socket.y) > 0, `${name} socket lies on the boot`);
        const x = pose.offset.x + socket.x * pose.scale;
        const y = pose.offset.y + socket.y * pose.scale;
        assert.ok(x >= 0 && x <= 224 && y >= 0 && y <= 192);
        assert.ok(224 - x >= 0 && 224 - x <= 224, "mirrored socket stays inside canvas");
      }
    }
    if (id === "hexon") {
      assert.deepEqual(config.renderer.poses.point.flameSockets, config.renderer.poses["point-up"].flameSockets);
      const idle = config.renderer.poses.idle;
      assert.deepEqual(idle.flameSockets.map((s: { x: number; y: number }) =>
        [idle.offset.x + s.x * idle.scale, idle.offset.y + s.y * idle.scale]), config.idleFlames);
    }
  }
});

test("lab imports the shared renderer and launches both coaches through the repository entry point", () => {
  const lab = readFileSync(new URL("../experiments/hexon-lab/shell.qml", import.meta.url), "utf8");
  const launcher = readFileSync(new URL("../bin/hexon-lab", import.meta.url), "utf8");
  assert.match(lab, /import "\.\.\/\.\.\/app" as App/);
  assert.match(lab, /App\.CharacterSprite\s*\{/);
  assert.doesNotMatch(lab, /SpriteSequence|AnimatedSprite|\/sprites\/hexon-/);
  assert.doesNotMatch(launcher, /export HEXON_ASSET_ROOT/);
  assert.match(launcher, /character-lab\.qml/);
});

test("course shares registered character geometry, independent speech and installed lab assets", () => {
  const shell = readFileSync(new URL("../app/shell.qml", import.meta.url), "utf8");
  const makefile = readFileSync(new URL("../Makefile", import.meta.url), "utf8");
  assert.match(shell, /CharacterSprite\s*\{\s*id: coachArt/);
  assert.match(shell, /talking: audioProcess\.running && !root\.audioPaused && !root\.audioStopRequested/);
  assert.match(shell, /animated: hexonWindow\.visible && root\.phase !== "paused"/);
  assert.match(shell, /model: coachArt\.flameSockets/);
  assert.match(shell, /upTipLocalX: 8 \+ coachArt\.upTipX/);
  assert.match(shell, /pointTipLocalY: \(height - 192\) \+ coachArt\.pointTipY/);
  assert.doesNotMatch(shell, /SpriteSequence|poseStage|pointPoseScale|coachSpriteLoader/);
  assert.match(makefile, /cp -R app courses experiments .*character-lab\.qml/);
});

test("rocket tour travel stays upright without letting flight facing move the landing target", () => {
  const shell = readFileSync(new URL("../app/shell.qml", import.meta.url), "utf8");
  assert.match(shell, /uprightFlight: root\.characterFlames && \(targetsTour \|\| targetsIntro\)/);
  assert.match(shell, /flying: hexonCoach\.isFlying && !hexonCoach\.uprightFlight/);
  assert.match(shell, /landmarkFacing: hexonCoach\.pointDirection/);
  assert.match(shell, /hexonCoach\.uprightFlight \? 0 : Math\.min\(45, horizontal \* 0\.065\)/);
});

test("reselecting the active lab coach preserves its loaded manifest", () => {
  const lab = readFileSync(new URL("../experiments/hexon-lab/shell.qml", import.meta.url), "utf8");
  const select = lab.match(/function selectCharacter\(name\) \{[\s\S]*?\n  \}/)?.[0];
  assert.ok(select);
  const config = { prefix: "hexon" };
  const context = {
    characters, characterName: "hexon", characterConfig: config,
    loadError: "", frame: 3, nextCharacter: "hexon",
  };
  const invoke = () => runInNewContext(select + "\nselectCharacter(nextCharacter)", context);
  assert.equal(invoke(), "ok");
  assert.equal(context.characterConfig, config);
  assert.equal(context.frame, 3);
  context.nextCharacter = "unknown";
  assert.equal(invoke(), "invalid-character");
  assert.equal(context.characterConfig, config);
  context.nextCharacter = "owl";
  assert.equal(invoke(), "ok");
  assert.equal(context.characterName, "owl");
  assert.equal(Object.keys(context.characterConfig).length, 0);
  assert.equal(context.frame, -1);
});
