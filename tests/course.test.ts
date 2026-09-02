import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { parseCourseJson, validateCourse } from "../src/course.ts";

test("bundled course is valid", async () => {
  const json = await readFile(
    new URL("../courses/omarchy-basics.json", import.meta.url),
    "utf8",
  );
  const result = parseCourseJson(json);

  assert.deepEqual(result.errors, []);
  assert.equal(result.course?.lessons[0]?.steps[0]?.completion.type, "hyprland-layer-open");
});

test("rejects shell strings and unsafe audio paths", () => {
  const errors = validateCourse({
    schemaVersion: 1,
    id: "unsafe",
    title: "Unsafe",
    lessons: [
      {
        id: "lesson",
        title: "Lesson",
        steps: [
          {
            id: "step",
            instruction: "Do something",
            keys: ["SUPER", "+", "A"],
            audio: "../outside.mp3",
            help: { label: "Help", command: "rm -rf /" },
            completion: {
              type: "hyprland-layer-open",
              namespace: "example",
            },
            highlight: {
              shape: "rectangle",
              anchor: "center",
              x: 0,
              y: 0,
              width: 200,
              height: 100,
              borderWidth: 4,
            },
          },
        ],
      },
    ],
  });

  assert.ok(errors.some((error) => error.includes("safe path")));
  assert.ok(errors.some((error) => error.includes("array of non-empty strings")));
});

test("requires equal dimensions for circle highlights", () => {
  const errors = validateCourse({
    schemaVersion: 1,
    id: "circle",
    title: "Circle",
    lessons: [
      {
        id: "lesson",
        title: "Lesson",
        steps: [
          {
            id: "step",
            instruction: "Find the target",
            keys: ["A"],
            completion: {
              type: "hyprland-layer-open",
              namespace: "example",
            },
            highlight: {
              shape: "circle",
              anchor: "center",
              x: 0,
              y: 0,
              width: 100,
              height: 80,
              borderWidth: 4,
            },
          },
        ],
      },
    ],
  });

  assert.ok(errors.some((error) => error.includes("equal width and height")));
});
