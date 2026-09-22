# Learn Omarchy 0.2.3

This patch release makes the Capture lesson use Omarchy's real screenshot,
screen-recording, OCR, and QR workflows instead of course-owned simulations.

Learn Omarchy includes 16 lessons, 93 activities, the guides Ohm-1 and Ollie,
offline narration, and read-only desktop integration in one package.

## Install

Requires an up-to-date **Omarchy 4.0.3 or newer** desktop.

Download `learn-omarchy-0.2.3-1-any.pkg.tar.zst` from this release, then run:

```sh
sudo pacman -U ./learn-omarchy-0.2.3-1-any.pkg.tar.zst
learn-omarchy
```

To verify the download first, place `SHA256SUMS` in the same directory and run:

```sh
sha256sum --check --ignore-missing SHA256SUMS
```

## Fixed

- Screen Recording now guides learners through `Super+Ctrl+C`, Screenrecord,
  With no audio, and Stop Screenrecording while observing the real native
  recording and requiring successful playback.
- OCR and QR practice now use Omarchy's native Text and QR Code capture tools,
  with completion based on pasting the harmless clipboard result.
- Removed the simulated Select, Start, Stop, Extract, Decode, and Copy controls
  from those Capture exercises.
- Added stable native recording detection, active-recording isolation, retake
  support, compact layouts, and end-to-end watcher/playback automation.
- Improved Clipboard, Compose, Screenshot, narration callouts, responsive
  practice surfaces, and exercise completion guidance.
- Development installs now use a distinct desktop-file ID, allowing packaged
  **Learn Omarchy** and **Learn Omarchy Local** launchers to coexist.

## Included from 0.2

- Three Shortcut Arcade games: Window Rescue, Shortcut Sprint, and Keyfall.
- Correctly packaged Window Rescue ship and planet artwork.
- Non-punitive hints, fair same-deck Sprint replays, and targeted practice.
- Simplified lesson and completion screens.
- Improved responsive character pointing and keyboard capture.
- Current Omarchy theme and wallpaper support throughout Arcade.
- Hardened progress migration, retention, reset, and corrupt-file handling.
- All 394 narration clips with matching validated word timings.

## Remove

Close the app, then run:

```sh
/usr/bin/learn-omarchy --uninstall
```

Managed integration cleanup preserves progress, settings, backups, and
user-edited files.

## Compatibility notes

All attached assets were built and verified from the `v0.2.3` tag.

Hyprland exposes monitor, window, and layer geometry, but Omarchy 4.0.3 does not
provide third-party plugins with every internal bar-widget or popup rectangle.
Learn Omarchy uses measured geometry where available and responsive estimates
where needed.

OCR, QR, dictation, and activity-monitor exercises may require optional
dependencies listed by pacman. Lock and microphone activities require an
explicit choice.
