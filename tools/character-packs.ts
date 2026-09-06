import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { defaultUserPackRoot, discoverCharacterPacks, loadCharacterPack } from "../src/character-packs.ts";

const appRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
async function main() {
  const [command, ...args] = process.argv.slice(2);
  if (command === "validate") {
    if (args.length !== 1) throw new Error("Usage: character-packs.ts validate PATH");
    const pack = await loadCharacterPack(args[0]);
    console.log(`Valid character pack: ${pack.manifest.displayName} (${pack.id})`);
    for (const diagnostic of pack.diagnostics) console.log(`Warning: ${diagnostic}`);
    return;
  }
  if (command !== "discover" && command !== "check-bundled") throw new Error("Usage: character-packs.ts discover [--bundled-root PATH] [--user-root PATH] | validate PATH | check-bundled");
  let bundledRoot = join(appRoot, "assets", "characters");
  let userRoot: string | undefined = command === "check-bundled" ? undefined
    : defaultUserPackRoot();
  for (let i = 0; i < args.length; i += 2) {
    const allowed = command === "check-bundled" ? ["--bundled-root"] : ["--bundled-root", "--user-root"];
    if (!allowed.includes(args[i]) || !args[i + 1] || args[i + 1].startsWith("--"))
      throw new Error(`Invalid option: ${args[i]}`);
    if (args[i] === "--bundled-root") bundledRoot = args[i + 1];
    else userRoot = args[i + 1];
  }
  const catalog = await discoverCharacterPacks({ bundledRoot, userRoot });
  if (command === "discover") console.log(JSON.stringify(catalog));
  else {
    for (const diagnostic of catalog.diagnostics) console.log(diagnostic);
    if (catalog.invalidBundledIds.length || !catalog.packs.length) {
      console.error("Bundled character pack validation failed");
      process.exitCode = 1;
    } else console.log(`Validated bundled character packs: ${catalog.packs.map(pack => pack.id).join(", ")}`);
  }
}
main().catch(error => {
  if (process.argv[2] === "discover") console.log(JSON.stringify({
    version: 1, packs: [], fallbackId: null, invalidBundledIds: [], diagnostics: [error.message],
  }));
  else console.error(`Character packs: ${error.message}`);
  process.exitCode = 1;
});
