import { copyFile, lstat, mkdir, realpath, rename, rm } from "node:fs/promises";
import { dirname, join, relative, resolve, sep } from "node:path";
import { randomUUID } from "node:crypto";
import { pathToFileURL } from "node:url";
import { discoverCharacterPacks } from "../src/character-packs.ts";

async function copyRuntimeFile(source: string, target: string, sourceRoot: string, destinationRoot: string) {
  const resolvedSource = await realpath(source);
  if (!resolvedSource.startsWith(sourceRoot + sep)) throw new Error(`Asset escapes its pack: ${source}`);
  await mkdir(dirname(target), { recursive: true });
  const parent = await realpath(dirname(target));
  if (parent !== destinationRoot && !parent.startsWith(destinationRoot + sep)) {
    throw new Error(`Installation path escapes its pack: ${target}`);
  }
  const stage = join(parent, `.pack-file-${randomUUID()}`);
  try {
    await copyFile(resolvedSource, stage);
    await rename(stage, target);
  } finally {
    await rm(stage, { force: true });
  }
}

export async function installBundledPacks(bundledRoot: string, destination: string) {
  const sourceRoot = await realpath(bundledRoot);
  const output = resolve(destination);
  if (output === sourceRoot || output.startsWith(sourceRoot + sep)) {
    throw new Error("The pack install destination must not overwrite the source packs");
  }
  const catalog = await discoverCharacterPacks({ bundledRoot: sourceRoot });
  if (catalog.invalidBundledIds?.length || catalog.packs.length === 0) {
    throw new Error(`Cannot install invalid bundled packs:\n${catalog.diagnostics.join("\n")}`);
  }
  await mkdir(output, { recursive: true });
  if ((await lstat(output)).isSymbolicLink()) throw new Error("Pack install destination must not be a symlink");
  const destinationRoot = await realpath(output);
  for (const pack of catalog.packs) {
    const packTarget = join(destinationRoot, pack.id);
    await mkdir(packTarget, { recursive: true });
    if ((await lstat(packTarget)).isSymbolicLink()) throw new Error(`Pack destination is a symlink: ${pack.id}`);
    for (const file of pack.runtimeFiles) {
      const target = resolve(packTarget, file);
      if (!relative(packTarget, target) || !target.startsWith(packTarget + sep)) {
        throw new Error(`Invalid runtime file destination: ${file}`);
      }
      await copyRuntimeFile(join(pack.root, file), target, pack.root, packTarget);
    }
  }
  await copyRuntimeFile(join(sourceRoot, "index.json"), join(destinationRoot, "index.json"), sourceRoot, destinationRoot);
  return catalog.packs.map(pack => pack.id);
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  if (process.argv.length !== 4) {
    console.error("Usage: install-character-packs.ts BUNDLED_ROOT DESTINATION");
    process.exitCode = 2;
  } else {
    installBundledPacks(process.argv[2], process.argv[3]).then(ids => {
      console.log(`Installed runtime packs: ${ids.join(", ")}`);
    }).catch(error => {
      console.error(`Character pack installation failed: ${error.message}`);
      process.exitCode = 1;
    });
  }
}
