import { spawnSync } from "node:child_process";
import { mkdir, mkdtemp, realpath, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { packageVersion, prepareRelease } from "./prepare-release.mjs";

const repository = resolve(fileURLToPath(new URL("..", import.meta.url)));

function git(source, args) {
  const result = spawnSync("git", args, {
    cwd: source, encoding: "utf8", maxBuffer: 16 * 1024 * 1024,
  });
  if (result.error || result.status !== 0)
    throw new Error(`git ${args[0]} failed: ${result.error?.message || result.stderr || result.stdout}`);
  return result.stdout.trim();
}

export async function prepareCheckoutPackage(source, output) {
  source = await realpath(source);
  if (await realpath(git(source, ["rev-parse", "--show-toplevel"])) !== source)
    throw new Error("Run package preparation from the Learn Omarchy repository root.");
  if (git(source, ["status", "--porcelain", "--untracked-files=no"]))
    throw new Error("Tracked files have changes. Commit or stash them first; packages use committed source only.");
  const commit = git(source, ["rev-parse", "--verify", "HEAD^{commit}"]);
  const { version } = JSON.parse(git(source, ["show", `${commit}:package.json`]));
  const archVersion = packageVersion(version);
  const epoch = git(source, ["show", "-s", "--format=%ct", commit]);
  if (!/^\d+$/.test(epoch)) throw new Error("Source commit has no valid timestamp.");
  output = resolve(output);
  const temporary = await mkdtemp(join(tmpdir(), "learn-checkout-package-"));
  try {
    const archive = join(temporary, `learn-omarchy-${archVersion}.tar.gz`);
    git(source, ["archive", "--format=tar.gz", `--prefix=learn-omarchy-${archVersion}/`,
      `--output=${archive}`, commit]);
    await mkdir(dirname(output), { recursive: true });
    const result = await prepareRelease(archive, output);
    await writeFile(join(output, "CHECKOUT-INFO.json"), JSON.stringify({
      commit, version, archVersion, sourceDateEpoch: Number(epoch), sourceSha256: result.checksum,
      scope: "Local checkout preparation; not a published or graphically accepted release.",
    }, null, 2) + "\n");
    return { ...result, commit, epoch };
  } finally {
    await rm(temporary, { recursive: true, force: true });
  }
}

async function main(args) {
  if (args.length === 1 && ["--help", "-h"].includes(args[0])) {
    console.log("Usage: node tools/prepare-checkout-package.mjs [--output NEW_DIRECTORY]\n"
      + "Prepares a checksummed Arch recipe from the clean committed checkout.\n"
      + "Does not build, install dependencies, install the app, tag, or publish.");
    return;
  }
  if (args.length && (args.length !== 2 || args[0] !== "--output" || !args[1] || args[1].startsWith("--")))
    throw new Error("Usage: node tools/prepare-checkout-package.mjs [--output NEW_DIRECTORY]");
  const output = args[1] || join(repository, "release-work", "local");
  const result = await prepareCheckoutPackage(repository, output);
  const quote = value => "'" + value.replaceAll("'", "'\\''") + "'";
  console.log(`Prepared ${result.packageVersion} from ${result.commit}\nSource SHA256: ${result.checksum}\n`
    + "Review PKGBUILD first. Then, on Omarchy, build and install as your regular user:\n\n"
    + `cd ${quote(result.output)}\nSOURCE_DATE_EPOCH=${result.epoch} makepkg --syncdeps --install\n\n`
    + "makepkg/pacman will request permission and confirmation for dependencies and installation.\n"
    + "For a build without installation, omit --syncdeps and --install (dependencies must already be present).");
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  main(process.argv.slice(2)).catch(error => { console.error(error.message); process.exitCode = 1; });
