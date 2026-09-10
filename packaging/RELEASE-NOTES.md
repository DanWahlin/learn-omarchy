# Learn Omarchy 0.1.0-rc.2

**Release candidate for testing, not a stable release.**

Learn Omarchy includes 15 lessons and 91 steps, Ohm-1 and Ollie, and local
word-synchronized narration. One package contains the app and its read-only
desktop integration. No separate plugin setup or speech-service account is
needed.

## Install

On a supported Omarchy system, download the package and `SHA256SUMS` from this
release, then verify the package checksum:

```sh
sha256sum --ignore-missing -c SHA256SUMS
sudo pacman -U ./learn-omarchy-0.1.0rc2-1-any.pkg.tar.zst
/usr/bin/learn-omarchy
```

Confirm that the package filename reports `OK` before installing. Checksums
verify downloaded bytes; they aren't a signing-key authenticity guarantee.
Pacman resolves required dependencies. The launcher prepares the bundled
integration for your account automatically. Audio is bundled for offline use.

For an isolated first-run trial:

```sh
XDG_STATE_HOME="$(mktemp -d /tmp/learn-omarchy-trial.XXXXXX)" /usr/bin/learn-omarchy
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

## Candidate highlights

This candidate replaces the initial draft, fixing GitHub asset-name handling
so the downloadable metadata filenames match `SHA256SUMS`.

- Clear goals throughout shortcut Practice mode; hints reveal instructions and keycaps.
- Welcome mute/unmute no longer replays the current line.
- Service readiness is checked through its own IPC rather than a bar-activation flag.
- Practice exercises stay in the normal coaching panel.
- Owned-window verification protects existing personal terminal/browser windows.
- All 368 narration clips have matching word-timing files.
- Ollie's welcome has short, fading background birdsong.
- Code uses MIT; original artwork/course content uses CC BY 4.0. Separately
  licensed birdsong and example assets retain CC0.

## Compatibility and known limitations

The live development environment is **Omarchy 4.0.2**, Quickshell 0.3.1, Qt
6.11.2, and a scaled single-monitor Hyprland desktop. Package dependency floors
are not claims that older versions have received full desktop acceptance.

Independent terminal launching supports configured Ghostty or Foot instances.
Isolated browser launching supports Chrome or Chromium. Unsupported adapters
show recovery guidance rather than controlling an existing window.

OCR, QR, dictation, and activity-monitor extras may require the optional
dependencies listed by pacman. Lock and microphone activities require an
explicit choice; save work and know your password before trying lock practice.

Clean graphical Omarchy installation, attended lock/microphone testing, and
physical multi-monitor acceptance are still pending. See
`packaging/ACCEPTANCE.md` in the source archive. Report issues with the candidate
version, lesson/step, environment, and reproduction steps; redact private
desktop content from screenshots.
