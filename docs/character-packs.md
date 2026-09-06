# Data-only character packs

A pack is a directory containing `character.json` and PNG assets. Characters are
discovered by data, not by adding a renderer branch or a compiled-in ID. The tour,
chooser and character lab use the same resolver:

```sh
npm run packs:list
npm run packs:validate -- examples/characters/spark
node --experimental-strip-types tools/character-packs.ts discover \
  --bundled-root assets/characters --user-root examples/characters
```

`discover` writes JSON only, with `version`, `packs`, `diagnostics`, `fallbackId`
and `invalidBundledIds`. Every resolved pack includes its stable `id`, absolute
real filesystem `root`, directory `assetUrl` (a file URL without a trailing slash),
validated `manifest`, validated `intro` or `null`, `runtimeFiles`, and diagnostics.
`validate PATH` reports errors with a nonzero exit status. Missing or invalid
optional intros produce warnings, not a failed graphic pack.
`check-bundled [--bundled-root PATH]` prints human-readable diagnostics and
fails when a bundled pack/catalog is invalid or no valid packs remain.
Unresolved licensing and optional-intro warnings alone are nonfatal. This
command never scans user packs and is suitable for developer/package checks.

## Install and discover

Bundled IDs are reserved by `assets/characters/index.json`:

```json
{ "formatVersion": 1, "characters": [{ "id": "hexon" }, { "id": "owl" }] }
```

The manifests, not catalog display text, are authoritative. User packs live at
`${XDG_DATA_HOME:-$HOME/.local/share}/learn-omarchy/characters/<id>/character.json`.
Only absolute `XDG_DATA_HOME` values are honored; relative or empty values use
an absolute `HOME`, falling back to the operating-system home directory.
The shared `defaultUserPackRoot(env = process.env)` export implements this
policy, and the CLI uses it whenever `--user-root` is not explicitly supplied.
They need **no user index**. IDs start with a lowercase letter and contain lowercase
letters, digits, and single hyphens between segments (maximum 64 characters).
The manifest ID must equal its directory name. Keep it stable after publishing:
saved preferences refer to the ID, not a display name or list position.

Discovery sorts IDs, skips invalid packs with diagnostics, and never allows user
packs to override any reserved bundled ID, even when the bundled pack is broken.
When the bundled catalog is malformed, safe directory IDs under the bounded
bundled root are reserved too. If that reservation scan cannot complete within
its limit, user discovery is disabled rather than permitting impersonation.
The fallback is valid `hexon`, otherwise the first valid sorted pack, otherwise
`null` with a diagnostic. A missing user directory is normal.

To try the original starter without touching official artwork:

```sh
pack_root="$(node --experimental-strip-types --input-type=module -e \
  'import { defaultUserPackRoot } from "./src/character-packs.ts"; console.log(defaultUserPackRoot())')"
npm run packs:validate -- examples/characters/spark &&
mkdir -p "$pack_root" &&
if mkdir "$pack_root/spark"; then
  cp -R examples/characters/spark/. "$pack_root/spark/" &&
  npm run packs:validate -- "$pack_root/spark"
else
  printf '%s\n' 'Spark was not installed: destination exists or cannot be created.'
fi
```

Run this from the repository root. Creating the destination with `mkdir`
refuses an existing directory or symlink; rerunning cannot overwrite the pack
or accidentally nest another `spark` directory inside it. If copying fails,
inspect the incomplete destination before retrying rather than merging files.

Use **Refresh** in the character lab, or restart the application, after changing
installed files. No
network requests, executable files, package installation or asset generation are
part of discovery.
The lab's **Preview fallback** button also exercises the same brief static entrance
used by the tour when an optional intro is missing or invalid. Moving the lab to
another screen cancels an active intro; replay it on the new screen.

### Update one installed pack

1. Extract the new version into a separate staging directory **outside** the
   discovered `characters/` directory. Inspect its files and run
   `npm run packs:validate -- /path/to/staged/spark`. Confirm the manifest still
   has `id: "spark"` and review license or narration changes.
