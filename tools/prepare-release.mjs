import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { copyFile, mkdir, readFile, writeFile } from "node:fs/promises";
import { basename, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repository = resolve(fileURLToPath(new URL("..", import.meta.url)));
const versionPattern = /^\d+\.\d+\.\d+(?:[a-z]+\d*)?$/;
const identifierPattern = /^[A-Za-z0-9][A-Za-z0-9.+-]*$/;

export function packageVersion(version) {
  if (typeof version !== "string") throw new Error("A release version is required.");
  const match = version.match(/^(\d+\.\d+\.\d+)(?:-(alpha|beta|rc)\.(\d+))?$/);
  if (!match) throw new Error("Use a release version such as 1.2.3 or 1.2.3-rc.1.");
  return match[1] + (match[2] ? match[2] + match[3] : "");
}

// This verifies recorded decisions and shipped notices, not ownership or legal permission.
export async function checkLicenses(read) {
  const problems = [];
  async function json(path) {
    try { return JSON.parse(await read(path)); }
    catch { problems.push(`${path}: missing or invalid`); return {}; }
  }
  const policy = await json("packaging/release-licenses.json");
  if (policy.status !== "approved")
    problems.push("Owner approval is pending for code and original artwork (including splash/icon, course text, narration, and original sounds).");
  for (const field of ["codeLicense", "artLicense"])
    if (!identifierPattern.test(policy[field] || ""))
      problems.push(`${field}: an owner-approved SPDX identifier is required.`);
  for (const path of ["LICENSE", "LICENSE-ASSETS.md", "LICENSES/CC0-1.0.txt"]) {
    try {
      if (!(await read(path)).toString().trim()) throw new Error("empty");
    } catch { problems.push(`${path}: missing or empty license notice.`); }
  }
  if (identifierPattern.test(policy.artLicense || "")) {
    const path = `LICENSES/${policy.artLicense}.txt`;
    try { if (!(await read(path)).toString().trim()) throw new Error("empty"); }
    catch { problems.push(`${path}: full artwork license text is required.`); }
  }
  const pkg = await json("package.json");
  const expected = [...new Set([policy.codeLicense, policy.artLicense, "CC0-1.0"])].sort();
  if (JSON.stringify((pkg.license || "").split(" AND ").sort()) !== JSON.stringify(expected))
    problems.push("package.json: license expression must match approved code/art licenses and the retained CC0-1.0 recording.");
  for (const id of ["ohm-1", "owl"]) {
    const path = `assets/characters/${id}/character.json`;
    const manifest = await json(path);
    if (manifest.author?.status !== "declared" || !manifest.author?.name?.trim())
      problems.push(`${path}: author attribution is unresolved.`);
    if (manifest.license?.status !== "declared" || manifest.license?.identifier !== policy.artLicense)
      problems.push(`${path}: artwork licensing is unresolved or differs from approval.`);
  }
  const splash = await json("assets/splash/provenance.json");
  if (splash.license?.status !== "declared" || splash.license?.identifier !== policy.artLicense)
    problems.push("assets/splash/provenance.json: splash licensing is unresolved or differs from approval.");
  const birds = await json("assets/sounds/birds-welcome.provenance.json");
  if (birds.license !== "CC0-1.0" || !birds.creator || !birds.sourceUrl || !/^[a-f0-9]{64}$/.test(birds.sourceSha256 || ""))
    problems.push("Bird recording: retain the existing CC0-1.0 license, creator, source, and source hash.");
  try {
    const digest = createHash("sha256").update(await read("assets/sounds/birds-welcome.opus")).digest("hex");
    if (digest !== birds.outputSha256) problems.push("Bird recording: output hash does not match its provenance.");
  } catch { problems.push("Bird recording: runtime audio is missing."); }
  return { problems, policy, version: pkg.version };
}

function tar(args) {
  const result = spawnSync("tar", args, { maxBuffer: 16 * 1024 * 1024, env: { ...process.env, LC_ALL: "C" } });
  if (result.status !== 0) throw new Error(`Cannot inspect archive: ${result.stderr?.toString().trim() || result.error?.message}`);
  return result.stdout;
}

export function inspectArchive(archive) {
  const entries = tar(["-tzf", archive]).toString().trim().split("\n");
  const roots = new Set(entries.map(entry => entry.split("/")[0]));
  if (roots.size !== 1) throw new Error("Archive must have exactly one versioned root directory.");
  const root = [...roots][0];
  const version = root.slice("learn-omarchy-".length);
  if (!root.startsWith("learn-omarchy-") || !versionPattern.test(version))
    throw new Error("Archive root must be learn-omarchy-VERSION (for example learn-omarchy-0.1.0).");
  const seen = new Set();
  for (const entry of entries) {
    if (entry.includes("\\") || entry.startsWith("/") || entry.split("/").some(part => part === "." || part === "..") || seen.has(entry))
      throw new Error("Archive contains unsafe or duplicate paths.");
    seen.add(entry);
  }
  if (tar(["-tvzf", archive]).toString().trim().split("\n").some(line => !["-", "d"].includes(line[0])))
    throw new Error("Source archives may contain only regular files and directories, not links or special files.");
  return { version, read: async path => {
    const entry = `${root}/${path}`;
    if (!seen.has(entry)) throw new Error(`Archive is missing ${path}`);
    return tar(["-xOzf", archive, "--", entry]);
  } };
}

function srcinfo(pkgbuild, version, checksum, licenses) {
  const values = name => {
    const body = pkgbuild.match(new RegExp(`^${name}=\\(([\\s\\S]*?)\\)$`, "m"))?.[1] || "";
    return [...body.matchAll(/'([^']*)'/g)].map(match => match[1]);
  };
  const fields = [
    ["pkgdesc", "Interactive, theme-aware courses for learning Omarchy"],
    ["pkgver", version], ["pkgrel", "1"], ["url", "https://github.com/DanWahlin/learn-omarchy"],
    ["arch", "any"], ...licenses.map(value => ["license", value]),
    ...["depends", "makedepends", "optdepends", "options"].flatMap(name => values(name).map(value => [name, value])),
    ["source", `learn-omarchy-${version}.tar.gz`], ["sha256sums", checksum],
  ];
  return `pkgbase = learn-omarchy\n${fields.map(([name, value]) => `\t${name} = ${value}`).join("\n")}\n\npkgname = learn-omarchy\n`;
}

export async function prepareRelease(archive, output) {
  archive = resolve(archive);
  const inspected = inspectArchive(archive);
  const { problems, policy, version } = await checkLicenses(inspected.read);
  let archVersion;
  try { archVersion = packageVersion(version); }
  catch (error) { problems.push(error.message); }
  if (archVersion !== inspected.version) problems.push("package.json version does not match the archive directory.");
  for (const path of [
    "Makefile", "bin/learn-omarchy", "app/shell.qml", "tools/remove-legacy-integration.mjs",
    "tools/bar-geometry.mjs", "tools/prepare-release.mjs", "packaging/PKGBUILD.in",
  ]) {
    try { await inspected.read(path); } catch { problems.push(`Missing one-package runtime/build payload: ${path}`); }
  }
  if (problems.length) throw new Error(`Release blocked:\n- ${problems.join("\n- ")}`);
  const checksum = createHash("sha256").update(await readFile(archive)).digest("hex");
  const licenses = [...new Set([policy.codeLicense, policy.artLicense, "CC0-1.0"])];
  const template = (await inspected.read("packaging/PKGBUILD.in")).toString();
  const pkgbuild = template.replaceAll("@VERSION@", archVersion)
    .replaceAll("@SHA256@", checksum).replaceAll("@LICENSES@", licenses.map(value => `'${value}'`).join(" "));
  // Refuse to overwrite an existing release directory, even after a failed build.
  await mkdir(output);
  await copyFile(archive, join(output, `learn-omarchy-${archVersion}.tar.gz`));
  await writeFile(join(output, "PKGBUILD"), pkgbuild);
  await writeFile(join(output, ".SRCINFO"), srcinfo(pkgbuild, archVersion, checksum, licenses));
  return { version, packageVersion: archVersion, checksum, output: resolve(output) };
}

async function main(args) {
  if (args[0] === "--check" && args.length <= 2) {
    const root = resolve(args[1] || repository);
    const { problems } = await checkLicenses(path => readFile(join(root, path)));
    if (problems.length) throw new Error(`Release blocked:\n- ${problems.join("\n- ")}`);
    console.log("Release licensing metadata is approved and internally consistent. This is not a legal ownership determination.");
  } else if (args.length === 4 && args[0] === "--archive" && args[2] === "--output") {
    const result = await prepareRelease(args[1], args[3]);
    console.log(`Prepared ${basename(result.output)} for ${result.version}\nSHA256 ${result.checksum}\nBuild (no installation): cd ${JSON.stringify(result.output)} && makepkg --cleanbuild`);
  } else {
    throw new Error("Usage: node tools/prepare-release.mjs --check [SOURCE_DIR]\n       node tools/prepare-release.mjs --archive EXISTING_VERSIONED.tar.gz --output NEW_DIRECTORY");
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  main(process.argv.slice(2)).catch(error => { console.error(error.message); process.exitCode = 1; });
