# Learn Omarchy

Learn Omarchy is an interactive, theme-aware desktop course for Omarchy 4. It
teaches real shortcuts and system surfaces in short modules, responds as each
expected key is pressed, performs an action on request, plays available coach
narration, and highlights the result on screen.

The bundled course includes a welcome, core modules, optional extensions, and
an explicitly opt-in lock-screen exercise. Optional modules appear after the
complete core sequence. All bundled activities have current coach narration,
including the new window exercises and optional shortcut introductions.

| Module | What it covers |
|---|---|
| Welcome to Omarchy | Your selected coach, course controls, and getting started |
| Omarchy tour | Your coach introduces the bar, then Super + Space opens the Omarchy menu |
| Menus and apps | Omarchy, Apps, and keybindings menus; search for, launch, and close a terminal |
| Everyday apps | Terminal, browser, and file manager, and closing what you open |
| Windows | Focus, floating and retiling, resize, dwindle split changes, fullscreen, swapping, and closing |
| Workspaces | Numbered and former workspaces, moving windows, and populating, showing, hiding, and emptying the scratchpad |
| Clipboard and Compose | Clipboard history and sequential Compose-key input |
| Capture | Region-selection exercise, image preview, and screen recording |
| Apps and upkeep | Application discovery and maintenance orientation |
| Setup and system | Hardware, Display, and System; optional explicit lock/unlock practice |
| Your first real session | A finale that strings the shortcuts together, then a send-off |
| More window controls (optional) | Grouping, pop-out/pin, workspace layout, and mouse gestures |
| Notifications (optional) | Notification-panel orientation and shortcut reference |
| Desktop controls (optional) | Audio, network, power, calendar, backgrounds, themes, and Toggle |
| Productivity extras (optional) | Emoji, reminders, and optional local dictation |
| Useful tools (optional) | Activity monitor, calculator, and disk-usage inspection |
| Create and share (optional) | Local media and sharing practice |

Progress and your current activity are saved automatically, and any module can
be resumed or repeated independently. Optional activities don't block a module's
completion, and optional modules don't block core completion. When an update adds
required activities, affected modules reopen without discarding earlier activity
results, and bookmarks return to new required work they would otherwise bypass.
Earned activity credit is separate from the latest attempt, so skipping a replay
doesn't erase prior completion.

## Why Quickshell and TypeScript?

The visible app uses Quickshell/QML, the native shell toolkit already included
with Omarchy. Its Wayland layer-shell surfaces provide accurate logical screen
coordinates, HiDPI scaling, compositor events, and overlays without Electron
or X11.

TypeScript defines and validates the JSON course format. The QML runtime reads
the JSON directly, so instructions, actions, narration, and highlight geometry
can change without compiling the app.

## Run from the repository

