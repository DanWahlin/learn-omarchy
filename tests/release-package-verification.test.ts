import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { launcherHelpPattern, validatePackagePaths } from "../tools/verify-release-package.mjs";

test("release packages contain only application installation paths and package metadata", () => {
  assert.doesNotThrow(() => validatePackagePaths([
    ".PKGINFO", ".BUILDINFO", ".MTREE", "usr/", "usr/bin/", "usr/bin/learn-omarchy",
    "usr/share/learn-omarchy/assets/sounds/birds-welcome.opus",
  ]));
  for (const path of [
    "../escape", "/absolute", "usr/../outside", "usr//bin", "usr\\bin",
    "usr/share/.git/config", "usr/share/node_modules/package.json", "usr/share/.env",
    "usr/share/.learn-omarchy-practice/session/recording.mp4", ".INSTALL", "home/user/settings.json",
  ]) assert.throws(() => validatePackagePaths([path]), undefined, path);
  assert.throws(() => validatePackagePaths(["usr/", "usr"]));
});

test("package verification expects the launcher's current help text", () => {
  const help = spawnSync("bin/learn-omarchy", ["--help"], { encoding: "utf8" });
  assert.equal(help.status, 0, help.stderr);
  assert.match(help.stdout, launcherHelpPattern);
});
