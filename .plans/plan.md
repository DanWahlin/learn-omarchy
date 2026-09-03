# Learn Omarchy product plan

## Goal

Ship a packageable, metadata-driven Omarchy learning app that lets someone
choose a topic, practice real desktop actions, hear each instruction, receive
immediate key feedback, and see the resulting interface highlighted.

## Product principles

- **Hands on:** every activity opens or changes a real Omarchy surface.
- **Short modules:** topics are independently selectable and take a few
  minutes.
- **Safe assistance:** Help runs semantic argument-vector commands, never
  privileged synthetic keyboard input.
- **Outcome based:** completion verifies a compositor surface or a successful
  action rather than logging arbitrary input.
- **Theme native:** colors come from the active Omarchy theme.
- **Content driven:** lessons, narration, actions, and geometry live in JSON.
- **Non-invasive:** the app doesn't edit Omarchy or Hyprland configuration.

## Researched architecture

### Native UI: Quickshell/QML

Omarchy 4 already uses Quickshell for its bar, menus, notifications, and
overlays. A standalone Quickshell application is therefore the smallest native
Wayland solution.

- `PanelWindow` with the overlay layer renders highlights above normal windows.
- Wayland logical coordinates account for monitor scale automatically.
- A shaped input region leaves non-interactive areas click-through.
- Hyprland events expose layer lifecycle without screen scraping.
- Conditional exclusive keyboard focus enables live expected-key feedback.

The visual surface is remapped only when a result needs to be highlighted
above a newly opened shell layer. Avoiding unnecessary remaps preserves
keyboard focus.

### Metadata and tooling: TypeScript

TypeScript owns schema-v2 types, runtime validation, validation tooling, and
tests. QML reads the validated JSON directly, so course authors don't need a
build step.

Schema v2 models:

- course identity and description;
- topic cards with icon, description, duration, and ordered activities;
- shortcut-driven or button-driven activities;
- optional details and narration;
- semantic Help and cleanup commands;
- `hyprland-layer-open` and `action-success` completion;
- anchored rectangle or circle highlights;
- completion messaging.

### Safe actions

Wayland intentionally prevents ordinary applications from synthesizing global
input. The course uses the same semantic Omarchy commands as the desktop's
bindings. Commands are argv arrays and bypass shell parsing. Cleanup commands
close opened surfaces or restore temporary state before progression.

Hyprland 0.56 moved dispatch configuration to Lua. Workspace actions therefore
use the supported `hyprctl eval` API with `hl.dsp.focus`.

### Narration

mpv provides format-independent local playback. The bundled curriculum has one
Ryan-voice MP3 per activity. Audio can be muted, unmuted, or replayed from the
teaching card. Course authors can bulk-generate missing narration with Edge
TTS.

### Progress

Completed module IDs are persisted under the XDG state directory. The topic
picker displays completion without coupling progress to course ordering.

## Curriculum

The initial release includes seven modules and 21 activities:

1. **Menus and apps:** root menu, Apps, searchable keybindings.
2. **Everyday apps:** terminal, browser, file manager.
3. **Workspaces:** next workspace and return to the original workspace.
4. **Menu bar:** audio, network, power, and calendar panels.
5. **Personalization:** background switcher, theme menu, theme cycling.
6. **Capture and share:** capture, sharing, and clipboard history.
7. **Setup and install:** Setup, Install, and Update menu routes.

Bindings and routes are based on the installed Omarchy 4.0.2 Lua bindings and
menu definitions. Destructive, privileged, or configuration-changing actions
aren't performed automatically.

## Delivery phases

### Phase 1: foundation — complete

- TypeScript schema and field-specific validation.
- Quickshell layer-shell app.
- Theme loading and safe command execution.
- First interactive Apps activity.
- Repository and Arch packaging scaffolding.

### Phase 2: teaching interaction — complete

- Large opaque keycaps.
- Live press and release feedback.
- Automatic semantic action after the expected combination is held.
- Help, mute/unmute, and replay controls.
- Result highlights and timed progression.

### Phase 3: course platform — complete

- Two-column topic picker.
- Keyboard and pointer navigation.
- Module descriptions, estimates, progress, skip, restart, and Topics.
- Button-driven activities.
- Persistent module completion.
- Runtime IPC diagnostics.

### Phase 4: full curriculum — complete

- Seven researched modules and 21 activities.
- Outcome detection and cleanup for Omarchy menus and panels.
- Workspace round trip.
- Narration for every activity.

### Phase 5: shipping quality — complete

- Schema-v2 documentation and authoring examples.
- Curriculum breadth and command-safety tests.
- Audio existence and media validation.
- Staged installation and installed-layout smoke tests.
- Representative end-to-end compositor checks.

## Acceptance criteria

1. The topic picker exposes all seven modules and preserves completion.
2. Every bundled activity is metadata-driven and validates before launch.
3. Expected keycaps highlight individually and the full shortcut performs the
   configured semantic action.
4. Help reaches the same outcome without shell evaluation or synthetic input.
5. Button activities are available for nested menu routes.
6. Opened surfaces are detected, highlighted, and cleaned up before advancing.
7. Workspace teaching returns the learner to the starting workspace.
8. All 21 activities have valid playable narration.
9. Highlights use active-theme colors, logical coordinates, and screen bounds.
10. The source and installed launchers work without modifying Omarchy system
    files or Hyprland configuration.
