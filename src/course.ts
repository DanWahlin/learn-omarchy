export type HighlightShape = "rectangle" | "circle";
export type HighlightAnchor =
  | "top-left"
  | "top"
  | "top-right"
  | "left"
  | "center"
  | "right"
  | "bottom-left"
  | "bottom"
  | "bottom-right";

export interface Highlight {
  // Semantic targets use live geometry when available; the coordinates remain a fallback.
  target?: "window" | "workspace" | "panel";
  workspaceId?: number;
  barWidgets?: string[];
  shape: HighlightShape;
  anchor: HighlightAnchor;
  x: number;
  y: number;
  width: number;
  height: number;
  borderWidth: number;
  dynamic?: "workspaces";
  radius?: number;
  durationMs?: number;
}

export interface WindowState {
  floating?: boolean;
  fullscreen?: boolean;
  workspace?: number;
  focused?: boolean;
  specialWorkspace?: "scratchpad";
  specialVisible?: boolean;
  swapped?: true;
  resized?: true;
  splitChanged?: true;
}

export type Completion =
  | { type: "practice-result" }
  | {
      type: "hyprland-layer-open";
      namespace: string;
    }
  | {
      type: "action-success";
      delayMs?: number;
    }
  | {
      type: "hyprland-workspace-change";
    }
  | {
      type: "hyprland-window-activated";
      // Optional app ID regex, matched case-insensitively; authors supply anchors.
      appIdPattern?: string;
    }
  | {
      // Completes when the focused workspace has the given id. If the learner
      // is already there when the step starts, the step is skipped.
      type: "hyprland-workspace-is";
      id: number;
    }
  | {
      // Completes when Hyprland emits one of `events` (e.g. "closewindow",
      // "changefloatingmode") after the taught keys or Help were observed.
      // `dataPattern` is an optional regular expression the event payload
      // must match. `target: "tutorial-window"` additionally requires the
      // event to concern the window launched by the step's `windowFromStep`,
      // so a stray keypress can't complete a step on another window.
      type: "hyprland-event";
      events: string[];
      dataPattern?: string;
      target?: "tutorial-window";
      // Confirm against the owned client's state after an event, never after closewindow.
      windowState?: WindowState;
    }
  | {
      type: "narration-complete";
      delayMs?: number;
      durationMs?: number;
    };

export interface CommandAction {
  label: string;
  command: string[];
}

export interface CourseStep {
  id: string;
  windowSize?: { width: number; height: number };
  windowFromStep?: string;
  swapWithStep?: string;
  pairWithStep?: string;
  directionFromStep?: string;
  optional?: boolean;
  instruction: string;
  practicePrompt?: string;
  note?: string;
  detail?: string;
  kind?: "tour" | "practice";
  practice?: "app-search" | "clipboard" | "capture" | "screen-lock" | "compose" | "screen-recording" | "ocr" | "qr" | "dictation" | "web-app" | "transcode" | "sharing";
  pose?: "point" | "talk";
  keys: string[];
  actionLabel?: string;
  audio?: string | null;
  shortcuts?: { keys: string[]; action: string; caution?: string }[];
  help?: CommandAction;
  cleanup?: string[];
  completion: Completion;
  highlight: Highlight;
  completionMessage?: string;
  completionAudio?: string | null;
}

export interface LessonWrapUp {
  text: string;
  audio: string;
}

export interface ReferenceEntry {
  kind: "chord" | "sequence" | "gesture" | "workflow";
  keys: string[];
  action: string;
  caution?: string;
  stepIds: string[];
  sourceIds: string[];
}

export interface CourseReference {
  platform: string;
  version: string;
  verifiedOn: string;
  sources: ({ id: string; title: string } & (
    { url: string; path?: never } | { path: string; url?: never }
  ))[];
}

export interface CourseLesson {
  references?: ReferenceEntry[];
  mixedPractice?: boolean;
  wrapUp?: LessonWrapUp;
  kind?: "welcome";
  id: string;
  title: string;
  description: string;
  icon: string;
  estimatedMinutes: number;
  optional?: boolean;
  steps: CourseStep[];
}

