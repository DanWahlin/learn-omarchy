# Narration files

The validator allows safe relative paths and rejects paths that contain `..`,
so keep audio under the course directory:

```text
courses/
  omarchy-basics.json
  audio/
    ohm-1/open-apps.mp3
    owl/open-apps.mp3
    production-manifest.json
```

```json
"audio": "audio/open-apps.mp3"
```

The course names the file without a coach; the app inserts the selected
coach's id as a directory, since each coach records its own narration.

The bundled narration and production tools use **24 kHz, mono, 96 kbps MP3**.
The player can also play Ogg, FLAC, and WAV, but the production pipeline requires
MP3 output paths.

## Local normalization

```bash
npm run audio:normalize
# Equivalent, including support for another narration directory:
node --experimental-strip-types tools/normalize-course-audio.ts courses/audio
```

This command is entirely local and requires `ffmpeg` (with `libmp3lame`) and
`ffprobe`. It does not contact a speech service. Avoid running it concurrently
with another production command against the same audio directory.

`tools/audio-production.ts` provides the shared generation/normalization
pipeline:

- Measure the complete decoded source with EBU R128 `loudnorm`.
- Target **-20 LUFS integrated** and a **-1 dBTP encoded-output ceiling**.
  The filter uses -1.5 dBTP to leave 0.5 dB of MP3 codec safety margin.
- Use measured two-pass normalization for clips at least three seconds long.
  FFmpeg uses linear normalization when feasible and falls back to dynamic
  normalization when the measured peak/range requires it.
- For shorter speech, use measured static gain capped by the peak ceiling.
  Short utterances do not have stable long-term gated loudness; preserving the
  speech envelope and peak headroom takes priority over forcing an exact LUFS
  value. Silent/unmeasurable input is rejected.
- Preserve silence, timing and channel layout; **no silence trimming** is done.
- Encode once to a staging file beside the destination, verify MP3/24 kHz/mono,
  check duration within 150 ms, fully decode and measure the encoded output,
  and reject peaks above -1 dBTP before atomically replacing the destination.
  A synthesis/encoding/validation failure leaves that destination unchanged.

Each successful clip is recorded in `courses/audio/production-manifest.json`.
The sidecar contains source/output SHA-256 hashes, before/after loudness and
true-peak measurements, output duration/format, method, FFmpeg version, export
options and a deterministic normalization fingerprint. The manifest is also
written through an atomic rename after each clip. Audio and manifest are not a
single filesystem transaction: an interruption between their writes leaves a
detectable hash mismatch rather than a false freshness claim.

Re-running with unchanged output hashes, options and FFmpeg version skips
already normalized files without another lossy encode. If you intentionally
change the processing settings, prefer original masters or fresh synthesis:
reprocessing an existing MP3 adds another lossy generation. Original masters
are not stored by this tool. Hashes/options document the input and procedure;
bit-identical reproduction also requires the same source bytes and toolchain.

### Initial normalization baseline

The original **206 clips** (103 matching filenames per coach, **1,101.552 seconds** total)
were locally normalized once and every encoded output was fully decoded and
probed. No external speech generation was performed. All are 24 kHz mono MP3.
These figures describe that initial batch, not later curriculum revisions.
The production manifest contains the current measurements and provenance for
each clip, including subsequently regenerated narration.

| Measurement | HEXON | OLLIE |
| --- | ---: | ---: |
| Mean source integrated loudness | -23.153 LUFS | -20.267 LUFS |
| Mean encoded integrated loudness | -20.631 LUFS | -20.443 LUFS |
| Encoded integrated loudness range | -21.76 to -20.22 LUFS | -20.52 to -20.32 LUFS |
| Highest encoded true peak | -1.85 dBTP | -1.94 dBTP |
| Short-speech static-gain clips | 14 | 5 |

Means are per-clip arithmetic means, not a concatenated-program measurement.
195 clips landed within 1 LU of the target; the other 11 are between -21.05
and -21.76 LUFS. These short/peak-limited narration results were retained rather
than repeatedly encoding or aggressively compressing them to chase a number.
For example, `ohm-1/tour-welcome.mp3` changed from -24.10 to -21.21 LUFS
(-1.94 dBTP output), while `owl/tour-welcome.mp3` changed from -20.33 to
-20.44 LUFS (-5.19 dBTP output).

The inherited recordings' original text, voices, pronunciation and backend
cannot be proven from the MP3 bytes. Their provenance is explicitly
`{"kind":"inherited","sourceProvenance":"unknown"}`; no current course-text
fingerprints have been invented for them.

## Speech generation and freshness

`npm run audio:check` audits every instruction, completion, lesson wrap-up, and host-welcome
recording required by the bundled packs. It fails on missing files, unverified
wording, changed speech or voices, mismatched file hashes, and outdated production
settings. It runs offline and is included in `npm run check`.

