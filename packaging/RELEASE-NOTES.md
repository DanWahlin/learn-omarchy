# Learn Omarchy 0.2.2

This patch release makes the Clipboard and Compose exercise easier to follow.

Learn Omarchy includes 17 lessons, 101 activities, the guides Ohm-1 and Ollie,
offline narration, and read-only desktop integration in one package.

## Install

Requires an up-to-date **Omarchy 4.0.3 or newer** desktop.

Download `learn-omarchy-0.2.2-1-any.pkg.tar.zst` from this release, then run:

```sh
sudo pacman -U ./learn-omarchy-0.2.2-1-any.pkg.tar.zst
learn-omarchy
```

To verify the download first, place `SHA256SUMS` in the same directory and run:

```sh
sha256sum --check --ignore-missing SHA256SUMS
```

## Fixed

- Completed clipboard steps collapse into short confirmations.
- Copying the first note automatically reveals and selects the newer note.
- Copying the newer note automatically reveals the clipboard-history step.
- Replaying the exercise reliably returns to the first note with an empty
  destination field.
- Added compact-layout coverage to keep each next step fully visible.

## Included from 0.2

- Three Shortcut Arcade games: Window Rescue, Shortcut Sprint, and Keyfall.
- Correctly packaged Window Rescue ship and planet artwork.
- Non-punitive hints, fair same-deck Sprint replays, and targeted practice.
- Simplified lesson and completion screens.
- Improved responsive character pointing and keyboard capture.
- Current Omarchy theme and wallpaper support throughout Arcade.
- Hardened progress migration, retention, reset, and corrupt-file handling.
- All 400 narration clips with matching validated word timings.

## Remove

Close the app, then run:

```sh
/usr/bin/learn-omarchy --uninstall
```

Managed integration cleanup preserves progress, settings, backups, and
user-edited files.

## Compatibility notes

All attached assets were built and verified from the `v0.2.2` tag.

Hyprland exposes monitor, window, and layer geometry, but Omarchy 4.0.3 does not
provide third-party plugins with every internal bar-widget or popup rectangle.
Learn Omarchy uses measured geometry where available and responsive estimates
where needed.

OCR, QR, dictation, and activity-monitor exercises may require optional
dependencies listed by pacman. Lock and microphone activities require an
explicit choice.