export interface Course {
  reference?: CourseReference;
  wrapUp?: { assisted: LessonWrapUp; explored: LessonWrapUp };
  schemaVersion: 2;
  id: string;
  title: string;
  description: string;
  referenceViewport?: { width: number; height: number };
  lessons: CourseLesson[];
}

const anchors = new Set<HighlightAnchor>([
  "top-left",
  "top",
  "top-right",
  "left",
  "center",
  "right",
  "bottom-left",
  "bottom",
  "bottom-right",
]);

const namedKeyLabels = new Set([
  "SUPER",
  "ALT",
  "CTRL",
  "SHIFT",
  "SPACE",
  "RETURN",
  "TAB",
  "ESCAPE", "LEFT", "RIGHT", "UP", "DOWN", "MINUS", "EQUAL",
]);

const isSupportedKeyLabel = (value: string): boolean =>
  value === "+" || namedKeyLabels.has(value) || /^[A-Z0-9]$/.test(value);

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const addStringError = (
  errors: string[],
  value: unknown,
  path: string,
): value is string => {
  if (typeof value === "string" && value.trim().length > 0) return true;
  errors.push(`${path} must be a non-empty string`);
  return false;
};

const addPositiveNumberError = (
  errors: string[],
  value: unknown,
  path: string,
): value is number => {
  if (typeof value === "number" && Number.isFinite(value) && value > 0) return true;
  errors.push(`${path} must be a positive number`);
  return false;
};

const isCommand = (value: unknown): value is string[] =>
  Array.isArray(value) &&
  value.length > 0 &&
  value.every((part) => typeof part === "string" && part.length > 0);

const validateCommand = (
  errors: string[],
  value: unknown,
  path: string,
): void => {
  if (!isCommand(value)) {
    errors.push(`${path} must be a non-empty array of non-empty strings`);
  }
};

const validateRelativePath = (
  errors: string[],
  value: unknown,
  path: string,
): void => {
  if (value === undefined || value === null) return;
  if (!addStringError(errors, value, path)) return;
  if (value.startsWith("/") || value.split("/").includes("..")) {
    errors.push(`${path} must be a safe path relative to the course file`);
  }
};

const validateHighlight = (
  errors: string[],
  value: unknown,
  path: string,
): void => {
  if (!isRecord(value)) {
    errors.push(`${path} must be an object`);
    return;
  }

  if (value.shape !== "rectangle" && value.shape !== "circle") {
    errors.push(`${path}.shape must be "rectangle" or "circle"`);
  }
  if (typeof value.anchor !== "string" || !anchors.has(value.anchor as HighlightAnchor)) {
    errors.push(`${path}.anchor is not a supported screen anchor`);
  }
  for (const key of ["x", "y"] as const) {
    if (typeof value[key] !== "number" || !Number.isFinite(value[key])) {
      errors.push(`${path}.${key} must be a finite number`);
    }
  }
  for (const key of ["width", "height", "borderWidth"] as const) {
    addPositiveNumberError(errors, value[key], `${path}.${key}`);
  }
  if (value.dynamic !== undefined && value.dynamic !== "workspaces") {
    errors.push(`${path}.dynamic must be "workspaces" when present`);
  }
  if (value.barWidgets !== undefined &&
      (!Array.isArray(value.barWidgets) || value.barWidgets.length === 0 ||
        value.barWidgets.some((id) => typeof id !== "string" || !id.trim()))) {
    errors.push(`${path}.barWidgets must be a non-empty list of widget IDs`);
  }
  if (value.target !== undefined &&
      (typeof value.target !== "string" || !["window", "workspace", "panel"].includes(value.target))) {
    errors.push(`${path}.target must be "window", "workspace", or "panel" when present`);
  }
  if (value.workspaceId !== undefined) {
    if (value.target !== "workspace") {
      errors.push(`${path}.workspaceId requires target "workspace"`);
    }
    validateWorkspaceId(errors, value.workspaceId, `${path}.workspaceId`);
  }
  if (
    value.shape === "circle" &&
    typeof value.width === "number" &&
    typeof value.height === "number" &&
    value.width !== value.height
  ) {
    errors.push(`${path} must use equal width and height for a circle`);
  }
  if (
    value.radius !== undefined &&
    (typeof value.radius !== "number" || !Number.isFinite(value.radius) || value.radius < 0)
  ) {
    errors.push(`${path}.radius must be a non-negative number`);
  }
  if (value.durationMs !== undefined) {
    addPositiveNumberError(errors, value.durationMs, `${path}.durationMs`);
  }
};

