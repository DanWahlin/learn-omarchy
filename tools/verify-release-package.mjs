import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { lstat, mkdtemp, mkdir, readFile, readdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { packageVersion } from "./prepare-release.mjs";

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    encoding: "utf8", timeout: 60000, maxBuffer: 16 * 1024 * 1024, ...options,
  });
  if (result.error || result.status !== 0)
    throw new Error(`${command} failed: ${result.error?.message || result.stderr || result.stdout}`);
  return result.stdout;
}

export function validatePackagePaths(entries) {
  const seen = new Set();
  for (const entry of entries) {
    const normalized = entry.replace(/\/$/, "");
    if (!normalized || entry.startsWith("/") || entry.includes("\\") || /[\r\n\0]/.test(entry) ||
        normalized.split("/").some(part => ["", ".", "..", ".git", "node_modules", ".learn-omarchy-practice", ".env"].includes(part)) ||
        seen.has(normalized)) throw new Error("Package contains unsafe, duplicate, or development-only paths.");
    if (![".PKGINFO", ".BUILDINFO", ".MTREE"].includes(normalized) &&
        normalized !== "usr" && !normalized.startsWith("usr/"))
      throw new Error("Package contains files outside its application installation.");
    seen.add(normalized);
  }
}

async function files(root, relative = "") {
  const result = new Map();
  for (const name of await readdir(join(root, relative))) {
    const path = relative ? `${relative}/${name}` : name;
    const stat = await lstat(join(root, path));
    if (stat.isDirectory()) {
      for (const [key, value] of await files(root, path)) result.set(key, value);
    } else if (stat.isFile()) {
      result.set(path, {
        hash: createHash("sha256").update(await readFile(join(root, path))).digest("hex"),
        executable: Boolean(stat.mode & 0o111),
      });
    } else throw new Error(`Package contains a link or special entry: ${path}`);
  }
  return result;
}

export async function verifyPackage(packagePath, sourceRoot) {
  packagePath = resolve(packagePath);
  sourceRoot = resolve(sourceRoot);
  const entries = run("bsdtar", ["-tf", packagePath]).trim().split("\n");
  validatePackagePaths(entries);
  const types = run("bsdtar", ["-tvf", packagePath]).trim().split("\n");
  if (types.some(line => !["-", "d"].includes(line[0])))
    throw new Error("Package archive contains links or special files.");
  const metadata = run("bsdtar", ["-xOf", packagePath, ".PKGINFO"]);
  const version = packageVersion(JSON.parse(await readFile(join(sourceRoot, "package.json"), "utf8")).version);
  assert.match(metadata, /^pkgname = learn-omarchy$/m);
  assert.ok(metadata.split("\n").includes(`pkgver = ${version}-1`), "package version matches the source");
  assert.match(metadata, /^depend = omarchy$/m, "the Omarchy runtime dependency must remain in the package");
  assert.match(metadata, /^license = MIT$/m);
  assert.match(metadata, /^license = CC-BY-4.0$/m);
  assert.match(metadata, /^license = CC0-1.0$/m);
  const directory = await mkdtemp(join(tmpdir(), "learn-package-verification-"));
  try {
    const extracted = join(directory, "extracted");
    const expected = join(directory, "expected");
    const home = join(directory, "home");
    await mkdir(extracted);
    await mkdir(home);
    run("bsdtar", ["-xf", packagePath, "-C", extracted, "--no-same-owner"]);
    const env = { ...process.env, HOME: home,
      XDG_STATE_HOME: join(home, "state"), XDG_CONFIG_HOME: join(home, "config"),
      LEARN_OMARCHY_ROOT: "", LEARN_OMARCHY_COURSE: "", LEARN_OMARCHY_CHARACTER: "",
    };
    run("make", ["install", `DESTDIR=${expected}`, "PREFIX=/usr"], { cwd: sourceRoot, env });
    const actualFiles = await files(join(extracted, "usr"));
    const expectedFiles = await files(join(expected, "usr"));
    assert.deepEqual([...actualFiles.keys()].sort(), [...expectedFiles.keys()].sort(),
      "the package contains exactly the source's intended installed files");
    for (const [path, expectedFile] of expectedFiles)
      assert.deepEqual(actualFiles.get(path), expectedFile, `packaged bytes and executable mode: ${path}`);
    const app = join(extracted, "usr/share/learn-omarchy");
    run(process.execPath, ["--experimental-strip-types", join(app, "tools/validate-course.ts"),
      join(app, "courses/omarchy-basics.json")], { cwd: directory, env });
    run(process.execPath, ["--experimental-strip-types", join(app, "tools/validate-course-audio.ts"),
      join(app, "courses/omarchy-basics.json"), "--require-word-timings"], { cwd: directory, env });
    const help = run(join(extracted, "usr/bin/learn-omarchy"), ["--help"], { cwd: directory, env });
    assert.match(help, /prepared automatically/);
    assert.deepEqual(await readdir(home), [], "offline inspection must not modify user configuration");
    return { version, installedFiles: actualFiles.size,
      sha256: createHash("sha256").update(await readFile(packagePath)).digest("hex") };
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  if (![2, 4].includes(args.length) || args[0] !== "--package" ||
      (args.length === 4 && args[2] !== "--source-root")) {
    console.error("Usage: node tools/verify-release-package.mjs --package FILE [--source-root SOURCE]");
    process.exitCode = 1;
  } else {
    verifyPackage(args[1], args[3] || resolve(fileURLToPath(new URL("..", import.meta.url))))
      .then(result => console.log(JSON.stringify({ verified: true, ...result }, null, 2)))
      .catch(error => { console.error(error.message); process.exitCode = 1; });
  }
}