2. Close the tour while replacing its files. Move only the existing
   `"$pack_root/spark"` directory to a clearly named backup **outside**
   `"$pack_root"`; do not move or replace the whole `characters` directory.
   Keep the backup until the replacement is verified.
3. Create a fresh `"$pack_root/spark"` directory, then copy the staged folder's
   **contents** into it, as in the non-overwriting installation example above.
   Do not copy over an existing version: that can retain obsolete files.
4. Validate the installed path again. If validation fails, move the failed
   replacement out of discovery and restore the backup to the original
   `"$pack_root/spark"` path.
5. Select **Refresh** in the lab and check preview, speech, pointing, flight and
   intro. Restart the application to reload the updated pack. Keeping the ID
   unchanged preserves the saved character selection.

### Remove or disable one user pack

Close the tour, then move only `"$pack_root/spark"` to a backup location outside
the discovery root. Moving is reversible; delete that chosen pack only when
you no longer need it. Never remove the parent `characters/` directory or edit
bundled assets to uninstall a user pack.

Refresh the lab or restart the application. If the removed ID was selected,
the application reports that it is unavailable and uses the valid fallback:
HEXON, otherwise the first valid sorted pack. With no valid packs, discovery
returns `fallbackId: null` and diagnostics rather than silently choosing a
missing character. Select an available character to update your preference.

## Manifest v1

Use `examples/characters/spark/character.json` as a complete starting point.
Required fields:

| Field | Contract |
| --- | --- |
| `formatVersion` | Exactly `1` |
| `id`, `displayName`, `description` | Stable safe ID, human name, concise description |
| `author` | `{ "name": "Your name", "status": "declared" }`, or `name: null`, `status: "unresolved"`; optional `note` |
| `license` | `{ "status": "declared", "identifier": "CC0-1.0" }`, or `status: "unresolved"`; optional `note` |
| `preview` | `{ "sprite": "idle", "frame": 0 }`; no duplicate preview PNG |
| `sprites` | Explicit semantic sprite roles and strip geometry |
| `renderer` | Fixed canvas and pose registration described below |
| `effects` | `{ "thrusters": true }` or `false` |
| `motion` | `{ "tourFlight": "upright" }` or `"sprite"` (requires flight) |
| `narration` | Explicit own, borrowed or silent policy |

Unsupported manifest fields are rejected rather than silently interpreted.
Old `prefix`, `flames`, `voice`, `edgeVoice`, `flightFrames` and `intro.kind`
fields are replaced by the explicit contract, not another supported format.

### Format stability and compatibility

The documented v1 contract is fixed. Replacing artwork, correcting registration
or changing supported metadata values does not change `formatVersion`; keep the
stable pack ID across those updates. Do not invent additional v1 fields or
reuse existing fields with different meanings: unknown fields are rejected.

A breaking schema or renderer interpretation requires a new format version and
explicit application support/migration. This loader accepts only
`formatVersion: 1`; it does not promise forward compatibility with future
versions or automatically migrate legacy prefix-based manifests. The optional
intro grammar has its own version, described in
[Character intros](character-intros.md). An unsupported intro is disabled with
a diagnostic; an unsupported character manifest rejects the pack.

### Sprite strips and animation

Required roles: `idle`, `talk`, `point`, `point-up`. Optional roles: `flight`,
`point-blink`, `point-up-blink`, and `speech`.
Each descriptor has a pack-relative PNG `path`, positive integer `frameWidth`,
`frameHeight`, and `frames`. Pose strips have `frameHeight: 192`; the optional
`speech` patch can have a smaller height (OLLIE's existing strip is 22×30 pixels
per frame). PNG width must equal `frameWidth * frames` exactly.

One-frame artwork is supported. Animated strips choose either `fps` (0.1–60) or
a nonempty `timeline` of `{ "frame": 0, "durationMs": 3000 }` entries. Frame
indices are zero-based and must exist. Durations are 16–60,000 milliseconds,
with at most 256 entries and at most 60 seconds total. No implicit 16-frame
requirement exists. Official idle pacing remains:

