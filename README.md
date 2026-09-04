# Learn Omarchy

Learn Omarchy is an interactive, theme-aware desktop course for Omarchy 4. It
teaches real shortcuts and system surfaces in short modules, responds as each
expected key is pressed, performs an action on request, narrates every
activity, and highlights the result on screen.

The bundled course contains 11 modules and 53 activities:

| Module | What it covers |
|---|---|
| Omarchy tour | Your coach introduces the bar, then Super + Space opens the Omarchy menu |
| Menus and apps | Omarchy, Apps, and keybindings menus |
| Everyday apps | Terminal, browser, and file manager, and closing what you open |
| Windows | Tiling, switching focus, floating, fullscreen, and closing |
| Workspaces | Jumping by number, sending windows, next and previous, the scratchpad |
| Menu bar | Audio, network, power, and calendar panels |
| Personalization | Backgrounds, themes, and the Toggle menu |
| Clipboard and helpers | Universal copy and paste, clipboard history, emoji, reminders |
| Capture and share | Capture and sharing menus |
| Setup and system | Hardware menu, Display panel, and System menu |
| Your first real session | A finale that strings the shortcuts together, then a send-off |

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

On the very first run, after you choose a coach, the Omarchy tour opens
straight away instead of the module picker. Completed modules are recorded
per course in `~/.local/state/learn-omarchy/progress.json`, and the fact that
the tour has been opened once is recorded in `settings.json` next to it, so a
skipped tour is never forced again; it stays available from the picker.

The tour opens with a short pixel-art scene before the first stop: HEXON's
rocket drops down the middle of the screen, lands on a pad at the bottom, and
he steps out of the lit hatch; OLLIE's tree grows from the ground and she
takes off from its branch. The desktop dims and the instruction panel fades
while it plays, a booster rumble (synthesized with ffmpeg into
`assets/sounds/`) plays for the landing and liftoff, and `Enter` or Skip
cuts it short. It is skipped entirely
under `LEARN_OMARCHY_REDUCED_MOTION=1`. The top-right controls also fade out
during tour stops that put the coach under the right end of the bar, so they
never compete with what he is pointing at.

- Select a module with the mouse or arrow keys and `Enter`. Each card previews
  its first shortcut.
- Press the displayed shortcut. Each keycap lights up while its key is held.
  Every bundled activity is driven by a real Omarchy hotkey; there are no
  click-only steps. Steps are verified against what Hyprland reports: a layer
  or window opening, the workspace changing, or a named Hyprland event such
  as a window closing or floating (the `hyprland-event` completion type).
  Close steps target only windows the course itself opened (`target:
  "tutorial-window"`, and `{tutorialWindow}` in a Help command), so neither
  a stray keypress nor Help can act on the learner's own windows. Modules
  that depend on a workspace open with a `hyprland-workspace-is`
  prerequisite step, which is skipped silently when the learner is already
  there.
- Select **Help** to perform the current action for you.
- Use the speaker control to mute or unmute narration.
- The speaker and exit controls remain available above the module picker.
- The gear control opens Settings: choose a coach or reset progress.
- The keyboard control beside them releases the keyboard to your other
  windows so you can keep working while the course stays open. A pill at the
  top of the screen brings the keys back; so does the control itself.
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
pointing poses hover by a few pixels with smaller animated boot flames, blink
at irregular intervals, and a brief leveling pause keeps coaching and pointing
from snapping into place. Takeoffs and landings squash and stretch slightly,
and a short trail of fading pixels follows each flight. Coaches travel in
their flying pose facing the direction of travel, land in the standing pose,
and raise or lower the pointing limb through a halfway frame. At
module completion, HEXON flies beside the summary panel before celebrating.
Targets use a small pulsing reticle instead of attempting to
outline an entire external window whose inner geometry isn't exposed by
Wayland. Set
`LEARN_OMARCHY_REDUCED_MOTION=1` before launching to keep the character
feedback while disabling nonessential movement.

## Install

To put this checkout in Omarchy's Apps menu without copying it anywhere:

```bash
make dev-launcher
```

That writes a user desktop entry whose `Exec` points at `bin/learn-omarchy`
in the repository, plus the HEXON icon, so edits apply on the next launch.
`make dev-launcher-remove` takes it out again.

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
  tour step early. A tour step with `"pose": "talk"` flies HEXON to the
  highlight's center and animates his mouth instead of pointing, which the
  tour uses for its welcome. Pointing stops draw a pulsing rectangle around the highlight;
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
app exits. An optional `completionAudio` file narrates the activity's
`completionMessage` while HEXON points at the result; the next activity
starts shortly after it finishes, or right away on Enter. MP3, Opus, Ogg, FLAC, and WAV work through mpv. Audio paths must be
safe paths relative to the course file.

