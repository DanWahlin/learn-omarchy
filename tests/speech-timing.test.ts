import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { mkdir, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { createRequire } from "node:module";
import test from "node:test";
import * as sdk from "microsoft-cognitiveservices-speech-sdk";
import { sha256 } from "../tools/audio-production.ts";
import {
  mapWordBoundaries, prepareSpeechWithOffsets, timingFileIsFresh, timingIsFresh, writeTiming,
} from "../tools/speech-timing.ts";
import type { SpeechTiming, WordBoundary } from "../tools/speech-timing.ts";
import { speechWebSocketEndpoint, synthesizeWithWordBoundaries } from "../tools/azure-speech-timing.ts";

function boundaries(text: string, tokens: string[]): WordBoundary[] {
  let cursor = 0;
  return tokens.map((token, i) => {
    const textOffset = text.indexOf(token, cursor);
    assert.notEqual(textOffset, -1);
    cursor = textOffset + token.length;
    return new sdk.SpeechSynthesisWordBoundaryEventArgs(
      (125 + i * 275) * 10000, 1000000, token, token.length, textOffset, sdk.SpeechSynthesisBoundaryType.Word,
    );
  });
}

test("SDK word events map UTF-16 indices and 100ns ticks, including punctuation and multiline text", () => {
  const text = "“Hi!”\nI'm 𐐀da.\nReady?";
  const prepared = prepareSpeechWithOffsets(text, "Ollie", {});
  const events = boundaries(prepared.text, ["Hi", "I'm", "𐐀da", "Ready"]);
  assert.equal(events[2].wordLength, 4, "non-BMP character occupies two UTF-16 code units");
  assert.equal(events[2].textOffset, text.indexOf("𐐀da"));
  assert.deepEqual(mapWordBoundaries(text, prepared, events, 3000), { words: [
    { startMs: 125, endOffset: text.indexOf("\n") },
    { startMs: 400, endOffset: text.indexOf(" 𐐀da") },
    { startMs: 675, endOffset: text.lastIndexOf("\n") },
    { startMs: 950, endOffset: text.length },
  ] });
});

test("genuine equal-time word events reveal together without inventing later timestamps", () => {
  const text = "with it.";
  const prepared = prepareSpeechWithOffsets(text, "Ohm", {});
  const events = boundaries(text, ["with", "it"]);
  const sameTime = events.map(event => ({ text: event.text, textOffset: event.textOffset,
    wordLength: event.wordLength, audioOffset: 39890000 }));
  const result = mapWordBoundaries(text, prepared, sameTime, 4550);
  assert.deepEqual(result, { words: [{ startMs: 3989, endOffset: 4 }, { startMs: 3989, endOffset: 8 }] });
  assert.ok(timingIsFresh({ version: 1, audioHash: "a".repeat(64), text, words: result.words },
    "a".repeat(64), text));
});

test("pinned SDK finds plain-text event offsets with UTF-16 indexOf, including repeated and XML-sensitive words", () => {
  const require = createRequire(import.meta.url);
  const { SynthesisTurn } = require("microsoft-cognitiveservices-speech-sdk/distrib/lib/src/common.speech/SynthesisTurn.js");
  const { MetadataType } = require("microsoft-cognitiveservices-speech-sdk/distrib/lib/src/common.speech/ServiceMessages/SynthesisAudioMetadata.js");
  const turn = new SynthesisTurn();
  const text = "𐐀da & Hi\n<Hi> Hi";
  turn.startNewSynthesis("fixture", text, false, undefined);
  for (const [word, offset] of [["𐐀da", 0], ["&", 5], ["Hi", 7], ["Hi", 11], ["Hi", 15]]) {
    turn.updateTextOffset(word, MetadataType.WordBoundary);
    assert.equal(turn.currentTextOffset, offset);
  }
  turn.updateTextOffset("absent", MetadataType.WordBoundary);
  assert.equal(turn.currentTextOffset, -1, "missing SDK text offsets must be rejected, not reconstructed");
});

test("SDK synthesis captures same-request PCM and word-only events; no events differs from synthesis failure", async (t) => {
  const directory = resolve("tests", `.sdk-timing-${randomUUID()}`);
  await mkdir(directory);
  const bytes = new Uint8Array(1200).fill(1);
  const output = resolve(directory, "clip.wav");
  const voice = "en-US-Andrew:DragonHDLatestNeural";
  const credentials = { key: "test-key-not-a-credential", region: "westus" };
  let mode = "words";
  let calls = 0;
  const mock = t.mock.method(sdk.SpeechSynthesizer.prototype, "speakTextAsync", function (text, success, failure) {
    calls++;
    assert.equal(text, "Hi & hello.");
    assert.equal(this.properties.getProperty(sdk.PropertyId.SpeechServiceConnection_SynthVoice), voice);
    assert.equal(this.properties.getProperty(sdk.PropertyId.SpeechServiceResponse_RequestWordBoundary), "true");
    assert.equal(this.properties.getProperty(sdk.PropertyId.SpeechServiceConnection_SynthOutputFormat),
      "Riff24Khz16BitMonoPcm");
    if (mode === "error") return failure("transport details that must not be printed");
    if (mode === "canceled") return success(new sdk.SpeechSynthesisResult("fixture", sdk.ResultReason.Canceled));
    if (mode === "words") {
      for (const event of boundaries(text, ["Hi", "&", "hello"])) this.wordBoundary(this, event);
      this.wordBoundary(this, new sdk.SpeechSynthesisWordBoundaryEventArgs(
        9000000, 0, ".", 1, text.length - 1, sdk.SpeechSynthesisBoundaryType.Punctuation));
    }
    success(new sdk.SpeechSynthesisResult("fixture", sdk.ResultReason.SynthesizingAudioCompleted, bytes.buffer));
  });
  try {
    const events = await synthesizeWithWordBoundaries("Hi & hello.", output, credentials, voice);
    assert.equal(calls, 1, "audio and metadata share a single synthesis");
    assert.deepEqual(events.map(event => event.text), ["Hi", "&", "hello"]);
    assert.deepEqual(await readFile(output), Buffer.from(bytes));
    mode = "no-events";
    assert.deepEqual(await synthesizeWithWordBoundaries("Hi & hello.", output, credentials, voice), []);
    for (mode of ["error", "canceled"]) {
      await assert.rejects(synthesizeWithWordBoundaries("Hi & hello.", output, credentials, voice),
        error => error instanceof Error && /synthesis failed/.test(error.message) && !/transport details/.test(error.message));
    }
  } finally {
    mock.mock.restore();
    await rm(directory, { recursive: true, force: true });
  }
});

test("name and pronunciation replacements map to original template ends, never respelled offsets", () => {
  const text = "Hi HEXON, welcome to Omarchy!\nHEXON & Omarchy.";
  const prepared = prepareSpeechWithOffsets(text, "Ollie", { Omarchy: "Ohmaachee" });
  assert.equal(prepared.text, "Hi Ollie, welcome to Ohmaachee!\nOllie & Ohmaachee.");
  const result = mapWordBoundaries(text, prepared,
    boundaries(prepared.text, ["Hi", "Ollie", "welcome", "to", "Ohmaachee", "Ollie", "&", "Ohmaachee"]), 4000);
  assert.ok(result.words);
  assert.equal(result.words[1].endOffset, text.indexOf(",") + 1);
  assert.equal(result.words[4].endOffset, text.indexOf("!") + 1);
  assert.equal(result.words.at(-1)?.endOffset, text.length);
  assert.equal(text.slice(0, result.words[5].endOffset), "Hi HEXON, welcome to Omarchy!\nHEXON");
});

test("mapping preserves shared preparation semantics: nonrecursive, escaped, literal, and chained", () => {
  assert.equal(prepareSpeechWithOffsets("A B a.b axb", "HEXON", { A: "B", B: "C", "a.b": "word" }).text, "B C word axb");
  assert.equal(prepareSpeechWithOffsets("HEXON", "$&", {}).text, "$&");
  const text = "HEXON.";
  const prepared = prepareSpeechWithOffsets(text, "Omarchy", { Omarchy: "Omaachi" });
  assert.deepEqual(mapWordBoundaries(text, prepared, boundaries(prepared.text, ["Omaachi"]), 1000),
    { words: [{ startMs: 125, endOffset: text.length }] });
});

test("missing, partial, malformed, reordered, invented, and out-of-duration events have no fallback timings", () => {
  const text = "Hello & world.";
  const prepared = prepareSpeechWithOffsets(text, "Ollie", {});
  const valid = boundaries(text, ["Hello", "&", "world"]);
  const mutate = (change: Partial<WordBoundary>) => [{ ...valid[0], ...change }, ...valid.slice(1)];
  for (const events of [
    [], valid.slice(1), valid.slice(0, -1), [valid[0], valid[2]], [...valid].reverse(),
    mutate({ textOffset: -1 }), mutate({ textOffset: 0.5 }), mutate({ textOffset: 100 }),
    mutate({ wordLength: 0 }), mutate({ wordLength: 3 }), mutate({ text: "HELLO" }),
    mutate({ audioOffset: -1 }), mutate({ audioOffset: NaN }), mutate({ audioOffset: Infinity }),
    mutate({ audioOffset: 0.5 }), mutate({ audioOffset: 100000000 }),
    [valid[0], { ...valid[1], audioOffset: valid[0].audioOffset - 10000 }, valid[2]],
  ]) {
    const result = mapWordBoundaries(text, prepared, events, 2000);
    assert.ok(result.reason, JSON.stringify(events));
    assert.equal(result.words, undefined);
  }
  assert.ok(mapWordBoundaries(text, prepared, valid, NaN).reason);
  assert.ok(mapWordBoundaries(text, prepared, valid, 0).reason);
});

test("ambiguous replacement interiors and deleted words reject rather than invent alignments", () => {
  for (const [text, name, pronunciations, tokens] of [
    ["Hello HEXON!", "Two Names", {}, ["Hello", "Two", "Names"]],
    ["Hello HEXON!", "", {}, ["Hello"]],
    ["Hello Omarchy!", "Ollie", { Omarchy: "Oh maa chee" }, ["Hello", "Oh", "maa", "chee"]],
    ["Hello Omarchy!", "Ollie", { Omarchy: "" }, ["Hello"]],
    ["Hello!", "Ollie", {}, ["Hel", "lo"]],
  ] as [string, string, Record<string, string>, string[]][]) {
    const prepared = prepareSpeechWithOffsets(text, name, pronunciations);
    assert.ok(mapWordBoundaries(text, prepared, boundaries(prepared.text, tokens), 3000).reason);
  }
});

test("malformed boundaries and sidecars never split UTF-16 surrogate pairs", () => {
  const text = "A𐐀 B";
  const prepared = prepareSpeechWithOffsets(text, "Ollie", {});
  const events = boundaries(text, ["A\uD801", "\uDC00", "B"]);
  assert.ok(mapWordBoundaries(text, prepared, events, 2000).reason);
  const hash = sha256("audio");
  assert.equal(timingIsFresh({
    version: 1, text, audioHash: hash,
    words: [{ startMs: 0, endOffset: 2 }, { startMs: 100, endOffset: text.length }],
  }, hash, text), false);
});

test("freshness binds original wording and final MP3 hash, and rejects corrupt timing records", async () => {
  const directory = resolve("tests", `.speech-timing-${randomUUID()}`);
  await mkdir(directory);
  try {
    const output = resolve(directory, "clip.mp3");
    const hash = sha256("FINAL normalized mp3");
    const timing: SpeechTiming = {
      version: 1, audioHash: hash, text: "Hi HEXON.",
      words: [{ startMs: 100, endOffset: 2 }, { startMs: 500, endOffset: 9 }],
    };
    assert.equal(await timingFileIsFresh(output, hash, timing.text), false);
    await writeTiming(output, timing);
    assert.deepEqual(JSON.parse(await readFile(`${output}.timing.json`, "utf8")), timing);
    assert.equal(await timingFileIsFresh(output, hash, timing.text), true);
    assert.equal(await timingFileIsFresh(output, sha256("raw PCM"), timing.text), false);
    assert.equal(await timingFileIsFresh(output, undefined, timing.text), false);
    assert.equal(await timingFileIsFresh(output, hash, "Hi Ollie."), false);
    for (const invalid of [
      null, {}, { ...timing, version: 2 }, { ...timing, words: [] },
      { ...timing, words: [null] }, { ...timing, words: [{ startMs: 1, endOffset: 2 }] },
      { ...timing, words: [{ startMs: NaN, endOffset: 9 }] },
      { ...timing, words: [{ startMs: -1, endOffset: 9 }] },
      { ...timing, words: [{ startMs: 1, endOffset: 100 }] },
      { ...timing, words: [{ startMs: 1, endOffset: 9.1 }] },
      { ...timing, words: [{ startMs: 2, endOffset: 2 }, { startMs: 1, endOffset: 9 }] },
    ]) assert.equal(timingIsFresh(invalid, hash, timing.text), false);
    await writeFile(`${output}.timing.json`, "{broken");
    assert.equal(await timingFileIsFresh(output, hash, timing.text), false);
    await writeTiming(output);
    assert.equal(await timingFileIsFresh(output, hash, timing.text), false);
    assert.deepEqual(await readdir(directory), [], "no stale sidecars or staging files");
    await mkdir(`${output}.timing.json`);
    await assert.rejects(timingFileIsFresh(output, hash, timing.text), /EISDIR/);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("SDK accepts existing REST credential endpoint shapes using the synthesis websocket route", () => {
  for (const endpoint of [
    "https://westus.tts.speech.microsoft.com",
    "https://westus.tts.speech.microsoft.com/",
    "https://westus.tts.speech.microsoft.com/cognitiveservices/v1",
    "wss://westus.tts.speech.microsoft.com/tts/cognitiveservices/websocket/v1",
  ]) {
    assert.equal(speechWebSocketEndpoint(endpoint).href,
      "wss://westus.tts.speech.microsoft.com/tts/cognitiveservices/websocket/v1");
  }
  assert.throws(() => speechWebSocketEndpoint("http://example.com"), /HTTPS or WSS/);
});
