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

test("top-bar pointing stays close using both guides' registered fingertips", async () => {
  const spriteSource = await readFile(new URL("../app/CharacterSprite.qml", import.meta.url), "utf8");
  for (const id of ["owl", "ohm-1"]) {
    const pack = JSON.parse(await readFile(new URL(`../assets/characters/${id}/character.json`, import.meta.url), "utf8"));
    const sprite = createContext({ poses: pack.renderer.poses, landmarkFacing: 1, facing: 1 });
    for (const name of ["tip", "registeredCoordinate"]) {
      runInContext(spriteSource.match(new RegExp("  function " + name + "\\([^\\n]*\\) \\{[\\s\\S]*?\\n  \\}"))![0], sprite);
    }
    for (const [width, height] of [[1920, 1200], [1280, 720], [720, 1280]]) {
      for (const scale of [1, 0.85]) {
        for (const facing of [-1, 1]) {
          sprite.landmarkFacing = facing;
          const tip = {
            x: 120 + (8 + sprite.tip("point-up", "x") - 120) * scale,
            y: 260 + (68 + sprite.tip("point-up", "y") - 260) * scale,
            canvasTop: 260 - 192 * scale,
          };
          for (const target of [
            { x: 0, y: 0, width, height: 30, edge: "top" },
            { x: 8, y: 1, width: 180, height: 27, edge: "top" },
            { x: width / 2 - 165, y: 1, width: 330, height: 27, edge: "top" },
            { x: width - 364, y: 1, width: 350, height: 27, edge: "top" },
            { x: 8, y: 1, width: 32, height: 30, edge: "top" },
          ]) {
            const position = layout.besideBar(width, height, 240, 260, target, tip);
            const gap = position.y + tip.y - target.y - target.height;
            assert.ok(Math.abs(gap - 44) < 0.001, `${id}: fingertip gap ${gap}, not container padding`);
            assert.ok(position.y + tip.canvasTop >= 0, "the sprite canvas stays on screen");
            assert.ok(position.x >= 18 && position.x + 240 <= width - 18);
            if (target.width === width)
              assert.ok(Math.abs(position.x + tip.x - width / 2) < 0.001, "point at the target centre");
          }
        }
      }
    }
  }
});
