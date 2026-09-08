#!/usr/bin/env -S node --experimental-strip-types

import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { dirname, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import { parseCourseJson } from "../src/course.ts";
import { defaultUserPackRoot, discoverCharacterPacks } from "../src/character-packs.ts";
import {
  ffmpegVersion, fileHash, fingerprint, generationIsFresh, normalizationIsFresh,
  normalizeAudio, prepareSpeech, productionOptions, readManifest, sha256, stagePath, writeManifest,
} from "./audio-production.ts";
import type { GenerationSpec } from "./audio-production.ts";
import { mapWordBoundaries, prepareSpeechWithOffsets, timingFileIsFresh, writeTiming } from "./speech-timing.ts";
import type { WordBoundary } from "./speech-timing.ts";

// Usage:
//   generate-course-audio.ts <course.json> [--character ID] [--steps ID,ID] [--part instruction|completion|both] [--welcome] [--wrapups-only] [--missing] [--word-timings] [--match TEXT] [--backend edge|azure] [--env-file PATH]
//
// Narration is recorded once per coach: "audio/x.mp3" in the course is written
// to audio/<character>/x.mp3, "HEXON" in the text becomes the coach's display
// name, and the voice is LEARN_OMARCHY_TTS_VOICE when set, otherwise the
// backend's entry in character.json's narration.voices. Without --character,
// only bundled packs with their own narration are generated.
//
// --match regenerates only narration whose spoken text contains TEXT (case
// insensitive), e.g. --match Omarchy after changing its pronunciation.
//
// The Azure backend uses the Speech REST API with credentials read from an env
// file (default ~/.env): AZURE_SPEECH_KEY plus AZURE_SPEECH_REGION or
// AZURE_SPEECH_ENDPOINT. The voice comes from LEARN_OMARCHY_TTS_VOICE, then
// AZURE_SPEECH_MALE_VOICE_US. Credential values are never printed.
// --word-timings opts into SDK PCM synthesis and captures boundaries from that
// same request. Unsupported/invalid alignment leaves no timing sidecar.
// --missing with --word-timings retries clips without valid, matching timings.

const args = process.argv.slice(2);
const readFlag = (name: string): string | undefined => {
  const index = args.indexOf(name);
  return index === -1 ? undefined : args[index + 1];
};
const coursePath = resolve(args.find((value) => !value.startsWith("--") && !isFlagValue(value)) ?? "courses/omarchy-basics.json");
const onlyMissing = args.includes("--missing");
const captureWordTimings = args.includes("--word-timings");
const matchText = (readFlag("--match") ?? "").toLowerCase();
const onlyCharacter = readFlag("--character");
const includeWelcome = args.includes("--welcome");
const onlyWrapUps = args.includes("--wrapups-only");
const stepFilter = readFlag("--steps");
if (args.includes("--steps") && (!stepFilter || stepFilter.startsWith("--"))) {
  throw new Error("--steps requires comma-separated activity IDs");
}
const selectedSteps = stepFilter === undefined ? null : new Set(stepFilter.split(",").map(id => id.trim()));
const part = readFlag("--part") ?? "both";
if (!["instruction", "completion", "both"].includes(part) ||
    (args.includes("--part") && !readFlag("--part"))) {
  throw new Error("--part must be instruction, completion, or both");
}
const charactersDir = fileURLToPath(new URL("../assets/characters", import.meta.url));
const backend = readFlag("--backend") ?? process.env.LEARN_OMARCHY_TTS_BACKEND ?? "edge";
const envFile = readFlag("--env-file") ?? resolve(process.env.HOME ?? "", ".env");
if (backend !== "edge" && backend !== "azure") throw new Error(`Unknown speech backend: ${backend}`);
if (captureWordTimings && backend !== "azure") throw new Error("--word-timings requires --backend azure");

function isFlagValue(value: string): boolean {
  const index = args.indexOf(value);
  return index > 0 && ["--backend", "--env-file", "--match", "--character", "--steps", "--part"].includes(args[index - 1]);
}

const result = parseCourseJson(await readFile(coursePath, "utf8"));
if (!result.course || result.errors.length > 0) {
  result.errors.forEach((error) => console.error(`- ${error}`));
  process.exit(1);
}
if (selectedSteps) {
  const knownSteps = new Set(result.course.lessons.flatMap(lesson => lesson.steps.map(step => step.id)));
  for (const id of selectedSteps) {
    if (!knownSteps.has(id)) throw new Error(`Unknown activity in --steps: ${id || "(empty)"}`);
  }
}

async function loadEnvFile(path: string): Promise<Record<string, string>> {
  const values: Record<string, string> = {};
  let raw = "";
  try {
    raw = await readFile(path, "utf8");
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return values;
    throw error;
  }
  for (const line of raw.split("\n")) {
    const match = line.match(/^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$/);
    if (!match) continue;
    let value = match[2];
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    values[match[1]] = value;
  }
  return values;
}

const escapeXml = (text: string): string =>
  text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

// Words the voice would otherwise mispronounce, respelled in the spoken text.
// Plain respelling is used rather than SSML <sub>/<phoneme> because the HD
// voices ignore those tags. Display text is unaffected. "Omarchy" is said
// "oh-MAH-chee"; override the respelling with LEARN_OMARCHY_PRONUNCIATION if
// a different voice needs another spelling.
const pronunciations: Record<string, string> = {
  Omarchy: process.env.LEARN_OMARCHY_PRONUNCIATION ?? "Omaachi",
};

type Character = { id: string; displayName: string; spokenName: string; voice?: string; edgeVoice?: string };

async function loadCharacters(): Promise<Character[]> {
  const userRoot = onlyCharacter ? defaultUserPackRoot() : undefined;
  const discovery = await discoverCharacterPacks({ bundledRoot: charactersDir, userRoot });
  for (const diagnostic of discovery.diagnostics) console.warn(diagnostic);
  const characters: Character[] = [];
  for (const pack of discovery.packs) {
    if (onlyCharacter && pack.id !== onlyCharacter) continue;
    const narration = pack.manifest.narration;
    if (narration.mode !== "own") {
      if (onlyCharacter) throw new Error(`Pack "${pack.id}" uses ${narration.mode} narration; it doesn't need generated recordings`);
      continue;
    }
    characters.push({
      id: pack.id,
      displayName: pack.manifest.displayName,
      spokenName: pack.manifest.spokenName ?? pack.manifest.displayName,
      voice: narration.voices?.azure,
      edgeVoice: narration.voices?.edge,
    });
  }
  if (characters.length === 0) throw new Error(`No characters found under ${charactersDir}${onlyCharacter ? ` matching ${onlyCharacter}` : ""}`);
  return characters;
}

type Synthesizer = {
  voice: string;
  options: Record<string, string>;
  synthesize: (text: string, output: string) => Promise<void | WordBoundary[]>;
};

async function createEdgeSynthesizer(manifestVoice?: string): Promise<Synthesizer> {
  const voice = process.env.LEARN_OMARCHY_TTS_VOICE ?? manifestVoice ?? "en-GB-RyanNeural";
  const edgeTts = process.env.EDGE_TTS_BIN ?? "edge-tts";
  return {
    voice,
    options: { rate: "+0%", volume: "+0%", pitch: "+0Hz", format: "edge-default-mp3" },
    async synthesize(text, output) {
      const child = spawnSync(edgeTts, [
        "--voice", voice, "--rate=+0%", "--volume=+0%", "--pitch=+0Hz",
        "--text", text, "--write-media", output,
      ], {
        encoding: "utf8",
        stdio: "inherit",
      });
      if (child.error) throw new Error(`Unable to run ${edgeTts}: ${child.error.message}`);
      if (child.status !== 0) throw new Error(`${edgeTts} exited with ${child.status}`);
    },
  };
}

async function createAzureSynthesizer(manifestVoice?: string): Promise<Synthesizer> {
  const env = { ...(await loadEnvFile(envFile)), ...process.env } as Record<string, string | undefined>;
  const key = env.AZURE_SPEECH_KEY;
  const region = env.AZURE_SPEECH_REGION;
  const configuredEndpoint = env.AZURE_SPEECH_ENDPOINT;
  const voice = env.LEARN_OMARCHY_TTS_VOICE ?? manifestVoice ?? env.AZURE_SPEECH_MALE_VOICE_US ?? "en-US-AndrewMultilingualNeural";
  if (!key) throw new Error(`AZURE_SPEECH_KEY is not set (looked in ${envFile})`);
  if (!region && !configuredEndpoint) {
    throw new Error(`AZURE_SPEECH_REGION or AZURE_SPEECH_ENDPOINT is not set (looked in ${envFile})`);
  }
  const endpoint = region
    ? `https://${region}.tts.speech.microsoft.com/cognitiveservices/v1`
    : `${String(configuredEndpoint).replace(/\/+$/, "")}/cognitiveservices/v1`;
  const locale = voice.split("-").slice(0, 2).join("-") || "en-US";
  if (captureWordTimings) {
    const { synthesizeWithWordBoundaries } = await import("./azure-speech-timing.ts");
    return {
      voice,
      options: {
        locale, format: "riff-24khz-16bit-mono-pcm", input: "plain-text",
        wordTimings: "azure-sdk-1.51.0-v1",
      },
      synthesize: (text, output) => synthesizeWithWordBoundaries(text, output,
        { key, region, endpoint: configuredEndpoint }, voice),
    };
  }
  return {
    voice,
    options: { locale, format: "audio-24khz-96kbitrate-mono-mp3", ssmlVersion: "1.0" },
    async synthesize(text, output) {
      const ssml =
        `<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="${locale}">` +
        `<voice name="${escapeXml(voice)}">${escapeXml(text)}</voice></speak>`;
      const response = await fetch(endpoint, {
        method: "POST",
        headers: {
          "Ocp-Apim-Subscription-Key": key,
          "Content-Type": "application/ssml+xml",
          "X-Microsoft-OutputFormat": "audio-24khz-96kbitrate-mono-mp3",
          "User-Agent": "learn-omarchy-narration",
        },
        body: ssml,
      });
      if (!response.ok) {
        throw new Error(`Azure Speech returned HTTP ${response.status} for "${text.slice(0, 40)}..."`);
      }
      const bytes = new Uint8Array(await response.arrayBuffer());
      if (bytes.byteLength < 1000) throw new Error(`Azure Speech returned ${bytes.byteLength} bytes; expected audio`);
      await writeFile(output, bytes);
    },
  };
}

function characterOutputPath(relativePath: string, character: Character): string {
  const slash = relativePath.lastIndexOf("/");
  const dir = slash === -1 ? "" : relativePath.slice(0, slash + 1);
  const file = slash === -1 ? relativePath : relativePath.slice(slash + 1);
  return `${dir}${character.id}/${file}`;
}

let generated = 0;
const audioRoot = resolve(dirname(coursePath), "audio");
await mkdir(audioRoot, { recursive: true });
const manifestPath = resolve(audioRoot, "production-manifest.json");
const manifest = await readManifest(manifestPath);
const version = ffmpegVersion();
for (const character of await loadCharacters()) {
  const synthesizer = backend === "azure"
    ? await createAzureSynthesizer(character.voice)
    : await createEdgeSynthesizer(character.edgeVoice);
  const generate = async (text: string, relativePath: string): Promise<void> => {
    const named = text.replace(/HEXON/g, () => character.displayName);
    if (matchText !== "" && !named.toLowerCase().includes(matchText)) return;
    const spoken = prepareSpeech(text, character.spokenName, pronunciations);
    const relative = characterOutputPath(relativePath, character);
    const output = resolve(dirname(coursePath), relative);
    if (!output.endsWith(".mp3")) throw new Error(`Narration production requires an .mp3 path: ${relative}`);
    await mkdir(dirname(output), { recursive: true });
    const key = relativeToAudio(output);
    const spec: GenerationSpec = {
      textHash: sha256(text),
      preparedTextHash: sha256(spoken),
      character: { id: character.id, displayName: character.displayName },
      voice: synthesizer.voice,
      backend,
      pronunciations,
      preparationVersion: 1,
      synthesisOptions: synthesizer.options,
      productionOptions,
    };
    const currentHash = await fileHash(output);
    if (onlyMissing && generationIsFresh(manifest.files[key], spec, currentHash)
      && normalizationIsFresh(manifest.files[key], currentHash, version)
      && (!captureWordTimings || await timingFileIsFresh(output, currentHash, text))) return;
    const staged = captureWordTimings ? stagePath(output).replace(/\.mp3$/, ".wav") : stagePath(output);
    try {
      const boundaries = await synthesizer.synthesize(spoken, staged);
      manifest.files[key] = await normalizeAudio(staged, output,
        { kind: "generated", fingerprint: fingerprint(spec), spec }, version);
      if (captureWordTimings) {
        const timing = mapWordBoundaries(text, prepareSpeechWithOffsets(text, character.spokenName, pronunciations),
          boundaries ?? [], manifest.files[key].normalization.probe.durationSeconds * 1000);
        if (timing.words) {
          await writeTiming(output, {
            version: 1, audioHash: manifest.files[key].normalization.outputHash, text, words: timing.words,
          });
          console.log(`Word timings: ${relative} (${timing.words.length} words).`);
        } else {
          await writeTiming(output);
          console.log(`No word timings: ${relative}: ${synthesizer.voice}: ${timing.reason}; displaying full text.`);
        }
      } else {
        await writeTiming(output);
      }
      await writeManifest(manifestPath, manifest);
    } finally {
      await rm(staged, { force: true });
    }
    generated++;
    console.log(`Generated ${relative}`);
  };
  console.log(`${character.displayName} (${character.id}) speaks with ${synthesizer.voice} via ${backend}.`);
  if (onlyWrapUps) {
    const wrapUps = [
      ...Object.values(result.course.wrapUp ?? {}),
      ...result.course.lessons.flatMap(lesson => lesson.wrapUp ? [lesson.wrapUp] : []),
    ];
    for (const wrapUp of wrapUps) await generate(wrapUp.text, wrapUp.audio);
    continue;
  }
  if (includeWelcome) {
    const welcome = JSON.parse(await readFile(resolve(dirname(coursePath), "welcome.json"), "utf8"));
    if (typeof welcome.instruction !== "string" || !welcome.instruction.trim() ||
        welcome.audio !== "audio/host-welcome.mp3") throw new Error("Invalid welcome narration metadata");
    const instruction = welcome.instructions?.[character.id] ?? welcome.instruction;
    if (typeof instruction !== "string" || !instruction.trim()) throw new Error("Invalid character welcome instruction");
    await generate(instruction, welcome.audio);
    if (welcome.recommendationAudio !== undefined) {
      if (welcome.recommendationAudio !== "audio/host-lessons.mp3" ||
          typeof welcome.recommendation !== "string" || !welcome.recommendation.trim())
        throw new Error("Invalid welcome lesson-menu narration");
      await generate(welcome.recommendation, welcome.recommendationAudio);
    }
    if (welcome.controls !== undefined) {
      if (!welcome.controls || typeof welcome.controls.instruction !== "string" ||
          !welcome.controls.instruction.trim() || welcome.controls.audio !== "audio/host-controls.mp3")
        throw new Error("Invalid welcome controls narration metadata");
      await generate(welcome.controls.instruction, welcome.controls.audio);
    }
  }
  for (const lesson of result.course.lessons) {
    for (const step of lesson.steps) {
      if (selectedSteps && !selectedSteps.has(step.id)) continue;
      if (part !== "completion" && step.audio) await generate(step.instruction, step.audio);
    }
  }
  for (const lesson of result.course.lessons) {
    for (const step of lesson.steps) {
      if (selectedSteps && !selectedSteps.has(step.id)) continue;
      if (part !== "instruction" && step.completionAudio && step.completionMessage) await generate(step.completionMessage, step.completionAudio);
    }
  }
}

function relativeToAudio(path: string): string {
  return relative(audioRoot, path).split("\\").join("/");
}

console.log(`Generated ${generated} narration file(s).`);
