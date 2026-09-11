import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { frames, sampleIntro, sampling } from "../tools/prepare-intro-pixels.mjs";
import { compileIntroSequence, sampleIntroSequence } from "../src/intro-sequence.ts";

const sprites = new URL("../assets/characters/ohm-1/sprites/", import.meta.url);
function rgba(input: URL | Buffer) {
  const result = spawnSync("ffmpeg", ["-v", "error", "-i", Buffer.isBuffer(input) ? "pipe:0" : fileURLToPath(input),
    "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgba", "pipe:1"],
    { input: Buffer.isBuffer(input) ? input : undefined, maxBuffer: 2 * 1024 * 1024, timeout: 10000 });
  assert.equal(result.status, 0, result.stderr.toString());
  return result.stdout;
}

test("pack-owned rocket samples are reproducible and retain only original palette and alpha", () => {
  const provenance = JSON.parse(readFileSync(new URL("intro-pixels.provenance.json", sprites), "utf8"));
  assert.equal(provenance.license, "CC-BY-4.0");
  for (const name of frames) {
    const source = new URL(`${name}.png`, sprites);
    const output = new URL(`${name}-pixel.png`, sprites);
    const stored = readFileSync(output);
    // PNG compression can vary by FFmpeg version; the sampled pixels cannot.
    assert.deepEqual(rgba(stored), rgba(sampleIntro(fileURLToPath(source))));
    const entry = provenance.files.find(file => file.source === `${name}.png`);
    assert.equal(entry.sourceSha256, createHash("sha256").update(readFileSync(source)).digest("hex"));
    assert.equal(entry.outputSha256, createHash("sha256").update(stored).digest("hex"));
    const original = rgba(source);
    const sampled = rgba(output);
    assert.equal(sampled.length, sampling.width * sampling.height * 4);
    const palette = new Set<number>();
    for (let i = 0; i < original.length; i += 4) palette.add(original.readUInt32LE(i));
    for (let i = 0; i < sampled.length; i += 4)
      assert.ok(palette.has(sampled.readUInt32LE(i)), "nearest sampling must not interpolate colour or alpha");
  }
});

test("sampled frames retain exact original scene geometry and pack-owned selection", () => {
  const sequence = JSON.parse(readFileSync(new URL("../assets/characters/ohm-1/intro/sequence.json", import.meta.url), "utf8"));
  const timeline = compileIntroSequence(sequence);
  for (const id of ["hull", "hatch"]) {
    const layer = sequence.layers.find(layer => layer.id === id);
    assert.ok(layer.images[0].endsWith("-pixel.png"));
    assert.equal(layer.aspect, 279 / 640);
  }
  for (const height of [720, 1080, 1440]) {
    const legacy = sampleIntroSequence(timeline, 2400, 1920, height,
      { hull: { width: 279, height: 640 }, hatch: { width: 279, height: 640 } });
    const sampled = sampleIntroSequence(timeline, 2400, 1920, height,
      { hull: sampling, hatch: sampling });
    assert.deepEqual(sampled, legacy);
  }
});
