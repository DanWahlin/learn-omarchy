import assert from "node:assert/strict";
import { mkdtemp, readFile, readdir, rm, symlink, mkdir, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import test from "node:test";
import { spawnSync } from "node:child_process";
import { discoverCharacterPacks } from "../src/character-packs.ts";
import { installBundledPacks } from "../tools/install-character-packs.ts";

const bundledRoot = resolve("assets/characters");

test("installation copies complete validated runtime packs without authoring machinery", async () => {
  const directory = await mkdtemp(resolve(".learn-pack-install-"));
  try {
    const destination = join(directory, "characters");
    const ids = await installBundledPacks(bundledRoot, destination);
    assert.ok(ids.includes("ohm-1") && ids.includes("owl"));
    const installed = await discoverCharacterPacks({ bundledRoot: destination });
    assert.deepEqual(installed.invalidBundledIds, []);
    assert.equal(installed.packs.length, ids.length);
    for (const pack of installed.packs) {
      assert.ok(pack.intro, `${pack.id} retains its intro`);
      for (const file of pack.runtimeFiles) {
        assert.deepEqual(await readFile(join(pack.root, file)), await readFile(join(bundledRoot, pack.id, file)));
      }
      const files = await readdir(pack.root, { recursive: true });
      assert.ok(!files.some(file => /concepts|sprites\.conf|\.qml$|\.js$|\.sh$|\.py$/.test(file)));
    }
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("installation cannot write through a pack-directory symlink or overwrite its source", async () => {
  await assert.rejects(installBundledPacks(bundledRoot, bundledRoot), /overwrite the source/);
  const directory = await mkdtemp(resolve(".learn-pack-install-"));
  try {
    const destination = join(directory, "characters");
    const outside = join(directory, "outside");
    await mkdir(destination);
    await mkdir(outside);
    await symlink(outside, join(destination, "ohm-1"));
    await assert.rejects(installBundledPacks(bundledRoot, destination), /symlink/);
    assert.deepEqual(await readdir(outside), []);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("the package install includes shared pack code and pack-owned intro assets", async () => {
  const directory = await mkdtemp(resolve(".learn-pack-package-"));
  try {
    const home = join(directory, "home");
    await mkdir(join(home, ".local/state/learn-omarchy"), { recursive: true });
    await mkdir(join(home, ".config/omarchy/plugins/learn-omarchy.geometry"), { recursive: true });
    const progress = join(home, ".local/state/learn-omarchy/progress.json");
    const editedIntegration = join(home, ".config/omarchy/plugins/learn-omarchy.geometry/Geometry.js");
    await writeFile(progress, '{"completed":["first-lesson"]}');
    await writeFile(editedIntegration, "// user-owned changes");
    const env = { ...process.env, HOME: home };
    const result = spawnSync("make", ["install", `DESTDIR=${directory}`, "PREFIX=/usr"], { encoding: "utf8", env });
    assert.equal(result.status, 0, result.stderr || result.stdout);
    const root = join(directory, "usr/share/learn-omarchy");
    for (const file of [
      "app/CharacterPackStore.qml", "app/IntroPlayer.qml", "app/CharacterSprite.qml",
      "app/AppSearchSession.qml", "app/app-search.qml",
      "app/PracticeSession.qml", "app/TeachingLayout.js", "tools/tutorial-launch.mjs",
      "app/SplashScreen.qml", "assets/splash/learn-omarchy.png",
      "app/SplashArtwork.qml", "app/InteractionAudio.qml", "app/WindowOutcomes.js", "app/Retention.js",
      "assets/arcade/rescue-planet.png", "assets/arcade/rescue-ship.png",
      "assets/sounds/interaction-correct.wav", "assets/sounds/interaction-wrong.wav",
      "assets/sounds/interaction-step-complete.wav", "assets/sounds/interaction-module-complete.wav",
      "tools/bar-geometry.mjs", "tools/generate-cheat-sheet.mjs", "tools/generate-interaction-sounds.mjs",
      "tools/prepare-intro-pixels.mjs",
      "tools/prepare-splash-poster.mjs", "assets/splash/learn-omarchy-poster.png",
      "assets/splash/poster.provenance.json",
      "docs/presentation.md", "docs/curriculum-expansion.md", "courses/omarchy-shortcuts.html",
      "assets/splash/provenance.json",
      "assets/sounds/birds-welcome.opus", "assets/sounds/birds-welcome.provenance.json",
      "app/WordRevealText.qml", "app/CaptionReveal.qml", "app/CaptionTiming.js", "tools/play-timed-speech.mjs",
      "app/IntroTimeline.js", "app/IntroEffect.qml", "app/qmldir",
      "src/character-packs.ts", "src/intro-sequence.ts", "tools/character-packs.ts",
      "tools/validate-course-audio.ts", "tools/audio-coverage.ts", "tools/audio-production.ts",
      "tools/validate-course.ts", "tools/capture-practice.mjs", "tools/verify-window-owner.mjs",
      "tools/remove-legacy-integration.mjs",
      "docs/character-packs.md", "docs/character-intros.md", "experiments/hexon-lab/shell.qml",
      "experiments/hexon-lab/qmldir",
      "assets/characters/ohm-1/intro/sequence.json", "assets/characters/owl/intro/sequence.json",
      "courses/audio/ohm-1/host-welcome.mp3.timing.json",
      "courses/audio/owl/host-welcome.mp3.timing.json",
    ]) {
      assert.ok((await readFile(join(root, file))).length > 0, file);
    }
    for (const file of ["LICENSE", "LICENSE-ASSETS.md", "LICENSES/CC-BY-4.0.txt", "LICENSES/CC0-1.0.txt"]) {
      assert.deepEqual(await readFile(join(directory, "usr/share/licenses/learn-omarchy", file)), await readFile(file), file);
      assert.deepEqual(await readFile(join(root, file)), await readFile(file), `installed documentation links: ${file}`);
    }
    for (const file of [
      "assets/characters/ohm-1/character.json", "assets/characters/owl/character.json",
      "assets/splash/provenance.json", "assets/sounds/birds-welcome.provenance.json",
    ]) assert.deepEqual(await readFile(join(root, file)), await readFile(file), file);
    assert.deepEqual((await readdir(join(root, "tools"))).sort(),
      ["audio-coverage.ts", "audio-production.ts", "bar-geometry.mjs", "capture-practice.mjs", "character-packs.ts",
        "generate-cheat-sheet.mjs", "generate-interaction-sounds.mjs",
        "play-timed-speech.mjs", "prepare-intro-pixels.mjs", "prepare-splash-poster.mjs",
        "remove-legacy-integration.mjs", "tutorial-launch.mjs", "validate-course-audio.ts", "validate-course.ts", "verify-window-owner.mjs"]);
    const audioCheck = spawnSync(process.execPath, ["--experimental-strip-types",
      join(root, "tools/validate-course-audio.ts"), join(root, "courses/omarchy-basics.json")],
    { encoding: "utf8" });
    assert.equal(audioCheck.status, 0, audioCheck.stderr || audioCheck.stdout);
    const sheet = join(directory, "reference.html");
    const generated = spawnSync(process.execPath, ["--experimental-strip-types",
      join(root, "tools/generate-cheat-sheet.mjs"), join(root, "courses/omarchy-basics.json"), sheet],
    { cwd: directory, encoding: "utf8" });
    assert.equal(generated.status, 0, generated.stderr || generated.stdout);
    assert.match(await readFile(sheet, "utf8"), /Print or save as PDF/);
    const catalog = await discoverCharacterPacks({ bundledRoot: join(root, "assets/characters") });
    assert.deepEqual(catalog.invalidBundledIds, []);
    assert.ok(catalog.packs.every(pack => pack.intro !== null));
    const help = spawnSync(join(directory, "usr/bin/learn-omarchy"), ["--help"], { encoding: "utf8" });
    assert.equal(help.status, 0, help.stderr);
    assert.match(help.stdout, /user data directory/);
    const removed = spawnSync("make", ["uninstall", `DESTDIR=${directory}`, "PREFIX=/usr"], { encoding: "utf8", env });
    assert.equal(removed.status, 0, removed.stderr);
    await assert.rejects(readFile(join(root, "tools/remove-legacy-integration.mjs")), /ENOENT/);
    assert.equal(await readFile(progress, "utf8"), '{"completed":["first-lesson"]}');
    assert.equal(await readFile(editedIntegration, "utf8"), "// user-owned changes");
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
