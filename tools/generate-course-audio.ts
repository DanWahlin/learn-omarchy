#!/usr/bin/env -S node --experimental-strip-types

import { access, mkdir, readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { parseCourseJson } from "../src/course.ts";

const coursePath = resolve(process.argv[2] ?? "courses/omarchy-basics.json");
const voice = process.env.LEARN_OMARCHY_TTS_VOICE ?? "en-GB-RyanNeural";
const edgeTts = process.env.EDGE_TTS_BIN ?? "edge-tts";
const onlyMissing = process.argv.includes("--missing");

const result = parseCourseJson(await readFile(coursePath, "utf8"));
if (!result.course || result.errors.length > 0) {
  result.errors.forEach((error) => console.error(`- ${error}`));
  process.exit(1);
}

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

    const child = spawnSync(
      edgeTts,
      [
        "--voice",
        voice,
        "--text",
        step.instruction,
        "--write-media",
        output,
      ],
      {
        encoding: "utf8",
        stdio: "inherit",
      },
    );

    if (child.error) {
      console.error(`Unable to run ${edgeTts}: ${child.error.message}`);
      process.exit(1);
    }
    if (child.status !== 0) {
      process.exit(child.status ?? 1);
    }
    generated++;
    console.log(`Generated ${step.audio}`);
  }
}

console.log(`Generated ${generated} narration file(s) with ${voice}.`);
