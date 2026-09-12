# Character introductions

A character pack can include an optional animated introduction. The sequence is
JSON data interpreted by Learn Omarchy. It can animate the guide, PNG scenery,
plain text, fixed visual effects, and a small set of built-in sounds.

It cannot run code, load remote content, execute commands, control lessons, or
replace the application's guide renderer.

If an intro is missing or invalid, the guide remains usable and receives a
short static entrance.

Use [Spark's sequence](../examples/characters/spark/intro/sequence.json) as the
smallest complete example.

## Connect an intro to a pack

Add this to `character.json`:

```json
{
  "intro": {
    "sequence": "intro/sequence.json"
  }
}
```

Then validate and preview the complete pack:

```bash
npm run packs:validate -- /path/to/your-pack
CHARACTER_LAB_ROOT=/path/to/characters ./bin/hexon-lab your-pack-id
```

Validation checks the sequence and every referenced image. Intro errors are
reported as warnings so the rest of the character pack can still load.

## Sequence structure

Format version 1 has four top-level fields:

```json
{
  "version": 1,
  "character": {
    "visible": false,
    "opacity": 0
  },
  "layers": [],
  "steps": [
    {
      "type": "set",
      "target": "character",
      "to": {
        "visible": true
      }
    },
    {
      "type": "tween",
      "target": "character",
      "to": {
        "opacity": 1
      },
      "duration": 400,
      "easing": "outQuad"
    }
  ]
}
```

| Field | Purpose |
|---|---|
| `version` | Must be `1` |
| `character` | Optional initial guide state |
| `layers` | Scenery, text, and fixed effects |
| `steps` | Sequential animation actions |

Unknown fields are rejected instead of being ignored.

## Layers

Every layer needs a unique safe `id` and one of these types:

| Type | Required field | Purpose |
|---|---|---|
| `image` | `images` | One or more pack-relative PNG files |
| `text` | None | Bounded plain text |
| `effect` | `effect` | A built-in visual primitive |

Example image layer:

```json
{
  "id": "ship",
  "type": "image",
  "images": [
    "sprites/ship-closed.png",
    "sprites/ship-open.png"
  ],
  "width": 360,
  "height": 220,
  "anchorX": 0.5,
  "anchorY": 1,
  "z": -1,
  "state": {
    "x": 0.5,
    "y": 0.8,
    "opacity": 0
  }
}
```

All intro images must be PNG and must remain inside the pack directory. Up to
16 images can share one layer. Change the displayed image with the layer's
zero-based `frame` state.

Common optional layer fields:

| Field | Purpose |
|---|---|
| `state` | Initial position, transform, visibility, text, frame, or progress |
| `width`, `height` | Logical pixels or responsive viewport sizing |
| `aspect` | Width-to-height ratio |
| `anchorX`, `anchorY` | Layer pivot from `0` to `1` |
| `z` | Scenery stacking order from `-20` to `20` |
| `fontSize` | Text size from `8` to `64` |
| `typewriter` | Reveals text with a cursor |

Responsive width or height uses a viewport multiplier with clamps:

```json
{
  "viewport": 0.5,
  "min": 360,
  "max": 700,
  "axis": "width"
}
```

## Position and state

Numeric `x` and `y` values are viewport-relative. `0.5` is the center and `1`
is the far edge. Values from `-2` to `3` allow entrances and exits beyond the
visible viewport.

Use `offsetX` and `offsetY` for logical-pixel adjustments.

The guide supports:

- `x`, `y`, `offsetX`, `offsetY`
- `opacity`, `scale`, `rotation`, `visible`
- `pose`: `idle`, `point`, or `point-up`
- `facing`: `1` or `-1`
- `flying`: `true` or `false`

Layers support the transform and visibility properties plus:

- `text` for text layers
- `frame` for image layers
- `progress` for the `burst` effect

### Attach one element to another

Instead of a numeric position, `x` or `y` can follow another layer:

```json
{
  "layer": "tree",
  "anchor": 0.84,
  "offset": -112
}
```

This positions the target from the referenced layer's untransformed box.
References must point to a different scenery layer. Self-references, character
references, unknown layers, and cycles are rejected.

## Actions

Steps run in order. Four action types control the sequence.

### Set

Changes state immediately:

```json
{
  "type": "set",
  "target": "character",
  "to": {
    "visible": true,
    "pose": "idle"
  }
}
```

### Tween

Animates numeric state:

```json
{
  "type": "tween",
  "target": "character",
  "to": {
    "opacity": 1,
    "offsetY": -192
  },
  "duration": 600,
  "easing": "inOutSine"
}
```

Tweenable properties are `x`, `y`, `offsetX`, `offsetY`, `opacity`, `scale`,
`rotation`, and `progress`. Use `set` for all other properties.

Supported easing values:

- `linear`
- `inQuad`
- `outQuad`
- `inOutSine`
- `outCubic`
- `outBack`

### Wait

Pauses the timeline:

```json
{ "type": "wait", "duration": 300 }
```

### Parallel

Starts multiple branches together and waits for the longest:

```json
{
  "type": "parallel",
  "branches": [
    [
      {
        "type": "tween",
        "target": "character",
        "to": { "opacity": 1 },
        "duration": 300
      }
    ],
    [
      {
        "type": "tween",
        "target": "greeting",
        "to": { "opacity": 1 },
        "duration": 500
      }
    ]
  ]
}
```

Parallel branches cannot write the same property on the same target.

## Text and theme colors

Text is always rendered as plain text. Use `{displayName}` to insert the guide's
display name:

```json
{
  "id": "greeting",
  "type": "text",
  "fontSize": 20,
  "typewriter": true,
  "state": {
    "text": "> HELLO, {displayName}!"
  }
}
```

Colors can be `#RRGGBB`, Qt `#AARRGGBB`, or one of:

- `theme:accent`
- `theme:instruction`
- `theme:foreground`
- `theme:background`
- `theme:muted`
- `theme:urgent`

Theme tokens help an intro remain readable across Omarchy themes.

## Built-in effects

Effect layers use one of four fixed primitives:

| Effect | Purpose |
|---|---|
| `specks` | Static stars or drifting lights |
| `plume` | Pulsing stacked pixel columns |
| `burst` | Outward particles driven by `progress` |
| `strip` | Bordered strip with blinking edge lights |

Effects can use `count`, one to four `colors`, `period`, and `amplitude` where
appropriate. They are deterministic, bounded, and removed when the intro ends.

## Built-in sounds

The only supported sound cues are:

- `rocket-land.opus`
- `rocket-liftoff.opus`
- `birds-welcome.opus`

Request a cue with:

```json
{ "type": "sound", "cue": "birds-welcome.opus" }
```

These names select application-owned sounds. They are not file paths and cannot
be replaced by pack content. Muting, disabling effects, reduced motion, or
cancelling the intro stops or suppresses them.

## Limits and safety

Version 1 limits sequences to:

- 24 layers
- 256 total actions
- 8 branches in a parallel action
- 4 nested parallel levels
- A 30-second longest timeline
- 240 characters per text value
- 64 KiB for `sequence.json`

Asset paths must be safe pack-relative PNG paths. URLs, absolute paths,
backslashes, empty segments, `.` segments, `..` segments, percent escapes,
query strings, and fragments are rejected.

The sequence format accepts no scripts, expressions, callbacks, imports, QML,
shell commands, shaders, or arbitrary property paths.

## Preview and verify

Use the character lab to check:

- Normal and reduced-motion entrances
- Different viewport sizes
- Layer order and responsive sizing
- Guide placement and pose changes
- Intro cancellation, skipping, and replay
- Missing or invalid asset fallback
- Theme readability

Run the focused automated tests:

```bash
node --experimental-strip-types --test tests/intro-sequence.test.ts
QT_QPA_PLATFORM=offscreen \
QT_QPA_PLATFORMTHEME=generic \
QT_QUICK_CONTROLS_STYLE=Basic \
QML_XHR_ALLOW_FILE_READ=1 \
  /usr/lib/qt6/bin/qmltestrunner -input tests/qml/tst_intro.qml
```

An intro ends by handing the guide's final position to the application. Learn
Omarchy then moves the guide into its normal welcome flow. Sequences do not
select lessons, advance progress, or control narration.
