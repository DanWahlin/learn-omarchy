import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createContext, runInContext } from "node:vm";
import test from "node:test";

const layout = createContext({});
runInContext(await readFile(new URL("../app/TeachingLayout.js", import.meta.url), "utf8"), layout);

test("coaches park inside the desktop away from every bar edge and its tooltip region", () => {
  for (const [width, height] of [[1920, 1200], [1280, 720], [720, 1280]]) {
    const bars = [
      { x: 0, y: 0, width, height: 30 },
      { x: 0, y: height - 30, width, height: 30 },
      { x: 0, y: 0, width: 30, height },
      { x: width - 30, y: 0, width: 30, height },
    ];
    for (const bar of bars) {
      const position = layout.besideBar(width, height, 240, 260, bar);
      assert.equal(layout.intersects({ ...position, width: 240, height: 260 }, bar, 60), false);
      assert.ok(position.x >= 0 && position.x + 240 <= width);
      assert.ok(position.y >= 0 && position.y + 260 <= height);
    }
  }
});

test("small workspace pills inherit their measured bar edge", () => {
  const rightPill = {x: 1250, y: 10, width: 30, height: 25, edge: "right"};
  const position = layout.besideBar(1280, 720, 240, 260, rightPill);
  assert.equal(position.edge, "right");
  assert.ok(position.x + 240 <= rightPill.x - 60);
});
