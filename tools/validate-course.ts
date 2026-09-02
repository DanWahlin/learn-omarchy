#!/usr/bin/env -S node --experimental-strip-types

import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { parseCourseJson } from "../src/course.ts";

const coursePath = resolve(process.argv[2] ?? "courses/omarchy-basics.json");

try {
  const result = parseCourseJson(await readFile(coursePath, "utf8"));
  if (result.errors.length > 0) {
    console.error(`Invalid course: ${coursePath}`);
    result.errors.forEach((error) => console.error(`- ${error}`));
    process.exitCode = 1;
  } else {
    const stepCount = result.course!.lessons.reduce(
      (total, lesson) => total + lesson.steps.length,
      0,
    );
    console.log(
      `Valid course: ${result.course!.title} (${result.course!.lessons.length} lesson(s), ${stepCount} step(s))`,
    );
  }
} catch (error) {
  console.error(
    `Unable to read course ${coursePath}: ${error instanceof Error ? error.message : String(error)}`,
  );
  process.exitCode = 1;
}
