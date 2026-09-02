# Learn Omarchy

Learn Omarchy is a metadata-driven, interactive desktop course runner for
Omarchy 4 and Hyprland. It teaches an action, shows the shortcut as themed
keycaps, lights up each expected key as it's pressed, detects the resulting
desktop state, and highlights the relevant UI.

The first lesson teaches the current Omarchy Apps binding:

```text
SUPER + ALT + SPACE
```

`SUPER + SPACE` opens the root Omarchy menu on current Omarchy releases.

## Why QML and TypeScript?

The visible application uses Quickshell/QML because Omarchy already ships it
and it provides native Wayland layer-shell surfaces. This gives accurate
per-monitor logical coordinates, HiDPI scaling, click-through overlays, and
direct Hyprland events without Electron or X11.

TypeScript defines and validates the course format. Course JSON is read
directly by the running app, so content and geometry changes don't require a
compile step.

## Run it

Requirements are already present on a normal Omarchy 4 installation:

- Hyprland
- Quickshell 0.3 or newer
- Node.js 22.6 or newer
- mpv

From this repository:

```bash
./bin/learn-omarchy
```

Run a different course:

```bash
./bin/learn-omarchy --course /path/to/course.json
```

Validate metadata without opening the UI:

```bash
./bin/learn-omarchy-validate courses/omarchy-basics.json
```

## Install it

Install for one user:

```bash
make install PREFIX="$HOME/.local"
```

Ensure `~/.local/bin` is on `PATH`, then run `learn-omarchy` or open **Learn
Omarchy** from the Apps menu.

Build an Arch package directly from this working tree:

```bash
cd packaging
makepkg -si
```

The local `PKGBUILD` is development scaffolding. Set its final project URL and
license before publishing it to a package repository.

## Course metadata

Courses use schema version 1:

```json
{
  "schemaVersion": 1,
  "id": "example",
  "title": "Example course",
  "lessons": [
    {
      "id": "apps",
      "title": "Apps",
      "steps": [
        {
          "id": "open-apps",
          "instruction": "Let's open the Apps menu.",
          "keys": ["SUPER", "+", "ALT", "+", "SPACE"],
          "audio": "audio/open-apps.opus",
          "help": {
            "label": "Open Apps for me",
            "command": ["omarchy", "menu", "summon", "apps"]
          },
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
            "durationMs": 2400
          }
        }
      ]
    }
  ]
}
```

### Geometry

Highlight values use Wayland logical pixels, not physical display pixels.
Quickshell applies the monitor scale automatically. `x` and `y` are offsets
from the selected anchor.

Supported anchors are `top-left`, `top`, `top-right`, `left`, `center`,
`right`, `bottom-left`, `bottom`, and `bottom-right`.

Set `shape` to `rectangle` or `circle`. Circles require equal width and height.
The border and keycaps use the active Omarchy theme's accent and foreground
colors from:

```text
~/.local/state/omarchy/current/theme/colors.toml
```

### Completion and Help

The first detector listens to Hyprland's native `openlayer` event and matches
the configured layer namespace. This verifies the desktop outcome without
capturing arbitrary keyboard input.

While a step is waiting for its shortcut, the teaching surface receives
keyboard focus but doesn't accept the events. Expected keycaps light up on
press and return to normal on release, while Hyprland can still handle its
global shortcut.

Help actions are argument arrays, not shell strings. The app executes the
semantic Omarchy command directly. This avoids privileged synthetic input,
shell injection, and differences between keyboard layouts.

### Audio

Audio starts when a step begins and stops when the step completes or the app
closes. Opus is recommended for narration, and mpv also supports MP3, Ogg,
FLAC, and WAV. Omit `audio` or set it to `null` for a silent step.

## Project layout

| Path | Purpose |
|---|---|
| `app/shell.qml` | Native layer-shell UI and course runtime |
| `courses/` | Editable course metadata and packaged narration |
| `src/course.ts` | Metadata types and runtime validator |
| `tools/validate-course.ts` | Validation CLI |
| `tests/` | Validator tests |
| `bin/` | Repository and installed launchers |
| `packaging/` | Arch Linux package scaffolding |
| `.plans/plan.md` | Researched architecture and phased plan |

## Current boundary

Version 0.1 supports ordered lessons, rectangle/circle highlights, narration,
Help actions, and Hyprland layer-open completion. Future lessons can add
detectors for focused applications, workspaces, and other shell state without
changing the metadata safety model.