```json
[
  { "frame": 0, "durationMs": 3000 },
  { "frame": 11, "durationMs": 50 },
  { "frame": 12, "durationMs": 100 },
  { "frame": 13, "durationMs": 50 }
]
```

`talk` shares the `idle` pose registration, so their frame widths must match.
The talking silhouette must use the same body centre and baseline as idle.

Optional `blink` defines `periodMs`, `startMs`, and `durationMs` for pointing
blink variants. The blink must finish within its period. Existing packs use
`3200`, `3050`, and `100` respectively. Omit blink roles when
the artwork does not need them.

### Registration, not resizing guesses

`renderer.canvas` is `{ "width": 224, "height": 192 }` in v1.
`renderer.baseline` and `renderer.bodyAnchorX` establish shared canvas anchors.
`renderer.poses` requires `idle`, `point`, `point-up`, plus `flight` when supplied.
Each pose declares `frameWidth`, `scale`, and `offset: {x,y}`. All non-flight
poses also declare a source `baseline` and `bodyAnchorX`; these must transform
to the canvas anchors within 0.05 pixels:

```text
source baseline * scale + offset.y = renderer.baseline
source bodyAnchorX * scale + offset.x = renderer.bodyAnchorX
```

Pointing poses require a source-frame `tip: {x,y}` that transforms inside the
canvas. Optional `flameSockets` are source-frame points. Optional `speech`
declares `source` and `destination` rectangles (`x`, `y`, `width`, `height`),
with an optional `sprite: "speech"` instead of the default `"talk"` and optional
matching `frameWidth`. Source crops must fit the referenced sprite frame, and
destination crops must fit the pose frame. Registration coordinates must be
finite, scales 0.1–4, and transformed frames bounded and intersecting the canvas.
Use `registrationNote` to explain the anatomical anchors.

The official registered geometry and original PNG filenames are unchanged.
The loader never trims, regenerates or copies official artwork.

### Narration is a separate choice

* Own: `{ "mode": "own", "audioSet": "your-pack-id" }`. The audio set must match
  the pack ID. Optional `voices: { "azure": "...", "edge": "..." }` carries
  authoring voice identifiers, not commands. Existing official voice strings
  are preserved here.
* Borrowed: `{ "mode": "borrowed", "audioSet": "hexon" }` or `"owl"`.
  Only these bundled audio sets are supported. The runtime deliberately
  presents text only for borrowed clips whose source text identifies HEXON or
  OLLIE, regardless of which voice set is borrowed, so Spark does not introduce
  itself as either bundled coach.
* Silent: `{ "mode": "silent" }`. Display course text without recorded narration.

Graphics-only community packs do not have to supply audio. A character pack
cannot override course text, launch a generator, or request arbitrary audio URLs.
Own audio is produced through the project's separate trusted course-audio workflow.

### Optional introductions

`"intro": { "sequence": "intro/sequence.json" }` refers to a declarative
sequence. See [Character intros](character-intros.md) for the shared grammar.
The same path-containment and PNG validation applies to every intro asset.
Missing, unsafe or invalid intro data disables the intro with a diagnostic,
leaving the character usable with a safe handoff to the ordinary tour.
Official intro PNGs remain in `sprites/`; asset relocation is unnecessary.

## Safety and limits

Only JSON and PNG references are accepted. Paths must be relative, with no
absolute paths, `.`/`..` segments, backslashes, URL schemes, percent escapes,
query strings, fragments or empty segments. The real path of every referenced
file must stay within its pack; discovered pack directories must stay within
their discovery root. Symlinks escaping these roots are rejected. Files must
be regular files, and their size is checked before bounded reads and parsing.

