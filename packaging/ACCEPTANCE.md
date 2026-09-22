# Release acceptance

The current release is **0.2.2** (Arch version **0.2.2**), an early public
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

The 0.2.3 development cycle was exercised on an installed Omarchy desktop on
2026-09-22. Screenshot, screen-recording, OCR, and QR lessons were reviewed
against the installed native Capture menu and commands. The course now observes
native outputs instead of starting or stopping those tools for the learner.
The packaged 0.2.2 upgrade and Apps launcher were also verified locally.

The release gates validate all 16 lessons, 93 activities, both bundled character
packs, 394 narration recordings and word timings, printable-reference freshness,
release licensing metadata, native recording watcher transitions and retakes,
real MP4 playback, and normal/compact QML layouts. The final working-tree run
passed 564 Node tests and 456 QML tests with 4 platform-dependent skips. Record
the exact release commit and packaged-artifact checks in the tagged workflow
evidence.

The clean Arch CI environment verifies builds, isolated lifecycle tests, QML
offscreen rendering, and extracted package contents. It does **not** replace
physical testing of lock/unlock, microphone dictation, mixed-scale monitors, or
every customized Hyprland layout. Those hardware-dependent paths remain
attended or optional and must not be inferred from automated checks.

No private screenshots, learner state, recordings, or developer credentials
belong in release assets. Keep detailed private QA evidence outside the source
archive. Publish only the package, source archive, build metadata/checksums, and
public release notes.
