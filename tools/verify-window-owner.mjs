import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";

export async function verifyWindowOwner(pid, token, readEnvironment = readFile, readCommandLine = readFile) {
  if (!/^[1-9][0-9]*$/.test(String(pid)) || !Number.isSafeInteger(Number(pid)) ||
      typeof token !== "string" || !/^[a-zA-Z0-9-]{16,128}$/.test(token)) return false;
  const unavailable = new Set(["ENOENT", "ESRCH", "EACCES", "EPERM"]);
  try {
    const environment = await readEnvironment(`/proc/${pid}/environ`, "utf8");
    if (environment.split("\0").includes(`LEARN_OMARCHY_WINDOW_TOKEN=${token}`)) return true;
  } catch (error) {
    if (!unavailable.has(error.code)) throw error;
  }
  try {
    const commandLine = await readCommandLine(`/proc/${pid}/cmdline`, "utf8");
    const expected = `--learn-omarchy-window-token=${token}`;
    return commandLine.split("\0").some(argument =>
      argument === expected || argument.split(/\s+/).includes(expected));
  } catch (error) {
    if (unavailable.has(error.code)) return false;
    throw error;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    process.exitCode = await verifyWindowOwner(process.argv[2], process.argv[3]) ? 0 : 1;
  } catch {
    console.error("Unable to verify tutorial window ownership.");
    process.exitCode = 2;
  }
}
