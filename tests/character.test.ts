import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { inflateSync } from "node:zlib";
import { createHash } from "node:crypto";
import { runInNewContext } from "node:vm";
import test from "node:test";
import { discoverCharacterPacks } from "../src/character-packs.ts";

const assetRoot = new URL("../assets/characters/", import.meta.url);
const catalog = await discoverCharacterPacks({ bundledRoot: fileURLToPath(assetRoot) });
const characters = catalog.packs;
const officialCharacters = characters.filter(character => ["ohm-1", "owl"].includes(character.id));

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

test("discovered character packs have unique safe IDs and include both production coaches", () => {
  const ids = characters.map((character: { id: string }) => character.id);
  assert.ok(ids.includes("ohm-1") && ids.includes("owl"), catalog.diagnostics.join("\n"));
  assert.equal(new Set(ids).size, ids.length);
  for (const id of ids) assert.match(id, /^[a-z0-9-]+$/);
});

test("Ohm-1's ship combines a pink nose and cyan collar and trim without changing its silhouette or hatch light", () => {
  const alphaHashes = {
    intro: "e3b466013a0ace33ddcdb4a3d6eb53ddb08b2e3886da3c7e29eae4d25cb79ed5",
    "intro-open": "e91677fd1c37656e9e4f7653c82459a9aa50205e2b3ff01c4b90ad18101cdbb6",
  };
  for (const pose of ["intro", "intro-open"] as const) {
    const image = png(new URL(`ohm-1/sprites/ohm-1-${pose}.png`, assetRoot));
    assert.equal(image.width, 279);
    assert.equal(image.height, 640);
    const alpha = Buffer.alloc(image.width * image.height);
    const amber: number[] = [];
    let vividCyan = 0;
    let vividPink = 0;
    for (let offset = 0; offset < image.pixels.length; offset += 4) {
      const [r, g, b, a] = image.pixels.subarray(offset, offset + 4);
      alpha[offset / 4] = a;
      if (!a) continue;
      if (a >= 128 && g > r + 60 && b > r + 60 && b > 150) vividCyan++;
      if (r >= g + 12 && b >= g + 10 && r >= b * 0.95 &&
          Math.max(r, g, b) - Math.min(r, g, b) >= 24) {
        assert.ok(Math.floor(offset / 4 / image.width) < 145, "pink remains on the nose and antenna");
        if (a >= 128) vividPink++;
      }
      if (r > 100 && g > 35 && r > g && g > b * 1.6)
        amber.push(...image.pixels.subarray(offset, offset + 4));
    }
    assert.equal(createHash("sha256").update(alpha).digest("hex"), alphaHashes[pose]);
    assert.ok(vividCyan > 6000, "keep vivid cyan on the lower accents");
    assert.ok(vividPink > 3000, "retain a colorful pink nose");
    if (pose === "intro-open") {
      assert.equal(createHash("sha256").update(Buffer.from(amber)).digest("hex"),
        "4f7dfd26dff3a4e604b5c08972c1a62797151e6b01911b945d6076333c4cde64");
    }
  }
});
test("every discovered sprite uses explicit metadata rather than a filename convention", () => {
  for (const pack of characters) {
    assert.equal(pack.manifest.formatVersion, 1);
    for (const [role, metadata] of Object.entries(pack.manifest.sprites)) {
      const image = readFileSync(new URL(metadata.path, pack.assetUrl + "/"));
      assert.equal(image.readUInt32BE(16), metadata.frameWidth * metadata.frames, `${pack.id}:${role} width`);
      assert.equal(image.readUInt32BE(20), metadata.frameHeight, `${pack.id}:${role} height`);
    }
  }
});

