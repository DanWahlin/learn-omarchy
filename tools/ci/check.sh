#!/usr/bin/env bash
set -euo pipefail

if (( EUID == 0 )); then
  echo "CI tests must run as an unprivileged user, including makepkg tests." >&2
  exit 1
fi

unset DISPLAY WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE
export QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic
export QT_QUICK_CONTROLS_STYLE=Basic QT_QUICK_BACKEND=software
export QML_XHR_ALLOW_FILE_READ=1 QT_MEDIA_BACKEND=ffmpeg
export TMPDIR="$PWD/.ci-tmp" XDG_RUNTIME_DIR="$PWD/.ci-runtime"
export XDG_CONFIG_HOME="$PWD/.ci-home/config" XDG_DATA_HOME="$PWD/.ci-home/data"
export XDG_CACHE_HOME="$PWD/.ci-home/cache" XDG_STATE_HOME="$PWD/.ci-home/state"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/no-session-bus"
mkdir -p "$TMPDIR" "$XDG_RUNTIME_DIR" "$XDG_CONFIG_HOME" \
  "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME"
chmod 700 "$TMPDIR" "$XDG_RUNTIME_DIR"

# Missing optional local-test tools must fail CI instead of silently skipping coverage.
for tool in node npm qs makepkg make gcc ffmpeg ffprobe zbarimg qrencode bsdtar fc-match; do
  command -v "$tool" >/dev/null
done
test -x /usr/lib/qt6/bin/qmltestrunner
test -n "$(fc-match --format='%{file}' sans-serif)"
test -n "$(fc-match --format='%{file}' monospace)"
qs --version
installed_qs="$(pacman -Q quickshell | cut -d ' ' -f 2)"
test "$(vercmp "$installed_qs" 0.3)" -ge 0
node --version
pacman -Q

npm ci --ignore-scripts --no-audit --no-fund
npm test
npm run test:ui
npm run check
npm run audio:check -- --require-word-timings
node tools/prepare-release.mjs --check

if [[ "${PREPARE_RELEASE:-false}" == true ]]; then
  node tools/ci/prepare-candidate.mjs
fi
