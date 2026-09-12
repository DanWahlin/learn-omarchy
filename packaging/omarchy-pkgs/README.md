# Future Omarchy package submission

This is the preparation kit for a future `omacom/omarchy-pkgs` PR, modeled on
[agent-arcade-bin #310](https://github.com/omacom/omarchy-pkgs/pull/310).
**It does not authorize or perform submission, publication, or a visibility change.**
The current repository is private and `v0.1.0-rc.5` is an unpublished candidate.
There is intentionally no checked-in PKGBUILD pointing at that inaccessible release.

## Package design

Use **`learn-omarchy`**, a source package with `arch=('any')`. The application
ships QML, JavaScript/TypeScript, and media, not Agent Arcade's native `.deb`.
Keeping the existing package name preserves upgrades from direct upstream Arch
installs. Do not add `-bin`, a second companion package, or redundant
`provides`/`conflicts` entries.

The generator reuses the **selected release archive's** `packaging/PKGBUILD.in`,
license checks, dependency list, and `make install`; it does not copy those
definitions into a second manually maintained recipe. Its only recipe changes
are a maintainer line and a public, version-interpolated source URL. It uses the
custom release `.tar.gz`, not GitHub's automatically generated source archive
or the already-built `.pkg.tar.zst`.

`.omarchy/package.json` follows the precedent's fast ring and 24-hour quarantine,
but tracks the existing `SHA256SUMS` manifest with `assets.any`. That maps to the
unsuffixed `sha256sums` array. All licenses come from the source archive; a second
local LICENSE source would break that one-source/one-checksum mapping.
**Fast ring means direct stable-channel builds, not prerelease opt-in.**

The GitHub provider ignores drafts and prereleases, even if their tags are public.
The first eligible release must therefore be an explicitly approved **stable
`vX.Y.Z` release**, at least 24 hours old. This also avoids incompatible mappings
between SemVer `0.1.0-rc.5` and Arch `0.1.0rc5`. Do not relabel rc.5 as stable,
move an existing tag, bypass the quarantine, or publish just to satisfy this tool.

These choices were checked against `omacom/omarchy-pkgs` commit
`f711dbb1111ac10e68236b487cd1f29403dd4655`:
[README](https://github.com/omacom/omarchy-pkgs/blob/f711dbb1111ac10e68236b487cd1f29403dd4655/README.md),
[metadata validator](https://github.com/omacom/omarchy-pkgs/blob/f711dbb1111ac10e68236b487cd1f29403dd4655/helpers/package-metadata.sh),
and [release provider](https://github.com/omacom/omarchy-pkgs/blob/f711dbb1111ac10e68236b487cd1f29403dd4655/helpers/upstream-github.sh).
Recheck current contribution rules when actually submitting.

## Generate the eventual submission

First complete the [stable acceptance gates](../ACCEPTANCE.md), obtain separate
public-distribution approval, and prepare a new stable tag/release through the
[release procedure](../RELEASING.md). CI always creates a draft prerelease, even
for a stable-shaped tag: publication **and removing the prerelease flag** remain
explicit owner-approved actions. Make the repository public only with approval.
Keep the release source archive and checksum manifest available permanently.

From the Learn Omarchy checkout, with Node.js and `tar` available:

```sh
# Example ONLY: replace v0.1.0 with the actual approved, published stable tag.
node tools/prepare-omarchy-submission.mjs \
  --release v0.1.0 --output release-work/omarchy-submission
```

The command deliberately uses anonymous HTTPS, not `gh` credentials. It rejects
private/inaccessible repositories, drafts, prereleases, young releases, missing
or redirected asset definitions, checksum/digest mismatches, archive/version
mismatches, and unresolved licensing. It refuses an existing output directory.
It does not execute the downloaded PKGBUILD.

Output:

```text
pkgbuilds/learn-omarchy/PKGBUILD
pkgbuilds/learn-omarchy/.omarchy/package.json
PR.md
SRCINFO
SUBMISSION.json
```

Only **`pkgbuilds/learn-omarchy/`** belongs in the Omarchy repository. `PR.md` is
the proposed PR description, not a file to commit there. `SRCINFO` and
`SUBMISSION.json` are local review evidence. No archive or binary goes in the PR.
The evidence records public source verification, **not** desktop acceptance or
submission approval. The PR description deliberately retains unchecked gates.

## Validate and stage, without opening a PR

Review the generated PKGBUILD before running it. On an up-to-date Omarchy test
machine, with dependencies already installed:

```sh
cd release-work/omarchy-submission/pkgbuilds/learn-omarchy
bash -n PKGBUILD
makepkg --printsrcinfo
makepkg --verifysource
makepkg --cleanbuild
```

Do not use `--install`, `--syncdeps`, `--nodeps`, or `sudo makepkg` for this
non-installing check. Use the source archive downloaded by makepkg and its
extracted versioned root to run `tools/verify-release-package.mjs` against the
resulting package, as described in [RELEASING.md](../RELEASING.md).
Compare `makepkg --printsrcinfo` with the generated `SRCINFO`.
`arch=any` does not certify ARM dependency availability or graphical behavior.

In a reviewed, disposable checkout/fork of `omacom/omarchy-pkgs`, first confirm
`pkgbuilds/learn-omarchy` does not already exist, then copy only the two submission
files into that path. From the Omarchy checkout root:

```sh
bash -c 'source helpers/package-metadata.sh; validate_package_metadata pkgbuilds/learn-omarchy'
bin/sync-upstream learn-omarchy
git diff --check
git status --short
```

`sync-upstream` can rewrite the staged recipe if a newer eligible release exists;
review the diff and regenerate/revalidate against that release instead of
submitting mismatched evidence. Do not run `bin/repo release`: it is a
build/sign/promote/sync operation, not PR validation.

Complete the generated PR checklist with exact-release evidence. In particular,
fresh graphical install, offline operation, upgrade/removal, attended lock and
dictation, and supported display/hardware acceptance are still separate from
automated packaging checks. Remove any checkout desktop launcher before testing
the installed Apps entry so it cannot shadow `/usr/bin/learn-omarchy`.

Once separately authorized, the intended title is **Add learn-omarchy to the
fast ring**. Until then, leave the prepared files local; do not create the PR.
