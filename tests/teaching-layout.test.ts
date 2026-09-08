import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { createContext, runInContext } from "node:vm";

const layout = createContext({});
runInContext(await readFile(new URL("../app/TeachingLayout.js", import.meta.url), "utf8"), layout);

test("teaching cards stay bottom centered when no native panel needs space", () => {
  assert.equal(layout.panelWidth(1920, 1200, 900, null), 900);
  const position = layout.position(1920, 1200, 900, 260, null);
  assert.equal(position.x, 510);
  assert.equal(position.y, 910);
});

test("tall centered native menus get a readable, nonoverlapping side card", () => {
  for (const [screenWidth, screenHeight, menuWidth, menuHeight, cardHeight] of [
    [1920, 1200, 420, 920, 350],
    [1920, 1200, 420, 1050, 520],
    [1280, 800, 400, 650, 370],
    [1600, 1000, 500, 800, 450],
  ]) {
    const target = { x: (screenWidth - menuWidth) / 2, y: (screenHeight - menuHeight) / 2,
      width: menuWidth, height: menuHeight };
    const width = layout.panelWidth(screenWidth, screenHeight, 900, target);
    const position = layout.position(screenWidth, screenHeight, width, cardHeight, target);
    const card = { ...position, width, height: cardHeight };
    assert.ok(width >= 340);
    assert.equal(layout.intersects(card, target, 16), false, JSON.stringify({ card, target }));
    assert.ok(card.x >= 12 && card.y >= 12);
    assert.ok(card.x + width <= screenWidth - 12);
    assert.ok(card.y + cardHeight <= screenHeight - 12);
  }
});

test("short top panels don't narrow the normal bottom card", () => {
  const target = { x: 700, y: 45, width: 520, height: 300 };
  assert.equal(layout.panelWidth(1920, 1200, 900, target), 900);
  assert.equal(layout.position(1920, 1200, 900, 300, target).y, 870);
});

test("side panels leave the coaching card on the opposite side", () => {
  for (const x of [20, 1200]) {
    const target = { x, y: 60, width: 650, height: 1000 };
    const width = layout.panelWidth(1920, 1200, 900, target);
    const card = { ...layout.position(1920, 1200, width, 400, target), width, height: 400 };
    assert.equal(layout.intersects(card, target, 16), false);
  }
});
