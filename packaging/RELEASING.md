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
The [CI and draft-release workflows](CI.md) run this gate on exact tagged
source before building or uploading. Branch CI runs the regression suites;
version-tag CI produces only a draft prerelease. It never publishes or
promotes a candidate to stable automatically. Complete the
[acceptance gates](ACCEPTANCE.md) before approving publication.

## Prepare a release from actual source bytes

There is no invented tag URL or placeholder checksum. Start with a trusted, existing local tag
whose `package.json` version and license approval are correct:

```sh
# Replace these with the actual existing tag and its package.json version.
VERSION=0.1.0-rc.3
TAG="v$VERSION"
git rev-parse --verify "refs/tags/$TAG"
ARCH_VERSION="$(node --input-type=module -e \
  "import {packageVersion} from './tools/prepare-release.mjs'; console.log(packageVersion('$VERSION'))")"
export SOURCE_DATE_EPOCH="$(git log -1 --format=%ct "refs/tags/$TAG")"
mkdir -p release-work
git archive --format=tar.gz --prefix="learn-omarchy-$ARCH_VERSION/" \
  "refs/tags/$TAG" > "release-work/learn-omarchy-$ARCH_VERSION.tar.gz"
node tools/prepare-release.mjs \
  --archive "release-work/learn-omarchy-$ARCH_VERSION.tar.gz" \
  --output "release-work/arch-$VERSION"
cd "release-work/arch-$VERSION"
makepkg --cleanbuild
```

Verify that the tag exists before running these commands. An existing
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

Candidate SemVer `0.1.0-rc.1` maps to Arch version `0.1.0rc1`, so candidate and
stable packages don't share the same identity. Use `v0.1.0-rc.1` for the Git tag
and `learn-omarchy-0.1.0rc1/` inside the source archive.

Verify the final binary package against that same source checkout:

```sh
node tools/verify-release-package.mjs \
  --package /path/to/learn-omarchy-0.1.0rc1-1-any.pkg.tar.zst \
  --source-root /path/to/exact-tag-checkout
```

This checks every installed file and executable bit, rejects development-only
paths, and runs the extracted course/audio validators and launcher help with
private empty user state. It neither installs the package nor substitutes for
the graphical acceptance gates in [ACCEPTANCE.md](ACCEPTANCE.md).

## Runtime dependencies

For collaborators building before a release is published,
`node tools/prepare-checkout-package.mjs --output release-work/local` prepares
the same recipe from clean committed `HEAD`, without requiring a tag. It records
the source commit, version, timestamp and checksum in `CHECKOUT-INFO.json`.
It never builds, installs dependencies, tags, publishes, or includes untracked
files. `makepkg --syncdeps --install` is a separate, explicit user action.
Do not distribute a checkout build as a verified tagged release.

Required dependencies are encoded in `PKGBUILD.in`:

- Node **22.6+**: the bundled validation/pack tools use
  `--experimental-strip-types`, introduced in Node 22.6. No runtime npm
  modules or speech-service credentials are needed.
- Quickshell **0.3+**, Hyprland, and **Omarchy 4.0.3+**: `Quickshell`, `.Io`, `.Wayland`,
  `.Hyprland`, `qs`, `hyprctl`, and the Omarchy companion API. A compatible
  running Omarchy shell is needed for desktop geometry; failure does not
  prevent the course from opening.
- `qt6-declarative` for QtQuick/Controls/Layouts and **`qt6-multimedia`** for
  `PracticeContent.qml`'s `QtMultimedia` import, even before a media lesson.
  `qt6-multimedia-ffmpeg` supplies the playback backend.
- `ttf-liberation` supplies scalable text fonts; `noto-fonts-emoji` displays
  the Compose practice samples. Tests must not run against a fontless image.
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
(Node 26.7, Quickshell 0.3.1, Qt 6.11.2, Omarchy 4.0.3-1). This is not a claim
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
