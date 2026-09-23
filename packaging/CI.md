# CI and tagged releases

`ci.yml` runs on branch pushes and pull requests. `release.yml` runs only on
`v*` tag pushes, calls the same CI, and publishes a GitHub release only after
all checks pass. Pushing a version tag is therefore the explicit publication
action, not merely a request to prepare a candidate.

## Isolated checks

Both paths use GitHub-hosted Ubuntu 24.04 with a digest-pinned official Arch
container. Before running source code, the container installs:

- `base-devel` (including makepkg's standard compiler/fakeroot toolchain),
  `git`, `libarchive` (including bsdtar), `nodejs`, and `npm`;
- `quickshell` (checked to be at least 0.3), `qt6-declarative` (including
  Quick Controls and qmltestrunner), `qt6-multimedia`, and
  `qt6-multimedia-ffmpeg`;
- `ffmpeg`, `mpv`, `zbar`, `qrencode`, `tesseract`, and `tesseract-data-eng`;
- `ttf-liberation` and `noto-fonts-emoji` so text-layout tests have actual
  scalable text fonts and the Compose samples have emoji glyphs.

The checkout and all test/build commands then run as an unprivileged `ci`
user without sudo access. This prevents makepkg's root refusal from silently
skipping its tests. Required native tools are checked before the suites.
Offscreen software rendering, private runtime/configuration directories, an
absent session bus, and no display/compositor variables isolate the checks
from any real desktop. No host package installation occurs.

The commands are:

```sh
npm ci --ignore-scripts --no-audit --no-fund
npm test
npm run test:ui
npm run check
npm run audio:check -- --require-word-timings
node tools/prepare-release.mjs --check
```

The npm Speech SDK dependency supports imports in tests; no Azure credentials
or audio generation are needed. Test totals may grow; QML platform-dependent
skips are reported by the suite, not presented as physical desktop coverage.
Arch packages are rolling even though the base image is pinned: logs record
installed versions, and candidates also retain `BUILD-INFO.txt`. This is not
a claim of cross-date reproducible toolchains.

## Exact source and artifact boundary

The tag must exactly equal `v` plus `package.json`'s version. For example,
`v0.1.0-rc.1` maps to archive/package version `0.1.0rc1`. The checkout must
match that tag's commit with no tracked changes. `git archive` selects only
that commit, never untracked practice recordings, screenshots, node_modules,
or local user state. The source commit timestamp becomes `SOURCE_DATE_EPOCH`.
Review tracked source before tagging: git archive is not a secret scanner.

The archive is checked by `tools/prepare-release.mjs`, then built with
`makepkg --nodeps --cleanbuild --noconfirm`. **This is deliberately a vanilla
Arch packaging check:** Omarchy is unavailable from vanilla Arch's official
repositories. No unreviewed repository bootstrap or fake dependency package
is used. `--nodeps` does not remove dependencies from the package.
`tools/verify-release-package.mjs` verifies the real Omarchy dependency,
installed payload bytes/modes, and extracted offline validators against the
same source before any upload. Neither this nor offscreen tests establishes
real Omarchy installation or graphical acceptance.

The only uploaded directory is `.ci-release/dist/`, artifact name
`release-candidate`, retained for 14 days:

- `learn-omarchy-ARCH_VERSION.tar.gz`
- `learn-omarchy-ARCH_VERSION-1-any.pkg.tar.zst`
- `PKGBUILD` and `SRCINFO` (the `.SRCINFO` recipe metadata is renamed for
  downloads because GitHub rewrites asset names beginning with a dot)
- `BUILD-INFO.txt`, `VERIFICATION.json`, and `RELEASE-NOTES.txt`
- `RELEASE-NOTES.md`, copied unchanged from the tagged source and used as the
  release description
- `SHA256SUMS` covering every other file

Build trees, npm modules, private state, and test output directories are not
uploaded. Pull requests and ordinary branch pushes never upload artifacts.
The separate release job downloads only this run's verified artifact,
rechecks SHA256 hashes, and attaches the listed files to the published release.
It then downloads the attached files and verifies the checksums again, catching
hosting-side filename changes as well as missing or changed uploads.
It refuses to replace an existing release on reruns. Never move a published
tag or delete a published release merely to make automation pass.

## Tagging is publication

Only the final release job has `contents: write`. Test jobs have read-only
permissions, checkout does not persist credentials, and no secrets are passed
to the reusable workflow. External actions are pinned to verified commit
SHAs. GitHub token repository settings must allow the narrowly scoped release
write permission. Restrict tag creation with repository rulesets.

Before pushing any version tag, complete the applicable gates in
[ACCEPTANCE.md](ACCEPTANCE.md) against the exact source commit, review
[RELEASE-NOTES.md](RELEASE-NOTES.md), and obtain explicit release approval.
Do not push release-candidate tags through this workflow unless it is first
changed to mark those releases as prereleases.

The [Omarchy submission kit](omarchy-pkgs/README.md) supplies release-tracking
metadata, a PR description template, and a generator that verifies an anonymously
accessible stable release before producing `pkgbuilds/learn-omarchy/`. The
existing Omarchy package definition tracks later stable releases automatically.
