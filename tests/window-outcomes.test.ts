import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import vm from "node:vm";
import test from "node:test";

const api = vm.createContext({});
vm.runInContext(await readFile(new URL("../app/WindowOutcomes.js", import.meta.url), "utf8"), api);
const first = { address: "0xabc", at: [0, 0], size: [600, 700], workspace: { id: 1 }, monitor: 0, floating: false, fullscreen: 0 };
const peer = { ...first, address: "0xdef", at: [610, 0] };

test("resize requires a real owned-window size delta in the same workspace and mode", () => {
  const before = api.rectangle(first);
  assert.equal(api.resized(before, { ...first, size: [700, 700] }), true);
  for (const changed of [
    first, { ...first, at: [100, 0] }, { ...first, address: "0x123", size: [700, 700] },
    { ...first, size: [601, 700] }, { ...first, floating: true, size: [700, 700] },
    { ...first, workspace: { id: 2 }, size: [700, 700] },
    { ...first, hidden: true, size: [700, 700] }, { ...first, size: [NaN, 700] },
    { ...first, mapped: false, size: [700, 700] }, { ...first, size: [-1, 700] },
    { ...first, monitor: undefined, size: [700, 700] },
    { ...first, fullscreen: undefined, size: [700, 700] },
  ]) assert.equal(api.resized(before, changed), false);
  assert.equal(api.resized(null, first), false);
});

test("split requires the same two visible tiled windows to change separation axis", () => {
  const before = api.capture(first, peer);
  const stackedFirst = { ...first, size: [1210, 345] };
  const stackedPeer = { ...peer, at: [0, 355], size: [1210, 345] };
  assert.equal(api.splitChanged(before, stackedFirst, stackedPeer), true);
  assert.equal(api.splitChanged(api.capture(stackedFirst, stackedPeer), first, peer), true);
  assert.equal(api.splitChanged(before, { ...first, at: peer.at }, { ...peer, at: first.at }), false, "swap is not a split");
  assert.equal(api.splitChanged(before, first, peer), false);
  assert.equal(api.splitChanged(before, stackedFirst, { ...stackedPeer, address: "0x123" }), false);
  assert.equal(api.splitChanged(before, { ...stackedFirst, floating: true }, stackedPeer), false);
  assert.equal(api.splitChanged(before, stackedFirst, { ...stackedPeer, workspace: { id: 2 } }), false);
  assert.equal(api.splitChanged(null, stackedFirst, stackedPeer), false);
  assert.equal(api.splitChanged(api.capture(first, first), stackedFirst, stackedPeer), false);
});