const validateWorkspaceId = (errors: string[], value: unknown, path: string): void => {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 1 || value > 10) {
    errors.push(`${path} must be a workspace number from 1 to 10`);
  }
};

const validatePattern = (errors: string[], value: unknown, path: string): void => {
  if (!addStringError(errors, value, path)) return;
  try {
    new RegExp(value);
  } catch {
    errors.push(`${path} must be a valid regular expression`);
  }
};

const validateWindowState = (errors: string[], value: unknown, path: string): void => {
  if (!isRecord(value)) {
    errors.push(`${path} must be a non-empty object`);
    return;
  }
  if (Object.keys(value).length === 0) errors.push(`${path} must be a non-empty object`);
  for (const [key, state] of Object.entries(value)) {
    if (key === "workspace") {
      validateWorkspaceId(errors, state, `${path}.${key}`);
    } else if (key === "specialWorkspace") {
      if (state !== "scratchpad") errors.push(`${path}.specialWorkspace must be "scratchpad"`);
      if (value.workspace !== undefined) errors.push(`${path} cannot combine workspace and specialWorkspace`);
    } else if (key === "specialVisible") {
      if (typeof state !== "boolean") errors.push(`${path}.specialVisible must be a boolean`);
      if (value.specialWorkspace !== "scratchpad") errors.push(`${path}.specialVisible requires specialWorkspace`);
    } else if (["swapped", "resized", "splitChanged"].includes(key)) {
      if (state !== true) errors.push(`${path}.${key} must be true`);
    } else if (["floating", "fullscreen", "focused"].includes(key)) {
      if (typeof state !== "boolean") errors.push(`${path}.${key} must be a boolean`);
    } else {
      errors.push(`${path}.${key} is not a supported window state`);
    }
  }
};

const validateCompletion = (
  errors: string[],
  value: unknown,
  path: string,
): void => {
  if (!isRecord(value)) {
    errors.push(`${path} must be an object`);
    return;
  }
  if (value.type === "practice-result") return;
  if (value.windowState !== undefined && value.type !== "hyprland-event") {
    errors.push(`${path}.windowState is only valid for "hyprland-event"`);
  }
  if (value.appIdPattern !== undefined && value.type !== "hyprland-window-activated") {
    errors.push(`${path}.appIdPattern is only valid for "hyprland-window-activated"`);
  }
  if (value.type === "hyprland-layer-open") {
    addStringError(errors, value.namespace, `${path}.namespace`);
    return;
  }
  if (value.type === "action-success") {
    if (value.delayMs !== undefined) {
      addPositiveNumberError(errors, value.delayMs, `${path}.delayMs`);
    }
    return;
  }
  if (value.type === "hyprland-workspace-change") return;
  if (value.type === "hyprland-window-activated") {
    if (value.appIdPattern !== undefined) {
      validatePattern(errors, value.appIdPattern, `${path}.appIdPattern`);
    }
    return;
  }
  if (value.type === "hyprland-workspace-is") {
    validateWorkspaceId(errors, value.id, `${path}.id`);
    return;
  }
  if (value.type === "hyprland-event") {
    if (!Array.isArray(value.events) || value.events.length === 0 || !value.events.every((name) => typeof name === "string" && name.trim().length > 0)) {
      errors.push(`${path}.events must be a non-empty array of event names`);
    }
    if (value.target !== undefined && value.target !== "tutorial-window") {
      errors.push(`${path}.target must be "tutorial-window" when present`);
    }
    if (value.dataPattern !== undefined) {
      validatePattern(errors, value.dataPattern, `${path}.dataPattern`);
    }
    if (value.windowState !== undefined) {
      validateWindowState(errors, value.windowState, `${path}.windowState`);
      if (value.target !== "tutorial-window") {
        errors.push(`${path}.windowState requires target "tutorial-window"`);
      }
      if (Array.isArray(value.events) && value.events.includes("closewindow")) {
        errors.push(`${path}.windowState cannot be checked after "closewindow"`);
      }
    }
    return;
  }
  if (value.type === "narration-complete") {
    if (value.delayMs !== undefined) addPositiveNumberError(errors, value.delayMs, `${path}.delayMs`);
    if (value.durationMs !== undefined) addPositiveNumberError(errors, value.durationMs, `${path}.durationMs`);
    return;
  }
  errors.push(
    `${path}.type must be "hyprland-layer-open", "hyprland-window-activated", "hyprland-workspace-change", "hyprland-workspace-is", "hyprland-event", "narration-complete", or "action-success"`,
  );
};

