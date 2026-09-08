import { readFile, rename, rm, writeFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { prepareSpeech } from "./audio-production.ts";

export type WordBoundary = {
  audioOffset: number;
  textOffset: number;
  wordLength: number;
  text: string;
};
export type SpeechTiming = {
  version: 1;
  audioHash: string;
  text: string;
  words: { startMs: number; endOffset: number }[];
};
type PreparedSpeech = { text: string; originalEnds: (number | null)[] };

// Replacement interiors have no trustworthy character correspondence. Never
// interpolate them, even when the replacement happens to have the same length.
export function prepareSpeechWithOffsets(
  original: string, spokenName: string, pronunciations: Record<string, string>,
): PreparedSpeech {
  let prepared: PreparedSpeech = {
    text: original, originalEnds: Array.from({ length: original.length + 1 }, (_, i) => i),
  };
  function replace(pattern: RegExp, replacement: (word: string) => string) {
    const { text, originalEnds } = prepared;
    let nextText = "";
    const nextEnds: (number | null)[] = [originalEnds[0]];
    let cursor = 0;
    for (const match of text.matchAll(pattern)) {
      const start = match.index;
      const end = start + match[0].length;
      nextText += text.slice(cursor, start);
      nextEnds.push(...originalEnds.slice(cursor + 1, start + 1));
      const value = replacement(match[0]);
      nextText += value;
      if (value === match[0]) nextEnds.push(...originalEnds.slice(start + 1, end + 1));
      else if (value.length) {
        nextEnds.push(...Array<number | null>(value.length - 1).fill(null), originalEnds[end]);
      } else {
        // Deleting spoken content cannot yield a complete word alignment.
        nextEnds[nextEnds.length - 1] = null;
      }
      cursor = end;
    }
    nextText += text.slice(cursor);
    nextEnds.push(...originalEnds.slice(cursor + 1));
    prepared = { text: nextText, originalEnds: nextEnds };
  }
  replace(/HEXON/g, () => spokenName);
  const words = Object.keys(pronunciations).sort((a, b) => b.length - a.length);
  if (words.length) {
    const alternatives = words.map(word => word.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"));
    replace(new RegExp(`\\b(?:${alternatives.join("|")})\\b`, "g"), word => pronunciations[word]);
  }
  if (prepared.text !== prepareSpeech(original, spokenName, pronunciations)) {
    throw new Error("Speech preparation and timing mapping disagree");
  }
  return prepared;
}

const spokenContent = /[\p{L}\p{N}\p{M}\p{S}&@%#]/u;
const letter = /[\p{L}\p{N}\p{M}]/u;
const splitsSurrogatePair = (text: string, offset: number): boolean =>
  /[\uD800-\uDBFF]/.test(text[offset - 1] ?? "") && /[\uDC00-\uDFFF]/.test(text[offset] ?? "");

export function mapWordBoundaries(
  original: string, prepared: PreparedSpeech, boundaries: WordBoundary[], durationMs: number,
): { words: SpeechTiming["words"]; reason?: never } | { words?: never; reason: string } {
  if (!boundaries.length) return { reason: "voice supplied no word boundary events" };
  if (!Number.isFinite(durationMs) || durationMs <= 0) return { reason: "invalid audio duration" };
  const words: SpeechTiming["words"] = [];
  let previousEnd = 0;
  let previousOriginalEnd = 0;
  let previousStartMs = -1;
  for (const event of boundaries) {
    const end = event.textOffset + event.wordLength;
    // SDK speakTextAsync offsets use JavaScript string indices (UTF-16), not
    // SSML offsets, Unicode code points, bytes, or audio ticks.
    if (!Number.isSafeInteger(event.textOffset) || !Number.isSafeInteger(event.wordLength) ||
        event.wordLength <= 0 || event.textOffset < previousEnd || end > prepared.text.length ||
        splitsSurrogatePair(prepared.text, event.textOffset) || splitsSurrogatePair(prepared.text, end) ||
        prepared.text.slice(event.textOffset, end) !== event.text ||
        !spokenContent.test(event.text) || spokenContent.test(prepared.text.slice(previousEnd, event.textOffset))) {
      return { reason: "incomplete or inconsistent word boundary text offsets" };
    }
    const startMs = event.audioOffset / 10000;
    if (!Number.isSafeInteger(event.audioOffset) || startMs < 0 ||
        startMs < previousStartMs || startMs >= durationMs) {
      return { reason: `invalid or nonmonotonic word boundary audio offsets (word ${words.length + 1}: ${startMs}ms, previous ${previousStartMs}ms, duration ${durationMs}ms)` };
    }
    let originalEnd = prepared.originalEnds[end];
    const originalStart = prepared.originalEnds[event.textOffset];
    if (originalEnd == null || originalStart == null ||
        spokenContent.test(original.slice(previousOriginalEnd, originalStart)) ||
        originalEnd <= previousOriginalEnd || originalEnd > original.length ||
        splitsSurrogatePair(original, originalStart) || splitsSurrogatePair(original, originalEnd) ||
        (letter.test(original[originalEnd - 1] ?? "") && letter.test(original[originalEnd] ?? ""))) {
      return { reason: "ambiguous original-text word mapping" };
    }
    // Include adjacent closing punctuation, but do not consume the next word.
    while (originalEnd < original.length && !/\s/u.test(original[originalEnd]) &&
           !spokenContent.test(original[originalEnd])) originalEnd++;
    words.push({ startMs, endOffset: originalEnd });
    previousEnd = end;
    previousOriginalEnd = originalEnd;
    previousStartMs = startMs;
  }
  if (spokenContent.test(prepared.text.slice(previousEnd)) ||
      spokenContent.test(original.slice(previousOriginalEnd))) {
    return { reason: "word boundary events do not cover the complete narration" };
  }
  words[words.length - 1].endOffset = original.length;
  return { words };
}

export function timingIsFresh(value: unknown, audioHash: string | undefined, text: string): value is SpeechTiming {
  if (!audioHash || !/^[a-f0-9]{64}$/.test(audioHash) || !value || typeof value !== "object") return false;
  const timing = value as SpeechTiming;
  if (timing.version !== 1 || timing.audioHash !== audioHash || timing.text !== text ||
      !Array.isArray(timing.words) || !timing.words.length) return false;
  let start = -1;
  let end = 0;
  for (const word of timing.words) {
    if (!word || !Number.isFinite(word.startMs) || word.startMs < 0 || word.startMs < start ||
        !Number.isSafeInteger(word.endOffset) || word.endOffset <= end || word.endOffset > text.length ||
        splitsSurrogatePair(text, word.endOffset)) return false;
    start = word.startMs;
    end = word.endOffset;
  }
  return end === text.length;
}

export async function timingFileIsFresh(output: string, audioHash: string | undefined, text: string): Promise<boolean> {
  let raw: string;
  try {
    raw = await readFile(`${output}.timing.json`, "utf8");
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return false;
    throw error;
  }
  let value: unknown;
  try { value = JSON.parse(raw); }
  catch (error) {
    if (error instanceof SyntaxError) return false;
    throw error;
  }
  return timingIsFresh(value, audioHash, text);
}

export async function writeTiming(output: string, timing?: SpeechTiming): Promise<void> {
  const path = `${output}.timing.json`;
  if (!timing) {
    await rm(path, { force: true });
    return;
  }
  const staged = `${path}.${randomUUID()}.staging`;
  try {
    await writeFile(staged, `${JSON.stringify(timing, null, 2)}\n`);
    await rename(staged, path);
  } finally {
    await rm(staged, { force: true });
  }
}
