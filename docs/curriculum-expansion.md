# Window practice and retention

## Binding evidence

Read-only inspection on 2026-09-10 found the installed package **`omarchy 4.0.3-1`**
(`pacman -Q omarchy`). `/usr/share/omarchy/version` still contains `4.0.0.alpha`;
the package version and actual Lua definitions, not that stale file, informed this expansion.

Sources:

- `/usr/share/omarchy/default/hypr/bindings/tiling.lua`: `Super+J` dispatches
  `hl.dsp.layout("togglesplit")`; physical codes 20/21 resize by -100/+100 on x,
  or on y with Shift. Alt uses 25 pixels; Control uses 300.
- The same file defines grouping, pop-out, workspace layout, and Super+mouse dragging.
- `/usr/share/omarchy/bin/omarchy-hyprland-window-pop` toggles floating, sizes,
  centers and pins an initially tiled window. Invoking it on a pinned pop-out
  unpins and toggles floating back. Already-floating windows need different care.
- `/usr/share/omarchy/bin/omarchy-hyprland-workspace-layout-toggle` persists a
  dwindle/scrolling rule under `$XDG_STATE_HOME`'s default equivalent,
  `~/.local/state/omarchy/workspace-layouts`. A custom layout is not restored by
  simply toggling twice.
- `/usr/share/omarchy/default/hypr/bindings/utilities.lua` defines comma-based
  notification history, dismissal, invocation, and silencing shortcuts.
- `~/.config/hypr/hyprland.lua` loads defaults followed by personal overrides.
  `~/.config/hypr/bindings.lua` does not replace the added shortcuts. It does
  customize screenshot, recording, and lock-explorer bindings. The user also
  has a custom workspace-layout plugin, so split practice must check the
  current workspace's layout instead of assuming dwindle.

No host settings, window state, notifications, or bindings were changed while
checking these sources.

Read-only public `hyprctl repl` queries additionally confirmed `hl.get_window`
accepts an exact `address:` selector, nonexistent addresses return `nil`, and
`hl.get_active_window()` exposes `address`, `floating`, `fullscreen`, and
`workspace.id`. Split commands assert both targets still exist and remain tiled,
then assert the requested owned window actually received focus before the
active-window-only layout dispatcher runs. A failed focus cannot silently
toggle a different application's split.

## Curriculum and narration

Windows now includes two optional split-direction activities immediately after opening
the two owned terminals, plus width resizing in both directions after floating
the first terminal. These use the existing owned-window execution and outcome
pipeline, not `action-success`. Split outcomes compare the same two windows'
separation axes; resize outcomes compare dimensions in the same workspace,
monitor, floating state, and fullscreen state. A swap, focus event, missing
window, or successful dispatcher exit alone does not count.

Both split activities stay in the core Windows lesson but are optional, so a
scrolling or custom workspace layout does not block core completion or mixed
review eligibility. The runner checks the target workspace's `tiledLayout`;
the global default layout does not establish which layout that workspace uses.
Use Skip when the target workspace is not dwindle. Resizing remains required.

Optional **More window controls** and **Notifications** lessons are read-only
introductions. They do not execute grouping, pinning, layout, mouse, notification,
or silencing commands, and count as **introduced**, not practiced.

Every new instruction, core completion message, and optional lesson wrap-up has
a dedicated recording for each bundled narrating coach. The additions use the
normal Azure speech workflow with word boundaries from the same synthesis,
normalization, production-manifest provenance, and hash-matched timing sidecars.
They do not use text-only exemptions, borrowed recordings, or placeholder paths.
Existing recordings and their spoken text remain untouched. The expansion adds
32 recordings and 32 timing sidecars; all 368 original production entries are
unchanged. Strict audio validation reports 400 current recordings with 400
current word-timing files and no full-text fallback.

The selected public course narration was generated with:

```sh
node --experimental-strip-types tools/generate-course-audio.ts courses/omarchy-basics.json --backend azure --word-timings --missing --steps windows-split,windows-split-restore,windows-resize,windows-resize-back,advanced-window-groups,advanced-window-pop,advanced-window-layout,advanced-window-mouse,notifications-history,notifications-quiet
node --experimental-strip-types tools/generate-course-audio.ts courses/omarchy-basics.json --backend azure --word-timings --missing --wrapups-only --match "You've been introduced to groups"
node --experimental-strip-types tools/generate-course-audio.ts courses/omarchy-basics.json --backend azure --word-timings --missing --wrapups-only --match "You now have a reference"
```

