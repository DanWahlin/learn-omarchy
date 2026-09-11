import assert from "node:assert/strict";
import test from "node:test";
import { collectBarGeometry, measuredBarSnapshot } from "../tools/bar-geometry.mjs";

const monitor = { name: "eDP-1", x: 100, y: 50, width: 3072, height: 1920, scale: 1.6, transform: 0 };
const widget = { id: "custom.clock", x: 10, y: 2, width: 35, height: 24, visible: true, itemVisible: true };
const layers = (x = 100, y = 50, w = 1920, h = 30) => ({
  "eDP-1": { levels: { "2": [{ namespace: "omarchy-bar", x, y, w, h, alpha: 1 }] } },
});

test("measured bar widgets use live layer offsets on every screen edge", () => {
  for (const [barEdge, x, y, w, h] of [["top", 100, 50, 1920, 30], ["bottom", 100, 1220, 1920, 30],
    ["left", 100, 50, 50, 1200], ["right", 1970, 50, 50, 1200]] as const) {
    const snapshot = measuredBarSnapshot([widget], [monitor], layers(x, y, w, h));
    assert.equal(snapshot.screens[0].width, 1920);
    assert.deepEqual(snapshot.screens[0].widgets[0], {
      ...widget, x: widget.x + x - monitor.x, y: widget.y + y - monitor.y, barEdge,
    });
  }
});

test("unknown and ambiguous layouts never become precise geometry", () => {
  assert.throws(() => measuredBarSnapshot([widget], [monitor, monitor], layers()), /multi-monitor/);
  assert.throws(() => measuredBarSnapshot([widget], [monitor], {}), /unambiguous/);
  assert.throws(() => measuredBarSnapshot([widget], [monitor], layers(100, 40)), /hidden|outside/);
  assert.throws(() => measuredBarSnapshot([{ ...widget, x: 1900 }], [monitor], layers()), /do not fit/);
  assert.throws(() => measuredBarSnapshot([{}], [monitor], layers()), /Invalid/);
  assert.throws(() => measuredBarSnapshot([], [monitor], layers()), /no widget/);
});

test("bar and monitor changes during collection discard the sample", () => {
  let reads = [ [monitor], layers(), [widget], layers(), [monitor] ];
  assert.equal(collectBarGeometry(() => reads.shift()).screens[0].widgets[0].id, "custom.clock");
  reads = [[monitor], layers(), [widget], layers(100, 1220), [monitor]];
  assert.throws(() => collectBarGeometry(() => reads.shift()), /changed/);
});
