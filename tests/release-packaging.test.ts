import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { mkdir, mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import test from "node:test";
import { checkLicenses, inspectArchive, packageVersion, prepareRelease } from "../tools/prepare-release.mjs";
import { prepareCheckoutPackage } from "../tools/prepare-checkout-package.mjs";
import { prepareOmarchySubmission } from "../tools/prepare-omarchy-submission.mjs";

const template = await readFile(new URL("../packaging/PKGBUILD.in", import.meta.url), "utf8");

// Synthetic metadata tests the gate without granting rights to real project assets.
function fixture() {
  const bird = Buffer.from("synthetic bird recording");
  const files: Record<string, string | Buffer> = {
    "packaging/release-licenses.json": JSON.stringify({ status: "approved", codeLicense: "LicenseRef-TestCode", artLicense: "LicenseRef-TestArt" }),
    "package.json": JSON.stringify({ version: "1.2.3", license: "LicenseRef-TestCode AND LicenseRef-TestArt AND CC0-1.0" }),
    "LICENSE": "Synthetic code notice, not a project license.",
    "LICENSE-ASSETS.md": "Synthetic art notice, not a project license.",
    "LICENSES/LicenseRef-TestArt.txt": "Synthetic full terms.",
    "LICENSES/CC0-1.0.txt": "Synthetic CC0 notice.",
    "assets/splash/provenance.json": JSON.stringify({ license: { status: "declared", identifier: "LicenseRef-TestArt" } }),
    "assets/sounds/birds-welcome.provenance.json": JSON.stringify({
      license: "CC0-1.0", creator: "Synthetic creator", sourceUrl: "https://example.invalid/bird",
      sourceSha256: "a".repeat(64), outputSha256: createHash("sha256").update(bird).digest("hex"),
    }),
    "assets/sounds/birds-welcome.opus": bird,
    "packaging/PKGBUILD.in": template,
  };
  for (const id of ["ohm-1", "owl"]) files[`assets/characters/${id}/character.json`] = JSON.stringify({
    author: { status: "declared", name: "Synthetic fixture" }, license: { status: "declared", identifier: "LicenseRef-TestArt" },
  });
  for (const file of ["Makefile", "bin/learn-omarchy", "app/shell.qml", "tools/install-geometry-provider.mjs", "tools/prepare-release.mjs",
    ...["manifest.json", "Service.qml", "SnapshotProvider.qml", "Geometry.js"].map(name => `integrations/omarchy/learn-omarchy.geometry/${name}`)])
    files[file] = "Synthetic payload";
  return files;
}

async function archiveFixture(directory: string, files: Record<string, string | Buffer>, version = "1.2.3") {
  const root = join(directory, `learn-omarchy-${version}`);
  for (const [file, value] of Object.entries(files)) {
    await mkdir(dirname(join(root, file)), { recursive: true });
    await writeFile(join(root, file), value);
  }
  const archive = join(directory, "input.tar.gz");
  const tar = spawnSync("tar", ["-czf", archive, "-C", directory, `learn-omarchy-${version}`], { encoding: "utf8" });
  assert.equal(tar.status, 0, tar.stderr);
  return archive;
}

async function checkoutFixture(directory: string) {
  await archiveFixture(directory, fixture());
  const source = join(directory, "learn-omarchy-1.2.3");
  const git = (...args: string[]) => {
    const result = spawnSync("git", ["-c", "core.hooksPath=/dev/null", "-c", "commit.gpgsign=false",
      "-c", "user.name=Package test", "-c", "user.email=package-test@example.invalid", ...args],
    { cwd: source, encoding: "utf8" });
    assert.equal(result.status, 0, result.stderr);
    return result.stdout.trim();
  };
  git("init", "--quiet", "--initial-branch=main");
  git("add", ".");
  git("commit", "--quiet", "-m", "Synthetic package preparation fixture\n\n"
    + "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>\n"
    + "Copilot-Session: 109acf47-0cc8-4d3f-b7f4-0f451dbe98ca");
  return { source, git };
}

async function submissionFixture(directory: string, files = fixture(), archiveVersion = "1.2.3") {
  const archive = await readFile(await archiveFixture(directory, files, archiveVersion));
  const checksum = createHash("sha256").update(archive).digest("hex");
  const repository = "DanWahlin/learn-omarchy";
  const api = `https://api.github.com/repos/${repository}`;
  const base = `https://github.com/${repository}/releases/download/v1.2.3`;
  const repo = { private: false, full_name: repository };
  const release = {
    tag_name: "v1.2.3", draft: false, prerelease: false, published_at: "2026-09-10T12:00:00Z",
    assets: ["learn-omarchy-1.2.3.tar.gz", "SHA256SUMS"].map(name => ({
      name, state: "uploaded", browser_download_url: `${base}/${name}`,
      digest: name.endsWith(".tar.gz") ? `sha256:${checksum}` : null,
    })),
  };
  const payload = { archive, manifest: `${checksum}  learn-omarchy-1.2.3.tar.gz\n` };
  const calls: string[] = [];
  const request: typeof fetch = async (input, options) => {
    const url = String(input);
    calls.push(url);
    assert.equal(options?.headers, undefined, "public readiness must not use authentication headers");
    if (url === api) return Response.json(repo);
    if (url === `${api}/releases/tags/v1.2.3`) return Response.json(release);
    if (url === `${base}/learn-omarchy-1.2.3.tar.gz`) return new Response(new Uint8Array(payload.archive));
    if (url === `${base}/SHA256SUMS`) return new Response(payload.manifest);
    return new Response("Missing synthetic response", { status: 404 });
  };
  return { repo, release, payload, checksum, calls, request, now: Date.parse("2026-09-12T12:00:00Z") };
}

test("Omarchy submission uses verified public source, an updatable recipe and explicit pending approval", async context => {
  const directory = await mkdtemp(resolve(".learn-submission-test-"));
  try {
    const fixture = await submissionFixture(directory);
    fixture.now = Date.parse(fixture.release.published_at) + 24 * 60 * 60 * 1000;
    const output = join(directory, "submission");
    const result = await prepareOmarchySubmission("v1.2.3", output, { fetch: fixture.request, now: fixture.now });
    assert.equal(result.sourceSha256, fixture.checksum);
    assert.equal(result.anonymousSourceVerified, true);
    assert.equal(result.submissionApproved, false);
    const packageDirectory = join(output, "pkgbuilds", "learn-omarchy");
    assert.deepEqual((await readdir(packageDirectory)).sort(), [".omarchy", "PKGBUILD"]);
    assert.deepEqual((await readdir(output)).sort(), ["PR.md", "SRCINFO", "SUBMISSION.json", "pkgbuilds"]);
    const pkgbuild = await readFile(join(packageDirectory, "PKGBUILD"), "utf8");
    assert.match(pkgbuild, /source=\("https:\/\/github\.com\/DanWahlin\/learn-omarchy\/releases\/download\/v\$pkgver\/learn-omarchy-\$pkgver\.tar\.gz"\)/);
    const local = await prepareRelease(join(directory, "input.tar.gz"), join(directory, "baseline"));
    const baseline = await readFile(join(local.output, "PKGBUILD"), "utf8");
    assert.equal(pkgbuild.replace(/^# Maintainer: .+\n\n/, "")
      .replace(/^source=.*$/m, 'source=("learn-omarchy-$pkgver.tar.gz")'),
    baseline, "only the maintainer comment and source URL may differ");
    const metadata = JSON.parse(await readFile(join(packageDirectory, ".omarchy", "package.json"), "utf8"));
    assert.deepEqual(metadata, {
      source: "local", release_ring: "fast", min_release_age: "24h",
      upstream: { github: "DanWahlin/learn-omarchy", checksums: "SHA256SUMS", assets: { any: "learn-omarchy-{pkgver}.tar.gz" } },
    });
    const body = await readFile(join(output, "PR.md"), "utf8");
    assert.ok(body.includes(fixture.checksum));
    assert.match(body, /- \[ \] Obtain explicit approval/);
    assert.doesNotMatch(body, /@[A-Z][A-Z0-9_]*@/);
    assert.equal(JSON.parse(await readFile(join(output, "SUBMISSION.json"), "utf8")).submissionApproved, false);
    assert.equal(spawnSync("bash", ["-n", join(packageDirectory, "PKGBUILD")]).status, 0);
    const info = spawnSync("makepkg", ["--printsrcinfo"], { cwd: packageDirectory, encoding: "utf8" });
    if (info.error && (info.error as NodeJS.ErrnoException).code === "ENOENT") {
      context.diagnostic("makepkg unavailable; native recipe checks require Arch/Omarchy.");
    } else {
      assert.equal(info.status, 0, info.stderr);
      const normalized = (text: string) => text.split("\n").map(line => line.trim()).filter(Boolean).sort();
      assert.deepEqual(normalized(info.stdout), normalized(await readFile(join(output, "SRCINFO"), "utf8")));
      await writeFile(join(packageDirectory, "learn-omarchy-1.2.3.tar.gz"), fixture.payload.archive);
      const verify = spawnSync("makepkg", ["--verifysource"], { cwd: packageDirectory, encoding: "utf8" });
      assert.equal(verify.status, 0, verify.stderr);
    }
    const callCount = fixture.calls.length;
    await assert.rejects(prepareOmarchySubmission("v1.2.3", output, { fetch: fixture.request }), /already exists/);
    assert.equal(fixture.calls.length, callCount, "existing output is rejected before downloading again");
    assert.ok(!(await readdir(directory)).some(name => name.startsWith(".learn-omarchy-submission-")));
  } finally { await rm(directory, { recursive: true, force: true }); }
});

test("Omarchy submission rejects private, draft, quarantined or inconsistent release metadata without output", async () => {
  const directory = await mkdtemp(resolve(".learn-submission-test-"));
  try {
    const original = await submissionFixture(directory);
    const cases: Array<[string, (value: typeof original) => void, RegExp]> = [
      ["private", value => { value.repo.private = true; }, /must be public/],
      ["wrong-repo", value => { value.repo.full_name = "other/repo"; }, /expected upstream/],
      ["draft", value => { value.release.draft = true; }, /published as stable/],
      ["prerelease", value => { value.release.prerelease = true; }, /published as stable/],
      ["wrong-tag", value => { value.release.tag_name = "v1.2.4"; }, /match the tag/],
      ["young", value => { value.release.published_at = "2026-09-11T12:00:00.001Z"; }, /at least 24h/],
      ["future-date", value => { value.release.published_at = "2026-09-13T12:00:00Z"; }, /at least 24h/],
      ["unknown-age", value => { value.release.published_at = "unknown"; }, /valid publication date/],
      ["missing-asset", value => { value.release.assets.pop(); }, /exactly one uploaded SHA256SUMS/],
      ["duplicate-asset", value => { value.release.assets.push(value.release.assets[0]); }, /exactly one uploaded/],
      ["wrong-url", value => { value.release.assets[0].browser_download_url = "https://example.invalid/source"; }, /expected public URL/],
      ["not-uploaded", value => { value.release.assets[0].state = "new"; }, /exactly one uploaded/],
      ["bad-bytes", value => { value.payload.archive = Buffer.from("Not the release"); }, /does not match SHA256SUMS/],
      ["missing-hash", value => { value.payload.manifest = `${value.checksum}  other.tar.gz\n`; }, /SHA256SUMS is missing/],
      ["duplicate-hash", value => { value.payload.manifest += value.payload.manifest; }, /duplicate entries/],
      ["malformed-hash", value => { value.payload.manifest = "SKIP  learn-omarchy-1.2.3.tar.gz\n"; }, /malformed/],
      ["wrong-digest", value => { value.release.assets[0].digest = `sha256:${"0".repeat(64)}`; }, /GitHub's asset digest/],
    ];
    for (const [name, change, error] of cases) {
      const state = await submissionFixture(directory);
      change(state);
      await assert.rejects(prepareOmarchySubmission("v1.2.3", join(directory, name), {
        fetch: state.request, now: state.now,
      }), error, name);
      assert.ok(!(await readdir(directory)).includes(name), name);
    }
    await assert.rejects(prepareOmarchySubmission("v1.2.3", join(directory, "unavailable"), {
      fetch: async () => new Response("Not found", { status: 404 }),
    }), /anonymously \(HTTP 404\)/);
    for (const tag of ["v0.1.0-rc.3", "1.2.3", "v1.2.3+build", "v01.2.3", "v1.2.3;echo bad"])
      await assert.rejects(prepareOmarchySubmission(tag, join(directory, "invalid"), {
        fetch: async () => { throw new Error("must not fetch an ineligible tag"); },
      }), /stable vX.Y.Z/);
  } finally { await rm(directory, { recursive: true, force: true }); }
});

test("Omarchy submission rechecks the downloaded archive version and licensing and cleans failed staging", async () => {
  const directory = await mkdtemp(resolve(".learn-submission-test-"));
  try {
    const files = fixture();
    const pkg = JSON.parse(String(files["package.json"]));
    files["package.json"] = JSON.stringify({ ...pkg, version: "2.3.4" });
    const wrongVersion = await submissionFixture(directory, files, "2.3.4");
    await assert.rejects(prepareOmarchySubmission("v1.2.3", join(directory, "wrong-version"), {
      fetch: wrongVersion.request, now: wrongVersion.now,
    }), /source version does not match/);
    const blocked = fixture();
    blocked["packaging/release-licenses.json"] = JSON.stringify({ status: "blocked" });
    const unapproved = await submissionFixture(directory, blocked);
    await assert.rejects(prepareOmarchySubmission("v1.2.3", join(directory, "blocked"), {
      fetch: unapproved.request, now: unapproved.now,
    }), /Release blocked:[\s\S]*Owner approval/);
    assert.ok(!(await readdir(directory)).some(name => name.startsWith(".learn-omarchy-submission-") || name === "blocked" || name === "wrong-version"));
  } finally { await rm(directory, { recursive: true, force: true }); }
});

test("Omarchy submission CLI is read-only for help and rejects publication or submission options", () => {
  const script = resolve("tools/prepare-omarchy-submission.mjs");
  const help = spawnSync(process.execPath, [script, "--help"], { encoding: "utf8" });
  assert.equal(help.status, 0, help.stderr);
  assert.match(help.stdout, /Does not build, install, publish, change visibility, commit, push, or create a PR/);
  for (const args of [["--publish"], ["--create-pr"], ["--release", "v1.2.3"], ["--release", "v1.2.3", "--output", "--help"]]) {
    const invalid = spawnSync(process.execPath, [script, ...args], { encoding: "utf8" });
    assert.notEqual(invalid.status, 0);
    assert.match(invalid.stderr, /Usage:/);
  }
});

test("a clean checkout prepares an exact-source package without a tag, install or untracked files", async () => {
  const directory = await mkdtemp(resolve(".learn-release-checkout-test-"));
  try {
    const { source, git } = await checkoutFixture(directory);
    await writeFile(join(source, "private-recording.wav"), "Untracked test data must not ship");
    const result = await prepareCheckoutPackage(source, join(directory, "new output", "package"));
    assert.equal(result.commit, git("rev-parse", "HEAD"));
    assert.equal(result.epoch, git("show", "-s", "--format=%ct", "HEAD"));
    assert.equal(result.packageVersion, "1.2.3");
    assert.equal(git("tag", "--list"), "", "preparing a checkout does not create release tags");
    const archive = inspectArchive(join(result.output, "learn-omarchy-1.2.3.tar.gz"));
    await assert.rejects(archive.read("private-recording.wav"), /missing/);
    await assert.rejects(archive.read(".git/config"), /missing/);
    assert.equal(await archive.read("package.json").then(buffer => JSON.parse(buffer.toString()).version), "1.2.3");
    const info = JSON.parse(await readFile(join(result.output, "CHECKOUT-INFO.json"), "utf8"));
    assert.equal(info.commit, result.commit);
    assert.equal(info.sourceSha256, result.checksum);
    assert.equal(info.sourceDateEpoch, Number(result.epoch));
    assert.ok(!(await readdir(result.output)).some(name => name.includes(".pkg.tar.")), "no build or installation");
    await assert.rejects(prepareCheckoutPackage(source, result.output), /EEXIST/);
  } finally { await rm(directory, { recursive: true, force: true }); }
});

test("checkout preparation rejects tracked edits and nested roots without silently building older source", async () => {
  const directory = await mkdtemp(resolve(".learn-release-checkout-test-"));
  try {
    const { source } = await checkoutFixture(directory);
    await assert.rejects(prepareCheckoutPackage(join(source, "app"), join(directory, "nested")), /repository root/);
    await writeFile(join(source, "LICENSE"), "A pending change");
    await assert.rejects(prepareCheckoutPackage(source, join(directory, "dirty")), /Commit or stash/);
    assert.ok(!(await readdir(directory)).includes("dirty"));
  } finally { await rm(directory, { recursive: true, force: true }); }
});

test("checkout preparation CLI help is read-only and rejects unsupported options", () => {
  const command = resolve("tools/prepare-checkout-package.mjs");
  const help = spawnSync(process.execPath, [command, "--help"], { encoding: "utf8" });
  assert.equal(help.status, 0, help.stderr);
  assert.match(help.stdout, /Does not build, install dependencies, install the app, tag, or publish/);
  for (const args of [["--install"], ["--output"], ["--output", "--help"]]) {
    const invalid = spawnSync(process.execPath, [command, ...args], { encoding: "utf8" });
    assert.notEqual(invalid.status, 0);
    assert.match(invalid.stderr, /Usage:/);
  }
});

test("candidate versions map to Arch versions that remain distinct from stable releases", () => {
  for (const [version, expected] of [
    ["0.1.0", "0.1.0"], ["0.1.0-rc.1", "0.1.0rc1"], ["1.2.3-beta.12", "1.2.3beta12"],
    ["1.2.3-alpha.1", "1.2.3alpha1"],
  ]) assert.equal(packageVersion(version), expected);
  for (const version of ["", "v1.2.3", "1.2.3-rc", "1.2.3+other", "../1.2.3", "1.2.3;echo bad"])
    assert.throws(() => packageVersion(version));
});

test("candidate archive names and package metadata use the mapped Arch version", async () => {
  const directory = await mkdtemp(resolve(".learn-release-test-"));
  try {
    const files = fixture();
    const pkg = JSON.parse(String(files["package.json"]));
    pkg.version = "1.2.3-rc.1";
    files["package.json"] = JSON.stringify(pkg);
    const archive = await archiveFixture(directory, files, "1.2.3rc1");
    const output = join(directory, "prepared");
    const result = await prepareRelease(archive, output);
    assert.equal(result.version, "1.2.3-rc.1");
    assert.equal(result.packageVersion, "1.2.3rc1");
    assert.match(await readFile(join(output, "PKGBUILD"), "utf8"), /pkgver=1\.2\.3rc1/);
    assert.match(await readFile(join(output, ".SRCINFO"), "utf8"), /source = learn-omarchy-1\.2\.3rc1\.tar\.gz/);
    assert.ok((await readdir(output)).includes("learn-omarchy-1.2.3rc1.tar.gz"));
  } finally { await rm(directory, { recursive: true, force: true }); }
});

test("licensing gate reports unresolved code, character, splash, and bird metadata together", async () => {
  const result = await checkLicenses(async () => { throw new Error("not supplied"); });
  for (const reason of ["Owner approval", "LICENSE:", "ohm-1", "owl", "splash", "Bird recording"])
    assert.ok(result.problems.some((problem: string) => problem.includes(reason)), reason);
});

test("draft license files cannot override blocked owner approval", async () => {
  const files = fixture();
  files["packaging/release-licenses.json"] = JSON.stringify({ status: "blocked", codeLicense: "LicenseRef-TestCode", artLicense: "LicenseRef-TestArt" });
  const result = await checkLicenses(async (path: string) => files[path]);
  assert.deepEqual(result.problems, ["Owner approval is pending for code and original artwork (including splash/icon, course text, narration, and original sounds)."]);
});

test("owner-approved project license files and asset provenance pass the release gate", async () => {
  const result = await checkLicenses((path: string) => readFile(resolve(path)));
  assert.deepEqual(result.problems, []);
  assert.equal(result.policy.status, "approved");
  assert.equal(result.policy.codeLicense, "MIT");
  assert.equal(result.policy.artLicense, "CC-BY-4.0");
});

test("release preparation uses exact archive bytes and emits one self-contained Arch recipe", async () => {
  const directory = await mkdtemp(resolve(".learn-release-test-"));
  try {
    const archive = await archiveFixture(directory, fixture());
    const output = join(directory, "prepared");
    const result = await prepareRelease(archive, output);
    const checksum = createHash("sha256").update(await readFile(archive)).digest("hex");
    assert.equal(result.checksum, checksum);
    assert.deepEqual((await readdir(output)).sort(), [".SRCINFO", "PKGBUILD", "learn-omarchy-1.2.3.tar.gz"]);
    assert.deepEqual(await readFile(join(output, "learn-omarchy-1.2.3.tar.gz")), await readFile(archive));
    const pkgbuild = await readFile(join(output, "PKGBUILD"), "utf8");
    assert.match(pkgbuild, /pkgver=1\.2\.3/);
    assert.ok(pkgbuild.includes(`sha256sums=('${checksum}')`));
    assert.match(pkgbuild, /cd "\$srcdir\/learn-omarchy-\$pkgver"/);
    assert.match(pkgbuild, /node tools\/prepare-release\.mjs --check \./);
    assert.doesNotMatch(pkgbuild, /\$startdir|SKIP|@[A-Z]+@|install=.*\.install/);
    for (const dependency of ["omarchy>=4.0.3", "nodejs>=22.6", "quickshell>=0.3", "qt6-multimedia", "xdg-utils", "tesseract-data-eng"])
      assert.ok(pkgbuild.includes(dependency), dependency);
    assert.equal(spawnSync("bash", ["-n", join(output, "PKGBUILD")]).status, 0);
    const srcinfo = await readFile(join(output, ".SRCINFO"), "utf8");
    for (const dependency of ["grim", "slurp", "gpu-screen-recorder", "util-linux", "ffmpeg", "qt6-multimedia",
      "qt6-multimedia-ffmpeg", "xdg-terminal-exec", "nautilus", "sudo", "ttf-liberation", "noto-fonts-emoji"]) {
      assert.ok(srcinfo.includes(`\tdepends = ${dependency}\n`), `${dependency} supports required lessons`);
      assert.ok(!srcinfo.includes(`\toptdepends = ${dependency}:`), dependency);
    }
    for (const dependency of ["tesseract", "zbar", "qrencode", "voxtype"])
      assert.ok(srcinfo.includes(`\toptdepends = ${dependency}:`), `${dependency} supports optional practice`);
    const makepkg = spawnSync("makepkg", ["--printsrcinfo"], { cwd: output, encoding: "utf8" });
    if (makepkg.error && (makepkg.error as NodeJS.ErrnoException).code === "ENOENT") {
      assert.match(srcinfo, /optdepends = voxtype:/);
    } else {
      assert.equal(makepkg.status, 0, makepkg.stderr);
      const normalized = (text: string) => text.split("\n").map(line => line.trim()).filter(Boolean).sort();
      assert.deepEqual(normalized(srcinfo), normalized(makepkg.stdout));
    }
    await assert.rejects(prepareRelease(archive, output), /EEXIST/);
  } finally { await rm(directory, { recursive: true, force: true }); }
});

test("archive approval is checked rather than trusting the working checkout", async () => {
  const directory = await mkdtemp(resolve(".learn-release-test-"));
  try {
    const files = fixture();
    files["assets/splash/provenance.json"] = JSON.stringify({ license: { status: "unresolved" } });
    delete files["tools/install-geometry-provider.mjs"];
    const archive = await archiveFixture(directory, files);
    await assert.rejects(prepareRelease(archive, join(directory, "blocked")), /Release blocked:[\s\S]*splash[\s\S]*install-geometry-provider/);
    assert.ok(!(await readdir(directory)).includes("blocked"));
  } finally { await rm(directory, { recursive: true, force: true }); }
});

test("source version mismatch and symbolic links are rejected before packaging", async () => {
  const directory = await mkdtemp(resolve(".learn-release-test-"));
  try {
    const archive = await archiveFixture(directory, fixture(), "9.9.9");
    await assert.rejects(prepareRelease(archive, join(directory, "wrong-version")), /version does not match/);
    const { symlink } = await import("node:fs/promises");
    await symlink("../../outside", join(directory, "learn-omarchy-9.9.9", "linked"));
    const tar = spawnSync("tar", ["-czf", archive, "-C", directory, "learn-omarchy-9.9.9"]);
    assert.equal(tar.status, 0);
    assert.throws(() => inspectArchive(archive), /not links/);
  } finally { await rm(directory, { recursive: true, force: true }); }
});

test("makepkg builds a single staged archive with the companion using synthetic approved source", async context => {
  const available = spawnSync("makepkg", ["--version"], { encoding: "utf8" });
  if (available.error && (available.error as NodeJS.ErrnoException).code === "ENOENT") {
    context.skip("Arch makepkg is not installed");
    return;
  }
  if (process.getuid?.() === 0) {
    context.skip("makepkg refuses root; the build must run as a regular user");
    return;
  }
  const directory = await mkdtemp(resolve(".learn-release-build-test-"));
  try {
    const files = fixture();
    files["tools/prepare-release.mjs"] = await readFile(new URL("../tools/prepare-release.mjs", import.meta.url));
    files["Makefile"] = `install:
\tmkdir -p "$(DESTDIR)$(PREFIX)/share/learn-omarchy"
\tcp -R app tools integrations "$(DESTDIR)$(PREFIX)/share/learn-omarchy/"
`;
    const archive = await archiveFixture(directory, files);
    const output = join(directory, "prepared");
    await prepareRelease(archive, output);
    const config = join(directory, "makepkg.conf");
    await writeFile(config, `CARCH=x86_64
CHOST=x86_64-pc-linux-gnu
BUILDENV=(!distcc !color !ccache !check !sign)
OPTIONS=(!strip docs !libtool !staticlibs emptydirs !zipman !purge !debug !lto)
INTEGRITY_CHECK=(sha256)
COMPRESSGZ=(gzip -c -n)
PKGEXT=.pkg.tar.gz
SRCEXT=.src.tar.gz
`);
    const buildOptions = {
      cwd: output, encoding: "utf8", timeout: 60000,
      env: { ...process.env, HOME: directory, TMPDIR: directory, SOURCE_DATE_EPOCH: "1",
        BUILDDIR: output, PKGDEST: output, SRCDEST: output, SRCPKGDEST: output, LOGDEST: output },
    } as const;
    const buildArguments = ["--config", config, "--nodeps", "--nocheck", "--cleanbuild", "--force"];
    const built = spawnSync("makepkg", buildArguments, buildOptions);
    assert.equal(built.status, 0, built.stderr || built.stdout);
    const packages = (await readdir(output)).filter(name => name.endsWith(".pkg.tar.gz"));
    assert.deepEqual(packages, ["learn-omarchy-1.2.3-1-any.pkg.tar.gz"]);
    const contents = spawnSync("tar", ["-tzf", join(output, packages[0])], { encoding: "utf8" });
    assert.equal(contents.status, 0, contents.stderr);
    for (const file of ["tools/install-geometry-provider.mjs", "integrations/omarchy/learn-omarchy.geometry/manifest.json"])
      assert.ok(contents.stdout.includes(`usr/share/learn-omarchy/${file}`), file);
    assert.ok(!contents.stdout.split("\n").includes(".INSTALL"));
    const firstBuild = await readFile(join(output, packages[0]));
    const rebuilt = spawnSync("makepkg", buildArguments, buildOptions);
    assert.equal(rebuilt.status, 0, rebuilt.stderr || rebuilt.stdout);
    assert.deepEqual(await readFile(join(output, packages[0])), firstBuild, "the same source, epoch, and toolchain produce identical package bytes");
  } finally { await rm(directory, { recursive: true, force: true }); }
});