Credential values are never printed or stored in the course. The generator uses
its existing environment-file loader and the voices configured by the bundled
character manifests. Optional reference activities remain introductions even
though their instructions are narrated: listening never counts as performing
grouping, pinning, mouse dragging, or notification actions.

## Mixed practice

`app/Retention.js` provides:

```js
Retention.eligibleLessons(course, stepResults, stepCredits)
Retention.mixedPracticePlan(course, stepResults, stepCredits, 3) // lesson IDs
Retention.lessonIndex(course, lessonId)
```

Only lessons explicitly marked `mixedPractice: true` participate. Initially
these are Menus and apps, Windows, Workspaces, and Clipboard and Compose.
All required activities must have been explored; stored credits remain valid
even if the latest attempt was skipped. Adding a new required activity prevents
that lesson from joining review until it has been explored.

The shuffle selects **whole lesson blocks**, not individual dependent window
activities. It preserves original IDs, launch prerequisites, recovery, cleanup,
Practice prompts, assistance recording, and persistent ID-based progress.
It additionally rejects any embedded exercise other than app-search, clipboard,
or Compose even if a future author accidentally opts an unsafe lesson in.
No locking, microphone, recording, or sharing exercise enters mixed review.
Offer it only after at least two eligible lessons have been explored.

### Shell integration contract

Import `"Retention.js" as Retention`. Keep a `property var mixedPracticeQueue: []`
and a `property bool mixedPracticeActive: false`. A start handler should:

```js
var plan = Retention.mixedPracticePlan(course, stepResults, stepCredits, 3)
if (plan.length < 2) return
mixedPracticeQueue = plan.slice(1)
mixedPracticeActive = true
startLesson(Retention.lessonIndex(course, plan[0]), true, false)
```

The lesson-complete screen can offer **Next mixed lesson**, which shifts the
next ID and calls the same `startLesson(index, true, false)`. Resolve IDs each
time, not stored numeric indexes. Finish or cancel the queue when returning
to the menu, selecting a normal lesson, or completing its last block.
Do not reset the queue inside `resetLessonRuntime()`, because `startLesson()`
uses that function between blocks. Do not auto-dispatch exercises.

The shell's themed `UiButton` controls expose mixed practice and printable
shortcuts in the menu and lesson-complete screens. They include disabled-state
guidance, explicit printable-generation errors, and Enter-key continuation.
The shell generates the printable reference for the active course before
opening the local HTML in a browser; no separate retention UI component is
shipped.

### Window outcome integration contract

Import `"WindowOutcomes.js" as WindowOutcomes`. `WindowState` adds `resized: true`
and `splitChanged: true`; split steps use `pairWithStep` (not directional
`swapWithStep`). Both references must be earlier owned launch steps in the
same lesson.

1. Resolve and revalidate owned client addresses before either a learner-triggered
   action or Help. Include `pairWithStep` in peer resolution without enabling
   directional-arrow logic.
2. Before dispatch, query `hyprctl -j clients`, find those owned addresses, and
   store `WindowOutcomes.capture(client, peer)`. Protect the async snapshot with
   the action generation and step ID. Reset it on cancel/step change.
3. For split, require current workspace `tiledLayout === "dwindle"`, both clients
   tiled, visible, and on the same workspace/monitor, and
   `WindowOutcomes.orientation(before.first, before.peer) !== ""`.
   If these prerequisites fail, show recovery/Skip; do not change layouts or
   touch other windows to make the exercise pass.
4. Execute through the existing protected command and keyboard-release path.
   The split command resolves both owned targets and checks focus atomically
   in the compositor's Lua evaluator immediately before toggling.
5. Poll the existing outcome verifier after dispatch even without a Hyprland
   event: resize and split do not reliably emit a dedicated IPC event. Require
   normal state checks **and** `WindowOutcomes.resized(before.first, client)` or
   `WindowOutcomes.splitChanged(before, client, peer)`. Never complete just
   because the dispatch exited successfully. For geometry activities, reject
   outcome requests and in-flight results while `actionRunning`, while the
   baseline is absent, or after `actionStepId` stops matching the current step.
   This prevents preflight events or a late response after a failed action from
   awarding completion. Split steps also require `focused: true`, routing them
   through the existing keyboard-release path and verifying final target focus.
6. Ignore stale results, retain existing bounded retries/recovery, and require
   ownership throughout. Baselines must be freshly captured on each retry.
