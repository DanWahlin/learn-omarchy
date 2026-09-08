import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createContext, runInContext } from "node:vm";
import test from "node:test";

const timing = createContext({});
runInContext(await readFile(new URL("../app/CaptionTiming.js", import.meta.url), "utf8"), timing);

test("reveals whole words using actual media timestamps, including seeking backwards", () => {
  const words = [{ startMs: 100, endOffset: 5 }, { startMs: 600, endOffset: 12 }];
  const reveal = (position: number) => timing.revealOffset("Hello world!", "Hello world!", "Hello world!", words, position);
  assert.equal(reveal(0), 0);
  assert.equal(reveal(100), 5);
  assert.equal(reveal(599), 5);
  assert.equal(reveal(600), 12);
  assert.equal(reveal(300), 5);
  assert.equal(reveal(-1), -1);
});

test("caption formatting and coach names don't invalidate original-text offsets", () => {
  const original = "Hi HEXON. Welcome!";
  const display = "Hi Ohm-1. Welcome!";
  const formatted = "Hi Ohm-1.\n\nWelcome!";
  const words = [{ startMs: 0, endOffset: 2 }, { startMs: 200, endOffset: 9 }, { startMs: 400, endOffset: 18 }];
  assert.equal(timing.revealOffset(original, display, formatted, words, 200), 9);
  assert.equal(timing.revealOffset(original, display, formatted, words, 400), formatted.length);
  assert.equal(timing.revealOffset("Your way.", "Your way.", "Your\u00a0way.",
    [{ startMs: 0, endOffset: 4 }, { startMs: 500, endOffset: 9 }], 0), 4);
});

test("missing, partial, or malformed timing falls back to full text", () => {
  for (const words of [[], [{ startMs: -1, endOffset: 5 }], [{ startMs: 0, endOffset: 20 }],
    [{ startMs: 0, endOffset: 5 }], [{ startMs: 10, endOffset: 5 }, { startMs: 0, endOffset: 12 }]]) {
    assert.equal(timing.revealOffset("Hello world!", "Hello world!", "Hello world!", words, 0), -1);
  }
  assert.equal(timing.revealOffset("Hi HEXON", "Hi Two Names", "Hi Two Names",
    [{ startMs: 0, endOffset: 2 }, { startMs: 100, endOffset: 8 }], 100), -1);
  assert.equal(timing.revealOffset("Hi.", "Hi.", "Wrong.", [{ startMs: 0, endOffset: 3 }], 0), -1);
});

test("reveal markup escapes text and retains the entire suffix for stable layout", () => {
  assert.equal(timing.styledText("Hi <Ohm> & Ollie", 2),
    'Hi<font color="#00000000"> &lt;Ohm&gt; &amp; Ollie</font>');
  assert.equal(timing.styledText("Hi\nOllie", -1), "Hi<br/>Ollie");
});

test("muted reading reveals gradually and never hides an already visible prefix", () => {
  const text = "One two three four.";
  assert.equal(timing.readingOffset(text, 0, 200, 0), 3);
  assert.equal(timing.readingOffset(text, 300, 200, 0), 7);
  assert.equal(timing.readingOffset(text, 600, 200, 0), 13);
  assert.equal(timing.readingOffset(text, 900, 200, 0), text.length);
  assert.ok(timing.readingOffset(text, 0, 200, 7) >= 7);
  assert.equal(timing.readingOffset(text, 0, 200, text.length), text.length);
  assert.equal(timing.readingOffset(text, 0, 0, 0), -1);
});

test("similar-length unrelated prompts cannot borrow timing from a recording", () => {
  const words = [{ startMs: 0, endOffset: 4 }, { startMs: 200, endOffset: 13 }];
  assert.equal(timing.revealOffset("Open terminal", "Help me again", "Help me again", words, 200), -1);
  assert.equal(timing.revealOffset("Hi HEXON!", "Hi Ohm-1?", "Hi Ohm-1?",
    [{ startMs: 0, endOffset: 2 }, { startMs: 100, endOffset: 9 }], 100), -1);
  assert.equal(timing.revealOffset("Hi HEXON!", "Hi OHM!", "Hi OHM!",
    [{ startMs: 0, endOffset: 2 }, { startMs: 100, endOffset: 9 }], 100), 7);
});
