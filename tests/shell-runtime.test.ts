import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { createContext, runInContext } from "node:vm";
import type { Course } from "../src/course.ts";

const shell = await readFile(new URL("../app/shell.qml", import.meta.url), "utf8");
const arcadePanelSource = await readFile(new URL("../app/ArcadePanel.qml", import.meta.url), "utf8");
const revealSource = await readFile(new URL("../app/CaptionReveal.qml", import.meta.url), "utf8");
const captionTiming = createContext({});
runInContext(await readFile(new URL("../app/CaptionTiming.js", import.meta.url), "utf8"), captionTiming);
const windowOutcomes = createContext({});
runInContext(await readFile(new URL("../app/WindowOutcomes.js", import.meta.url), "utf8"), windowOutcomes);
const retention = createContext({});
runInContext(await readFile(new URL("../app/Retention.js", import.meta.url), "utf8"), retention);
const arcadeLogic = createContext({});
runInContext(await readFile(new URL("../app/ArcadeLogic.js", import.meta.url), "utf8"), arcadeLogic);
const welcomeSource = await readFile(new URL("../courses/welcome.json", import.meta.url), "utf8");
const course: Course = JSON.parse(
  await readFile(new URL("../courses/omarchy-basics.json", import.meta.url), "utf8"),
);

function timer() {
  return {
    running: false,
    interval: 0,
    stepId: "",
    generation: -1,
    restart() { this.running = true; },
    stop() { this.running = false; },
  };
}

function captionRuntime(state: any, source: () => string, display: () => string, available: () => boolean,
    narrationEnabled = () => state.narrationEnabled) {
  const deadline = timer();
  const context = createContext({
    CaptionTiming: captionTiming, timingDeadline: deadline, deadline, console: state.console,
    words: [], timingText: "", positionMs: -1, failed: false, finished: false, playing: false,
    generation: 0, readingElapsed: 0, readingStartOffset: 0, lastVoicedEnd: 0,
  });
  context.root = context;
  Object.defineProperties(context, {
    sourceText: { get: source }, displayText: { get: display },
    formattedText: { get: () => state.captionText(display()) },
    typeText: { get: () => state.synchronizedWelcomeText },
    reducedMotion: { get: () => state.reducedMotion },
    narrationEnabled: { get: narrationEnabled },
    audioAvailable: { get: available }, wordsPerMinute: { get: () => state.readingWordsPerMinute },
    paused: { get: () => state.phase === "paused" || state.phase === "settings" },
    revealEnd: { get: () => runInContext(revealSource.match(/readonly property int revealEnd: ([\s\S]*?)\n\n/)![1], context) },
  });
  for (const method of revealSource.matchAll(/^  function \w+\([^\n]*\) \{[\s\S]*?^  \}/gm))
    runInContext(method[0], context);
  return context;
}

// Execute the runtime's JavaScript, with compositor, process and timer effects
// replaced by inert objects so regression tests never touch the user's desktop.
function runtime(stepId: string, reducedMotion = true) {
  const lessonIndex = course.lessons.findIndex((lesson) =>
    lesson.steps.some((step) => step.id === stepId),
  );
  assert.notEqual(lessonIndex, -1);
  const context = createContext({
    course: structuredClone(course),
    interactionAudio: { notify(_kind: string) {}, stop() {} },
    CaptionTiming: captionTiming,
    WindowOutcomes: windowOutcomes,
    Retention: retention,
    ArcadeLogic: arcadeLogic,
    arcadeStats: arcadeLogic.defaultStats(),
    arcadeStatsReady: true,
    arcadeWritesBlocked: false,
    arcadeSaveRetry: false,
    arcadeStorageNotice: "",
    arcadePath: "/state/learn-omarchy/arcade.json",
    arcadeFile: { setText() {}, reload() {}, waitForJob() {} },
    arcadeHost: null,
    FileViewError: { FileNotFound: 2, PermissionDenied: 3 },
    windowChangeBaseline: null,
    mixedLessonIds: [],
    mixedLessonPosition: 0,
    retentionNotice: "",
    referenceBrowsing: false,
    referenceRestoreCapture: false,
    referenceRequestPhase: "",
    cheatSheetPath: "/state/learn-omarchy/shortcuts.html",
    cheatSheetProcess: { running: false, command: [] },
    courseDir: "/course",
    coursePath: "/course/omarchy-basics.json",
    requestedCharacter: "ohm-1",
    characterState: "coach",
    characterParked: false,
    characterIndex: [],
    characterPick: 0,
    savedCharacter: "ohm-1",
    characterOverride: "",
    settingsResolved: true,
    progressResolved: true,
    tourSeen: true,
    welcomeSeen: true,
    welcomeSettingPresent: true,
    welcomeStage: "",
    splashActive: false,
    startupOpacity: 1,
    startupRevealPending: false,
    startupCoverHeld: false,
    startupFadeIn: timer(),
    startupCoverRelease: timer(),
    welcomeNarration: JSON.parse(welcomeSource),
    welcomeNarrationStarted: false,
    welcomeNarrationFinished: false,
    welcomeSpeechStopping: false,
    synchronizedWelcomeText: true,
    welcomeWordTimings: [],
    welcomeTimingText: "",
    welcomePlaybackMs: -1,
    welcomeTimingFailed: false,
    welcomeTimingDeadline: timer(),
    welcomeReadingActive: false,
    welcomeReadingElapsed: 0,
    welcomeReadingStartOffset: 0,
    welcomeSpeech: { running: false, generation: -1, command: [] },
    lessonWrapupSpeech: { running: false, generation: -1, command: [] },
    lessonWrapupReady: false,
    lessonWrapupPlayed: false,
    lessonWrapupStopping: false,
    lessonWrapupGeneration: 0,
    introActive: false,
    introGeneration: 0,
    introPlaybackStarted: false,
    introDeparting: false,
    introNotice: "",
    introPlaybackRequested() {},
    introCancellationRequested() {},
    introHandoffRequested() {},
    introReleaseRequested() {},
    tourRestingState: "tour-talk",
    tourRestingMessage: "WELCOME",
    autoAdvance: true,
    tourDetailsExpanded: false,
    readingWordsPerMinute: 200,
    narrationRestMs: 900,
    selectedLessonIndex: lessonIndex,
    optionalLessonsExpanded: false,
    coreLessonCount: course.lessons.filter(lesson => !lesson.optional).length,
    optionalLessonCount: course.lessons.filter(lesson => lesson.optional).length,
    menuWheelRemainder: 0,
    menuPointerX: NaN,
    menuPointerY: NaN,
    audioEnabled: false,
    speechEnabled: true,
    effectsEnabled: true,
    speechVolume: 80,
    effectsVolume: 45,
    speechRate: 1,
    textScale: 1,
    motionReduced: false,
    externalLayerTick: 0,
    audioStopRequested: false,
    audioPaused: false,
    audioProcessPath: "",
    audioPlaybackEvents: [],
    pendingAudioPath: "",
    settingsReturnToLesson: false,
    practiceMode: false,
    practiceHintVisible: false,
    stepAssisted: false,
    recoveryMessage: "",
    recoveryStepId: "",
    recoveryReturnStepId: "",
    highlightStartedAt: 0,
    completedLessons: {},
    progressByCourse: {},
    progressDetails: {},
    stepResults: {},
    stepCredits: {},
    lessonBookmarks: {},
    settingsSaveError: "",
    progressSaveError: "",
    stateSaveRetry: "",
    settingsFile: { setText() {}, reload() {}, waitForJob() {} },
    progressFile: { setText() {}, reload() {}, waitForJob() {} },
    lessonIndex,
    stepIndex: course.lessons[lessonIndex].steps.findIndex((step) => step.id === stepId),
    phase: "waiting",
    reducedMotion,
    lessonTransitionRunning: false,
    pendingLessonTransition: "",
    pendingTransitionStepIndex: -1,
    actionGeneration: 0,
    actionProcessGeneration: -1,
    actionRunning: false,
    actionStopping: false,
    stepOwnsCleanupSurface: false,
    keyboardExclusive: true,
    keyboardCaptureResetting: false,
    shortcutInhibitionActive: false,
    restoreKeyboardAfterAction: false,
    exerciseRunning: false,
    practiceSessionActive: false,
    practiceSessionGeneration: -1,
    practiceSessionMode: "",
    practiceHost: {},
    practiceLoader: { item: { cancel() {} } },
    exitAfterPractice: false,
    exerciseRestoreCapture: false,
    swapBefore: null,
    directionalKey: "",
    appRoot: "/app",
    barGeometry: [],
    barGeometryAvailable: true,
    barGeometryTopology: "",
    barGeometryRequested: false,
    targetGeometryRequested: false,
    windowGeometryRefreshing: false,
    barGeometryProcess: { running: false },
    requestKeyboardFocus() {},
    outcomeGeneration: 0,
    outcomeAttempts: 0,
    outcomeAddress: "",
    outcomeExpected: null,
    targetLayerNamespace: "",
    targetLayerMonitor: "",
    targetScreenId: -1,
    actionStepId: "",
    activeKeys: {},
    comboTriggered: false,
    shortcutArmedUntil: 0,
    shortcutArmWindowMs: 8000,
    helpArmWindowMs: 10000,
    targetWindowAddress: "",
    stepStartWindowAddress: "",
    targetWindowGeometry: null,
    targetMonitorGeometry: null,
    windowGeometryPending: false,
    windowGeometryGeneration: 0,
    windowGeometryAttempts: 0,
    tutorialWindows: [],
    tutorialWindowsByStep: {},
    tutorialWindowSnapshots: {},
    pendingTutorialWindowAddress: "",
    windowLaunchToken: "",
    pressedPhysicalKeys: {},
    windowLaunchAcknowledged: true,
    windowOwnershipVerified: false,
    tutorialLaunchProcess: { running: false, requestGeneration: -1, requestToken: "", command: [] },
    windowOwnershipStopping: false,
    windowOwnershipProcess: { running: false, requestGeneration: -1, requestToken: "", command: [] },
    pausedCompletionPending: false,
    characterCue: 0,
    audioProcess: { running: false, processId: 123, write() {} },
    sfxProcess: { running: false },
    introAmbienceProcess: { running: false, command: [] },
    outcomeProcess: { running: false },
    windowPresentationProcess: { running: false, command: [], requestGeneration: -1 },
    windowPresentationReady: false,
    windowPresentationSize: null,
    windowGeometryMaxAttempts: 6,
    scratchpadVisibilityProcess: { running: false, requestGeneration: -1, monitorId: -1 },
    layerGeometryProcess: { running: false },
    helpProcess: { running: false, command: [] },
    practiceProcess: { running: false, command: [], requestGeneration: -1 },
    swapPreflightProcess: { running: false, requestGeneration: -1 },
    windowBaselineProcess: { running: false, requestGeneration: -1 },
    layoutPreflightProcess: { running: false, requestGeneration: -1 },
    directionPreviewProcess: { running: false, requestGeneration: -1 },
    clientGeometryProcess: { running: false },
    monitorGeometryProcess: { running: false },
    stepStartWindowProcess: { running: false },
    lessonTransitionAnimation: timer(),
    Quickshell: { execDetached() {}, env: () => "/runtime", screens: [{ name: "eDP-1", x: 0, y: 0, width: 1920, height: 1200 }] },
    Hyprland: { focusedMonitor: null },
    console: { info() {}, warn() {}, error() {} },
    Qt: { callLater() {}, rgba: (r: number, g: number, b: number, a: number) => ({ r, g, b, a }) },
  });
  Object.defineProperties(context, {
    mixedPracticeActive: { get: () => context.mixedLessonIds.length > 0 },
    welcomeRevealEnd: { get: () => context.welcomeReveal.revealEnd },
    lessonCaptionStage: { get: () => context.phase === "highlight" ||
      (["paused", "settings"].includes(context.phase) && context.pausedPhase === "highlight") ? "completion" : "instruction" },
    currentLesson: { get: () => context.course.lessons[context.lessonIndex] },
    currentStep: { get: () => context.currentLesson?.steps[context.stepIndex] },
    currentStepIsTour: { get: () => context.currentStep?.kind === "tour" },
    currentStepIsPractice: { get: () => context.currentStep?.kind === "practice" },
    currentStepNeedsDirection: { get: () => Boolean(context.currentStep?.directionFromStep || context.currentStep?.swapWithStep) },
    currentStepKeys: { get: () => (context.currentStep?.keys || []).map((key: string) =>
      context.currentStepNeedsDirection && context.directionalKey && ["LEFT", "RIGHT", "UP", "DOWN"].includes(key) ? context.directionalKey : key) },
    currentStepClosesWindow: { get: () => context.currentStep?.completion?.events?.includes("closewindow") ?? false },
    currentStepHasNoVisibleTarget: { get: () => context.currentStepClosesWindow || context.currentStepIsPractice ||
      Boolean(context.currentStep?.completion?.windowState?.specialWorkspace &&
        context.currentStep.completion.windowState.specialVisible !== true) },
    inlineAppSearch: { get: () => context.currentStepIsPractice && context.currentStep.practice === "app-search" },
    embeddedPracticeRunning: { get: () => context.exerciseRunning && context.practiceSessionActive },
    narrationEnabled: { get: () => context.audioEnabled && context.speechEnabled && context.speechVolume > 0 },
    characterName: { get: () => context.characterStore.selectedPack?.id || "" },
    characterConfig: { get: () => context.characterStore.selectedPack?.manifest || {} },
    narrationPlaybackRate: { get: () => context.speechRate * context.boundedNumber(
      (context.characterStore.selectedPack?.manifest.narration || {}).playbackRate, 1, 0.5, 2) },
    characterIndex: { get: () => context.characterStore.packs },
    characterNotice: { get: () => context.characterStore.notice },
    characterDisplayName: { get: () => context.characterStore.selectedPack?.manifest.displayName || "Coach" },
    welcomeText: { get: () => runInContext(
      shell.match(/readonly property string welcomeText: ([\s\S]*?)\n  property bool introActive/)![1], context) },
  });
  context.welcomeReveal = captionRuntime(context, () => context.welcomeInstruction(),
    () => context.welcomeText, () => context.welcomeAudioPath() !== "",
    () => context.narrationEnabled && !context.welcomeReadingActive);
  context.lessonReveal = captionRuntime(context, () => context.lessonCaptionStage === "completion"
    ? context.currentStep?.completionMessage || "" : context.currentStep?.instruction || "",
    () => context.characterText(context.lessonReveal.sourceText),
    () => (context.lessonCaptionStage === "completion" ? context.completionAudioPath() : context.currentAudioPath()) !== "");
  context.wrapupReveal = captionRuntime(context, () => context.currentLessonWrapup()?.text || "",
    () => context.characterText(context.wrapupReveal.sourceText), () => context.currentLessonWrapup() !== null);
  for (const [outer, inner] of Object.entries({
    welcomeWordTimings: "words", welcomeTimingText: "timingText", welcomePlaybackMs: "positionMs",
    welcomeTimingFailed: "failed", welcomeReadingElapsed: "readingElapsed", welcomeReadingStartOffset: "readingStartOffset",
    welcomeTimingDeadline: "deadline",
  })) Object.defineProperty(context, outer, {
    get: () => context.welcomeReveal[inner], set: (value) => context.welcomeReveal[inner] = value,
  });
  context.characterStore = {
    appRoot: "/app",
    requestedId: "ohm-1",
    ready: true,
    fallbackId: "ohm-1",
    diagnostics: [],
    narrationNotice: "",
    packs: ["ohm-1", "owl", "custom-coach"].map((id) => ({
      id, root: `/packs/${id}`, assetUrl: `file:///packs/${id}`,
      manifest: {
        formatVersion: 1, id, displayName: id === "owl" ? "OLLIE" : id.toUpperCase(),
        description: "A coach", preview: { sprite: "idle", frame: 0 },
        sprites: { idle: { path: "sprites/body.png", frameWidth: 192, frameHeight: 192, frames: 1 } },
        effects: { thrusters: false }, motion: { tourFlight: "sprite" },
        narration: { mode: "own", audioSet: id },
      },
      intro: null,
    })),
    get selectedPack() {
      return this.packs.find((pack) => pack.id === this.requestedId)
        || this.packs.find((pack) => pack.id === this.fallbackId) || null;
    },
    get notice() {
      if (!this.ready) return "Loading character packs…";
      if (!this.selectedPack) return "No valid character packs are available.";
      return this.selectedPack.id !== this.requestedId
        ? `Character pack '${this.requestedId}' is unavailable; using ${this.selectedPack.manifest.displayName}.` : "";
    },
    refresh() {},
    select(id: string) { this.requestedId = id; },
    audioPath(relativePath: string, spokenText: string, courseDir: string) {
      const narration = this.selectedPack?.manifest.narration;
      if (!relativePath || !narration || narration.mode === "silent" ||
          (narration.mode === "borrowed" && /HEXON|ARCHIE|OLLIE/i.test(spokenText || ""))) return "";
      return `${courseDir}/${relativePath.replace(/([^/]*)$/, `${narration.audioSet}/$1`)}`;
    },
  };
  for (const match of shell.matchAll(/^\s+id: (\w+Timer)$/gm)) {
    context[match[1]] = timer();
  }
  const functions = Array.from(shell.matchAll(/^  function \w+\([^\n]*\) \{[\s\S]*?^  \}/gm));
  assert.ok(functions.length > 0);
  runInContext(functions.map(([source]) => source).join("\n"), context);
  context.root = context;
  const audioProcessSource = shell.match(/  Process \{\n    id: audioProcess[\s\S]*?\n  \}/)![0];
  context.audioExited = runInContext("(" + audioProcessSource.slice(
    audioProcessSource.indexOf("function(exitCode)"), audioProcessSource.lastIndexOf("\n  }"),
  ) + ")", context);
  const helpProcessSource = shell.match(/  Process \{\n    id: helpProcess[\s\S]*?\n  \}/)![0];
  context.helpExited = runInContext("(" + helpProcessSource.slice(
    helpProcessSource.indexOf("function(exitCode)"), helpProcessSource.lastIndexOf("\n  }"),
  ) + ")", context);
  context.captureWorkspaceStart = () => {};
  context.productionStartCharacterStep = context.startCharacterStep;
  context.startCharacterStep = () => {};
  context.currentWorkspaceId = () => 1;
  return context;
}

function client(address: string) {
  return { address, pid: 1234, at: [10, 20], size: [500, 300], mapped: true, hidden: false };
}

function timingPacket(text: string) {
  return JSON.stringify({ type: "timing", text, words: Array.from(text.matchAll(/\S+/g),
    (match, index) => ({ startMs: 100 + index * 200, endOffset: match.index! + match[0].length })) });
}

test("instructions, action results, and wrap-ups use the timed bridge with exact caption sources", () => {
  for (const step of ["tour-welcome", "launch-terminal"]) {
    const state = runtime(step, false);
    state.audioEnabled = true;
    state.playCurrentAudio(true);
    assert.match(state.audioProcess.command[1], /play-timed-speech\.mjs$/);
    assert.equal(state.audioProcess.captionStage, "instruction");
    const token = state.audioProcess.captionGeneration;
    state.receiveLessonPlayback(timingPacket(state.currentStep.instruction), token, step, "instruction");
    state.receiveLessonPlayback('{"type":"position","positionMs":100}', token, step, "instruction");
    assert.ok(state.lessonRevealEnd(state.characterText(state.currentStep.instruction)) > 0);
    assert.equal(state.lessonRevealEnd("An unrelated help prompt."), -1);
    state.audioProcess.running = false;
    state.audioExited(0);
    assert.equal(state.lessonReveal.revealEnd, -1, "finished instructions stay complete");
    if (state.completionAudioPath() === "") continue;
    state.phase = "highlight";
    state.playCompletionNarration();
    assert.equal(state.audioProcess.captionStage, "completion");
    assert.equal(state.lessonRevealEnd(state.characterText(state.currentStep.instruction)), -1);
    const completionToken = state.audioProcess.captionGeneration;
    state.receiveLessonPlayback(timingPacket(state.currentStep.instruction), token, step, "instruction");
    assert.equal(state.lessonReveal.failed, false);
    assert.equal(state.lessonReveal.revealEnd, 0, "late instruction metadata cannot reveal completion text");
    state.receiveLessonPlayback(timingPacket(state.currentStep.completionMessage), completionToken, step, "completion");
    state.receiveLessonPlayback('{"type":"position","positionMs":100}', completionToken, step, "completion");
    assert.ok(state.lessonRevealEnd(state.characterText(state.currentStep.completionMessage)) > 0);
    const command = [...state.audioProcess.command];
    state.replayCurrentAudio();
    assert.deepEqual(Array.from(state.audioProcess.command), command, "instruction replay cannot replace result speech");
  }
  const state = runtime("launch-terminal", false);
  state.audioEnabled = true;
  state.phase = "lesson-complete";
  state.characterState = "celebrate";
  state.lessonWrapupReady = true;
  state.playLessonWrapup();
  assert.match(state.lessonWrapupSpeech.command[1], /play-timed-speech\.mjs$/);
  const token = state.lessonWrapupSpeech.captionGeneration;
  state.wrapupReveal.receive(timingPacket(state.currentLessonWrapup().text), token);
  state.wrapupReveal.receive('{"type":"position","positionMs":100}', token);
  assert.ok(state.wrapupReveal.revealEnd > 0);
  state.lessonWrapupSpeech.running = false;
  state.lessonWrapupExited(0, state.lessonWrapupGeneration);
  assert.equal(state.wrapupReveal.revealEnd, -1);
});

test("cancelled, mismatched, and stale lesson packets safely leave the active caption alone", () => {
  const state = runtime("launch-terminal", false);
  state.audioEnabled = true;
  state.playCurrentAudio(true);
  const token = state.audioProcess.captionGeneration;
  const step = state.currentStep.id;
  state.receiveLessonPlayback(timingPacket("Unrelated narration."), token, "old-step", "instruction");
  state.receiveLessonPlayback(timingPacket("Unrelated narration."), token - 1, step, "instruction");
  assert.equal(state.lessonReveal.failed, false);
  state.receiveLessonPlayback(timingPacket("Unrelated narration."), token, step, "instruction");
  assert.equal(state.lessonReveal.failed, true);
  const fallbackEnd = state.lessonReveal.revealEnd;
  assert.ok(fallbackEnd >= 0);
  state.receiveLessonPlayback(timingPacket(state.currentStep.instruction), token, step, "instruction");
  state.receiveLessonPlayback('{"type":"position","positionMs":100}', token, step, "instruction");
  assert.ok(state.lessonReveal.revealEnd >= fallbackEnd);
  state.stopAudio();
  state.receiveLessonPlayback(timingPacket(state.currentStep.instruction), token, step, "instruction");
  assert.equal(state.lessonReveal.playing, false);
});

test("replay invalidates old timing and deferred replay cannot survive a step change", () => {
  const state = runtime("launch-terminal", false);
  state.audioEnabled = true;
  state.playCurrentAudio(true);
  const oldToken = state.audioProcess.captionGeneration;
  const callbacks: (() => void)[] = [];
  state.Qt.callLater = (callback: () => void) => callbacks.push(callback);
  state.replayCurrentAudio();
  state.audioProcess.running = false;
  state.audioExited(0);
  assert.equal(callbacks.length, 1);
  callbacks.shift()!();
  assert.ok(state.audioProcess.captionGeneration > oldToken);
  state.receiveLessonPlayback(timingPacket(state.currentStep.instruction), oldToken, state.currentStep.id, "instruction");
  assert.equal(state.lessonReveal.words.length, 0);
  state.replayCurrentAudio();
  state.audioProcess.running = false;
  state.audioExited(0);
  state.actionGeneration++;
  callbacks.shift()!();
  assert.equal(state.audioProcess.running, false);
});

test("practice recall and unplayed hints stay complete instead of waiting for nonexistent playback", () => {
  const state = runtime("launch-terminal", false);
  state.audioEnabled = true;
  state.practiceMode = true;
  assert.equal(state.lessonRevealEnd("Open the terminal."), -1);
  assert.equal(state.lessonRevealEnd(state.characterText(state.currentStep.instruction)), -1);
  state.playCurrentAudio(true);
  assert.equal(state.lessonRevealEnd(state.characterText(state.currentStep.instruction)), 0);
  assert.equal(state.lessonRevealEnd("Open the terminal."), -1);
});

test("global Type text migrates the welcome preference without losing an explicit choice", () => {
  for (const saved of [
    { synchronizedWelcomeText: false }, { typeText: false },
    { synchronizedWelcomeText: false, typeText: true }, {},
  ]) {
    const state = runtime("launch-terminal");
    let written: any;
    state.settingsFile.setText = (raw: string) => { written = JSON.parse(raw); };
    state.loadSettings(JSON.stringify(saved));
    const expected = "typeText" in saved ? saved.typeText : saved.synchronizedWelcomeText !== false;
    assert.equal(state.synchronizedWelcomeText, expected);
    state.persistSettings();
    assert.equal(written.typeText, expected);
    assert.equal(written.synchronizedWelcomeText, expected);
  }
});

function confirmWindowOwnership(state: ReturnType<typeof runtime>, exitCode = 0) {
  if (state.tutorialLaunchProcess.running) {
    state.tutorialLaunchProcess.running = false;
    state.finishTutorialLaunch(0, state.tutorialLaunchProcess.requestGeneration,
      state.tutorialLaunchProcess.requestToken, '{"ok":true,"state":"spawned","pid":1234}', "");
  }
  const process = state.windowOwnershipProcess;
  assert.equal(process.running, true);
  process.running = false;
  state.finishWindowOwnership(exitCode, process.requestGeneration, process.requestToken);
}

function exerciseRuntime() {
  const state = runtime("launch-terminal");
  state.currentLesson.steps[state.stepIndex] = {
    ...state.currentStep, kind: "practice", practice: "clipboard", keys: [],
    help: undefined, completion: { type: "practice-result" },
  };
  return state;
}

test("lesson wrap-ups acknowledge completion, assistance, and skipped activities accurately", () => {
  const state = runtime("tour-welcome");
  state.stepResults = Object.fromEntries(state.currentLesson.steps.map((step: any) => [step.id, "introduced"]));
  assert.equal(state.currentLessonWrapup().audio, "audio/wrapup-omarchy-tour.mp3");
  state.stepResults["tour-workspace-two"] = "assisted";
  assert.equal(state.currentLessonWrapup().audio, "audio/lesson-wrapup-assisted.mp3");
  state.stepResults["tour-clock"] = "skipped";
  assert.equal(state.currentLessonWrapup().audio, "audio/lesson-wrapup-explored.mp3");
  delete state.stepResults["tour-clock"];
  assert.equal(state.currentLessonWrapup().audio, "audio/lesson-wrapup-explored.mp3");
});

test("wrap-up speech waits for the visible settled panel and plays only once", () => {
  const state = runtime("tour-welcome");
  state.audioEnabled = true;
  state.phase = "lesson-complete";
  state.characterState = "module-fly";
  state.playLessonWrapup();
  assert.equal(state.lessonWrapupSpeech.running, false);
  state.characterState = "celebrate";
  state.playLessonWrapup();
  assert.equal(state.lessonWrapupSpeech.running, false, "pose alone isn't proof the coach arrived");
  state.lessonWrapupReady = true;
  state.playLessonWrapup();
  assert.equal(state.lessonWrapupSpeech.running, true);
  assert.match(state.lessonWrapupSpeech.command.at(-1), /ohm-1\/lesson-wrapup-explored\.mp3$/);
  state.lessonWrapupSpeech.running = false;
  state.lessonWrapupExited(0, state.lessonWrapupSpeech.generation);
  state.playLessonWrapup();
  assert.equal(state.lessonWrapupSpeech.running, false);
  assert.equal(state.phase, "lesson-complete", "a wrap-up never starts another topic automatically");
});

test("leaving or muting wrap-ups cancels speech and late exits cannot advance lessons", () => {
  const state = runtime("tour-welcome");
  state.audioEnabled = true;
  state.phase = "lesson-complete";
  state.characterState = "celebrate";
  state.lessonWrapupReady = true;
  state.playLessonWrapup();
  const generation = state.lessonWrapupSpeech.generation;
  state.toggleAudio();
  assert.equal(state.lessonWrapupSpeech.running, false);
  state.lessonWrapupExited(0, generation);
  assert.equal(state.lessonWrapupSpeech.running, false);
  assert.equal(state.phase, "lesson-complete");
  state.toggleAudio();
  assert.equal(state.lessonWrapupSpeech.running, true);
  state.returnToMenu();
  state.lessonWrapupExited(0, generation);
  assert.equal(state.phase, "menu");
  assert.equal(state.lessonWrapupSpeech.running, false);
});

