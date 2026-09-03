# Learn Omarchy

Learn Omarchy is an interactive, theme-aware desktop course for Omarchy 4. It
teaches real shortcuts and system surfaces in short modules, responds as each
expected key is pressed, performs an action on request, narrates every
activity, and highlights the result on screen.

The bundled course contains 7 modules and 21 hands-on activities:

| Module | What it covers |
|---|---|
| Omarchy tour | HEXON introduces the bar, then Super + Space opens the Omarchy menu |
| Menus and apps | Omarchy, Apps, and keybindings menus |
| Everyday apps | Terminal, browser, and file manager |
| Workspaces | Moving forward and back between workspaces |
| Menu bar | Audio, network, power, and calendar panels |
| Personalization | Backgrounds, themes, and the Toggle menu |
| Capture and share | Capture, sharing, and clipboard history |
| Setup and system | Hardware menu, Display panel, and System menu |

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

- Select a module with the mouse or arrow keys and `Enter`. Each card previews
  its first shortcut.
- Press the displayed shortcut. Each keycap lights up while its key is held.
  Every bundled activity is driven by a real Omarchy hotkey; there are no
  click-only steps.
- Select **Help** to perform the current action for you.
- Use the speaker control to mute or unmute narration.
- The speaker and exit controls remain available above the module picker.
- Use the play control beside the instruction to replay it.
- Select **Skip** to move past an activity or **Topics** to return to the
  module picker.
- Press `Escape` to return to Topics during a module.

The visual overlay keeps keyboard focus while Learn Omarchy teaches a shortcut
and remains continuously mapped during success animations. When the complete
combination is held, it runs
the configured semantic Omarchy action and verifies the result. It doesn't
inject privileged synthetic input.

Activity changes cross-fade the outgoing instruction and controls into the
next success or teaching state. Workspace activities also verify that
Hyprland's focused workspace actually changed before reporting success.

HEXON coaches each activity alongside the existing keycap feedback. He flies
into position when a step begins, talks with narration, reacts to correct and
incorrect keys, celebrates completed shortcuts, and flies toward the controls
before performing a requested Help action. He waits beside the keycaps during
an activity, follows selected cards in the lesson picker, and travels to the
configured target after a shortcut succeeds. For left-column lessons he stays
beside the dialog; for right-column lessons he makes a short flight into the
center gap. He always points right toward the selected card. Moving within one
column uses a shorter vertical pointing-pose transition. Click HEXON for a
reaction, or drag him to another position and release him to let gravity return
him to the lower screen boundary.
Completion guidance scales and positions HEXON from the available screen
space, keeps him outside the target, and points at its vertical center. Travel
uses eased movement with an upright pose and stronger boot thrust. Settled and
pointing poses hover by a few pixels with smaller animated boot flames, and a
brief leveling pause keeps coaching and pointing from snapping into place. At
module completion, HEXON flies beside the summary panel before celebrating.
Targets use a small pulsing reticle instead of attempting to
outline an entire external window whose inner geometry isn't exposed by
Wayland. Set
`LEARN_OMARCHY_REDUCED_MOTION=1` before launching to keep the character
feedback while disabling nonessential movement.

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
- `narration-complete` is used by tour steps (`"kind": "tour"`). HEXON flies to
  the step's highlight, shows the instruction as a caption beneath him, plays
  the narration, and advances `delayMs` after it ends. With narration muted or
  unavailable the step advances after `durationMs` instead. Enter continues a
  tour step early. Tour stops draw a pulsing rectangle around the highlight;
  a highlight with `"dynamic": "workspaces"` sizes itself from the number of
  workspace pills the bar is showing.
- `hyprland-window-activated` waits for an application window to open or gain
  focus, which verifies global launch shortcuts even when Hyprland consumes the
  final key. A newly opened window always counts. A focus-only change counts
  only after the expected modifier keys were observed or a Help action ran, and
  only for a window other than the one that was active when the step began.
  The window's exact geometry is read from `hyprctl clients -j` in logical
  coordinates, retried briefly while Hyprland finishes tiling, and refreshed
  once before HEXON flies to it.
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
qs --path "$PWD/app" ipc call learn select 1
qs --path "$PWD/app" ipc call learn start 0
qs --path "$PWD/app" ipc call learn activate
qs --path "$PWD/app" ipc call learn react SUPER
qs --path "$PWD/app" ipc call learn target
```

`select` previews menu selection with a zero-based module index, and `start`
opens that module. `activate` previews HEXON's Help sequence before performing
the current activity's configured action. `react` previews a key reaction
without injecting input, and `target` previews the post-completion flight
without launching the external action. These methods are intended for
diagnostics.

## HEXON character lab

The standalone character lab previews HEXON's reusable animation assets and
movement sequences independently from the tutorial:

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
Idle and talk use packed 192×192 frames. Showcase flight uses a wider 256×192
frame, and guided interactions add a dedicated 224×192 pointing pose plus an
upward-pointing variant derived from it for tour stops beneath the bar. Rebuild
the assets after changing the source artwork:

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
