#!/usr/bin/env node
import { mkdirSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const sampleRate = 48000;
export const soundDefinitions = {
  correct: { duration: 0.16, notes: [[0, 659.25, 0.145, 1]] },
  wrong: { duration: 0.22, notes: [[0, 349.23, 0.15, 0.7], [0.065, 293.66, 0.145, 0.7]] },
  "step-complete": { duration: 0.34, notes: [[0, 523.25, 0.20, 0.75], [0.10, 783.99, 0.23, 0.8]] },
  "module-complete": { duration: 0.58, notes: [[0, 523.25, 0.30, 0.65],
    [0.10, 659.25, 0.32, 0.65], [0.21, 783.99, 0.35, 0.75]] },
};

export function renderSound(definition) {
  const samples = new Float64Array(Math.round(definition.duration * sampleRate));
  for (const [start, frequency, duration, gain] of definition.notes) {
    for (let i = Math.round(start * sampleRate); i < samples.length; i++) {
      const t = i / sampleRate - start;
      if (t < 0 || t >= duration) continue;
      const attack = Math.sin(Math.min(1, t / 0.012) * Math.PI / 2) ** 2;
      const release = Math.sin(Math.min(1, (duration - t) / 0.05) * Math.PI / 2) ** 2;
      const phase = 2 * Math.PI * frequency * t;
      samples[i] += gain * attack * release * Math.exp(-5 * t / duration)
        * (Math.sin(phase) + 0.10 * Math.sin(2 * phase) + 0.025 * Math.sin(3 * phase));
    }
  }
  let peak = 0;
  for (const value of samples) peak = Math.max(peak, Math.abs(value));
  // -19.2 dBFS peak leaves narration comfortably in the foreground.
  const gain = peak ? 0.11 / peak : 0;
  const wav = Buffer.alloc(44 + samples.length * 2);
  wav.write("RIFF", 0);
  wav.writeUInt32LE(wav.length - 8, 4);
  wav.write("WAVEfmt ", 8);
  wav.writeUInt32LE(16, 16);
  wav.writeUInt16LE(1, 20);
  wav.writeUInt16LE(1, 22);
  wav.writeUInt32LE(sampleRate, 24);
  wav.writeUInt32LE(sampleRate * 2, 28);
  wav.writeUInt16LE(2, 32);
  wav.writeUInt16LE(16, 34);
  wav.write("data", 36);
  wav.writeUInt32LE(samples.length * 2, 40);
  for (let i = 0; i < samples.length; i++) wav.writeInt16LE(Math.round(samples[i] * gain * 32767), 44 + i * 2);
  return wav;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const destination = resolve(process.argv[2] || fileURLToPath(new URL("../assets/sounds", import.meta.url)));
  mkdirSync(destination, { recursive: true });
  for (const [name, definition] of Object.entries(soundDefinitions)) {
    const path = resolve(destination, `interaction-${name}.wav`);
    writeFileSync(path, renderSound(definition));
  }
}
