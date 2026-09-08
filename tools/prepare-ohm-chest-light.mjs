#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { join } from "node:path";

const directory = fileURLToPath(new URL("../assets/characters/ohm-1/sprites/", import.meta.url));
const width = 16;
const height = 32;
const frames = 40;
const strip = Buffer.alloc(width * frames * height * 4);
// Stack pose-specific patches in each frame to retain each lens's native shape.
for (const patch of [
  { pose: "idle", x: 92, y: 111, width: 14, height: 14, row: 0 },
  { pose: "point", x: 99, y: 92, width: 13, height: 13, row: 16 },
]) {
  const pixels = execFileSync("magick", [join(directory, `ohm-1-${patch.pose}.png`),
    "-crop", `${patch.width}x${patch.height}+${patch.x}+${patch.y}`, "+repage", "-depth", "8", "rgba:-"]);
  if (pixels.length !== patch.width * patch.height * 4) throw new Error(`Unexpected ${patch.pose} chest crop`);
  for (let frame = 0; frame < frames; frame++) {
    const strength = frame === 0 ? 0.35 : frame === 1 ? 0 :
      0.85 * Math.sin(Math.PI * frame / frames) ** 2;
    for (let y = 0; y < patch.height; y++) {
      for (let x = 0; x < patch.width; x++) {
        const source = (y * patch.width + x) * 4;
        const [r, g, b, alpha] = pixels.subarray(source, source + 4);
        // Leave the housing, engraved mark, and original highlights untouched.
        if (r < 100 || r < g * 1.35 || b < g * 1.15 || alpha === 0) continue;
        const target = ((patch.row + y) * width * frames + frame * width + x) * 4;
        const luminance = Math.max(r, b) / 255;
        strip[target] = Math.round(255 * luminance);
        strip[target + 1] = Math.round(183 * luminance);
        strip[target + 2] = Math.round(90 * luminance);
        strip[target + 3] = Math.round(alpha * strength);
      }
    }
  }
}
const output = join(directory, "ohm-1-speech.png");
execFileSync("magick", ["-size", `${width * frames}x${height}`, "-depth", "8", "rgba:-",
  "-strip", "-define", "png:color-type=6", output], { input: strip });
console.log(`Prepared ${frames} chest-light frames at ${output}`);
