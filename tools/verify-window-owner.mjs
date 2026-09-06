import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";

export async function verifyWindowOwner(pid, token, readEnvironment = readFile) {
  if (!/^[1-9][0-9]*$/.test(String(pid)) || !Number.isSafeInteger(Number(pid)) ||
      typeof token !== "string" || !/^[a-zA-Z0-9-]{16,128}$/.test(token)) return false;
  let environment;
  try {
    environment = await readEnvironment(`/proc/${pid}/environ`, "utf8");
  } catch (error) {
    if (["ENOENT", "ESRCH", "EACCES", "EPERM"].includes(error.code)) return false;
    throw error;
  }
  return environment.split("\0").includes(`LEARN_OMARCHY_WINDOW_TOKEN=${token}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    process.exitCode = await verifyWindowOwner(process.argv[2], process.argv[3]) ? 0 : 1;
  } catch {
    console.error("Unable to verify tutorial window ownership.");
    process.exitCode = 2;
  }
}
