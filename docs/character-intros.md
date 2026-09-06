# Data-only character intros

An optional character-pack intro points to a version-1 JSON sequence. The sequence describes scenery and character choreography; the application owns execution, character rendering, tour destinations, audio/narration, and lesson progress. Omitting the intro deliberately produces a brief static character entrance.

The official examples are:

| Pack | Sequence | Duration | Choreography |
| --- | --- | --- | --- |
| HEXON | `assets/characters/hexon/intro/sequence.json` | 6,800 ms | Star field and prompt, landing pad, 1,600 ms descent with pixel exhaust, touchdown dust, hatch crossfade, character reveal/exit, 1,600 ms departure, scenery fade |
| OLLIE | `assets/characters/owl/intro/sequence.json` | 3,700 ms | Bottom-pivot tree growth, sway and fireflies, perch reveal, short takeoff, scenery fade |
| SPARK | `examples/characters/spark/intro/sequence.json` | 2,950 ms | Two independent decorative layers arriving in parallel, then character scale/slide/reveal |

The application has no character-ID, sprite-prefix, propulsion, rocket, or tree dispatch. The first two sequences reference the existing `sprites/hexon-intro.png`, `sprites/hexon-intro-open.png`, and `sprites/owl-intro.png` in their respective packs. These files are not duplicated. Their presence does not establish their license.

## Version 1 grammar

Unknown fields, unsupported types, invalid references, and non-finite numbers are errors. All times are milliseconds. The top-level object accepts only:

```json
{
  "version": 1,
  "character": { "visible": false },
  "layers": [],
  "steps": [
    { "type": "set", "target": "character", "to": { "visible": true } },
    { "type": "tween", "target": "character", "to": { "opacity": 1 }, "duration": 400, "easing": "outQuad" }
  ]
}
```

`character` is optional initial state. `layers` and `steps` are required arrays, which may be empty. No script, expression, callback, import, dynamic QML, shell command, or arbitrary object/property path is accepted.

### Bounds

* At most 24 layers, 256 total actions (including parallel groups and sound cues), 8 branches per parallel group, and 4 nested parallel levels.
* The longest joined timeline must not exceed 30,000 ms. `wait.duration` is 0–30,000; `tween.duration` is 1–30,000.
* Layer IDs match `[a-z][a-z0-9-]{0,39}`. They must be unique, must not equal `character`, and cannot use `constructor`, `prototype`, or `__proto__`.
* At most 16 images per image layer. Asset paths are 1–240 ASCII characters from letters, digits, `_`, `-`, `.`, and `/`; they are pack-relative, without empty, `.` or `..` path segments. Only `.png`, `.webp`, `.jpg`, `.jpeg`, and `.svg` image extensions are accepted. Absolute paths, URLs, percent-encoded paths, and backslashes are rejected. The pack loader must additionally enforce containment, existence, and its file-size policies.
* Text is at most 240 characters, without control characters other than tab/newline/carriage return. Braces may appear only in the literal placeholder `{displayName}`. The player replaces that exact placeholder with up to 80 display-name characters and always renders plain text, never rich text.

### Layers

Every layer requires `id` and `type` (`image`, `text`, or `effect`). Optional fields:

| Field | Meaning |
| --- | --- |
| `state` | Initial state using the property table below |
| `width`, `height` | Logical pixels (1–4,096), or a viewport size object |
| `aspect` | Optional width/height ratio, 0.05–20; otherwise images use their first image's native aspect |
| `anchorX`, `anchorY` | Fraction of the layer's own size to subtract from its position, 0–1 |
| `z` | Local scenery stacking order, -20–20 |
| `images` | Required for image layers only: list of pack-relative image paths |
| `effect` | Required for effect layers only: one fixed application primitive listed below |
| `count` | Integer particle/light count, 1–64 |
| `colors` | 1–4 hex colors or fixed theme tokens (below) |
| `background`, `border` | Optional text-panel/strip colors, each a hex color or fixed theme token |
| `period` | Decorative cycle length, 100–10,000 ms |
| `amplitude` | Decorative drift in logical pixels, 0–300 |
| `fontSize` | Text size, 8–64 logical pixels |
| `typewriter` | Boolean: reveal text at 34 ms/character with a 480 ms blinking cursor |

A viewport size has exactly `viewport`, `min`, `max`, and optional `axis`:

```json
{ "viewport": 0.5, "min": 360, "max": 700 }
```

