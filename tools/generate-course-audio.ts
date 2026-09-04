#!/usr/bin/env -S node --experimental-strip-types

import { access, mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { parseCourseJson } from "../src/course.ts";

// Usage:
//   generate-course-audio.ts <course.json> [--missing] [--backend edge|azure] [--env-file PATH]
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
const backend = readFlag("--backend") ?? process.env.LEARN_OMARCHY_TTS_BACKEND ?? "edge";
const envFile = readFlag("--env-file") ?? resolve(process.env.HOME ?? "", ".env");

function isFlagValue(value: string): boolean {
  const index = args.indexOf(value);
  return index > 0 && ["--backend", "--env-file"].includes(args[index - 1]);
}

const result = parseCourseJson(await readFile(coursePath, "utf8"));
if (!result.course || result.errors.length > 0) {
  result.errors.forEach((error) => console.error(`- ${error}`));
  process.exit(1);
}

async function loadEnvFile(path: string): Promise<Record<string, string>> {
  const values: Record<string, string> = {};
  let raw = "";
  try {
    raw = await readFile(path, "utf8");
  } catch {
    return values;
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
// voices ignore those tags. Display text is unaffected.
const pronunciations: Record<string, string> = { Omarchy: "Omaaachi" };

const toSsmlText = (text: string): string =>
  escapeXml(
    Object.entries(pronunciations).reduce(
      (spoken, [word, respelling]) => spoken.replace(new RegExp(`\\b${word}\\b`, "g"), respelling),
      text,
    ),
  );

type Synthesizer = { voice: string; synthesize: (text: string, output: string) => Promise<void> };

async function createEdgeSynthesizer(): Promise<Synthesizer> {
  const voice = process.env.LEARN_OMARCHY_TTS_VOICE ?? "en-GB-RyanNeural";
  const edgeTts = process.env.EDGE_TTS_BIN ?? "edge-tts";
  return {
    voice,
    async synthesize(text, output) {
      const child = spawnSync(edgeTts, ["--voice", voice, "--text", text, "--write-media", output], {
        encoding: "utf8",
        stdio: "inherit",
      });
      if (child.error) throw new Error(`Unable to run ${edgeTts}: ${child.error.message}`);
      if (child.status !== 0) throw new Error(`${edgeTts} exited with ${child.status}`);
    },
  };
}

async function createAzureSynthesizer(): Promise<Synthesizer> {
  const env = { ...(await loadEnvFile(envFile)), ...process.env } as Record<string, string | undefined>;
  const key = env.AZURE_SPEECH_KEY;
  const region = env.AZURE_SPEECH_REGION;
  const configuredEndpoint = env.AZURE_SPEECH_ENDPOINT;
  const voice = env.LEARN_OMARCHY_TTS_VOICE ?? env.AZURE_SPEECH_MALE_VOICE_US ?? "en-US-AndrewMultilingualNeural";
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
    async synthesize(text, output) {
      const ssml =
        `<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="${locale}">` +
        `<voice name="${escapeXml(voice)}">${toSsmlText(text)}</voice></speak>`;
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

const synthesizer = backend === "azure" ? await createAzureSynthesizer() : await createEdgeSynthesizer();

let generated = 0;
for (const lesson of result.course.lessons) {
  for (const step of lesson.steps) {
    if (!step.audio) continue;
    const output = resolve(dirname(coursePath), step.audio);
    await mkdir(dirname(output), { recursive: true });
    if (onlyMissing) {
      try {
        await access(output);
        continue;
      } catch {
        // Generate files that don't exist yet.
      }
    }
    try {
      await synthesizer.synthesize(step.instruction, output);
    } catch (error) {
      console.error(String(error instanceof Error ? error.message : error));
      process.exit(1);
    }
    generated++;
    console.log(`Generated ${step.audio}`);
  }
}

for (const lesson of result.course.lessons) {
  for (const step of lesson.steps) {
    if (!step.completionAudio || !step.completionMessage) continue;
    const output = resolve(dirname(coursePath), step.completionAudio);
    await mkdir(dirname(output), { recursive: true });
    if (onlyMissing) {
      try {
        await access(output);
        continue;
      } catch {
        // Generate files that don't exist yet.
      }
    }
    try {
      await synthesizer.synthesize(step.completionMessage, output);
    } catch (error) {
      console.error(String(error instanceof Error ? error.message : error));
      process.exit(1);
    }
    generated++;
    console.log(`Generated ${step.completionAudio}`);
  }
}

console.log(`Generated ${generated} narration file(s) with ${synthesizer.voice} via ${backend}.`);
