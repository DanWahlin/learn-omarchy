import { createHash, randomUUID } from "node:crypto";
import { spawnSync } from "node:child_process";
import { readFile, rename, rm, writeFile } from "node:fs/promises";

export const productionOptions = {
  revision: 1,
  integratedLufs: -20,
  truePeakDbtp: -1,
  codecSafetyDb: 0.5,
  loudnessRangeLu: 11,
  shortSpeechSeconds: 3,
  sampleRate: 24000,
  channels: 1,
  codec: "libmp3lame",
  bitrate: "96k",
  trimSilence: false,
};

export function fingerprint(value: unknown): string {
  const canonical = (item: unknown): unknown => {
    if (Array.isArray(item)) return item.map(canonical);
    if (item !== null && typeof item === "object") {
      return Object.fromEntries(Object.entries(item).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0)
        .map(([key, value]) => [key, canonical(value)]));
    }
    return item;
  };
  return sha256(JSON.stringify(canonical(value)));
}

export function sha256(value: string | Uint8Array): string {
  return createHash("sha256").update(value).digest("hex");
}

export async function fileHash(path: string): Promise<string | undefined> {
  try {
    return sha256(await readFile(path));
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return undefined;
    throw error;
  }
}

export function prepareSpeech(text: string, displayName: string, pronunciations: Record<string, string>): string {
  const named = text.replace(/HEXON/g, () => displayName);
  const words = Object.keys(pronunciations).sort((a, b) => b.length - a.length);
  if (words.length === 0) return named;
  const alternatives = words.map((word) => word.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"));
  return named.replace(new RegExp(`\\b(?:${alternatives.join("|")})\\b`, "g"),
    (word) => pronunciations[word]);
}

export type GenerationSpec = {
  textHash: string;
  preparedTextHash: string;
  character: { id: string; displayName: string };
  voice: string;
  backend: "edge" | "azure";
  pronunciations: Record<string, string>;
  preparationVersion: number;
  synthesisOptions: Record<string, string>;
  productionOptions: typeof productionOptions;
};

export type Provenance =
  | { kind: "inherited"; sourceProvenance: "unknown" }
  | { kind: "generated"; fingerprint: string; spec: GenerationSpec };

export type Measurement = {
  integratedLufs: number;
  truePeakDbtp: number;
  loudnessRangeLu: number;
  thresholdLufs: number;
  targetOffsetLu: number;
};
export type Probe = { durationSeconds: number; sampleRate: number; channels: number; codec: string };
export type ProductionEntry = {
  provenance: Provenance;
  normalization: {
    fingerprint: string;
    sourceHash: string;
    outputHash: string;
    options: typeof productionOptions;
    ffmpegVersion: string;
    method: "measured-two-pass" | "short-speech-static-gain";
    source: Measurement;
    output: Measurement;
    probe: Probe;
  };
};
export type ProductionManifest = { schemaVersion: 1; files: Record<string, ProductionEntry> };

export function generationIsFresh(entry: ProductionEntry | undefined, spec: GenerationSpec, outputHash: string | undefined): boolean {
  return outputHash !== undefined && entry?.provenance.kind === "generated"
    && entry.provenance.fingerprint === fingerprint(spec)
    && entry.normalization.outputHash === outputHash
    && fingerprint(entry.normalization.options) === fingerprint(productionOptions);
}

export function normalizationIsFresh(entry: ProductionEntry | undefined, outputHash: string | undefined, ffmpegVersion: string): boolean {
  return outputHash !== undefined && entry !== undefined
    && entry.normalization.outputHash === outputHash
    && entry.normalization.ffmpegVersion === ffmpegVersion
    && fingerprint(entry.normalization.options) === fingerprint(productionOptions)
    && entry.normalization.fingerprint === normalizationFingerprint(entry.normalization.sourceHash, ffmpegVersion);
}

function normalizationFingerprint(sourceHash: string, ffmpegVersion: string): string {
  return fingerprint({ sourceHash, ffmpegVersion, options: productionOptions });
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function isNonemptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function isHash(value: unknown): boolean {
  return typeof value === "string" && /^[a-f0-9]{64}$/.test(value);
}

function isFiniteNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

function isStringRecord(value: unknown): boolean {
  return isRecord(value) && Object.entries(value).every(([key, item]) =>
    isNonemptyString(key) && typeof item === "string");
}

function isProductionOptions(value: unknown): boolean {
  // Validate the schema, not today's values: older export settings must load
  // successfully so freshness checks can mark them stale.
  return isRecord(value) && Object.entries(productionOptions).every(([key, example]) => {
    const item = value[key];
    if (typeof example === "number") return isFiniteNumber(item);
    if (typeof example === "string") return isNonemptyString(item);
    return typeof item === "boolean";
  });
}

function isMeasurement(value: unknown): boolean {
  return isRecord(value) && [
    "integratedLufs", "truePeakDbtp", "loudnessRangeLu", "thresholdLufs", "targetOffsetLu",
  ].every((key) => isFiniteNumber(value[key]));
}

function isProbe(value: unknown): boolean {
  return isRecord(value) && isFiniteNumber(value.durationSeconds) && value.durationSeconds > 0
    && isFiniteNumber(value.sampleRate) && Number.isInteger(value.sampleRate) && value.sampleRate > 0
    && isFiniteNumber(value.channels) && Number.isInteger(value.channels) && value.channels > 0
    && isNonemptyString(value.codec);
}

function isGenerationSpec(value: unknown): boolean {
  return isRecord(value) && isHash(value.textHash) && isHash(value.preparedTextHash)
    && isRecord(value.character) && isNonemptyString(value.character.id) && isNonemptyString(value.character.displayName)
    && isNonemptyString(value.voice) && (value.backend === "edge" || value.backend === "azure")
    && isStringRecord(value.pronunciations) && isStringRecord(value.synthesisOptions)
    && isFiniteNumber(value.preparationVersion) && Number.isInteger(value.preparationVersion) && value.preparationVersion > 0
    && isProductionOptions(value.productionOptions);
}

function isProvenance(value: unknown): boolean {
  if (!isRecord(value)) return false;
  if (value.kind === "inherited") return value.sourceProvenance === "unknown";
  return value.kind === "generated" && isHash(value.fingerprint) && isGenerationSpec(value.spec);
}

function isProductionEntry(value: unknown): value is ProductionEntry {
  if (!isRecord(value) || !isProvenance(value.provenance) || !isRecord(value.normalization)) return false;
  const normalization = value.normalization;
  return isHash(normalization.fingerprint) && isHash(normalization.sourceHash) && isHash(normalization.outputHash)
    && isProductionOptions(normalization.options) && isNonemptyString(normalization.ffmpegVersion)
    && (normalization.method === "measured-two-pass" || normalization.method === "short-speech-static-gain")
    && isMeasurement(normalization.source) && isMeasurement(normalization.output) && isProbe(normalization.probe);
}

export async function readManifest(path: string): Promise<ProductionManifest> {
  let text: string;
  try {
    text = await readFile(path, "utf8");
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return { schemaVersion: 1, files: {} };
    throw error;
  }
  const manifest: unknown = JSON.parse(text);
  if (!isRecord(manifest) || manifest.schemaVersion !== 1 || !isRecord(manifest.files)) {
    throw new Error(`Invalid or unsupported audio production manifest: ${path}`);
  }
  for (const [key, entry] of Object.entries(manifest.files)) {
    if (!isNonemptyString(key) || !isProductionEntry(entry)) {
      throw new Error(`Invalid audio production manifest entry "${key}": ${path}`);
    }
  }
  return manifest as ProductionManifest;
}

export function stagePath(output: string): string {
  return `${output}.${randomUUID()}.staging.mp3`;
}

export async function writeManifest(path: string, manifest: ProductionManifest): Promise<void> {
  const staged = `${path}.${randomUUID()}.staging`;
  try {
    await writeFile(staged, `${JSON.stringify(manifest, null, 2)}\n`);
    await rename(staged, path);
  } finally {
    await rm(staged, { force: true });
  }
}

function run(command: string, args: string[]): { stdout: string; stderr: string } {
  const result = spawnSync(command, args, { encoding: "utf8", maxBuffer: 8 * 1024 * 1024 });
  if (result.error) throw new Error(`Unable to run ${command}: ${result.error.message}`);
  if (result.status !== 0) throw new Error(`${command} failed (${result.status ?? result.signal}): ${result.stderr}`);
  return result;
}

export function ffmpegVersion(): string {
  return run("ffmpeg", ["-version"]).stdout.split("\n")[0];
}

export function probeAudio(path: string): Probe {
  const parsed = JSON.parse(run("ffprobe", [
    "-v", "error", "-show_entries", "stream=codec_name,sample_rate,channels:format=duration", "-of", "json", path,
  ]).stdout);
  const stream = parsed.streams?.[0];
  const durationSeconds = Number(parsed.format?.duration);
  if (parsed.streams?.length !== 1 || !stream || !Number.isFinite(durationSeconds) || durationSeconds <= 0) {
    throw new Error(`Expected one nonempty audio stream: ${path}`);
  }
  return { durationSeconds, sampleRate: Number(stream.sample_rate), channels: stream.channels, codec: stream.codec_name };
}

const loudnormTarget = `I=${productionOptions.integratedLufs}:TP=${productionOptions.truePeakDbtp - productionOptions.codecSafetyDb}:LRA=${productionOptions.loudnessRangeLu}`;

export function measureAudio(path: string): Measurement {
  // Decodes the whole stream; -xerror rejects damaged frames rather than concealing them.
  const { stderr } = run("ffmpeg", [
    "-hide_banner", "-nostats", "-v", "info", "-xerror", "-i", path,
    "-af", `loudnorm=${loudnormTarget}:print_format=json`, "-f", "null", "-",
  ]);
  const match = stderr.match(/\{\s*"input_i"[\s\S]*?\}/);
  if (!match) throw new Error(`ffmpeg returned no loudness measurement: ${path}`);
  const raw = JSON.parse(match[0]);
  const measurement = {
    integratedLufs: Number(raw.input_i),
    truePeakDbtp: Number(raw.input_tp),
    loudnessRangeLu: Number(raw.input_lra),
    thresholdLufs: Number(raw.input_thresh),
    targetOffsetLu: Number(raw.target_offset),
  };
  if (!Object.values(measurement).every(Number.isFinite)) {
    throw new Error(`Cannot normalize silence or unmeasurable speech: ${path}`);
  }
  return measurement;
}

export function normalizationFilter(source: Measurement, durationSeconds: number): { method: ProductionEntry["normalization"]["method"]; filter: string } {
  if (durationSeconds < productionOptions.shortSpeechSeconds) {
    // Very short speech has unstable gated loudness. Preserve its envelope and
    // accept a quieter result when the true-peak ceiling limits static gain.
    const gain = Math.min(productionOptions.integratedLufs - source.integratedLufs,
      productionOptions.truePeakDbtp - productionOptions.codecSafetyDb - source.truePeakDbtp);
    return { method: "short-speech-static-gain", filter: `volume=${gain}dB` };
  }
  return {
    method: "measured-two-pass",
    filter: `loudnorm=${loudnormTarget}:measured_I=${source.integratedLufs}:measured_TP=${source.truePeakDbtp}:measured_LRA=${source.loudnessRangeLu}:measured_thresh=${source.thresholdLufs}:offset=${source.targetOffsetLu}:linear=true`,
  };
}

export async function normalizeAudio(sourcePath: string, outputPath: string, provenance: Provenance, version: string): Promise<ProductionEntry> {
  const sourceHash = await fileHash(sourcePath);
  if (!sourceHash) throw new Error(`Missing source audio: ${sourcePath}`);
  const inputProbe = probeAudio(sourcePath);
  const source = measureAudio(sourcePath);
  const { method, filter } = normalizationFilter(source, inputProbe.durationSeconds);
  const staged = stagePath(outputPath);
  try {
    run("ffmpeg", [
      "-hide_banner", "-nostats", "-v", "error", "-xerror", "-i", sourcePath,
      "-map", "0:a:0", "-map_metadata", "-1", "-af", filter,
      "-ar", String(productionOptions.sampleRate), "-ac", String(productionOptions.channels),
      "-c:a", productionOptions.codec, "-b:a", productionOptions.bitrate, "-f", "mp3", staged,
    ]);
    const probe = probeAudio(staged);
    if (probe.sampleRate !== productionOptions.sampleRate || probe.channels !== productionOptions.channels || probe.codec !== "mp3"
      || Math.abs(probe.durationSeconds - inputProbe.durationSeconds) > 0.15) {
      throw new Error(`Normalized format/duration check failed: ${outputPath}`);
    }
    const output = measureAudio(staged);
    if (output.truePeakDbtp > productionOptions.truePeakDbtp) {
      throw new Error(`Encoded true peak exceeds ${productionOptions.truePeakDbtp} dBTP: ${outputPath} (${output.truePeakDbtp})`);
    }
    const outputHash = await fileHash(staged);
    if (!outputHash) throw new Error(`Missing staged audio: ${staged}`);
    await rename(staged, outputPath);
    return {
      provenance,
      normalization: {
        fingerprint: normalizationFingerprint(sourceHash, version), sourceHash, outputHash,
        options: productionOptions, ffmpegVersion: version, method, source, output, probe,
      },
    };
  } finally {
    await rm(staged, { force: true });
  }
}
