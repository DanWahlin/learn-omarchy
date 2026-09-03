# Learn Omarchy

Learn Omarchy is an interactive, theme-aware desktop course for Omarchy 4. It
teaches real shortcuts and system surfaces in short modules, responds as each
expected key is pressed, performs an action on request, narrates every
activity, and highlights the result on screen.

The bundled course contains 7 modules and 21 hands-on activities:

| Module | What it covers |
|---|---|
| Menus and apps | Omarchy, Apps, and keybindings menus |
| Everyday apps | Terminal, browser, and file manager |
| Workspaces | Moving forward and back between workspaces |
| Menu bar | Audio, network, power, and calendar panels |
| Personalization | Backgrounds, themes, and theme cycling |
| Capture and share | Capture, sharing, and clipboard history |
| Setup and install | Setup, software installation, and updates |

Progress is saved automatically, and any module can be repeated independently.

## Why Quickshell and TypeScript?

The visible app uses Quickshell/QML, the native shell toolkit already included
with Omarchy. Its Wayland layer-shell surfaces provide accurate logical screen
coordinates, HiDPI scaling, compositor events, and overlays without Electron
or X11.

TypeScript defines and validates the JSON course format. The QML runtime reads
the JSON directly, so instructions, actions, narration, and highlight geometry
can change without compiling the app.

## Run from the repository

Learn Omarchy expects a normal Omarchy 4 installation with Hyprland,
Quickshell 0.3 or newer, Node.js 22.6 or newer, and mpv.

```bash
./bin/learn-omarchy
```

Run a different course:

```bash
./bin/learn-omarchy --course /path/to/course.json
```

Validate the bundled course and run its tests:

```bash
npm run check
npm test
```

## Course controls

- Select a module with the mouse or arrow keys and `Enter`.
- Press the displayed shortcut. Each keycap lights up while its key is held.
- For menu-driven activities, select the large action button.
- Select **Help** to perform the current action for you.
- Use the speaker control to mute or unmute narration.
- Use the play control beside the instruction to replay it.
- Select **Skip** to move past an activity or **Topics** to return to the
  module picker.
- Press `Escape` to return to Topics during a module.

Learn Omarchy holds keyboard focus while teaching a shortcut so it can provide
immediate key-by-key feedback. When the complete combination is held, it runs
the configured semantic Omarchy action and verifies the result. It doesn't
inject privileged synthetic input.

## Install

Install for one user:

```bash
make install PREFIX="$HOME/.local"
```

Ensure `~/.local/bin` is on `PATH`, then run `learn-omarchy` or open **Learn
Omarchy** from the Apps menu.

Build and install an Arch package from this working tree:

```bash
cd packaging
makepkg -si
```

The included `PKGBUILD` is local development scaffolding. A release package
should use a tagged source archive and its checksum.