The multiplier is 0.001–2; clamp bounds are 1–4,096 with `min <= max`. By default width uses viewport width and height uses viewport height. `axis: "width"` or `"height"` explicitly changes that choice, useful for decorative elements sized to match a height-based image. An omitted image height uses its native height, and an omitted width follows its aspect. Other omitted dimensions default to 100 pixels. Image frames share one layer box and are stretched into it. Use same-sized artwork or explicit dimensions if switching frames.

All layer transforms use a bottom-center pivot. Attachments refer to **nominal, untransformed** boxes, not rotated/scaled edges. Reveal a character after growth finishes if it must sit on an exact perch.

Colors accept only `#RRGGBB`, Qt `#AARRGGBB`, or one of these exact tokens: `theme:accent`, `theme:instruction`, `theme:foreground`, `theme:background`, `theme:muted`, `theme:urgent`. Tokens are fixed lookups, not expressions or arbitrary property paths. Text panels default to theme background/accent; strips default to theme background/muted. Their backgrounds retain the original 0.82/0.95 alpha. Official scenery explicitly uses theme tokens; third-party artwork may choose literal colors.

### State and targets

An action's `target` is exactly `character` or a declared layer ID. The production character's nominal canvas is 224×192; the player never draws a separate character renderer.

| Property | Accepted values |
| --- | --- |
| `x`, `y` | Viewport-relative number -2–3, or typed layer attachment |
| `offsetX`, `offsetY` | Logical pixels, -4,096–4,096 |
| `opacity` | 0–1 |
| `scale` | 0.01–8; bottom-center pivot |
| `rotation` | -360–360 degrees |
| `visible` | Boolean |
| `pose` | Character only: `idle`, `point`, `point-up` |
| `facing` | Character only: `1` or `-1` |
| `flying` | Character only: Boolean |
| `text` | Text layers only: bounded plain text |
| `frame` | Image layers only: zero-based integer indexing that layer's `images` |
| `progress` | 0–1, used by the `burst` primitive |

Defaults: scenery x/y and offsets 0, visible true; character x 0.5, y 0.75, offsets -112/-192, visible false; all opacity/scale 1, rotation/progress/frame 0; character idle, facing 1, flying false; empty text.

An attachment has exactly `layer`, `anchor`, and optional `offset`:

```json
{ "layer": "canopy", "anchor": 0.84, "offset": -112 }
```

For x this means the referenced layer's nominal left plus `anchor * width + offset`; for y it means top plus `anchor * height + offset`. Anchor is 0–1 and offset is -4,096–4,096 pixels. The state's `offsetX/Y` is added separately, then the layer's own `anchorX/Y` is subtracted. The character has no own anchor subtraction. Unknown/self references, references to `character`, and cycles across any initial/action attachments are rejected.

Coordinates are resolved every frame against the current viewport and current attached layer layout. Tweening between viewport coordinates and attachments interpolates resolved positions; there are no math strings.

### Steps

Only these action shapes are accepted:

```json
{ "type": "sound", "cue": "rocket-land.opus" }
```

Sound is a zero-duration request for an explicitly allowlisted application-owned effect. Version 1 accepts only `rocket-land.opus` and `rocket-liftoff.opus`. These names are opaque built-in asset keys, not paths supplied to a shell. They do not imply any scene behavior: the pack must place each cue in its own steps. The host maps them to the existing `assets/sounds` files. No binaries are duplicated; these built-ins are not returned by `introAssetPaths()`.

```json
{ "type": "wait", "duration": 200 }
```

```json
{ "type": "set", "target": "character", "to": { "visible": true, "pose": "idle" } }
```

```json
{ "type": "tween", "target": "character", "to": { "offsetX": -112, "opacity": 1 }, "duration": 600, "easing": "inOutSine" }
```

```json
{
  "type": "parallel",
  "branches": [
    [{ "type": "tween", "target": "character", "to": { "opacity": 1 }, "duration": 300 }],
    [{ "type": "wait", "duration": 500 }]
  ]
}
```

Steps are sequential; branches begin together and join once after the longest branch. Different branches of a parallel group may not write the same target/property, even if their individual write intervals would not overlap. Within a branch, repeated writes are allowed. A tween may change only `x`, `y`, `offsetX`, `offsetY`, `opacity`, `scale`, `rotation`, and `progress`; other properties require `set`.

Allowed easing names: `linear` (default), `inQuad`, `outQuad`, `inOutSine`, `outCubic`, `outBack`. `outBack` deliberately overshoots the declared endpoints during interpolation.

### Fixed effects

Effects are explicitly selected by data, never inferred from IDs or character metadata:

