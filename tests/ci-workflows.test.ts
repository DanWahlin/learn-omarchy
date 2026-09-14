import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { candidateIdentity } from "../tools/ci/prepare-candidate.mjs";

const read = (path: string) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("release tag identity must exactly match the source SemVer and mapped Arch version", () => {
  assert.deepEqual(candidateIdentity("v0.1.0-rc.1", "0.1.0-rc.1"), {
    tag: "v0.1.0-rc.1", version: "0.1.0-rc.1", archVersion: "0.1.0rc1",
  });
  assert.equal(candidateIdentity("v1.2.3", "1.2.3").archVersion, "1.2.3");
  for (const tag of ["0.1.0-rc.1", "v0.1.0", "v0.1.0-rc.2", "v0.1.0-rc.1;echo bad", undefined])
    assert.throws(() => candidateIdentity(tag, "0.1.0-rc.1"), /exactly match/);
  assert.throws(() => candidateIdentity("v../evil", "../evil"));
});

test("CI pins actions and Arch image and restricts credentials and artifact uploads", async () => {
  const ci = await read(".github/workflows/ci.yml");
  const release = await read(".github/workflows/release.yml");
  for (const workflow of [ci, release]) {
    for (const [, action] of workflow.matchAll(/uses: ([^\s]+)/g))
      assert.ok(action.startsWith("./") || /@[a-f0-9]{40}$/.test(action), action);
    assert.doesNotMatch(workflow, /pull_request_target|secrets: inherit|--privileged/);
  }
  assert.match(ci, /archlinux:base@sha256:[a-f0-9]{64}/);
  assert.match(ci, /persist-credentials: false/);
  assert.match(ci, /ttf-liberation noto-fonts-emoji/);
  assert.match(ci, /runuser -u ci -- env -i/);
  assert.match(ci, /github\.event_name == 'push'.*refs\/tags\/v/);
  assert.match(ci, /path: \.ci-release\/dist\//);
  assert.match(release, /needs: validate/);
  assert.match(release, /--verify-tag --latest/);
  assert.doesNotMatch(release, /--draft|--prerelease/);
  assert.match(release, /--notes-file RELEASE-NOTES\.md/);
  assert.match(release, /PKGBUILD SRCINFO/);
  assert.ok(release.indexOf("gh release download") > release.indexOf("gh release create"),
    "check downloaded release assets, not just the files before upload");
  assert.doesNotMatch(release, /gh release (edit|upload)/);
  assert.ok(ci.indexOf("pacman -Syu") < ci.indexOf("runuser -u ci"));
});

test("candidate artifacts preserve the tagged release notes and require offline package verification", async () => {
  const script = await read("tools/ci/prepare-candidate.mjs");
  assert.match(script, /releaseNotes\.startsWith\(`# Learn Omarchy \$\{version\}\\n`\)/);
  assert.match(script, /releaseNotes\.includes\(`learn-omarchy-\$\{archVersion\}-1-any\.pkg\.tar\.zst`\)/);
  assert.match(script, /writeFile\(join\(dist, "RELEASE-NOTES\.md"\), releaseNotes\)/);
  assert.doesNotMatch(script, /DRAFT \/ PRERELEASE|not approved for public|before explicitly publishing/);
  assert.match(script, /tools\/verify-release-package\.mjs/);
  assert.match(script, /"--package", binary, "--source-root", source/);
  assert.match(script, /JSON\.parse\(verification\)\.verified !== true/);
  assert.ok(script.indexOf("JSON.parse(verification).verified") < script.indexOf("await mkdir(dist)"));
  assert.match(script, /name === "\.SRCINFO" \? "SRCINFO" : name/,
    "checksum filenames must survive GitHub's leading-dot asset renaming");
});

test("CI requires native tools and executes all mandatory checks without cloud credentials", async () => {
  const script = await read("tools/ci/check.sh");
  for (const command of ["npm ci --ignore-scripts", "npm test", "npm run test:ui",
    "npm run check", "npm run audio:check -- --require-word-timings",
    "node tools/prepare-release.mjs --check"])
    assert.ok(script.includes(command), command);
  assert.match(script, /EUID == 0/);
  assert.match(script, /unset DISPLAY WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE/);
  assert.match(script, /QT_QPA_PLATFORM=offscreen/);
  assert.match(script, /QT_QUICK_BACKEND=software/);
  assert.match(script, /for tool in .*qs makepkg .*ffmpeg .*zbarimg qrencode/);
  assert.match(script, /vercmp "\$installed_qs" 0\.3/);
  assert.doesNotMatch(script, /audio:generate|AZURE|SPEECH_KEY/);
});
