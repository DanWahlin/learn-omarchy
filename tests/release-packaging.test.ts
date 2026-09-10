import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { mkdir, mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import test from "node:test";
import { checkLicenses, inspectArchive, packageVersion, prepareRelease } from "../tools/prepare-release.mjs";

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
    for (const dependency of ["nodejs>=22.6", "quickshell>=0.3", "qt6-multimedia", "xdg-utils", "tesseract-data-eng"])
      assert.ok(pkgbuild.includes(dependency), dependency);
    assert.equal(spawnSync("bash", ["-n", join(output, "PKGBUILD")]).status, 0);
    const srcinfo = await readFile(join(output, ".SRCINFO"), "utf8");
    for (const dependency of ["grim", "slurp", "gpu-screen-recorder", "util-linux", "ffmpeg", "qt6-multimedia",
      "qt6-multimedia-ffmpeg", "xdg-terminal-exec", "nautilus", "sudo"]) {
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
