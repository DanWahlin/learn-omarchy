import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import type { CharacterManifest } from "../src/character-packs.ts";
import { clipIssues, timingIssues, type AudioClip } from "../tools/audio-coverage.ts";
import { sha256, prepareSpeech, productionOptions, type ProductionEntry } from "../tools/audio-production.ts";

const pack: CharacterManifest = JSON.parse(await readFile(new URL("../assets/characters/ohm-1/character.json", import.meta.url), "utf8"));
const manifest = JSON.parse(await readFile(new URL("../courses/audio/production-manifest.json", import.meta.url), "utf8"));
const example: ProductionEntry = manifest.files["ohm-1/host-welcome.mp3"];
const clip: AudioClip = { character: "ohm-1", step: "test", part: "instruction",
  path: "/unused/audio.mp3", key: "ohm-1/test.mp3", text: "Hi! I'm HEXON. Welcome to Omarchy." };

function matchingEntry(): ProductionEntry {
  const entry = structuredClone(example);
  assert.equal(entry.provenance.kind, "generated");
  if (entry.provenance.kind !== "generated") throw new Error("Expected generated fixture");
  entry.provenance.spec.textHash = sha256(clip.text);
  entry.provenance.spec.preparedTextHash = sha256(prepareSpeech(clip.text, pack.spokenName ?? pack.displayName, { Omarchy: "Omaachi" }));
  entry.provenance.spec.voice = pack.narration.mode === "own" ? pack.narration.voices!.azure! : "";
  entry.normalization.options = productionOptions;
  return entry;
}

test("coverage catches absent recordings and unverified wording", () => {
  const entry = matchingEntry();
  assert.deepEqual(clipIssues(clip, pack, entry, undefined), ["missing recording"]);
  assert.deepEqual(clipIssues(clip, pack, undefined, "hash"), ["missing production metadata"]);
  entry.provenance = { kind: "inherited", sourceProvenance: "unknown" };
  assert.deepEqual(clipIssues(clip, pack, entry, entry.normalization.outputHash), ["unverified original wording"]);
});

test("coverage checks actual speech, voice and bytes without invalidating historical pack IDs", () => {
  const entry = matchingEntry();
  if (entry.provenance.kind !== "generated") throw new Error("Expected generated fixture");
  entry.provenance.spec.character = { id: "previous-id", displayName: "Previous display" };
  assert.deepEqual(clipIssues(clip, pack, entry, entry.normalization.outputHash), []);
  assert.ok(clipIssues({ ...clip, text: "New instruction." }, pack, entry, entry.normalization.outputHash).includes("outdated spoken text"));
  entry.provenance.spec.voice = "wrong-voice";
  assert.ok(clipIssues(clip, pack, entry, entry.normalization.outputHash).includes("outdated voice"));
  assert.ok(clipIssues(clip, pack, entry, "different-bytes").includes("recording hash mismatch"));
});

test("optional timing falls back when absent but rejects stale, mismatched, or out-of-range data", () => {
  assert.deepEqual(timingIssues(clip, { reason: "missing-timing" }), []);
  assert.deepEqual(timingIssues(clip, { reason: "invalid-timing" }), ["invalid or stale word timing metadata"]);
  const timing = { text: clip.text, words: [{ startMs: 100, endOffset: clip.text.length }] };
  assert.deepEqual(timingIssues(clip, { timing }, 3), []);
  assert.deepEqual(timingIssues(clip, { timing: { ...timing, text: "Old wording." } }, 3),
    ["word timing text doesn't match narration"]);
  assert.deepEqual(timingIssues(clip, { timing }, 0.1), ["word timing extends beyond the recording"]);
});
