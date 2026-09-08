import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { cp, mkdir, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import test from "node:test";
import {
  ffmpegVersion, fileHash, fingerprint, generationIsFresh, normalizationFilter,
  normalizationIsFresh, normalizeAudio, prepareSpeech, productionOptions, readManifest, sha256,
} from "../tools/audio-production.ts";
import type { GenerationSpec, ProductionEntry } from "../tools/audio-production.ts";

const spec: GenerationSpec = {
  textHash: sha256("Welcome to Omarchy, HEXON"),
  preparedTextHash: sha256("Welcome to Omaachi, OLLIE"),
  character: { id: "owl", displayName: "OLLIE" },
  voice: "test-voice",
  backend: "edge",
  pronunciations: { Omarchy: "Omaachi" },
  preparationVersion: 1,
  synthesisOptions: { rate: "+0%" },
  productionOptions,
};

test("activity-scoped generation rejects unknown IDs before contacting a speech service", () => {
  for (const ids of ["not-an-activity", "launch-terminal,", ""]) {
    const result = spawnSync(process.execPath, [
      "--experimental-strip-types", "tools/generate-course-audio.ts",
      "courses/omarchy-basics.json", "--backend", "azure", "--steps", ids,
    ], { encoding: "utf8" });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /Unknown activity in --steps|--steps requires/);
    assert.doesNotMatch(result.stderr, /AZURE_SPEECH_KEY|Azure Speech returned/);
  }
});

test("narration-part selection rejects invalid values before contacting a speech service", () => {
  for (const args of [["--part"], ["--part", "other"], ["--part", "--welcome"]]) {
    const result = spawnSync(process.execPath, [
      "--experimental-strip-types", "tools/generate-course-audio.ts",
      "courses/omarchy-basics.json", "--backend", "azure", ...args,
    ], { encoding: "utf8" });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /--part must be/);
    assert.doesNotMatch(result.stderr, /AZURE_SPEECH_KEY|Azure Speech returned/);
  }
});
test("word timing capture explicitly requires Azure rather than silently guessing Edge timings", () => {
  const result = spawnSync(process.execPath, [
    "--experimental-strip-types", "tools/generate-course-audio.ts",
    "courses/omarchy-basics.json", "--backend", "edge", "--word-timings",
  ], { encoding: "utf8" });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /--word-timings requires --backend azure/);
});