For a managed installation, use the [Arch package instructions](#install).
Learn Omarchy expects an updated Omarchy **4.0.3 or newer** installation with Hyprland,
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
npm run test:ui
```

The UI suite uses Qt 6's `qmltestrunner` offscreen. It exercises production
settings layouts, scrolling, focus, toolbar docking, both sprite renderers,
and practice controls, including native Qt copy/paste events. The clipboard used
by these offscreen tests isn't your desktop clipboard. The suite doesn't open a
window on your desktop or change your preferences.

When Quickshell is installed, `npm test` also launches the real character lab
from both the checkout and a staged installation, offscreen with private HOME/XDG
directories and PID-scoped IPC. It tests user-pack
discovery, all three intros, cancellation, reduced motion, missing/invalid-intro
fallbacks, refresh and removed-pack recovery. It does not connect to your live
display or session bus. Without Quickshell, that integration test is skipped.

## Course controls

On the very first run, choosing a coach automatically starts **Welcome to
Omarchy**, lesson #1. Your coach enters, flies to the center, narrates the
greeting, briefly explains the highlighted Settings, Keys, Mute, and Exit controls,
and then introduces the course menu while pointing at **Omarchy tour**,
now lesson #2. The tour is
recommended, not started: choose any lesson with the mouse or keyboard.
Captions fade in only after the coach arrives, with time to read each message.
Complete captions fade in briefly without empty reserved rows or per-word
layout changes. Validated recording timings and muted reading timers continue
to govern progression, not text visibility. Reduced motion shows text
immediately. Turn off **Fade captions** in Settings to disable the fade.
This applies to welcome messages, lesson instructions,
completion messages, and lesson wrap-ups. Keycaps, action buttons, safety notes,
and expanded Details remain fully visible.
Choose **Welcome to Omarchy** anytime to replay the entrance and greeting with
your selected coach. There's no need to reset settings or lesson progress.
The welcome reuses `courses/welcome.json` and its existing recordings; its
course entry has `kind: "welcome"` and an empty `steps` array rather than
duplicating the greeting as an activity.

The welcome opens with the selected pack's short pixel-art scene: Ohm's
rocket drops down the middle of the screen, lands on a pad at the bottom, and
he steps out of the lit hatch; OLLIE's tree grows from the ground and she
takes off from its branch. The desktop dims; the existing landing and liftoff
effects play when requested by the pack. **Skip scene** or `Enter` moves on
to the greeting, **Show lessons** advances to the menu, and **Skip welcome**
(or `Escape` before the menu) bypasses the whole welcome.
Reduced motion uses a brief static entrance and immediate placement, retaining
readable captions and manual controls.

Completed modules are recorded per course in
`~/.local/state/learn-omarchy/progress.json`. A `welcomeSeen` flag in the adjacent
`settings.json` records the welcome when it begins, so closing or skipping it
does not replay it next time. Returning users with an older `tourSeen` flag or
recorded progress go directly to the menu. Selecting the tour starts at its
first activity without replaying a pack entrance; other modules resume their bookmarks.
Controls move to the opposite corner when a tour stop uses the right
end of the bar; mute, pause, keyboard capture, and exit remain available.
The workspace overview boxes the menu icon and workspace numbers together;
later workspace-switching activities use individual destination markers.

- Select a module with the mouse or arrow keys and `Enter`. Each card previews
  its first shortcut.
- Press the displayed shortcut. Each keycap lights up while its key is held.
  Guided shortcut activities use real Omarchy key combinations. Narrated tour
  stops introduce concepts, while **Start exercise** opens a separate window
  for hands-on tasks. Shortcut steps are verified against what Hyprland reports: a layer
  or window opening, the workspace changing, or a named Hyprland event such
  as a window closing or floating (the `hyprland-event` completion type).
  Window-changing steps target the window opened by a specific earlier activity
  (`windowFromStep: "launch-terminal"`, `target: "tutorial-window"` in the
  completion detector, and `{tutorialWindow}` in a Help command). Permission
  requires both a new-window event and verification that its process inherited
  the course's unique launch token. Focusing an existing window doesn't grant
  ownership. If a launch happens outside the course's
  keyboard capture, or an app reuses an existing window, the course won't close
  it automatically. Repeat the module with keyboard capture enabled and use
  Help to launch a fresh process, or skip the activity. Guided terminal launches
  use independent Ghostty or Foot instances. Chrome and Chromium use temporary,
  isolated profiles that are removed when their tutorial instance exits; your
  existing browser profile stays untouched. Unsupported terminal/browser
  configurations fail explicitly rather than reusing an unowned instance.
  Files and the calculator retain their normal launch paths and the same token
  verification. A missing-window message offers a return
  to the launch activity, then brings you back to the interrupted task. Move,
  focus, floating, and fullscreen activities inspect the resulting client state
  before reporting success. Modules
  that depend on a workspace open with a `hyprland-workspace-is`
  prerequisite step, which is skipped silently when the learner is already
  there.
- Select **Help** to perform the current action for you.
- **Start exercise** releases keyboard capture so normal desktop shortcuts,
  typing, and clipboard operations reach the exercise window. The coach overlay
  hides so it can't cover the exercise controls. Exercise windows inherit the
  course's theme colors and text size, keep content at a readable width, and
  scroll focused fields into view. **Finish exercise**
  becomes available only after the task is verified. Closing it or choosing
  **Return without completing** doesn't count as success; the coach offers a
  retry or Skip and restores the previous capture setting. Help starts the
  exercise rather than completing it for you.
- Use **Mute** to stop narration and effects immediately.
  During the welcome, unmuting doesn't replay the current line or reset its
  text. Reading continues from your place; the next welcome line uses the new
  audio setting.
- **Settings** groups preferences into Coach, Audio, and Reading & motion.
  Separate narration and effects sliders show **Off** at zero; toolbar Mute
  temporarily silences both without changing their levels. When muted, the Audio
  section shows an Unmute action. Reading controls use switches for Type text,
  Reduce motion, and Advance automatically, plus a text-size slider.
  Preferences persist. Levels and speed apply to the next clip or Replay.
  Opening Settings during a lesson pauses it instead of abandoning your place.
  Its header and Done button stay fixed while the settings body scrolls.
  Tab navigation brings focused controls into view. Done is the only footer
  button, and Reset progress is tucked under Show reset options with a separate
  confirmation. First-run setup shows only the coach choice.
- **Pause** suspends narration and stops activity advancement; **Resume**
  continues it. A running desktop action finishes before pausing is allowed.
- **Release Keys** releases the keyboard to your other
  windows so you can keep working while the course stays open. A pill at the
  top of the screen brings the keys back; so does the control itself.
- Hardware volume up, volume down, and mute still work while keys are captured,
  including during the welcome and in Settings. They adjust system output
  through Omarchy's normal volume controls; Alt + volume uses one-percent steps.
- During narrated tour stops, a compact bottom row keeps navigation separate
  from the coach's caption. **Details** reveals extra guidance and **Replay**;
  automatic progression waits while Details is open. Narration can finish,
  and closing Details restores reading time rather than immediately moving on.
  **Next** moves on manually. Hands-on activities show the main instruction,
  then keycaps or the action button, followed by an optional short note.
  Longer explanations stay behind **Details** instead of appearing as a second
  instruction paragraph. Opening Details in Practice counts as revealing a hint.
- Use **Replay** to hear the instruction again.
- Select **Back** to revisit an activity without automatically repeating its
  action, **Skip** to move past it, or **Topics** to return to the module picker.
- Results appear immediately, with **Continue** available throughout. Turn off
  automatic advancement in Settings to inspect results at your own pace.
- At the end of each taught topic, the coach delivers a short wrap-up after
  arriving beside the completion panel. Skipped or unfinished activities use
  an invitation to revisit them; assisted activities acknowledge the guidance.
  The matching text remains visible with narration muted or unavailable.
  Welcome retains its existing greeting and menu handoff.
- Press **P** on the topic picker, or choose **Practice** after a module, to
  recall shortcuts without visible keycaps or spoken answers. Each shortcut
  step still shows a concrete goal (for example, "Switch to workspace one")
  and its safety note. **H** reveals the full instruction and keycaps as a
  hint, and Help remains available. Practice still dispatches course-guided
  actions; it doesn't verify customized native Hyprland bindings.
- Activity results distinguish **introduced**, **assisted**, **practiced**, and
  **skipped**. Skipping a module doesn't earn a completion checkmark.
- **Mixed practice** unlocks after two eligible modules are explored. It shuffles
  up to three complete lesson blocks, retaining their owned-window setup,
  verification, cleanup, and ID-based progress. Continue explicitly between
  modules; capture, locking, microphone, and sharing exercises are excluded.
- **Printable shortcuts** generates a local reference from the loaded course
  and opens it in the browser for printing or saving as PDF. The bundled sheet
  covers every lesson, including Compose sequences, capture controls and
  non-keyboard workflows, with explicit Omarchy 4.0.3 source references.
  Standalone descriptions distinguish real desktop actions from guided practice.
  Coverage validation rejects missing activities; older custom courses without
  reference metadata are clearly marked unreviewed. It releases keyboard
  capture so the browser can receive your input, and moves the course panels
  and coach aside so they don't cover the document. A small return banner
  brings back your picker or completion screen and its previous Keys state.
  An existing browser may be on another workspace. A rejected browser launch
  leaves the course visible and restores the previous capture state.
  `npm run cheatsheet`
  regenerates the bundled reference. See [curriculum and retention](docs/curriculum-expansion.md).
- Soft accepted-chord, wrong-key, verified-step, and earned-module cues use
  **Effects** volume and Mute independently of narration. They are throttled
  and never replace visual feedback. See [presentation](docs/presentation.md).
- **Tab** moves between controls and **Enter** activates them. Settings sliders
  also support arrow keys.
- Press `Escape` to return to Topics during a module.

The visual overlay keeps keyboard focus and inhibits compositor shortcuts while Learn Omarchy teaches a shortcut
and remains continuously mapped during success animations. When the complete
combination is held, it runs
the configured semantic Omarchy action and verifies the result. It doesn't
inject privileged synthetic input.
Workspace changes and window-focus actions briefly release keyboard capture so
the compositor can establish the new desktop focus. Capture returns after the
outcome is verified, rather than pulling the learner back to the previous workspace.

Focus activities briefly yield the keyboard to verify the actual application
focus before capturing it again. Applications are launched independently of the
activity process, so advancing doesn't terminate Files or another launched app.
Active lessons inhibit idle effects; Topics and Pause allow normal idle behavior.
Directional focus and swap keycaps use the practice windows' measured positions,
so an arrow doesn't claim the other terminal is on the right when it's on the left.

Hands-on exercises deliberately use narrow completion conditions:

- Exercises keep the coach, lesson navigation, and toolbar in place. A bounded,
  scrollable work area appears inside the normal bottom card for samples and
  input. Native menus and region pickers still work normally. Leaving or exiting
  waits for the exercise helper to finish cleaning up before unloading it.
  Recording and OCR samples stay fixed while their controls scroll, so choosing
  the next action doesn't move the content out of the selected region.
- **Start search** keeps the coach and instructions in the normal bottom panel
  while the learner uses the real Apps menu. No separate exercise dialog opens;
  closing the new terminal finishes automatically and restores keyboard capture.
  App search observes an Omarchy menu opening, a new terminal opening, and that
  exact terminal closing. It doesn't inspect the search text or close existing
  windows.
- Clipboard practice requires native copy events for two harmless notes, opening
  clipboard history, and a native paste of the older note. Typing the answer
  doesn't count. This replaces the clipboard; previous clipboard contents aren't
  read or logged by the exercise. Learners use **Shift + Enter** in history to
  copy without pasting, then **Super + V** in the destination field. Ordinary
  history selection pastes immediately, so the exercise doesn't ask for that
  followed by a second paste.
- Capture uses `slurp` and `grim` to select an explicit region and load the saved
  image, then asks you to copy its path and add a local preview annotation.
  The original image is unchanged. Cancellation doesn't count. The image stays
  in the private directory shown in the exercise, not the Pictures screenshot folder.
  It isn't uploaded, and the exercise doesn't terminate other screenshot tools.
- Lock practice never locks automatically. An explicit button starts the lock,
  and completion requires observing both locked and unlocked session states.
  Unsupported lock reporting produces guidance to skip this optional activity.
- Compose checks the smile and heart entered into normal text fields using
  Caps Lock, `m`, `s` and Caps Lock, `m`, `h`, pressed sequentially.
- Recording requires selecting and reviewing a region, explicitly starting and
  stopping the exercise's own `gpu-screen-recorder` process, then successfully
  playing its saved silent clip. It never enables audio or a webcam or stops
  another recorder. Playback uses Qt Multimedia; validation uses `ffprobe`.
  The standard util-linux `setpriv` utility also stops the owned recorder if its
  helper is forcibly terminated.
- OCR and QR use `slurp`/`grim` with `tesseract` or `zbarimg`, respectively.
  `qrencode` creates the harmless QR sample. Completion requires recognition
  of the sample, a native paste, and explicit proofreading. Other recognized
  text isn't displayed or logged, and decoded links are never opened.
- Dictation checks for Voxtype, requires microphone consent before enabling the
  field, and asks you to stop dictation and proofread the sample phrase.
  Microphone control remains with your normal shortcuts. Completion records
  your review, not independently verified microphone use.
- Web-app practice creates an isolated demo entry, opens a local preview,
  and requires removing the entry. It does **not** install a desktop launcher,
  contact a website, or modify an existing app. Unfinished demo entries are
  removed when the helper closes.
- Transcoding uses `ffmpeg` to generate a harmless clip and a separate,
  measurably smaller MP4. Play both and compare quality before completing.
- Sharing prepares a harmless local note and requires reviewing its contents
  and intended demo recipient. It never contacts devices, sends files, or
  reports confirmed delivery.

The extended exercises retain their own artifacts under
`.learn-omarchy-practice/` in the launch directory; exact paths appear in the
exercise. You can remove those artifacts after reviewing them. Capture uses
`XDG_RUNTIME_DIR` when available, otherwise the same local artifact directory.
Missing tools produce a retry/skip explanation; nothing is installed
automatically. Closing an exercise stops only its own helper and child processes.

Activity changes cross-fade the outgoing instruction and controls into the
next success or teaching state. Highlights appear before the coach arrives,
track the affected window or panel, and keep a minimum visible dwell time.
Transitions use a gentler fade and settling pause, with a short breath after
completion narration before advancing automatically.
With speech off, automatic dwell also accounts for the amount of text to read.
Workspace highlights emphasize the destination indicator. Panels use a measured
card rectangle or a measured corresponding bar button. Bar-button outlines say
**Panel button**, not **Panel opened**. When only the button's position is known,
the coach stays beside the lesson rather than covering the popup beneath it.
Unmeasured cards don't receive guessed pointers. Closing a window doesn't leave a stale outline
or a pointer aimed at empty space. Workspace activities
also verify that Hyprland's focused workspace actually changed before reporting
success. Missing narration leaves the written lesson available instead of
ending the activity.

Ohm coaches each activity alongside the existing keycap feedback. He flies
into position when a step begins, talks with narration, reacts to correct and
incorrect keys, celebrates completed shortcuts, and flies toward the controls
while a requested Help action runs immediately. He waits beside the keycaps during
an activity, follows selected cards in the lesson picker, and travels to the
configured target after a shortcut succeeds. Scrolling the picker advances
through lessons in order and keeps the selected row in view; cards moving
under a stationary pointer don't change the selection. He points right toward
the selected card using a short vertical pointing-pose transition. Click Ohm for a
reaction, or drag him to another position and release him to let gravity return
him to the lower screen boundary.
Completion guidance scales and positions Ohm from the available screen
space, keeps him outside the target, and points at its vertical center. Travel
uses distance-based easing. Settled and
pointing poses hover by a few pixels with smaller animated boot flames, blink
periodically, and a brief leveling pause keeps coaching and pointing
from snapping into place. Takeoffs and landings squash and stretch slightly,
and a short trail of fading pixels follows each flight. Coaches travel in
their flying pose facing the direction of travel, land in the standing pose,
and keep speech independent of the pointing pose. At
module completion, Ohm flies beside the summary panel before celebrating.
Reliable targets use a small reticle. Outlines appear for measured windows,
panels, bar buttons, and workspace indicators; unknown panel bounds don't add a
second border. Coaches retain a readable minimum size, with a short connector
when pointing upward at a workspace indicator.
On smaller screens the coach parks above the teaching
panel instead of covering it. Set
`LEARN_OMARCHY_REDUCED_MOTION=1` before launching to keep the character
feedback while disabling nonessential movement.

The character preview lab uses the same sprite renderer as the course. Use
`./bin/hexon-lab` to inspect both coaches, pose transitions, speech, facing,
scales, backgrounds, and landmark alignment without running lesson actions.

Narration production uses a shared local normalization pipeline:

```bash
npm run audio:normalize
```

This requires ffmpeg and ffprobe. It targets -20 LUFS with true-peak headroom,
preserves the mono MP3 format, and records hashes and measurements so unchanged
exports aren't re-encoded. See [audio/README.md](audio/README.md) for generation
fingerprints, source provenance, and export details.

For a running course, `qs ipc -p app call learn audioLog` returns a bounded,
read-only history of actual narration starts, finishes, interruptions, paths,
and exit codes. It reports playback, not merely that an MP3 exists.

## Install

The current testing candidate is **0.1.0-rc.5**, not a stable release.
See [candidate notes](packaging/RELEASE-NOTES.md) for
compatibility and [release acceptance](packaging/ACCEPTANCE.md) for remaining
desktop/hardware checks. Download availability follows repository access:
releases in a private repository are not public downloads, and draft releases
are not published downloads. The repository is currently private and release
creation produces drafts only. Public testing requires an explicit visibility
and prerelease-publication decision; there is no public one-line installer yet.

Learn Omarchy is one package containing the application, both coaches, recorded
narration, and the read-only desktop integration. Install it and open the app:
there's no separate plugin download, Enable button, or setup command.

On launch, the app prepares the bundled integration for the current account
and updates it when the package contains a newer version. An already-current,
active integration isn't reinstalled or reloaded. User-edited or conflicting
plugin files are preserved; a visible notice explains if precise pointing
is temporarily unavailable, and the next launch retries automatically.

### Build and install directly from GitHub

This works for collaborators with repository access before a release is public.
Use your normal GitHub authentication; do not paste tokens into commands.
Use an updated Omarchy desktop, not a vanilla Arch installation. Run the
following as your regular user; pacman requests permission when needed:

```bash
sudo pacman -S --needed base-devel git nodejs
git clone https://github.com/DanWahlin/learn-omarchy.git
cd learn-omarchy
node tools/prepare-checkout-package.mjs --output release-work/local
cd release-work/local
# Read PKGBUILD before executing a build from any repository.
makepkg --syncdeps --install
/usr/bin/learn-omarchy
```

The preparation command uses the exact committed checkout, records its commit
and source SHA256 in `CHECKOUT-INFO.json`, and excludes untracked files.
Tracked changes must be committed or stashed first. It refuses to overwrite an
existing output directory; choose a new `--output` directory for a later build.
It prints an equivalent build command with the source timestamp for reproducibility.
No `npm install`, Azure account, speech generation, or separate plugin package
is needed. Preparation does not install anything; `makepkg --syncdeps --install`
explicitly resolves dependencies and installs the finished package.

For updates, pull the desired trusted commit and prepare a new output directory,
then build/install again. GitHub-installed candidates do not acquire automatic
package-repository updates until Learn Omarchy is accepted into a repository.

### Install a downloaded release package

When a testing prerelease is published and you have access, download these two
assets from the **same release** on the [Releases page](https://github.com/DanWahlin/learn-omarchy/releases):
`learn-omarchy-0.1.0rc5-1-any.pkg.tar.zst` and `SHA256SUMS`.
Do not use GitHub's automatic "Source code" downloads as binary packages.

```bash
PACKAGE=learn-omarchy-0.1.0rc5-1-any.pkg.tar.zst
awk -v file="$PACKAGE" '$2 == file {print}' SHA256SUMS | sha256sum --check --strict &&
  sudo pacman -U "./$PACKAGE"
```

The check must report that exact package as `OK`; installation is chained to
its success. Checksums detect changed download bytes, not publisher identity.
Only download from the intended repository/release. Open **Learn Omarchy**
from Apps or run `/usr/bin/learn-omarchy`.

Required lesson dependencies are installed with the package. OCR, QR, dictation,
and activity-monitor tools are optional; missing tools offer a retry or Skip.
The current native window exercises support configured Ghostty/Foot terminals
and Chrome/Chromium browsers. Other choices are not replaced: unsupported
adapters show recovery/Skip instead of taking control of an existing window.
Customized bars may provide approximate rather than individual workspace-pill
highlights. See the candidate notes for the remaining desktop acceptance limits.

### Unmanaged source and development shortcuts

To put this checkout in Omarchy's Apps menu without copying it anywhere:

```bash
make dev-launcher
```

That writes a user desktop entry whose `Exec` points at `bin/learn-omarchy`
in the repository, plus the app icon, so edits apply on the next launch.
`make dev-launcher-remove` takes it out again.
Remove that development entry before switching to a package installation;
otherwise its user-level Apps entry can still launch the checkout. Calling
`/usr/bin/learn-omarchy` explicitly always selects the system package.

For an unmanaged, one-user copy (dependencies are not resolved for you):

```bash
make install PREFIX="$HOME/.local"
```

Ensure `~/.local/bin` is on `PATH`, then run `learn-omarchy` or open **Learn
Omarchy** from the Apps menu.

To build a package from a trusted, existing versioned source archive:

```bash
node tools/prepare-release.mjs --check
node tools/prepare-release.mjs --archive /path/to/learn-omarchy-VERSION.tar.gz --output /path/to/new-build-directory
cd /path/to/new-build-directory
makepkg --cleanbuild
```

Preparation validates the archive's licensing and bundled integration, computes
its real checksum, and generates `PKGBUILD` and `.SRCINFO`. It doesn't publish
or install anything. See [packaging/RELEASING.md](packaging/RELEASING.md) for
tagged-source preparation, dependencies, reproducibility, and removal.
To uninstall the Arch package and its unchanged integration for your account,
run `learn-omarchy --uninstall` as your regular user from a terminal.

Branch and pull-request CI run the regression, QML, audio, and licensing checks.
Version tags additionally build and verify one package, then create a draft
prerelease with checksums. See [packaging/CI.md](packaging/CI.md); stable
publication remains a separate acceptance decision.

Progress is stored at:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/learn-omarchy/progress.json
```

## Course metadata

Steps may include a `practicePrompt`: a short, single-paragraph goal of at most
240 characters that identifies the task without giving away its shortcut.
Practice mode shows it until a hint is requested. All bundled shortcut steps
provide one; external courses that omit it retain the full instruction instead
of substituting a Help-button label. These recall prompts are shown as text;
Replay continues to use the existing narrated instruction.

Courses use schema version 2:

Activities can supply an optional `note`: one short paragraph, at most 140
characters, displayed below the keys or action button. Use it for a useful
definition, reassurance, or essential caution. Keep longer explanations in
`detail`, which learners open with Details. Notes aren't separate narration.

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

The following completion detectors are supported:

- `hyprland-layer-open` waits for a matching Wayland layer namespace, such as
  `omarchy-menu` or `omarchy-clipboard`.
- `narration-complete` is used by tour steps (`"kind": "tour"`). HEXON flies to
  the step's highlight, shows the instruction as a caption beneath him, plays
  the narration, and advances `delayMs` after it ends. With narration muted or
  unavailable, `durationMs` and a text-length-based reading time provide the
  minimum dwell. Automatic advancement can be disabled. Enter continues a
  tour step early. A tour step with `"pose": "talk"` flies HEXON to the
  highlight's center and animates his mouth instead of pointing, which the
  tour uses for its welcome. Pointing stops draw a pulsing rectangle around the highlight;
  a highlight with `"dynamic": "workspaces"` sizes itself from the number of
  workspace pills the bar is showing.
- `hyprland-window-activated` waits for an application window to open or gain
  focus, which verifies global launch shortcuts even when Hyprland consumes the
  final key. An optional, case-insensitive `appIdPattern` restricts the accepted
  application class. A focus-only change counts
  only after the expected modifier keys were observed or a Help action ran, and
  only for a window other than the one that was active when the step began.
  The window's exact geometry is read from `hyprctl clients -j` in logical
  coordinates, retried briefly while Hyprland finishes tiling, and refreshed
  throughout the result display. Tutorial ownership also requires verifying the
  compositor-reported process's `/proc/PID/environ` for the per-launch
  `LEARN_OMARCHY_WINDOW_TOKEN`. An existing app instance that doesn't inherit
  this token is never granted permission for window-changing actions.
  An optional step-level `windowSize: { "width": 1200, "height": 640 }`
  gives a newly owned activity window a readable floating size near the top
  of its display. Ownership is checked before resizing, and the resulting
  geometry is checked before the activity completes. This is used for the
  activity monitor so a crowded tiled workspace can't hide its statistics.
- `hyprland-event` waits for one of the named `events`, optionally filtered by
  `dataPattern`. For window actions, set `target: "tutorial-window"` and put
  `windowFromStep` on the activity to reference an earlier launch in the same
  module. Optional `windowState` verifies `focused`, `floating`, `fullscreen`,
  and/or `workspace` against the actual client. Close activities match the exact
  address instead; they can't query a client that has already closed.
- `hyprland-workspace-change` observes a change from the starting workspace.
- `hyprland-workspace-is` waits for a specific workspace `id`; an already
  satisfied prerequisite is recorded as introduced and passed over.
- `action-success` waits for the configured command to exit successfully,
  then applies an optional `delayMs` before highlighting.
- `practice-result` is exclusive to `"kind": "practice"`. Set `practice` to
  `app-search`, `clipboard`, `capture`, `screen-lock`, `compose`,
  `screen-recording`, `ocr`, `qr`, `dictation`, `web-app`, `transcode`, or
  `sharing`, `keys` to `[]`, and
  supply an `actionLabel`. The embedded session must report a verified result
  for that mode; the nonvisual app-search runner instead exits successfully with
  one verified result. Practice steps can't supply arbitrary Help,
  cleanup, or window-target commands.

Lessons and individual activities accept `"optional": true`. For an owned
window, `windowState.specialWorkspace: "scratchpad"` verifies placement even
while hidden. Add `specialVisible: true` or `false` to verify that the named
scratchpad is actually shown or hidden on that window's monitor. An empty
scratchpad or an unrelated special-workspace event never satisfies this check.
A swap uses `swapWithStep` to reference a second earlier launch,
`windowState.swapped: true`, and `{peerWindow}` in its command. Both windows'
positions must exchange; an unrelated focus event doesn't count. Directional
focus uses `directionFromStep` for its starting window and `windowFromStep`
for its destination. Directional activities declare one arrow; the displayed
and accepted arrow is resolved from the owned windows' measured positions.

Set `actionLabel` on a step to replace shortcut keycaps with a large action
button. This works well for nested menu activities where asking a learner to
press a shortcut would be misleading.

Shortcut labels use canonical uppercase names. Supported labels are `SUPER`,
`ALT`, `CTRL`, `SHIFT`, `SPACE`, `RETURN`, `TAB`, `ESCAPE`, `LEFT`, `RIGHT`,
`UP`, `DOWN`, individual letters and
digits, plus `+` as a visual separator.

`cleanup` runs before advancing, skipping, returning to Topics, or restarting a
module. It should close any surface or undo any temporary state introduced by
the activity. Both Help and cleanup can use `{tutorialWindow}` with an explicit
`windowFromStep`. A missing owned window never falls back to the focused window.

### Highlight geometry

Highlight values use Wayland logical pixels. Quickshell applies each monitor's
scale automatically. Measured targets account for monitor offsets, fractional
scaling, rotation, and the overlay's current size. Window measurements refresh
while highlighted, including the monitor's resolution and scale, and are clipped
to the visible part of that screen.

Configured `x` and `y` values are offsets from the selected anchor in a reference
viewport, not fixed physical pixels. The default reference is 1920 by 1200 logical
pixels. A course can override it with `"referenceViewport": { "width": 1280,
"height": 720 }`. Fallback dimensions and offsets scale to the current screen;
circles stay circular. These areas are labeled **Estimated area**, and estimated
workspace cells are marked **(estimated)** rather than given a precise pointer.

Optional `target` values are `window`, `panel`, and `workspace`. Window and panel
targets use compositor geometry when available; closed-window results suppress
their former bounds. Workspace targets can supply `workspaceId` (1 through 10),
otherwise they follow the active workspace. Configured geometry remains a
fallback for tour and workspace guidance, not a claim that an unmeasured
fullscreen panel layer reveals the visible card's bounds.

`barWidgets` can name one or more Omarchy widget IDs, such as
`["omarchy.menu", "omarchy.workspaces"]`. The companion `learn-omarchy.geometry`
service provides fresh measurements tagged with the screen's connector name and
logical dimensions. Each overlay uses only its own screen's records, even when
two monitors have identical resolutions. Exact workspace-cell bounds take
precedence over subdivision of the workspace widget; subdivisions remain
explicitly estimated.

The service also measures the visible stock Omarchy menu card from its live
content item, rather than using the transparent fullscreen layer. The opening
tour points to that card after Super + Space, then closes it and introduces the
bar icon in a separate narrated stop. Unsupported menu layouts remain unmeasured
instead of redirecting the opening step to the icon.

The launcher automatically prepares `learn-omarchy.geometry` under
`~/.config/omarchy/plugins` using Omarchy's plugin manager. No separate user
installation or activation is needed. It doesn't modify packaged Omarchy
files or your bar layout. The helper refuses to overwrite an unrelated plugin
or locally edited provider files. Clean upgrades preserve the previous version
and use content-addressed component paths, so Omarchy can load the new code
without restarting the desktop shell.

For troubleshooting only, `npm run geometry:install` runs the same bundled
helper from a checkout. Installed copies include
`tools/install-geometry-provider.mjs`; normal users don't need to run it.

For an Arch-package installation, run `learn-omarchy --uninstall` from a terminal
as your regular user. It requests package-removal permission and retains
pacman's confirmation, then removes the unchanged managed companion for that
account through Omarchy's supported removal command. Cancelling package
removal leaves the integration alone. Progress, backups, and user-edited or
unrelated plugin files are preserved; other users' configuration isn't touched.

For source installations or advanced cleanup, `learn-omarchy --remove-integration`
removes only the unchanged managed companion. Opening the app again
automatically restores it.

Omarchy 4.0.3 gives third-party services a restricted facade without live widget
slots. On a single monitor, the runtime combines `debugBarGeometry` widget
measurements with the live Hyprland bar layer to account for top, bottom, left,
and right placement. Customized widgets exposed by that API remain measurable.
The helper rejects ambiguous, hidden, out-of-bounds, and changing layouts.

Individual workspace pills are still estimates when the host exposes only the
workspace group's bounds. Untagged widget records are never assigned to an
output by guessing their order, so multi-monitor precision requires the
monitor-aware companion API. Custom bar implementations without measured widget
records also retain explicit estimates. Full support needs a host-provided,
read-only geometry API; the app never traverses restricted plugin internals or
changes packaged Omarchy files. Display changes invalidate cached measurements
and in-flight results. The service is probed periodically.

The coach parks inside the desktop, clear of the bar and its tooltip space.
First-run setup hides pack-maintenance controls; **Refresh coaches** and pack
diagnostics remain in Settings. Desktop-integration notices use plain language,
while detailed startup errors remain in terminal output.

Supported anchors are `top-left`, `top`, `top-right`, `left`, `center`,
`right`, `bottom-left`, `bottom`, and `bottom-right`. Highlights are clamped
inside the selected screen.

`shape` can be `rectangle` or `circle`; circles require equal width and height.
The active Omarchy theme provides the border, foreground, background, muted,
and instruction colors from:

```text
~/.local/state/omarchy/current/theme/colors.toml
```

The main UI and open practice windows share a live theme loader. Buttons,
captions, text fields, dropdowns, selection highlights, tooltips, sliders, and
scrollbars use the same palette, including focus and disabled states. Text
contrast is adjusted when needed for light or dark themes; character artwork
and the exercise's sample images keep their original colors. If theme colors
can't be read, the app reports the problem and uses a readable fallback palette.

### Narration

Narration begins with each activity and stops during transitions or when the
app exits. An optional `completionAudio` file narrates the activity's
`completionMessage` while HEXON points at the result; the next activity
starts shortly after it finishes, or right away on Enter. MP3, Opus, Ogg, FLAC, and WAV work through mpv. Audio paths must be
safe paths relative to the course file.

The repository includes separate MP3 tracks for both coaches. Current generation
uses the configured Azure HD Andrew voice for Ohm and Ada for OLLIE. To
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
each pack's `character.json` names `narration.voices.azure` (Ohm uses Andrew,
OLLIE uses Ada, both HD voices) and `narration.voices.edge`.
`LEARN_OMARCHY_TTS_VOICE` overrides both. With no `--character` flag, bundled
packs with `narration.mode: "own"` are generated. Borrowed and silent packs don't
need voice generation. "Omarchy" is respelled for the
voice as "Omaachi" (oh-MAH-chee); set `LEARN_OMARCHY_PRONUNCIATION` to try
another spelling, then regenerate just the lines that mention it:

```bash
LEARN_OMARCHY_PRONUNCIATION=Omaachi \
node --experimental-strip-types tools/generate-course-audio.ts \
  courses/omarchy-basics.json --backend azure --match Omarchy --character owl
```

Generate missing or stale files, or choose another voice. Files without a matching
generation fingerprint aren't treated as fresh; use `--steps` to limit a revision:

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

On startup, a short illustrated splash features Ohm flying beside a tiled
desktop, with Ollie perched on its corner. It preserves the original poster
composition with magenta accents and magenta/cyan boot flames matching the
characters. The artwork fits the screen without cropping, against a dark navy
background independent of the desktop theme. Both mascots appear as app branding;
the selected coach still controls the entrance and lessons. If the image cannot
load, a neutral title remains visible and the app logs a warning.
Once the app is ready, the splash fades out over 650 ms, then the first scene
fades in over 750 ms. This applies to the lesson picker, first-run coach picker,
and either character's entrance. Intro reveals wait for the first playable
frame so loading doesn't consume the fade. Click, Enter, Space, or Escape
starts the transition early; reduced motion skips both the display delay and
fades. The splash doesn't start a lesson or change the selected coach.

Ohm-1 (pronounced "Ohm") is the default coach, with pack ID `ohm-1`, assets under
`assets/characters/ohm-1/`, and narration under `courses/audio/ohm-1/`. The
`HEXON` token in course text is replaced with the selected coach's display name.
An optional `spokenName` supplies a different name to narration generation:
Ohm-1 displays as `Ohm-1` and uses `Ohm` as his spoken short name.
His welcome says, "Hi! I'm Ohm-1, but you can call me Ohm for short."
`courses/welcome.json` supports character-specific `instructions` keyed by pack
ID; other coaches use the shared `instruction`. Captions and audio generation
select the same greeting.
On first launch a "Choose your coach" screen
shows every character side by side; pick with the arrow keys or the mouse and
confirm with Enter. The choice is saved to
`~/.local/state/learn-omarchy/settings.json`. The Settings button in the toolbar
lets you switch coaches and
reset progress (Show reset options, Reset Progress, then Confirm Reset, or press R twice).
The confirmation stays open until confirmed, cancelled, or Settings is closed.
A confirmed reset clears every module
checkmark and the coach choice, so closing Settings asks for a coach again
and then replays the welcome, like a fresh install. An explicit character
override skips the coach picker but still replays the welcome after Done.
The module picker normally
selects unfinished core modules before optional ones, so the coach points at what's next.

