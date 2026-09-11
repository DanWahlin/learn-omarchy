import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import test from "node:test";

const course = JSON.parse(await readFile(new URL("../courses/omarchy-basics.json", import.meta.url), "utf8"));
const steps = course.lessons.flatMap((lesson: any) => lesson.steps)
  .filter((step: any) => step.completion.windowState?.splitChanged);
const luaAvailable = spawnSync("lua", ["-v"], { encoding: "utf8" }).status === 0;

test("split commands never reach the layout dispatcher after missing targets or failed focus", { skip: !luaAvailable }, () => {
  const scenarios = [
    { name: "ready", mutate: "", focusSucceeds: true, expected: true },
    { name: "missing-target", mutate: 'windows["address:0xaaa"] = nil', focusSucceeds: true, expected: false },
    { name: "missing-peer", mutate: 'windows["address:0xbbb"] = nil', focusSucceeds: true, expected: false },
    { name: "floating-peer", mutate: "peer.floating = true", focusSucceeds: true, expected: false },
    { name: "fullscreen", mutate: "target.fullscreen = 1", focusSucceeds: true, expected: false },
    { name: "other-workspace", mutate: "peer.workspace.id = 2", focusSucceeds: true, expected: false },
    { name: "focus-refused", mutate: "", focusSucceeds: false, expected: false },
  ];
  assert.equal(steps.length, 2);
  for (const step of steps) {
    const command = step.help.command[2].replaceAll("{tutorialWindow}", "address:0xaaa").replaceAll("{peerWindow}", "address:0xbbb");
    for (const scenario of scenarios) {
      const script = `
local target = { address = "0xaaa", floating = false, fullscreen = 0, workspace = { id = 1 } }
local peer = { address = "0xbbb", floating = false, fullscreen = 0, workspace = { id = 1 } }
local active = { address = "0xunrelated" }
local windows = { ["address:0xaaa"] = target, ["address:0xbbb"] = peer }
local layoutCalls = 0
hl = {
  get_window = function(selector) return windows[selector] end,
  get_active_window = function() return active end,
  dsp = {
    focus = function(spec) return { kind = "focus", window = spec.window } end,
    layout = function(message) assert(message == "togglesplit"); return { kind = "layout" } end
  },
  dispatch = function(action)
    if action.kind == "focus" then
      assert(action.window == "address:0xaaa")
      if ${scenario.focusSucceeds} then active = target end
    else
      assert(active.address == target.address)
      layoutCalls = layoutCalls + 1
    end
  end
}
${scenario.mutate}
local ok = pcall(function() ${command} end)
assert(ok == ${scenario.expected})
assert(layoutCalls == ${scenario.expected ? 1 : 0})
`;
      const result = spawnSync("lua", ["-"], { input: script, encoding: "utf8" });
      assert.equal(result.status, 0, `${step.id}/${scenario.name}: ${result.stderr}`);
    }
  }
});
