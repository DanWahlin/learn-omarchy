# Release acceptance

The first candidate is **0.1.0-rc.1** (Arch version **0.1.0rc1**).
It is not a stable release. CI and packaging checks do not establish that every
desktop, hardware device, or installed Omarchy version behaves correctly.

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

The development desktop is Omarchy 4.0.2 with Quickshell 0.3.1 and Qt 6.11.2.
Prior live testing covered both coaches, native actions, safe practice exercises,
and the scaled laptop display. The reported installation-status, welcome
audio-toggle, and practice-goal defects have regression coverage.

The clean Arch CI environment verifies builds, isolated lifecycle tests, QML
offscreen rendering, and extracted package contents. It does **not** run a clean
graphical Omarchy desktop. Mocked integration commands prove installer control
flow, not compatibility with a real shell.

A clean graphical Omarchy installation, attended lock/microphone validation,
and physical multi-monitor acceptance remain outstanding. The draft candidate
must not be promoted to stable on the basis of automated checks alone.

No private screenshots, learner state, recordings, or developer credentials
belong in release assets. Keep detailed private QA evidence outside the source
archive. Publish only the package, source archive, build metadata/checksums, and
public release notes.