test("wrap-ups preserve visible feedback when muted, silent, or missing audio", () => {
  const state = runtime("tour-welcome");
  state.phase = "lesson-complete";
  state.characterState = "celebrate";
  state.lessonWrapupReady = true;
  state.playLessonWrapup();
  assert.equal(state.lessonWrapupSpeech.running, false);
  assert.ok(state.currentLessonWrapup().text.length > 0);
  state.audioEnabled = true;
  state.characterStore.selectedPack.manifest.narration = { mode: "silent" };
  state.playLessonWrapup();
  assert.equal(state.lessonWrapupSpeech.running, false);
  state.characterStore.selectedPack.manifest.narration = { mode: "own", audioSet: "ohm-1" };
  state.playLessonWrapup();
  state.lessonWrapupSpeech.running = false;
  state.lessonWrapupExited(1, state.lessonWrapupSpeech.generation);
  assert.equal(state.phase, "lesson-complete");
  assert.ok(state.currentLessonWrapup().text.length > 0);
});

test("system volume adjustments serialize repeats without touching lesson or narration state", () => {
  const state = runtime("tour-welcome");
  state.systemVolumeProcess = { running: false, command: [] };
  state.pendingSystemVolumeActions = [];
  state.Qt.callLater = (callback: () => void) => callback();
  for (const phase of ["welcome", "menu", "waiting", "highlight", "paused", "settings"]) {
    state.phase = phase;
    state.queueSystemVolume(-5);
    assert.deepEqual(Array.from(state.systemVolumeProcess.command), ["omarchy", "audio", "output", "volume", "-5"]);
    for (let i = 0; i < 30; i++) state.queueSystemVolume(-5);
    assert.deepEqual(Array.from(state.pendingSystemVolumeActions), [-100]);
    state.queueSystemVolume("mute-toggle");
    state.systemVolumeProcess.running = false;
    state.finishSystemVolumeAction(0);
    assert.equal(state.systemVolumeProcess.command.at(-1), "-100");
    state.systemVolumeProcess.running = false;
    state.finishSystemVolumeAction(0);
    assert.equal(state.systemVolumeProcess.command.at(-1), "mute-toggle");
    state.systemVolumeProcess.running = false;
    state.finishSystemVolumeAction(0);
    assert.equal(state.phase, phase);
    assert.equal(state.currentStep.id, "tour-welcome");
    assert.equal(state.speechVolume, 80);
    assert.equal(state.welcomeStage, "");
  }
});

test("workspace actions release compositor focus and recapture only after dispatch finishes", () => {
  for (const id of ["tour-workspace-two", "next-workspace"]) {
    const state = runtime(id);
    state.currentWorkspaceId = () => 1;
    state.workspaceStartId = 1;
    state.runStepAction("shortcut");
    assert.equal(state.keyboardExclusive, false);
    assert.equal(state.restoreKeyboardAfterAction, true);
    assert.equal(state.helpProcess.running, false);
    state.currentWorkspaceId = () => 2;
    state.checkWorkspaceCompletion();
    assert.equal(state.phase, "waiting");
    state.helpExited(0);
    state.checkWorkspaceCompletion();
    assert.equal(state.keyboardExclusive, true);
    assert.equal(state.restoreKeyboardAfterAction, false);
    assert.equal(state.phase, "highlight");
  }
});

test("taught modified Tab chords cannot move focus onto the Topics button", () => {
  const state = runtime("next-workspace");
  Object.assign(state.Qt, { NoModifier: 0, ShiftModifier: 1, ControlModifier: 2,
    AltModifier: 4, MetaModifier: 8, Key_Tab: 0x01000001, Key_Backtab: 0x01000002 });
  state.updateActiveKeys = () => {};
  for (const [key, modifiers, accepted] of [
    [state.Qt.Key_Tab, 8, true],
    [state.Qt.Key_Backtab, 9, true],
    [state.Qt.Key_Tab, 0, false],
    [state.Qt.Key_Backtab, 1, false],
  ]) {
    const event = { key, modifiers, accepted: false };
    state.handleKeyPressed(event);
    assert.equal(event.accepted, accepted);
  }
});

test("direct media-key events work on layer surfaces before any lesson key handling", () => {
  const state = runtime("tour-welcome");
  Object.assign(state.Qt, { NoModifier: 0, ShiftModifier: 1, ControlModifier: 2, AltModifier: 4, MetaModifier: 8,
    Key_VolumeUp: 0x01000072, Key_VolumeDown: 0x01000070, Key_VolumeMute: 0x01000071 });
  state.keyboardExclusive = true;
  state.shortcutInhibitionActive = true;
  const actions: (string | number)[] = [];
  state.queueSystemVolume = (action: string | number) => actions.push(action);
  for (const phase of ["welcome", "menu", "waiting", "highlight", "paused", "settings"]) {
    state.phase = phase;
    state.lessonTransitionRunning = true;
    const event = { key: state.Qt.Key_VolumeDown, modifiers: 0, nativeScanCode: 122, accepted: false };
    state.handleKeyPressed(event);
    assert.equal(event.accepted, true);
    assert.equal(actions.at(-1), -5);
    assert.equal(state.phase, phase);
  }
  state.handleSystemVolumeKey({ key: state.Qt.Key_VolumeUp, modifiers: 4, isAutoRepeat: true });
  assert.equal(actions.at(-1), 1);
  const count = actions.length;
  assert.equal(state.handleSystemVolumeKey({ key: state.Qt.Key_VolumeMute, modifiers: 0, isAutoRepeat: true }), true);
  assert.equal(actions.length, count);
  assert.equal(state.handleSystemVolumeKey({ key: state.Qt.Key_VolumeMute, modifiers: 1 }), false);
  state.shortcutInhibitionActive = false;
  assert.equal(state.handleSystemVolumeKey({ key: state.Qt.Key_VolumeDown, modifiers: 0 }), false);
  assert.equal(actions.length, count);
});

function arcadeRuntime() {
  const state = runtime("launch-terminal");
  Object.assign(state.Qt, {
    NoModifier: 0, ShiftModifier: 1, ControlModifier: 2, AltModifier: 4, MetaModifier: 8,
    Key_A: 65, Key_Z: 90, Key_H: 72, Key_P: 80,
    Key_0: 48, Key_9: 57, Key_1: 49, Key_R: 82,
    Key_Tab: 0x01000001, Key_Backtab: 0x01000002, Key_Escape: 0x01000000,
    Key_Return: 0x01000004, Key_Enter: 0x01000005, Key_Space: 32,
    Key_Meta: 0x01000022, Key_Control: 0x01000021, Key_Shift: 0x01000020,
    Key_Alt: 0x01000023, Key_VolumeDown: 0x01000070,
  });
  state.phase = "arcade";
  const received: { kind: string; keys: string[] }[] = [];
  state.arcadeHost = {
    running: true,
    mode: "rescue",
    expectedKeys: ["SUPER", "RETURN"],
    handleEscape() { received.push({ kind: "back", keys: [] }); },
    pauseGame() { received.push({ kind: "pause", keys: [] }); },
    showHint() { received.push({ kind: "hint", keys: [] }); },
    handleControlKey(key: string) { received.push({ kind: "control", keys: [key] }); },
    handleKeyPress(direct: string, keys: string[]) {
      received.push({ kind: direct, keys: Array.from(keys) });
    },
  };
  return { state, received };
}

test("arcade owns real shortcut input and intercepts only plain hint and pause keys", () => {
  const { state, received } = arcadeRuntime();
  for (const [key, modifiers] of [[72, 8], [state.Qt.Key_Return, 8], [72, 0], [80, 0]]) {
    const event = { key, modifiers, accepted: false, isAutoRepeat: false };
    state.handleKeyPressed(event);
    assert.equal(event.accepted, true);
    state.updateActiveKeys(event, false);
  }
  assert.equal(received[0].kind, "H");
  assert.deepEqual(received[0].keys, ["SUPER", "H"]);
  assert.equal(received[1].kind, "RETURN");
  assert.deepEqual(received[1].keys, ["SUPER", "RETURN"]);
  assert.equal(received[2].kind, "hint");
  assert.equal(received[3].kind, "pause");
  assert.equal(state.phase, "arcade", "P pauses without leaving the arcade");
});

test("Sprint keeps plain P available and does not route it to pause", () => {
  const { state, received } = arcadeRuntime();
  state.arcadeHost.mode = "sprint";
  const event = { key: 80, modifiers: 0, accepted: false, isAutoRepeat: false };
  state.handleKeyPressed(event);
  assert.equal(event.accepted, true);
  assert.equal(received.some(item => item.kind === "pause"), false);
});

test("arcade navigation handles hub, pause and results keys without submitting answers", () => {
  const { state, received } = arcadeRuntime();
  state.arcadeHost.running = false;
  for (const [key, modifiers] of [
    [state.Qt.Key_1, 0], [state.Qt.Key_Tab, 0], [state.Qt.Key_Tab, 1],
    [state.Qt.Key_Return, 0], [state.Qt.Key_Escape, 0],
  ]) state.handleKeyPressed({ key, modifiers, isAutoRepeat: false, accepted: false });
  assert.deepEqual(received.map(item => [item.kind, ...item.keys]), [
    ["control", "1"], ["control", "TAB"], ["control", "BACKTAB"], ["control", "RETURN"],
    ["back"],
  ]);
  state.handleKeyPressed({ key: state.Qt.Key_Return, modifiers: 0, isAutoRepeat: true });
  assert.equal(received.length, 5, "held Enter must not launch or replay again");
});

test("arcade never routes media keys into real volume changes or desktop actions", () => {
  const { state, received } = arcadeRuntime();
  state.queueSystemVolume = () => assert.fail("Arcade must not adjust real system volume");
  state.checkExpectedCombo = () => assert.fail("Arcade must not execute a lesson action");
  const event = { key: state.Qt.Key_VolumeDown, modifiers: 0, isAutoRepeat: false, accepted: false };
  state.handleKeyPressed(event);
  assert.equal(event.accepted, true);
  assert.equal(received.length, 1);
  assert.ok(received[0].keys.some(key => key.startsWith("__KEY_")));
  state.arcadeHost = null;
  state.handleKeyPressed(event);
  assert.equal(event.accepted, true, "input remains captured during host handoff");
});

test("custom arcade courses can use plain answer keys that only navigate outside play", () => {
  const { state, received } = arcadeRuntime();
  for (const [key, label] of [
    [state.Qt.Key_Return, "RETURN"], [state.Qt.Key_Space, "SPACE"],
    [state.Qt.Key_Tab, "TAB"], [state.Qt.Key_R, "R"], [state.Qt.Key_1, "1"],
  ] as const) {
    state.arcadeHost.expectedKeys = [label];
    const event = { key, modifiers: 0, accepted: false, isAutoRepeat: false };
    state.handleKeyPressed(event);
    assert.equal(event.accepted, true);
    assert.equal(received.at(-1)?.kind, label);
    assert.deepEqual(received.at(-1)?.keys, [label]);
    state.updateActiveKeys(event, false);
  }
});