Characters are **data-only packs**. The bundled catalog at
`assets/characters/index.json` reserves the official `ohm-1` and `owl` IDs.
Community packs are discovered from
`${XDG_DATA_HOME:-$HOME/.local/share}/learn-omarchy/characters/<id>/`; they don't
need a catalog edit, sudo, or changes to the application. Bundled IDs can't be
overridden by community packs.

Each pack's `character.json` declares its format version, metadata, licensing,
preview, explicit sprite paths/frame metadata, pose registration, effects,
narration policy, and optional declarative intro sequence. The shared loader
checks assets and bounds before exposing a pack to either the course or lab.
Invalid packs are skipped with diagnostics; a missing saved selection falls
back to an available pack with a notice.

The v1 renderer uses a documented 224×192 canvas. Pointing landmarks, speech
crops, and flame sockets use registered pose geometry, including mirrored
facing. Both the course and lab use `app/CharacterSprite.qml` and the same
`app/IntroPlayer.qml`. Rocket/tree assets and choreography belong to the
official packs, not character-specific branches in the tour controller.

See [Character packs](docs/character-packs.md) for the format, safe installation,
validation, starter pack, narration options, and contribution workflow.
[Declarative intros](docs/character-intros.md) documents the bounded action
vocabulary and viewport-relative layout.

