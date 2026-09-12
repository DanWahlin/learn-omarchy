# Character packs

Character packs let you add a new Learn Omarchy guide without changing the
application. A pack is a folder containing a validated `character.json` file
and PNG sprite sheets.

Packs are data, not plugins. They cannot run code, execute commands, alter
lessons, or access the network.

Use [Spark](../examples/characters/spark/) as the starter example.

## Quick start

From a Learn Omarchy repository checkout:

```bash
npm run packs:validate -- examples/characters/spark
CHARACTER_LAB_ROOT="$PWD/examples/characters" ./bin/hexon-lab spark
```

The first command validates the pack. The second opens it in the character lab
so you can inspect every pose, animation, direction, and optional introduction.

To install a copy for your user account:

```bash
pack_root="$(node --experimental-strip-types --input-type=module -e \
  'import { defaultUserPackRoot } from "./src/character-packs.ts"; console.log(defaultUserPackRoot())')"
(
  set -e
  mkdir -p "$pack_root"
  test ! -e "$pack_root/spark"
  cp -R examples/characters/spark "$pack_root/spark"
)
npm run packs:validate -- "$pack_root/spark"
```

The destination check prevents an existing pack from being overwritten. Restart
Learn Omarchy after installing or updating a pack. The character lab also has a
**Refresh** action.

## Pack structure

A basic pack looks like this:

```text
spark/
├── character.json
└── sprites/
    ├── spark-idle.png
    ├── spark-talk.png
    ├── spark-point.png
    └── spark-point-up.png
```

An optional introduction adds:

```text
spark/
└── intro/
    └── sequence.json
```

The directory name and manifest `id` must match. IDs:

- Start with a lowercase letter
- Use lowercase letters, numbers, and single hyphens
- Contain at most 64 characters
- Stay unchanged after publication

Saved guide preferences use the ID, not the display name.

## Manifest overview

`character.json` uses format version 1:

```json
{
  "formatVersion": 1,
  "id": "spark",
  "displayName": "Spark",
  "description": "A geometric lantern guide.",
  "author": {
    "name": "Your name",
    "status": "declared"
  },
  "license": {
    "identifier": "CC0-1.0",
    "status": "declared"
  },
  "preview": {
    "sprite": "idle",
    "frame": 0
  },
  "sprites": {},
  "renderer": {},
  "effects": {
    "thrusters": false
  },
  "motion": {
    "tourFlight": "upright"
  },
  "narration": {
    "mode": "silent"
  }
}
```

The complete working manifest is
[`examples/characters/spark/character.json`](../examples/characters/spark/character.json).
Copy it and replace one section at a time.

### Identity and attribution

| Field | Purpose |
|---|---|
| `id` | Stable machine-readable identifier |
| `displayName` | Name shown in the interface |
| `spokenName` | Optional shorter name used during narration generation |
| `description` | Concise description shown to learners |
| `author` | Creator name and declaration status |
| `license` | Artwork license and declaration status |

`author.status` and `license.status` can be `declared` or `unresolved`. An
unresolved value is allowed for private local testing, but it is not permission
to redistribute artwork. Published packs need accurate attribution and a
license that permits redistribution.

## Artwork requirements

All referenced character and introduction artwork must be PNG. Sprite sheets
use horizontal frames:

```text
image width = frameWidth × frames
image height = frameHeight
```

Required sprite roles:

| Role | Purpose |
|---|---|
| `idle` | Resting pose and chooser preview |
| `talk` | Speech animation source |
| `point` | Sideways pointing pose |
| `point-up` | Upward pointing pose |

Optional roles:

| Role | Purpose |
|---|---|
| `flight` | Custom travel animation |
| `point-blink` | Blink replacement for `point` |
| `point-up-blink` | Blink replacement for `point-up` |
| `speech` | Small speech patch used instead of the full `talk` frame |

Every pose except a small `speech` patch is 192 pixels high. Frames can have
different widths, but `talk.frameWidth` must match `idle.frameWidth`.

A one-frame sprite needs no timing. Multi-frame sprites use either `fps`:

```json
{
  "path": "sprites/spark-idle.png",
  "frameWidth": 224,
  "frameHeight": 192,
  "frames": 8,
  "fps": 8
}
```

Or a timeline:

```json
{
  "path": "sprites/spark-idle.png",
  "frameWidth": 224,
  "frameHeight": 192,
  "frames": 4,
  "timeline": [
    { "frame": 0, "durationMs": 3000 },
    { "frame": 1, "durationMs": 50 },
    { "frame": 2, "durationMs": 100 },
    { "frame": 3, "durationMs": 50 }
  ]
}
```

Do not set both `fps` and `timeline`.

## Register poses to one canvas

Format version 1 renders every guide in a 224 by 192 canvas. Registration keeps
the body from jumping when its pose changes.

The renderer defines a shared baseline and horizontal body anchor:

```json
{
  "canvas": { "width": 224, "height": 192 },
  "baseline": 176,
  "bodyAnchorX": 112,
  "poses": {}
}
```

