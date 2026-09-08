import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { createContext, runInContext } from "node:vm";
import type { Course } from "../src/course.ts";

const shell = await readFile(new URL("../app/shell.qml", import.meta.url), "utf8");
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

// Execute the runtime's JavaScript, with compositor, process and timer effects
// replaced by inert objects so regression tests never touch the user's desktop.
function runtime(stepId: string, reducedMotion = true) {
  const lessonIndex = course.lessons.findIndex((lesson) =>
    lesson.steps.some((step) => step.id === stepId),
  );
  assert.notEqual(lessonIndex, -1);
  const context = createContext({
    course: structuredClone(course),
    courseDir: "/course",
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
    welcomeNarration: JSON.parse(welcomeSource),
    welcomeNarrationStarted: false,
    welcomeNarrationFinished: false,
    welcomeSpeechStopping: false,
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
    settingsFile: { setText() {} },
    progressFile: { setText() {} },
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
    keyboardExclusive: true,
    keyboardCaptureResetting: false,
    shortcutInhibitionActive: false,
    restoreKeyboardAfterAction: false,
    exerciseRunning: false,
    exerciseRestoreCapture: false,
    swapBefore: null,
    directionalKey: "",
    appRoot: "/app",
    barGeometry: [],
    barGeometryAvailable: true,
    barGeometryTopology: "",
    geometryProviderAvailable: true,
    geometryProviderRetryAt: 0,
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
    windowOwnershipStopping: false,
    windowOwnershipProcess: { running: false, requestGeneration: -1, requestToken: "", command: [] },
    pausedCompletionPending: false,
    characterCue: 0,
    audioProcess: { running: false, processId: 123, signal() {} },
    sfxProcess: { running: false },
    outcomeProcess: { running: false },
    layerGeometryProcess: { running: false },
    helpProcess: { running: false, command: [] },
    practiceProcess: { running: false, command: [], requestGeneration: -1 },
    swapPreflightProcess: { running: false, requestGeneration: -1 },
    directionPreviewProcess: { running: false, requestGeneration: -1 },
    clientGeometryProcess: { running: false },
    monitorGeometryProcess: { running: false },
    stepStartWindowProcess: { running: false },
    lessonTransitionAnimation: timer(),
    Quickshell: { execDetached() {}, screens: [{ name: "eDP-1", x: 0, y: 0, width: 1920, height: 1200 }] },
    Hyprland: { focusedMonitor: null },
    console: { info() {}, warn() {}, error() {} },
    Qt: { callLater() {}, rgba: (r: number, g: number, b: number, a: number) => ({ r, g, b, a }) },
  });
  Object.defineProperties(context, {
    currentLesson: { get: () => context.course.lessons[context.lessonIndex] },
    currentStep: { get: () => context.currentLesson?.steps[context.stepIndex] },
    currentStepIsTour: { get: () => context.currentStep?.kind === "tour" },
    currentStepIsPractice: { get: () => context.currentStep?.kind === "practice" },
    currentStepNeedsDirection: { get: () => Boolean(context.currentStep?.directionFromStep || context.currentStep?.swapWithStep) },
    currentStepKeys: { get: () => (context.currentStep?.keys || []).map((key: string) =>
      context.currentStepNeedsDirection && context.directionalKey && ["LEFT", "RIGHT", "UP", "DOWN"].includes(key) ? context.directionalKey : key) },
    currentStepClosesWindow: { get: () => context.currentStep?.completion?.events?.includes("closewindow") ?? false },
    currentStepHasNoVisibleTarget: { get: () => context.currentStepClosesWindow || context.currentStepIsPractice ||
      Boolean(context.currentStep?.completion?.windowState?.specialWorkspace) },
    narrationEnabled: { get: () => context.audioEnabled && context.speechEnabled && context.speechVolume > 0 },
    characterName: { get: () => context.characterStore.selectedPack?.id || "" },
    characterIndex: { get: () => context.characterStore.packs },
    characterNotice: { get: () => context.characterStore.notice },
    characterDisplayName: { get: () => context.characterStore.selectedPack?.manifest.displayName || "Coach" },
    welcomeText: { get: () => runInContext(
      shell.match(/readonly property string welcomeText: ([\s\S]*?)\n  property bool introActive/)![1], context) },
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
  context.captureWorkspaceStart = () => {};
  context.productionStartCharacterStep = context.startCharacterStep;
  context.startCharacterStep = () => {};
  context.currentWorkspaceId = () => 1;
  return context;
}

function client(address: string) {
  return { address, pid: 1234, at: [10, 20], size: [500, 300], mapped: true, hidden: false };
}

function confirmWindowOwnership(state: ReturnType<typeof runtime>, exitCode = 0) {
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
  assert.deepEqual(Array.from(state.practiceProcess.command), ["/app/bin/learn-omarchy-practice", "clipboard"]);
  state.finishPracticeExercise(0, state.actionGeneration,
    'LEARN_PRACTICE_RESULT:{"mode":"clipboard","completed":true}\n');
  assert.equal(state.keyboardExclusive, true);
  assert.equal(state.exerciseRunning, false);
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

test("leaving an exercise cancels its process and rejects a stale success", () => {
  const state = exerciseRuntime();
  state.runStepAction("action");
  const generation = state.actionGeneration;
  state.cancelAction();
  assert.equal(state.practiceProcess.running, false);
  assert.equal(state.keyboardExclusive, true);
  state.finishPracticeExercise(0, generation, 'LEARN_PRACTICE_RESULT:{"mode":"clipboard","completed":true}');
  assert.equal(state.stepResults["launch-terminal"], undefined);
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
  const launches: string[][] = [];
  state.Quickshell.execDetached = (command: string[]) => launches.push(command);
  state.runStepAction("help");
  assert.equal(launches[0][0], "env");
  assert.equal(launches[0][1], `LEARN_OMARCHY_WINDOW_TOKEN=${state.windowLaunchToken}`);
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

test("finale verifies and closes the terminal and browser independently", () => {
  const state = runtime("finale-close-terminal");
  state.rememberTutorialWindow("111", "finale-terminal");
  state.rememberTutorialWindow("222", "finale-browser");
  state.runStepAction("help");
  assert.match(state.helpProcess.command[2], /address:0x111/);
  state.handleHyprlandEvent({ name: "closewindow", data: "111" });
  assert.equal(state.layerCompletionFeedbackTimer.running, true);
  assert.equal(state.tutorialWindowsByStep["finale-terminal"], undefined);
  assert.equal(state.tutorialWindowsByStep["finale-browser"], "0x222");
  state.helpProcess.running = false;
  state.stepIndex += 2;
  state.startCurrentStep();
  state.runStepAction("shortcut");
  assert.match(state.helpProcess.command[2], /address:0x222/);
  state.handleHyprlandEvent({ name: "closewindow", data: "222" });
  assert.equal(state.layerCompletionFeedbackTimer.running, true);
  assert.equal(state.tutorialWindows.length, 0);
});

test("closing another tutorial window doesn't complete the current activity", () => {
  const state = runtime("finale-close-terminal");
  state.rememberTutorialWindow("111", "finale-terminal");
  state.rememberTutorialWindow("222", "finale-browser");
  state.armHelpDetection();
  state.handleHyprlandEvent({ name: "closewindow", data: "222" });
  assert.equal(state.layerCompletionFeedbackTimer.running, false);
  assert.equal(state.currentTutorialWindow(), "0x111");
});

test("missing targets never fall back to another tracked or reused window", () => {
  const state = runtime("finale-close-terminal");
  state.rememberTutorialWindow("111", "finale-terminal");
  state.rememberTutorialWindow("222", "finale-browser");
  state.forgetTutorialWindow("111");
  state.rememberTutorialWindow("111", "another-launch");
  state.runStepAction("help");
  assert.equal(state.helpProcess.running, false);
  assert.equal(state.currentTutorialWindow(), "");
  state.armHelpDetection();
  state.handleHyprlandEvent({ name: "closewindow", data: "111" });
  assert.equal(state.layerCompletionFeedbackTimer.running, false);
});

test("resetting a lesson clears both window ownership indexes", () => {
  const state = runtime("finale-close-terminal");
  state.rememberTutorialWindow("111", "finale-terminal");
  state.resetLessonRuntime();
  assert.equal(state.tutorialWindows.length, 0);
  assert.equal(Object.keys(state.tutorialWindowsByStep).length, 0);
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

test("Welcome lesson replays the selected coach without clearing existing progress", () => {
  for (const character of ["ohm-1", "owl"]) {
    const { state, screens } = introRuntime();
    state.characterStore.select(character);
    state.welcomeSeen = true;
    state.stepResults = { "tour-workspaces": "introduced", "launch-terminal": "practiced" };
    state.stepCredits = { "tour-workspaces": true, "launch-terminal": true };
    state.completedLessons = { "everyday-apps": true };
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
    assert.equal(state.windowGeometryRefreshTimer.running, true);
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

test("the coach follows every reliable highlighted panel target, including measured menu widgets", () => {
  const estimated = shell.match(/readonly property bool targetIsEstimated: ([\s\S]*?)\n        readonly property bool hasReliableCompletionTarget/)?.[1];
  const reliable = shell.match(/readonly property bool hasReliableCompletionTarget: ([\s\S]*?)\n        readonly property real fittedHighlightWidth/)?.[1];
  const follows = shell.match(/readonly property bool targetsCompletion:\s*([\s\S]*?)\n          readonly property bool targetsTour/)?.[1];
  assert.ok(estimated && reliable && follows);
  for (const [target, windowMeasured, widgetMeasured, expected] of [
    ["panel", false, true, true],
    ["panel", true, false, true],
    ["panel", false, false, false],
    ["window", true, false, true],
    ["window", false, true, false],
    ["workspace", false, true, true],
  ] as const) {
    for (const state of ["target-fly", "target-settle", "target-point"]) {
      const context = createContext({
        root: { currentStepHasNoVisibleTarget: false, characterState: state },
        highlight: { target },
        usesWindowTarget: windowMeasured,
        measuredBarTarget: widgetMeasured ? { x: 100, y: 20, width: 40, height: 30 } : null,
        targetIsEstimated: false,
        overlay: { highlight: { target }, usesWindowTarget: windowMeasured, hasReliableCompletionTarget: false },
      });
      context.targetIsEstimated = runInContext(estimated, context);
      context.overlay.hasReliableCompletionTarget = runInContext(reliable, context);
      assert.equal(runInContext(follows, context), expected, `${target}: ${state}, window=${windowMeasured}, widget=${widgetMeasured}`);
      context.root.currentStepHasNoVisibleTarget = true;
      context.overlay.hasReliableCompletionTarget = runInContext(reliable, context);
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
  const state = runtime("finale-close-terminal");
  state.startCurrentStep();
  assert.equal(state.recoveryStepId, "finale-terminal");
  assert.match(state.recoveryMessage, /isn't available/);
  assert.match(shell, /text: root\.recoveryMessage/);
  state.recoverTutorialWindow();
  assert.equal(state.currentStep.id, "finale-terminal");
  assert.equal(state.helpProcess.running, false);
  state.rememberTutorialWindow("111", "finale-terminal");
  state.phase = "highlight";
  state.advance();
  assert.equal(state.currentStep.id, "finale-close-terminal");
  assert.equal(state.currentTutorialWindow(), "0x111");
});

test("pause suspends narration and settings preserves the lesson position", () => {
  const state = runtime("open-root-menu");
  const signals: number[] = [];
  state.audioEnabled = true;
  state.audioProcess.running = true;
  state.audioProcessPath = state.currentAudioPath();
  state.audioProcess.signal = (signal: number) => signals.push(signal);
  state.openSettings("settings");
  assert.equal(state.phase, "settings");
  assert.equal(state.settingsReturnToLesson, true);
  assert.equal(state.audioProcess.running, true);
  assert.deepEqual(signals, [19]);
  state.closeSettings();
  assert.equal(state.phase, "waiting");
  assert.equal(state.currentStep.id, "open-root-menu");
  assert.deepEqual(signals, [19, 18]);
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
  const state = runtime("finale-close-terminal");
  const client = { mapped: true, hidden: false, floating: true, fullscreen: 2, workspace: { id: 2 }, focusHistoryID: 0 };
  state.currentWorkspaceId = () => 2;
  assert.equal(state.matchesWindowState(client, { workspace: 2, focused: true }), true);
  assert.equal(state.matchesWindowState(client, { workspace: 1 }), false);
  assert.equal(state.matchesWindowState(client, { floating: false }), false);
  assert.equal(state.matchesWindowState(client, { floating: true, fullscreen: true }), true);
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

test("measured bar geometry distinguishes the workspace group from individual numbers", () => {
  const state = runtime("tour-workspaces");
  state.Hyprland = { workspaces: { values: [{ id: 6 }] } };
  state.parseBarGeometry(JSON.stringify([
    { id: "omarchy.menu", x: 9, y: 0, width: 32, height: 30, visible: true, itemVisible: true },
    { id: "omarchy.workspaces", x: 41, y: 0, width: 145, height: 30, visible: true, itemVisible: true },
  ]));
  const group = state.barTargetGeometry(state.currentStep.highlight, 0);
  assert.deepEqual(JSON.parse(JSON.stringify(group)), { x: 9, y: 0, width: 177, height: 30, estimated: true });
  const workspace = state.barTargetGeometry({ target: "workspace" }, 1);
  assert.equal(workspace.x, 41 + 145 / 6);
  assert.ok(Math.abs(workspace.width - 145 / 6) < 0.000001);
  assert.equal(workspace.estimated, true);
  assert.ok(workspace.x > 41, "workspace two must not highlight the menu icon or workspace one");
  state.Quickshell.screens.push({});
  assert.equal(state.barTargetGeometry(state.currentStep.highlight, 0), null);
});

test("the menu-opening result targets only its center card, while the following stop targets the icon", () => {
  const state = runtime("tour-omarchy-menu");
  const screen = state.geometryScreens()[0];
  const widgets = [{ id: "omarchy.menu", x: 9, y: 0, width: 32, height: 30, visible: true, itemVisible: true }];
  const update = () => assert.equal(state.parseProviderGeometry(
    JSON.stringify({ version: 1, screens: [{ ...screen, widgets }] }), state.geometryScreens()), true);
  update();
  assert.equal(state.barTargetGeometry(state.currentStep.highlight, 0), null);
  widgets.push({ id: "panel:omarchy-menu", x: 785, y: 248, width: 350, height: 705, visible: true, itemVisible: true });
  update();
  assert.deepEqual(JSON.parse(JSON.stringify(state.barTargetGeometry(state.currentStep.highlight, 0))),
    { x: 785, y: 248, width: 350, height: 705, panel: true });
  const icon = state.currentLesson.steps.find((step: any) => step.id === "tour-menu-icon");
  assert.equal(state.barTargetGeometry(icon.highlight, 0).x, 9);
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
  assert.equal(state.parseProviderGeometry(JSON.stringify(snapshot), outputs), true);
  const external = state.Quickshell.screens[1];
  const internal = state.Quickshell.screens[0];
  assert.equal(state.barTargetGeometry(state.currentStep.highlight, 0, internal).x, 800);
  assert.equal(state.barTargetGeometry(state.currentStep.highlight, 0, external).x, 1200);
  assert.equal(state.barTargetGeometry(state.currentStep.highlight, 0), null);
  assert.equal(state.barTargetGeometry(state.currentStep.highlight, 0, external, 960, 600).x, 600);
});

test("exact workspace cells don't assume uniform spacing or count", () => {
  const state = runtime("workspaces-home");
  const screens = state.geometryScreens();
  state.parseProviderGeometry(JSON.stringify({ version: 1, screens: [{
    ...screens[0], widgets: [
      { id: "omarchy.workspaces", x: 40, y: 5, width: 300, height: 30, visible: true, itemVisible: true },
      { id: "workspace.2", workspaceId: 2, x: 110, y: 6, width: 35, height: 27, visible: true, itemVisible: true },
    ],
  }] }), screens);
  const target = state.barTargetGeometry({ target: "workspace", workspaceId: 2 }, 1);
  assert.deepEqual(JSON.parse(JSON.stringify(target)), { x: 110, y: 6, width: 35, height: 27 });
});

test("bar caches and in-flight results are rejected after output resize or topology change", () => {
  const state = runtime("tour-clock");
  const screens = state.geometryScreens();
  const raw = JSON.stringify([{ id: "omarchy.clock", x: 800, y: 0, width: 100, height: 30, visible: true, itemVisible: true }]);
  state.parseBarGeometry(raw, screens);
  assert.ok(state.barTargetGeometry(state.currentStep.highlight, 0));
  state.Quickshell.screens[0].width = 1280;
  assert.equal(state.barTargetGeometry(state.currentStep.highlight, 0), null);
  state.finishBarGeometry(0, raw, screens, false);
  assert.equal(state.barTargetGeometry(state.currentStep.highlight, 0), null);
  state.parseBarGeometry(raw, state.geometryScreens());
  assert.ok(state.barTargetGeometry(state.currentStep.highlight, 0));
  state.Quickshell.screens.push({ name: "DP-1", width: 1920, height: 1080, x: 1280, y: 0 });
  assert.equal(state.barTargetGeometry(state.currentStep.highlight, 0, state.Quickshell.screens[0]), null);
  state.parseBarGeometry(raw, state.geometryScreens());
  assert.equal(state.barGeometry.length, 0);
});

test("an unavailable provider falls back without guessing a multi-monitor association", () => {
  const state = runtime("tour-clock");
  state.finishBarGeometry(1, "", state.geometryScreens(), true);
  assert.equal(state.geometryProviderAvailable, false);
  state.requestBarGeometry();
  assert.deepEqual(Array.from(state.barGeometryProcess.command), ["omarchy-shell", "shell", "debugBarGeometry"]);
  state.barGeometryProcess.running = false;
  state.Quickshell.screens.push({ name: "DP-1", x: 1920, y: 0, width: 1920, height: 1200 });
  state.requestBarGeometry();
  assert.equal(state.barGeometryProcess.running, false);
  state.geometryProviderRetryAt = 0;
  state.requestBarGeometry();
  assert.deepEqual(Array.from(state.barGeometryProcess.command), ["omarchy-shell", "learnGeometry", "snapshot"]);
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
  state.windowGeometryRefreshTimer.refreshing = true;
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

test("detected layer results explain keyboard ownership without releasing or repeating instructions", () => {
  const state = runtime("calendar-panel");
  assert.equal(state.openedToolKeyboardHint(), "");
  state.phase = "highlight";
  assert.equal(state.openedToolKeyboardHint(), "Use Release Keys to interact with the opened tool.");
  assert.equal(state.keyboardExclusive, true);
  state.keyboardExclusive = false;
  assert.equal(state.openedToolKeyboardHint(), "");
  state.keyboardExclusive = true;
  state.currentStep.completionMessage = "Choose Release Keys before typing or browsing here.";
  assert.equal(state.openedToolKeyboardHint(), "");
  state.currentStep.completionMessage = "After releasing the keys, select an entry.";
  assert.equal(state.openedToolKeyboardHint(), "");
  state.currentStep.completionMessage = "Done.";
  state.currentStep.completion.type = "hyprland-event";
  assert.equal(state.openedToolKeyboardHint(), "");
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

test("Ohm-1's approved greeting is character-specific and retains its spoken pause", () => {
  const state = runtime("tour-welcome");
  state.welcomeStage = "welcome";
  assert.match(state.welcomeText, /^Hi! I'm Ohm-1, but you can call me Ohm for short\./);
  state.characterStore.select("owl");
  assert.match(state.welcomeText, /^Hi! I'm OLLIE\. Welcome to Omarchy\./);
  assert.doesNotMatch(state.welcomeText, /Ohm/);
});

test("welcome copy explains the benefits and the menu follow-up avoids repeating them", () => {
  const { state } = introRuntime();
  state.characterStore.select("custom-coach");
  state.welcomeStage = "welcome";
  assert.match(state.welcomeText, /^Hi! I'm CUSTOM-COACH\. Welcome to Omarchy\./);
  assert.match(state.welcomeText, /You'll learn by doing/);
  assert.match(state.welcomeText, /Find what works for you\. Your desktop\. Your way\.$/);
  assert.doesNotMatch(state.welcomeText, /HEXON|OLLIE|Let's take a quick tour/);
  state.welcomeStage = "recommendation";
  assert.match(state.welcomeText, /The Omarchy tour is a good starting point/);
  assert.match(state.welcomeText, /there's no required order/);
  assert.doesNotMatch(state.welcomeText, /I'm|shortcuts can change|learn by doing/);
  assert.equal(state.currentAudioPath(), "");
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
  assert.match(state.currentStep.instruction, /Super is the Windows key/);
  assert.doesNotMatch(state.currentStep.instruction, /Welcome|I'm|HEXON|Archie|OLLIE|learn by doing/);
  assert.doesNotMatch(shell, /SKIP SCENE/);
  assert.match(shell, /id: welcomeControls\s+visible: root\.phase === "welcome" && root\.welcomeStage === "welcome"/);
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

test("intro palette forwards the current application theme", () => {
  const palette = shell.match(/palette: \(\{([\s\S]*?)\}\)/)?.[1];
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
    "button.label", 'button.description === button.label ? button.label : button.label + "\\n" + button.description', "characterCard.modelData.manifest.displayName",
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
