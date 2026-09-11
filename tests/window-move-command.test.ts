import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import test from "node:test";
import type { Course } from "../src/course.ts";

const course: Course = JSON.parse(await readFile(new URL("../courses/omarchy-basics.json", import.meta.url), "utf8"));
const moves = course.lessons.flatMap(lesson => lesson.steps)
  .filter(step => step.completion.windowState?.workspace !== undefined &&
    step.completion.windowState.focused === true);
const luaAvailable = spawnSync("lua", ["-v"], { encoding: "utf8" }).status === 0;

test("workspace moves focus only the owned target and refuse missing or unfocused targets",
  { skip: !luaAvailable }, () => {
    assert.equal(moves.length, 3);
    for (const step of moves) {
      assert.ok(step.help);
      const command = step.help.command[2].replaceAll("{tutorialWindow}", "address:0xaaa");
      for (const scenario of ["ready", "missing", "focus-refused"]) {
        const result = spawnSync("lua", ["-"], { encoding: "utf8", input: `
local target = { address = "0xaaa" }
local active = { address = "0xunrelated" }
local moves = 0
hl = {
  get_window = function(selector)
    assert(selector == "address:0xaaa")
    if "${scenario}" ~= "missing" then return target end
  end,
  get_active_window = function() return active end,
  dsp = {
    focus = function(spec) return { kind = "focus", window = spec.window } end,
    window = { move = function(spec) return { kind = "move", window = spec.window, workspace = spec.workspace } end }
  },
  dispatch = function(action)
    assert(action.window == "address:0xaaa")
    if action.kind == "focus" then
      if "${scenario}" ~= "focus-refused" then active = target end
    else
      assert(active == target and action.workspace == "2")
      moves = moves + 1
    end
  end
}
local ok = pcall(function() ${command} end)
assert(ok == ${scenario === "ready"})
assert(moves == ${scenario === "ready" ? 1 : 0})
` });
        assert.equal(result.status, 0, `${step.id}/${scenario}: ${result.stderr}`);
      }
    }
  });
