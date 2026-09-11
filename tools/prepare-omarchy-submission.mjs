import { createHash } from "node:crypto";
import { lstat, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { prepareRelease } from "./prepare-release.mjs";

const templates = new URL("../packaging/omarchy-pkgs/", import.meta.url);
const metadataText = await readFile(new URL(".omarchy/package.json", templates), "utf8");
const metadata = JSON.parse(metadataText);
const repository = metadata.upstream.github;
const repositoryUrl = `https://github.com/${repository}`;
const usage = `Usage: node tools/prepare-omarchy-submission.mjs --release vX.Y.Z --output NEW_DIRECTORY
Requires an anonymously accessible stable release at least ${metadata.min_release_age} old.
Verifies the published source archive and prepares package files plus a PR draft.
Does not build, install, publish, change visibility, commit, push, or create a PR.`;

function manifestChecksum(manifest, filename) {
  const entries = new Map();
  for (const line of manifest.trim().split(/\r?\n/)) {
    const match = line.match(/^([a-f0-9]{64}) [ *](?:\.\/)?(\S+)$/);
    if (!match || entries.has(match[2]))
      throw new Error("SHA256SUMS contains malformed or duplicate entries.");
    entries.set(match[2], match[1]);
  }
  if (!entries.has(filename)) throw new Error(`SHA256SUMS is missing ${filename}.`);
  return entries.get(filename);
}

export async function prepareOmarchySubmission(tag, output, { fetch: request = fetch, now = Date.now() } = {}) {
  if (typeof tag !== "string" || !/^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(tag))
    throw new Error("Omarchy submission requires a stable vX.Y.Z tag; drafts and prereleases such as rc.3 are not eligible.");
  output = resolve(output);
  const existing = await lstat(output).catch(error => {
    if (error.code !== "ENOENT") throw error;
    return null;
  });
  if (existing) throw new Error(`Output already exists: ${output}`);
  const version = tag.slice(1);
  const sourceName = metadata.upstream.assets.any.replaceAll("{pkgver}", version);
  const releaseUrl = `${repositoryUrl}/releases/tag/${tag}`;
  const assetUrl = name => `${repositoryUrl}/releases/download/${tag}/${name}`;
  async function download(url) {
    // Deliberately anonymous: a maintainer's gh credentials must not hide a private release.
    const response = await request(url, { signal: AbortSignal.timeout(120_000) });
    if (!response.ok)
      throw new Error(`Cannot read ${url} anonymously (HTTP ${response.status}). A public repository and published stable release are required.`);
    return Buffer.from(await response.arrayBuffer());
  }
  const repo = JSON.parse((await download(`https://api.github.com/repos/${repository}`)).toString());
  if (repo.private !== false || repo.full_name !== repository)
    throw new Error("The expected upstream repository must be public before preparing a submission.");
  const release = JSON.parse((await download(`https://api.github.com/repos/${repository}/releases/tags/${tag}`)).toString());
  if (release.tag_name !== tag || release.draft !== false || release.prerelease !== false)
    throw new Error("The selected release must match the tag and be published as stable, not draft or prerelease.");
  const age = /^(\d+)([smhd]?)$/.exec(String(metadata.min_release_age));
  if (!age) throw new Error("Unsupported min_release_age in Omarchy metadata.");
  const minimumAge = Number(age[1]) * ({ "": 1, s: 1, m: 60, h: 3600, d: 86400 }[age[2]]) * 1000;
  const published = Date.parse(release.published_at);
  if (!Number.isFinite(published) || !Number.isFinite(now) || now - published < minimumAge)
    throw new Error(`The stable release must have a valid publication date and be at least ${metadata.min_release_age} old.`);
  for (const name of [sourceName, metadata.upstream.checksums]) {
    const matches = release.assets?.filter(asset => asset.name === name);
    if (matches?.length !== 1 || matches[0].state !== "uploaded" || matches[0].browser_download_url !== assetUrl(name))
      throw new Error(`Release must contain exactly one uploaded ${name} at its expected public URL.`);
  }
  const [archive, manifest] = await Promise.all([
    download(assetUrl(sourceName)), download(assetUrl(metadata.upstream.checksums)),
  ]);
  const checksum = createHash("sha256").update(archive).digest("hex");
  if (checksum !== manifestChecksum(manifest.toString(), sourceName))
    throw new Error("Downloaded source archive does not match SHA256SUMS.");
  const digest = release.assets.find(asset => asset.name === sourceName).digest;
  if (digest != null && digest !== `sha256:${checksum}`)
    throw new Error("Downloaded source archive does not match GitHub's asset digest.");

  await mkdir(dirname(output), { recursive: true });
  const scratch = await mkdtemp(join(dirname(output), ".learn-omarchy-submission-"));
  let ownsOutput = false;
  try {
    const archivePath = join(scratch, sourceName);
    await writeFile(archivePath, archive);
    const prepared = await prepareRelease(archivePath, join(scratch, "prepared"));
    if (prepared.version !== version || prepared.packageVersion !== version)
      throw new Error("Published source version does not match the stable release tag.");
    const original = await readFile(join(prepared.output, "PKGBUILD"), "utf8");
    const originalSource = 'source=("learn-omarchy-$pkgver.tar.gz")';
    if (original.split(originalSource).length !== 2)
      throw new Error("Upstream PKGBUILD source layout changed; review submission generation before proceeding.");
    // Keep pkgver in the URL so upstream sync can update only pkgver and sha256sums.
    const source = `${repositoryUrl}/releases/download/v$pkgver/learn-omarchy-$pkgver.tar.gz`;
    const pkgbuild = "# Maintainer: Dan Wahlin <dwahlin@gmail.com>\n\n"
      + original.replace(originalSource, `source=("${source}")`);
    const srcinfo = (await readFile(join(prepared.output, ".SRCINFO"), "utf8"))
      .replace(`\tsource = ${sourceName}\n`, `\tsource = ${assetUrl(sourceName)}\n`);
    const values = {
      VERSION: version, RELEASE_URL: releaseUrl, SOURCE_URL: assetUrl(sourceName), SHA256: checksum,
    };
    const body = (await readFile(new URL("PR.md.in", templates), "utf8")).replace(/@([A-Z][A-Z0-9_]*)@/g, (_, key) => {
      if (!(key in values)) throw new Error(`Unknown PR template field: ${key}`);
      return values[key];
    });
    const evidence = {
      repository, tag, version, releaseUrl, sourceUrl: assetUrl(sourceName), sourceSha256: checksum,
      publishedAt: release.published_at, checkedAt: new Date(now).toISOString(),
      anonymousSourceVerified: true, submissionApproved: false,
      acceptance: "Complete packaging/ACCEPTANCE.md stable gates and the generated PR checklist before submission.",
    };
    await mkdir(output);
    ownsOutput = true;
    const packageDirectory = join(output, "pkgbuilds", "learn-omarchy");
    await mkdir(join(packageDirectory, ".omarchy"), { recursive: true });
    await Promise.all([
      writeFile(join(packageDirectory, "PKGBUILD"), pkgbuild),
      writeFile(join(packageDirectory, ".omarchy", "package.json"), metadataText),
      writeFile(join(output, "SRCINFO"), srcinfo),
      writeFile(join(output, "PR.md"), body),
      writeFile(join(output, "SUBMISSION.json"), JSON.stringify(evidence, null, 2) + "\n"),
    ]);
    return { ...evidence, output };
  } catch (error) {
    if (ownsOutput) await rm(output, { recursive: true, force: true });
    throw error;
  } finally {
    await rm(scratch, { recursive: true, force: true });
  }
}

async function main(args) {
  if (args.length === 1 && ["--help", "-h"].includes(args[0])) {
    console.log(usage);
    return;
  }
  if (args.length !== 4 || args[0] !== "--release" || args[2] !== "--output" || !args[3] || args[3].startsWith("--"))
    throw new Error(usage);
  const result = await prepareOmarchySubmission(args[1], args[3]);
  console.log(`Prepared ${result.output}\nSource SHA256: ${result.sourceSha256}\nComplete the PR checklist and obtain submission approval. No PR was created.`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  main(process.argv.slice(2)).catch(error => { console.error(error.message); process.exitCode = 1; });
