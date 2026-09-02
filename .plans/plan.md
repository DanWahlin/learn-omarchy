# Learn Omarchy implementation plan

## Goal

Build a packageable, metadata-driven, interactive Omarchy course runner that:

- teaches real desktop actions;
- renders precise, theme-aware screen highlights and key hints;
- plays optional narrated audio;
- detects whether the learner reached the intended desktop state;
- offers a visible Help action that performs the semantic action safely; and
- keeps lesson content in editable JSON.

## Researched technical direction

### UI: standalone Quickshell/QML application

Omarchy 4 uses Quickshell 0.3.1 for its bar, menus, notifications, and overlays.
Quickshell is therefore the smallest native dependency and the most accurate
Wayland integration:

- `PanelWindow` plus `WlrLayershell.layer: WlrLayer.Overlay` renders above
  normal windows without screen capture or X11 compatibility layers.
- Logical QML coordinates automatically account for each monitor's Wayland
  scale, so a configured 10 px border stays visually consistent on HiDPI.
- `mask: Region` keeps the full-screen teaching surface click-through except
  for the Help button.
- One overlay is created per `Quickshell.screens` entry for multi-monitor
  correctness.
- `Hyprland.rawEvent` reads compositor events directly over Hyprland IPC. It
  avoids polling and avoids intercepting or logging arbitrary keyboard input.

### Course engine and tooling: TypeScript

TypeScript will own metadata types, validation, and command-line tooling.
QML remains responsible for the native surface because a TypeScript GUI stack
would add Chromium/Electron or a custom Wayland binding without improving the
result.

The runtime UI reads the same JSON directly, so authors don't need a build
step after editing a course. The TypeScript validator catches authoring errors
before packaging or launching.

### Completion detection

Lessons should verify outcomes rather than spy on keystrokes. For the first
lesson:

1. Show `SUPER + ALT + SPACE`, the binding on current Omarchy 4 systems.
2. Listen for Hyprland's `openlayer` event.
3. Complete the action when the `omarchy-menu` layer appears.
4. Remap the passive teaching overlay so the configured highlight appears
   above the newly opened menu.

Future detectors can cover toplevel windows, active workspaces, focused apps,
and shell IPC states while preserving this outcome-based model.

### Help action

Wayland intentionally prevents arbitrary applications from synthesizing global
key presses. Although tools such as `ydotool` can bypass that boundary, they
require a privileged daemon and create unnecessary security risk.

Each lesson will instead configure an argument-vector action such as:

```json
["omarchy", "menu", "summon", "apps"]
```

That performs the exact semantic result of the taught shortcut without shell
evaluation, quoting bugs, or elevated input injection.

### Audio

An optional relative audio path is played through `mpv`, which is already
available on the target Omarchy system. `--no-video` and a dedicated player
process provide MP3, Opus, Ogg, FLAC, and WAV support. Missing audio is a
visible course error rather than a silent failure.

### Theme integration

The app watches:

```text
~/.local/state/omarchy/current/theme/colors.toml
~/.local/state/omarchy/current/theme/shell.toml
```

It uses `accent`, `foreground`, `background`, and `muted` from the active
theme, with safe fallbacks. Theme files are read-only; the learning app never
edits packaged Omarchy files or the user's Hyprland configuration.

## Metadata v1

Each course contains ordered lessons. Each lesson contains ordered steps with:

- stable IDs and instructional text;
- visual key tokens;
- optional relative narration audio;
- a detector (`hyprland-layer-open` in the first slice);
- an optional argument-vector Help action;
- a highlight shape (`rectangle` or `circle`);
- logical dimensions, border width, and an anchor/offset;
- display timing and an optional completion message.

No metadata field is treated as a shell command string.

## Implementation phases

### Phase 1: foundation and metadata

- Create the dependency-light TypeScript project.
- Define strict metadata types and runtime validation.
- Add a sample "Open Apps" course.
- Add validator tests for valid and unsafe/invalid courses.

**Checkpoint:** `npm test` passes and the sample course validates.

### Phase 2: native overlay

- Build a standalone Quickshell entry point.
- Load and watch course JSON.
- Render the instruction card, themed keycaps, and top-right Help button.
- Render rectangle/circle highlights from logical metadata coordinates.
- Keep all non-interactive overlay areas click-through.
- Replicate the surface across monitors and select the focused monitor.

**Checkpoint:** the QML process starts cleanly and displays the first prompt.

### Phase 3: interaction, audio, and progression

- Connect to `Hyprland.rawEvent`.
- Match configured layer-open outcomes.
- Invoke Help with a safe argv array.
- Play/stop narration with `mpv`.
- Transition from prompt to success highlight, then advance or finish.
- Surface metadata, audio, and action failures in the UI.

**Checkpoint:** both the real shortcut and Help button open Apps, trigger the
highlight, and complete the step.

### Phase 4: packaging and author experience

- Add `learn-omarchy` and validation launchers.
- Add install/uninstall targets that use user-owned XDG locations.
- Add a desktop entry and Arch `PKGBUILD` as package scaffolding.
- Document metadata authoring, geometry, audio, and extension points.

**Checkpoint:** the app can run from the repository and from the staged package
layout without modifying Omarchy system files.

### Phase 5: verification

- Run TypeScript checks and metadata tests.
- Validate the bundled course.
- Run a short Quickshell startup smoke test and inspect its logs.
- Exercise live Hyprland layer detection and Help behavior.

## First-slice boundaries

Included now:

- rectangle and circle highlights;
- exact logical size, offset, and border width;
- active-theme colors;
- visual key combinations;
- optional audio-file playback;
- top-right Help action;
- Hyprland layer-open completion;
- ordered course progression;
- TypeScript metadata validation;
- user-local and Arch package scaffolding.

Deferred until a concrete lesson needs it:

- recorded narration content;
- branching lessons and quizzes;
- persistence/resume;
- translations;
- detectors for arbitrary application internals;
- an Omarchy bar plugin (the top-right in-course Help button is less invasive
  and works even when the bar is hidden).

## Acceptance criteria

1. Editing `courses/omarchy-basics.json` changes lesson content without a
   rebuild.
2. Invalid metadata fails with a field-specific message.
3. The prompt shows theme-colored `SUPER`, `+`, `ALT`, `+`, `SPACE` keycaps.
4. The overlay doesn't block normal desktop input outside the Help button.
5. Opening Apps emits a match, displays the configured 10 px highlight, and
   progresses the course.
6. Help reaches the same outcome without synthetic input or privilege.
7. Optional audio can be replayed and is stopped during transitions/exit.
8. No file under `/usr/share/omarchy` or `~/.config/hypr` is modified.
