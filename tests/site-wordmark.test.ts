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

test("all site themes keep body, secondary, and accent text readable", () => {
  const backgrounds = ["--bg", "--bg-deep", "--crust", "--surface", "--surface-2"];
  const textRoles = [
    ["--ink", 4.5],
    ["--ink-2", 4.5],
    ["--muted", 5.5],
    ["--dim", 4.5],
    ["--brand-text", 4.5],
    ["--pink-text", 4.5],
    ["--cyan-text", 4.5],
    ["--sky-text", 4.5],
    ["--blue-text", 4.5],
    ["--orange-text", 4.5],
    ["--green-text", 4.5],
    ["--magenta-text", 4.5],
    ["--red-text", 4.5],
    ["--yellow-text", 4.5],
  ] as const;
  for (const [id, theme] of Object.entries(context.themes)) {
    const tokens = context.tokensFor(theme);
    for (const [foreground, minimum] of textRoles) {
      for (const background of backgrounds) {
        assert.ok(context.contrastRatio(tokens[foreground], tokens[background]) >= minimum,
          `${id}: ${foreground} must stand out against ${background}`);
      }
    }
    for (const background of ["--brand", "--pink"]) {
      assert.ok(context.contrastRatio(tokens["--brand-ink"], tokens[background]) >= 4.5,
        `${id}: --brand-ink must stand out against ${background}`);
    }
  }
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

test("the homepage presents Arcade clearly and exposes mobile theme controls", async () => {
  const html = await readFile(new URL("../docs/index.html", import.meta.url), "utf8");
  const css = await readFile(new URL("../docs/style.css", import.meta.url), "utf8");
  assert.doesNotMatch(html, /guide-steps|Choose a guide|Follow along|Press the keys/);
  for (const game of ["Window Rescue", "Shortcut Sprint", "Keyfall"])
    assert.match(html, new RegExp(`<h3>${game}</h3>`));
  assert.match(html, /images\/arcade-rescue-ship\.png/);
  assert.match(html, /images\/arcade-rescue-planet\.png/);
  assert.match(html, /id="theme-previous"/);
  assert.match(html, /id="theme-keep"[^>]*>Use this theme</);
  assert.match(html, /id="theme-next"/);
  assert.match(source, /previousBtn\.addEventListener\('click'/);
  assert.match(source, /keepBtn\.addEventListener\('click', commit\)/);
  assert.match(source, /nextBtn\.addEventListener\('click'/);
  assert.match(css, /@media \(max-width: 720px\)[\s\S]*\.theme-controls \{ display: flex; \}/);
});