const validateAction = (
  errors: string[],
  value: unknown,
  path: string,
): void => {
  if (!isRecord(value)) {
    errors.push(`${path} must be an object`);
    return;
  }
  addStringError(errors, value.label, `${path}.label`);
  validateCommand(errors, value.command, `${path}.command`);
};

const validateStep = (
  errors: string[],
  value: unknown,
  path: string,
  seenIds: Set<string>,
): void => {
  if (!isRecord(value)) {
    errors.push(`${path} must be an object`);
    return;
  }

  if (addStringError(errors, value.id, `${path}.id`)) {
    if (seenIds.has(value.id)) errors.push(`${path}.id "${value.id}" is duplicated`);
    seenIds.add(value.id);
  }
  addStringError(errors, value.instruction, `${path}.instruction`);
  if (value.practicePrompt !== undefined) {
    addStringError(errors, value.practicePrompt, `${path}.practicePrompt`);
    if (typeof value.practicePrompt === "string" &&
        (value.practicePrompt.length > 240 || /[\r\n]/.test(value.practicePrompt)))
      errors.push(`${path}.practicePrompt must be a single short paragraph (at most 240 characters)`);
  }
  if (value.windowSize !== undefined) {
    if (!isRecord(value.windowSize) ||
        !Number.isInteger(value.windowSize.width) || Number(value.windowSize.width) < 400 ||
        !Number.isInteger(value.windowSize.height) || Number(value.windowSize.height) < 250 ||
        Number(value.windowSize.width) > 4096 || Number(value.windowSize.height) > 4096) {
      errors.push(`${path}.windowSize must contain integer width (400-4096) and height (250-4096)`);
    }
    if (!isRecord(value.completion) || value.completion.type !== "hyprland-window-activated")
      errors.push(`${path}.windowSize requires a newly launched tutorial window`);
  }
  if (value.optional !== undefined && typeof value.optional !== "boolean") errors.push(`${path}.optional must be a boolean`);
  if (value.detail !== undefined) addStringError(errors, value.detail, `${path}.detail`);
  if (value.note !== undefined) {
    addStringError(errors, value.note, `${path}.note`);
    if (typeof value.note === "string" && (value.note.length > 140 || /[\r\n]/.test(value.note)))
      errors.push(`${path}.note must be a single short paragraph (at most 140 characters)`);
  }
  const usesTutorialWindow =
    (isRecord(value.completion) &&
      (value.completion.target === "tutorial-window" || value.completion.windowState !== undefined)) ||
    (isRecord(value.help) && isCommand(value.help.command) &&
      value.help.command.some((part) => part.includes("{tutorialWindow}"))) ||
    (isCommand(value.cleanup) && value.cleanup.some((part) => part.includes("{tutorialWindow}")));
  if (usesTutorialWindow || value.windowFromStep !== undefined) {
    addStringError(errors, value.windowFromStep, `${path}.windowFromStep`);
  }
  const isTour = value.kind === "tour";
  const isPractice = value.kind === "practice";
  if (value.kind !== undefined && !isTour && !isPractice) {
    errors.push(`${path}.kind must be "tour" or "practice" when present`);
  }
  validateRelativePath(errors, value.audio, `${path}.audio`);
  if (value.shortcuts !== undefined) {
    if (!Array.isArray(value.shortcuts) || value.shortcuts.length === 0) {
      errors.push(`${path}.shortcuts must be a non-empty array`);
    } else {
      value.shortcuts.forEach((shortcut, index) => {
        const shortcutPath = `${path}.shortcuts[${index}]`;
        if (!isRecord(shortcut)) { errors.push(`${shortcutPath} must be an object`); return; }
        if (!Array.isArray(shortcut.keys) || shortcut.keys.length === 0 ||
            shortcut.keys.some(key => typeof key !== "string" || !key.trim()))
          errors.push(`${shortcutPath}.keys must be non-empty labels`);
        addStringError(errors, shortcut.action, `${shortcutPath}.action`);
        if (shortcut.caution !== undefined) addStringError(errors, shortcut.caution, `${shortcutPath}.caution`);
      });
    }
  }
  validateRelativePath(errors, value.completionAudio, `${path}.completionAudio`);
  if (value.completionMessage !== undefined) {
    addStringError(errors, value.completionMessage, `${path}.completionMessage`);
  }
  if (typeof value.completionAudio === "string" && typeof value.completionMessage !== "string") {
    errors.push(`${path}.completionAudio requires a completionMessage to narrate`);
  }
  if (value.cleanup !== undefined) validateCommand(errors, value.cleanup, `${path}.cleanup`);
  validateCompletion(errors, value.completion, `${path}.completion`);
  validateHighlight(errors, value.highlight, `${path}.highlight`);
  if (value.practice !== undefined && !isPractice) errors.push(`${path}.practice requires kind "practice"`);
  if (isPractice) {
    if (typeof value.practice !== "string" || !["app-search", "clipboard", "capture", "screen-lock", "compose", "screen-recording", "ocr", "qr", "dictation", "web-app", "transcode", "sharing"].includes(value.practice)) errors.push(`${path}.practice is not supported`);
    if (!Array.isArray(value.keys) || value.keys.length !== 0) errors.push(`${path}.keys must be empty for practice`);
    addStringError(errors, value.actionLabel, `${path}.actionLabel`);
    if (value.help !== undefined || value.cleanup !== undefined || value.pose !== undefined || value.windowFromStep !== undefined || value.swapWithStep !== undefined || value.directionFromStep !== undefined || value.pairWithStep !== undefined) {
      errors.push(`${path}: practice cannot define help, cleanup, pose or window targets`);
    }
    if (!isRecord(value.completion) || value.completion.type !== "practice-result") errors.push(`${path}.completion must be practice-result`);
    else if (Object.keys(value.completion).some((key) => key !== "type")) errors.push(`${path}.completion may only define type for practice`);
    return;
  }
  if (isRecord(value.completion) && value.completion.type === "practice-result") errors.push(`${path}.completion requires kind "practice"`);
  const swapped = isRecord(value.completion) && isRecord(value.completion.windowState) && value.completion.windowState.swapped;
  const splitChanged = isRecord(value.completion) && isRecord(value.completion.windowState) && value.completion.windowState.splitChanged;
  if (value.pairWithStep !== undefined || splitChanged) {
    addStringError(errors, value.pairWithStep, `${path}.pairWithStep`);
    if (!splitChanged || !value.windowFromStep || value.pairWithStep === value.windowFromStep ||
        value.swapWithStep !== undefined || value.directionFromStep !== undefined)
      errors.push(`${path}.pairWithStep requires distinct owned windows and splitChanged verification`);
  }
  if (value.directionFromStep !== undefined) {
    addStringError(errors, value.directionFromStep, `${path}.directionFromStep`);
    if (value.swapWithStep !== undefined) errors.push(`${path}.directionFromStep cannot be combined with swapWithStep`);
    if (!value.windowFromStep || value.directionFromStep === value.windowFromStep ||
        !isRecord(value.completion) || value.completion.type !== "hyprland-event" ||
        !isRecord(value.completion.windowState) || value.completion.windowState.focused !== true) {
      errors.push(`${path}.directionFromStep requires distinct owned windows and focused verification`);
    }
  }
  if ((value.directionFromStep !== undefined || value.swapWithStep !== undefined) &&
      (!Array.isArray(value.keys) || value.keys.filter(key => ["LEFT", "RIGHT", "UP", "DOWN"].includes(key)).length !== 1)) {
    errors.push(`${path}.keys must contain one arrow for a directional activity`);
  }
  if (value.swapWithStep !== undefined || swapped) {
    addStringError(errors, value.swapWithStep, `${path}.swapWithStep`);
    if (!swapped || !value.windowFromStep || value.swapWithStep === value.windowFromStep) errors.push(`${path}.swapWithStep requires two distinct owned window references and swapped verification`);
  }
  if (isRecord(value.help) && isCommand(value.help.command) && value.help.command.some((part) => part.includes("{peerWindow}")) && !value.swapWithStep && !value.pairWithStep) {
    errors.push(`${path}.help.command requires swapWithStep or pairWithStep for {peerWindow}`);
  }
  if (!isTour && value.pose !== undefined) {
    errors.push(`${path}.pose is only valid for tour steps`);
  }
  if (isTour) {
    if (!Array.isArray(value.keys) || value.keys.length !== 0) {
      errors.push(`${path}.keys must be empty for tour steps`);
    }
    if (typeof value.audio !== "string") errors.push(`${path}.audio is required for tour steps`);
    if (value.pose !== undefined && value.pose !== "point" && value.pose !== "talk") {
      errors.push(`${path}.pose must be "point" or "talk"`);
    }
    if (value.help !== undefined) errors.push(`${path}.help is not allowed for tour steps`);
    if (value.actionLabel !== undefined) errors.push(`${path}.actionLabel is not allowed for tour steps`);
    if (!isRecord(value.completion) || value.completion.type !== "narration-complete") {
      errors.push(`${path}.completion.type must be "narration-complete" for tour steps`);
    }
    return;
  }
  if (!Array.isArray(value.keys) || !value.keys.every((key) => typeof key === "string" && key.trim().length > 0)) {
    errors.push(`${path}.keys must be an array of non-empty key labels`);
  } else {
    value.keys.forEach((key, keyIndex) => {
      if (key !== key.toUpperCase()) {
        errors.push(`${path}.keys[${keyIndex}] must use its canonical uppercase label`);
      } else if (!isSupportedKeyLabel(key)) {
        errors.push(`${path}.keys[${keyIndex}] "${key}" is not supported`);
      }
    });
    if (value.keys.length === 0) {
      addStringError(errors, value.actionLabel, `${path}.actionLabel`);
    }
  }
  if (value.actionLabel !== undefined) {
    addStringError(errors, value.actionLabel, `${path}.actionLabel`);
  }
  validateAction(errors, value.help, `${path}.help`);
  if (isRecord(value.completion) && value.completion.type === "narration-complete") {
    errors.push(`${path}.completion.type "narration-complete" is only valid for tour steps`);
  }
};