test("arcade transitions clear stale physical keys and preserve lesson progress", () => {
  const { state } = arcadeRuntime();
  state.completedLessons = { windows: true };
  state.activeKeys = { SUPER: true, RETURN: true };
  state.pressedPhysicalKeys = { 36: "RETURN" };
  state.openArcade();
  assert.equal(state.phase, "arcade");
  assert.deepEqual(Object.keys(state.activeKeys), []);
  assert.deepEqual(Object.keys(state.pressedPhysicalKeys), []);
  assert.deepEqual(Object.keys(state.completedLessons), ["windows"]);
  assert.match(shell, /pressedKeys: Object\.keys\(root\.activeKeys\)/);
  assert.match(shell, /Keys\.forwardTo: \[keyCatcher\]/);
  assert.match(shell, /onClearInputRequested: \{\s+root\.clearArcadeInput\(\)[\s\S]*?arcadePanel\.active && arcadePanel\.running && !root\.keyboardExclusive/);
});

test("arcade has no lesson toolbar and entering it always captures shortcuts", () => {
  const { state, received } = arcadeRuntime();
  state.keyboardExclusive = false;
  state.openArcade();
  assert.equal(state.keyboardExclusive, true);
  state.setKeyboardExclusive(false);
  assert.equal(received.at(-1)?.kind, "pause", "lost capture pauses the game");
  const controls = shell.match(/id: controls\s+z: \d+\s+visible: ([^\n]+)/)?.[1];
  assert.ok(controls);
  assert.equal(runInContext(controls, state), false);
  assert.match(shell, /component SystemVolumeShortcut:[\s\S]*?enabled: root\.phase !== "arcade"/);
  assert.match(shell, /label: "ARCADE"\s+description:/);
  assert.match(shell, /objectName: "lessonArcadeButton"[\s\S]*?arcadeStyle: true[\s\S]*?label: "ARCADE"/);
  assert.doesNotMatch(shell, /label: "SHORTCUT ARCADE"/);
});

test("dedicated practice raises the coach beside the exercise surface", () => {
  assert.match(shell, /readonly property bool targetsPractice: root\.embeddedPracticeRunning/);
  assert.match(shell, /targetsPractice \? practiceX/);
  assert.match(shell, /targetsPractice \? practiceY/);
  assert.match(shell, /targetsPractice \? practiceScale/);
  assert.match(shell, /targetsPractice && \(coachTravelX\.running \|\| coachTravelY\.running\)/);
});

test("arcade wallpaper is preloaded and retained between visits", () => {
  assert.match(shell, /OmarchyTheme \{ id: appTheme; wallpaperEnabled: true \}/);
  assert.match(shell, /ArcadePanel \{[\s\S]*?appRoot: root\.appRoot/);
  assert.match(arcadePanelSource, /function arcadeAssetUrl\(name\)[\s\S]*?"file:\/\/"/);
  assert.match(arcadePanelSource, /source: root\.wallpaperSource/);
  assert.match(arcadePanelSource, /asynchronous: true\s+cache: true/);
  assert.doesNotMatch(arcadePanelSource, /source: root\.active \? root\.wallpaperSource : ""/);
});

test("lesson menu reuses the wallpaper and fades it away when teaching starts", () => {
  assert.match(shell, /objectName: "lessonMenuBackdropFallback"[\s\S]*?visible: lessonMenuBackdrop\.requested[\s\S]*?color: root\.background/);
  assert.match(shell, /id: lessonMenuBackdrop[\s\S]*?root\.phase === "menu"[\s\S]*?root\.phase === "settings" && !root\.settingsReturnToLesson/);
  assert.match(shell, /id: lessonMenuBackdrop[\s\S]*?source: appTheme\.wallpaperSource[\s\S]*?fillMode: Image\.PreserveAspectCrop/);
  assert.match(shell, /id: lessonMenuBackdrop[\s\S]*?asynchronous: true\s+cache: true/);
  assert.match(shell, /opacity: requested && status === Image\.Ready \? 1 : 0[\s\S]*?NumberAnimation \{ duration: 300/);
  assert.match(shell, /id: menuBackdropShade[\s\S]*?lessonMenuBackdrop\.requested && lessonMenuBackdrop\.status === Image\.Ready \? 0\.3 : 0\.72/);
});

test("arcade pages are preloaded instead of recreated during navigation", () => {
  for (const page of ["Hub", "Play", "Paused", "Complete", "Results"]) {
    assert.match(arcadePanelSource,
      new RegExp(`objectName: "arcade${page}PageLoader"[\\s\\S]*?active: true`));
  }
  assert.doesNotMatch(arcadePanelSource, /arcadeReadyPageLoader|id: readyPage|function beginRound/);
  assert.doesNotMatch(arcadePanelSource, /screen = "ready"/);
  assert.doesNotMatch(arcadePanelSource, /id: page\s+Layout\.fillWidth: true\s+sourceComponent:/);
});

test("lesson menu footer prioritizes contextual actions and keeps tools secondary", () => {
  assert.doesNotMatch(shell, /text: "SELECTED LESSON"/);
  assert.doesNotMatch(shell, /text: "↑↓ Select  ·  Enter Start  ·  Esc Close"/);
  assert.match(shell, /width: Math\.min\(1040, parent\.width - 64\)/);
  assert.match(shell, /function lessonShortcutKeys\(lesson\) \{\s+if \(!lesson \|\| lesson\.kind === "welcome" \|\| !lesson\.steps\) return \[\]/);
  assert.match(shell, /objectName: "lessonShortcutColumn"[\s\S]*?Layout\.preferredWidth: 180/);
  assert.match(shell, /readonly property string selectedActionLabel:[\s\S]*?return "RESUME LESSON"/);
  assert.match(shell, /kind: "primary"[\s\S]*?label: topicPanel\.selectedActionLabel/);
  assert.match(shell, /label: "PRACTICE"\s+description: "Practice the selected lesson\. Press P\."/);
  assert.match(shell, /MixedPracticeButton \{\s+compact: true/);
  assert.match(shell, /label: "ARCADE"\s+description: "Play three safe shortcut games and chase your personal bests\. Press A\."/);
  assert.match(shell, /objectName: "lessonFooterGrid"[\s\S]*?columns: singleRow \? 5 : 2/);
  const progressHeader = shell.slice(shell.indexOf('objectName: "lessonProgressSummary"'), shell.indexOf("id: lessonList"));
  assert.match(progressHeader, /MixedPracticeButton \{[\s\S]*?Layout\.alignment: Qt\.AlignRight/);
  assert.doesNotMatch(shell.slice(shell.indexOf("id: lessonFooterGrid"), shell.indexOf("id: lessonFooterGrid") + 3000), /MixedPracticeButton/);
  assert.match(shell, /label: "REVIEW MODULES"\s+description: "Revisit up to 3 completed modules in random order\."/);
  assert.match(shell, /component MixedPracticeButton:[\s\S]*?enabled: root\.mixedEligibleCount >= 2\s+visible: enabled/);
  const completion = shell.slice(shell.indexOf("id: completionPanel"), shell.indexOf("id: welcomeControls"));
  assert.doesNotMatch(completion, /MixedPracticeButton|completionMore|RESULT DETAILS|PRINTABLE SHORTCUTS|REPLAY MODULE/);
  assert.doesNotMatch(shell, /MIXED PRACTICE|Mixed practice:|mixed-practice session/);
  assert.doesNotMatch(shell, /text: "TOOLS"/);
  assert.doesNotMatch(shell, /function lessonShortcutLabel/);
  assert.doesNotMatch(shell, /Complete two practice-ready modules to unlock a mixed review\./);
  assert.doesNotMatch(shell, /\["P", "PRACTICE"\], \["A", "ARCADE"\]/);
});

test("course header adds breathing room without changing lesson-card density", () => {
  const header = shell.slice(shell.indexOf("id: topicPanel"), shell.indexOf("id: lessonList"));
  assert.match(header, /RowLayout \{\s+Layout\.fillWidth: true\s+Layout\.bottomMargin: 12/);
  assert.match(header, /Layout\.maximumWidth: topicPanel\.width - 380\s+Layout\.topMargin: 6/);
  assert.match(header, /MixedPracticeButton \{\s+compact: true\s+Layout\.alignment: Qt\.AlignRight\s+Layout\.topMargin: 8/);
  assert.match(shell, /id: lessonColumn[\s\S]*?spacing: 8\s+readonly property int rowHeight: 76/);
});

test("lesson list uses a fixed draggable scrollbar", () => {
  assert.match(shell, /Controls\.ScrollBar\.vertical: Controls\.ScrollBar \{\s+id: lessonScrollbar/);
  assert.match(shell, /objectName: "lessonScrollbar"[\s\S]*?policy: Controls\.ScrollBar\.AlwaysOn/);
  assert.match(shell, /visible: lessonList\.contentHeight > lessonList\.height/);
  assert.match(shell, /width: lessonList\.width - \(lessonScrollbar\.visible \? 16 : 0\)/);
  assert.doesNotMatch(shell, /y: lessonList\.height \* \(lessonList\.contentY/);
});

test("optional lessons are collapsed behind an accessible section by default", () => {
  const state = runtime("launch-terminal");
  state.phase = "menu";
  assert.equal(state.optionalLessonsExpanded, false);
  state.selectedLessonIndex = state.coreLessonCount - 1;
  state.moveMenuSelection(1);
  assert.equal(state.selectedLessonIndex, state.coreLessonCount - 1);
  state.setOptionalLessonsExpanded(true);
  state.moveMenuSelection(1);
  assert.equal(state.selectedLessonIndex, state.coreLessonCount);
  state.setOptionalLessonsExpanded(false);
  assert.equal(state.selectedLessonIndex, state.coreLessonCount - 1);
  assert.match(shell, /text: "OPTIONAL LESSONS  ·  " \+ root\.optionalLessonCount/);
  assert.match(shell, /text: root\.optionalLessonsExpanded \? "▾" : "▸"/);
  assert.match(shell, /selectedLessonIndex === root\.coreLessonCount - 1[\s\S]*?optionalSection\.y \+ optionalSection\.height/);
  assert.match(shell, /function revealOptionalSection\(\)[\s\S]*?optionalSection\.y \+ optionalSection\.height \+ 12/);
  assert.match(shell, /event\.key === Qt\.Key_O\) toggleOptionalLessons/);
  state.toggleOptionalLessons();
  assert.equal(state.optionalLessonsExpanded, true);
  assert.equal(state.selectedLessonIndex, state.coreLessonCount);
});

test("arcade preserves corrupt and newer-version files instead of overwriting them", () => {
  for (const content of ["{bad", "[]", "null", '{"version":99}']) {
    const { state } = arcadeRuntime();
    state.arcadeFile.setText = () => assert.fail("Unreadable progress must not be overwritten");
    state.loadArcadeStats(content);
    assert.equal(state.arcadeWritesBlocked, true);
    assert.equal(state.arcadeStatsReady, true);
    assert.match(state.arcadeStorageNotice, /file is preserved/);
    assert.equal(state.saveArcadeStats(arcadeLogic.defaultStats()), false);
  }
});

test("arcade distinguishes first-run missing progress from inaccessible progress", () => {
  const { state } = arcadeRuntime();
  state.arcadeLoadFailed(state.FileViewError.FileNotFound);
  assert.equal(state.arcadeWritesBlocked, false);
  assert.equal(state.arcadeStorageNotice, "");
  state.arcadeLoadFailed(state.FileViewError.PermissionDenied);
  assert.equal(state.arcadeWritesBlocked, true);
  assert.match(state.arcadeStorageNotice, /will not be saved/);
  state.loadArcadeStats('{"version":1,"sprint":{"bestScore":200}}');
  assert.equal(state.arcadeWritesBlocked, false);
  assert.equal(state.arcadeStats.sprint.bestScore, 200);
});

test("arcade retries failed writes without replacing in-memory practice with stale disk data", () => {
  const { state } = arcadeRuntime();
  const next = arcadeLogic.defaultStats();
  next.sprint.bestScore = 500;
  let reloads = 0;
  let saved = "";
  state.arcadeFile.reload = () => {
    reloads++;
    state.loadArcadeStats('{"version":1,"sprint":{"bestScore":100}}');
  };
  state.arcadeFile.setText = (text: string) => {
    saved = text;
    state.arcadeStorageNotice = "";
  };
  state.arcadeSaveFailed(state.FileViewError.PermissionDenied);
  assert.match(state.arcadeStorageNotice, /next completed shortcut will retry/);
  assert.equal(state.saveArcadeStats(next), true);
  assert.equal(reloads, 1);
  assert.equal(JSON.parse(saved).sprint.bestScore, 500);
  assert.equal(state.arcadeSaveRetry, false);
});

test("system volume failures notify the learner and clear pending repeats", () => {
  const state = runtime("tour-welcome");
  state.systemVolumeProcess = { running: false, command: [] };
  state.pendingSystemVolumeActions = [5];
  const notifications: string[][] = [];
  state.Quickshell.execDetached = (command: string[]) => notifications.push(Array.from(command));
  state.finishSystemVolumeAction(1);
  assert.equal(state.pendingSystemVolumeActions.length, 0);
  assert.equal(notifications.length, 1);
  assert.equal(notifications[0][0], "notify-send");
  state.queueSystemVolume("unexpected");
  assert.equal(state.systemVolumeProcess.running, false);
});

test("hands-on exercises release keys and require a verified result", () => {
  const state = exerciseRuntime();
  state.runStepAction("action");
  assert.equal(state.keyboardExclusive, false);
  assert.equal(state.exerciseRunning, true);
  assert.equal(state.practiceProcess.running, false);
  assert.equal(state.practiceSessionActive, true);
  assert.equal(state.practiceSessionMode, "clipboard");
  state.Qt.callLater = (callback: () => void) => callback();
  state.finishEmbeddedPractice(state.actionGeneration, "clipboard", true, "");
  assert.equal(state.keyboardExclusive, true);
  assert.equal(state.exerciseRunning, false);
  assert.equal(state.practiceSessionActive, false);
  assert.equal(state.stepResults["launch-terminal"], "practiced");
});

test("exercise cancellation, errors and mismatched results never count as completion", () => {
  for (const [exitCode, output] of [
    [0, ""],
    [1, 'LEARN_PRACTICE_RESULT:{"mode":"clipboard","completed":true}'],
    [0, 'LEARN_PRACTICE_RESULT:{"mode":"capture","completed":true}'],
    [0, 'LEARN_PRACTICE_RESULT:{"mode":"clipboard","completed":false}'],
    [0, 'LEARN_PRACTICE_RESULT:not-json'],
  ] as const) {
    const state = exerciseRuntime();
    state.runStepAction("action");
    state.finishPracticeExercise(exitCode, state.actionGeneration, output);
    assert.equal(state.phase, "waiting");
    assert.equal(state.stepResults["launch-terminal"], undefined);
    assert.notEqual(state.recoveryMessage, "");
    assert.equal(state.keyboardExclusive, true);
  }
});

test("leaving an embedded exercise waits for cleanup before unloading and rejects stale success", () => {
  const state = exerciseRuntime();
  let cancelled = false;
  state.practiceLoader.item.cancel = () => { cancelled = true; };
  state.runStepAction("action");
  const generation = state.actionGeneration;
  state.cancelAction();
  assert.equal(state.practiceProcess.running, false);
  assert.equal(cancelled, true);
  assert.equal(state.practiceSessionActive, true);
  assert.equal(state.keyboardExclusive, true);
  state.Qt.callLater = (callback: () => void) => callback();
  state.finishEmbeddedPractice(generation, "clipboard", true, "");
  assert.equal(state.practiceSessionActive, false);
  assert.equal(state.stepResults["launch-terminal"], undefined);
});

test("new exercises wait for prior cleanup and require an available embedded host", () => {
  const state = exerciseRuntime();
  state.practiceSessionActive = true;
  state.startPracticeExercise();
  assert.match(state.recoveryMessage, /still closing/);
  assert.equal(state.exerciseRunning, false);
  state.practiceSessionActive = false;
  state.practiceHost = null;
  state.startPracticeExercise();
  assert.match(state.recoveryMessage, /isn't available/);
  assert.equal(state.exerciseRunning, false);
});

test("app search remains a nonvisual observer with the normal coaching interface", () => {
  const state = runtime("apps-search-practice");
  state.startPracticeExercise();
  assert.equal(state.practiceSessionActive, false);
  assert.equal(state.practiceProcess.running, true);
  assert.deepEqual(Array.from(state.practiceProcess.command), ["/app/bin/learn-omarchy-practice", "app-search"]);
});

test("Exit waits for embedded helper cleanup before quitting", () => {
  const state = exerciseRuntime();
  let quit = false;
  state.Qt.quit = () => { quit = true; };
  state.startPracticeExercise();
  state.requestExit();
  assert.equal(quit, false);
  assert.equal(state.practiceSessionActive, true);
  state.Qt.callLater = (callback: () => void) => callback();
  state.finishEmbeddedPractice(state.practiceSessionGeneration, "clipboard", false, "");
  assert.equal(quit, true);
});

test("optional steps don't block required lesson completion", () => {
  const state = runtime("launch-terminal");
  for (const step of state.currentLesson.steps) state.stepResults[step.id] = "practiced";
  state.currentStep.optional = true;
  state.stepResults[state.currentStep.id] = "skipped";
  assert.equal(state.lessonFullyExplored(state.currentLesson), true);
  state.currentStep.optional = false;
  assert.equal(state.lessonFullyExplored(state.currentLesson), false);
});

test("new required activities reopen completed lessons without discarding earlier results", () => {
  const state = runtime("launch-terminal");
  const steps: Record<string, string> = {};
  for (const step of state.currentLesson.steps) steps[step.id] = "practiced";
  state.currentLesson.steps.push({ ...state.currentStep, id: "new-required-activity" });
  state.progressByCourse[state.course.id] = [state.currentLesson.id];
  state.progressDetails[state.course.id] = { steps, bookmarks: {} };
  state.applyCourseProgress();
  assert.equal(state.completedLessons[state.currentLesson.id], false);
  assert.equal(state.lessonBookmarks[state.currentLesson.id], "new-required-activity");
  assert.equal(state.stepResults["launch-terminal"], "practiced");
});

test("lesson-only legacy progress preserves old work without crediting new activities", () => {
  for (const legacy of [
    { schemaVersion: 2, courses: { "omarchy-essentials": ["omarchy-tour", "windows"] } },
    { courseId: "omarchy-essentials", completedLessons: ["omarchy-tour", "windows"] },
  ]) {
    const state = runtime("tour-welcome");
    state.loadProgress(JSON.stringify(legacy));
    assert.equal(state.completedLessons["omarchy-tour"], false);
    assert.equal(state.stepCredits["tour-omarchy-menu"], true);
    assert.equal(state.stepCredits["tour-menu-icon"], undefined);
    assert.equal(state.stepCredits["tour-workspace-two"], undefined);
    assert.equal(state.stepCredits["tour-workspace-one"], undefined);
    assert.equal(state.lessonBookmarks["omarchy-tour"], "tour-workspace-two");
    assert.equal(state.completedLessons.windows, false);
    assert.equal(state.stepCredits["windows-open-first"], true);
    assert.equal(state.stepCredits["windows-swap"], undefined);
    assert.equal(state.stepCredits["windows-focus-right"], undefined);
    assert.ok(state.lessonBookmarks.windows);
    let saved = "";
    state.progressFile.setText = (text: string) => { saved = text; };
    state.persistProgress();
    const restored = runtime("tour-welcome");
    restored.loadProgress(saved);
    assert.equal(restored.completedLessons["omarchy-tour"], false);
    assert.equal(restored.stepCredits["tour-omarchy-menu"], true);
    assert.equal(restored.stepCredits["windows-open-first"], true);
    assert.equal(restored.stepCredits["windows-swap"], undefined);
  }
});

test("tour workspace actions wait for their exact destination and continue in sequence", () => {
  for (const [id, destination, next] of [
    ["tour-workspace-two", 2, "tour-workspace-one"],
    ["tour-workspace-one", 1, "tour-clock"],
  ] as const) {
    const state = runtime(id);
    state.currentWorkspaceId = () => 7;
    state.workspaceCheckAttempts = 0;
    state.startCurrentStep();
    assert.equal(state.phase, "waiting");
    state.checkWorkspaceCompletion();
    assert.equal(state.phase, "waiting", "another workspace cannot satisfy the action");
    state.currentWorkspaceId = () => destination;
    state.checkWorkspaceCompletion();
    assert.equal(state.phase, "highlight");
    state.advance();
    assert.equal(state.currentStep.id, next);
  }
});

test("workspace-is verifies a successful dispatch even without a compositor event", () => {
  for (const [step, destination] of [["tour-workspace-one", 1], ["tour-workspace-two", 2]] as const) {
    const state = runtime(step);
    state.currentWorkspaceId = () => destination;
    state.workspaceCheckAttempts = 5;
    state.runStepAction("shortcut");
    assert.equal(state.workspaceCheckAttempts, 0);
    state.helpProcess.running = false;
    state.helpExited(0);
    assert.equal(state.workspaceCompletionTimer.running, true);
    state.checkWorkspaceCompletion();
    assert.equal(state.phase, "highlight");
  }
});

test("failed workspace arrival allows another shortcut attempt and rejects stale command exits", () => {
  const state = runtime("tour-workspace-one");
  state.currentWorkspaceId = () => 2;
  state.comboTriggered = true;
  state.runStepAction("shortcut");
  state.helpProcess.running = false;
  state.helpExited(0);
  for (let i = 0; i < 5; i++) state.checkWorkspaceCompletion();
  assert.equal(state.phase, "waiting");
  assert.equal(state.comboTriggered, false);
  assert.match(state.recoveryMessage, /Try the shortcut again/);
  state.runStepAction("shortcut");
  assert.equal(state.workspaceCheckAttempts, 0);
  assert.equal(state.recoveryMessage, "");
  state.helpProcess.running = false;
  state.workspaceCompletionTimer.stop();
  state.actionGeneration++;
  state.helpExited(0);
  assert.equal(state.workspaceCompletionTimer.running, false);
});

test("starting the tour workspace action at its destination safely skips that satisfied action", () => {
  const state = runtime("tour-workspace-two");
  state.currentWorkspaceId = () => 2;
  state.startCurrentStep();
  assert.equal(state.currentStep.id, "tour-workspace-one");
  assert.equal(state.phase, "waiting");
  assert.equal(state.stepResults["tour-workspace-two"], "introduced");
  assert.equal(state.helpProcess.running, false);
});

test("legacy credits are scoped to the bundled course and never override modern empty credits", () => {
  for (const customCourse of [false, true]) {
    const state = runtime("tour-welcome");
    if (customCourse) state.course.id = "custom-course";
    state.loadProgress(JSON.stringify({
      schemaVersion: 2,
      courses: { [state.course.id]: ["omarchy-tour"] },
      ...(customCourse ? {} : { details: { [state.course.id]: { credits: {}, steps: {} } } }),
    }));
    assert.equal(state.completedLessons["omarchy-tour"], false);
    assert.equal(state.stepCredits["tour-welcome"], undefined);
  }
});

test("legacy activity credits follow work moved into different lessons", () => {
  const state = runtime("tour-welcome");
  state.loadProgress(JSON.stringify({
    schemaVersion: 2, courses: { "omarchy-essentials": ["personalization", "clipboard-and-helpers", "capture-and-share"] },
  }));
  for (const id of ["theme-menu", "background-menu", "helpers-emoji", "helpers-reminder", "share-menu"]) {
    assert.equal(state.stepCredits[id], true, id);
  }
  for (const id of ["clipboard-practice", "sharing-practice", "dictation-practice"]) {
    assert.equal(state.stepCredits[id], undefined, id);
  }
});

test("replay skips retain earned completion after saving and reloading", () => {
  const state = runtime("launch-terminal");
  for (const step of state.currentLesson.steps) state.stepResults[step.id] = "practiced";
  state.recordStepResult("practiced");
  state.markCurrentLessonComplete();
  state.recordStepResult("skipped");
  let persisted = "";
  state.progressFile.setText = (text: string) => { persisted = text; };
  state.persistProgress();
  const restored = runtime("launch-terminal");
  restored.loadProgress(persisted);
  assert.equal(restored.completedLessons[state.currentLesson.id], true);
  assert.equal(restored.stepResults["launch-terminal"], "skipped");
  assert.equal(restored.stepCredits["launch-terminal"], true);
});

test("legacy replay results keep earned work while newly required work remains incomplete", () => {
  const state = runtime("launch-terminal");
  const steps: Record<string, string> = {};
  for (const step of state.currentLesson.steps) steps[step.id] = "skipped";
  state.progressByCourse[state.course.id] = [state.currentLesson.id];
  state.progressDetails[state.course.id] = { steps, bookmarks: {} };
  state.applyCourseProgress();
  assert.equal(state.completedLessons[state.currentLesson.id], true);
  state.currentLesson.steps.push({ ...state.currentStep, id: "new-required-activity" });
  state.applyCourseProgress();
  assert.equal(state.completedLessons[state.currentLesson.id], false);
  assert.equal(state.lessonBookmarks[state.currentLesson.id], "new-required-activity");
  state.stepIndex = state.currentLesson.steps.length - 1;
  state.recordStepResult("practiced");
  state.markCurrentLessonComplete();
  assert.equal(state.completedLessons[state.currentLesson.id], true);
  assert.equal(state.stepResults["launch-terminal"], "skipped");
});

test("partial bookmarks return to inserted required work without revisiting deliberate skips", () => {
  const state = runtime("launch-terminal");
  const lesson = state.currentLesson;
  const bookmark = lesson.steps[1].id;
  state.progressDetails[state.course.id] = {
    steps: { [lesson.steps[0].id]: "skipped" },
    bookmarks: { [lesson.id]: bookmark },
  };
  state.applyCourseProgress();
  assert.equal(state.lessonBookmarks[lesson.id], bookmark);
  lesson.steps.splice(1, 0, { ...state.currentStep, id: "new-optional-activity", optional: true });
  state.applyCourseProgress();
  assert.equal(state.lessonBookmarks[lesson.id], bookmark);
  lesson.steps.splice(2, 0, { ...state.currentStep, id: "new-required-activity" });
  state.applyCourseProgress();
  assert.equal(state.lessonBookmarks[lesson.id], "new-required-activity");
});

test("skipped optional work doesn't earn credit if it later becomes required", () => {
  const state = runtime("lock-practice");
  const steps: Record<string, string> = {};
  for (const step of state.currentLesson.steps) steps[step.id] = "practiced";
  steps["lock-practice"] = "skipped";
  state.progressByCourse[state.course.id] = [state.currentLesson.id];
  state.progressDetails[state.course.id] = { steps, bookmarks: {} };
  state.applyCourseProgress();
  assert.equal(state.completedLessons[state.currentLesson.id], true);
  assert.equal(state.stepCredits["lock-practice"], undefined);
  state.persistProgress();
  state.currentStep.optional = false;
  state.applyCourseProgress();
  assert.equal(state.completedLessons[state.currentLesson.id], false);
  assert.equal(state.lessonBookmarks[state.currentLesson.id], "lock-practice");
});

test("audio history retains actual starts and finishes including short clips", () => {
  const state = runtime("launch-terminal");
  state.recordAudioPlayback("started", "/audio/short.mp3", null);
  state.recordAudioPlayback("finished", "/audio/short.mp3", 0);
  assert.deepEqual(Array.from(state.audioPlaybackEvents, (entry: { event: string }) => entry.event), ["started", "finished"]);
  assert.equal(state.audioPlaybackEvents[1].exitCode, 0);
});

test("hidden scratchpad windows must match the named special workspace", () => {
  const state = runtime("launch-terminal");
  const hidden = { ...client("0xabc"), hidden: true, workspace: { id: -99, name: "special:scratchpad" } };
  assert.equal(state.matchesWindowState(hidden, { specialWorkspace: "scratchpad" }), true);
  assert.equal(state.matchesWindowState(hidden, { workspace: 2 }), false);
  assert.equal(state.matchesWindowState({ ...hidden, workspace: { id: -98, name: "special:other" } },
    { specialWorkspace: "scratchpad" }), false);
  assert.equal(state.matchesWindowState({ ...hidden, focusHistoryID: 0 },
    { specialWorkspace: "scratchpad", focused: true }), false);
});

test("scratchpad reveal verifies the exact owned visible focused window for every supported event", () => {
  const visible = { ...client("0xabc"), focusHistoryID: 0,
    workspace: { id: -99, name: "special:scratchpad" } };
  for (const event of [
    { name: "activespecialv2", data: "-99,special:scratchpad,eDP-1" },
    { name: "activespecial", data: "special:scratchpad,eDP-1" },
    { name: "activewindowv2", data: "abc" },
  ]) {
    for (const invalid of [
      { ...visible, address: "0xother" },
      { ...visible, hidden: true },
      { ...visible, mapped: false },
      { ...visible, focusHistoryID: 1 },
      { ...visible, workspace: { id: -98, name: "special:other" } },
      { ...visible, workspace: { id: 1, name: "1" } },
    ]) {
      const state = runtime("workspaces-reveal-before-restore");
      state.windowGeometryMaxAttempts = 3;
      state.rememberTutorialWindow("abc", "workspaces-open-terminal");
      state.shortcutArmedUntil = Date.now() + 8000;
      state.handleHyprlandEvent(event);
      assert.equal(state.outcomeProcess.running, true, event.name);
      assert.equal(state.outcomeAddress, "0xabc");
      assert.equal(state.layerCompletionFeedbackTimer.running, false);
      state.parseOutcome(JSON.stringify([invalid]), state.outcomeGeneration);
      assert.equal(state.layerCompletionFeedbackTimer.running, false, JSON.stringify(invalid));
      assert.equal(state.outcomeAddress, "0xabc");
      state.parseOutcome(JSON.stringify([visible]), state.outcomeGeneration);
      assert.equal(state.outcomeAddress, "");
      assert.equal(state.layerCompletionFeedbackTimer.running, true, event.name);
      assert.equal(state.targetWindowGeometry, null);
    }
  }
});

test("scratchpad reveal rejects unarmed, unowned, wrong-window, and stale outcomes", () => {
  const state = runtime("workspaces-reveal-before-restore");
  const specialEvent = { name: "activespecialv2", data: "-99,special:scratchpad,eDP-1" };
  state.shortcutArmedUntil = Date.now() + 8000;
  state.handleHyprlandEvent(specialEvent);
  assert.equal(state.outcomeProcess.running, false, "an unowned window cannot be a target");
  state.rememberTutorialWindow("abc", "workspaces-open-terminal");
  state.shortcutArmedUntil = 0;
  state.handleHyprlandEvent(specialEvent);
  assert.equal(state.outcomeProcess.running, false, "an unrelated reveal is not an attempt");
  state.shortcutArmedUntil = Date.now() + 8000;
  state.handleHyprlandEvent({ name: "activewindowv2", data: "other" });
  assert.equal(state.outcomeProcess.running, false, "window events still require the exact address");
  state.handleHyprlandEvent(specialEvent);
  state.parseOutcome(JSON.stringify([{ ...client("0xabc"), focusHistoryID: 0,
    workspace: { id: -99, name: "special:scratchpad" } }]), state.outcomeGeneration - 1);
  assert.equal(state.layerCompletionFeedbackTimer.running, false);
  assert.equal(state.outcomeAddress, "0xabc");
});

test("scratchpad visibility requires the owned window on the exact monitor and expected named state", () => {
  for (const visible of [true, false]) {
    const state = runtime("workspaces-reveal-before-restore");
    state.windowGeometryMaxAttempts = 5;
    state.currentStep.completion.windowState = { specialWorkspace: "scratchpad", specialVisible: visible };
    state.rememberTutorialWindow("abc", "workspaces-open-terminal");
    state.shortcutArmedUntil = Date.now() + 8000;
    state.handleHyprlandEvent({ name: "activespecialv2", data: "-99,special:scratchpad,eDP-1" });
    state.parseOutcome(JSON.stringify([{ ...client("0xabc"), monitor: 0,
      workspace: { id: -99, name: "special:scratchpad" } }]), state.outcomeGeneration);
    assert.equal(state.layerCompletionFeedbackTimer.running, false);
    assert.equal(state.scratchpadVisibilityProcess.running, true);
    const generation = state.outcomeGeneration;
    const packet = (name: string, id = 0) => JSON.stringify([{ id, specialWorkspace: { name } }]);
    state.parseScratchpadVisibility(packet(visible ? "" : "special:scratchpad"), generation, 0, 0);
    assert.equal(state.layerCompletionFeedbackTimer.running, false, "inverted visibility isn't success");
    state.parseScratchpadVisibility(packet(visible ? "special:scratchpad" : "", 1), generation, 0, 0);
    assert.equal(state.layerCompletionFeedbackTimer.running, false, "another monitor isn't success");
    state.parseScratchpadVisibility(packet(visible ? "special:scratchpad" : ""), generation - 1, 0, 0);
    assert.equal(state.layerCompletionFeedbackTimer.running, false, "stale responses aren't success");
    state.parseScratchpadVisibility(packet(visible ? "special:scratchpad" : ""), generation, 0, 0,
      state.scratchpadVisibilityProcess.verifiedWindow);
    assert.equal(state.layerCompletionFeedbackTimer.running, true);
    if (visible) assert.equal(state.targetWindowGeometry.address, "0xabc", "pointing uses the verified terminal");
    else assert.equal(state.targetWindowGeometry, null, "hidden scratchpads don't show a misleading target");
  }
});

test("native-panel safety notes remain visible while the learner inspects the open tool", () => {
  const expression = shell.match(/id: teachingNote\n\s+visible: ([\s\S]*?)\n\s+Layout/)![1];
  for (const id of ["hardware-menu", "open-keybindings", "display-panel"]) {
    const state = runtime(id);
    for (const phase of ["waiting", "highlight"]) {
      state.phase = phase;
      assert.equal(runInContext(expression, state), true, `${id}: ${phase}`);
    }
    state.phase = "paused";
    assert.equal(runInContext(expression, state), false);
  }
});

test("closing the scratchpad window during visibility detection releases the pending outcome", () => {
  const state = runtime("workspaces-reveal-before-restore");
  state.outcomeAddress = "0xabc";
  state.outcomeExpected = { specialWorkspace: "scratchpad", specialVisible: true };
  state.parseScratchpadVisibility(JSON.stringify([{ id: 0, specialWorkspace: { name: "special:scratchpad" } }]),
    state.outcomeGeneration, 0, 0);
  assert.equal(state.layerCompletionFeedbackTimer.running, false);
  assert.equal(state.outcomeAddress, "");
  assert.match(state.recoveryMessage, /no longer available/);
  assert.equal(state.recoveryStepId, "workspaces-open-terminal");
});

test("readable activity-window sizing cannot run before ownership is established", () => {
  const state = runtime("launch-terminal");
  state.currentStep.windowSize = { width: 1200, height: 640 };
  state.targetMonitorGeometry = { id: 0, x: 0, y: 0, width: 3072, height: 1920, scale: 1.6 };
  state.pendingTutorialWindowAddress = "0xabc";
  state.prepareTutorialWindow();
  assert.equal(state.windowPresentationProcess.running, false);
  state.rememberTutorialWindow("0xabc", state.currentStep.id);
  state.prepareTutorialWindow();
  assert.equal(state.windowPresentationProcess.running, true);
  const command = state.windowPresentationProcess.command.join(" ");
  assert.match(command, /window\.float/);
  assert.match(command, /window\.resize/);
  assert.match(command, /x=1200, y=640/);
  assert.equal(command.match(/window="address:0xabc"/g)?.length, 3, "every mutation targets only the owned window");
  assert.equal(state.layerCompletionFeedbackTimer.running, false, "dispatch alone never credits success");
});

test("activity monitor completion waits for observed readable geometry after the resize command", () => {
  const state = runtime("launch-terminal");
  state.currentStep.windowSize = { width: 1200, height: 640 };
  const monitor = { id: 0, x: 0, y: 0, width: 3072, height: 1920, scale: 1.6 };
  const narrow = { ...client("0xabc"), monitor: 0, floating: false, size: [240, 600] };
  state.runStepAction("help");
  state.handleHyprlandEvent({ name: "openwindow", data: "abc,1,terminal,Terminal" });
  state.finishWindowDetection(narrow, monitor);
  confirmWindowOwnership(state);
  assert.equal(state.windowPresentationProcess.running, true);
  assert.equal(state.layerCompletionFeedbackTimer.running, false);
  state.windowPresentationProcess.running = false;
  state.finishWindowPresentation(0, state.windowGeometryGeneration);
  state.finishWindowDetection(narrow, monitor);
  confirmWindowOwnership(state);
  assert.equal(state.layerCompletionFeedbackTimer.running, false, "successful dispatch doesn't prove the size changed");
  state.finishWindowDetection({ ...narrow, floating: true, size: [1200, 640] }, monitor);
  confirmWindowOwnership(state);
  assert.equal(state.layerCompletionFeedbackTimer.running, true);
  assert.equal(state.windowGeometryPending, false);
});

test("activity sizing responses are rejected after cancellation and failures never credit success", () => {
  const state = runtime("launch-terminal");
  state.windowGeometryPending = true;
  state.finishWindowPresentation(0, state.windowGeometryGeneration - 1);
  assert.equal(state.windowPresentationReady, false);
  state.finishWindowPresentation(1, state.windowGeometryGeneration);
  assert.equal(state.windowPresentationReady, false);
  assert.equal(state.layerCompletionFeedbackTimer.running, false);
  assert.match(state.recoveryMessage, /Couldn't give the activity monitor enough room/);
});

function swapRuntime() {
  const state = runtime("windows-swap");
  state.rememberTutorialWindow("aaa", state.currentStep.windowFromStep);
  state.rememberTutorialWindow("bbb", state.currentStep.swapWithStep);
  state.directionalKey = "RIGHT";
  state.runStepAction("shortcut");
  const first = { ...client("0xaaa"), at: [10, 20], floating: false, fullscreen: 0, workspace: { id: 1 } };
  const peer = { ...client("0xbbb"), at: [700, 20], floating: false, fullscreen: 0, workspace: { id: 1 } };
  return { state, first, peer };
}

test("swap preflight dispatches only after confirming an owned tiled pair", () => {
  const { state, first, peer } = swapRuntime();
  assert.equal(state.helpProcess.running, false);
  assert.equal(state.swapPreflightProcess.running, true);
  state.parseSwapBaseline(JSON.stringify([first, peer]), state.actionGeneration - 1);
  assert.equal(state.helpProcess.running, false);
  state.parseSwapBaseline(JSON.stringify([null, first, peer]), state.actionGeneration);
  assert.equal(state.keyboardExclusive, true);
  assert.equal(state.helpProcess.running, true);
  assert.deepEqual(Array.from(state.swapBefore.firstAt), first.at);
  assert.deepEqual(Array.from(state.swapBefore.peerAt), peer.at);
  assert.match(state.helpProcess.command.join(" "), /address:0xaaa.*address:0xbbb/);
});

test("swap rejects missing, overlapping, floating, hidden, or cross-workspace peers", () => {
  for (const patch of [
    { address: "0xccc" }, { at: [10, 20] }, { at: [] }, { at: ["700", 20] },
    { floating: true }, { fullscreen: 2 }, { hidden: true },
    { mapped: false }, { workspace: { id: 2 } },
  ]) {
    const { state, first, peer } = swapRuntime();
    state.parseSwapBaseline(JSON.stringify([first, { ...peer, ...patch }]), state.actionGeneration);
    assert.equal(state.helpProcess.running, false, JSON.stringify(patch));
    assert.equal(state.actionRunning, false);
    assert.match(state.recoveryMessage, /Both practice terminals/);
  }
});

test("swap outcome requires both windows to exchange their earlier positions", () => {
  const { state, first, peer } = swapRuntime();
  state.windowGeometryMaxAttempts = 3;
  state.parseSwapBaseline(JSON.stringify([first, peer]), state.actionGeneration);
  state.outcomeExpected = { swapped: true };
  state.outcomeAddress = first.address;
  state.parseOutcome(JSON.stringify([{ ...first, at: peer.at }, peer]), state.outcomeGeneration);
  assert.equal(state.outcomeAddress, first.address);
  assert.equal(state.targetWindowGeometry, null);
  state.parseOutcome(JSON.stringify([{ ...first, at: peer.at }, { ...peer, at: first.at }]), state.outcomeGeneration);
  assert.equal(state.outcomeAddress, "");
  assert.equal(state.targetWindowGeometry.address, first.address);
});

test("capture renewal yields a frame and doesn't interrupt deliberate handoff", () => {
  const state = runtime("launch-terminal");
  state.renewKeyboardCapture();
  assert.equal(state.keyboardCaptureResetting, true);
  assert.equal(state.keyboardCaptureTimer.running, true);
  state.setKeyboardExclusive(false);
  assert.equal(state.keyboardCaptureResetting, false);
  assert.equal(state.keyboardCaptureTimer.running, false);
  state.renewKeyboardCapture();
  assert.equal(state.keyboardCaptureTimer.running, false);
  state.keyboardExclusive = true;
  state.exerciseRunning = true;
  state.renewKeyboardCapture();
  assert.equal(state.keyboardCaptureTimer.running, false);
});

test("directional keycaps and matching follow the actual owned-window positions", () => {
  for (const [at, direction] of [
    [[700, 20], "RIGHT"], [[-700, 20], "LEFT"], [[10, -700], "UP"], [[10, 700], "DOWN"],
  ] as const) {
    const state = runtime("windows-focus-right");
    state.rememberTutorialWindow("aaa", "windows-open-first");
    state.rememberTutorialWindow("bbb", "windows-open-second");
    const first = { ...client("0xaaa"), workspace: { id: 1 } };
    const second = { ...client("0xbbb"), at, workspace: { id: 1 } };
    state.parseDirectionPreview(JSON.stringify([first, second]), state.actionGeneration);
    assert.equal(state.directionalKey, direction);
    assert.deepEqual(Array.from(state.currentStepKeys), ["SUPER", "+", direction]);
    assert.deepEqual(Object.keys(state.expectedKeyMap()), ["SUPER", direction]);
    state.parseDirectionPreview("[]", state.actionGeneration - 1);
    assert.equal(state.directionalKey, direction);
  }
});

test("directional activities can't dispatch before their owned pair is available", () => {
  const state = runtime("windows-focus-right");
  state.runStepAction("shortcut");
  assert.equal(state.helpProcess.running, false);
  assert.equal(state.directionPreviewTimer.running, true);
  assert.match(state.recoveryMessage, /Checking/);
  state.parseDirectionPreview("[]", state.actionGeneration);
  assert.equal(state.directionalKey, "");
  assert.match(state.recoveryMessage, /Both practice terminals/);
});

test("pair recovery selects whichever launch is actually missing", () => {
  for (const id of ["windows-swap", "windows-focus-right"]) {
    for (const missing of ["windows-open-first", "windows-open-second"]) {
      const state = runtime(id);
      const existing = missing === "windows-open-first" ? "windows-open-second" : "windows-open-first";
      state.rememberTutorialWindow("aaa", existing);
      state.parseDirectionPreview(JSON.stringify([{
        ...client("0xaaa"), workspace: { id: 1 },
      }]), state.actionGeneration);
      assert.equal(state.recoveryStepId, missing);
    }
  }
});

test("swap preflight and dispatch recover the missing peer, not the surviving target", () => {
  const state = runtime("windows-swap");
  state.rememberTutorialWindow("aaa", state.currentStep.windowFromStep);
  state.directionalKey = "RIGHT";
  state.runStepAction("help");
  assert.equal(state.recoveryStepId, state.currentStep.swapWithStep);
  assert.equal(state.helpProcess.running, false);

  state.rememberTutorialWindow("bbb", state.currentStep.swapWithStep);
  state.runStepAction("help");
  state.parseSwapBaseline(JSON.stringify([{
    ...client("0xaaa"), workspace: { id: 1 },
  }]), state.actionGeneration);
  assert.equal(state.recoveryStepId, state.currentStep.swapWithStep);
  assert.equal(state.helpProcess.running, false);
});

test("closed-window results and exercises don't point at stale desktop rectangles", () => {
  assert.match(shell, /id: targetMarker[\s\S]*?overlay\.hasReliableCompletionTarget/);
  assert.match(shell, /id: resultOutline[\s\S]*?!root\.currentStepHasNoVisibleTarget/);
  assert.match(shell, /Math\.max\(0\.85, Math\.min\(1, overlay\.width \/ 900\)\)/);
});

test("focus-only detection never grants ownership, even after a guided launch", () => {
  for (const guided of [false, true]) {
    const state = runtime("launch-terminal");
    if (guided) state.runStepAction("help");
    else state.armShortcutDetection({ SUPER: true });
    state.handleHyprlandEvent({ name: "activewindowv2", data: "abc" });
    assert.equal(state.targetWindowAddress, "0xabc");
    state.finishWindowDetection(null, null);
    assert.equal(state.tutorialWindows.length, 0);
    assert.equal(Object.keys(state.tutorialWindowsByStep).length, 0);
    state.helpProcess.running = false;
    state.stepIndex++;
    state.startCurrentStep();
    state.runStepAction("help");
    assert.equal(state.helpProcess.running, false);
    assert.match(state.characterMessage, /REOPEN THE PRACTICE WINDOW/);
  }
});

test("a new-window event grants close permission only after process ownership is verified", () => {
  const state = runtime("launch-terminal");
  state.runStepAction("shortcut");
  state.handleHyprlandEvent({ name: "openwindow", data: "abc,1,terminal,Terminal" });
  assert.equal(state.tutorialWindowsByStep["launch-terminal"], undefined);
  assert.equal(state.targetWindowAddress, "0xabc");
  state.finishWindowDetection(client("0xabc"), null);
  assert.equal(state.tutorialWindows.length, 0);
  confirmWindowOwnership(state);
  assert.equal(state.tutorialWindowsByStep["launch-terminal"], "0xabc");
  assert.equal(state.tutorialWindows.length, 1);

  for (const armed of [false, true]) {
    const external = runtime("launch-terminal");
    if (armed) external.armShortcutDetection({ SUPER: true });
    external.handleHyprlandEvent({ name: "openwindow", data: "def,1,terminal,Terminal" });
    external.finishWindowDetection(null, null);
    assert.equal(external.tutorialWindows.length, 0);
  }
});

test("lesson-owned app launch steps recapture keys before teaching the shortcut", () => {
  for (const step of ["launch-terminal", "launch-browser"]) {
    const state = runtime(step);
    state.keyboardExclusive = false;
    state.startCurrentStep();
    assert.equal(state.keyboardExclusive, true, step);
  }
});

test("an open event can establish ownership after focus detection started", () => {
  const state = runtime("launch-terminal");
  state.runStepAction("help");
  state.handleHyprlandEvent({ name: "activewindowv2", data: "abc" });
  assert.equal(state.windowGeometryPending, true);
  state.handleHyprlandEvent({ name: "openwindow", data: "abc,1,terminal,Terminal" });
  state.finishWindowDetection(client("0xabc"), null);
  confirmWindowOwnership(state);
  assert.equal(state.tutorialWindowsByStep["launch-terminal"], "0xabc");
});

test("geometry completion cannot resurrect a closed tutorial window", () => {
  const state = runtime("launch-terminal");
  state.runStepAction("help");
  state.handleHyprlandEvent({ name: "openwindow", data: "abc,1,terminal,Terminal" });
  state.finishWindowDetection(client("0xabc"), null);
  confirmWindowOwnership(state);
  state.handleHyprlandEvent({ name: "closewindow", data: "abc" });
  state.finishWindowDetection(client("0xabc"), null);
  assert.equal(state.tutorialWindows.length, 0);
  assert.equal(Object.keys(state.tutorialWindowsByStep).length, 0);
});

test("an unrelated new editor never becomes a terminal close target", () => {
  const state = runtime("launch-terminal");
  state.runStepAction("help");
  const launch = state.tutorialLaunchProcess.command;
  assert.deepEqual(Array.from(launch.slice(0, 4)), ["node", "/app/tools/tutorial-launch.mjs", "--token", state.windowLaunchToken]);
  assert.deepEqual(Array.from(launch.slice(-4)), ["--", "omarchy", "launch", "terminal"]);
  state.handleHyprlandEvent({ name: "openwindow", data: "abc,1,org.example.Editor,Editor" });
  state.finishWindowDetection({ ...client("0xabc"), class: "org.example.Editor" }, null);
  confirmWindowOwnership(state, 1);
  assert.equal(state.tutorialWindows.length, 0);
  assert.equal(state.phase, "waiting");
  assert.match(state.recoveryMessage, /couldn't be linked/);
  state.stepIndex++;
  state.startCurrentStep();
  state.runStepAction("help");
  assert.equal(state.helpProcess.running, false);
});

test("shifted workspace number keys match their physical keycaps and release without sticking", () => {
  const state = runtime("workspaces-send");
  Object.assign(state.Qt, { Key_0: 48, Key_9: 57, Key_A: 65, Key_Z: 90,
    ShiftModifier: 1, MetaModifier: 2, AltModifier: 4, ControlModifier: 8 });
  state.armShortcutDetection = () => {};
  state.reactToKey = () => {};
  state.checkExpectedCombo = () => {};
  state.updateActiveKeys({ key: 64, nativeScanCode: 11, modifiers: 3, isAutoRepeat: false }, true);
  assert.equal(state.activeKeys["2"], true);
  assert.equal(state.activeKeys["SHIFT"], true);
  assert.equal(state.activeKeys["SUPER"], true);
  state.updateActiveKeys({ key: 64, nativeScanCode: 11, modifiers: 0 }, false);
  assert.equal(state.activeKeys["2"], undefined, "release uses the recorded physical identity after Shift changes");
  assert.equal(Object.keys(state.pressedPhysicalKeys).length, 0);
  state.updateActiveKeys({ key: 64, nativeScanCode: 24, modifiers: 3, isAutoRepeat: false }, true);
  assert.equal(state.activeKeys["2"], undefined, "a symbol on another physical key isn't the number row");
  state.clearActiveKeys();
  assert.equal(Object.keys(state.pressedPhysicalKeys).length, 0);
});

test("launcher acknowledgement alone never grants ownership and failures leave retry available", () => {
  const state = runtime("launch-terminal");
  state.runStepAction("shortcut");
  const launch = state.tutorialLaunchProcess;
  state.finishTutorialLaunch(2, launch.requestGeneration, launch.requestToken, "",
    '{"ok":false,"error":"Unsupported independent terminal configuration."}');
  assert.equal(state.tutorialWindows.length, 0);
  assert.equal(state.actionRunning, false);
  assert.match(state.recoveryMessage, /Unsupported independent terminal/);
  launch.running = false;
  state.runStepAction("shortcut");
  state.finishTutorialLaunch(0, launch.requestGeneration, launch.requestToken,
    '{"ok":true,"state":"spawned","pid":1234}', "");
  assert.equal(state.tutorialWindows.length, 0);
  assert.equal(state.layerCompletionFeedbackTimer.running, false);
});

test("ownership waits for launcher acknowledgement so advancing cannot kill its attached startup worker", () => {
  const state = runtime("launch-terminal");
  state.runStepAction("shortcut");
  state.handleHyprlandEvent({ name: "openwindow", data: "abc,1,terminal,Terminal" });
  state.finishWindowDetection(client("0xabc"), null);
  state.windowOwnershipProcess.running = false;
  state.finishWindowOwnership(0, state.windowGeometryGeneration, state.windowLaunchToken);
  assert.equal(state.windowOwnershipVerified, true);
  assert.equal(state.tutorialWindows.length, 0);
  assert.equal(state.layerCompletionFeedbackTimer.running, false);
  state.tutorialLaunchProcess.running = false;
  state.finishTutorialLaunch(0, state.actionGeneration, state.windowLaunchToken,
    '{"ok":true,"state":"spawned","pid":1234}', "");
  assert.equal(state.tutorialWindowsByStep["launch-terminal"], "0xabc");
  assert.equal(state.layerCompletionFeedbackTimer.running, true);
});

test("cancelled and closed launch candidates reject delayed ownership results", () => {
  for (const cancel of [false, true]) {
    const state = runtime("launch-terminal");
    state.runStepAction("help");
    state.handleHyprlandEvent({ name: "openwindow", data: "abc,1,terminal,Terminal" });
    state.finishWindowDetection(client("0xabc"), null);
    const { requestGeneration, requestToken } = state.windowOwnershipProcess;
    if (cancel) state.resetLessonRuntime();
    else state.handleHyprlandEvent({ name: "closewindow", data: "abc" });
    state.finishWindowOwnership(0, requestGeneration, requestToken);
    assert.equal(state.tutorialWindows.length, 0);
    assert.equal(state.windowGeometryPending, false);
    assert.equal(state.targetWindowGeometry, null);
    assert.equal(state.actionRunning, false);
    if (!cancel) {
      assert.match(state.recoveryMessage, /closed before/);
      assert.equal(state.pauseLesson(), true);
      state.resumePausedLesson();
      state.runStepAction("help");
      assert.equal(state.actionRunning, true);
      assert.notEqual(state.windowLaunchToken, requestToken);
    }
  }
});

test("a cancelled verifier cannot be reused before its exit callback arrives", () => {
  const state = runtime("launch-terminal");
  state.runStepAction("help");
  state.handleHyprlandEvent({ name: "openwindow", data: "aaa,1,terminal,Terminal" });
  state.finishWindowDetection(client("0xaaa"), null);
  const old = { ...state.windowOwnershipProcess };
  state.handleHyprlandEvent({ name: "closewindow", data: "aaa" });
  assert.equal(state.windowOwnershipStopping, true);
  state.runStepAction("help");
  state.handleHyprlandEvent({ name: "openwindow", data: "bbb,1,terminal,Terminal" });
  state.finishWindowDetection(client("0xbbb"), null);
  assert.equal(state.windowOwnershipProcess.requestToken, old.requestToken);
  assert.equal(state.windowGeometryRetryTimer.running, true);
  state.finishWindowOwnership(0, old.requestGeneration, old.requestToken);
  assert.equal(state.tutorialWindows.length, 0);
  state.finishWindowDetection(client("0xbbb"), null);
  confirmWindowOwnership(state);
  assert.equal(state.tutorialWindowsByStep["launch-terminal"], "0xbbb");
});
test("each close action targets its declared launch, not the most recent window", () => {
  const closeSteps = course.lessons.flatMap((lesson) => lesson.steps)
    .filter((step) => step.completion.type === "hyprland-event" && step.completion.events.includes("closewindow"));
  assert.ok(closeSteps.length >= 6);
  for (const step of closeSteps) {
    for (const source of ["help", "shortcut"]) {
      const state = runtime(step.id);
      state.rememberTutorialWindow("111", step.windowFromStep);
      state.rememberTutorialWindow("222", "unrelated-launch");
      state.runStepAction(source);
      assert.equal(state.helpProcess.running, true, step.id);
      assert.match(state.helpProcess.command[2], /address:0x111/, step.id);
      assert.doesNotMatch(state.helpProcess.command[2], /0x222/, step.id);
    }
  }
});

test("course reload while Settings is open discards its paused-lesson return target", () => {
  const state = runtime("launch-terminal");
  state.openSettings("settings");
  assert.equal(state.settingsReturnToLesson, true);
  state.loadCourse(JSON.stringify(course));
  assert.equal(state.phase, "menu");
  assert.equal(state.lessonIndex, -1);
  assert.equal(state.settingsReturnToLesson, false);
  state.openSettings("settings");
  state.closeSettings();
  assert.equal(state.phase, "menu");
  state.settingsReturnToLesson = true;
  state.phase = "settings";
  state.closeSettings();
  assert.equal(state.phase, "menu");
});
test("course failures tear down pending transitions, actions, narration and window ownership", () => {
  for (const transition of ["highlight", "step", "lesson-complete"]) {
    for (const failure of ["invalid-json", "invalid-metadata", "load-error"]) {
      const state = runtime("launch-terminal", false);
      state.runStepAction("help");
      state.rememberTutorialWindow("111", "launch-terminal");
      state.beginLessonTransition(transition, state.stepIndex + 1);
      state.audioProcess.running = true;
      state.audioProcessPath = state.currentAudioPath();
      state.pendingAudioPath = state.completionAudioPath();
      state.completionTimer.restart();
      state.tourAdvanceTimer.restart();
      state.pendingStepAction = true;
      state.pendingActionStepId = state.currentStep.id;
      state.pendingActionGeneration = state.actionGeneration;
      const actionGeneration = state.actionGeneration;
      const geometryGeneration = state.windowGeometryGeneration;
      const stepIndex = state.stepIndex;

      if (failure === "load-error") state.fail("Course couldn't be loaded");
      else state.loadCourse(failure === "invalid-json" ? "{" : "{}");

      assert.equal(state.phase, "error", failure);
      assert.notEqual(state.errorMessage, "");
      assert.equal(state.characterState, "hidden");
      assert.equal(state.lessonTransitionAnimation.running, false);
      assert.equal(state.lessonTransitionRunning, false);
      assert.equal(state.pendingLessonTransition, "");
      assert.equal(state.pendingTransitionStepIndex, -1);
      assert.equal(state.lessonContentOpacity, 1);
      assert.equal(state.helpProcess.running, false);
      assert.equal(state.actionRunning, false);
      assert.equal(state.pendingStepAction, false);
      assert.equal(state.pendingActionStepId, "");
      assert.ok(state.actionGeneration > actionGeneration);
      assert.ok(state.windowGeometryGeneration > geometryGeneration);
      assert.equal(state.audioProcess.running, false);
      assert.equal(state.pendingAudioPath, "");
      assert.equal(state.completionTimer.running, false);
      assert.equal(state.tourAdvanceTimer.running, false);
      assert.equal(state.tutorialWindows.length, 0);
      assert.equal(Object.keys(state.tutorialWindowsByStep).length, 0);

      state.applyLessonTransition();
      state.parseClientGeometry(JSON.stringify([client("0x111")]), geometryGeneration);
      assert.equal(state.phase, "error");
      assert.equal(state.stepIndex, stepIndex);
      assert.equal(state.completionTimer.running, false);
      assert.equal(state.targetWindowGeometry, null);
    }
  }
});

test("manual continue stops completion advancement in both animation modes", () => {
  for (const reducedMotion of [false, true]) {
    const state = runtime("open-root-menu", reducedMotion);
    state.phase = "highlight";
    state.scheduleCompletionAdvance(2600);
    const { stepId, generation } = state.completionTimer;
    state.advance();
    assert.equal(state.completionTimer.running, false);
    if (!reducedMotion) {
      state.applyLessonTransition();
      state.lessonTransitionRunning = false;
    }
    assert.equal(state.currentStep.id, "open-apps");
    state.advanceAfterCompletion(stepId, generation);
    assert.equal(state.currentStep.id, "open-apps");
    state.phase = "highlight";
    state.advanceAfterCompletion(stepId, generation);
    assert.equal(state.currentStep.id, "open-apps");
  }
});

test("stale completion callbacks can't advance a restarted copy of the same step", () => {
  const state = runtime("open-root-menu");
  state.phase = "highlight";
  state.scheduleCompletionAdvance(900);
  const { stepId, generation } = state.completionTimer;
  state.startCurrentStep();
  assert.equal(state.completionTimer.running, false);
  state.phase = "highlight";
  state.advanceAfterCompletion(stepId, generation);
  assert.equal(state.currentStep.id, stepId);
});

test("completion narration cannot rearm advancement during an outgoing transition", () => {
  const state = runtime("open-root-menu", false);
  state.phase = "highlight";
  state.scheduleCompletionAdvance(2600);
  state.advance();
  state.finishCompletionNarration();
  assert.equal(state.completionTimer.running, false);
});

test("valid completion timer callbacks still advance normally", () => {
  const state = runtime("open-root-menu");
  state.beginLessonTransition("highlight");
  assert.equal(state.completionTimer.running, true);
  state.advanceAfterCompletion(state.completionTimer.stepId, state.completionTimer.generation);
  assert.equal(state.currentStep.id, "open-apps");
  assert.equal(state.completionTimer.running, false);
});

test("manual advancement leaves the result visible until Continue", () => {
  const state = runtime("launch-terminal");
  state.autoAdvance = false;
  state.beginLessonTransition("highlight");
  assert.equal(state.phase, "highlight");
  assert.equal(state.completionNarrationDone, true);
  assert.equal(state.completionTimer.running, false);
  assert.match(shell, /id: targetMarker[\s\S]*?visible: root\.phase === "highlight" &&\s+overlay\.hasReliableCompletionTarget/);
});

test("highlight timing guarantees dwell from the visible result", () => {
  const state = runtime("launch-terminal");
  state.phase = "highlight";
  state.highlightStartedAt = Date.now();
  state.finishCompletionNarration();
  assert.ok(state.completionTimer.interval >= 2100);
  state.highlightStartedAt = Date.now() - 10000;
  state.finishCompletionNarration();
  assert.equal(state.completionTimer.interval, 900);
});

test("wheel selection advances by lesson, including the final rows and list boundaries", () => {
  const state = runtime("launch-terminal");
  state.phase = "menu";
  state.optionalLessonsExpanded = true;
  const lastIndex = state.course.lessons.length - 1;
  state.selectedLessonIndex = lastIndex - 3;
  state.scrollMenuSelection(-120, 0);
  assert.equal(state.selectedLessonIndex, lastIndex - 2);
  state.scrollMenuSelection(-120, 0);
  assert.equal(state.selectedLessonIndex, lastIndex - 1);
  state.scrollMenuSelection(-120, 0);
  assert.equal(state.selectedLessonIndex, lastIndex);
  state.scrollMenuSelection(-120, 0);
  assert.equal(state.selectedLessonIndex, lastIndex);
  state.scrollMenuSelection(120, 0);
  assert.equal(state.selectedLessonIndex, lastIndex - 1);
  state.selectedLessonIndex = 0;
  state.scrollMenuSelection(120, 0);
  assert.equal(state.selectedLessonIndex, 0);
});

test("smooth wheel deltas accumulate without skipping rows or resisting reversal", () => {
  const state = runtime("launch-terminal");
  state.phase = "menu";
  state.selectedLessonIndex = 7;
  for (let i = 0; i < 3; i++) state.scrollMenuSelection(-30, 0);
  assert.equal(state.selectedLessonIndex, 7);
  state.scrollMenuSelection(-30, 0);
  assert.equal(state.selectedLessonIndex, 8);
  for (let i = 0; i < 4; i++) state.scrollMenuSelection(0, -10);
  assert.equal(state.selectedLessonIndex, 9);
  state.scrollMenuSelection(0, -20);
  state.scrollMenuSelection(0, 40);
  assert.equal(state.selectedLessonIndex, 8);
  state.phase = "waiting";
  state.scrollMenuSelection(-120, 0);
  assert.equal(state.selectedLessonIndex, 8);
});

test("scrolling cards beneath a stationary pointer cannot steal the menu selection", () => {
  const state = runtime("launch-terminal");
  state.phase = "menu";
  state.selectedLessonIndex = 7;
  state.selectMenuAtPointer(5, 600, 420);
  assert.equal(state.selectedLessonIndex, 7);
  state.scrollMenuSelection(-120, 0);
  state.selectMenuAtPointer(5, 600, 420);
  state.selectMenuAtPointer(6, 600, 420);
  assert.equal(state.selectedLessonIndex, 8);
  state.selectMenuAtPointer(6, 605, 425);
  assert.equal(state.selectedLessonIndex, 6);
  assert.match(shell, /mapToItem\(overlay\.contentItem, mouse\.x, mouse\.y\)/);
  assert.match(shell, /WheelHandler\s*\{[\s\S]*?scrollMenuSelection\(event\.angleDelta\.y, event\.pixelDelta\.y\)[\s\S]*?event\.accepted = true/);
});

test("character travel has a gentler distance-based pace and honors reduced motion", () => {
  const state = runtime("launch-terminal", false);
  assert.equal(state.travelDurationForDistance(0), 420);
  assert.equal(state.travelDurationForDistance(500), 575);
  assert.equal(state.travelDurationForDistance(1000), 1150);
  assert.equal(state.travelDurationForDistance(2000), 1500);
  assert.equal(state.travelDurationForDistance(500, true), 1200);
  assert.equal(state.travelDurationForDistance(1000, true), 1350);
  assert.equal(state.travelDurationForDistance(2000, true), 1900);
  state.reducedMotion = true;
  assert.equal(state.travelDurationForDistance(500), 0);
  assert.equal(state.travelDurationForDistance(2000, true), 0);
});

test("workspace overview retains its full width while destination markers stay individual", () => {
  const state = runtime("tour-workspaces");
  state.Hyprland = { workspaces: { values: [{ id: 1 }, { id: 6 }] } };
  assert.equal(state.highlightWidth(state.currentStep.highlight), 180);
  state.Hyprland.workspaces.values.push({ id: 7 });
  assert.equal(state.highlightWidth(state.currentStep.highlight), 208);
  assert.equal(state.highlightWidth({ target: "workspace", workspaceId: 2 }), 28);
  assert.equal(state.highlightWidth({ width: 330 }), 330);
});

test("skipped, assisted, and practiced activities have distinct persisted results", () => {
  const state = runtime("open-root-menu");
  let persisted = "";
  state.progressFile.setText = (text: string) => { persisted = text; };
  state.skipCurrentStep();
  assert.equal(state.stepResults["open-root-menu"], "skipped");
  state.stepAssisted = true;
  state.completeCurrentStep();
  assert.equal(state.stepResults["open-apps"], "assisted");
  state.advance();
  state.completeCurrentStep();
  assert.equal(state.stepResults["apps-search-practice"], "practiced");
  state.advance();
  state.completeCurrentStep();
  assert.equal(state.stepResults["open-keybindings"], "practiced");
  state.advance();
  assert.equal(state.completedLessons["menus-and-apps"], false);
  assert.equal(JSON.parse(persisted).details[course.id].steps["open-root-menu"], "skipped");
  assert.equal(state.lessonBookmarks["menus-and-apps"], undefined);
});

test("lesson starts resume bookmarks but explicit replay and practice start at the beginning", () => {
  const state = runtime("open-root-menu");
  state.lessonBookmarks["menus-and-apps"] = "open-apps";
  state.startLesson(state.lessonIndex);
  assert.equal(state.currentStep.id, "open-apps");
  state.startLesson(state.lessonIndex, false, false);
  assert.equal(state.currentStep.id, "open-root-menu");
  state.lessonBookmarks["menus-and-apps"] = "open-apps";
  state.startLesson(state.lessonIndex, true);
  assert.equal(state.currentStep.id, "open-root-menu");
  assert.equal(state.practiceMode, true);
});

test("optional lessons appear after the complete core course", () => {
  const state = runtime("open-root-menu");
  const ordered = state.coreLessonsFirst([
    { id: "welcome" },
    { id: "optional-one", optional: true },
    { id: "core-one" },
    { id: "optional-two", optional: true },
    { id: "core-finale" },
  ]);
  assert.deepEqual(
    Array.from(ordered, (lesson: any) => lesson.id),
    ["welcome", "core-one", "core-finale", "optional-one", "optional-two"],
  );
  state.loadCourse(JSON.stringify(course));
  assert.deepEqual(Array.from(state.course.lessons, (lesson: any) => lesson.id), [
    ...course.lessons.filter(lesson => !lesson.optional).map(lesson => lesson.id),
    ...course.lessons.filter(lesson => lesson.optional).map(lesson => lesson.id),
  ]);
  const selected = state.course.lessons.findIndex((lesson: any) => lesson.id === "bar-panels");
  state.startLesson(selected, true, false);
  assert.equal(state.currentLesson.id, "bar-panels");
  assert.equal(state.practiceMode, true);
});

test("mixed practice reuses original lesson IDs and stops cleanly at a module boundary", () => {
  const state = runtime("open-root-menu");
  state.currentWorkspaceId = () => 99;
  assert.equal(state.startMixedPractice(), false);
  assert.match(state.retentionNotice, /Complete at least two/);
  for (const lesson of state.course.lessons.filter((item: any) => item.mixedPractice)) {
    for (const step of lesson.steps) state.stepCredits[step.id] = true;
  }
  assert.equal(state.startMixedPractice(), true);
  const plan = Array.from(state.mixedLessonIds);
  assert.ok(plan.length >= 2);
  assert.equal(state.currentLesson.id, plan[0]);
  assert.equal(state.practiceMode, true);
  assert.equal(state.stepIndex, 0);
  state.phase = "lesson-complete";
  state.nextMixedLesson();
  assert.equal(state.currentLesson.id, plan[1]);
  assert.equal(state.practiceMode, true);
  state.returnToMenu();
  assert.equal(state.mixedPracticeActive, false);
  assert.equal(state.actionRunning, false);
  assert.ok(Object.keys(state.stepCredits).length > 0);
});

test("interaction sounds distinguish accepted chords, wrong keys and verified outcomes", () => {
  const state = runtime("launch-terminal");
  const cues: string[] = [];
  state.interactionAudio.notify = (kind: string) => cues.push(kind);
  state.reactToKey("SHIFT");
  state.reactToKey("SUPER");
  assert.deepEqual(cues, []);
  state.reactToKey("Z");
  assert.deepEqual(cues, ["wrong"]);
  state.activeKeys = { SUPER: true, RETURN: true };
  state.runStepAction = () => {};
  state.checkExpectedCombo();
  assert.deepEqual(cues, ["wrong", "correct"]);
  state.completeCurrentStep();
  assert.deepEqual(cues, ["wrong", "correct", "step-complete"]);
  state.completeCurrentStep();
  assert.equal(cues.length, 3, "repeated completion cannot replay the cue");
});

test("printable shortcuts explain the browser handoff and preserve the current lesson", () => {
  for (const phase of ["menu", "lesson-complete"]) {
    const state = runtime("open-root-menu");
    state.phase = phase;
    const lessonIndex = state.lessonIndex;
    const stepIndex = state.stepIndex;
    state.coursePath = "/course/custom course.json";
    state.cheatSheetPath = "/state/custom #1/shortcuts.html";
    let opened = "";
    state.Qt.openUrlExternally = (url: string) => {
      assert.equal(state.keyboardExclusive, false, "release capture before launching the browser");
      opened = url;
      return true;
    };
    state.openCheatSheet();
    assert.match(state.retentionNotice, /Preparing printable shortcuts/);
    assert.equal(state.keyboardExclusive, true, "generation must not release keys");
    assert.deepEqual(Array.from(state.cheatSheetProcess.command),
      ["node", "--experimental-strip-types", "/app/tools/generate-cheat-sheet.mjs",
        state.coursePath, state.cheatSheetPath]);
    state.finishCheatSheetGeneration(0, "");
    assert.equal(opened, "file:///state/custom%20%231/shortcuts.html");
    assert.equal(state.keyboardExclusive, false);
    assert.match(state.retentionNotice, /browser.*another workspace/);
    assert.match(state.retentionNotice, /Keys are released for printing.*return banner/);
    assert.equal(state.referenceBrowsing, true);
    assert.equal(state.phase, phase);
    assert.equal(state.lessonIndex, lessonIndex);
    assert.equal(state.stepIndex, stepIndex);
    state.returnFromReference();
    assert.equal(state.referenceBrowsing, false);
    assert.equal(state.keyboardExclusive, true);
    assert.equal(state.phase, phase);
    assert.equal(state.lessonIndex, lessonIndex);
    assert.equal(state.stepIndex, stepIndex);
  }
});

test("reference generation and browser rejection leave the original Keys state intact", () => {
  for (const exclusive of [true, false]) {
    for (const code of [0, 1]) {
      const state = runtime("open-root-menu");
      state.phase = "menu";
      state.openCheatSheet();
      state.keyboardExclusive = exclusive;
      let launches = 0;
      let warnings = 0;
      state.Qt.openUrlExternally = () => { launches++; return false; };
      state.console.warn = () => { warnings++; };
      state.finishCheatSheetGeneration(code, "generation diagnostic");
      assert.equal(state.keyboardExclusive, exclusive);
      assert.equal(state.referenceBrowsing, false);
      assert.equal(launches, code === 0 ? 1 : 0);
      assert.equal(warnings, 1);
      assert.match(state.retentionNotice, code === 0 ? /Couldn't open the browser.*shortcuts\.html/ : /couldn't be generated/);
    }
  }
});

test("returning from a reference preserves intentionally released keys", () => {
  const state = runtime("open-root-menu");
  state.phase = "menu";
  state.keyboardExclusive = false;
  state.Qt.openUrlExternally = () => true;
  state.openCheatSheet();
  state.finishCheatSheetGeneration(0, "");
  assert.equal(state.referenceBrowsing, true);
  state.returnFromReference();
  assert.equal(state.keyboardExclusive, false);
  assert.equal(state.referenceBrowsing, false);
});

test("a reference generated after leaving the picker cannot interrupt the lesson", () => {
  const state = runtime("open-root-menu");
  state.phase = "menu";
  state.Qt.openUrlExternally = () => { assert.fail("must not launch a browser after navigation"); };
  state.openCheatSheet();
  state.phase = "waiting";
  state.finishCheatSheetGeneration(0, "");
  assert.equal(state.referenceBrowsing, false);
  assert.equal(state.keyboardExclusive, true);
  assert.match(state.retentionNotice, /saved at.*shortcuts\.html/);
});

test("Display uses standard Qt shortcut keys and waits for the panel to open", () => {
  const state = runtime("display-panel");
  Object.assign(state.Qt, {
    Key_A: 65, Key_Z: 90, Key_Meta: 0x01000022, Key_Control: 0x01000021,
    NoModifier: 0, MetaModifier: 0x10000000, ControlModifier: 0x04000000,
    AltModifier: 0x08000000, ShiftModifier: 0x02000000,
  });
  state.shortcutInhibitionActive = true;
  state.startCurrentStep();
  assert.equal(state.keyboardExclusive, true);
  const modifiers = state.Qt.MetaModifier | state.Qt.ControlModifier;
  state.handleKeyPressed({
    key: state.Qt.Key_Meta, modifiers: state.Qt.MetaModifier, isAutoRepeat: false,
  });
  state.handleKeyPressed({
    key: state.Qt.Key_Control, modifiers, isAutoRepeat: false,
  });
  assert.equal(state.helpProcess.running, false, "modifiers alone cannot trigger Display");
  const event = {
    key: 68,
    modifiers,
    isAutoRepeat: false,
    accepted: false,
  };
  state.handleKeyPressed(event);
  assert.equal(event.accepted, true);
  assert.equal(state.activeKeys.SUPER, true);
  assert.equal(state.activeKeys.CTRL, true);
  assert.equal(state.activeKeys.D, true);
  assert.equal(state.keyboardExclusive, true);
  assert.equal(state.stepAssisted, false);
  assert.equal(state.helpProcess.running, true);
  assert.deepEqual(Array.from(state.helpProcess.command),
    ["omarchy-shell", "shell", "summon", "omarchy.monitor"]);
  assert.equal(state.layerCompletionFeedbackTimer.running, false,
    "recognizing the shortcut isn't proof the panel opened");
  state.updateActiveKeys(event, false);
  assert.equal(state.activeKeys.D, undefined);
  state.helpProcess.running = false;
  state.helpExited(0);
  assert.equal(state.layerCompletionFeedbackTimer.running, false);
  state.handleHyprlandEvent({ name: "openlayer", data: "omarchy-keyboard-panel" });
  assert.equal(state.layerCompletionFeedbackTimer.running, true);
  assert.equal(state.stepOwnsCleanupSurface, true);
});

test("resize outcomes require a before snapshot and a real owned-window size change", () => {
  const state = runtime("windows-resize");
  const client = {address: "0xabc", at: [20, 20], size: [500, 300], mapped: true,
    hidden: false, monitor: 0, workspace: {id: 1}, floating: true, fullscreen: 0};
  state.tutorialWindows = ["0xabc"];
  state.tutorialWindowsByStep = {"windows-open-first": "0xabc"};
  state.runStepAction("shortcut");
  assert.equal(state.windowBaselineProcess.running, true);
  assert.equal(state.helpProcess.running, false);
  state.parseWindowBaseline(JSON.stringify([client]), state.actionGeneration);
  assert.equal(state.helpProcess.running, true);
  assert.equal(state.windowChangeBaseline.first.size[0], 500);
  state.helpProcess.running = false;
  state.helpExited(0);
  state.parseOutcome(JSON.stringify([client]), state.outcomeGeneration);
  assert.notEqual(state.outcomeAddress, "", "command acknowledgement is not a resize");
  state.parseOutcome(JSON.stringify([{...client, size: [600, 300]}]), state.outcomeGeneration);
  assert.equal(state.outcomeAddress, "");
  assert.equal(state.windowGeometryPending, true);
  state.cancelAction();
  assert.equal(state.windowChangeBaseline, null);
});

test("resize shortcuts recognize physical minus and equals positions on other keyboard layouts", () => {
  for (const [stepId, scan, label] of [["windows-resize", 21, "EQUAL"],
    ["windows-resize-back", 20, "MINUS"]] as const) {
    const state = runtime(stepId);
    Object.assign(state.Qt, { Key_0: 48, Key_9: 57, Key_A: 65, Key_Z: 90,
      ShiftModifier: 1, MetaModifier: 2, AltModifier: 4, ControlModifier: 8 });
    const actions: string[] = [];
    state.runStepAction = (source: string) => actions.push(source);
    state.updateActiveKeys({key: 233, nativeScanCode: scan, modifiers: 2, isAutoRepeat: false}, true);
    assert.deepEqual(actions, ["shortcut"]);
    assert.equal(state.activeKeys[label], true);
    state.updateActiveKeys({key: 233, nativeScanCode: scan, modifiers: 0}, false);
    assert.equal(state.activeKeys[label], undefined);
  }
});

test("window-change observations cannot award completion before successful dispatch", () => {
  const state = runtime("windows-resize");
  const client = {address: "0xabc", at: [20, 20], size: [500, 300], mapped: true,
    hidden: false, monitor: 0, workspace: {id: 1}, floating: true, fullscreen: 0};
  state.tutorialWindows = ["0xabc"];
  state.tutorialWindowsByStep = {"windows-open-first": "0xabc"};
  state.runStepAction("shortcut");
  state.requestOutcomeVerification();
  assert.equal(state.outcomeAddress, "");
  state.parseWindowBaseline(JSON.stringify([client]), state.actionGeneration);
  state.requestOutcomeVerification();
  assert.equal(state.outcomeAddress, "");
  state.outcomeAddress = "0xabc";
  state.outcomeExpected = state.currentStep.completion.windowState;
  const changed = JSON.stringify([{...client, size: [600, 300]}]);
  state.parseOutcome(changed, state.outcomeGeneration);
  assert.equal(state.outcomeAddress, "0xabc", "in-flight changes cannot complete the activity");
  state.helpProcess.running = false;
  state.helpExited(1);
  assert.equal(state.actionStepId, "");
  state.requestOutcomeVerification();
  assert.equal(state.outcomeProcess.running, false);
  state.parseOutcome(changed, state.outcomeGeneration);
  assert.equal(state.outcomeAddress, "0xabc", "a failed dispatch cannot earn completion");
});

test("split changes inspect the owned pair and actual workspace layout before dispatch", () => {
  const state = runtime("windows-split");
  // Complete the keyboard-release delay; this fixture tests layout gating, not timer scheduling.
  state.focusActionTimer.restart = () => { state.helpProcess.running = true; };
  const first = {address: "0xabc", at: [0, 0], size: [500, 600], mapped: true,
    hidden: false, monitor: 0, workspace: {id: 1}, floating: false, fullscreen: 0, focusHistoryID: 2};
  const peer = {...first, address: "0xdef", at: [510, 0], focusHistoryID: 1};
  state.tutorialWindows = ["0xabc", "0xdef"];
  state.tutorialWindowsByStep = {"windows-open-second": "0xabc", "windows-open-first": "0xdef"};
  state.runStepAction("shortcut");
  state.parseWindowBaseline(JSON.stringify([first, peer]), state.actionGeneration);
  assert.equal(state.helpProcess.running, false);
  state.parseLayoutPreflight(JSON.stringify([{id: 1, tiledLayout: "lua:custom"}]), state.actionGeneration);
  assert.equal(state.helpProcess.running, false);
  assert.match(state.recoveryMessage, /dwindle/);
  state.runStepAction("shortcut");
  state.parseWindowBaseline(JSON.stringify([first, peer]), state.actionGeneration);
  state.parseLayoutPreflight(JSON.stringify([{id: 1, tiledLayout: "dwindle"}]), state.actionGeneration);
  assert.equal(state.helpProcess.running, true);
  state.helpProcess.running = false;
  state.helpExited(0);
  first.focusHistoryID = 0;
  state.parseOutcome(JSON.stringify([first, peer]), state.outcomeGeneration);
  assert.notEqual(state.outcomeAddress, "");
  state.parseOutcome(JSON.stringify([{...first, size: [1010, 290]},
    {...peer, at: [0, 300], size: [1010, 300]}]), state.outcomeGeneration);
  assert.equal(state.outcomeAddress, "");
});

test("Welcome lesson replays the selected coach without clearing existing progress", () => {
  for (const character of ["ohm-1", "owl"]) {
    const { state, screens } = introRuntime();
    state.characterStore.select(character);
    state.welcomeSeen = true;
    state.stepResults = { "tour-workspaces": "introduced", "launch-terminal": "practiced" };
    state.stepCredits = { "tour-workspaces": true, "launch-terminal": true };
    state.completedLessons = { welcome: true, "everyday-apps": true };
    state.lessonBookmarks = { windows: "windows-swap" };
    const progress = JSON.stringify([state.stepResults, state.stepCredits, state.completedLessons, state.lessonBookmarks]);
    state.startLesson(0);
    assert.equal(state.phase, "welcome");
    assert.equal(state.welcomeStage, "scene");
    assert.equal(state.characterName, character);
    assert.equal(state.lessonIndex, -1);
    assert.equal(state.practiceMode, false);
    state.beginIntroScene();
    assert.equal(screens[0].player.plays, 1);
    screens[0].player.finish();
    state.flushCallbacks();
    state.welcomeArrived(state.introGeneration);
    assert.equal(state.welcomeStage, "welcome");
    state.advanceWelcome(state.introGeneration, "welcome");
    assert.equal(state.welcomeStage, "controls-flight");
    state.welcomeArrived(state.introGeneration);
    state.advanceWelcome(state.introGeneration, "controls");
    assert.equal(state.course.lessons[state.selectedLessonIndex].id, "omarchy-tour");
    state.finishWelcome();
    assert.equal(state.phase, "menu");
    assert.equal(JSON.stringify([state.stepResults, state.stepCredits, state.completedLessons, state.lessonBookmarks]), progress);
    assert.equal(state.lessonCompleted(state.course.lessons[0]), true);
    state.startLesson(0, true, false);
    assert.equal(state.phase, "welcome", "Practice shortcut replays rather than starting an empty exercise");
    assert.equal(state.practiceMode, false);
  }
});

test("selecting the tour restarts its first activity without a pack entrance", () => {
  for (const character of ["owl", "ohm-1"]) {
    const state = runtime("tour-omarchy-menu", false);
    state.startCharacterStep = state.productionStartCharacterStep;
    state.characterStore.select(character);
    state.lessonBookmarks["omarchy-tour"] = "tour-omarchy-menu";
    state.completedLessons["omarchy-tour"] = true;
    const tourIndex = state.course.lessons.findIndex((lesson: any) => lesson.id === "omarchy-tour");
    state.startLesson(tourIndex);
    assert.equal(state.currentStep.id, "tour-welcome");
    assert.equal(state.introActive, false);
    assert.equal(state.welcomeStage, "");
    assert.equal(state.completedLessons["omarchy-tour"], true);
    state.startLesson(tourIndex, false, false);
    assert.equal(state.introActive, false);
    state.startLesson(tourIndex, true, false);
    assert.equal(state.currentStep.id, "tour-welcome");
    assert.equal(state.introActive, false);
  }
});

test("transparent full-screen panel surfaces aren't treated as the visible menu card", () => {
  for (const transform of [0, 1]) {
    const state = runtime("tour-omarchy-menu");
    const monitor = { id: 0, name: "eDP-1", x: 0, y: 0, width: 3072, height: 1920, scale: 1.6, transform };
    const dimensions = transform ? [1200, 1920] : [1920, 1200];
    state.targetLayerNamespace = "omarchy-menu";
    state.parseLayerGeometry(JSON.stringify({
      "eDP-1": { levels: { "2": [{ namespace: "omarchy-menu", x: 0, y: 0, w: dimensions[0], h: dimensions[1] }] } },
    }), state.windowGeometryGeneration);
    state.parseMonitorGeometry(JSON.stringify([monitor]), state.windowGeometryGeneration);
    assert.equal(state.targetWindowGeometry, null);
    assert.equal(state.targetMonitorGeometry, null);
    assert.equal(state.targetScreenId, 0);
    assert.equal(state.targetGeometryRequested, false, "measurement does not start recurring panel refreshes");
  }
});

test("unmeasured panels avoid falsely precise pointers and outlines", () => {
  const condition = shell.match(/id: resultOutline[\s\S]*?visible: ([\s\S]*?)\n          x:/)?.[1];
  assert.ok(condition);
  for (const [target, measured, expected] of [
    ["panel", false, false], ["panel", true, true],
    ["window", false, false], ["window", true, true],
    ["workspace", false, true],
  ] as const) {
    const context = createContext({
      root: { phase: "highlight" },
      overlay: { highlight: { target }, usesWindowTarget: measured },
    });
    assert.equal(runInContext(condition, context), expected, `${target}, measured=${measured}`);
    context.root.phase = "waiting";
    assert.equal(runInContext(condition, context), false);
  }
  assert.doesNotMatch(shell, /Panel location \(estimate\)/);
  assert.match(shell, /id: targetMarker[\s\S]*?visible: root\.phase === "highlight" &&\s+overlay\.hasReliableCompletionTarget/);
});

test("the coach follows workspace estimates and measured popups, not unrelated bar buttons", () => {
  const estimated = shell.match(/readonly property bool targetIsEstimated: ([\s\S]*?)\n        readonly property bool hasReliableCompletionTarget/)?.[1];
  const reliable = shell.match(/readonly property bool hasReliableCompletionTarget: ([\s\S]*?)\n        readonly property bool hasCoachCompletionTarget/)?.[1];
  const coachTarget = shell.match(/readonly property bool hasCoachCompletionTarget: ([\s\S]*?)\n        readonly property real fittedHighlightWidth/)?.[1];
  const follows = shell.match(/readonly property bool targetsCompletion:\s*([\s\S]*?)\n          readonly property bool targetsTour/)?.[1];
  assert.ok(estimated && reliable && coachTarget && follows);
  for (const [target, windowMeasured, widgetMeasured, expected, widgetEstimated = false,
    surfaceOwned = false] of [
    ["panel", false, true, false],
    ["panel", false, true, true, false, true],
    ["panel", true, false, true],
    ["panel", false, false, false],
    ["window", true, false, true],
    ["window", false, true, false],
    ["workspace", false, true, true],
    ["workspace", false, true, true, true],
    ["workspace", false, false, false, true],
  ] as const) {
    for (const state of ["target-fly", "target-settle", "target-point"]) {
      const context = createContext({
        root: { currentStepHasNoVisibleTarget: false, characterState: state,
          stepOwnsCleanupSurface: surfaceOwned, targetLayerNamespace: surfaceOwned ? "omarchy-menu" : "" },
        highlight: { target },
        usesWindowTarget: windowMeasured,
        measuredBarTarget: widgetMeasured ? { x: 100, y: 20, width: 40, height: 30,
          estimated: widgetEstimated } : null,
        targetIsEstimated: false,
        overlay: { highlight: { target }, usesWindowTarget: windowMeasured, hasReliableCompletionTarget: false,
          hasCoachCompletionTarget: false },
      });
      context.targetIsEstimated = runInContext(estimated, context);
      context.overlay.hasReliableCompletionTarget = runInContext(reliable, context);
      context.hasReliableCompletionTarget = context.overlay.hasReliableCompletionTarget;
      context.overlay.hasCoachCompletionTarget = runInContext(coachTarget, context);
      assert.equal(runInContext(follows, context), expected, `${target}: ${state}, window=${windowMeasured}, widget=${widgetMeasured}`);
      context.root.currentStepHasNoVisibleTarget = true;
      context.overlay.hasReliableCompletionTarget = runInContext(reliable, context);
      context.hasReliableCompletionTarget = context.overlay.hasReliableCompletionTarget;
      context.overlay.hasCoachCompletionTarget = runInContext(coachTarget, context);
      assert.equal(runInContext(follows, context), false);
    }
  }
});

test("actual card-sized layers and fullscreen application windows keep measured geometry", () => {
  const monitor = { id: 0, name: "eDP-1", x: 0, y: 0, width: 3072, height: 1920, scale: 1.6 };
  const state = runtime("tour-omarchy-menu");
  state.targetLayerNamespace = "omarchy-menu";
  state.parseLayerGeometry(JSON.stringify({
    "eDP-1": { levels: { "2": [{ namespace: "omarchy-menu", x: 780, y: 240, w: 360, h: 720 }] } },
  }), state.windowGeometryGeneration);
  state.parseMonitorGeometry(JSON.stringify([monitor]), state.windowGeometryGeneration);
  assert.equal(state.targetWindowGeometry.at[0], 780);
  assert.equal(state.targetWindowGeometry.size[0], 360);
  state.targetLayerNamespace = "";
  state.targetLayerMonitor = "";
  state.targetWindowGeometry = { at: [0, 0], size: [1920, 1200], monitor: 0 };
  state.parseMonitorGeometry(JSON.stringify([monitor]), state.windowGeometryGeneration);
  assert.equal(state.targetWindowGeometry.size[0], 1920);
  assert.equal(state.targetMonitorGeometry.id, 0);
});

test("Back navigates without automatically repeating a desktop action", () => {
  const state = runtime("close-terminal");
  state.previousStep();
  assert.equal(state.currentStep.id, "launch-terminal");
  assert.equal(state.helpProcess.running, false);
});

test("window recovery returns to the dependent step after the learner relaunches", () => {
  const state = runtime("windows-close-one");
  state.startCurrentStep();
  assert.equal(state.recoveryStepId, "windows-open-second");
  assert.match(state.recoveryMessage, /isn't available/);
  assert.match(shell, /text: root\.recoveryMessage/);
  state.recoverTutorialWindow();
  assert.equal(state.currentStep.id, "windows-open-second");
  assert.equal(state.helpProcess.running, false);
  state.rememberTutorialWindow("111", "windows-open-second");
  state.phase = "highlight";
  state.advance();
  assert.equal(state.currentStep.id, "windows-close-one");
  assert.equal(state.currentTutorialWindow(), "0x111");
});

test("pause suspends narration and settings preserves the lesson position", () => {
  const state = runtime("open-root-menu");
  const signals: object[] = [];
  state.audioEnabled = true;
  state.audioProcess.running = true;
  state.audioProcessPath = state.currentAudioPath();
  state.audioProcess.write = (message: string) => signals.push(JSON.parse(message));
  state.openSettings("settings");
  assert.equal(state.phase, "settings");
  assert.equal(state.settingsReturnToLesson, true);
  assert.equal(state.audioProcess.running, true);
  assert.deepEqual(signals, [{ command: "pause" }]);
  state.closeSettings();
  assert.equal(state.phase, "waiting");
  assert.equal(state.currentStep.id, "open-root-menu");
  assert.deepEqual(signals, [{ command: "pause" }, { command: "resume" }]);
});

test("mute stops both sound channels immediately and persists the preference", () => {
  const state = runtime("open-root-menu");
  let persisted = "";
  state.settingsFile.setText = (text: string) => { persisted = text; };
  state.audioEnabled = true;
  state.audioProcess.running = true;
  state.sfxProcess.running = true;
  state.toggleAudio();
  assert.equal(state.audioProcess.running, false);
  assert.equal(state.sfxProcess.running, false);
  assert.equal(JSON.parse(persisted).audioEnabled, false);
});

test("window state matching requires the intended state, workspace, and focus", () => {
  const state = runtime("windows-float");
  const client = { mapped: true, hidden: false, floating: true, pinned: true, fullscreen: 2, workspace: { id: 2 }, focusHistoryID: 0 };
  state.currentWorkspaceId = () => 2;
  assert.equal(state.matchesWindowState(client, { workspace: 2, focused: true }), true);
  assert.equal(state.matchesWindowState(client, { workspace: 1 }), false);
  assert.equal(state.matchesWindowState(client, { floating: false }), false);
  assert.equal(state.matchesWindowState(client, { floating: true, pinned: true, fullscreen: true }), true);
  assert.equal(state.matchesWindowState(client, { pinned: false }), false);
  state.currentWorkspaceId = () => 1;
  assert.equal(state.matchesWindowState(client, { workspace: 2, focused: true }), false);
});

test("panel geometry resolves named layers and ignores stale responses", () => {
  const state = runtime("open-root-menu");
  state.requestPanelGeometry("omarchy-menu");
  const payload = JSON.stringify({
    "DP-1": { levels: { "2": [{ namespace: "omarchy-menu", x: 110, y: 120, w: 500, h: 600 }] } },
  });
  state.parseLayerGeometry(payload, state.windowGeometryGeneration - 1);
  assert.equal(state.targetWindowGeometry, null);
  state.parseLayerGeometry(payload, state.windowGeometryGeneration);
  assert.equal(state.targetLayerMonitor, "DP-1");
  assert.equal(state.targetWindowGeometry.size[0], 500);
  assert.equal(state.monitorGeometryProcess.running, true);
});

test("duplicate panel namespaces select the intended monitor instead of enumeration order", () => {
  const state = runtime("open-root-menu");
  state.requestPanelGeometry("omarchy-menu");
  state.Hyprland.focusedMonitor = { name: "DP-1" };
  const panel = { namespace: "omarchy-menu", x: 100, y: 120, w: 500, h: 600 };
  const payload = JSON.stringify({
    "eDP-1": { levels: { "2": [panel] } },
    "DP-1": { levels: { "2": [{ ...panel, x: 2200 }] } },
  });
  state.parseLayerGeometry(payload, state.windowGeometryGeneration);
  assert.equal(state.targetLayerMonitor, "DP-1");
  assert.equal(state.targetWindowGeometry.at[0], 2200);
  state.targetLayerMonitor = "";
  state.Hyprland.focusedMonitor = null;
  state.parseLayerGeometry(payload, state.windowGeometryGeneration);
  assert.equal(state.targetWindowGeometry, null);
});

test("application launch lifetime is independent of activity cancellation", () => {
  const state = runtime("launch-files");
  const commands: string[][] = [];
  state.Quickshell.execDetached = (command: string[]) => commands.push(command);
  state.runStepAction("shortcut");
  assert.deepEqual(Array.from(commands[0]).slice(2), ["omarchy", "launch", "nautilus"]);
  assert.equal(state.helpProcess.running, false);
  assert.equal(state.windowActivationHintTimer.running, true);
  state.handleHyprlandEvent({ name: "openwindow", data: "abc,1,org.gnome.Nautilus,Files" });
  state.finishWindowDetection(client("0xabc"), null);
  confirmWindowOwnership(state);
  assert.equal(state.actionRunning, false);
  state.stepIndex++;
  state.startCurrentStep();
  assert.equal(state.currentTutorialWindow(), "0xabc");
});

test("focus actions release exclusive focus until their outcome is verified", () => {
  for (const outcome of ["verified", "failed", "cancelled"]) {
    const state = runtime("windows-focus-next");
    state.rememberTutorialWindow("abc", "windows-open-first");
    state.runStepAction("shortcut");
    assert.equal(state.keyboardExclusive, false);
    assert.equal(state.restoreKeyboardAfterAction, true);
    assert.equal(state.focusActionTimer.running, true);
    assert.equal(state.helpProcess.running, false);
    if (outcome === "verified") state.finishWindowDetection(client("0xabc"), null);
    else if (outcome === "failed") state.showRecovery("Focus failed");
    else {
      state.cancelAction();
      assert.equal(state.focusActionTimer.running, false);
    }
    assert.equal(state.keyboardExclusive, true);
    assert.equal(state.restoreKeyboardAfterAction, false);
  }
});

test("an already-open panel can complete after a successful summon", () => {
  const state = runtime("open-root-menu");
  state.runStepAction("shortcut");
  state.requestPanelGeometry("omarchy-menu");
  state.parseLayerGeometry(JSON.stringify({
    "DP-1": { levels: { "2": [{ namespace: "omarchy-menu", x: 0, y: 0, w: 1920, h: 1200 }] } },
  }), state.windowGeometryGeneration);
  assert.equal(state.layerCompletionFeedbackTimer.running, true);
});

test("exclusive course input inhibits compositor shortcuts only while captured", () => {
  assert.match(shell, /ShortcutInhibitor\s*\{[\s\S]*?window: overlay[\s\S]*?enabled: root\.keyboardExclusive && !root\.keyboardCaptureResetting && overlay\.shouldShow/);
  assert.match(shell, /onCancelled: root\.setKeyboardExclusive\(false\)/);
});

test("a fast chord is recognized before its key-release event clears the keys", () => {
  const state = runtime("close-terminal");
  state.rememberTutorialWindow("abc", "launch-terminal");
  state.Qt.MetaModifier = 0x10000000;
  state.Qt.Key_A = 65;
  state.Qt.Key_Z = 90;
  const deferred: (() => void)[] = [];
  state.Qt.callLater = (callback: () => void) => deferred.push(callback);
  const event = { key: 87, modifiers: state.Qt.MetaModifier, isAutoRepeat: false };
  state.updateActiveKeys(event, true);
  state.updateActiveKeys(event, false);
  for (const callback of deferred) callback();
  assert.equal(state.helpProcess.running, true);
  assert.match(state.helpProcess.command[2], /address:0xabc/);
});

test("opening tour highlights the measured span from menu to system controls on every bar edge", () => {
  const state = runtime("tour-welcome");
  for (const vertical of [false, true]) {
    const screen = state.geometryScreens()[0];
    const widgets = vertical
      ? [
        { id: "omarchy.menu", x: 0, y: 9, width: 30, height: 32, visible: true, itemVisible: true },
        { id: "omarchy.power", x: 0, y: 1100, width: 30, height: 64, visible: true, itemVisible: true },
      ] : [
        { id: "omarchy.menu", x: 9, y: 1170, width: 32, height: 30, visible: true, itemVisible: true },
        { id: "omarchy.power", x: 1847, y: 1170, width: 64, height: 30, visible: true, itemVisible: true },
      ];
    assert.equal(state.parseBarGeometry(JSON.stringify({ version: 1, screens: [{ ...screen, widgets }] }),
      state.geometryScreens()), true);
    const target = state.barTargetGeometry(state.currentStep.highlight, 0);
    assert.deepEqual(JSON.parse(JSON.stringify(target)), vertical
      ? { x: 0, y: 9, width: 30, height: 1155 }
      : { x: 9, y: 1170, width: 1902, height: 30 });
  }
});

test("measured bar geometry distinguishes the workspace group from individual numbers", () => {
  const state = runtime("tour-workspaces");
  state.Hyprland = { workspaces: { values: [{ id: 6 }] } };
  state.parseBarGeometry(JSON.stringify({ version: 1, screens: [{ ...state.geometryScreens()[0], widgets: [
    { id: "omarchy.menu", x: 9, y: 0, width: 32, height: 30, visible: true, itemVisible: true },
    { id: "omarchy.workspaces", x: 41, y: 0, width: 145, height: 30, visible: true, itemVisible: true },
  ] }] }), state.geometryScreens());
  const group = state.barTargetGeometry(state.currentStep.highlight, 0);
  assert.deepEqual(JSON.parse(JSON.stringify(group)), { x: 9, y: 0, width: 177, height: 30 });
  const workspace = state.barTargetGeometry({ target: "workspace" }, 1);
  assert.equal(workspace.x, 41 + 145 / 6);
  assert.ok(Math.abs(workspace.width - 145 / 6) < 0.000001);
  assert.equal(workspace.estimated, true);
  assert.ok(workspace.x > 41, "workspace two must not highlight the menu icon or workspace one");
  state.Quickshell.screens.push({});
  assert.equal(state.barTargetGeometry(state.currentStep.highlight, 0), null);
});

test("the menu-opening result uses its center-card estimate, while the following stop targets the icon", () => {
  const state = runtime("tour-omarchy-menu");
  const screen = state.geometryScreens()[0];
  const widgets = [{ id: "omarchy.menu", x: 9, y: 0, width: 32, height: 30, visible: true, itemVisible: true }];
  assert.equal(state.parseBarGeometry(
    JSON.stringify({ version: 1, screens: [{ ...screen, widgets }] }), state.geometryScreens()), true);
  assert.equal(state.barTargetGeometry(state.currentStep.highlight, 0), null);
  const icon = state.currentLesson.steps.find((step: any) => step.id === "tour-menu-icon");
  assert.equal(state.barTargetGeometry(icon.highlight, 0).x, 9);
});

test("an opened menu is targeted instead of the bar button that opened it", () => {
  const state = runtime("open-root-menu");
  const screen = state.geometryScreens()[0];
  const widgets = [{ id: "omarchy.menu", x: 9, y: 0, width: 32, height: 30, visible: true, itemVisible: true }];
  assert.equal(state.parseBarGeometry(
    JSON.stringify({ version: 1, screens: [{ ...screen, widgets }] }), state.geometryScreens()), true);
  assert.equal(state.barTargetGeometry(state.currentStep.highlight, 0).x, 9);
  state.stepOwnsCleanupSurface = true;
  state.targetLayerNamespace = "omarchy-menu";
  assert.equal(state.barTargetGeometry(state.currentStep.highlight, 0), null,
    "an open menu falls back to its centered estimate");
});

test("monitor-tagged measurements select the right output even with identical monitor sizes", () => {
  const state = runtime("tour-clock");
  state.Quickshell.screens.push({ name: "DP-1", x: 1920, y: 0, width: 1920, height: 1200 });
  const outputs = state.geometryScreens();
  const snapshot = { version: 1, screens: outputs.map((screen: { name: string; width: number; height: number }) => ({
    ...screen,
    widgets: [{ id: "omarchy.clock", x: screen.name === "DP-1" ? 1200 : 800, y: 6,
      width: 100, height: 30, visible: true, itemVisible: true }],
  })) };
  assert.equal(state.parseBarGeometry(JSON.stringify(snapshot), outputs), true);
  const external = state.Quickshell.screens[1];
  const internal = state.Quickshell.screens[0];
  assert.equal(state.barTargetGeometry(state.currentStep.highlight, 0, internal).x, 800);
  assert.equal(state.barTargetGeometry(state.currentStep.highlight, 0, external).x, 1200);
  assert.equal(state.barTargetGeometry(state.currentStep.highlight, 0), null);
  assert.equal(state.barTargetGeometry(state.currentStep.highlight, 0, external, 960, 600).x, 600);
});

test("bar caches and in-flight results are rejected after output resize or topology change", () => {
  const state = runtime("tour-clock");
  const screens = state.geometryScreens();
  const rawFor = (output: object) => JSON.stringify({ version: 1, screens: [{ ...output,
    widgets: [{ id: "omarchy.clock", x: 800, y: 0, width: 100, height: 30, visible: true, itemVisible: true }] }] });
  const raw = rawFor(screens[0]);
  state.parseBarGeometry(raw, screens);
  assert.ok(state.barTargetGeometry(state.currentStep.highlight, 0));
  state.Quickshell.screens[0].width = 1280;
  assert.equal(state.barTargetGeometry(state.currentStep.highlight, 0), null);
  state.finishBarGeometry(0, raw, screens);
  assert.equal(state.barTargetGeometry(state.currentStep.highlight, 0), null);
  assert.equal(state.parseBarGeometry(raw, state.geometryScreens()), false, "stale output sizes are rejected");
  state.parseBarGeometry(rawFor(state.geometryScreens()[0]), state.geometryScreens());
  assert.ok(state.barTargetGeometry(state.currentStep.highlight, 0));
  state.Quickshell.screens.push({ name: "DP-1", width: 1920, height: 1080, x: 1280, y: 0 });
  assert.equal(state.barTargetGeometry(state.currentStep.highlight, 0, state.Quickshell.screens[0]), null);
});

test("bar measurements never guess a multi-monitor association", () => {
  const state = runtime("tour-clock");
  state.requestBarGeometry();
  state.flushGeometryRequests();
  assert.equal(state.barGeometryProcess.running, true);
  assert.match(shell, /id: barGeometryProcess[\s\S]*?command: \["node", root\.appRoot \+ "\/tools\/bar-geometry\.mjs"\]/);
  state.barGeometryProcess.running = false;
  state.Quickshell.screens.push({ name: "DP-1", x: 1920, y: 0, width: 1920, height: 1200 });
  state.requestBarGeometry();
  state.flushGeometryRequests();
  assert.equal(state.barGeometryProcess.running, false);
  assert.match(state.integrationNotice, /single monitor/);
});

test("geometry refreshes have no repeating timers or timed provider retries", () => {
  assert.doesNotMatch(shell, /geometryProviderRetryAt|windowGeometryRefreshTimer/);
  for (const [timer] of shell.matchAll(/^  Timer \{[\s\S]*?^  \}/gm)) {
    if (/repeat: true/.test(timer))
      assert.doesNotMatch(timer, /requestBarGeometry|requestPanelGeometry|queryWindowGeometry|flushGeometryRequests/);
  }
  assert.match(shell, /onPhaseChanged: \{[\s\S]*?requestBarGeometry\(\)/);
  assert.match(shell, /onDesktopGeometryTopologyChanged: \{[\s\S]*?requestTargetGeometryRefresh\(\)/);
  for (const process of ["barGeometryProcess", "clientGeometryProcess", "monitorGeometryProcess", "layerGeometryProcess"]) {
    const block = shell.match(new RegExp("  Process \\{\\n    id: " + process + "[\\s\\S]*?\\n  \\}"))![0];
    assert.match(block, process === "barGeometryProcess" ? /finishBarGeometry/ : /onExited: Qt.callLater\(root.flushGeometryRequests\)/);
  }
});

test("event bursts coalesce and keep only one follow-up measurement in flight", () => {
  const state = runtime("tour-clock");
  const callbacks = new Set<() => void>();
  state.Qt.callLater = (callback: () => void) => callbacks.add(callback);
  const drain = () => {
    const pending = [...callbacks];
    callbacks.clear();
    pending.forEach(callback => callback());
  };
  let running = false;
  let starts = 0;
  Object.defineProperty(state.barGeometryProcess, "running", {
    get: () => running,
    set: (value: boolean) => { if (value && !running) starts++; running = value; },
  });
  const screens = state.geometryScreens();
  const raw = JSON.stringify({ version: 1, screens: [{ ...screens[0], widgets: [
    { id: "omarchy.clock", x: 800, y: 0, width: 100, height: 30, visible: true, itemVisible: true },
  ] }] });
  for (let i = 0; i < 20; i++) state.handleGeometryEvent({ name: "workspacev2", data: "1,1" });
  assert.equal(callbacks.size, 1);
  assert.equal(starts, 0);
  drain();
  assert.equal(starts, 1);
  for (let i = 0; i < 20; i++) state.requestBarGeometry();
  drain();
  assert.equal(starts, 1, "events never start parallel measurements");
  state.barGeometryProcess.running = false;
  state.finishBarGeometry(0, raw, screens);
  drain();
  assert.equal(starts, 2, "one follow-up covers all events received while busy");
  state.barGeometryProcess.running = false;
  state.finishBarGeometry(0, raw, screens);
  drain();
  assert.equal(starts, 2);
  assert.equal(callbacks.size, 0, "an idle desktop schedules no more work");
  assert.equal(state.barGeometryAvailable, true);
});

test("irrelevant events and inactive screens do not request geometry", () => {
  const state = runtime("tour-clock");
  for (const name of ["windowtitle", "windowtitlev2", "urgent", "submap"]) {
    state.handleGeometryEvent({ name, data: "abc" });
    assert.equal(state.barGeometryRequested, false, name);
    assert.equal(state.targetGeometryRequested, false, name);
  }
  for (const data of ["learn-omarchy", "learn-omarchy-coach", "notifications"]) {
    state.handleGeometryEvent({ name: "openlayer", data });
    state.handleGeometryEvent({ name: "closelayer", data });
    assert.equal(state.barGeometryRequested, false, data);
  }
  for (const phase of ["menu", "arcade", "paused", "settings", "lesson-complete"]) {
    state.phase = phase;
    state.barGeometryRequested = true;
    state.targetGeometryRequested = true;
    state.handleGeometryEvent({ name: "workspacev2", data: "2,2" });
    state.flushGeometryRequests();
    assert.equal(state.barGeometryProcess.running, false, phase);
    assert.equal(state.barGeometryRequested, false, phase);
    assert.equal(state.targetGeometryRequested, false, phase);
  }
  const windowStep = runtime("launch-terminal");
  windowStep.handleGeometryEvent({ name: "workspacev2", data: "2,2" });
  windowStep.flushGeometryRequests();
  assert.equal(windowStep.barGeometryProcess.running, false, "window-only steps do not measure the bar");
});

test("failed geometry waits for a new event instead of retrying at idle", () => {
  const state = runtime("tour-clock");
  state.requestBarGeometry();
  state.flushGeometryRequests();
  state.barGeometryProcess.running = false;
  state.finishBarGeometry(1, "", state.geometryScreens());
  for (let i = 0; i < 10; i++) state.flushGeometryRequests();
  assert.equal(state.barGeometryProcess.running, false);
  assert.equal(state.barGeometryRequested, false);
  assert.match(state.integrationNotice, /could not be measured/);
  state.handleGeometryEvent({ name: "openlayer", data: "omarchy-bar" });
  state.flushGeometryRequests();
  assert.equal(state.barGeometryProcess.running, true, "a relevant event allows a fresh attempt");
});

test("display changes invalidate cached geometry and remeasure after old requests finish", () => {
  const state = runtime("tour-clock");
  const screens = state.geometryScreens();
  const raw = JSON.stringify({ version: 1, screens: [{ ...screens[0],
    widgets: [{ id: "omarchy.clock", x: 800, y: 0, width: 100, height: 30, visible: true, itemVisible: true }] }] });
  state.parseBarGeometry(raw, screens);
  state.requestBarGeometry();
  state.flushGeometryRequests();
  state.Quickshell.screens[0].width = 1280;
  runInContext(shell.match(/^  onDesktopGeometryTopologyChanged: \{([\s\S]*?)^  \}/m)![1], state);
  assert.equal(state.barGeometryAvailable, false);
  assert.equal(state.barGeometry.length, 0);
  state.flushGeometryRequests();
  assert.equal(state.barGeometryRequested, true, "a changed display is queued behind the active request");
  state.barGeometryProcess.running = false;
  state.finishBarGeometry(0, raw, screens);
  assert.equal(state.barGeometry.length, 0, "old output coordinates are not applied");
  state.flushGeometryRequests();
  assert.equal(state.barGeometryProcess.requestScreens[0].width, 1280);
});

test("panel events refresh only the affected panel and share the geometry queue", () => {
  const state = runtime("open-root-menu");
  state.requestPanelGeometry("omarchy-menu");
  state.handleGeometryEvent({ name: "openlayer", data: "omarchy-menu" });
  state.flushGeometryRequests();
  assert.equal(state.layerGeometryProcess.running, true);
  assert.equal(state.barGeometryProcess.running, true);
  assert.equal(state.targetGeometryRequested, false);
  state.handleGeometryEvent({ name: "openlayer", data: "notifications" });
  assert.equal(state.targetGeometryRequested, false);
  state.targetWindowGeometry = { at: [0, 0], size: [100, 100] };
  state.handleGeometryEvent({ name: "closelayer", data: "omarchy-menu" });
  assert.equal(state.targetWindowGeometry, null);
  assert.equal(state.targetGeometryRequested, true, "closure waits behind an in-flight panel request");
});

test("window refreshes wait for monitor measurement and do not loop", () => {
  const state = runtime("launch-terminal");
  state.phase = "highlight";
  state.targetWindowAddress = "0xabc";
  state.handleGeometryEvent({ name: "fullscreen", data: "1" });
  state.flushGeometryRequests();
  assert.equal(state.clientGeometryProcess.running, true);
  assert.equal(state.windowGeometryRefreshing, true);
  state.handleGeometryEvent({ name: "movewindowv2", data: "abc,2,2" });
  state.clientGeometryProcess.running = false;
  state.parseClientGeometry(JSON.stringify([{ ...client("0xabc"), monitor: 0 }]), state.windowGeometryGeneration);
  state.flushGeometryRequests();
  assert.equal(state.monitorGeometryProcess.running, true);
  assert.equal(state.clientGeometryProcess.running, false, "follow-up waits for the entire measurement");
  state.monitorGeometryProcess.running = false;
  state.flushGeometryRequests();
  assert.equal(state.clientGeometryProcess.running, true);
  assert.equal(state.targetGeometryRequested, false);
  state.resetWindowTarget();
  state.clientGeometryProcess.running = false;
  state.flushGeometryRequests();
  assert.equal(state.clientGeometryProcess.running, false, "leaving the target cancels queued refreshes");
});

test("stale window results cannot consume a current refresh request", () => {
  const state = runtime("launch-terminal");
  state.windowGeometryRefreshing = true;
  state.parseClientGeometry("[]", state.windowGeometryGeneration - 1);
  assert.equal(state.windowGeometryRefreshing, true);
});

test("unavailable bar measurements retain the configured geometry fallback", () => {
  const state = runtime("workspaces-home");
  assert.equal(state.barTargetGeometry(state.currentStep.highlight, 0), null);
  state.parseBarGeometry('{"error":"unsupported"}');
  assert.equal(state.barGeometryAvailable, false);
  assert.equal(state.highlightWidth(state.currentStep.highlight), 28);
});

test("estimated geometry adapts to logical screen size, orientation and every anchor", () => {
  const state = runtime("tour-workspaces");
  for (const [width, height] of [[1280, 720], [1920, 1200], [2560, 1440], [1080, 1920], [640, 480]]) {
    for (const anchor of ["top-left", "top", "top-right", "left", "center", "right", "bottom-left", "bottom", "bottom-right"]) {
      const rect = state.estimatedTargetGeometry({
        shape: "rectangle", anchor, x: -8, y: 1, width: 340, height: 760,
      }, width, height, 0);
      assert.ok(rect.x >= 0 && rect.y >= 0);
      assert.ok(rect.x + rect.width <= width);
      assert.ok(rect.y + rect.height <= height);
      assert.equal(rect.estimated, true);
      assert.equal(rect.width, 340 * width / 1920);
      assert.equal(rect.height, 760 * height / 1200);
    }
    const circle = state.estimatedTargetGeometry({
      shape: "circle", anchor: "bottom-right", x: 0, y: 0, width: 500, height: 500,
    }, width, height, 0);
    assert.equal(circle.width, circle.height);
  }
});

test("authored reference viewport and monitor scaling don't double-scale fallback geometry", () => {
  const state = runtime("tour-workspaces");
  const highlight = { shape: "rectangle", anchor: "center", x: 0, y: 0, width: 300, height: 200 };
  const logical = state.logicalMonitorSize({ width: 3840, height: 2400, scale: 2, transform: 0 });
  assert.deepEqual(
    JSON.parse(JSON.stringify(state.estimatedTargetGeometry(highlight, logical.width, logical.height, 0))),
    { x: 810, y: 500, width: 300, height: 200, estimated: true },
  );
  state.course.referenceViewport = { width: 1280, height: 720 };
  const rect = state.estimatedTargetGeometry(highlight, 1920, 1080, 0);
  assert.equal(rect.width, 450);
  assert.equal(rect.height, 300);
  assert.equal(state.estimatedTargetGeometry(highlight, 0, 0, 0), null);
});

test("measured windows project onto their own scaled and rotated monitor", () => {
  const state = runtime("launch-terminal");
  for (const scale of [1, 1.25, 1.5, 2]) {
    for (const transform of [0, 1, 2, 3]) {
      const monitor = { x: -1920, y: 300, width: 2560, height: 1440, scale, transform };
      const logical = state.logicalMonitorSize(monitor);
      const data = { at: [monitor.x + 100, monitor.y + 80], size: [400, 300] };
      const rect = state.projectWindowGeometry(data, monitor, logical.width, logical.height);
      assert.deepEqual(JSON.parse(JSON.stringify(rect)), { x: 100, y: 80, width: 400, height: 300 });
      const resized = state.projectWindowGeometry(data, monitor, logical.width / 2, logical.height / 2);
      assert.deepEqual(JSON.parse(JSON.stringify(resized)), { x: 50, y: 40, width: 200, height: 150 });
    }
  }
});

test("measured bounds are clipped to the visible screen, not an adjacent monitor", () => {
  const state = runtime("launch-terminal");
  const monitor = { x: 1920, y: 0, width: 1280, height: 720, scale: 1, transform: 0 };
  const rect = state.projectWindowGeometry({ at: [1800, -100], size: [500, 400] }, monitor, 1280, 720);
  assert.deepEqual(JSON.parse(JSON.stringify(rect)), { x: 0, y: 0, width: 380, height: 300 });
  assert.equal(state.projectWindowGeometry({ at: [0, 0], size: [400, 300] }, monitor, 1280, 720), null);
});

test("refreshing a window also refreshes an unchanged monitor's resolution and scale", () => {
  const state = runtime("launch-terminal");
  state.targetWindowAddress = "0xabc";
  state.targetMonitorGeometry = { id: 0 };
  state.windowGeometryRefreshing = true;
  state.parseClientGeometry(JSON.stringify([{ ...client("0xabc"), monitor: 0 }]), state.windowGeometryGeneration);
  assert.equal(state.monitorGeometryProcess.running, true);
});

test("unrelated windows cannot complete an activity while shortcut capture is inhibited", () => {
  const state = runtime("launch-terminal");
  state.shortcutInhibitionActive = true;
  state.handleHyprlandEvent({ name: "openwindow", data: "abc,1,org.omarchy.screensaver,Screensaver" });
  assert.equal(state.windowGeometryPending, false);
  assert.equal(state.targetWindowAddress, "");
});

test("legacy channel-off preferences become zero-volume sliders without changing toolbar mute", () => {
  const state = runtime("tour-welcome");
  state.loadSettings(JSON.stringify({ character: "ohm-1", speechEnabled: false, effectsEnabled: false,
    speechVolume: 80, effectsVolume: 75, audioEnabled: true }));
  assert.equal(state.speechVolume, 0);
  assert.equal(state.effectsVolume, 0);
  assert.equal(state.audioEnabled, true);
  assert.equal(state.narrationEnabled, false);
  state.openSettings("settings");
  assert.equal(state.resetOptionsExpanded, false);
  state.resetConfirmPending = true;
  state.closeSettings();
  assert.equal(state.resetConfirmPending, false);
});

test("motion and sound settings are bounded when loaded", () => {
  const state = runtime("open-root-menu");
  state.loadSettings(JSON.stringify({ character: "ohm-1", speechVolume: 1000, effectsVolume: -5,
    speechRate: 20, textScale: 5, motionReduced: true, autoAdvance: false, audioEnabled: false }));
  assert.equal(state.speechVolume, 100);
  assert.equal(state.effectsVolume, 0);
  assert.equal(state.speechRate, 1.5);
  assert.equal(state.textScale, 1.3);
  assert.equal(state.motionReduced, true);
  assert.equal(state.autoAdvance, false);
});

test("secondary text maintains readable contrast on light and dark themes", () => {
  const state = runtime("open-root-menu");
  for (const background of [{ r: 0.1, g: 0.1, b: 0.15 }, { r: 0.9, g: 0.9, b: 0.95 }]) {
    const result = state.readableSecondaryColor({ r: 0.4, g: 0.45, b: 0.6 }, background);
    const foregroundLight = state.colorLuminance(result);
    const backgroundLight = state.colorLuminance(background);
    const ratio = (Math.max(foregroundLight, backgroundLight) + 0.05) /
      (Math.min(foregroundLight, backgroundLight) + 0.05);
    assert.ok(ratio >= 4.5);
  }
});

test("rejected or unverified launch candidates never gain close permission", () => {
  for (const skip of [false, true]) {
    const state = runtime("launch-terminal");
    state.currentStep.completion.appIdPattern = "^expected-terminal$";
    state.runStepAction("help");
    state.handleHyprlandEvent({ name: "openwindow", data: "abc,1,unrelated,Unrelated" });
    if (skip) {
      state.helpProcess.running = false;
      state.skipCurrentStep();
    } else {
      state.parseClientGeometry(JSON.stringify([{ ...client("0xabc"), class: "unrelated" }]),
        state.windowGeometryGeneration);
    }
    assert.equal(state.tutorialWindows.length, 0);
    assert.equal(state.tutorialWindowsByStep["launch-terminal"], undefined);
    assert.equal(state.pendingTutorialWindowAddress, "");
  }
});

test("pause preserves pending verified and action-success completions", () => {
  for (const timerName of ["layerCompletionFeedbackTimer", "actionCompletionTimer"]) {
    const state = runtime("launch-terminal");
    state[timerName].restart();
    assert.equal(state.pauseLesson(), true);
    assert.equal(state[timerName].running, false);
    state.resumePausedLesson();
    assert.equal(state.phase, "highlight");
    assert.equal(state.stepResults["launch-terminal"], "practiced");
  }
});

test("muting during the instruction-to-completion handoff still advances", () => {
  const state = runtime("launch-terminal");
  state.audioEnabled = true;
  state.audioProcess.running = true;
  state.audioProcessPath = state.currentAudioPath();
  state.audioStopRequested = true;
  state.phase = "highlight";
  state.highlightStartedAt = Date.now();
  state.pendingAudioPath = state.completionAudioPath();
  state.toggleAudio();
  assert.equal(state.pendingAudioPath, "");
  assert.equal(state.completionTimer.running, true);
});

test("muted tour timing accounts for the text the learner needs to read", () => {
  const state = runtime("tour-clock");
  assert.ok(state.tourFallbackDuration() >= state.readingDuration(state.currentStep.instruction));
});

test("tour Details holds timed captions and stale callbacks, then gives fresh reading time", () => {
  const state = runtime("tour-clock");
  state.beginTourNarration();
  assert.equal(state.tourAdvanceTimer.running, true);
  state.tourDetailsExpanded = true;
  state.updateTourDetails();
  assert.equal(state.tourAdvanceTimer.running, false);
  state.beginTourNarration();
  state.scheduleTourAdvance();
  state.advanceTour();
  assert.equal(state.currentStep.id, "tour-clock");
  assert.equal(state.tourAdvanceTimer.running, false);
  state.tourDetailsExpanded = false;
  state.updateTourDetails();
  assert.equal(state.tourAdvanceTimer.running, true);
  assert.ok(state.tourAdvanceTimer.interval >= state.readingDuration(state.currentStep.detail));
  state.advanceTour();
  assert.notEqual(state.currentStep.id, "tour-clock");
  assert.match(shell, /onTriggered: root\.advanceTour\(\)/);
});

test("tour narration continues through Details and collapse never cuts speech short", () => {
  for (const closeBeforeEnd of [true, false]) {
    for (const exitCode of [0, 1]) {
      const state = runtime("tour-clock");
      state.audioEnabled = true;
      state.beginTourNarration();
      assert.equal(state.audioProcess.running, true);
      state.tourDetailsExpanded = true;
      state.updateTourDetails();
      assert.equal(state.audioProcess.running, true);
      if (closeBeforeEnd) {
        state.tourDetailsExpanded = false;
        state.updateTourDetails();
        state.advanceTour();
        assert.equal(state.tourAdvanceTimer.running, false);
        assert.equal(state.currentStep.id, "tour-clock");
      }
      state.audioProcess.running = false;
      state.audioExited(exitCode);
      assert.equal(state.tourAdvanceTimer.running, closeBeforeEnd);
      if (!closeBeforeEnd) {
        state.advanceTour();
        assert.equal(state.currentStep.id, "tour-clock");
        state.tourDetailsExpanded = false;
        state.updateTourDetails();
      }
      assert.equal(state.tourAdvanceTimer.running, true);
      assert.ok(state.tourAdvanceTimer.interval >= state.narrationRestMs);
    }
  }
});

test("tour Details gates mute fallback, replay, manual mode, pause, and transitions", () => {
  const state = runtime("tour-clock");
  state.audioEnabled = true;
  state.beginTourNarration();
  state.tourDetailsExpanded = true;
  state.updateTourDetails();
  state.toggleAudio();
  state.audioExited(0);
  assert.equal(state.tourAdvanceTimer.running, false);
  state.toggleAudio();
  assert.equal(state.audioProcess.running, true);
  state.replayCurrentAudio();
  assert.equal(state.audioProcess.running, false);
  assert.equal(state.tourAdvanceTimer.running, false);
  state.Qt.callLater = (callback: () => void) => callback();
  state.audioExited(0);
  assert.equal(state.audioProcess.running, true);
  state.audioProcess.running = false;
  state.audioExited(0);
  state.tourDetailsExpanded = false;
  state.pendingLessonTransition = "step";
  for (const [key, value] of [
    ["autoAdvance", false], ["phase", "paused"], ["phase", "settings"],
    ["lessonTransitionRunning", true], ["audioStopRequested", true],
    ["pendingAudioPath", state.currentAudioPath()],
  ] as const) {
    const original = state[key];
    state[key] = value;
    state.updateTourDetails();
    state.advanceTour();
    assert.equal(state.tourAdvanceTimer.running, false, key);
    assert.equal(state.currentStep.id, "tour-clock", key);
    state[key] = original;
  }
  state.tourDetailsExpanded = true;
  state.advance();
  assert.notEqual(state.currentStep.id, "tour-clock", "manual Next is not gated");
});

test("tour fallback survives stopped prior narration and the incoming transition", () => {
  const state = runtime("tour-clock", false);
  state.audioStopRequested = true;
  state.audioProcessPath = "/course/audio/ohm-1/prior-step.mp3";
  state.beginTourNarration();
  assert.equal(state.tourAdvanceTimer.running, false);
  state.lessonTransitionRunning = true;
  state.pendingLessonTransition = "";
  state.audioExited(0);
  assert.equal(state.tourAdvanceTimer.running, true);
  state.advanceTour();
  assert.equal(state.currentStep.id, "tour-clock");
  state.lessonTransitionRunning = false;
  state.advanceTour();
  assert.equal(state.pendingLessonTransition, "step");
});

test("skipping the opening scene still travels to the standalone welcome", () => {
  const state = runtime("tour-welcome");
  state.characterState = "intro";
  state.introActive = true;
  state.phase = "welcome";
  state.welcomeStage = "scene";
  state.Qt.callLater = (callback: () => void) => callback();
  state.skipIntroScene();
  assert.equal(state.characterState, "tour-fly");
  assert.equal(state.welcomeStage, "center-flight");
  assert.equal(state.tourAdvanceTimer.running, false);
  assert.equal(state.introActive, false);
  assert.equal(state.currentStep.id, "tour-welcome");
});

function introRuntime(reducedMotion = false) {
  const state = runtime("tour-welcome", reducedMotion);
  state.phase = "menu";
  state.lessonIndex = -1;
  const deferred: Array<() => void> = [];
  state.Qt.callLater = (callback: () => void) => deferred.push(callback);
  state.flushCallbacks = () => { while (deferred.length) deferred.shift()!(); };
  state.startCharacterStep = state.productionStartCharacterStep;
  const screens = [true, false].map((shouldShow) => {
    const overlay = { shouldShow };
    const coach = { x: 320, y: 640, userX: 0, userY: 0, userPlaced: false };
    const player = {
      sequence: state.characterStore.selectedPack.intro,
      assetRoot: state.characterStore.selectedPack.assetUrl,
      displayName: state.characterDisplayName,
      reducedMotion, running: false, playbackGeneration: -1, handoffPinned: false,
      characterX: 328, characterY: 708, characterScale: 1, characterOpacity: 1,
      characterVisible: true, characterPose: "idle", characterFacing: 1, characterFlying: false,
      plays: 0,
      play() { this.running = true; this.plays++; },
      cancel() {
        const running = this.running;
        this.running = false;
        if (running && overlay.shouldShow && state.introActive && this.playbackGeneration === state.introGeneration)
          state.finishIntro(this.playbackGeneration, "Interrupted");
      },
      reset() { this.cancel(); },
      finish() {
        this.running = false;
        if (overlay.shouldShow) state.finishIntro(this.playbackGeneration);
      },
      fail(message: string) {
        this.running = false;
        if (overlay.shouldShow) state.finishIntro(this.playbackGeneration, message);
      },
    };
    const context = createContext({ root: state, overlay, introPlayer: player, hexonCoach: coach, introStartTimer: state.introStartTimer });
    function handler(name: string) {
      const expression = new RegExp(`^            function ${name}\\([^\\n]*\\) \\{[\\s\\S]*?^            \\}`, "m");
      const source = shell.match(expression)?.[0];
      assert.ok(source, name);
      return runInContext(`(${source})`, context);
    }
    return {
      overlay, coach, player,
      start: handler("onIntroPlaybackRequested"),
      cancel: handler("onIntroCancellationRequested"),
      pin: handler("onIntroHandoffRequested"),
      release: handler("onIntroReleaseRequested"),
      screenChanged: handler("onShouldShowChanged"),
    };
  });
  state.introPlaybackRequested = (generation: number) => screens.forEach((screen) => screen.start(generation));
  state.introCancellationRequested = (keep: boolean) => screens.forEach((screen) => screen.cancel(keep));
  state.introHandoffRequested = (generation: number) => screens.forEach((screen) => screen.pin(generation));
  state.introReleaseRequested = () => screens.forEach((screen) => screen.release());
  return { state, screens };
}

test("saved selection and first-run welcome wait for resolved pack readiness", () => {
  const state = runtime("tour-welcome");
  state.phase = "menu";
  state.lessonIndex = -1;
  state.characterStore.ready = false;
  state.loadSettings(JSON.stringify({ character: "owl", tourSeen: false }));
  assert.equal(state.requestedCharacter, "owl");
  assert.equal(state.characterName, "owl");
  assert.equal(state.tourSeen, false);
  state.startLesson(0);
  assert.equal(state.lessonIndex, -1);
  state.characterStore.ready = true;
  state.characterPacksReady();
  assert.equal(state.lessonIndex, -1);
  assert.equal(state.tourSeen, false);
  assert.equal(state.welcomeSeen, true);
  assert.equal(state.introActive, true);
  state.characterPacksReady();
  assert.equal(state.phase, "welcome");
});

test("welcome migrates prior use but not empty progress, regardless of load order", () => {
  for (const settingsFirst of [true, false]) {
    for (const prior of ["none", "tour", "completed", "steps", "bookmark"]) {
      const state = runtime("tour-welcome");
      state.phase = "menu";
      state.lessonIndex = -1;
      state.settingsResolved = false;
      state.progressResolved = false;
      let saved: any;
      state.settingsFile.setText = (text: string) => saved = JSON.parse(text);
      const settings = JSON.stringify({ character: "owl", tourSeen: prior === "tour" });
      const progress = JSON.stringify({
        schemaVersion: 2,
        courses: { "old-course": prior === "completed" ? ["old-lesson"] : [] },
        details: { "old-course": prior === "steps" ? { steps: { old: "skipped" } }
          : prior === "bookmark" ? { bookmarks: { lesson: "step" } } : {} },
      });
      if (settingsFirst) {
        state.loadSettings(settings);
        assert.equal(state.phase, "menu");
        state.loadProgress(progress);
      } else {
        state.loadProgress(progress);
        assert.equal(state.phase, "menu");
        state.loadSettings(settings);
      }
      assert.equal(state.phase, prior === "none" ? "welcome" : "menu", `${settingsFirst}/${prior}`);
      assert.equal(state.lessonIndex, -1);
      assert.equal(saved.welcomeSeen, true);
      state.finishWelcome();
      state.enterHome();
      assert.equal(state.phase, "menu");
      const returning = runtime("tour-welcome");
      returning.phase = "menu";
      returning.lessonIndex = -1;
      returning.loadSettings(JSON.stringify(saved));
      assert.equal(returning.phase, "menu");
    }
  }
});

test("first coach choice precedes entrance and confirmed reset replays after Done and choice", () => {
  const { state } = introRuntime();
  state.savedCharacter = "";
  state.welcomeSeen = false;
  state.loadSettings("{}");
  assert.equal(state.phase, "settings");
  assert.equal(state.introActive, false);
  state.chooseCharacter("owl");
  assert.equal(state.phase, "welcome");
  assert.equal(state.characterName, "owl");
  state.finishWelcome();
  state.openSettings("settings");
  let saved: any;
  state.settingsFile.setText = (text: string) => saved = JSON.parse(text);
  state.requestResetProgress();
  assert.equal(state.welcomeSeen, true);
  state.requestResetProgress();
  assert.equal(saved.welcomeSeen, false);
  assert.equal(saved.tourSeen, false);
  assert.equal(state.phase, "settings");
  state.closeSettings();
  assert.equal(state.settingsMode, "first-run");
  assert.equal(state.phase, "settings");
  state.chooseCharacter("custom-coach");
  assert.equal(state.phase, "welcome");
  assert.equal(state.characterName, "custom-coach");
  assert.equal(state.lessonIndex, -1);
});

test("confirmed reset clears completed tour results and credits across a saved reload", () => {
  for (const fromLesson of [false, true]) {
    const state = runtime("tour-welcome");
    const steps = Object.fromEntries(state.currentLesson.steps.map((step: { id: string }) => [step.id, "introduced"]));
    state.loadProgress(JSON.stringify({
      schemaVersion: 2,
      courses: { [state.course.id]: ["omarchy-tour"] },
      details: { [state.course.id]: { steps, credits: Object.fromEntries(Object.keys(steps).map(id => [id, true])),
        bookmarks: { "omarchy-tour": "tour-workspaces" } } },
    }));
    assert.equal(state.completedLessons["omarchy-tour"], true);
    if (!fromLesson) { state.lessonIndex = -1; state.phase = "menu"; }
    state.openSettings("settings");
    let savedProgress = "";
    let savedSettings = "";
    state.progressFile.setText = (text: string) => { savedProgress = text; };
    state.settingsFile.setText = (text: string) => { savedSettings = text; };
    state.requestResetProgress();
    assert.equal(state.resetConfirmPending, true);
    assert.equal(state.completedLessons["omarchy-tour"], true);
    assert.equal(savedProgress, "", "asking for confirmation must not erase progress");
    state.requestResetProgress();
    assert.equal(state.resetConfirmPending, false);
    assert.equal(Boolean(state.completedLessons["omarchy-tour"]), false);
    assert.equal(state.lessonIndex, -1);
    const restored = runtime("tour-welcome");
    restored.phase = "settings";
    restored.loadSettings(savedSettings);
    restored.loadProgress(savedProgress);
    assert.equal(restored.completedLessons["omarchy-tour"], false);
    assert.equal(Object.keys(restored.stepResults).length, 0);
    assert.equal(Object.keys(restored.stepCredits).length, 0);
    assert.equal(Object.keys(restored.lessonBookmarks).length, 0);
    assert.equal(restored.tourSeen, false);
    assert.equal(restored.welcomeSeen, false);
  }
});

test("reset stays cleared after choosing a coach, starting welcome, skipping and restarting", () => {
  const { state } = introRuntime();
  state.completedLessons = { welcome: true, "omarchy-tour": true };
  state.openSettings("settings");
  let savedProgress = "";
  let savedSettings = "";
  state.progressFile.setText = (text: string) => { savedProgress = text; };
  state.settingsFile.setText = (text: string) => { savedSettings = text; };
  state.requestResetProgress();
  state.requestResetProgress();
  state.closeSettings();
  state.chooseCharacter("owl");
  assert.equal(state.phase, "welcome");
  assert.equal(state.welcomeSeen, true, "startup welcome is not forced repeatedly");
  assert.equal(state.lessonCompleted(state.course.lessons[0]), false, "starting welcome is not completion");
  state.finishWelcome();
  assert.equal(state.lessonCompleted(state.course.lessons[0]), false, "skipping welcome is not completion");
  assert.equal(state.lessonCompleted(state.course.lessons[1]), false);
  for (const settingsFirst of [false, true]) {
    const restored = runtime("tour-welcome");
    restored.phase = "settings";
    if (settingsFirst) {
      restored.loadSettings(savedSettings);
      restored.loadProgress(savedProgress);
    } else {
      restored.loadProgress(savedProgress);
      restored.loadSettings(savedSettings);
    }
    assert.equal(restored.welcomeSeen, true);
    assert.equal(restored.lessonCompleted(restored.course.lessons[0]), false);
    assert.equal(restored.lessonFullyExplored(restored.course.lessons[0]), false);
    assert.equal(restored.lessonCompleted(restored.course.lessons[1]), false);
  }
  state.startLesson(0);
  state.welcomeStage = "recommendation";
  state.advanceWelcome(state.introGeneration, "recommendation");
  assert.equal(state.lessonCompleted(state.course.lessons[0]), true, "finishing welcome earns completion");
  assert.equal(state.lessonCompleted(state.course.lessons[1]), false, "welcome never completes the desktop tour");
  const restored = runtime("tour-welcome");
  restored.phase = "settings";
  restored.loadProgress(savedProgress);
  assert.equal(restored.lessonCompleted(restored.course.lessons[0]), true, "earned welcome completion persists");
});

test("an explicit reset flag overrides legacy use and a character override skips only the picker", () => {
  const state = runtime("tour-welcome");
  state.phase = "menu";
  state.lessonIndex = -1;
  state.characterOverride = "owl";
  state.progressByCourse = { other: ["completed-lesson"] };
  state.loadSettings(JSON.stringify({ tourSeen: true, welcomeSeen: false }));
  assert.equal(state.phase, "welcome");
  state.finishWelcome();
  state.openSettings("settings");
  state.requestResetProgress();
  state.requestResetProgress();
  state.closeSettings();
  assert.equal(state.phase, "welcome");
  assert.equal(state.welcomeStage, "scene");
});

test("reset reports success only after both state writes succeed and a failed save can be retried", () => {
  for (const kind of ["progress", "settings"]) {
    const state = runtime("tour-welcome");
    state.phase = "menu";
    state.lessonIndex = -1;
    state.settingsPath = "/isolated/settings.json";
    state.progressPath = "/isolated/progress.json";
    const file = kind === "progress" ? state.progressFile : state.settingsFile;
    file.setText = () => state.reportStateSaveFailure(kind, "synthetic write failure");
    state.openSettings("settings");
    state.requestResetProgress();
    state.requestResetProgress();
    assert.equal(state.resetJustDone, false);
    assert.equal(state.resetDoneTimer.running, false);
    assert.match(state[kind + "SaveError"], /could not be saved/);
    file.setText = () => { state[kind + "SaveError"] = ""; };
    state.requestResetProgress();
    state.requestResetProgress();
    assert.equal(state.resetJustDone, true);
    assert.equal(state.resetDoneTimer.running, true);
    assert.equal(state.progressSaveError, "");
    assert.equal(state.settingsSaveError, "");
  }
});

test("Ollie speaks exactly 10 percent faster while preserving the learner's speed and other coaches", async () => {
  const state = runtime("tour-welcome");
  for (const id of ["owl", "ohm-1", "owl"]) {
    state.characterStore.requestedId = id;
    state.characterStore.selectedPack.manifest = JSON.parse(
      await readFile(new URL(`../assets/characters/${id}/character.json`, import.meta.url), "utf8"));
    for (const speed of [0.75, 1, 1.25, 1.5]) {
      state.speechRate = speed;
      const command = state.timedSpeechCommand("/audio/clip.mp3");
      assert.equal(Number(command[command.indexOf("--speed") + 1]), speed * (id === "owl" ? 1.1 : 1));
      assert.equal(state.speechRate, speed);
      assert.equal(command[command.indexOf("--audio") + 1], "/audio/clip.mp3");
      assert.equal(Number(command[command.indexOf("--volume") + 1]), state.speechVolume);
    }
  }
});

test("welcome keyboard controls skip scenery, show lessons, or dismiss without starting a tour", () => {
  const { state } = introRuntime(true);
  Object.assign(state.Qt, { NoModifier: 0, Key_Return: 13, Key_Enter: 10, Key_Space: 32, Key_Escape: 27 });
  const press = (key: number) => {
    const event = { key, modifiers: 0, accepted: false };
    state.handleKeyPressed(event);
    assert.equal(event.accepted, true);
  };
  state.startIntro();
  press(13);
  state.flushCallbacks();
  assert.equal(state.welcomeStage, "center-flight");
  state.welcomeArrived(state.introGeneration);
  press(32);
  assert.equal(state.welcomeStage, "controls-flight");
  state.welcomeArrived(state.introGeneration);
  press(32);
  assert.equal(state.phase, "menu");
  assert.equal(state.lessonIndex, -1);
  state.startIntro();
  press(27);
  assert.equal(state.phase, "menu");
  assert.equal(state.welcomeStage, "");
  assert.equal(state.lessonIndex, -1);
});

test("arrival and reading handoffs reveal an unstarted menu and preserve free lesson choice", () => {
  const { state, screens } = introRuntime();
  state.selectedLessonIndex = 5;
  state.startIntro();
  state.beginIntroScene();
  screens[0].player.finish();
  state.flushCallbacks();
  assert.equal(state.welcomeReadTimer.running, false);
  state.welcomeArrived(state.introGeneration);
  assert.equal(state.welcomeStage, "welcome");
  assert.equal(state.welcomeReadTimer.running, false, "caption visibility starts the reading clock");
  state.welcomeCaptionShown();
  assert.ok(state.welcomeReadTimer.interval >= state.readingDuration(state.welcomeText));
  state.advanceWelcome(state.welcomeReadTimer.generation, state.welcomeReadTimer.stage);
  assert.equal(state.welcomeStage, "controls-flight");
  assert.equal(state.phase, "welcome");
  assert.equal(state.welcomeReadTimer.running, false);
  state.welcomeArrived(state.introGeneration);
  assert.equal(state.welcomeStage, "controls");
  assert.equal(state.characterState, "tour-point");
  state.welcomeCaptionShown();
  assert.match(state.welcomeText, /These are the Learn Omarchy controls: Settings, keyboard capture, mute narration, and Exit/);
  assert.match(state.welcomeText, /capture them again to continue with me/);
  state.advanceWelcome(state.welcomeReadTimer.generation, state.welcomeReadTimer.stage);
  assert.equal(state.phase, "menu");
  assert.equal(state.course.lessons[state.selectedLessonIndex].id, "omarchy-tour");
  assert.equal(state.lessonIndex, -1);
  assert.equal(state.welcomeStage, "menu-flight");
  state.welcomeArrived(state.introGeneration);
  assert.equal(state.welcomeStage, "recommendation");
  assert.equal(state.characterState, "menu-point");
  state.welcomeCaptionShown();
  state.advanceWelcome(state.welcomeReadTimer.generation, state.welcomeReadTimer.stage);
  assert.equal(state.welcomeStage, "");
  assert.equal(state.phase, "menu");
  assert.equal(state.lessonIndex, -1);
  assert.equal(state.audioProcess.running, false);
});

test("controls narration waits for arrival and rejects stale greeting completion", () => {
  const { state } = introRuntime();
  state.audioEnabled = true;
  state.startIntro();
  state.skipIntroScene();
  state.welcomeArrived(state.introGeneration);
  state.welcomeCaptionShown();
  assert.equal(state.welcomeSpeech.stage, "welcome");
  const generation = state.introGeneration;
  state.advanceWelcome(generation, "welcome");
  assert.equal(state.welcomeSpeech.running, false);
  assert.equal(state.welcomeStage, "controls-flight");
  state.welcomeSpeechExited(0, generation, "welcome");
  assert.equal(state.welcomeSpeech.running, false);
  state.welcomeArrived(generation);
  assert.equal(state.welcomeSpeech.running, false, "the caption, not just the state change, starts speech");
  state.welcomeCaptionShown();
  assert.equal(state.welcomeSpeech.stage, "controls");
  assert.match(state.welcomeSpeech.command.at(-1), /ohm-1\/host-controls\.mp3$/);
  state.welcomeSpeechExited(0, generation, "welcome");
  assert.equal(state.welcomeReadTimer.running, false);
  state.welcomeSpeech.running = false;
  state.welcomeSpeechExited(0, generation, "controls");
  assert.equal(state.welcomeReadTimer.stage, "controls");
  state.advanceWelcome(generation, "controls");
  assert.equal(state.welcomeStage, "menu-flight");
});

test("controls mute, skip, and settings do not leave welcome narration running", () => {
  for (const action of ["mute", "skip", "settings"]) {
    const { state } = introRuntime();
    state.audioEnabled = true;
    state.startIntro();
    state.skipIntroScene();
    state.welcomeArrived(state.introGeneration);
    state.advanceWelcome(state.introGeneration, "welcome");
    state.welcomeArrived(state.introGeneration);
    state.welcomeCaptionShown();
    assert.equal(state.welcomeSpeech.running, true);
    const generation = state.introGeneration;
    if (action === "mute") state.toggleAudio();
    else if (action === "skip") state.finishWelcome();
    else state.openSettings("settings");
    state.welcomeSpeechExited(0, generation, "controls");
    assert.equal(state.welcomeSpeech.running, false);
    if (action === "mute") {
      assert.equal(state.welcomeStage, "controls");
      assert.equal(state.welcomeReadTimer.stage, "controls");
      state.toggleAudio();
      assert.equal(state.welcomeSpeech.running, false, "unmuting must not replay the controls explanation");
    } else assert.equal(state.welcomeStage, "");
  }
});

test("welcome mute/unmute never replays or rewinds the current caption, including late speech exits", () => {
  for (const stage of ["welcome", "controls", "recommendation"]) {
    const state = runtime("tour-welcome", false);
    state.phase = stage === "recommendation" ? "menu" : "welcome";
    state.welcomeStage = stage;
    state.audioEnabled = true;
    state.welcomeCaptionShown();
    state.receiveWelcomePlayback(timingPacket(state.welcomeInstruction()), state.introGeneration, stage);
    state.receiveWelcomePlayback('{"type":"position","positionMs":1300}', state.introGeneration, stage);
    const revealed = state.welcomeRevealEnd;
    assert.ok(revealed > 0);
    const captionGeneration = state.welcomeSpeech.captionGeneration;
    state.toggleAudio();
    assert.equal(state.welcomeSpeech.running, false);
    assert.equal(state.welcomeReadingActive, true);
    assert.ok(state.welcomeRevealEnd >= revealed);
    state.welcomeReadingElapsed = 500;
    const afterReading = state.welcomeRevealEnd;
    const timerGeneration = state.welcomeReadTimer.generation;
    state.toggleAudio();
    assert.equal(state.audioEnabled, true);
    assert.equal(state.welcomeSpeech.running, false);
    assert.equal(state.welcomeSpeech.captionGeneration, captionGeneration);
    assert.ok(state.welcomeRevealEnd >= afterReading);
    state.welcomeSpeechExited(143, state.introGeneration, stage);
    state.welcomeCaptionShown();
    assert.equal(state.welcomeSpeech.running, false, "late cancellation cannot restart voice");
    assert.ok(state.welcomeRevealEnd >= afterReading);
    assert.equal(state.welcomeReadTimer.generation, timerGeneration);
    state.welcomeReadingElapsed = 1000;
    assert.ok(state.welcomeRevealEnd > afterReading, "reading continues even with audio enabled");
    if (stage !== "recommendation") {
      state.advanceWelcome(state.introGeneration, stage);
      state.welcomeArrived(state.introGeneration);
      state.welcomeCaptionShown();
      assert.equal(state.welcomeSpeech.running, true, "the next line uses the new audio preference");
    }
  }
});

test("unmuting a welcome line that began muted preserves its reading position", () => {
  const state = runtime("tour-welcome", false);
  state.phase = "welcome";
  state.welcomeStage = "controls";
  state.welcomeCaptionShown();
  state.welcomeReadingElapsed = 1500;
  const revealed = state.welcomeRevealEnd;
  state.toggleAudio();
  assert.equal(state.welcomeSpeech.running, false);
  assert.equal(state.welcomeReadingActive, true);
  assert.ok(state.welcomeRevealEnd >= revealed);
});

test("Ohm-1's approved greeting is character-specific and retains its spoken pause", () => {
  const state = runtime("tour-welcome");
  state.welcomeStage = "welcome";
  assert.match(state.welcomeText, /^Hi! I'm Ohm-1, but you can call me Ohm for short\./);
  state.characterStore.select("owl");
  assert.match(state.welcomeText, /^Hi! I'm OLLIE\. Welcome to Omarchy!/);
  assert.doesNotMatch(state.welcomeText, /Ohm/);
});

test("welcome copy explains the benefits and the menu follow-up avoids repeating them", () => {
  const { state } = introRuntime();
  state.characterStore.select("custom-coach");
  state.welcomeStage = "welcome";
  assert.match(state.welcomeText, /^Hi! I'm CUSTOM-COACH\. Welcome to Omarchy!/);
  assert.match(state.welcomeText, /Spend less time managing your desktop and operating system/);
  assert.match(state.welcomeText, /more time doing what matters/);
  assert.match(state.welcomeText, /I'll help you get started/);
  assert.ok(state.welcomeText.split(/\s+/).length <= 45);
  assert.doesNotMatch(state.welcomeText, /shortcuts|workspaces/);
  assert.match(state.welcomeText, /Your desktop - your way\. Let's jump in!$/);
  assert.doesNotMatch(state.welcomeText, /HEXON|OLLIE|Let's take a quick tour/);
  state.welcomeStage = "recommendation";
  assert.equal(state.welcomeText, "Ready to get started? Choose from one of the following lessons.");
  assert.doesNotMatch(state.welcomeText, /I'm|managing your desktop|try things yourself/);
  assert.equal(state.currentAudioPath(), "");
});

test("welcome word reveal uses matching timing and playback position, with safe full-text fallbacks", () => {
  const state = runtime("tour-welcome", false);
  state.phase = "welcome";
  state.welcomeStage = "welcome";
  state.audioEnabled = true;
  state.motionReduced = false;
  state.welcomeCaptionShown();
  const generation = state.introGeneration;
  const text = state.welcomeInstruction();
  const words = Array.from(text.matchAll(/\S+/g), (match: any, index) =>
    ({ startMs: 100 + index * 200, endOffset: match.index + match[0].length }));
  assert.equal(state.welcomeRevealEnd, 0, "don't flash full text while loading optional timing");
  state.receiveWelcomePlayback(JSON.stringify({ type: "timing", text, words }), generation, "welcome");
  assert.equal(state.welcomeRevealEnd, 0, "wait for actual playback before revealing words");
  state.receiveWelcomePlayback(JSON.stringify({ type: "position", positionMs: 0 }), generation, "welcome");
  assert.equal(state.welcomeRevealEnd, 0);
  state.receiveWelcomePlayback(JSON.stringify({ type: "position", positionMs: 100 }), generation, "welcome");
  assert.equal(state.welcomeRevealEnd, 3);
  state.synchronizedWelcomeText = false;
  assert.equal(state.welcomeRevealEnd, -1);
  state.synchronizedWelcomeText = true;
  state.reducedMotion = true;
  assert.equal(state.welcomeRevealEnd, -1);
  state.reducedMotion = false;
  state.toggleAudio();
  assert.ok(state.welcomeRevealEnd >= 3, "muting must not hide words already revealed");
  assert.equal(state.welcomeReadingActive, true);
  assert.equal(state.welcomeWordTimings.length, 0);
});

test("welcome text stays concealed until timing resolves, then fallback reveals at reading speed", () => {
  for (const stage of ["welcome", "controls", "recommendation"]) {
    const state = runtime("tour-welcome", false);
    state.phase = stage === "recommendation" ? "menu" : "welcome";
    state.welcomeStage = stage;
    state.audioEnabled = true;
    assert.equal(state.welcomeRevealEnd, 0, "even the frame before playback starts must not show the full text");
    state.welcomeCaptionShown();
    assert.equal(state.welcomeRevealEnd, 0);
    assert.equal(state.welcomeTimingDeadline.running, true);
    state.receiveWelcomePlayback(JSON.stringify({ type: "fallback", reason: "missing-timing" }),
      state.introGeneration, stage);
    assert.ok(state.welcomeRevealEnd >= 0 && state.welcomeRevealEnd < state.welcomeText.length);
    assert.equal(state.welcomeTimingDeadline.running, false);
    state.receiveWelcomePlayback(JSON.stringify({ type: "position", positionMs: 0 }), state.introGeneration, stage);
    assert.ok(state.welcomeRevealEnd >= 0, "late packets cannot clear the reading-speed fallback");
  }
});

test("timing timeout safely uses reading-speed reveal and does not interrupt audio", () => {
  const state = runtime("tour-welcome", false);
  state.phase = "welcome";
  state.welcomeStage = "welcome";
  state.audioEnabled = true;
  state.welcomeCaptionShown();
  state.welcomeReveal.fallback("timing deadline");
  assert.ok(state.welcomeRevealEnd >= 0 && state.welcomeRevealEnd < state.welcomeText.length);
  assert.equal(state.welcomeSpeech.running, true);
});

test("muted welcome reveals at reading speed without requiring voice timing", () => {
  const state = runtime("tour-welcome", false);
  state.phase = "welcome";
  state.welcomeStage = "welcome";
  state.welcomeCaptionShown();
  assert.equal(state.welcomeReadingActive, true);
  assert.equal(state.welcomeSpeech.running, false);
  assert.equal(state.welcomeRevealEnd, 3);
  state.welcomeReadingElapsed = 1000;
  assert.ok(state.welcomeRevealEnd > 3);
  state.welcomeReadingElapsed = state.readingDuration(state.welcomeText) - 50;
  assert.equal(state.welcomeRevealEnd, state.captionText(state.welcomeText).length);
  state.synchronizedWelcomeText = false;
  assert.equal(state.welcomeRevealEnd, -1);
  state.synchronizedWelcomeText = true;
  state.reducedMotion = true;
  assert.equal(state.welcomeRevealEnd, -1);
  state.advanceWelcome(state.introGeneration, "welcome");
  assert.equal(state.welcomeReadingActive, false);
  assert.equal(state.welcomeReadingElapsed, 0);
});

test("stale and mismatched welcome timing cannot hide a later caption", () => {
  const state = runtime("tour-welcome", false);
  state.phase = "welcome";
  state.welcomeStage = "controls";
  state.audioEnabled = true;
  state.motionReduced = false;
  state.welcomeCaptionShown();
  const generation = state.introGeneration;
  const timing = JSON.stringify({ type: "timing", text: "Wrong text.", words: [{ startMs: 0, endOffset: 11 }] });
  state.receiveWelcomePlayback(timing, generation - 1, "controls");
  assert.equal(state.welcomeTimingFailed, false);
  state.receiveWelcomePlayback(timing, generation, "welcome");
  assert.equal(state.welcomeTimingFailed, false);
  state.receiveWelcomePlayback(timing, generation, "controls");
  assert.equal(state.welcomeTimingFailed, true);
  assert.ok(state.welcomeRevealEnd >= 0 && state.welcomeRevealEnd < state.welcomeText.length);
  assert.equal(state.welcomeSpeech.running, true, "missing alignment must not silence the voice");
  state.stopWelcomeSpeech();
  assert.equal(state.welcomeWordTimings.length, 0);
});

test("the lesson-menu invitation is narrated after arrival and cancels when selecting a lesson", () => {
  const { state } = introRuntime();
  state.audioEnabled = true;
  state.phase = "menu";
  state.welcomeStage = "menu-flight";
  state.welcomeNarrationStarted = false;
  state.welcomeNarrationFinished = false;
  state.welcomeCaptionShown();
  assert.equal(state.welcomeSpeech.running, false);
  state.welcomeArrived(state.introGeneration);
  state.welcomeCaptionShown();
  assert.equal(state.welcomeSpeech.stage, "recommendation");
  assert.match(state.welcomeSpeech.command.at(-1), /host-lessons\.mp3$/);
  const generation = state.introGeneration;
  state.welcomeSpeechExited(0, generation, "controls");
  assert.equal(state.welcomeReadTimer.running, false);
  state.startLesson(1);
  state.welcomeSpeechExited(0, generation, "recommendation");
  assert.equal(state.welcomeStage, "");
  assert.equal(state.welcomeSpeech.running, false);
  assert.equal(state.phase, "waiting");
});

test("the startup splash defers the welcome and releases it only once", () => {
  const { state } = introRuntime();
  state.phase = "menu";
  state.welcomeSeen = false;
  state.welcomeSettingPresent = true;
  state.splashActive = true;
  assert.equal(state.maybeBeginWelcome(), false);
  assert.equal(state.introActive, false);
  state.finishSplash();
  assert.equal(state.splashActive, false);
  assert.equal(state.introActive, true);
  const generation = state.introGeneration;
  state.finishSplash();
  assert.equal(state.introGeneration, generation);
});
test("startup hands the lesson menu off once and waits for an intro's first frame", () => {
  for (const phase of ["menu", "settings", "welcome", "error"]) {
    const state = runtime("open-root-menu", false);
    state.splashActive = true;
    state.maybeBeginWelcome = () => {
      state.phase = phase;
      state.introActive = phase === "welcome";
    };
    let reveals = 0;
    state.startupFadeIn.restart = () => { reveals++; };
    state.finishSplash();
    const directMenu = phase === "menu";
    assert.equal(state.startupOpacity, directMenu ? 1 : 0);
    assert.equal(state.startupRevealPending, phase === "welcome");
    assert.equal(reveals, phase === "welcome" || directMenu ? 0 : 1);
    assert.equal(state.startupCoverRelease.running, directMenu);
    state.revealStartupScene();
    assert.equal(reveals, directMenu ? 0 : 1);
    state.startupOpacity = 0.4;
    state.revealStartupScene();
    state.finishSplash();
    assert.equal(reveals, directMenu ? 0 : 1);
    assert.equal(state.startupOpacity, 0.4);
  }
  assert.equal((shell.match(/contentItem\.opacity: root\.startupOpacity/g) || []).length, 2,
    "the UI and separately hosted coach/intro must reveal together");
  assert.match(shell, /visible: \(root\.splashActive \|\| root\.startupCoverHeld\) && overlay\.isFocusedScreen/);
  assert.match(shell, /id: startupFadeIn[\s\S]*?onFinished: startupCoverRelease\.restart\(\)/);
});
test("reduced-motion startup does not hide the destination or schedule a fade", () => {
  const state = runtime("open-root-menu", true);
  state.splashActive = true;
  state.maybeBeginWelcome = () => {};
  state.finishSplash();
  assert.equal(state.startupOpacity, 1);
  assert.equal(state.startupRevealPending, false);
  assert.equal(state.startupFadeIn.running, false);
  assert.equal(state.startupCoverRelease.running, true);
});
test("early lesson selection, Settings, coach changes and skip invalidate all welcome callbacks", () => {
  for (const stage of ["scene", "center-flight", "welcome", "menu-flight", "recommendation"]) {
    for (const action of ["lesson", "settings", "coach", "skip", "close"]) {
      const { state, screens } = introRuntime();
      state.startIntro();
      state.beginIntroScene();
      if (stage !== "scene") {
        screens[0].player.finish();
        state.flushCallbacks();
        if (stage !== "center-flight") state.welcomeArrived(state.introGeneration);
        if (stage === "menu-flight" || stage === "recommendation")
          state.advanceWelcome(state.introGeneration, "welcome");
        if (stage === "recommendation") state.welcomeArrived(state.introGeneration);
      }
      state.welcomeCaptionShown();
      const generation = state.introGeneration;
      if (action === "lesson") state.startLesson(1);
      else if (action === "settings") state.openSettings("settings");
      else if (action === "coach") state.applyCharacter("owl");
      else if (action === "skip") state.finishWelcome();
      else state.cancelIntro();
      const phase = state.phase;
      state.finishIntro(generation);
      state.welcomeArrived(generation);
      state.advanceWelcome(generation, stage);
      state.flushCallbacks();
      assert.equal(state.phase, phase, `${stage}/${action}`);
      assert.equal(state.welcomeStage, "");
      assert.equal(state.introActive, false);
      assert.equal(state.welcomeReadTimer.running, false);
      assert.equal(screens[0].player.running, false);
      assert.equal(screens[0].coach.userPlaced, false);
      if (action === "lesson") assert.equal(state.lessonIndex, 1);
    }
  }
});

test("missing saved selections show the fallback without silently rewriting settings", () => {
  const state = runtime("tour-welcome");
  state.phase = "menu";
  state.lessonIndex = -1;
  state.loadSettings(JSON.stringify({ character: "removed-coach", tourSeen: true }));
  assert.equal(state.characterName, "ohm-1");
  assert.equal(state.savedCharacter, "removed-coach");
  assert.equal(state.requestedCharacter, "removed-coach");
  assert.match(state.characterNotice, /removed-coach.*unavailable/);
  state.chooseCharacter("custom-coach");
  assert.equal(state.characterName, "custom-coach");
  assert.equal(state.savedCharacter, "custom-coach");
  state.chooseCharacter("invalid-pack");
  assert.equal(state.savedCharacter, "custom-coach");
});

test("an empty catalog opens useful settings and can be refreshed", () => {
  const state = runtime("tour-welcome");
  state.phase = "menu";
  state.lessonIndex = -1;
  state.characterStore.packs = [];
  state.characterPacksReady();
  assert.equal(state.phase, "settings");
  assert.match(state.characterNotice, /No valid character packs/);
  let refreshes = 0;
  state.characterStore.refresh = () => refreshes++;
  state.refreshCharacters();
  assert.equal(refreshes, 1);
  state.startLesson(0);
  assert.equal(state.phase, "settings");
  assert.equal(state.lessonIndex, -1);
  assert.match(shell, /label: "REFRESH COACHES"/);
});

test("only the active display plays an intro and completion hands off exactly once", () => {
  const { state, screens } = introRuntime();
  state.startIntro();
  state.beginIntroScene();
  state.beginIntroScene();
  assert.deepEqual(screens.map((screen) => screen.player.plays), [1, 0]);
  assert.equal(state.characterTourArrivalTimer.running, false);
  assert.equal(state.tourAdvanceTimer.running, false);
  const generation = state.introGeneration;
  screens[0].player.finish();
  screens[0].player.finish();
  state.finishIntro(generation);
  assert.equal(state.characterState, "tour-fly");
  assert.equal(screens[0].coach.userPlaced, true);
  assert.equal(screens[0].coach.userX, 320);
  assert.equal(screens[0].coach.userY, 640);
  assert.equal(state.characterTourArrivalTimer.running, false);
  state.flushCallbacks();
  assert.equal(screens[0].coach.userPlaced, false);
  assert.equal(state.characterTourArrivalTimer.running, false);
  assert.equal(state.introDeparting, true);
  assert.equal(state.tourAdvanceTimer.running, false);
  assert.equal(state.lessonIndex, -1);
  assert.equal(state.welcomeStage, "center-flight");
});

test("skip, failure and reduced motion keep the same welcome and narrate only after arrival", () => {
  for (const finish of ["skip", "failure", "reduced"] as const) {
    const { state, screens } = introRuntime(finish === "reduced");
    state.startIntro();
    state.beginIntroScene();
    assert.equal(screens[0].player.plays, 1);
    assert.equal(screens[0].player.reducedMotion, finish === "reduced");
    assert.equal(state.tourAdvanceTimer.running, false);
    if (finish === "skip") state.skipIntroScene();
    else if (finish === "failure") screens[0].player.fail("Missing optional intro asset");
    else screens[0].player.finish();
    state.flushCallbacks();
    assert.equal(state.lessonIndex, -1);
    assert.equal(state.introActive, false);
    assert.equal(state.characterTourArrivalTimer.running, false);
    assert.equal(state.tourAdvanceTimer.running, false);
    assert.equal(state.welcomeStage, "center-flight");
    if (finish === "failure") assert.match(state.introNotice, /Missing optional intro asset/);
    state.welcomeArrived(state.introGeneration);
    assert.equal(state.introDeparting, false);
    assert.equal(state.characterState, "tour-talk");
    assert.equal(state.welcomeStage, "welcome");
    assert.equal(state.tourAdvanceTimer.running, false);
  }
});

test("restart and explicit cancellation reject stale player and deferred handoff callbacks", () => {
  const { state, screens } = introRuntime();
  state.startIntro();
  state.beginIntroScene();
  const previous = state.introGeneration;
  screens[0].player.finish();
  state.startIntro();
  state.beginIntroScene();
  state.finishIntro(previous, "stale");
  state.flushCallbacks();
  assert.equal(state.introActive, true);
  assert.equal(state.characterTourArrivalTimer.running, false);
  assert.equal(state.introNotice, "");
  state.cancelIntro();
  state.finishIntro(state.introGeneration - 1);
  assert.equal(state.introActive, false);
  assert.equal(screens[0].player.running, false);
  assert.equal(screens[0].coach.userPlaced, false);
  assert.equal(state.tourAdvanceTimer.running, false);
});

test("first ascent keeps its gentle timing and defers narration despite audio controls", () => {
  const { state, screens } = introRuntime();
  state.startIntro();
  state.beginIntroScene();
  screens[0].player.finish();
  state.flushCallbacks();
  assert.equal(state.introActive, false);
  assert.equal(state.introDeparting, true);
  assert.equal(state.travelDurationForDistance(10, state.introDeparting), 1200);
  assert.equal(state.travelDurationForDistance(5000, state.introDeparting), 1900);
  state.beginTourNarration();
  state.toggleAudio();
  state.replayCurrentAudio();
  assert.equal(state.introDeparting, true);
  assert.equal(state.audioProcess.running, false);
  assert.equal(state.tourAdvanceTimer.running, false);
  state.toggleAudio();
  assert.equal(state.tourAdvanceTimer.running, false);
  state.welcomeArrived(state.introGeneration);
  assert.equal(state.introDeparting, false);
  assert.equal(state.tourAdvanceTimer.running, false);
  assert.equal(state.travelDurationForDistance(10, state.introDeparting), 420);
});

test("changing displays cancels the old intro and rejects its later completion", () => {
  const { state, screens } = introRuntime();
  state.startIntro();
  state.beginIntroScene();
  const generation = state.introGeneration;
  screens[0].overlay.shouldShow = false;
  screens[1].overlay.shouldShow = true;
  screens[0].screenChanged();
  state.flushCallbacks();
  assert.equal(state.introActive, false);
  assert.equal(screens[0].player.running, false);
  assert.equal(screens[1].player.plays, 0);
  assert.equal(state.characterTourArrivalTimer.running, false);
  state.finishIntro(generation);
  assert.equal(state.welcomeStage, "center-flight");
});

test("an initially unavailable focused display can claim the pending intro later", () => {
  const { state, screens } = introRuntime();
  screens[0].overlay.shouldShow = false;
  state.startIntro();
  state.beginIntroScene();
  assert.equal(state.introPlaybackStarted, false);
  assert.deepEqual(screens.map((screen) => screen.player.plays), [0, 0]);
  screens[1].overlay.shouldShow = true;
  screens[1].screenChanged();
  assert.equal(state.introPlaybackStarted, true);
  assert.deepEqual(screens.map((screen) => screen.player.plays), [0, 1]);
});

test("switching packs in paused settings keeps lesson progress and window ownership", () => {
  const { state, screens } = introRuntime();
  state.startLesson(state.course.lessons.findIndex((lesson: any) => lesson.id === "omarchy-tour"));
  const generation = state.introGeneration;
  state.tutorialWindows = ["0x123"];
  state.tutorialWindowsByStep = { "launch-terminal": "0x123" };
  state.stepResults = { "launch-terminal": "practiced" };
  state.openSettings("settings");
  state.audioProcess.running = true;
  state.audioPaused = true;
  state.audioProcessPath = state.currentAudioPath();
  state.chooseCharacter("custom-coach");
  state.finishIntro(generation);
  assert.equal(state.phase, "settings");
  assert.equal(state.settingsReturnToLesson, true);
  assert.equal(state.audioProcess.running, false);
  assert.equal(screens[0].player.running, false);
  assert.deepEqual(Array.from(state.tutorialWindows), ["0x123"]);
  assert.equal(state.tutorialWindowsByStep["launch-terminal"], "0x123");
  assert.equal(state.stepResults["launch-terminal"], "practiced");
  state.closeSettings();
  assert.equal(state.phase, "waiting");
  assert.equal(state.currentStep.id, "tour-welcome");
  assert.equal(state.characterName, "custom-coach");
});

test("refreshing an emptied catalog preserves a paused lesson's Settings return target", () => {
  const state = runtime("launch-terminal");
  state.openSettings("settings");
  const packs = state.characterStore.packs;
  state.characterStore.packs = [];
  state.characterPacksReady();
  assert.equal(state.phase, "settings");
  assert.equal(state.settingsReturnToLesson, true);
  state.closeSettings();
  assert.equal(state.phase, "settings");
  state.characterStore.packs = packs;
  state.characterPacksReady();
  state.closeSettings();
  assert.equal(state.phase, "waiting");
  assert.equal(state.currentStep.id, "launch-terminal");
});

test("narration policy suppresses borrowed name lines, disables Replay, and keeps fallback timing", () => {
  const state = runtime("tour-welcome");
  state.phase = "menu";
  state.chooseCharacter("custom-coach");
  state.phase = "waiting";
  state.audioEnabled = true;
  state.characterStore.selectedPack.manifest.narration = { mode: "borrowed", audioSet: "ohm-1" };
  state.currentStep.instruction = "Hi, I'm HEXON.";
  assert.match(state.currentStep.instruction, /HEXON/);
  assert.equal(state.currentAudioPath(), "");
  assert.match(state.characterText(state.currentStep.instruction), /CUSTOM-COACH/);
  state.beginTourNarration();
  assert.equal(state.tourAdvanceTimer.running, true);
  state.replayCurrentAudio();
  assert.equal(state.audioProcess.running, false);
  assert.equal(state.tourAdvanceTimer.running, true);
  state.characterStore.selectedPack.manifest.narration.mode = "silent";
  state.currentStep.completionAudio = "audio/result.mp3";
  assert.equal(state.completionAudioPath(), "");
  assert.match(shell, /visible: root\.phase === "waiting" && !root\.introActive && root\.currentAudioPath\(\) !== ""/);
});

test("center welcome has its own narration and waits for speech rather than reading time", () => {
  const state = runtime("tour-welcome");
  state.phase = "welcome";
  state.welcomeStage = "welcome";
  state.audioEnabled = true;
  state.welcomeCaptionShown();
  assert.equal(state.welcomeSpeech.running, true);
  assert.match(state.welcomeSpeech.command.at(-1), /audio\/ohm-1\/host-welcome\.mp3$/);
  assert.equal(state.welcomeReadTimer.running, false);
  state.welcomeSpeech.running = false;
  state.welcomeSpeechExited(0, state.introGeneration);
  assert.equal(state.welcomeReadTimer.running, true);
  assert.equal(state.welcomeReadTimer.interval, state.narrationRestMs);
});

test("cancelled welcome speech cannot advance a later scene and failure uses reading time", () => {
  const state = runtime("tour-welcome");
  state.phase = "welcome";
  state.welcomeStage = "welcome";
  state.audioEnabled = true;
  state.welcomeCaptionShown();
  const generation = state.introGeneration;
  state.cancelIntro();
  state.welcomeSpeechExited(0, generation);
  assert.equal(state.welcomeReadTimer.running, false);
  state.phase = "welcome";
  state.welcomeStage = "welcome";
  state.welcomeCaptionShown();
  state.welcomeSpeech.running = false;
  state.welcomeSpeechExited(1, state.introGeneration);
  assert.ok(state.welcomeReadTimer.interval >= state.readingDuration(state.welcomeText));
});

test("tour opening begins orientation without repeating the welcome", () => {
  const state = runtime("tour-welcome");
  assert.match(state.currentStep.instruction, /highlighted desktop bar/);
  assert.match(state.currentStep.instruction, /You'll use the Super key for many of Omarchy's keyboard shortcuts/);
  assert.doesNotMatch(state.currentStep.instruction, /Welcome|I'm|HEXON|Archie|OLLIE|learn by doing/);
  assert.doesNotMatch(shell, /SKIP SCENE/);
  assert.match(shell, /id: welcomeControls\s+visible: root\.phase === "welcome"/);
});

test("main rendering contains no coach-specific manifest paths or intro choreography", () => {
  assert.doesNotMatch(shell, /introKind|introStage|introAnchor|introScene|rocketArt|treeArt|intro-stand|intro-exit|intro-land|config\.prefix|characterFile|characterIndexFile/);
  assert.match(shell, /root\.characterConfig\.motion\.tourFlight === "upright"/);
  assert.match(shell, /characterConfig\.effects\.thrusters/);
  assert.match(shell, /modelData\.assetUrl \+ "\/" \+ characterCard\.previewSprite\.path/);
  const renderer = shell.match(/CharacterSprite \{([\s\S]*?)\n            \}/)?.[1];
  assert.ok(renderer);
  assert.match(renderer, /pack: root\.resolvedPack/);
  assert.doesNotMatch(renderer, /\b(?:assetRoot|config):/);
});

test("intro colors forward the current application theme", () => {
  const palette = shell.match(/introColors: \(\{([\s\S]*?)\}\)/)?.[1];
  assert.ok(palette);
  for (const color of ["accent", "instruction", "foreground", "background", "muted", "urgent"])
    assert.match(palette, new RegExp(`${color}: root\\.${color}`));
});

test("pack names preserve Unicode, markup and replacement characters literally", () => {
  const state = runtime("tour-welcome");
  const name = "<b>雪 $& café</b>";
  state.characterStore.selectedPack.manifest.displayName = name;
  assert.equal(state.characterText("Meet HEXON. HEXON can help."), `Meet ${name}. ${name} can help.`);
  for (const expression of [
    "button.label", "button.description", "characterCard.modelData.manifest.displayName",
    'characterCard.modelData.manifest.description || ""',
    "root.characterText(lessonCard.modelData.description)",
    'coachArt.errorMessage + "\\nOpen Settings to choose another coach."',
  ]) {
    const start = shell.indexOf(`text: ${expression}\n`);
    assert.notEqual(start, -1, expression);
    assert.match(shell.slice(start, shell.indexOf("\n", start + `text: ${expression}\n`.length)),
      /textFormat: Text\.PlainText/, expression);
  }
});

test("intro sounds accept only allowlisted cues from the active generation and respect preferences", () => {
  const state = runtime("tour-welcome", false);
  state.phase = "welcome";
  state.introActive = true;
  state.audioEnabled = true;
  state.playIntroSound("rocket-land.opus", state.introGeneration);
  assert.equal(state.sfxProcess.running, true);
  assert.deepEqual(Array.from(state.sfxProcess.command), [
    "mpv", "--no-video", "--really-quiet", "--volume=45", "--", "/app/assets/sounds/rocket-land.opus",
  ]);
  state.sfxProcess.running = false;
  for (const cue of ["../../other", "https://example.invalid/audio", "__proto__", "constructor", "unknown"])
    state.playIntroSound(cue, state.introGeneration);
  assert.equal(state.sfxProcess.running, false);
  state.playIntroSound("rocket-liftoff.opus", state.introGeneration - 1);
  assert.equal(state.sfxProcess.running, false);
  for (const [setting, value] of [
    ["audioEnabled", false], ["effectsEnabled", false], ["effectsVolume", 0], ["reducedMotion", true],
  ] as const) {
    const previous = state[setting];
    state[setting] = value;
    state.playIntroSound("rocket-liftoff.opus", state.introGeneration);
    assert.equal(state.sfxProcess.running, false, setting);
    state[setting] = previous;
  }
  state.playIntroSound("rocket-liftoff.opus", state.introGeneration);
  assert.equal(state.sfxProcess.running, true);
  assert.equal(state.sfxProcess.command.at(-1), "/app/assets/sounds/rocket-liftoff.opus");
  state.cancelIntro();
  assert.equal(state.sfxProcess.running, false);
});

test("welcome birds play quietly through the scene handoff but stop on cancellation", () => {
  const state = runtime("tour-welcome", false);
  state.phase = "welcome";
  state.welcomeStage = "scene";
  state.introActive = true;
  state.audioEnabled = true;
  state.effectsVolume = 75;
  state.playIntroSound("birds-welcome.opus", state.introGeneration);
  assert.equal(state.introAmbienceProcess.running, true);
  assert.equal(state.sfxProcess.running, false);
  assert.deepEqual(Array.from(state.introAmbienceProcess.command), [
    "mpv", "--no-video", "--really-quiet", "--volume=45.00", "--", "/app/assets/sounds/birds-welcome.opus",
  ]);
  state.finishIntro(state.introGeneration);
  assert.equal(state.welcomeStage, "center-flight");
  assert.equal(state.introAmbienceProcess.running, true, "the 3.7-second tree scene must not cut off the ten-second ambience");
  state.stopAudio();
  assert.equal(state.introAmbienceProcess.running, true, "narration lifecycle stays independent");
  state.finishWelcome();
  assert.equal(state.introAmbienceProcess.running, false);
});

test("welcome ambience rejects stale cues and respects effects, mute, and motion preferences", () => {
  const state = runtime("tour-welcome", false);
  state.phase = "welcome";
  state.introActive = true;
  state.audioEnabled = true;
  state.playIntroSound("birds-welcome.opus", state.introGeneration - 1);
  assert.equal(state.introAmbienceProcess.running, false);
  for (const [setting, value] of [
    ["audioEnabled", false], ["effectsEnabled", false], ["effectsVolume", 0], ["reducedMotion", true],
  ] as const) {
    const previous = state[setting];
    state[setting] = value;
    state.playIntroSound("birds-welcome.opus", state.introGeneration);
    assert.equal(state.introAmbienceProcess.running, false, setting);
    state[setting] = previous;
  }
  for (const [setting, value, handler] of [
    ["audioEnabled", false, "onAudioEnabledChanged"],
    ["effectsEnabled", false, "onEffectsEnabledChanged"],
    ["effectsVolume", 0, "onEffectsVolumeChanged"],
  ] as const) {
    const previous = state[setting];
    state.introAmbienceProcess.running = true;
    state[setting] = value;
    runInContext(shell.match(new RegExp("^  " + handler + ": (.*)$", "m"))![1], state);
    assert.equal(state.introAmbienceProcess.running, false, handler);
    state[setting] = previous;
  }
});

test("geometry status distinguishes working bar measurements from unavailable ones", () => {
  const state = runtime("tour-workspaces");
  state.geometryScreens = () => [];
  state.parseBarGeometry = () => true;
  state.finishBarGeometry(0, "{}", []);
  assert.match(state.integrationNotice, /Bar measurements are available/);
  state.parseBarGeometry = () => false;
  state.finishBarGeometry(0, "{}", []);
  assert.match(state.integrationNotice, /could not be measured/);
  state.finishBarGeometry(1, "", []);
  assert.match(state.integrationNotice, /could not be measured/);
  assert.equal(state.barGeometryAvailable, false);
});

test("geometry diagnostics stay in Settings and guidance follows only the affected lesson", () => {
  const noticePanel = shell.slice(shell.indexOf("id: packNoticePanel"), shell.indexOf("id: characterPanel"));
  assert.doesNotMatch(noticePanel, /integrationNotice/);
  assert.match(shell, /root\.settingsSaveError, root\.progressSaveError,[^\n]+root\.integrationNotice/);
  assert.match(shell, /objectName: "teachingGeometryNotice"[\s\S]*?text: root\.geometryGuidance\(overlay\.targetIsEstimated\)/);
  const state = runtime("tour-workspaces");
  state.integrationNotice = "Bar measurements are available.";
  state.barGeometryProcess.running = false;
  state.phase = "waiting";
  state.currentStep.highlight = { target: "workspace", workspaceId: 2 };
  assert.match(state.geometryGuidance(true), /workspace number/);
  assert.equal(state.geometryGuidance(false), "", "measured targets have no warning");
  state.barGeometryProcess.running = true;
  assert.match(state.geometryGuidance(true), /workspace number/,
    "existing guidance stays stable while measurements refresh");
  state.barGeometryProcess.running = false;
  for (const phase of ["menu", "arcade", "paused", "settings", "lesson-complete"]) {
    state.phase = phase;
    assert.equal(state.geometryGuidance(true), "", phase);
  }
  state.phase = "highlight";
  state.currentStep.highlight = { target: "panel" };
  assert.match(state.geometryGuidance(true), /named panel/);
  state.currentStep.highlight = { barWidgets: ["omarchy.clock"] };
  assert.match(state.geometryGuidance(true), /named item in the bar/);
  state.currentStep.highlight = { target: "window" };
  assert.equal(state.geometryGuidance(true), "");
  state.currentStep.highlight = null;
  assert.equal(state.geometryGuidance(true), "");
});

test("empty geometry cannot be promoted to working precise measurements", () => {
  const state = runtime("tour-workspaces");
  const screens = state.geometryScreens();
  for (const raw of [
    JSON.stringify({ version: 1, screens: [] }),
    JSON.stringify({ version: 1, screens: [{ ...screens[0], widgets: [] }] }),
    "[]", "not-json"
  ]) {
    state.barGeometryAvailable = true;
    assert.equal(state.parseBarGeometry(raw, screens), false);
    assert.equal(state.barGeometryAvailable, false);
    assert.equal(state.barGeometry.length, 0);
  }
});

test("layer-offset fallback promotes widget groups but not inferred workspace pills", () => {
  const state = runtime("tour-workspaces");
  const screens = state.geometryScreens();
  assert.equal(screens.length, 1);
  const output = { ...screens[0], widgets: [
    { id: "omarchy.workspaces", x: 40, y: 1170, width: 125, height: 30, visible: true, itemVisible: true },
  ] };
  state.parseBarGeometry(JSON.stringify({ version: 1, screens: [output] }), screens);
  assert.equal(state.barGeometry.length, 1);
  assert.equal(state.barGeometry[0].estimated, undefined);
  const group = state.barTargetGeometry({ barWidgets: ["omarchy.workspaces"] }, 0);
  assert.equal(group.estimated, undefined);
  const pill = state.barTargetGeometry({ target: "workspace", workspaceId: 2 }, 1);
  assert.equal(pill.estimated, true);
});

test("cleanup resolves owned targets and refuses a missing target", () => {
  const state = runtime("close-terminal");
  const commands: string[][] = [];
  state.Quickshell.execDetached = (command: string[]) => commands.push(command);
  state.currentStep.cleanup = ["example", "{tutorialWindow}"];
  state.rememberTutorialWindow("111", "launch-terminal");
  state.runCleanup();
  assert.equal(commands[0][1], "address:0x111");
  state.forgetTutorialWindow("111");
  state.runCleanup();
  assert.equal(commands.length, 1);
});

test("leaving a lesson closes only its verified owned windows through the Lua API", () => {
  const state = runtime("advanced-window-pop");
  const commands: string[][] = [];
  state.Quickshell.execDetached = (command: string[]) => commands.push(command);
  state.tutorialWindows = ["0x111", "not-an-address", "0x222"];
  state.closeOwnedTutorialWindows();
  assert.deepEqual(JSON.parse(JSON.stringify(commands)), [
    ["hyprctl", "eval", 'hl.dispatch(hl.dsp.window.close({ window = "address:0x111" }))'],
    ["hyprctl", "eval", 'hl.dispatch(hl.dsp.window.close({ window = "address:0x222" }))'],
  ]);
});

test("desktop panels complete and clean up only after this activity opens them", () => {
  const state = runtime("open-root-menu");
  const commands: string[][] = [];
  state.Quickshell.execDetached = (command: string[]) => commands.push(command);

  state.handleHyprlandEvent({ name: "openlayer", data: state.currentStep.completion.namespace });
  assert.equal(state.stepOwnsCleanupSurface, false);
  assert.equal(state.comboTriggered, false);
  state.runCleanup();
  assert.equal(commands.length, 0, "a pre-existing panel is never closed by Skip or navigation");

  state.shortcutArmedUntil = Date.now() + 1000;
  state.handleHyprlandEvent({ name: "openlayer", data: state.currentStep.completion.namespace });
  assert.equal(state.stepOwnsCleanupSurface, true);
  assert.equal(state.comboTriggered, true);
  state.runCleanup();
  assert.equal(commands.length, 1);
});

for (const stepId of [
  "upkeep-install", "upkeep-remove", "upkeep-defaults", "upkeep-updates", "upkeep-recovery",
]) {
  test(`menu inspection cleanup requires ownership: ${stepId}`, () => {
    for (const cleanup of ["runCleanup", "resetLessonRuntime"]) {
      const state = runtime(stepId);
      const commands: string[][] = [];
      state.Quickshell.execDetached = (command: string[]) => commands.push(command);

      assert.equal(state.stepOwnsCleanupSurface, false);
      state[cleanup]();
      assert.equal(commands.length, 0, `${cleanup} must preserve a pre-existing menu`);

      state.runStepAction("help");
      assert.equal(state.stepOwnsCleanupSurface, true);
      state[cleanup]();
      assert.deepEqual(JSON.parse(JSON.stringify(commands)), [
        ["omarchy", "menu", "close"],
      ], `${cleanup} must still close a menu opened by the activity`);
    }
  });
}

test("menu inspection completes only after the learner opens and closes the menu", () => {
  const actionState = runtime("upkeep-install");
  actionState.runStepAction("help");
  assert.equal(actionState.keyboardExclusive, false, "menu search must receive the learner's typing");
  assert.equal(actionState.stepOwnsCleanupSurface, true);
  assert.ok(actionState.layerCloseReadyAt > Date.now());

  const state = runtime("upkeep-install");
  const namespace = state.currentStep.completion.namespace;

  state.handleHyprlandEvent({ name: "openlayer", data: namespace });
  state.handleHyprlandEvent({ name: "closelayer", data: namespace });
  assert.equal(state.stepOwnsCleanupSurface, false);
  assert.equal(state.comboTriggered, false);

  state.shortcutArmedUntil = Date.now() + 1000;
  state.handleHyprlandEvent({ name: "openlayer", data: namespace });
  assert.equal(state.stepOwnsCleanupSurface, true);
  assert.equal(state.comboTriggered, false);

  state.handleHyprlandEvent({ name: "closelayer", data: namespace });
  assert.equal(state.layerCloseCompletionTimer.running, true);
  assert.equal(state.comboTriggered, false);
  state.shortcutArmedUntil = 0;
  state.handleHyprlandEvent({ name: "openlayer", data: namespace });
  assert.equal(state.layerCloseCompletionTimer.running, false, "a route remap isn't final closure");
  state.handleHyprlandEvent({ name: "closelayer", data: namespace });
  const { stepId } = state.layerCloseCompletionTimer;
  state.layerCloseReadyAt = Date.now() - 1;
  state.finishLayerCloseCheck(JSON.stringify({
    monitor: { levels: { "3": [{ namespace: "omarchy-menu" }] } },
  }), stepId, namespace);
  assert.equal(state.comboTriggered, false, "a mapped route remains open");
  state.finishLayerCloseCheck(JSON.stringify({ monitor: { levels: { "3": [] } } }), stepId, namespace);
  assert.equal(state.comboTriggered, true);
});

test("the delayed Apps launch notice is dismissed once rather than polled", () => {
  const timer = shell.slice(shell.indexOf("id: launchOsdTimer"), shell.indexOf("Item {", shell.indexOf("id: launchOsdTimer")));
  assert.match(timer, /interval:\s*2300/);
  assert.match(timer, /repeat:\s*false/);
  assert.doesNotMatch(timer, /launchOsdAttempts/);
});

test("bottom bars use a neutral coach pose rather than pointing sideways", () => {
  assert.match(shell, /readonly property bool canPointAtBar:\s*!barPosition \|\| barPosition\.edge !== "bottom"/);
  assert.match(shell, /root\.characterState === "tour-point"\) && canPointAtBar/);
});