The repository includes MP3 narration for all bundled activities, spoken by
the Azure Speech HD Andrew voice from each activity's instruction text. To
regenerate it with the same service, put `AZURE_SPEECH_KEY` and either
`AZURE_SPEECH_REGION` or `AZURE_SPEECH_ENDPOINT` in `~/.env` (or pass
`--env-file`), optionally `AZURE_SPEECH_MALE_VOICE_US` or
`LEARN_OMARCHY_TTS_VOICE` for the voice, and run:

```bash
node --experimental-strip-types tools/generate-course-audio.ts \
  courses/omarchy-basics.json --backend azure
```

Credential values are read from the file and never printed. Edge TTS remains
available as a free fallback:

```bash
python -m pip install edge-tts
npm run audio:generate
```

Narration is recorded once per coach, under `courses/audio/<character>/`:
the spoken text says the coach's name where the course text says HEXON, and
each coach's `character.json` names its Azure `voice` (HEXON uses Andrew,
OLLIE uses Ada, both HD voices) and an `edgeVoice` for the Edge backend.
`LEARN_OMARCHY_TTS_VOICE` overrides both. With no `--character` flag every coach in
`assets/characters/index.json` is generated. "Omarchy" is respelled for the
voice as "Omaachi" (oh-MAH-chee); set `LEARN_OMARCHY_PRONUNCIATION` to try
another spelling, then regenerate just the lines that mention it:

```bash
LEARN_OMARCHY_PRONUNCIATION=Omaachi \
node --experimental-strip-types tools/generate-course-audio.ts \
  courses/omarchy-basics.json --backend azure --match Omarchy --character owl
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

## Characters

HEXON is the default coach. On first launch a "Choose your coach" screen
shows every character side by side; pick with the arrow keys or the mouse and
confirm with Enter. The choice is saved to
`~/.local/state/learn-omarchy/settings.json`. The gear button beside the
speaker and exit controls opens Settings, where you can switch coaches and
reset progress (two clicks, or press R twice); a reset clears every module
checkmark and the coach choice, so closing Settings asks for a coach again
and then starts the tour, like a fresh install. The module picker always
selects the first unfinished module, so the coach points at what's next. The coach list comes from
`assets/characters/index.json`.

Alternative characters live under `assets/characters/<name>/` with the same
asset set: `concepts/` (generated sheets), `sprites.conf` (pipeline geometry),
`character.json` (runtime geometry: sprite prefix, display name, pointing
tips, pose scales, boot flames, flight frames, opening scene), and `sprites/`
(built strips). The opening scene comes from `<prefix>-intro.png` (a rocket
also needs `<prefix>-intro-open.png` with the hatch open); `intro` in
`character.json` names the `kind` (`rocket` or `tree`) and `anchorX`/`anchorY`,
the doorway floor or the perch as fractions of that sprite.
A launch flag overrides the saved choice and skips the picker:

```bash
./bin/learn-omarchy --character owl
```

The bundled owl, OLLIE, was generated from a single concept with the image
model configured in `~/.env` (`AI_IMAGE_ENDPOINT`, `AI_IMAGE_API_KEY`,
`AI_IMAGE_MODEL`), then edited into the idle strip and poses:

```bash
node --experimental-strip-types tools/generate-character-art.ts generate \
  --prompt "16-bit pixel art mascot sprite of ..." \
  --out assets/characters/owl/concepts/owl-concept-v1.png
node --experimental-strip-types tools/generate-character-art.ts edit \
  --image assets/characters/owl/concepts/owl-concept-v1.png \
  --prompt "Sprite sheet of this exact owl: 8 identical copies ..." \
  --out assets/characters/owl/concepts/owl-idle-blink-strip-v1.png
tools/prepare-character-sprites.sh owl
```

Credential values are never printed. The idle strip must hold eight copies in
192 px columns with expressions in the order neutral, half blink, closed,
happy; `sprites.conf` sets the eye region that is swapped between frames plus
an optional alpha cutoff and column-locked alignment for generated art whose
copies vary slightly. A character whose mouth is what moves (a beak, say) can
add a `talk_source` strip with eight mouth variations, and characters with
wings can list `flight_extra_sources` (a wing down-stroke) to build a
multi-frame flight strip that `character.json` enables with `flightFrames`;
those characters fly with their wings instead of HEXON's boot flames. Displayed text that names HEXON switches to the selected
character's display name automatically.

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
| `tools/generate-course-audio.ts` | Narration generator (Azure Speech or Edge TTS) |
| `tests/` | Metadata and safety tests |
| `bin/` | Repository and installed launchers |
| `packaging/` | Arch Linux package scaffolding |
| `.plans/plan.md` | Architecture, implementation phases, and acceptance criteria |

Learn Omarchy reads Omarchy's theme and desktop state but doesn't modify files
under `/usr/share/omarchy` or the user's Hyprland configuration.