function validateWrapUp(errors: string[], value: unknown, path: string) {
  if (!isRecord(value)) {
    errors.push(`${path} must be an object`);
    return;
  }
  addStringError(errors, value.text, `${path}.text`);
  if (addStringError(errors, value.audio, `${path}.audio`))
    validateRelativePath(errors, value.audio, `${path}.audio`);
}

function validateReferenceMetadata(errors: string[], value: unknown): Set<string> {
  const ids = new Set<string>();
  const path = "course.reference";
  if (!isRecord(value)) {
    errors.push(`${path} must be an object`);
    return ids;
  }
  addStringError(errors, value.platform, `${path}.platform`);
  addStringError(errors, value.version, `${path}.version`);
  if (typeof value.verifiedOn !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value.verifiedOn) ||
      !Number.isFinite(Date.parse(value.verifiedOn)) ||
      new Date(value.verifiedOn).toISOString().slice(0, 10) !== value.verifiedOn)
    errors.push(`${path}.verifiedOn must be a valid YYYY-MM-DD date`);
  if (!Array.isArray(value.sources) || value.sources.length === 0) {
    errors.push(`${path}.sources must be a non-empty array`);
    return ids;
  }
  value.sources.forEach((source, index) => {
    const sourcePath = `${path}.sources[${index}]`;
    if (!isRecord(source)) { errors.push(`${sourcePath} must be an object`); return; }
    if (addStringError(errors, source.id, `${sourcePath}.id`)) {
      if (!/^[a-z0-9][a-z0-9-]*$/.test(source.id)) errors.push(`${sourcePath}.id must be a lowercase source identifier`);
      if (ids.has(source.id)) errors.push(`${sourcePath}.id "${source.id}" is duplicated`);
      ids.add(source.id);
    }
    addStringError(errors, source.title, `${sourcePath}.title`);
    if ((source.url !== undefined) === (source.path !== undefined))
      errors.push(`${sourcePath} must have exactly one HTTPS url or bundled path`);
    if (source.url !== undefined && addStringError(errors, source.url, `${sourcePath}.url`)) {
      const url = URL.canParse(source.url) ? new URL(source.url) : null;
      if (!url || url.protocol !== "https:" || url.username || url.password)
        errors.push(`${sourcePath}.url must be an HTTPS URL without credentials`);
    }
    if (source.path !== undefined && addStringError(errors, source.path, `${sourcePath}.path`) &&
        (/[:\\\u0000-\u001f]/.test(source.path) || source.path.split("/").some(part => !part || part === "." || part === "..")))
      errors.push(`${sourcePath}.path must be a safe path relative to the application directory`);
  });
  return ids;
}

