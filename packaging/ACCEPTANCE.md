# Release acceptance

The current release is **0.1.0** (Arch version **0.1.0**), an early public
release. CI and packaging checks do not establish that every
desktop, hardware device, or installed Omarchy version behaves correctly.

## Testing-prerelease distribution gates

Before publishing a **testing prerelease**, require green exact-tag CI,
license/audio checks, verified package contents, downloadable assets with
matching checksums, current installation/removal instructions, and explicit
compatibility/known-limitations notes. Confirm intended repository access:
an unpublished draft or private repository is not a public download.

Graphical/hardware gates below may remain pending for an explicitly labeled
testing prerelease only when those limitations are disclosed. Publishing a
candidate does not approve stable promotion or the Omarchy package PR.

## Stable-release gates

Record the tested source commit, package SHA256, Omarchy/Hyprland/Quickshell
versions, display scale, tester, and date with each result. Retest changed
behavior after fixes. Never mark a gate passed based on an older package.

| Gate | Evidence required before a stable release |
| --- | --- |
| Exact artifact | Tests and license/audio checks pass on the tagged source; packaged files match that source; retain source/package checksums. |
| Clean Omarchy install | Install the candidate on a fresh supported Omarchy desktop without the repository, development dependencies, or pre-existing companion. Opening the app must prepare precise pointing automatically. |
| Offline use | Disconnect the test environment from the network after installation. Both coaches, captions, narration, and local exercises still work. |
| Upgrade/removal | Reopening leaves the companion untouched; upgrading updates only managed files. Cancelled uninstall leaves it available. Successful uninstall preserves progress and user changes. |
| Welcome | Both coaches complete their entrance and controls explanation. Mute stops speech; unmute doesn't replay or rewind the current line. Birds fade out after about ten seconds. |
| Practice | Complete Workspaces, choose Practice, and verify every task states its goal. H/Details reveals the shortcut without executing it. |
| Windows | Terminal/browser launch, workspace/scratchpad, and finale chains work while personal windows remain open and untouched. |
| Reading/layout | Normal and 130% text, muted reading, reduced motion, and a second screen size remain readable; panels and navigation stay on screen. |
| Attended optional tools | A tester explicitly chooses lock/unlock and microphone dictation, saves work first, and verifies recovery. No unattended locking or recording. |
| Multi-monitor | Test mixed scaling and focus/display changes, or explicitly restrict the stable support statement to tested single-monitor setups. |

## Current evidence and limitations

The latest development acceptance run was performed on 2026-09-11 against base
commit `ff079ca` plus the current uncommitted reset, narration, caption, course,
and test changes. This is evidence for the working tree, not a releasable tagged
artifact. The desktop used Omarchy 4.0.3-1, omarchy-settings 4.0.3-1, Hyprland
0.56.2-2, Quickshell 0.3.1-1, Qt 6.11.2-3, and MPV 0.41.0-6 on one 3072x1920
display at 1.6 scale.

The fresh isolated-state live run persisted outcomes for all 101 activities and
all 17 lessons across an app restart: 72 practiced, 24 introduced with live
narration and target presentation, and 5 explicitly skipped. Sixty-two
shortcut-driven activities completed through real input and reported a verified
result. Ninety-nine sampled lesson states had matching word timings, advancing
playback positions, and progressive caption offsets. The run retained the exact
three personal windows present before testing and left no additional window.
Detailed screenshots, event logs, and final state remain outside the repository
in the private session artifacts.

The five skips were the split and split-restore activities on the tester's
non-dwindle custom layout, Compose on a keyboard where Caps Lock is not Compose,
screen lock, and microphone dictation. The course now treats Compose as optional
when mappings differ, and treats the Power panel as optional on battery-less
systems. Physical lock/unlock and spoken dictation still require an attended
tester. Split behavior remains covered by automated owned-window tests but was
not physically exercised on this custom layout.

An activity-by-activity source audit compared all 101 activities and all 66
explicit course chords with installed Omarchy 4.0.3 and upstream tag `v4.0.3`.
All 66 chords matched. The audit found and corrected two content issues: Power
is unavailable without a battery, and screenshot Control+Enter captures the
focused monitor rather than the entire multi-monitor desktop. The printable
reference was regenerated from those corrections. Customized bars can still
lack precise workspace-pill geometry.

Final working-tree checks passed: 478 Node tests, 258 QML tests with 4
platform-dependent skips, course validation for 17 lessons and 101 activities,
both bundled character packs, all 400 narration recordings and word timings,
printable-reference freshness, and release licensing metadata.

The clean Arch CI environment verifies builds, isolated lifecycle tests, QML
offscreen rendering, and extracted package contents. It does **not** run a clean
graphical Omarchy desktop. Mocked integration commands prove installer control
flow, not compatibility with a real shell.

A clean graphical package installation without the repository, offline use,
upgrade/removal, attended lock/microphone validation, a dwindle-layout split
run, and physical multi-monitor acceptance remain outstanding. The draft
candidate must not be promoted to stable on the basis of this working-tree run.

No private screenshots, learner state, recordings, or developer credentials
belong in release assets. Keep detailed private QA evidence outside the source
archive. Publish only the package, source archive, build metadata/checksums, and
public release notes.
