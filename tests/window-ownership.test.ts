import assert from "node:assert/strict";
import test from "node:test";
import { spawnSync } from "node:child_process";
import { verifyWindowOwner } from "../tools/verify-window-owner.mjs";

const token = "tutorial-launch-123456789";

test("ownership requires an exact launch token in the client's environment or command line", async () => {
  for (const environment of [
    "", "OTHER=value\0", `LEARN_OMARCHY_WINDOW_TOKEN=${token}-other\0`,
    `OTHER=LEARN_OMARCHY_WINDOW_TOKEN=${token}\0`,
  ]) {
    assert.equal(await verifyWindowOwner(123, token, async () => environment, async () => ""), false);
  }
  assert.equal(await verifyWindowOwner(123, token, async (path: string) => {
    assert.equal(path, "/proc/123/environ");
    return `OTHER=value\0LEARN_OMARCHY_WINDOW_TOKEN=${token}\0`;
  }, async () => assert.fail("An environment match must not read the command line")), true);
  for (const commandLine of [
    `chromium\0--learn-omarchy-window-token=${token}-other\0`,
    `chromium\0prefix--learn-omarchy-window-token=${token}\0`,
  ]) {
    assert.equal(await verifyWindowOwner(123, token, async () => "", async () => commandLine), false);
  }
  assert.equal(await verifyWindowOwner(123, token, async () => "", async (path: string) => {
    assert.equal(path, "/proc/123/cmdline");
    return `chromium\0--learn-omarchy-window-token=${token}\0`;
  }), true);
  assert.equal(await verifyWindowOwner(123, token, async () => "", async () =>
    `chromium --user-data-dir=/tmp/profile --learn-omarchy-window-token=${token} --new-window about:blank\0`), true);
});

test("invalid identities and unavailable process environments never grant ownership", async () => {
  for (const pid of [undefined, 0, -1, "1/../2", "12a", 1.5, Number.MAX_SAFE_INTEGER + 1]) {
    assert.equal(await verifyWindowOwner(pid, token, async () => {
      assert.fail("Invalid process identity must not read the filesystem");
    }), false);
  }
  for (const code of ["ENOENT", "ESRCH", "EACCES", "EPERM"]) {
    assert.equal(await verifyWindowOwner(123, token, async () => {
      throw Object.assign(new Error("Unavailable"), { code });
    }, async () => {
      throw Object.assign(new Error("Unavailable"), { code });
    }), false);
  }
  await assert.rejects(verifyWindowOwner(123, token, async () => {
    throw Object.assign(new Error("Read failed"), { code: "EIO" });
  }, async () => ""), /Read failed/);
});

test("the ownership helper verifies an inherited token in a real isolated process", () => {
  const helper = new URL("../tools/verify-window-owner.mjs", import.meta.url).href;
  for (const inherited of [true, false]) {
    const child = spawnSync(process.execPath, ["--input-type=module", "-e",
      `import { verifyWindowOwner } from ${JSON.stringify(helper)};
       process.exitCode = await verifyWindowOwner(process.pid, ${JSON.stringify(token)}) ? 0 : 1;`,
    ], { env: inherited ? { LEARN_OMARCHY_WINDOW_TOKEN: token } : {}, encoding: "utf8" });
    assert.equal(child.status, inherited ? 0 : 1, child.stderr);
  }
});

test("the ownership helper verifies a real command-line token when the environment is stripped", () => {
  const helper = new URL("../tools/verify-window-owner.mjs", import.meta.url).href;
  const child = spawnSync(process.execPath, ["--input-type=module", "-e",
    `import { verifyWindowOwner } from ${JSON.stringify(helper)};
     process.exitCode = await verifyWindowOwner(process.pid, ${JSON.stringify(token)}) ? 0 : 1;`,
    "--", `--learn-omarchy-window-token=${token}`,
  ], { env: {}, encoding: "utf8" });
  assert.equal(child.status, 0, child.stderr);
});
