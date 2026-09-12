# Learn Omarchy 0.1.0

First public release. Still early: expect rough edges, and please report what
confuses you.

Learn Omarchy includes 17 lessons and 101 activities, the guides Ohm-1 and
Ollie, and local recorded narration with validated timing metadata. One package
contains the app and its read-only desktop integration. No separate plugin
setup or speech-service account is needed.

## Install

Requires an updated **Omarchy 4.0.3 or newer** desktop.

Download the package from this release, then install it with pacman:

```sh
sudo pacman -U ./learn-omarchy-0.1.0-1-any.pkg.tar.zst
learn-omarchy
```

To verify the download first, fetch `SHA256SUMS` from this release and run
`sha256sum --check --ignore-missing SHA256SUMS` in the same directory.
Checksums verify downloaded bytes; they aren't a signing-key authenticity
guarantee. Pacman resolves required dependencies. The launcher prepares the
bundled integration for your account automatically. Audio is bundled for
offline use.

For an isolated first-run trial:

```sh
XDG_STATE_HOME="$(mktemp -d /tmp/learn-omarchy-trial.XXXXXX)" learn-omarchy
```

This isolates learning preferences and progress, not the desktop integration.
Use your usual launch command to return to normal progress.

## Remove

Close the app, then run as your regular user from a terminal:

```sh
/usr/bin/learn-omarchy --uninstall
```

Package removal requests permission and confirmation. Managed integration
cleanup preserves progress, settings, backups, and user-edited files. Removing
only the package directly through pacman can leave the user integration behind.

## Highlights

All attached assets are built from the v0.1.0 tag.

- Clear goals throughout shortcut Practice mode; hints reveal instructions and keycaps.
- Welcome mute/unmute no longer replays the current line.
- Service readiness is checked through its own IPC rather than a bar-activation flag.
- Practice exercises stay in the normal coaching panel.
- Owned-window verification protects existing personal terminal/browser windows.
- All 400 narration clips have matching word-timing files.
- Expanded window/notification references, mixed practice, and interaction sounds.
- Illustrated splash with a smooth transition into the first scene.
- Solid text-bearing panels, buttons, captions, and print-return banners.
- Printable reference with 122 entries covering all 17 lessons and 101 activities,
  versioned Omarchy 4.0.3 citations, and complete source/coverage checks.
- Printable Shortcuts moves the course aside for the browser and restores its
  previous Keys state when you return.
- A committed-checkout packaging command for collaborators testing directly from GitHub.
- Ollie's welcome has short, fading background birdsong.
- Progress reset now proves both state files were saved and reports failures.
- Ollie speaks 10% faster while preserving synchronized word timings.
- Captions reveal as the guide speaks instead of appearing all at once.
- Every activity was re-audited against Omarchy 4.0.3; Power availability,
  focused-monitor capture wording, and optional Compose behavior now match the
  actual platform.
- Release validation waits for complete JSON fixture output, eliminating a
  cancellation-test race in the Arch packaging workflow.
- Code uses MIT; original artwork/course content uses CC BY 4.0. Separately
  licensed birdsong and example assets retain CC0.

## Compatibility and known limitations

The live development environment is **Omarchy 4.0.3-1**, Quickshell 0.3.1, Qt
6.11.2, and a scaled single-monitor Hyprland desktop. Package dependency floors
are not claims that older versions have received full desktop acceptance.

Independent terminal launching supports configured Ghostty or Foot instances.
Isolated browser launching supports Chrome or Chromium. Unsupported adapters
show recovery guidance rather than controlling an existing window.

OCR, QR, dictation, and activity-monitor extras may require the optional
dependencies listed by pacman. Lock and microphone activities require an
explicit choice; save work and know your password before trying lock practice.

Clean graphical Omarchy installation, attended lock/microphone testing, and
physical multi-monitor acceptance are still pending. Customized bars may still
use approximate workspace highlights when individual pill geometry is unavailable.
These limits are disclosed, not resolved, in this early release. See
`packaging/ACCEPTANCE.md` in the source archive. Report issues with the release
version, lesson/step, environment, and reproduction steps; redact private
desktop content from screenshots.
