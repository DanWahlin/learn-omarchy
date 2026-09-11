# Release acceptance

The current candidate is **0.1.0-rc.3** (Arch version **0.1.0rc3**).
It is not a stable release. CI and packaging checks do not establish that every
desktop, hardware device, or installed Omarchy version behaves correctly.

## Testing-prerelease distribution gates

Keep rc.3 private and unpublished until the owner approves distribution.
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

The development desktop is Omarchy 4.0.3-1 with Quickshell 0.3.1 and Qt 6.11.2.
Prior live testing covered both coaches, native actions, safe practice exercises,
and the scaled laptop display. The reported installation-status, welcome
audio-toggle, and practice-goal defects have regression coverage. Subsequent
live checks reached all 101 activities; physical lock/unlock and spoken dictation
still need attended acceptance. The printable reference is checked against the
official 4.0.3 source and rendered PDF; this does not certify customized physical
key bindings. Customized bars can still lack precise workspace-pill geometry.

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
