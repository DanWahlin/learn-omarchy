#!/usr/bin/env -S node --experimental-strip-types

import { readFile, writeFile, mkdir } from "node:fs/promises";
import { basename, dirname, resolve } from "node:path";

// Generate or edit character concept art with the configured image model.
//
//   generate-character-art.ts generate --prompt TEXT --out FILE [--size WxH] [--background transparent|opaque]
//   generate-character-art.ts edit --image REF.png [--image REF2.png] --prompt TEXT --out FILE [...]
//
// Credentials come from an env file (default ~/.env): AI_IMAGE_ENDPOINT,
// AI_IMAGE_API_KEY, AI_IMAGE_MODEL. Values are never printed.

const args = process.argv.slice(2);
const mode = args[0];
const flag = (name: string): string | undefined => {
  const index = args.indexOf(name);
  return index === -1 ? undefined : args[index + 1];
};
const flags = (name: string): string[] =>
  args.flatMap((value, index) => (value === name && args[index + 1] ? [args[index + 1]] : []));

if (mode !== "generate" && mode !== "edit") {
  console.error("usage: generate-character-art.ts generate|edit --prompt TEXT --out FILE [--image REF] [--size WxH] [--background transparent|opaque] [--env-file PATH]");
  process.exit(2);
}
const prompt = flag("--prompt");
const out = flag("--out");
if (!prompt || !out) {
  console.error("--prompt and --out are required");
  process.exit(2);
}
const size = flag("--size") ?? "1536x1024";
const background = flag("--background") ?? "transparent";
const quality = flag("--quality") ?? "high";
const envFile = flag("--env-file") ?? resolve(process.env.HOME ?? "", ".env");
const images = flags("--image");

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

const env = { ...(await loadEnvFile(envFile)), ...process.env } as Record<string, string | undefined>;
const endpoint = (env.AI_IMAGE_ENDPOINT ?? "").replace(/\/+$/, "");
const apiKey = env.AI_IMAGE_API_KEY;
const model = env.AI_IMAGE_MODEL;
if (!endpoint || !apiKey || !model) {
  console.error(`AI_IMAGE_ENDPOINT, AI_IMAGE_API_KEY, and AI_IMAGE_MODEL are required (looked in ${envFile})`);
  process.exit(1);
}

const v1 = endpoint.endsWith("/openai/v1");
const operation = mode === "generate" ? "generations" : "edits";
const url = v1
  ? `${endpoint}/images/${operation}`
  : `${endpoint}/openai/deployments/${model}/images/${operation}?api-version=2025-04-01-preview`;

let response: Response;
if (mode === "generate") {
  const body: Record<string, unknown> = { prompt, n: 1, size, quality, background, output_format: "png" };
  if (v1) body.model = model;
  response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json", "api-key": apiKey },
    body: JSON.stringify(body),
  });
} else {
  if (images.length === 0) {
    console.error("edit mode needs at least one --image");
    process.exit(2);
  }
  const form = new FormData();
  if (v1) form.append("model", model);
  form.append("prompt", prompt);
  form.append("n", "1");
  form.append("size", size);
  form.append("quality", quality);
  form.append("background", background);
  form.append("output_format", "png");
  for (const image of images) {
    const bytes = await readFile(resolve(image));
    form.append(images.length === 1 ? "image" : "image[]", new Blob([bytes], { type: "image/png" }), basename(image));
  }
  response = await fetch(url, { method: "POST", headers: { "api-key": apiKey }, body: form });
}

const text = await response.text();
if (!response.ok) {
  console.error(`Image API returned HTTP ${response.status}: ${text.slice(0, 400).replace(/api[-_]?key[^,}]*/gi, "[redacted]")}`);
  process.exit(1);
}
const parsed = JSON.parse(text) as { data?: Array<{ b64_json?: string }> };
const b64 = parsed.data?.[0]?.b64_json;
if (!b64) {
  console.error("Image API response had no image data");
  process.exit(1);
}
await mkdir(dirname(resolve(out)), { recursive: true });
await writeFile(resolve(out), Buffer.from(b64, "base64"));
console.log(`Wrote ${out}`);