7. Add `MINUS`/`EQUAL` canonical UI/key labels for the physical positions (codes
   20/21). US Qt keys are `Qt.Key_Minus`/`Qt.Key_Equal`; do not describe these
   as layout-independent printed symbols. If physical input cannot be matched
   on another layout, Help uses the verified equivalent dispatch.

## Printable reference

The HTML is generated from explicit `references` in each lesson of
`courses/omarchy-basics.json`, not from guided instructions, practice prompts,
or safety notes. Native shortcuts affect the real focused window: the app's
owned-window protections do not apply outside a guided activity.

The course's `reference` metadata names the platform, version, review date and
source catalog. Each source has either an HTTPS `url` or a safe application-relative
`path` for bundled course code. The bundled reference targets **Omarchy 4.0.3**, using
the official release-tagged manual and implementation. Course-specific practice
sources are identified separately. Source links are printed, but no remote
resources are loaded to read or print the document.

Each lesson entry has this shape:

```json
{
  "kind": "chord",
  "keys": ["SUPER", "+", "W"],
  "action": "Close the focused window.",
  "caution": "Save your work first.",
  "stepIds": ["close-terminal"],
  "sourceIds": ["tiling-bindings"]
}
```

`kind` is `chord`, `sequence`, `gesture`, or `workflow`. Source IDs must refer
to the course catalog; activity IDs must belong to that lesson. Coverage is
required for every activity, including embedded exercises and read-only
introductions. Welcome has no activity IDs but still has reference entries.
Group repeated activities within a lesson using `stepIds`; retain useful
shortcuts in each relevant lesson rather than globally deduplicating chords.
An entry is marked optional when all its activities are optional, or its entire
lesson is optional. Optional lessons appear after core lessons.

Compose sequences explicitly distinguish tapping and releasing from holding
a chord. Screenshot-picker and clipboard controls identify their context.
Focus and swap entries use `ARROW`; a guided activity's initial direction is
only a runtime seed. The clipboard entry deliberately follows the 4.0.3
implementation: Enter attempts a paste, while Shift+Enter copies only. The
release's clipboard manual is less precise about this distinction.

Validation rejects missing coverage, unknown activity/source IDs, duplicate
sources, unsafe source URLs and malformed metadata. Regression tests also
compare every taught native chord with its reference, check the previously
omitted skills, and prevent guided-only promises from leaking into print.
Changing a lesson requires reviewing its references and sources, not merely
regenerating HTML. Version changes require another source review.

Legacy custom courses without `reference` metadata remain loadable. Their
generated output is prominently marked unreviewed and potentially incomplete;
it uses explicit legacy `shortcuts` where supplied, and otherwise lists keys
without copying guided instructions or safety assurances. Versioned courses
use lesson references exclusively, not a duplicate `step.shortcuts` table.

```sh
node --experimental-strip-types tools/generate-cheat-sheet.mjs
node --experimental-strip-types tools/generate-cheat-sheet.mjs --check
```

Open `courses/omarchy-shortcuts.html` and select **Print or save as PDF**. The
document is offline, escapes all course text, uses print CSS, and distinguishes
optional activities, sequential inputs, mouse gestures and workflows. Long
lessons can continue across print columns; individual entries stay together.
Its HTML is shipped in the existing `courses`
directory, which `make install` already copies.

`npm run cheatsheet` regenerates the bundled HTML; `npm run check` rejects stale
output. The installer copies both the HTML and generator, so the installed app
can regenerate the same reference. Opening the existing HTML directly does not
need Node or the generator.

## Validation

```sh
node --experimental-strip-types --test tests/course.test.ts tests/curriculum-coverage.test.ts tests/learner-copy.test.ts tests/window-outcomes.test.ts tests/retention.test.ts
node --experimental-strip-types tools/validate-course-audio.ts courses/omarchy-basics.json --require-word-timings
```

Pure-helper tests cover wrong addresses, workspace changes, invalid/missing
geometry, focus-only movement, swap-versus-split, and required narration metadata.
`tests/window-split-command.test.ts` additionally runs the course's actual Lua
split commands against mocked public APIs when the `lua` executable is available;
missing targets, floating/fullscreen windows, mismatched workspaces, and failed
focus cannot reach the layout dispatcher. It never contacts Hyprland.
Shell integration additionally needs protected-dispatch tests covering fresh
snapshots, event-independent polling, stale generations, cancellation, split
layout recovery, mixed queue cancellation, and original ID-based credit.