Historical pack IDs and display-name spellings do not themselves invalidate a
recording: the check compares the prepared spoken text, including `spokenName`
and the expected `Omaachi` pronunciation. An inherited recording without text
provenance must be regenerated before it counts as release-ready.

Generation resolves the same validated character packs as the app and lab.
Only packs with `narration.mode: "own"` need generation; backend voice choices
come from `narration.voices.azure` and `narration.voices.edge`, with the explicit
environment override still taking precedence.

Name substitution uses the pack's optional `spokenName`, falling back to
`displayName`. This lets `Ohm-1` appear on screen while the voice says `Ohm`.
The prepared-text fingerprint tracks pronunciation changes; a display-only
rename doesn't require replacing audio that already says the correct name.

Graphics-only packs can borrow an official audio set or remain silent, without
credentials or new recordings. Borrowed clips that introduce the source coach
by name are omitted instead of introducing the wrong character. The selected
pack's visible text and normal reading-time fallback remain available.
See [the pack format](../docs/character-packs.md) for the complete policy.

```bash
npm run audio:generate -- --character ohm-1 --backend edge --missing
npm run audio:generate -- --character owl --backend azure --match Omarchy
npm run audio:generate -- --backend azure --steps tour-welcome,launch-browser
```

The host's center-screen greeting is separate from lesson narration and is
defined in `courses/welcome.json`. Add `--welcome` to include that greeting:

```bash
npm run audio:generate -- --backend azure --steps tour-welcome --welcome
```

This updates only the host greeting and tour opening for each selected coach.
The greeting introduces the coach; the tour opening introduces the features
without repeating the coach's name. Both use the configured pronunciation map.

Each taught lesson's `wrapUp` contains its completion `text` and `audio` path.
Course-level `wrapUp.assisted` and `wrapUp.explored` provide alternatives for
guided work and skipped or unfinished activities. The app uses the same selected
message for the completion panel and narration, starting after the coach arrives.
Welcome uses its existing menu handoff instead.

Generate only these wrap-up recordings, without replacing activity narration:

```bash
npm run audio:generate -- --backend azure --wrapups-only
```

**Generation contacts the selected speech service; Azure may incur charges.**

### Welcome word timing pilot

The current Andrew and Ada Dragon HD voices both returned usable word boundaries
for the welcome pilot. Generate the welcome audio and timings in the same SDK
synthesis run:

```bash
npm run audio:generate -- --backend azure --welcome --steps tour-welcome --part completion --word-timings
```

This selects the greeting, toolbar overview, and lesson-menu invitation without
regenerating activity clips. Each timing sidecar is named `<clip>.mp3.timing.json`
and contains the final MP3's SHA-256, original source text, and word timestamps.
The runtime rejects stale or mismatched metadata rather than estimating speech
timing. Audio without usable boundaries still plays with its full text visible.
Generating a clip without timing removes its old sidecar.

The app follows mpv's actual media position, not elapsed wall-clock time, and
keeps the caption's full layout while revealing words. Muted welcome captions
reveal at the configured reading pace instead. Reduced motion or turning off
**Type text** shows the full caption immediately. This feature needs no Azure
connection or Speech SDK on the learner's machine; the timestamps are bundled
with the recordings.
Unlike local normalization, `--missing` means *missing or stale*, not just
“a filename does not exist.” Inherited files with unknown provenance are stale,
so the first generation with `--missing` will regenerate selected inherited
clips. Use `--character`, `--match`, or `--steps` to bound that operation.
`--steps` selects exact comma-separated activity IDs and regenerates their
instruction/completion clips for the selected coaches. Unknown or empty IDs
are rejected before contacting the speech service.
Use `--part instruction` or `--part completion` when editing only one side of
an activity; the default `both` retains the existing behavior. This avoids
regenerating unchanged recordings during an editorial pass.

Generation records a deterministic fingerprint of the original text hash,
prepared speech hash, character ID/display name, selected voice/backend,
pronunciation map, preparation version, synthesis options and production
options. `--missing` only skips when this fingerprint, the normalization
fingerprint and the current output hash all match. Changed text, pronunciation,
voice, backend, options or damaged/replaced files therefore trigger generation.
Malformed manifests and non-missing filesystem errors are reported, not
silently treated as defaults.

Both Edge and Azure receive the **same prepared spoken text**: replace `HEXON`
with the selected coach's display name, then apply whole-word pronunciation
substitutions. `Omarchy` defaults to `Omaachi`, overridden by
`LEARN_OMARCHY_PRONUNCIATION`. Only Azure's transport then XML-escapes the
prepared text for SSML; display text is unchanged. Generated audio is staged
and sent through the same local normalization/verification pipeline before
publication. Credentials and speech text are not stored in the manifest.

## Playback judgment

The two existing rocket effects are retained unchanged. Narration loudness
normalization is not a substitute for listening to the final application mix:
judge both coaches, short confirmations and rocket effects on real speakers
and headphones using the runtime levels. No new effects or sound design are
introduced here, and no listening/UI assessment is claimed.
