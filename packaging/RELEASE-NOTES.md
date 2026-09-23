# Learn Omarchy 0.2.4

This patch release makes the guides point at the menu or panel you opened,
restores bar measurements on stock Omarchy, and retires the desktop plugin that
Omarchy no longer supports.

Learn Omarchy includes 16 lessons, 93 activities, the guides Ohm-1 and Ollie,
and offline narration in one package.

## Install

Requires an up-to-date **Omarchy 4.0.3 or newer** desktop.

```sh
omarchy update
omarchy pkg add learn-omarchy
```

Press **Super + Space**, type **Learn Omarchy**, and press Enter.

If the Omarchy package repository hasn't picked up this release yet, download
`learn-omarchy-0.2.4-1-any.pkg.tar.zst` and `SHA256SUMS` from this release, then
run:

```sh
sha256sum --check --ignore-missing SHA256SUMS
sudo pacman -U ./learn-omarchy-0.2.4-1-any.pkg.tar.zst
```

## Fixed

- After you open a menu or panel, the guide points at it instead of flying back
  to the bar button that opened it. The lesson card also moves aside so it
  doesn't cover the open menu.
- Bar measurements work on stock Omarchy again. Omarchy disables the bar's
  animations, so Hyprland reports its layer alpha as 0, which was wrongly
  treated as a hidden bar.
- Capture exercises now play and verify saved files whose paths contain `#` or
  `%`.
- Saved progress details are kept even when the progress file lists no courses.

## Changed

- The app no longer installs the `learn-omarchy.geometry` shell plugin.
  Omarchy 4.0.3+ doesn't give third-party plugins the bar and menu objects it
  measured, so it couldn't work. Launching never changes your Omarchy
  configuration; `learn-omarchy --uninstall` removes an unchanged copy left by
  an earlier release. The `--remove-integration` option was removed.
- Launch guidance now uses **Super + Space** search.
- Removed unused code left over from the simulated Capture controls and earlier
  Arcade prototypes.

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

Your progress, settings, backups, and user-edited files are preserved.

## Compatibility notes

All attached assets were built and verified from the `v0.2.4` tag.

Learn Omarchy measures bar items with Omarchy's supported bar geometry on
single-monitor desktops. Omarchy doesn't expose the position of open menus,
panels, or individual workspace buttons, so those targets use responsive
estimates.

OCR, QR, dictation, and activity-monitor exercises may require optional
dependencies listed by pacman. Lock and microphone activities require an
explicit choice.