function validateLessonReferences(errors: string[], lesson: Record<string, unknown>, path: string, sources: Set<string>) {
  if (!Array.isArray(lesson.references) || lesson.references.length === 0) {
    errors.push(`${path}.references must cover this lesson with a non-empty array`);
    return;
  }
  const steps = Array.isArray(lesson.steps) ? lesson.steps.filter(isRecord) : [];
  const ids = new Set(steps.map(step => step.id));
  const covered = new Set<string>();
  lesson.references.forEach((entry, index) => {
    const entryPath = `${path}.references[${index}]`;
    if (!isRecord(entry)) { errors.push(`${entryPath} must be an object`); return; }
    if (typeof entry.kind !== "string" || !["chord", "sequence", "gesture", "workflow"].includes(entry.kind))
      errors.push(`${entryPath}.kind must be chord, sequence, gesture, or workflow`);
    if (!Array.isArray(entry.keys) || entry.keys.length === 0 ||
        entry.keys.some(key => typeof key !== "string" || !key.trim()))
      errors.push(`${entryPath}.keys must be non-empty labels`);
    addStringError(errors, entry.action, `${entryPath}.action`);
    if (entry.caution !== undefined) addStringError(errors, entry.caution, `${entryPath}.caution`);
    if (!Array.isArray(entry.sourceIds) || entry.sourceIds.length === 0 ||
        entry.sourceIds.some(id => typeof id !== "string" || !sources.has(id)))
      errors.push(`${entryPath}.sourceIds must reference declared sources`);
    if (!Array.isArray(entry.stepIds) || (entry.stepIds.length === 0 && lesson.kind !== "welcome")) {
      errors.push(`${entryPath}.stepIds must cover activities in this lesson`);
    } else {
      const seen = new Set<string>();
      for (const id of entry.stepIds) {
        if (typeof id !== "string" || !ids.has(id)) {
          errors.push(`${entryPath}.stepIds contains an unknown activity`);
        } else {
          if (seen.has(id)) errors.push(`${entryPath}.stepIds repeats "${id}"`);
          seen.add(id);
          covered.add(id);
        }
      }
    }
  });
  for (const step of steps) {
    if (typeof step.id === "string" && !covered.has(step.id))
      errors.push(`${path}.references is missing activity "${step.id}"`);
    if (step.shortcuts !== undefined)
      errors.push(`${path}: use lesson.references instead of duplicating step.shortcuts in a versioned reference`);
  }
}

