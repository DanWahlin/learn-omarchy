#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const frames = ["ohm-1-intro", "ohm-1-intro-open"];
export const sampling = { width: 140, height: 320, filter: "nearest-neighbor" };
const sprites = new URL("../assets/characters/ohm-1/sprites/", import.meta.url);

export function sampleIntro(path) {
  const result = spawnSync("ffmpeg", ["-v", "error", "-i", path,
    "-vf", `scale=${sampling.width}:${sampling.height}:flags=neighbor,format=rgba`,
    "-frames:v", "1", "-f", "image2pipe", "-c:v", "png", "pipe:1"],
    { maxBuffer: 2 * 1024 * 1024, timeout: 10000 });
  if (result.error || result.status !== 0)
    throw new Error(`Intro pixel sampling failed: ${result.error || result.stderr.toString()}`);
  return result.stdout;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const provenance = {
    creator: "Learn Omarchy",
    copyright: "2026 Dan Wahlin",
    license: "CC-BY-4.0",
    generator: "tools/prepare-intro-pixels.mjs",
    operation: "Nearest-neighbor half-resolution sampling of existing pack artwork; original colours and alpha retained.",
    sampling,
    files: [],
  };
  for (const name of frames) {
    const source = new URL(`${name}.png`, sprites);
    const output = sampleIntro(fileURLToPath(source));
    const outputName = `${name}-pixel.png`;
    writeFileSync(new URL(outputName, sprites), output);
    provenance.files.push({
      source: `${name}.png`, output: outputName,
      sourceSha256: createHash("sha256").update(readFileSync(source)).digest("hex"),
      outputSha256: createHash("sha256").update(output).digest("hex"),
    });
  }
  writeFileSync(new URL("intro-pixels.provenance.json", sprites), JSON.stringify(provenance, null, 2) + "\n");
}
