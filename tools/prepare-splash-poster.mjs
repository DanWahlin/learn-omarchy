#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const poster = {
  width: 1536, height: 1024,
  source: "learn-omarchy.png", output: "learn-omarchy-poster.png",
  accentHue: 318, flameHue: 300,
};
const assets = new URL("../assets/splash/", import.meta.url);

function ffmpeg(args, input) {
  const result = spawnSync("ffmpeg", ["-v", "error", ...args],
    { input, maxBuffer: 16 * 1024 * 1024, timeout: 15000 });
  if (result.error || result.status !== 0)
    throw new Error(`Splash palette preparation failed: ${result.error || result.stderr.toString()}`);
  return result.stdout;
}

export function decodePoster(input) {
  return ffmpeg(["-i", Buffer.isBuffer(input) ? "pipe:0" : input,
    "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"],
  Buffer.isBuffer(input) ? input : undefined);
}

export function recolorPoster(original) {
  if (original.length !== poster.width * poster.height * 3)
    throw new Error("The source splash must be 1536 by 1024 RGB pixels.");
  const output = Buffer.from(original);
  for (let i = 0; i < original.length; i += 3) {
    const x = (i / 3) % poster.width, y = Math.floor(i / 3 / poster.width);
    const robot = x >= 196 && x < 520 && y >= 330 && y < 860;
    const scarf = x >= 1250 && x < 1370 && y >= 402 && y < 462;
    if (!robot && !scarf) continue;
    const r = original[i] / 255, g = original[i + 1] / 255, b = original[i + 2] / 255;
    const value = Math.max(r, g, b), low = Math.min(r, g, b), chroma = value - low;
    if (chroma === 0 || value < 0.08) continue;
    const saturation = chroma / value;
    const hue = ((value === r ? (g - b) / chroma :
      value === g ? (b - r) / chroma + 2 : (r - g) / chroma + 4) * 60 + 360) % 360;
    const accent = saturation > 0.2 && hue >= 330;
    const flame = robot && y >= 720 && saturation > 0.2 && hue >= 10 && hue <= 70;
    if (!accent && !flame) continue;
    // Preserve the original shading, texture and white-hot cores; shift only hue.
    const h = (flame ? poster.flameHue : poster.accentHue) / 60;
    const secondary = chroma * (1 - Math.abs(h % 2 - 1));
    const rgb = h < 5 ? [secondary, 0, chroma] : [chroma, 0, secondary];
    for (let channel = 0; channel < 3; channel++)
      output[i + channel] = Math.round((rgb[channel] + low) * 255);
  }
  return output;
}

export function preparePoster() {
  const pixels = decodePoster(fileURLToPath(new URL(poster.source, assets)));
  return ffmpeg(["-f", "rawvideo", "-pixel_format", "rgb24",
    "-video_size", `${poster.width}x${poster.height}`, "-i", "pipe:0",
    "-frames:v", "1", "-f", "image2pipe", "-c:v", "png", "pipe:1"], pixels);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const image = preparePoster();
  writeFileSync(new URL(poster.output, assets), image);
  writeFileSync(new URL("poster.provenance.json", assets), JSON.stringify({
    creator: "Learn Omarchy",
    copyright: "2026 Dan Wahlin",
    license: "CC-BY-4.0",
    generator: "tools/prepare-splash-poster.mjs",
    sourceProvenance: "provenance.json",
    operation: "Deterministic RGB normalization of the approved splash master, preserving its exact composition, Neon Aurora wordmark, character artwork and local glow treatment.",
    ...poster,
    sourceSha256: createHash("sha256").update(readFileSync(new URL(poster.source, assets))).digest("hex"),
    outputSha256: createHash("sha256").update(image).digest("hex"),
  }, null, 2) + "\n");
}