Progress is stored at:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/learn-omarchy/progress.json
```

## Course metadata

Courses use schema version 2:

```json
{
  "schemaVersion": 2,
  "id": "example",
  "title": "Example course",
  "description": "A short hands-on course.",
  "lessons": [
    {
      "id": "menus",
      "title": "Menus",
      "description": "Learn the primary Omarchy menus.",
      "icon": "01",
      "estimatedMinutes": 2,
      "steps": [
        {
          "id": "open-apps",
          "instruction": "Open the Apps menu.",
          "detail": "Start typing an app name when it opens.",
          "keys": ["SUPER", "+", "ALT", "+", "SPACE"],
          "audio": "audio/open-apps.mp3",
          "help": {
            "label": "Open Apps for me",
            "command": ["omarchy", "menu", "summon", "apps"]
          },
          "cleanup": ["omarchy", "menu", "close"],
          "completion": {
            "type": "hyprland-layer-open",
            "namespace": "omarchy-menu"
          },
          "highlight": {
            "shape": "rectangle",
            "anchor": "center",
            "x": 0,
            "y": 0,
            "width": 340,
            "height": 880,
            "borderWidth": 10,
            "radius": 12,
            "durationMs": 2200
          },
          "completionMessage": "Apps is ready. Type to search."
        }
      ]
    }
  ]
}
```

### Actions and completion

`help.command` and optional `cleanup` values are argument arrays, not shell
strings. They execute directly without shell evaluation.

Two completion detectors are supported:

- `hyprland-layer-open` waits for a matching Wayland layer namespace, such as
  `omarchy-menu` or `omarchy-clipboard`.
- `action-success` waits for the configured command to exit successfully,
  then applies an optional `delayMs` before highlighting.

Set `actionLabel` on a step to replace shortcut keycaps with a large action
button. This works well for nested menu activities where asking a learner to
press a shortcut would be misleading.

Shortcut labels use canonical uppercase names. Supported labels are `SUPER`,
`ALT`, `CTRL`, `SHIFT`, `SPACE`, `RETURN`, `TAB`, individual letters and
digits, plus `+` as a visual separator.

`cleanup` runs before advancing, skipping, returning to Topics, or restarting a
module. It should close any surface or undo any temporary state introduced by
the activity.

### Highlight geometry

Highlight values use Wayland logical pixels. Quickshell applies each monitor's
scale automatically. `x` and `y` are offsets from the selected anchor.

Supported anchors are `top-left`, `top`, `top-right`, `left`, `center`,
`right`, `bottom-left`, `bottom`, and `bottom-right`. Highlights are clamped
inside the selected screen.

`shape` can be `rectangle` or `circle`; circles require equal width and height.
The active Omarchy theme provides the border, foreground, background, muted,
and instruction colors from:

```text
~/.local/state/omarchy/current/theme/colors.toml
```

### Narration

Narration begins with each activity and stops during transitions or when the
app exits. MP3, Opus, Ogg, FLAC, and WAV work through mpv. Audio paths must be
safe paths relative to the course file.

The repository includes Ryan-voice MP3 narration for all bundled activities.
To regenerate it with Edge TTS:

```bash
python -m pip install edge-tts
npm run audio:generate
```

Generate only missing files or choose another voice:

```bash
EDGE_TTS_BIN=/path/to/edge-tts \
LEARN_OMARCHY_TTS_VOICE=en-GB-RyanNeural \
node --experimental-strip-types tools/generate-course-audio.ts \
  courses/omarchy-basics.json --missing
```

## Runtime diagnostics

While the app is running, Quickshell IPC can report or drive its state:

```bash
qs --path "$PWD/app" ipc call learn status
qs --path "$PWD/app" ipc call learn start 0
qs --path "$PWD/app" ipc call learn activate
```

`start` uses a zero-based module index. `activate` performs the current
activity's configured action and is intended for diagnostics.

## HEXON character lab

The standalone character lab previews the experimental HEXON sprite pipeline
without changing the tutorial runtime:

```bash
./bin/hexon-lab
```

Use `1`, `2`, `3`, `4`, and `5` to switch between idle, talk, horizontal
flight, vertical flight, and the fly-and-point teaching sequence. Press `D`
to play every state in sequence, `M` to move, `S` to cycle through 0.5×, 1×,
1.5×, and 2× scaling, `R` to toggle reduced motion, and `Escape` to close.
The same controls are available as clearly labeled buttons.

The generated concept art is under `assets/characters/hexon/concepts/`.
Normalized runtime assets are under `assets/characters/hexon/sprites/`.
Idle and talk use packed 192×192 frames. Flight uses a wider 256×192 frame
that preserves the exhaust trail, and guided interactions add a dedicated
224×192 pointing pose. Rebuild the assets after changing the source artwork:

```bash
npm run character:prepare
```

The preparation command requires ImageMagick during asset development.

## Project layout

| Path | Purpose |
|---|---|
| `app/shell.qml` | Native layer-shell UI and course runtime |
| `assets/characters/` | Character concepts and prepared sprite strips |
| `courses/` | Editable curriculum and packaged narration |
| `experiments/hexon-lab/` | Standalone sprite and movement test surface |
| `src/course.ts` | Schema-v2 types and runtime validator |
| `tools/validate-course.ts` | Course validation CLI |
| `tools/generate-course-audio.ts` | Bulk Edge TTS narration generator |
| `tests/` | Metadata and safety tests |
| `bin/` | Repository and installed launchers |
| `packaging/` | Arch Linux package scaffolding |
| `.plans/plan.md` | Architecture, implementation phases, and acceptance criteria |

Learn Omarchy reads Omarchy's theme and desktop state but doesn't modify files
under `/usr/share/omarchy` or the user's Hyprland configuration.