* `specks`: deterministically placed pixel lights with periodic opacity and vertical drift. Zero amplitude makes a star field; nonzero amplitude makes drifting lights.
* `plume`: stacked pixel columns, using up to three colors and periodic scale pulsing.
* `burst`: outward pixel scatter driven by `progress`; its visibility naturally decays across 0–1.
* `strip`: bordered dark strip with alternating blinking edge lights.

The same single player clock drives all effects. They have no private timers, infinite animation objects, or pack-provided shaders. Cancelling or completing removes all scenery and stops the clock.

## Player and host contract

`app/IntroPlayer.qml` accepts `sequence` (validated object or null), `assetRoot` (local file URL of the pack directory), `displayName`, `reducedMotion`, and optional `palette`. Palette keys are `accent`, `instruction`, `foreground`, `background`, `muted`, and `urgent`; the main app passes its existing theme colors. QColor values and hex strings are accepted, with missing/invalid entries falling back to the player's default palette. Palette updates are live and do not restart playback. It revalidates sequences even if its caller already validated. `IntroTimeline.js` is the shared trusted grammar, compiler, and sampler. `src/intro-sequence.ts` exposes `validateIntroSequence(value): string[]` and `introAssetPaths(value): string[]`; the Node adapter evaluates only that checked-in application module, never pack text.

* `play()` starts or restarts playback. `cancel()` stops it and hides the character; `reset()` also clears a completed handoff.
* `running` includes asset preloading and brief fallback presentation.
* `characterX/Y` are the nominal 224×192 body canvas top-left. Other outputs are `characterScale`, `characterOpacity`, `characterVisible`, `characterPose`, `characterFacing`, `characterFlying`, and `characterRotation`. `handoff` exposes the final state.
* The host binds its existing `CharacterSprite` to these outputs. A 240×260 coach container whose body starts at (8,68) subtracts those offsets from characterX/Y and keeps its bottom-center transform pivot.
* Successful playback emits `finished()` exactly once, after all branches join. It removes scenery but retains the last character placement. The host then flies from that position to its application-owned tour target and starts narration only after settling.
* Optional/missing intros and reduced motion reveal a static character and finish after about 250 ms (one timer-frame rounding, below 400 ms under normal scheduling). No decorative assets are loaded in reduced motion.
* Invalid data and missing/unloadable assets emit `diagnostic(message)`, show the same brief static entrance, then emit `failed(message)` **instead of** `finished()`. Asset preload timeout is two seconds. Hosts treat finished/failed as alternative terminal signals and guard their own continuation once.
* Cancelling an active run emits `cancelled()` once, never `finished()`. Changing sequence or asset root cancels safely, including during loading. Image callbacks carry generation tokens; stale callbacks cannot move a new character or complete a later run.
* `soundRequested(string path)` emits each declared built-in key once when its timeline position is reached. The host must allowlist the key again, resolve the existing application asset, and stop active intro sound on cancellation/reset. No sound cues run during reduced-motion/static fallback. Generation guards also handle a sound listener cancelling or replacing the sequence synchronously.

Sequences cannot advance lessons, select tour coordinates, or trigger narration. Global sound playback stays with the host. HEXON explicitly requests the existing landing effect at 0 ms and liftoff effect at 4,400 ms, preserving the original ship sound timing.

## Verification and visual acceptance

Run the focused tests:

```sh
node --experimental-strip-types --test tests/intro-sequence.test.ts
QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_CONTROLS_STYLE=Basic \
  QML_XHR_ALLOW_FILE_READ=1 /usr/lib/qt6/bin/qmltestrunner -input tests/qml/tst_intro.qml
```

Tests cover the shared grammar, bounds, local asset discovery, sequential/parallel sampling, completion/cancellation/restart/switch, stale callbacks, asset failures, optional/reduced entrances, viewport attachments, and all three data-driven sequences.

Migration preserves the source scene's meaningful art, height clamps, native image proportions, layering, terminal prompt, landing/reveal/departure phases, and decorative effect types. Star positions are now deterministic; official scenery retains live theme colors through explicit pack tokens and the host palette. Effects are generic approximations, not pixel-identical simulations. OLLIE performs a short local takeoff before the host's destination flight, and the host begins destination flight only after the sequence finishes. Automated timing/geometry checks and offscreen rendering do not establish pixel parity or real desktop visual acceptance.

During migration, isolated 1920×1080 captures using the production `CharacterSprite` were reviewed for HEXON's hatch reveal and ground exit, OLLIE's perch reveal, and SPARK's independent composition. Those checks confirmed the intended visible art and character placement on a flat background; they did not compare against recorded legacy frames or exercise compositor-specific tour flight.
