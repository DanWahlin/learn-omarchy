import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { copyFile, mkdir, readFile, readdir, writeFile } from "node:fs/promises";
import { resolve, join } from "node:path";
import { fileURLToPath } from "node:url";
import { packageVersion, prepareRelease } from "../prepare-release.mjs";

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    encoding: "utf8", maxBuffer: 32 * 1024 * 1024, ...options,
  });
  if (result.error || result.status !== 0)
    throw new Error(`${command} failed: ${result.error?.message || result.stderr || result.stdout}`);
  return result.stdout;
}

export function candidateIdentity(tag, version) {
  const archVersion = packageVersion(version);
  if (tag !== `v${version}`) throw new Error("Release tag must exactly match package.json version.");
  return { tag, version, archVersion };
}

export async function prepareCandidate(tag) {
  if (process.getuid?.() === 0) throw new Error("Candidate builds must not run as root.");
  const source = process.cwd();
  const pkg = JSON.parse(await readFile("package.json", "utf8"));
  const { version, archVersion } = candidateIdentity(tag, pkg.version);
  const commit = run("git", ["rev-parse", "--verify", `refs/tags/${tag}^{commit}`]).trim();
  if (run("git", ["rev-parse", "HEAD"]).trim() !== commit)
    throw new Error("The checkout must be the exact tagged commit.");
  if (run("git", ["status", "--porcelain", "--untracked-files=no"]).trim())
    throw new Error("Tracked source files must be unchanged before creating a candidate.");
  const epoch = run("git", ["show", "-s", "--format=%ct", commit]).trim();
  if (!/^\d+$/.test(epoch)) throw new Error("Missing source commit timestamp.");
  const env = { ...process.env, SOURCE_DATE_EPOCH: epoch };
  const work = resolve(".ci-release");
  await mkdir(work); // Never reuse an earlier build or mix its artifacts into this candidate.
  const archive = join(work, `learn-omarchy-${archVersion}.tar.gz`);
  run("git", ["archive", "--format=tar.gz", `--prefix=learn-omarchy-${archVersion}/`,
    `--output=${archive}`, commit], { env });
  const build = join(work, "build");
  await prepareRelease(archive, build);

  // Vanilla Arch has no Omarchy repository. This checks packaging, not runtime
  // dependency resolution; the final package must still require real Omarchy.
  run("makepkg", ["--nodeps", "--cleanbuild", "--noconfirm"], { cwd: build, env });
  const packages = (await readdir(build)).filter(name => name.endsWith(".pkg.tar.zst"));
  if (packages.length !== 1 || packages[0] !== `learn-omarchy-${archVersion}-1-any.pkg.tar.zst`)
    throw new Error("Expected exactly one version-matched application package.");
  const binary = join(build, packages[0]);
  const verification = run(process.execPath, ["tools/verify-release-package.mjs",
    "--package", binary, "--source-root", source], { env });
  if (JSON.parse(verification).verified !== true) throw new Error("Package verification did not pass.");
  const dist = join(work, "dist");
  await mkdir(dist);
  for (const name of [packages[0], `learn-omarchy-${archVersion}.tar.gz`, "PKGBUILD", ".SRCINFO"])
    await copyFile(join(build, name), join(dist, name));
  await copyFile(join(source, "packaging/RELEASE-NOTES.md"), join(dist, "RELEASE-NOTES.md"));
  await writeFile(join(dist, "VERIFICATION.json"), verification);
  await writeFile(join(dist, "BUILD-INFO.txt"), [
    `tag=${tag}`, `version=${version}`, `arch_version=${archVersion}`,
    `commit=${commit}`, `SOURCE_DATE_EPOCH=${epoch}`,
    "build=vanilla-arch-packaging-only; makepkg --nodeps; no system installation",
    "", run("pacman", ["-Q"]),
  ].join("\n"));
  await writeFile(join(dist, "RELEASE-NOTES.txt"), [
    `Learn Omarchy ${version} candidate`, "", `Source commit: ${commit}`,
    `Source archive: learn-omarchy-${archVersion}.tar.gz`, "",
    "DRAFT / PRERELEASE: not approved for public or stable release.",
    "Automated Node, offscreen QML, course/audio, licensing, and package-content checks passed.",
    "Built on vanilla Arch with --nodeps because Omarchy is not in the vanilla Arch repositories.",
    "The package retains its real Omarchy dependency. No installation or graphical acceptance is claimed.",
    "Complete packaging/ACCEPTANCE.md against this exact source and package before explicitly publishing.",
    "Review packaging/RELEASE-NOTES.md and packaging/CI.md before promotion.", "",
  ].join("\n"));
  const checksums = [];
  for (const name of (await readdir(dist)).sort()) {
    const digest = createHash("sha256").update(await readFile(join(dist, name))).digest("hex");
    checksums.push(`${digest}  ${name}`);
  }
  await writeFile(join(dist, "SHA256SUMS"), `${checksums.join("\n")}\n`);
  console.log(`Verified draft candidate files: ${dist}`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  prepareCandidate(process.env.RELEASE_TAG).catch(error => {
    console.error(error.message);
    process.exitCode = 1;
  });