for (const { id, manifest, assetUrl } of officialCharacters) {
  const sprite = (pose: string) => png(new URL(manifest.sprites[pose].path, assetUrl + "/"));

  test(`${id}: registered body baselines, anchors, tips and speech crops are valid`, () => {
    assert.equal(manifest.id, id);
    const { renderer } = manifest;
    assert.deepEqual(renderer.canvas, { width: 224, height: 192 });
    assert.ok(renderer.registrationNote.length > 0);
    for (const [name, p] of Object.entries(renderer.poses) as [string, any][]) {
      assert.ok(p.scale > 0 && p.scale < 2);
      assert.ok(Number.isFinite(p.offset.x) && Number.isFinite(p.offset.y));
      const image = sprite(name);
      assert.equal(image.height, 192);
      assert.equal(image.width, manifest.sprites[name].frameWidth * manifest.sprites[name].frames);
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
      const blink = sprite(name + "-blink");
      assert.equal(blink.width, 224);
      assert.equal(blink.height, 192);
      // Midpoint artwork is retained as authoring material, not a runtime role.
      const midpoint = png(new URL(`${id}/sprites/${id}-${name}-mid.png`, assetRoot));
      assert.equal(midpoint.width, 224);
      assert.equal(midpoint.height, 192);
    }
  });

  test(`${id}: existing strips retain their frame counts and unique artwork`, () => {
    for (const [name, count, unique] of [
      ["idle", 16, 3], ["talk", id === "ohm-1" ? 16 : 8, 3], ["flight", id === "owl" ? 2 : 1, id === "owl" ? 2 : 1],
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

test("Ohm's raised fingertip follows a rigid shoulder rotation of his original pointing arm", () => {
  const manifest = JSON.parse(readFileSync(new URL("ohm-1/character.json", assetRoot), "utf8"));
  const point = manifest.renderer.poses.point.tip;
  const up = manifest.renderer.poses["point-up"].tip;
  const radians = -Math.PI / 4;
  assert.ok(Math.abs(up.x - (131 + (point.x - 131) * Math.cos(radians) - (point.y - 84) * Math.sin(radians))) <= 1);
  assert.ok(Math.abs(up.y - (84 + (point.x - 131) * Math.sin(radians) + (point.y - 84) * Math.cos(radians))) <= 1);
  for (const pose of ["point-up", "point-up-blink"]) {
    const image = png(new URL(`ohm-1/sprites/ohm-1-${pose}.png`, assetRoot));
    assert.ok(image.alpha(up.x, up.y) > 0);
    for (let y = 88; y <= 94; y++) {
      for (let x = 132; x <= 134; x++)
        assert.ok(image.alpha(x, y) >= 250, `${pose}: the elbow joint must remain opaque at ${x},${y}`);
    }
    for (const [x, y] of [[140, 93], [140, 94], [129, 98], [131, 99]])
      assert.equal(image.alpha(x, y), 0, `${pose}: no hanging elbow remnant at ${x},${y}`);
  }
  assert.match(readFileSync(new URL("ohm-1/sprites.conf", assetRoot), "utf8"), /point_up_mode="rotate"/);
});

test("Ohm's speech glow stays inside the original chest lenses and leaves his face alone", () => {
  const manifest = JSON.parse(readFileSync(new URL("ohm-1/character.json", assetRoot), "utf8"));
  const image = png(new URL("ohm-1/sprites/ohm-1-speech.png", assetRoot));
  assert.equal(image.width, 16 * 40);
  assert.equal(image.height, 32);
  let litPixels = 0;
  for (let frame = 0; frame < 40; frame++) {
    for (let y = 0; y < 32; y++) {
      for (let x = 0; x < 16; x++) {
        const alpha = image.alpha(frame * 16 + x, y);
        if (frame === 1) assert.equal(alpha, 0, "resting frame preserves the original chest panel");
        if (alpha) litPixels++;
      }
    }
  }
  assert.ok(litPixels > 100);
  for (const name of ["idle", "point", "point-up"]) {
    const speech = manifest.renderer.poses[name].speech;
    assert.equal(speech.sprite, "speech");
    assert.equal(speech.restFrame, 1);
    assert.ok(speech.destination.y >= 92, "speech must not overlap the screen or eyes");
    assert.equal(speech.destination.width, speech.source.width);
    assert.equal(speech.destination.height, speech.source.height);
    assert.equal(manifest.sprites[name].path, `sprites/ohm-1-${name}.png`);
  }
  assert.deepEqual(manifest.sprites.talk, manifest.sprites.idle);
});

test("speech overlays select their registered role and metadata stride, with the original talk fallback", () => {
  const renderer = readFileSync(new URL("../app/CharacterSprite.qml", import.meta.url), "utf8");
  assert.match(renderer, /speech && speech\.sprite \? speech\.sprite : "talk"/);
  assert.match(renderer, /spriteSource\(root\.speechRole\)/);
  assert.match(renderer, /root\.speechFrame \* Number\(root\.sprites\[root\.speechRole\]\?\.frameWidth/);
  assert.doesNotMatch(renderer, /config\.(prefix|flames|flightFrames|flightFrameRate|pointBlink)/);
  assert.match(renderer, /smooth: false/);
});

test("HEXON cleanup removes only the audited stray locations, retaining flight particles", () => {
  for (const pose of ["point", "point-up", "point-blink", "point-up-blink", "point-mid", "point-up-mid"]) {
    const image = png(new URL(`ohm-1/sprites/ohm-1-${pose}.png`, assetRoot));
    for (const [x, y] of [[189, 23], [152, 160], [110, 164]]) assert.equal(image.alpha(x, y), 0);
  }
  const flight = png(new URL("ohm-1/sprites/ohm-1-flight.png", assetRoot));
  for (const [x, y] of [[110, 170], [97, 175], [189, 178], [101, 182]]) assert.equal(flight.alpha(x, y), 0);
  for (const [x, y] of [[51, 120], [79, 104], [31, 132]]) assert.ok(flight.alpha(x, y) > 0);
});

test("flame sockets register idle and both pointing poses without adding exhaust to flight or OLLIE", () => {
  for (const { id } of officialCharacters) {
    const config = JSON.parse(readFileSync(new URL(`${id}/character.json`, assetRoot), "utf8"));
    for (const [name, pose] of Object.entries(config.renderer.poses) as [string, any][]) {
      const sockets = pose.flameSockets || [];
      assert.equal(sockets.length, id === "ohm-1" && name !== "flight" ? 2 : 0);
      const image = png(new URL(`${id}/sprites/${id}-${name}.png`, assetRoot));
      for (const socket of sockets) {
        assert.ok(image.alpha(socket.x, socket.y) > 0, `${name} socket lies on the boot`);
        const x = pose.offset.x + socket.x * pose.scale;
        const y = pose.offset.y + socket.y * pose.scale;
        assert.ok(x >= 0 && x <= 224 && y >= 0 && y <= 192);
        assert.ok(224 - x >= 0 && 224 - x <= 224, "mirrored socket stays inside canvas");
      }
    }
    if (id === "ohm-1") {
      assert.deepEqual(config.renderer.poses.point.flameSockets, config.renderer.poses["point-up"].flameSockets);
      const idle = config.renderer.poses.idle;
      assert.deepEqual(idle.flameSockets.map((s: { x: number; y: number }) =>
        [idle.offset.x + s.x * idle.scale, idle.offset.y + s.y * idle.scale]), [[96, 181], [130, 181]]);
    }
  }
});

test("lab imports the shared renderer and launches both coaches through the repository entry point", () => {
  const lab = readFileSync(new URL("../experiments/hexon-lab/shell.qml", import.meta.url), "utf8");
  const launcher = readFileSync(new URL("../bin/hexon-lab", import.meta.url), "utf8");
  assert.match(lab, /import "\.\.\/\.\.\/app" as App/);
  assert.match(lab, /App\.CharacterSprite\s*\{/);
  assert.doesNotMatch(lab, /SpriteSequence|AnimatedSprite|\/sprites\/ohm-1-/);
  assert.doesNotMatch(launcher, /export HEXON_ASSET_ROOT/);
  assert.match(launcher, /character-lab\.qml/);
});

test("course shares registered character geometry, independent speech and installed lab assets", () => {
  const shell = readFileSync(new URL("../app/shell.qml", import.meta.url), "utf8");
  const makefile = readFileSync(new URL("../Makefile", import.meta.url), "utf8");
  assert.match(shell, /CharacterSprite\s*\{\s*id: coachArt/);
  assert.match(shell, /talking: welcomeCaption\.ready \|\| \(audioProcess\.running && !root\.audioPaused && !root\.audioStopRequested\)/);
  assert.match(shell, /animated: hexonWindow\.visible && root\.phase !== "paused"/);
  assert.match(shell, /model: coachArt\.flameSockets/);
  assert.match(shell, /upTipLocalX: 8 \+ coachArt\.upTipX/);
  assert.match(shell, /pointTipLocalY: \(height - 192\) \+ coachArt\.pointTipY/);
  assert.doesNotMatch(shell, /SpriteSequence|poseStage|pointPoseScale|coachSpriteLoader/);
  assert.match(makefile, /cp -R app courses .*character-lab\.qml/);
  assert.match(makefile, /install -m 644 experiments\/hexon-lab\/shell\.qml experiments\/hexon-lab\/qmldir/);
});

test("development and packaged launchers use distinct desktop IDs", () => {
  const makefile = readFileSync(new URL("../Makefile", import.meta.url), "utf8");
  assert.match(makefile, /learn-omarchy-local\.desktop/);
  assert.match(makefile, /rm -f "\$\(USER_DESKTOP_DIR\)\/learn-omarchy\.desktop"/);
});

test("rocket tour travel stays upright without letting flight facing move the landing target", () => {
  const shell = readFileSync(new URL("../app/shell.qml", import.meta.url), "utf8");
  assert.match(shell, /uprightFlight: Boolean\(root\.characterConfig\.motion &&\s*root\.characterConfig\.motion\.tourFlight === "upright"\)/);
  assert.match(shell, /flying: hexonCoach\.targetsIntro \? introPlayer\.characterFlying :\s*hexonCoach\.isFlying && !hexonCoach\.uprightFlight/);
  assert.match(shell, /landmarkFacing: hexonCoach\.pointDirection/);
  assert.match(shell, /hexonCoach\.uprightFlight \? 0 : Math\.min\(45, horizontal \* 0\.065\)/);
});

test("reselecting the active lab coach preserves its loaded manifest", () => {
  const lab = readFileSync(new URL("../experiments/hexon-lab/shell.qml", import.meta.url), "utf8");
  const select = lab.match(/function selectCharacter\(name\) \{[\s\S]*?\n  \}/)?.[0];
  assert.ok(select);
  const config = { id: "ohm-1" };
  const context = {
    characters, characterName: "ohm-1", characterConfig: config,
    loadError: "", frame: 3, nextCharacter: "ohm-1",
    stopIntro() {},
    packStore: { select(name: string) { context.characterName = name; } },
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
  assert.equal(context.characterConfig, config, "the shared store owns the manifest binding");
  assert.equal(context.frame, -1);
});