Each non-flight pose supplies the source image's baseline and body anchor,
plus a scale and offset:

```text
source baseline × scale + offset.y = renderer baseline
source bodyAnchorX × scale + offset.x = renderer bodyAnchorX
```

Pointing poses also provide `tip`, the fingertip location in the source frame.
The application transforms it with the rest of the pose so highlights and
guide placement remain accurate.

Start with full-canvas 224 by 192 artwork, as Spark does, whenever possible.
That makes each pose use scale `1`, offset `{ "x": 0, "y": 0 }`, and the same
anchors.

## Movement and effects

`motion.tourFlight` controls travel:

- `upright` keeps the regular guide pose while moving.
- `sprite` uses the `flight` sprite and requires a registered flight pose.

`effects.thrusters` enables the application's travel thruster effect. Set it to
`false` for guides that fly using wings or another visual style.

Optional blink timing applies to the `point-blink` and `point-up-blink` roles:

```json
{
  "blink": {
    "periodMs": 3200,
    "startMs": 3050,
    "durationMs": 100
  }
}
```

## Narration

Choose one narration policy:

```json
{ "mode": "silent" }
```

Displays captions without recorded speech. This is the simplest choice for a
community pack.

```json
{ "mode": "borrowed", "audioSet": "ohm-1" }
```

Uses the bundled `ohm-1` or `owl` narration set. Lines that identify the
original guide are intentionally shown as text instead of playing mismatched
audio.

```json
{
  "mode": "own",
  "audioSet": "your-pack-id",
  "playbackRate": 1
}
```

Own narration is intended for bundled contributions whose matching audio set
is added through the repository's trusted narration workflow. A user pack
cannot download or execute an audio generator.

## Optional introduction

Add an intro reference to the manifest:

```json
{
  "intro": {
    "sequence": "intro/sequence.json"
  }
}
```

Introductions are bounded JSON choreography. They can animate the guide,
trusted PNG scenery, text, fixed effects, and allowlisted sounds. They cannot
run scripts or affect lesson progress.

See [Character introductions](character-intros.md) for the format. A missing or
invalid intro does not reject an otherwise valid pack. Learn Omarchy uses a
short static entrance and reports the intro diagnostic.

## Validate and preview

Run these checks while authoring:

```bash
npm run packs:validate -- /path/to/your-pack
CHARACTER_LAB_ROOT=/path/to/characters ./bin/hexon-lab your-pack-id
```

Before proposing a bundled guide:

```bash
npm run packs:validate -- assets/characters/your-pack-id
npm run check
npm test
npm run test:ui
```

In the lab, verify:

- Idle and talking animation
- Pointing tips in both directions
- Upward pointing
- Flight and effects
- Speech patches and blink timing
- Introduction playback, skipping, and reduced motion

## Install, update, and remove

User packs live under:

```text
${XDG_DATA_HOME:-$HOME/.local/share}/learn-omarchy/characters/<id>/
```

`XDG_DATA_HOME` must be an absolute path. Packs need no catalog or index.

To update a pack safely:

1. Validate the new version in a staging directory.
2. Close Learn Omarchy.
3. Move the installed pack outside the `characters/` directory as a backup.
4. Copy the replacement into a new directory with the same ID.
5. Validate the installed copy and restart Learn Omarchy.

Do not merge a replacement over an existing directory. Old files can remain
and make the installed pack differ from the version you tested.

To remove a user pack, close Learn Omarchy and move that pack's directory out
of the discovery root. If it was selected, the application reports that it is
unavailable and chooses a valid fallback.

## Safety limits

Validation enforces path containment, file type, dimensions, decoded image
size, total files, and total bytes. Key limits include:

- 64 referenced runtime files
- 128 MiB of referenced runtime data
- 16 MiB per PNG
- 32 million decoded pixels across the pack
- 256 filesystem entries
- 64 discovered user-pack directories

Only JSON and PNG runtime files are accepted. Executable files, QML,
JavaScript, shell files, URLs, absolute paths, escaping symlinks, and unsafe
relative paths are rejected.

Authoring files and scripts should stay outside the installed pack. Never run a
stranger's build script or `sprites.conf` to try a guide. Inspect and validate
the finished JSON and PNG files instead.

## Publish or contribute a guide

Before sharing a pack:

- Use a unique, stable ID.
- Include accurate author and license declarations.
- Share only the manifest and referenced runtime assets.
- Validate the final directory you plan to distribute.
- Test every pose and the optional introduction.

Bundled guides also need an entry in `assets/characters/index.json` and a pull
request that includes the full automated test results. A bundled contribution
must use the existing data contract without guide-specific branches in the
application.

Ohm-1 and Ollie are original Learn Omarchy artwork licensed under CC BY 4.0.
Their license does not apply to new artwork. Spark's geometric example artwork
is CC0-1.0 and can be replaced with properly licensed artwork of your own.

See [LICENSE-ASSETS.md](../LICENSE-ASSETS.md) for project asset licensing.