A launch flag overrides the saved choice and skips the picker:

```bash
./bin/learn-omarchy --character owl
```

Graphics-only contributions can use silent narration or borrow an official
audio set. Borrowed clips that name the original coach are intentionally omitted:
the selected character's text stays visible and the normal reading-time fallback
applies. Ohm and OLLIE retain their existing voices and audio-set directories.

**Licensing:** Application code and technical documentation use the
[MIT license](LICENSE). Original artwork and course content, including Ohm-1
and Ollie by Dan Wahlin, use [CC BY 4.0](LICENSE-ASSETS.md). The bird recording
and Spark's example artwork retain their separately declared CC0 terms.

### Trusted repository artwork tools

Finished JSON and PNG files are sufficient to create a pack. No image-generation
service, credentials, paid tools, or build step is required. The following
pipeline is optional authoring machinery for trusted repository development,
not a runtime pack format. It sources `sprites.conf` as executable Bash; never
run it on an untrusted contribution. Runtime discovery and installation don't
source that file or copy `concepts/` into installed packs.

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
multi-frame flight strip declared by `sprites.flight` in `character.json`;
those characters fly with their wings instead of HEXON's boot flames. Displayed text that names HEXON switches to the selected
character's display name automatically.
OLLIE's `talk_face_mask` excludes neighboring eye pixels from the animated
beak. Preparation also creates an eye-free `owl-speech.png` strip, registered
at native pixel size to each pointing pose so the original beak doesn't show
around its edges.