test("welcome pilot scope includes all welcome clips but no activities, and regeneration removes stale timings", async () => {
  const directory = resolve("tests", `.welcome-audio-${randomUUID()}`);
  await mkdir(directory);
  try {
    const course = resolve(directory, "course.json");
    await cp(resolve("courses/omarchy-basics.json"), course);
    await cp(resolve("courses/welcome.json"), resolve(directory, "welcome.json"));
    const edge = resolve(directory, "fake-edge.mjs");
    await writeFile(edge, `#!${process.execPath}
import { spawnSync } from "node:child_process";
const output = process.argv[process.argv.indexOf("--write-media") + 1];
const result = spawnSync("ffmpeg", ["-v", "error", "-f", "lavfi", "-i",
  "sine=frequency=440:duration=1", "-ar", "24000", "-ac", "1", output]);
process.exit(result.status ?? 1);
`, { mode: 0o700 });
    const args = [
      "--experimental-strip-types", "tools/generate-course-audio.ts", course,
      "--backend", "edge", "--character", "owl", "--welcome", "--steps", "tour-welcome", "--part", "completion",
    ];
    const env = { ...process.env, EDGE_TTS_BIN: edge, HOME: directory, XDG_DATA_HOME: directory };
    const first = spawnSync(process.execPath, args, { encoding: "utf8", env });
    assert.equal(first.status, 0, first.stderr);
    assert.match(first.stdout, /Generated 3 narration file/);
    const root = resolve(directory, "audio/owl");
    const clips = ["host-controls.mp3", "host-lessons.mp3", "host-welcome.mp3"];
    assert.deepEqual((await readdir(root)).sort(), clips);
    const skipped = spawnSync(process.execPath, [...args, "--missing"], { encoding: "utf8", env });
    assert.equal(skipped.status, 0, skipped.stderr);
    assert.match(skipped.stdout, /Generated 0 narration file/);
    for (const name of clips) await writeFile(resolve(root, `${name}.timing.json`), '{"stale":true}');
    const again = spawnSync(process.execPath, args, { encoding: "utf8", env });
    assert.equal(again.status, 0, again.stderr);
    assert.deepEqual((await readdir(root)).sort(), clips);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
test("Ohm-1 displays his designation but uses Ohm and Andrew in his welcome recording", async () => {
  const pack = JSON.parse(await readFile(new URL("../assets/characters/ohm-1/character.json", import.meta.url), "utf8"));
  const welcome = JSON.parse(await readFile(new URL("../courses/welcome.json", import.meta.url), "utf8"));
  assert.equal(pack.id, "ohm-1");
  assert.equal(pack.displayName, "Ohm-1");
  assert.equal(pack.spokenName, "Ohm");
  assert.equal(pack.narration.audioSet, "ohm-1");
  const spoken = prepareSpeech(welcome.instructions[pack.id], pack.spokenName ?? pack.displayName, { Omarchy: "Omaachi" });
  assert.match(spoken, /^Hi! I'm Ohm-1, but you can call me Ohm for short\. Welcome to Omaachi!/);
  assert.equal(prepareSpeech("I'm HEXON.", pack.spokenName, {}), "I'm Ohm.");
  assert.match(prepareSpeech(welcome.instruction, "Ollie", {}), /^Hi! I'm Ollie\. Welcome/);
  assert.doesNotMatch(spoken, /HEXON|Arco/);
  const manifest = await readManifest(resolve("courses/audio/production-manifest.json"));
  const greeting = manifest.files["ohm-1/host-welcome.mp3"];
  assert.equal(greeting?.provenance.kind, "generated");
  if (greeting.provenance.kind === "generated") {
    assert.equal(greeting.provenance.spec.character.displayName, pack.displayName);
    assert.equal(greeting.provenance.spec.voice, "en-US-Andrew:DragonHDLatestNeural");
    assert.equal(greeting.provenance.spec.preparedTextHash, sha256(spoken));
  }
});
test("graphics-only packs never initiate voice generation", async () => {
  const directory = resolve("tests", `.learn-pack-audio-${randomUUID()}`);
  await mkdir(directory);
  try {
    const dataHome = resolve(directory, "data");
    const target = resolve(dataHome, "learn-omarchy/characters/spark");
    await cp(resolve("examples/characters/spark"), target, { recursive: true });
    const result = spawnSync(process.execPath, [
      "--experimental-strip-types", "tools/generate-course-audio.ts",
      "courses/omarchy-basics.json", "--character", "spark", "--backend", "azure",
    ], {
      encoding: "utf8",
      env: { ...process.env, HOME: directory, XDG_DATA_HOME: dataHome, AZURE_SPEECH_KEY: "" },
    });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /uses (borrowed|silent) narration/);
    assert.doesNotMatch(result.stderr, /AZURE_SPEECH_KEY is not set|Azure Speech returned/);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("fingerprints ignore object insertion order but include values and array order", () => {
  assert.equal(fingerprint({ b: { y: 2, x: 1 }, a: 0 }), fingerprint({ a: 0, b: { x: 1, y: 2 } }));
  assert.notEqual(fingerprint(["a", "b"]), fingerprint(["b", "a"]));
  for (const change of [
    { textHash: sha256("Changed") }, { preparedTextHash: sha256("Other") },
    { character: { id: "ohm-1", displayName: "HEXON" } }, { voice: "other" },
    { backend: "azure" }, { pronunciations: { Omarchy: "oh-mah-chee" } },
    { synthesisOptions: { rate: "+5%" } }, { productionOptions: { ...productionOptions, integratedLufs: -19 } },
  ]) {
    assert.notEqual(fingerprint(spec), fingerprint({ ...spec, ...change }));
  }
});

test("speech preparation is shared plain text, nonrecursive and XML-independent", () => {
  assert.equal(prepareSpeech("HEXON & Omarchy <menu> Omarchyish", "OLLIE", spec.pronunciations),
    "OLLIE & Omaachi <menu> Omarchyish");
  assert.equal(prepareSpeech("A B", "HEXON", { A: "B", B: "C" }), "B C");
  assert.equal(prepareSpeech("a.b axb", "HEXON", { "a.b": "word" }), "word axb");
  assert.equal(prepareSpeech("HEXON", "$&", {}), "$&");
});

test("short speech uses static gain with peak headroom rather than unstable dynamics", () => {
  const source = { integratedLufs: -30, truePeakDbtp: -5, loudnessRangeLu: 1, thresholdLufs: -40, targetOffsetLu: 0 };
  assert.deepEqual(normalizationFilter(source, 1.5), {
    method: "short-speech-static-gain", filter: "volume=3.5dB",
  });
  assert.equal(normalizationFilter(source, 3).method, "measured-two-pass");
  assert.match(normalizationFilter(source, 3).filter, /measured_I=-30/);
});

test("manifest validation rejects malformed records and accepts stale prior production options", async () => {
  const directory = resolve("tests", `.audio-test-${randomUUID()}`);
  await mkdir(directory);
  try {
    const path = resolve(directory, "manifest.json");
    const hash = sha256("fixture");
    const measurement = { integratedLufs: -20, truePeakDbtp: -2, loudnessRangeLu: 1, thresholdLufs: -30, targetOffsetLu: 0 };
    const entry: ProductionEntry = {
      provenance: { kind: "generated", fingerprint: fingerprint(spec), spec },
      normalization: {
        fingerprint: fingerprint({ sourceHash: hash, ffmpegVersion: "fixture", options: productionOptions }),
        sourceHash: hash, outputHash: hash, options: productionOptions, ffmpegVersion: "fixture",
        method: "measured-two-pass", source: measurement, output: measurement,
        probe: { durationSeconds: 4, sampleRate: 24000, channels: 1, codec: "mp3" },
      },
    };
    const manifest = (value: unknown) => ({ schemaVersion: 1, files: { "owl/test.mp3": value } });
    for (const invalid of [
      null, [], { schemaVersion: 1, files: [] }, { schemaVersion: 1, files: null },
      { schemaVersion: 1, files: { " ": entry } },
    ]) {
      await writeFile(path, JSON.stringify(invalid));
      await assert.rejects(readManifest(path), /Invalid.*audio production manifest/);
    }
    const invalidEntries = [
      null, [], {}, { ...entry, provenance: [] }, { ...entry, normalization: [] },
      { ...entry, provenance: { kind: "inherited", sourceProvenance: "assumed" } },
      { ...entry, provenance: { kind: "generated", fingerprint: "", spec } },
      ...[
        { textHash: "not-a-hash" }, { preparedTextHash: "" }, { character: [] },
        { character: { id: "owl", displayName: " " } }, { voice: "" }, { backend: "unknown" },
        { pronunciations: [] }, { synthesisOptions: { rate: 5 } }, { preparationVersion: null },
        { productionOptions: [] },
      ].map((change) => ({
        ...entry, provenance: { kind: "generated", fingerprint: hash, spec: { ...spec, ...change } },
      })),
      ...[
        { fingerprint: "" }, { sourceHash: "bad" }, { outputHash: 12 }, { options: [] },
        { options: { ...productionOptions, integratedLufs: "-20" } },
        { options: { ...productionOptions, trimSilence: null } },
        { ffmpegVersion: " " }, { method: "unrecognized" }, { source: [] },
        { source: { ...measurement, thresholdLufs: null } },
        { output: { ...measurement, integratedLufs: "NaN" } }, { probe: [] },
        { probe: { ...entry.normalization.probe, durationSeconds: 0 } },
        { probe: { ...entry.normalization.probe, sampleRate: "24000" } },
        { probe: { ...entry.normalization.probe, channels: 0.5 } },
        { probe: { ...entry.normalization.probe, codec: "" } },
      ].map((change) => ({ ...entry, normalization: { ...entry.normalization, ...change } })),
    ];
    for (const invalid of invalidEntries) {
      await writeFile(path, JSON.stringify(manifest(invalid)));
      await assert.rejects(readManifest(path), /Invalid audio production manifest entry "owl\/test.mp3"/);
    }
    await writeFile(path, JSON.stringify(manifest(entry)).replace('"durationSeconds":4', '"durationSeconds":1e999'));
    await assert.rejects(readManifest(path), /Invalid audio production manifest entry/);
    await writeFile(path, JSON.stringify(manifest(entry)));
    const valid = (await readManifest(path)).files["owl/test.mp3"];
    assert.equal(generationIsFresh(valid, spec, hash), true);
    assert.equal(normalizationIsFresh(valid, hash, "fixture"), true);
    const priorOptions = { ...productionOptions, revision: 2, integratedLufs: -18, sampleRate: 48000, bitrate: "128k", trimSilence: true };
    const priorSpec = { ...spec, productionOptions: priorOptions };
    await writeFile(path, JSON.stringify(manifest({
      ...entry,
      provenance: { kind: "generated", fingerprint: fingerprint(priorSpec), spec: priorSpec },
      normalization: { ...entry.normalization, options: priorOptions },
    })));
    const prior = (await readManifest(path)).files["owl/test.mp3"];
    assert.deepEqual(prior.normalization.options, priorOptions);
    assert.equal(generationIsFresh(prior, spec, hash), false);
    assert.equal(normalizationIsFresh(prior, hash, "fixture"), false);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("local normalization verifies output, tracks provenance and skips matching fingerprints", async () => {
  const directory = resolve("tests", `.audio-test-${randomUUID()}`);
  await mkdir(directory);
  try {
    const source = resolve(directory, "source.wav");
    const output = resolve(directory, "output.mp3");
    const created = spawnSync("ffmpeg", [
      "-v", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=4",
      "-ar", "24000", "-ac", "1", source,
    ], { encoding: "utf8" });
    assert.equal(created.status, 0, created.error?.message ?? created.stderr);
    const version = ffmpegVersion();
    const entry = await normalizeAudio(source, output,
      { kind: "generated", fingerprint: fingerprint(spec), spec }, version);
    const hash = await fileHash(output);
    assert.equal(entry.normalization.probe.sampleRate, 24000);
    assert.equal(entry.normalization.probe.channels, 1);
    assert.equal(entry.normalization.probe.codec, "mp3");
    assert.ok(entry.normalization.output.truePeakDbtp <= -1);
    assert.ok(Math.abs(entry.normalization.output.integratedLufs + 20) < 1);
    assert.equal(generationIsFresh(entry, spec, hash), true);
    assert.equal(generationIsFresh(entry, { ...spec, voice: "changed" }, hash), false);
    assert.equal(generationIsFresh(entry, spec, undefined), false);
    assert.equal(generationIsFresh(entry, spec, "different hash"), false);
    assert.equal(generationIsFresh({ ...entry, provenance: { kind: "inherited", sourceProvenance: "unknown" } }, spec, hash), false);
    assert.equal(normalizationIsFresh(entry, hash, version), true);
    assert.equal(normalizationIsFresh(entry, hash, "different version"), false);
    assert.equal(normalizationIsFresh(entry, "changed file", version), false);
    assert.equal(normalizationIsFresh(undefined, hash, version), false);
    await writeFile(source, "not audio");
    await assert.rejects(normalizeAudio(source, output, entry.provenance, version), /ffprobe failed/);
    assert.equal(await fileHash(output), hash, "invalid input must preserve the published clip");
    assert.deepEqual((await readdir(directory)).sort(), ["output.mp3", "source.wav"]);
    const manifestPath = resolve(directory, "manifest.json");
    assert.deepEqual(await readManifest(manifestPath), { schemaVersion: 1, files: {} });
    await writeFile(manifestPath, "invalid json");
    await assert.rejects(readManifest(manifestPath), SyntaxError);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("bundled audio manifest describes each character file without invented text provenance", async () => {
  const root = resolve("courses/audio");
  const manifest = await readManifest(resolve(root, "production-manifest.json"));
  const characterFiles = await Promise.all(["ohm-1", "owl"].map(async (character) =>
    (await readdir(resolve(root, character))).filter((name) => name.endsWith(".mp3")).sort()));
  assert.deepEqual(characterFiles[0], characterFiles[1]);
  for (const [index, character] of ["ohm-1", "owl"].entries()) {
    for (const name of characterFiles[index]) {
      const entry = manifest.files[`${character}/${name}`];
      assert.ok(entry, `${character}/${name} has no manifest entry`);
      assert.equal(entry.normalization.outputHash, sha256(await readFile(resolve(root, character, name))));
      assert.equal(entry.normalization.probe.sampleRate, 24000);
      assert.equal(entry.normalization.probe.channels, 1);
      assert.ok(entry.normalization.output.truePeakDbtp <= -1);
      if (entry.provenance.kind === "inherited") {
        assert.deepEqual(entry.provenance, { kind: "inherited", sourceProvenance: "unknown" });
      }
    }
  }
  assert.equal(Object.keys(manifest.files).length, characterFiles.flat().length);
});
