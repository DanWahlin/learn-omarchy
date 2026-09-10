# One-package distribution

The package contains the application **and** its Omarchy geometry companion.
Install the package and open Learn Omarchy; no second plugin package, Enable
button, download, or privileged post-install hook is needed. The launcher
manages only the current user's bundled integration. Package installation and
removal never scan users' home directories or delete learning progress.
Startup verifies that the service is enabled and answers its capability IPC.
Omarchy's plugin-list `active` field denotes the selected bar, not service
readiness, so it isn't used to judge the companion.

## Approved licensing and the release gate

The owner selected **MIT** for code and **CC BY 4.0** for original artwork
and course content. `packaging/release-licenses.json` records that approval;
the bird recording retains its existing **CC0-1.0** license. Generated Arch
metadata lists `MIT`, `CC-BY-4.0`, and `CC0-1.0`. Licensing approval does not
authorize publishing a release.

Run `node tools/prepare-release.mjs --check` before preparing a release.
The gate remains required and verifies:

- `LICENSE` for code and `LICENSE-ASSETS.md` for original artwork/content,
  plus `LICENSES/<artLicense>.txt` containing the full artwork license.
- Matching `package.json` licensing and both bundled character manifests'
  declared license/author attribution.
- Explicit splash licensing in `assets/splash/provenance.json`. Include
  derived launcher icons, course text, narration, and original sounds in
  the original-content review; do not assume character permission covers
  everything automatically.
- The bird recording's existing CC0-1.0 provenance, creator, source, and
  hashes, without relicensing it, plus `LICENSES/CC0-1.0.txt`. Preserve other
  third-party notices.

The gate checks recorded approval and consistency, not legal ownership.
Missing notices, unresolved metadata, or a blocked approval record still
prevent preparation. All license files and asset provenance ship with the app.
Notices are installed under `/usr/share/licenses/learn-omarchy` and at the
application root so relative links from the installed documentation resolve.
No publication workflow is installed. Do not upload build/CI artifacts until
the gate passes; any future publishing workflow must run it on the exact
tagged source before building or uploading, with an explicit release trigger.

## Prepare a release from actual source bytes

There is no invented tag URL or placeholder checksum. No release tag existed
when this tooling was introduced. Start with a trusted, existing local tag
whose `package.json` version and license approval are correct:

```sh
# Replace these with the actual existing tag and its package.json version.
VERSION=0.1.0
TAG=v0.1.0
git rev-parse --verify "refs/tags/$TAG"
export SOURCE_DATE_EPOCH="$(git log -1 --format=%ct "refs/tags/$TAG")"
mkdir -p release-work
git archive --format=tar.gz --prefix="learn-omarchy-$VERSION/" \
  "refs/tags/$TAG" > "release-work/learn-omarchy-$VERSION.tar.gz"
node tools/prepare-release.mjs \
  --archive "release-work/learn-omarchy-$VERSION.tar.gz" \
  --output "release-work/arch-$VERSION"
cd "release-work/arch-$VERSION"
makepkg --cleanbuild
```

These commands are instructions, not a claim that `v0.1.0` exists. An existing
trusted local `.tar.gz` with the same versioned root layout works too.
`git archive` excludes untracked recordings, user data, and `node_modules`;
never create release sources by blindly archiving a working directory.

The preparation tool inspects metadata **inside the archive**, calculates its
actual SHA256, and writes a new directory containing the unchanged versioned
archive, `PKGBUILD`, and `.SRCINFO`. The PKGBUILD uses only `$srcdir`, not a
neighboring source checkout, and repeats the licensing gate before staging.
`makepkg --cleanbuild` builds one `learn-omarchy-*.pkg.tar.zst`; it does not
install anything or automatically install dependencies. Run it as a regular
user with Arch build/runtime dependencies available. No npm install,
network access, or audio/art regeneration is needed during packaging.
Keep the source archive, SHA256, `SOURCE_DATE_EPOCH`, and build-environment
versions for reproducibility. For a supplied local archive, obtain the epoch
from its actual source commit rather than inventing a release timestamp.

Archive inputs and Makefiles must be trusted: inspecting them does not make
executing their build scripts safe. Only add a public source URL after that
specific tagged archive really exists, and recalculate its checksum from the
downloaded bytes (hosting-service archives can differ from `git archive`).

## Runtime dependencies

Required dependencies are encoded in `PKGBUILD.in`:

- Node **22.6+**: the bundled validation/pack tools use
  `--experimental-strip-types`, introduced in Node 22.6. No runtime npm
  modules or speech-service credentials are needed.
- Quickshell **0.3+**, Hyprland, and Omarchy: `Quickshell`, `.Io`, `.Wayland`,
  `.Hyprland`, `qs`, `hyprctl`, and the Omarchy companion API. A compatible
  running Omarchy shell is needed for desktop geometry; failure does not
  prevent the course from opening.
- `qt6-declarative` for QtQuick/Controls/Layouts and **`qt6-multimedia`** for
  `PracticeContent.qml`'s `QtMultimedia` import, even before a media lesson.
  `qt6-multimedia-ffmpeg` supplies the playback backend.
- `mpv` for narration; `xdg-utils` for browser resolution using `xdg-settings`
  and `xdg-mime`; `bash` and `coreutils` for the launchers, and `sudo` for
  the explicitly requested terminal-based package removal.
- `xdg-terminal-exec` resolves the configured terminal for required window
  lessons; `nautilus` supports the required Files activities.
- `grim` and `slurp` for required screenshot practice; `gpu-screen-recorder`,
  `util-linux` (`setpriv`), and `ffmpeg` (`ffprobe`) for required recording
  practice and recording validation. These are package dependencies, not
  optional extras. The recorder does not use `wf-recorder`.

Optional practice dependencies map directly to commands in
`tools/capture-practice.mjs` and `tools/tutorial-launch.mjs`:
`tesseract` with `tesseract-data-eng`, `zbar` (`zbarimg`), `qrencode`,
`voxtype`, and `btop`. A supported configured browser
and terminal are used rather than installing/replacing the user's choices.
Missing optional tools let learners skip the affected exercises.
Optional transcoding reuses the required `ffmpeg` package.

The package/version mappings were checked against this Arch/Omarchy host
(Node 26.7, Quickshell 0.3.1, Qt 6.11.2, Omarchy 4.0.2). This is not a claim
of end-to-end testing on the minimum versions.

## Local development and removal

Local staged builds do not publish anything and remain available independently
of the release gate:

```sh
make install DESTDIR="$PWD/local-stage" PREFIX=/usr
# Inspect local-stage/usr without installing into the system.
make uninstall DESTDIR="$PWD/local-stage" PREFIX=/usr
```

`make install` never activates the companion. The normal launcher performs
that per-user work on first open. To uninstall the Arch package, run
`learn-omarchy --uninstall` from a terminal as the regular user. It retains
pacman's normal confirmation and runs current-user integration cleanup from
a private staged helper only after package removal succeeds. Cancelling
package removal leaves the integration unchanged.

`learn-omarchy --remove-integration` remains available for explicit cleanup
with source installations or other removal workflows. Modified integrations
are preserved, as are state/settings, external character packs, and practice
recordings. There are no root hooks to disable plugins or clean other users'
configuration. Removing only the package through a package manager may leave
a registered per-user companion copy; launch-time setup updates intact managed
copies on reinstall.
