import assert from "node:assert/strict";
import test from "node:test";
import { EventEmitter } from "node:events";
import { spawn, spawnSync } from "node:child_process";
import { access, lstat, mkdir, mkdtemp, readFile, readdir, rm, symlink, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { classifyLaunchCommand, desktopCommand, launchDetached, launchPrepared, parseArguments, parseDesktopExec, prepareLaunch } from "../tools/tutorial-launch.mjs";

const token = "tutorial-launch-123456789";
const options = { kind: "terminal", token };

test("native course launch commands classify without executing launch-or-focus scripts", async () => {
  const forms: [string, string[]][] = [
    ["terminal", ["omarchy", "launch", "terminal"]],
    ["terminal", ["omarchy-launch-terminal"]],
    ["browser", ["omarchy", "launch", "browser"]],
    ["browser", ["omarchy-launch-browser"]],
    ["activity", ["omarchy-launch-or-focus-tui", "btop"]],
    ["activity", ["btop"]],
    ["activity", ["xdg-terminal-exec", "btop"]],
    ["activity", ["xdg-terminal-exec", "-e", "btop"]],
    ["activity", ["xdg-terminal-exec", "--app-id=org.learn-omarchy.toolbox", "--title=Learn Omarchy activity", "-e", "btop"]],
  ];
  for (const [kind, command] of forms) {
    assert.equal(classifyLaunchCommand(command), kind);
    const parsed = parseArguments(["--token", token, "--detach", "--", ...command]);
    assert.deepEqual(parsed, { kind, token, detach: true });
    const plan = await prepareLaunch(parsed, dependencies());
    assert.notEqual(plan.executable, command[0]);
    if (kind === "activity") assert.deepEqual(plan.args.slice(-2), ["-e", "btop"]);
  }
  for (const command of [
    [], ["omarchy", "launch", "files"], ["omarchy-launch-or-focus-tui", "btop; echo unsafe"],
    ["omarchy-launch-or-focus-tui", "btop", "--other"], ["xdg-terminal-exec", "-e", "sh"],
    ["env", "NAME=value", "omarchy", "launch", "terminal"], ["btop", "extra"],
  ]) assert.throws(() => classifyLaunchCommand(command), /Unsupported tutorial launch command/);
  assert.throws(() => parseArguments(["--kind", "browser", "--token", token, "--", "btop"]), /does not match/);
});

test("the current course activity monitor command uses the safe activity adapter", async () => {
  const course = JSON.parse(await readFile(new URL("../courses/omarchy-basics.json", import.meta.url), "utf8"));
  const monitor = course.lessons.flatMap((lesson: any) => lesson.steps).find((step: any) => step.id === "tools-monitor-open");
  assert.equal(classifyLaunchCommand(monitor.help.command), "activity");
});

function dependencies(terminal = "/usr/bin/ghostty\0--gtk-single-instance=true\0", browser = "/usr/bin/google-chrome-stable %U") {
  const calls: unknown[][] = [];
  return {
    calls,
    env: { HOME: "/home/test user", PATH: "/usr/bin", BROWSER: "untrusted-browser", LEARN_OMARCHY_WINDOW_TOKEN: "older-parent-token" },
    query: (command: string, args: string[], env: Record<string, string>) => {
      calls.push([command, args, env]);
      if (command === "xdg-terminal-exec") return terminal;
      assert.equal(command, "xdg-settings");
      assert.deepEqual(args, ["get", "default-web-browser"]);
      assert.equal(env.BROWSER, undefined);
      return "google-chrome.desktop\n";
    },
    readFile: async (path: string) => {
      calls.push(["read", path]);
      return `[Desktop Entry]\nType=Application\nExec=${browser}\n[Desktop Action incognito]\nExec=untrusted-other-browser`;
    },
    executable: async (command: string) => command,
  };
}

test("CLI accepts only explicit intents and exact verifier-compatible tokens", () => {
  assert.deepEqual(parseArguments(["--kind", "activity", "--token", token, "--check", "--profile-root", "path with spaces"]),
    { kind: "activity", token, check: true, profileRoot: "path with spaces" });
  assert.deepEqual(parseArguments(["--kind", "terminal", "--token", token, "--detach"]), { kind: "terminal", token, detach: true });
  for (const args of [
    [], ["--kind", "shell", "--token", token], ["--kind", "terminal", "--token", "short"],
    ["--kind", "terminal", "--token", `${token}\0`],
    ["--kind", "terminal", "--token", `${token};exec`],
    ["--kind", "terminal", "--token", "a".repeat(129)],
    ["--kind", "terminal", "--token", token, "--", "rm"],
    ["--kind", "terminal", "--kind", "browser", "--token", token],
    ["--kind", "terminal", "--token", token, "--check", "--check"],
    ["--kind", "terminal", "--token", token, "--check", "--detach"],
  ]) assert.throws(() => parseArguments(args));
});

test("desktop Exec parser handles spaces without shell evaluation and rejects ambiguous entries", () => {
  assert.deepEqual(parseDesktopExec('"/path with spaces/browser" --new-window %U'), ["/path with spaces/browser", "--new-window", "%U"]);
  assert.deepEqual(parseDesktopExec('"/path/with\\\\slash/browser" %u'), ["/path/with\\slash/browser", "%u"]);
  for (const value of ["", 'browser "unclosed', "browser \\", "browser $(touch sentinel)", "browser;other", "browser 'quoted'", "browser\0"]) {
    assert.throws(() => parseDesktopExec(value));
  }
  assert.deepEqual(desktopCommand("[Desktop Entry]\nType=Application\nExec=chromium %U\n[Desktop Action other]\nExec=evil"), ["chromium", "%U"]);
  assert.deepEqual(desktopCommand("[Desktop Entry]\nType=Application\nExec=chromium %U\nStartupWMClass=Chrome\nStartupWMClass=chrome"), ["chromium", "%U"]);
  for (const entry of [
    "[Desktop Entry]\nType=Application\nExec=chromium\nExec=evil",
    "[Desktop Entry]\nType=Application\nHidden=true\nExec=chromium",
    "[Desktop Entry]\nType=Link\nExec=chromium",
    "[Desktop Action other]\nType=Application\nExec=chromium",
  ]) assert.throws(() => desktopCommand(entry));
});

test("Ghostty launches a fresh instance with a unique activity class and usable initial character size", async () => {
  const deps = dependencies();
  const normal = await prepareLaunch(options, deps);
  assert.equal(normal.executable, "/usr/bin/ghostty");
  assert.ok(normal.args.includes("--gtk-single-instance=false"));
  assert.ok(!normal.args.includes("--gtk-single-instance=true"));
  assert.equal(normal.appId, `org.learn-omarchy.terminal.t${token}`);
  assert.ok(normal.args.includes(`--class=${normal.appId}`));
  const monitor = await prepareLaunch({ ...options, kind: "activity" }, deps);
  assert.equal(monitor.appId, `org.learn-omarchy.activity.t${token}`);
  assert.ok(monitor.args.includes("--window-width=120"));
  assert.ok(monitor.args.includes("--window-height=36"));
  assert.deepEqual(monitor.args.slice(-2), ["-e", "btop"]);
  assert.deepEqual(deps.calls[0]?.slice(0, 2), ["xdg-terminal-exec", ["--print-cmd=\\0"]]);
  assert.equal(deps.env.LEARN_OMARCHY_WINDOW_TOKEN, "older-parent-token");
});

test("Foot uses a fresh process, not footclient; unsupported terminal configuration fails closed", async () => {
  const plan = await prepareLaunch({ ...options, kind: "activity" }, dependencies("/usr/bin/foot\0"));
  assert.deepEqual(plan.args, [`--app-id=${plan.appId}`, "--title=Learn Omarchy activity", "--window-size-chars=120x36", "btop"]);
  for (const command of [
    "/usr/bin/footclient\0", "/usr/bin/foot\0--server\0",
    "/usr/bin/ghostty\0-e\0sh\0", "/usr/bin/ghostty\0--config-file=/unknown\0",
    "/usr/bin/unknown-terminal\0", "/usr/bin/ghostty\n--gtk-single-instance=true\n",
  ]) await assert.rejects(prepareLaunch(options, dependencies(command)), /no supported independent launch adapter/);
  await assert.rejects(prepareLaunch(options, { ...dependencies(), query: () => { throw new Error("not installed"); } }), /Cannot resolve/);
});

test("browser resolves the configured desktop safely and bypasses profile-reusing wrapper scripts", async () => {
  const deps = dependencies();
  const plan = await prepareLaunch({ ...options, kind: "browser", profileRoot: "directory with spaces" }, deps);
  assert.equal(plan.executable, "/opt/google/chrome/chrome");
  assert.equal(plan.profileRoot, resolve("directory with spaces"));
  assert.ok(plan.args.includes("--disable-background-mode"));
  assert.equal(plan.args.at(-1), "about:blank");
  assert.equal(plan.args.some((arg: string) => arg.startsWith("--user-data-dir")), false);
  assert.ok(deps.calls.some(call => call[1] === "/home/test user/.local/share/applications/google-chrome.desktop"));
  const chromium = await prepareLaunch({ ...options, kind: "browser" }, dependencies(undefined, "chromium %U"));
  assert.equal(chromium.executable, "/usr/lib/chromium/chromium");
  await assert.rejects(prepareLaunch({ ...options, kind: "browser" }, {
    ...deps, executable: async () => { throw new Error("Required executable is unavailable"); },
  }), /unavailable/);
});

test("unknown browsers, shell launchers, custom profiles and unsafe desktop IDs cannot trigger fallback", async () => {
  for (const browser of [
    "firefox %U", "unrecognized-browser %U", "env chromium %U",
    "/custom/chromium %U", "chromium --user-data-dir=/home/user/profile",
    "chromium --remote-debugging-port=9222", '"/path with spaces/google-chrome" %U',
    "chromium https://example.com", "sh -c chromium", "chromium %i",
  ]) await assert.rejects(prepareLaunch({ ...options, kind: "browser" }, dependencies(undefined, browser)), /no supported isolated launch adapter/);
  for (const id of ["../evil.desktop", "/etc/evil.desktop", "chrome.desktop\nother.desktop", "chrome.desktop;evil"]) {
    await assert.rejects(prepareLaunch({ ...options, kind: "browser" }, {
      ...dependencies(), query: () => id, readFile: async () => assert.fail("Invalid desktop ID must not read files"),
    }), /desktop ID/);
  }
});

test("browser desktop lookup respects XDG precedence and never skips malformed user overrides", async () => {
  const paths: string[] = [];
  const deps = dependencies();
  const plan = await prepareLaunch({ ...options, kind: "browser" }, {
    ...deps, env: { XDG_DATA_HOME: "/custom data", XDG_DATA_DIRS: "/first:/second" },
    readFile: async (path: string) => {
      paths.push(path);
      if (path.startsWith("/custom data/")) throw Object.assign(new Error("missing"), { code: "ENOENT" });
      return "[Desktop Entry]\nType=Application\nExec=chromium %U";
    },
  });
  assert.equal(plan.executable, "/usr/lib/chromium/chromium");
  assert.deepEqual(paths, ["/custom data/applications/google-chrome.desktop", "/first/applications/google-chrome.desktop"]);
  await assert.rejects(prepareLaunch({ ...options, kind: "browser" }, {
    ...deps, readFile: async () => "malformed user override",
  }), /no usable desktop Exec/);
});

async function withDirectory(run: (directory: string) => Promise<void>) {
  const directory = await mkdtemp(resolve("tests/.tutorial-launch-"));
  try { await run(directory); } finally { await rm(directory, { recursive: true, force: true }); }
}

test("isolated profiles are private, unique, argument-safe and removed only after their process exits", async () => {
  await withDirectory(async directory => {
    const root = join(directory, "profile root with spaces");
    await mkdir(root);
    const existingProfile = join(root, "existing-profile");
    await mkdir(existingProfile);
    await writeFile(join(existingProfile, "history"), "existing history");
    const observed: string[] = [];
    for (let i = 0; i < 2; i++) {
      const plan = await prepareLaunch({ ...options, kind: "browser", profileRoot: root }, dependencies());
      const signals = new EventEmitter();
      const env = { LEARN_OMARCHY_WINDOW_TOKEN: "parent-token", CHROME_USER_FLAGS: "--user-data-dir=existing-profile" };
      const launch = launchPrepared(plan, {
        signals, env,
        spawn: (command: string, args: string[], spawnOptions: any) => {
          assert.equal(command, "/opt/google/chrome/chrome");
          assert.equal(spawnOptions.shell, false);
          assert.equal(spawnOptions.env.LEARN_OMARCHY_WINDOW_TOKEN, token);
          assert.equal(spawnOptions.env.CHROME_USER_FLAGS, undefined);
          const profile = args[0]!.slice("--user-data-dir=".length);
          assert.equal(spawnOptions.env.XDG_CONFIG_HOME, profile);
          observed.push(profile);
          const child = new EventEmitter();
          setImmediate(async () => {
            assert.equal((await lstat(profile)).mode & 0o777, 0o700);
            await writeFile(join(profile, "test-data"), "owned");
            child.emit("close", 0, null);
          });
          return child;
        },
      });
      assert.equal((await launch).code, 0);
      await assert.rejects(access(observed[i]!), { code: "ENOENT" });
      assert.equal(signals.listenerCount("SIGTERM"), 0);
      assert.equal(env.LEARN_OMARCHY_WINDOW_TOKEN, "parent-token");
    }
    assert.notEqual(observed[0], observed[1]);
    assert.equal(await readFile(join(existingProfile, "history"), "utf8"), "existing history");
  });
});

test("failed spawn and nonzero exits clean only the allocated profile and report the error", async () => {
  await withDirectory(async directory => {
    const plan = await prepareLaunch({ ...options, kind: "browser", profileRoot: directory }, dependencies());
    for (const failure of ["throw", "error", "exit"]) {
      await assert.rejects(launchPrepared(plan, {
        signals: new EventEmitter(),
        spawn: () => {
          if (failure === "throw") throw new Error("spawn failed");
          const child = new EventEmitter();
          setImmediate(() => failure === "error" ? child.emit("error", new Error("spawn failed")) : child.emit("close", 7, null));
          return child;
        },
      }), failure === "exit" ? /exited \(7\)/ : /spawn failed/);
      assert.deepEqual(await readdir(directory), []);
    }
  });
});

test("cancellation signals only the newly spawned process, waiting for exit before cleanup", async () => {
  await withDirectory(async directory => {
    const plan = await prepareLaunch({ ...options, kind: "browser", profileRoot: directory }, dependencies());
    const signals = new EventEmitter();
    const killed: string[] = [];
    let profile = "";
    const result = await launchPrepared(plan, {
      signals,
      spawn: (_command: string, args: string[]) => {
        profile = args[0]!.slice("--user-data-dir=".length);
        const child = Object.assign(new EventEmitter(), {
          kill: (signal: string) => {
            killed.push(signal);
            setImmediate(() => child.emit("close", null, signal));
            return true;
          },
        });
        setImmediate(async () => {
          signals.emit("SIGTERM");
          await access(profile);
        });
        return child;
      },
    });
    assert.deepEqual(killed, ["SIGTERM"]);
    assert.equal(result.signal, "SIGTERM");
    await assert.rejects(access(profile), { code: "ENOENT" });
  });
});

test("profile cleanup never follows a replacement symlink into an existing user profile", async () => {
  await withDirectory(async directory => {
    const existing = join(directory, "existing");
    await mkdir(existing);
    await writeFile(join(existing, "history"), "keep");
    const plan = await prepareLaunch({ ...options, kind: "browser", profileRoot: directory }, dependencies());
    await assert.rejects(launchPrepared(plan, {
      signals: new EventEmitter(),
      spawn: (_command: string, args: string[]) => {
        const child = new EventEmitter();
        const profile = args[0]!.slice("--user-data-dir=".length);
        setImmediate(async () => {
          await rm(profile, { recursive: true });
          await symlink(existing, profile);
          child.emit("close", 0, null);
        });
        return child;
      },
    }), /Refusing cleanup/);
    assert.equal(await readFile(join(existing, "history"), "utf8"), "keep");
  });
});

test("real environment-only child and descendant satisfy exact /proc token verification without desktop launches", async () => {
  const helper = new URL("../tools/verify-window-owner.mjs", import.meta.url).href;
  const code = `import { verifyWindowOwner } from ${JSON.stringify(helper)};
    import { spawnSync } from "node:child_process";
    if (!await verifyWindowOwner(process.pid, ${JSON.stringify(token)})) process.exit(5);
    const nested = spawnSync(process.execPath, ["--input-type=module", "-e",
      'import { verifyWindowOwner } from ${JSON.stringify(helper)}; process.exitCode = await verifyWindowOwner(process.pid, ${JSON.stringify(token)}) ? 0 : 6;'
    ], { env: process.env });
    process.exitCode = nested.status;`;
  const plan = await prepareLaunch(options, dependencies());
  const result = await launchPrepared(plan, {
    env: { ...process.env, LEARN_OMARCHY_WINDOW_TOKEN: "stale-parent-token" },
    signals: new EventEmitter(),
    spawn: (_command: string, _args: string[], spawnOptions: any) =>
      spawn(process.execPath, ["--input-type=module", "-e", code], spawnOptions),
  });
  assert.equal(result.code, 0);
});

test("invalid CLI input reports structured failure without launching any desktop process", () => {
  const child = spawnSync(process.execPath, ["tools/tutorial-launch.mjs", "--kind", "browser", "--token", "invalid"], { encoding: "utf8" });
  assert.equal(child.status, 2);
  assert.deepEqual(JSON.parse(child.stderr), { ok: false, error: "Invalid tutorial launch token." });
});

test("detached launcher returns spawn acknowledgement and releases its worker without terminating it", async () => {
  const signals = new EventEmitter();
  const result = await launchDetached({ ...options, detach: true, profileRoot: "path with spaces" }, {
    signals,
    fork: (path: string, args: string[], forkOptions: any) => {
      assert.ok(path.endsWith("/tools/tutorial-launch.mjs"));
      assert.deepEqual(args, ["--worker", "--kind", "terminal", "--token", token, "--profile-root", resolve("path with spaces")]);
      assert.equal(forkOptions.detached, true);
      assert.deepEqual(forkOptions.stdio, ["ignore", "ignore", "ignore", "ipc"]);
      const worker = Object.assign(new EventEmitter(), {
        connected: true,
        disconnect: () => { worker.connected = false; },
        unref: () => assert.equal(worker.connected, false),
        kill: () => assert.fail("Successful worker must survive launcher exit"),
      });
      setImmediate(() => worker.emit("message", { ok: true, state: "spawned", kind: "terminal", pid: 123 }));
      return worker;
    },
  });
  assert.equal(result.state, "spawned");
  assert.equal(result.pid, 123);
  assert.equal(signals.listenerCount("SIGTERM"), 0);
});

test("detached launcher reports worker startup errors, early exit, and cancellation", async () => {
  for (const failure of ["message", "error", "exit", "cancel"]) {
    const signals = new EventEmitter();
    const killed: string[] = [];
    await assert.rejects(launchDetached(options, {
      signals,
      fork: () => {
        const worker = Object.assign(new EventEmitter(), {
          connected: true,
          disconnect: () => { worker.connected = false; },
          unref: () => {},
          kill: (signal: string) => { killed.push(signal); },
        });
        setImmediate(() => {
          if (failure === "message") worker.emit("message", { ok: false, error: "unsupported browser" });
          if (failure === "error") worker.emit("error", new Error("fork failed"));
          if (failure === "exit") worker.emit("exit", 2, null);
          if (failure === "cancel") signals.emit("SIGTERM");
        });
        return worker;
      },
    }), /unsupported browser|fork failed|exited before|cancelled/);
    assert.deepEqual(killed, failure === "cancel" ? ["SIGTERM"] : []);
    assert.equal(signals.listenerCount("SIGTERM"), 0);
  }
});

test("a real environment-only IPC worker survives the short launcher parent exiting", async () => {
  await withDirectory(async directory => {
    const marker = join(directory, "worker-finished");
    const module = new URL("../tools/tutorial-launch.mjs", import.meta.url).href;
    const workerCode = `import { writeFileSync } from "node:fs";
      process.send({ ok: true, state: "spawned", kind: "terminal", pid: process.pid });
      process.on("disconnect", () => setTimeout(() => writeFileSync(${JSON.stringify(marker)}, "survived"), 120));`;
    const parentCode = `import { launchDetached } from ${JSON.stringify(module)};
      import { spawn } from "node:child_process";
      const result = await launchDetached(${JSON.stringify(options)}, {
        fork: (_path, _args, options) => spawn(process.execPath, ["--input-type=module", "-e", ${JSON.stringify(workerCode)}], options)
      });
      console.log(JSON.stringify(result));`;
    const parent = spawnSync(process.execPath, ["--input-type=module", "-e", parentCode], { encoding: "utf8", timeout: 3000 });
    assert.equal(parent.status, 0, parent.stderr);
    assert.equal(JSON.parse(parent.stdout).state, "spawned");
    for (let attempt = 0; attempt < 100; attempt++) {
      try {
        assert.equal(await readFile(marker, "utf8"), "survived");
        return;
      } catch (error: any) {
        if (error.code !== "ENOENT") throw error;
        await new Promise(resolve => setTimeout(resolve, 20));
      }
    }
    assert.fail("Worker did not finish after its launcher parent exited");
  });
});

test("real detached CLI relays an unsupported resolver error without desktop launches", () => {
  const child = spawnSync(process.execPath, [
    "tools/tutorial-launch.mjs", "--kind", "terminal", "--token", token, "--detach",
  ], { env: { ...process.env, PATH: "/nonexistent-tutorial-test-bin" }, encoding: "utf8", timeout: 3000 });
  assert.equal(child.status, 2, child.stderr);
  assert.equal(child.stdout, "");
  assert.match(JSON.parse(child.stderr).error, /Cannot resolve the configured terminal safely/);
});
