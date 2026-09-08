import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { discoverCharacterPacks, type CharacterManifest } from "../src/character-packs.ts";
import { parseCourseJson } from "../src/course.ts";
import { fileHash, fingerprint, prepareSpeech, productionOptions, readManifest, sha256, type ProductionEntry } from "./audio-production.ts";

export type AudioClip = {
  character: string;
  step: string;
  part: "instruction" | "completion" | "welcome" | "wrapup";
  path: string;
  key: string;
  text: string;
};

export function clipIssues(clip: AudioClip, pack: CharacterManifest, entry: ProductionEntry | undefined, hash: string | undefined) {
  if (!hash) return ["missing recording"];
  if (!entry) return ["missing production metadata"];
  const issues: string[] = [];
  if (entry.normalization.outputHash !== hash) issues.push("recording hash mismatch");
  if (fingerprint(entry.normalization.options) !== fingerprint(productionOptions)) issues.push("outdated production settings");
  if (entry.provenance.kind !== "generated") return issues.concat("unverified original wording");
  const spec = entry.provenance.spec;
  const expected = prepareSpeech(clip.text, pack.spokenName ?? pack.displayName, { Omarchy: "Omaachi" });
  // Historical display names and directory IDs aren't evidence of stale speech.
  // Compare what was actually prepared for synthesis instead.
  if (spec.textHash !== sha256(clip.text) || spec.preparedTextHash !== sha256(expected))
    issues.push("outdated spoken text");
  if (pack.narration.mode === "own") {
    const voice = pack.narration.voices?.[spec.backend];
    if (voice && spec.voice !== voice) issues.push("outdated voice");
  }
  return issues;
}

export async function auditCourseAudio(coursePath: string) {
  const parsed = parseCourseJson(await readFile(coursePath, "utf8"));
  if (!parsed.course || parsed.errors.length) throw new Error(parsed.errors.join("\n"));
  const bundledRoot = fileURLToPath(new URL("../assets/characters", import.meta.url));
  const catalog = await discoverCharacterPacks({ bundledRoot });
  if (catalog.invalidBundledIds.length || !catalog.packs.length) throw new Error(catalog.diagnostics.join("\n"));
  const directory = dirname(resolve(coursePath));
  const welcome = JSON.parse(await readFile(resolve(directory, "welcome.json"), "utf8"));
  if (typeof welcome.instruction !== "string" || !welcome.instruction.trim() || welcome.audio !== "audio/host-welcome.mp3")
    throw new Error("Invalid welcome narration metadata");
  if (welcome.controls !== undefined && (!welcome.controls || typeof welcome.controls.instruction !== "string" ||
      !welcome.controls.instruction.trim() || welcome.controls.audio !== "audio/host-controls.mp3"))
    throw new Error("Invalid welcome controls narration metadata");
  const manifest = await readManifest(resolve(directory, "audio/production-manifest.json"));
  if (welcome.recommendationAudio !== undefined && (welcome.recommendationAudio !== "audio/host-lessons.mp3" ||
      typeof welcome.recommendation !== "string" || !welcome.recommendation.trim()))
    throw new Error("Invalid welcome lesson-menu narration");
  const clips: AudioClip[] = [];
  const issues: { clip: AudioClip; reasons: string[] }[] = [];
  for (const pack of catalog.packs) {
    if (pack.manifest.narration.mode !== "own") continue;
    const instruction = welcome.instructions?.[pack.id] ?? welcome.instruction;
    if (typeof instruction !== "string" || !instruction.trim()) throw new Error("Invalid character welcome instruction");
    const records = [{ step: "host-welcome", part: "welcome" as const, text: instruction, audio: welcome.audio }];
    const items: { step: string; part: AudioClip["part"]; text: string; audio: string }[] = records;
    if (welcome.controls) items.push({ step: "host-controls", part: "welcome",
      text: welcome.controls.instruction, audio: welcome.controls.audio });
    if (welcome.recommendationAudio) items.push({ step: "host-lessons", part: "welcome",
      text: welcome.recommendation, audio: welcome.recommendationAudio });
    for (const [variant, wrapUp] of Object.entries(parsed.course.wrapUp ?? {}))
      items.push({ step: "lesson-wrapup-" + variant, part: "wrapup", text: wrapUp.text, audio: wrapUp.audio });
    for (const lesson of parsed.course.lessons) {
      if (lesson.wrapUp) items.push({ step: lesson.id, part: "wrapup", text: lesson.wrapUp.text, audio: lesson.wrapUp.audio });
    }
    for (const step of parsed.course.lessons.flatMap(lesson => lesson.steps)) {
      if (step.audio) items.push({ step: step.id, part: "instruction", text: step.instruction, audio: step.audio });
      if (step.completionAudio && step.completionMessage)
        items.push({ step: step.id, part: "completion", text: step.completionMessage, audio: step.completionAudio });
    }
    for (const item of items) {
      const slash = item.audio.lastIndexOf("/");
      const relative = item.audio.slice(0, slash + 1) + pack.manifest.narration.audioSet + "/" + item.audio.slice(slash + 1);
      const path = resolve(directory, relative);
      const key = relative.startsWith("audio/") ? relative.slice(6) : relative;
      const clip: AudioClip = { character: pack.id, step: item.step, part: item.part, text: item.text, key, path };
      clips.push(clip);
      const reasons = clipIssues(clip, pack.manifest, manifest.files[key], await fileHash(path));
      if (reasons.length) issues.push({ clip, reasons });
    }
  }
  return { clips, issues };
}
