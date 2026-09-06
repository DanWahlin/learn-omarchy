#!/usr/bin/env -S node --experimental-strip-types

import { readdir } from "node:fs/promises";
import { join, relative, resolve } from "node:path";
import {
  ffmpegVersion, fileHash, normalizationIsFresh, normalizeAudio, readManifest, writeManifest,
} from "./audio-production.ts";

const root = resolve(process.argv[2] ?? "courses/audio");
const manifestPath = join(root, "production-manifest.json");
const manifest = await readManifest(manifestPath);
const version = ffmpegVersion();

async function audioFiles(directory: string): Promise<string[]> {
  const files: string[] = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) files.push(...await audioFiles(path));
    else if (entry.isFile() && entry.name.endsWith(".mp3") && !entry.name.endsWith(".staging.mp3")) files.push(path);
  }
  return files.sort();
}

let normalized = 0;
let skipped = 0;
for (const path of await audioFiles(root)) {
  const key = relative(root, path).split("\\").join("/");
  const previous = manifest.files[key];
  const currentHash = await fileHash(path);
  if (normalizationIsFresh(previous, currentHash, version)) {
    skipped++;
    continue;
  }
  // Never attach an old text claim to a file that was replaced outside this tool.
  const provenance = previous?.normalization.outputHash === currentHash
    ? previous.provenance : { kind: "inherited", sourceProvenance: "unknown" } as const;
  manifest.files[key] = await normalizeAudio(path, path, provenance, version);
  await writeManifest(manifestPath, manifest);
  normalized++;
  const measured = manifest.files[key].normalization;
  console.log(`${key}: ${measured.source.integratedLufs} → ${measured.output.integratedLufs} LUFS; ${measured.output.truePeakDbtp} dBTP`);
}
console.log(`Normalized ${normalized}; skipped ${skipped} current file(s).`);