Limits: manifest/catalog 256 KiB, intro sequence 64 KiB, PNG 16 MiB, PNG side
16,384 pixels, 32 million decoded pixels per image **and cumulatively per pack**
(at most 128 MiB of RGBA pixels), 64 referenced runtime files,
128 MiB referenced runtime bytes, 256 filesystem entries per pack, 512
catalog/user-directory entries, and at most 64 user-pack directories per discovery.
Discovery caps serialized pack data below 8 MiB, reserving room for diagnostics.
Strips allow 1–256 frames, each at most 2,048 pixels wide. PNGs must be
noninterlaced, 8-bit grayscale, grayscale-alpha, RGB or RGBA; export indexed
artwork as RGBA. PNG signatures, dimensions, chunk boundaries/checksums,
compressed scanline sizes and filter types are checked without extra dependencies.
All ordinary pack files also count toward a 128 MiB filesystem budget.
Bundled `concepts/` and `sprites.conf` are explicitly excluded from this
filesystem inspection as trusted development material. Only referenced files
are loaded or installed by the runtime installer.

Packs are **data, never plugins**. QML, JavaScript, shell files and SVG are not
runtime assets, and executable extensions are rejected even when unreferenced.
A repository `sprites.conf` is trusted authoring input to the
existing preparation scripts, not a pack manifest: discovery ignores it and
never sources it. Never run a stranger's preparation script or `sprites.conf`
just to try their character. Generate sprites in your own trusted authoring
environment, inspect the resulting JSON/PNGs, then validate the data-only pack.

`make install` includes the shared QML module (including its `qmldir` type
registration), timeline grammar, resolver, lab entrypoint, format documentation,
and validated official runtime assets. It installs only the discovery, course
validation, capture-practice, and window-ownership helper tools. Sprite
preparation, audio generation and other authoring tools remain checkout-only.
The idle frame-zero preview reuses each pack's installed idle PNG.

## Attribution and publishing

Declared metadata records the publisher's claim; validation does not determine
copyright ownership. Unresolved author/license status warns rather than blocking
local use. HEXON and OLLIE intentionally have unresolved authorship and asset
licenses because the repository does not declare them. Do not infer a license
from project code or packaging and do not redistribute that artwork without
clarification.

Spark's four simple geometric placeholder PNGs are original example
project-generated shapes, explicitly CC0-1.0. This declaration applies only to
that example, not existing artwork. Replace the example images with your own
properly licensed work, update metadata and registration, validate the folder,
preview it in the lab, then share only the intended pack files.

### Propose a bundled character through a pull request

Bundling is a repository contribution, not something a user pack can request
at runtime. Open a PR with this checklist:

- [ ] Choose a unique, stable ID and provide accurate author attribution and
      a declared asset license permitting redistribution. Include any required
      attribution and license terms in the review. Existing unresolved official
      asset metadata is not permission to reuse that artwork.
- [ ] Add `assets/characters/<id>/character.json` and its referenced PNG assets.
      Include a validated intro sequence and its assets if the character has
      one; otherwise confirm that the graphics-only fallback is intentional.
      Set the narration policy explicitly.
- [ ] Add the ID to `assets/characters/index.json`. The manifest remains the
      authority for its display name and behavior.
- [ ] Run `npm run packs:validate -- assets/characters/<id>`, `npm run check`,
      and `npm test`. Run `npm run test:ui` in the supported Qt environment;
      preserve existing-art regression coverage rather than regenerating
      official assets to satisfy tests.
- [ ] Preview the pack in the character lab: idle/talk timing, pointing tips,
      speech overlay, facing, motion, optional effects, and intro
      play/skip/replay. Check chooser selection and the selected narration mode
      in the main application.
- [ ] Keep the contribution data-only. Do not add character-ID branches to the
      application, renderer or lab. Do not include executable pack scripts,
      generated concept-art collections, or `sprites.conf` as runtime assets.
      A new pack must use the existing contract without bespoke application
      registration.
- [ ] Verify the installation whitelist includes the manifest, referenced PNGs,
      and valid intro files, but excludes authoring material and unrelated
      files. Describe any compatibility implications in the PR; schema changes
      need separate versioned application support.
