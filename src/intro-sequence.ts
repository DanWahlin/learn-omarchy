import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";

// Evaluate only this trusted application module, never pack-provided source.
// QML imports the same ES5-compatible file, keeping validation identical.
const timeline = runInNewContext(
  readFileSync(new URL("../app/IntroTimeline.js", import.meta.url), "utf8") +
    "\n({ validateIntroSequence, introAssetPaths, compile, sample, ease })",
  Object.create(null),
  { timeout: 1000 },
) as {
  validateIntroSequence(value: unknown): string[];
  introAssetPaths(value: unknown): string[];
  compile(value: unknown): unknown;
  sample(value: unknown, elapsed: number, width: number, height: number, sizes?: unknown): unknown;
  ease(name: string, t: number): number;
};

export function validateIntroSequence(value: unknown): string[] {
  return Array.from(timeline.validateIntroSequence(value));
}

export function introAssetPaths(value: unknown): string[] {
  return Array.from(timeline.introAssetPaths(value));
}

export const compileIntroSequence = timeline.compile;
export const sampleIntroSequence = timeline.sample;
