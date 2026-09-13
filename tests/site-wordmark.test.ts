import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import vm from "node:vm";
import test from "node:test";

const source = await readFile(new URL("../docs/script.js", import.meta.url), "utf8");
const context = vm.createContext({});
vm.runInContext(source.slice(source.indexOf("  const THEMES ="), source.indexOf("  let currentTheme ="))
  + source.slice(source.indexOf("  const FONT ="), source.indexOf("  document.querySelectorAll('[data-pixel-text]')"))
  + "\nglobalThis.themes = THEMES; globalThis.font = FONT;", context);
const stops = ["top", "blush", "pink", "violet", "cyan"];

test("the splash-style wordmark reuses the exact glyphs with separated square pixels", () => {
  const wordmark = context.pixelWordmark("Learn Omarchy");
  assert.equal(wordmark.width, 75);
  assert.equal(wordmark.height, 7);
  let pixels = 0;
  for (const char of "LEARN OMARCHY") {
    pixels += context.font[char].join("").split("█").length - 1;
  }
  assert.equal((wordmark.path.match(/M/g) || []).length, pixels);
  assert.equal((wordmark.path.match(/h\.92v\.92h-\.92z/g) || []).length, pixels);
  assert.equal(context.pixelWordmark("?").path, "");
});

test("all site themes keep every wordmark gradient segment readable", () => {
  const palettes = new Set<string>();
  for (const [id, theme] of Object.entries(context.themes)) {
    const tokens = context.tokensFor(theme);
    const palette = stops.map(stop => tokens[`--wordmark-${stop}`]);
    palettes.add(palette.join(","));
    for (let segment = 1; segment < palette.length; segment++) {
      for (let step = 0; step <= 100; step++) {
        const color = context.mix(palette[segment - 1], palette[segment], step / 100);
        for (const background of [tokens["--bg"], tokens["--bg-deep"]]) {
          assert.ok(context.contrastRatio(color, background) >= 4.5,
            `${id}: ${color} must stand out against ${background}`);
        }
      }
    }
  }
  assert.equal(palettes.size, Object.keys(context.themes).length, "every theme supplies its own palette");
});

test("theme switching, accessible text and high-contrast rendering remain connected", async () => {
  const html = await readFile(new URL("../docs/index.html", import.meta.url), "utf8");
  const css = await readFile(new URL("../docs/style.css", import.meta.url), "utf8");
  assert.match(source, /root\.style\.setProperty\(k, tokens\[k\]\)/);
  assert.match(source, /stop\.style\.stopColor = 'var\(--wordmark-'/);
  assert.match(source, /svg\.setAttribute\('aria-hidden', 'true'\)/);
  assert.match(html, /<h1>Learn Omarchy by doing\.<\/h1>/);
  assert.match(html, /aria-hidden="true">LEARN OMARCHY<\/pre>/);
  assert.match(css, /shape-rendering: crispEdges/);
  assert.match(css, /\.wordmark-pixels \{ fill: CanvasText; \}/);
});