export function validateCourse(value: unknown): string[] {
  const errors: string[] = [];
  if (!isRecord(value)) return ["course must be an object"];

  if (value.schemaVersion !== 2) errors.push("course.schemaVersion must be 2");
  if (value.wrapUp !== undefined) {
    if (!isRecord(value.wrapUp)) errors.push("course.wrapUp must be an object");
    else {
      validateWrapUp(errors, value.wrapUp.assisted, "course.wrapUp.assisted");
      validateWrapUp(errors, value.wrapUp.explored, "course.wrapUp.explored");
    }
  }
  addStringError(errors, value.id, "course.id");
  addStringError(errors, value.title, "course.title");
  addStringError(errors, value.description, "course.description");
  if (value.referenceViewport !== undefined) {
    if (!isRecord(value.referenceViewport)) {
      errors.push("course.referenceViewport must be an object");
    } else {
      addPositiveNumberError(errors, value.referenceViewport.width, "course.referenceViewport.width");
      addPositiveNumberError(errors, value.referenceViewport.height, "course.referenceViewport.height");
    }
  }

  if (!Array.isArray(value.lessons) || value.lessons.length === 0) {
    errors.push("course.lessons must be a non-empty array");
    return errors;
  }

  const seenLessonIds = new Set<string>();
  const seenStepIds = new Set<string>();
  const referenceSources = value.reference === undefined ? undefined : validateReferenceMetadata(errors, value.reference);
  value.lessons.forEach((lesson, lessonIndex) => {
    const path = `course.lessons[${lessonIndex}]`;
    if (!isRecord(lesson)) {
      errors.push(`${path} must be an object`);
      return;
    }
    if (addStringError(errors, lesson.id, `${path}.id`)) {
      if (seenLessonIds.has(lesson.id)) errors.push(`${path}.id "${lesson.id}" is duplicated`);
      seenLessonIds.add(lesson.id);
    }
    addStringError(errors, lesson.title, `${path}.title`);
    addStringError(errors, lesson.description, `${path}.description`);
    if (lesson.wrapUp !== undefined) validateWrapUp(errors, lesson.wrapUp, `${path}.wrapUp`);
    if (lesson.kind !== undefined && lesson.kind !== "welcome") errors.push(`${path}.kind must be welcome when provided`);
    if (lesson.optional !== undefined && typeof lesson.optional !== "boolean") errors.push(`${path}.optional must be a boolean`);
    if (lesson.mixedPractice !== undefined && typeof lesson.mixedPractice !== "boolean") errors.push(`${path}.mixedPractice must be a boolean`);
    addStringError(errors, lesson.icon, `${path}.icon`);
    addPositiveNumberError(errors, lesson.estimatedMinutes, `${path}.estimatedMinutes`);
    if (referenceSources) validateLessonReferences(errors, lesson, path, referenceSources);
    else if (lesson.references !== undefined) errors.push(`${path}.references requires course.reference metadata`);
    if (lesson.kind === "welcome") {
      if (!Array.isArray(lesson.steps) || lesson.steps.length !== 0) errors.push(`${path}.steps must be empty for a welcome lesson`);
      if (lessonIndex !== 0) errors.push(`${path}: the welcome lesson must be first`);
      return;
    }
    if (!Array.isArray(lesson.steps) || lesson.steps.length === 0) {
      errors.push(`${path}.steps must be a non-empty array`);
      return;
    }
    const launchSteps = new Set<string>();
    lesson.steps.forEach((step, stepIndex) => {
      const stepPath = `${path}.steps[${stepIndex}]`;
      validateStep(errors, step, stepPath, seenStepIds);
      if (!isRecord(step)) return;
      if (typeof step.windowFromStep === "string" && !launchSteps.has(step.windowFromStep)) {
        errors.push(`${stepPath}.windowFromStep must reference an earlier window-launch step in the same lesson`);
      }
      if (typeof step.swapWithStep === "string" && !launchSteps.has(step.swapWithStep)) {
        errors.push(`${stepPath}.swapWithStep must reference an earlier window-launch step in the same lesson`);
      }
      if (typeof step.pairWithStep === "string" && !launchSteps.has(step.pairWithStep)) {
        errors.push(`${stepPath}.pairWithStep must reference an earlier window-launch step in the same lesson`);
      }
      if (typeof step.directionFromStep === "string" && !launchSteps.has(step.directionFromStep)) {
        errors.push(`${stepPath}.directionFromStep must reference an earlier window-launch step in the same lesson`);
      }
      if (typeof step.id === "string" && isRecord(step.completion) &&
          step.completion.type === "hyprland-window-activated") {
        launchSteps.add(step.id);
      }
    });
  });

  return errors;
}

export function parseCourseJson(json: string): {
  course?: Course;
  errors: string[];
} {
  let value: unknown;
  try {
    value = JSON.parse(json);
  } catch (error) {
    return {
      errors: [
        `course contains invalid JSON: ${error instanceof Error ? error.message : String(error)}`,
      ],
    };
  }

  const errors = validateCourse(value);
  return errors.length === 0 ? { course: value as Course, errors } : { errors };
}
