# Learn Omarchy 0.2.0

This release adds Shortcut Arcade and sharpens the guided course for a clearer,
more reliable learning experience.

Learn Omarchy includes 17 lessons, 101 activities, the guides Ohm-1 and Ollie,
offline narration, and read-only desktop integration in one package.

## Install

Requires an up-to-date **Omarchy 4.0.3 or newer** desktop.

Download `learn-omarchy-0.2.0-1-any.pkg.tar.zst` from this release, then run:

```sh
sudo pacman -U ./learn-omarchy-0.2.0-1-any.pkg.tar.zst
learn-omarchy
```

To verify the download first, place `SHA256SUMS` in the same directory and run:

```sh
sha256sum --check --ignore-missing SHA256SUMS
```

## Shortcut Arcade

- **Window Rescue** teaches a six-step desktop workflow with no timer.
- **Shortcut Sprint** tests recall in 60-second rounds and supports fair
  same-deck replays against your best pace.
- **Keyfall** challenges you to use each shortcut before its card reaches the
  bottom, with selectable speed and reduced-motion support.
- Hints and misses never remove earned points.
- Practice history identifies shortcuts worth revisiting without punishing
  learners who ask for help.

## Course improvements

- Simplified lesson, completion, and Arcade screens keep the next action clear.
- Character pointing follows responsive bar, workspace, panel, and window
  targets more accurately.
- Text-entry exercises automatically pass keyboard input to the opened app.
- Keyboard capture pauses safely when focus is lost and resumes explicitly.
- Window exercises act only on course-owned windows.
- Progress reset, migration, retention, and corrupt-file handling are more
  reliable and transparent.
- Arcade follows the current Omarchy theme and wallpaper.
- All 400 narration clips have matching validated word timings.

## Remove

Close the app, then run:

```sh
/usr/bin/learn-omarchy --uninstall
```

Managed integration cleanup preserves progress, settings, backups, and
user-edited files.

## Compatibility notes

All attached assets were built and verified from the `v0.2.0` tag.

Hyprland exposes monitor, window, and layer geometry, but Omarchy 4.0.3 does not
provide third-party plugins with every internal bar-widget or popup rectangle.
Learn Omarchy uses measured geometry where available and responsive estimates
where needed.

OCR, QR, dictation, and activity-monitor exercises may require optional
dependencies listed by pacman. Lock and microphone activities require an
explicit choice.
