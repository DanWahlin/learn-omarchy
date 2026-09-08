import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import test from "node:test";

test("welcome birds retain CC0 provenance and a ten-second asset with a quiet fade-out", () => {
  const audio = new URL("../assets/sounds/birds-welcome.opus", import.meta.url);
  const provenance = JSON.parse(readFileSync(new URL("../assets/sounds/birds-welcome.provenance.json", import.meta.url), "utf8"));
  assert.equal(provenance.license, "CC0-1.0");
  assert.equal(provenance.creator, "isaiah658");
  assert.equal(provenance.outputSha256, createHash("sha256").update(readFileSync(audio)).digest("hex"));
  const decoded = spawnSync("ffmpeg", ["-v", "error", "-i", fileURLToPath(audio),
    "-ac", "1", "-ar", "48000", "-f", "f32le", "pipe:1"], { maxBuffer: 4 * 1024 * 1024, timeout: 10000 });
  assert.equal(decoded.error, undefined);
  assert.equal(decoded.status, 0, decoded.stderr.toString());
  const samples = decoded.stdout.length / 4;
  assert.ok(Math.abs(samples / 48000 - 10) < 0.04, "ambience lasts approximately ten seconds");
  function rms(start: number, end: number) {
    let sum = 0;
    for (let index = start; index < end; index++) sum += decoded.stdout.readFloatLE(index * 4) ** 2;
    return Math.sqrt(sum / (end - start));
  }
  const body = rms(48000, 7 * 48000);
  assert.ok(body > 0.00001, "the recording isn't silent");
  assert.ok(rms(samples - 4800, samples) < body * 0.15, "the final 100 ms fades well below the background level");
});
