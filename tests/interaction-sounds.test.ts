import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { renderSound, sampleRate, soundDefinitions } from "../tools/generate-interaction-sounds.mjs";

test("original interaction cues are reproducible quiet PCM with click-free edges", () => {
  for (const [name, definition] of Object.entries(soundDefinitions)) {
    const wav = readFileSync(new URL(`../assets/sounds/interaction-${name}.wav`, import.meta.url));
    assert.deepEqual(wav, renderSound(definition), name);
    assert.equal(wav.toString("ascii", 0, 4), "RIFF");
    assert.equal(wav.readUInt16LE(22), 1);
    assert.equal(wav.readUInt32LE(24), sampleRate);
    assert.equal(wav.readUInt16LE(34), 16);
    const count = (wav.length - 44) / 2;
    assert.equal(count, Math.round(definition.duration * sampleRate));
    let peak = 0, energy = 0, edgePeak = 0, mean = 0;
    for (let i = 0; i < count; i++) {
      const value = wav.readInt16LE(44 + i * 2) / 32767;
      peak = Math.max(peak, Math.abs(value));
      energy += value * value;
      mean += value;
      if (i < 48 || i > count - 48) edgePeak = Math.max(edgePeak, Math.abs(value));
    }
    assert.ok(peak > 0.10 && peak < 0.111, name);
    assert.ok(Math.sqrt(energy / count) < 0.045, `${name} stays restrained`);
    assert.ok(edgePeak < 0.004, `${name} has soft edges`);
    assert.ok(Math.abs(mean / count) < 0.001, `${name} has no significant DC offset`);
  }
});