## Character lab

The standalone character lab discovers official and user-installed packs through
the same loader as the course, independently from lesson actions:

```bash
./bin/hexon-lab
./bin/hexon-lab owl
```

Use the labeled controls to switch coaches, idle/talk/point/up-point poses,
flight, and the teaching sequence. Preview/replay or stop a pack's full intro,
refresh pack discovery, and inspect validation diagnostics. Speech and facing are independent controls.
Choose a light, dark, or checkerboard background, inspect registered landmarks,
adjust scale, or enable reduced motion. Space pauses or resumes; Left/Right
scrub individual frames; Escape closes the lab.

The root `character-lab.qml` entrypoint keeps the shared renderer inside
Quickshell's configuration boundary. IPC uses that same entrypoint:

```bash
qs ipc -p character-lab.qml call hexon-lab status
```

The generated concept art is under `assets/characters/ohm-1/concepts/`.
Normalized runtime assets are under `assets/characters/ohm-1/sprites/`.
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
| `app/CharacterSprite.qml` | Shared registered pose and speech renderer |
| `app/CharacterPackStore.qml` | Shared validated discovery and selection bridge |
| `app/IntroPlayer.qml` | Bounded declarative scenery and character choreography |
| `assets/characters/` | Official character packs; trusted authoring files aren't installed |
| `examples/characters/spark/` | Original graphics-only starter pack |
| `docs/character-packs.md` | Public pack format and contribution workflow |
| `docs/character-intros.md` | Intro actions, coordinates, and lifecycle |
| `courses/` | Editable curriculum and packaged narration |
| `experiments/hexon-lab/` | Standalone sprite and movement test surface |
| `character-lab.qml` | Lab entrypoint with access to the shared renderer |
| `src/course.ts` | Schema-v2 types and runtime validator |
| `src/character-packs.ts` | Shared safe pack discovery, resolution, and validation |
| `tools/character-packs.ts` | Offline pack listing and validation CLI |
| `tools/install-character-packs.ts` | Validated runtime-asset packaging |
| `tools/validate-course.ts` | Course validation CLI |
| `tools/generate-course-audio.ts` | Narration generator (Azure Speech or Edge TTS) |
| `tests/` | Metadata and safety tests |
| `bin/` | Repository and installed launchers |
| `packaging/` | Arch Linux package scaffolding |
| `.plans/plan.md` | Architecture, implementation phases, and acceptance criteria |

Learn Omarchy reads Omarchy's theme and desktop state but doesn't modify files
under `/usr/share/omarchy` or the user's Hyprland configuration.
