#!/usr/bin/env -S node --experimental-strip-types

import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { dirname, relative, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { parseCourseJson } from "../src/course.ts";
import {
  ffmpegVersion, fileHash, fingerprint, generationIsFresh, normalizationIsFresh,
  normalizeAudio, prepareSpeech, productionOptions, readManifest, sha256, stagePath, writeManifest,
} from "./audio-production.ts";
import type { GenerationSpec } from "./audio-production.ts";

// Usage:
//   generate-course-audio.ts <course.json> [--character ID] [--steps ID,ID] [--missing] [--match TEXT] [--backend edge|azure] [--env-file PATH]
//
// Narration is recorded once per coach: "audio/x.mp3" in the course is written
// to audio/<character>/x.mp3, "HEXON" in the text becomes the coach's display
// name, and the voice is LEARN_OMARCHY_TTS_VOICE when set, otherwise "voice"
// (Azure) or "edgeVoice" (Edge) from the coach's character.json, otherwise a
// backend default. Without --character every coach in
// assets/characters/index.json is generated.
//
// --match regenerates only narration whose spoken text contains TEXT (case
// insensitive), e.g. --match Omarchy after changing its pronunciation.
//
// The Azure backend uses the Speech REST API with credentials read from an env
// file (default ~/.env): AZURE_SPEECH_KEY plus AZURE_SPEECH_REGION or
// AZURE_SPEECH_ENDPOINT. The voice comes from LEARN_OMARCHY_TTS_VOICE, then
// AZURE_SPEECH_MALE_VOICE_US. Credential values are never printed.

const args = process.argv.slice(2);
const readFlag = (name: string): string | undefined => {
  const index = args.indexOf(name);
  return index === -1 ? undefined : args[index + 1];
};
const coursePath = resolve(args.find((value) => !value.startsWith("--") && !isFlagValue(value)) ?? "courses/omarchy-basics.json");
const onlyMissing = args.includes("--missing");
const matchText = (readFlag("--match") ?? "").toLowerCase();
const onlyCharacter = readFlag("--character");
const stepFilter = readFlag("--steps");
if (args.includes("--steps") && (!stepFilter || stepFilter.startsWith("--"))) {
  throw new Error("--steps requires comma-separated activity IDs");
}
const selectedSteps = stepFilter === undefined ? null : new Set(stepFilter.split(",").map(id => id.trim()));
const charactersDir = resolve(dirname(coursePath), "..", "assets", "characters");
const backend = readFlag("--backend") ?? process.env.LEARN_OMARCHY_TTS_BACKEND ?? "edge";
const envFile = readFlag("--env-file") ?? resolve(process.env.HOME ?? "", ".env");
if (backend !== "edge" && backend !== "azure") throw new Error(`Unknown speech backend: ${backend}`);

function isFlagValue(value: string): boolean {
  const index = args.indexOf(value);
  return index > 0 && ["--backend", "--env-file", "--match", "--character", "--steps"].includes(args[index - 1]);
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

// Manifest voices are backend-specific: "voice" names an Azure voice and
// "edgeVoice" an Edge TTS voice. LEARN_OMARCHY_TTS_VOICE always wins.
type Character = { id: string; displayName: string; voice?: string; edgeVoice?: string };

async function loadCharacters(): Promise<Character[]> {
  const index = JSON.parse(await readFile(resolve(charactersDir, "index.json"), "utf8")) as {
    characters?: Array<{ id?: string; displayName?: string }>;
  };
  const characters: Character[] = [];
  for (const entry of index.characters ?? []) {
    if (typeof entry.id !== "string") continue;
    if (onlyCharacter && entry.id !== onlyCharacter) continue;
    let manifest: { displayName?: string; voice?: string; edgeVoice?: string } = {};
    try {
      manifest = JSON.parse(await readFile(resolve(charactersDir, entry.id, "character.json"), "utf8"));
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
    }
    characters.push({
      id: entry.id,
      displayName: manifest.displayName ?? entry.displayName ?? entry.id.toUpperCase(),
      voice: manifest.voice,
      edgeVoice: manifest.edgeVoice,
    });
  }
  if (characters.length === 0) throw new Error(`No characters found under ${charactersDir}${onlyCharacter ? ` matching ${onlyCharacter}` : ""}`);
  return characters;
}

type Synthesizer = {
  voice: string;
  options: Record<string, string>;
  synthesize: (text: string, output: string) => Promise<void>;
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
    const spoken = prepareSpeech(text, character.displayName, pronunciations);
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
      && normalizationIsFresh(manifest.files[key], currentHash, version)) return;
    const staged = stagePath(output);
    try {
      await synthesizer.synthesize(spoken, staged);
      manifest.files[key] = await normalizeAudio(staged, output,
        { kind: "generated", fingerprint: fingerprint(spec), spec }, version);
      await writeManifest(manifestPath, manifest);
    } finally {
      await rm(staged, { force: true });
    }
    generated++;
    console.log(`Generated ${relative}`);
  };
  console.log(`${character.displayName} (${character.id}) speaks with ${synthesizer.voice} via ${backend}.`);
  for (const lesson of result.course.lessons) {
    for (const step of lesson.steps) {
      if (selectedSteps && !selectedSteps.has(step.id)) continue;
      if (step.audio) await generate(step.instruction, step.audio);
    }
  }
  for (const lesson of result.course.lessons) {
    for (const step of lesson.steps) {
      if (selectedSteps && !selectedSteps.has(step.id)) continue;
      if (step.completionAudio && step.completionMessage) await generate(step.completionMessage, step.completionAudio);
    }
  }
}

function relativeToAudio(path: string): string {
  return relative(audioRoot, path).split("\\").join("/");
}

console.log(`Generated ${generated} narration file(s).`);
