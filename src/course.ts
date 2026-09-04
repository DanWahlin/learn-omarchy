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

export type Completion =
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
  instruction: string;
  detail?: string;
  kind?: "tour";
  pose?: "point" | "talk";
  keys: string[];
  actionLabel?: string;
  audio?: string | null;
  help?: CommandAction;
  cleanup?: string[];
  completion: Completion;
  highlight: Highlight;
  completionMessage?: string;
  completionAudio?: string | null;
}

export interface CourseLesson {
  id: string;
  title: string;
  description: string;
  icon: string;
  estimatedMinutes: number;
  steps: CourseStep[];
}

export interface Course {
  schemaVersion: 2;
  id: string;
  title: string;
  description: string;
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
  "ESCAPE",
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

const validateCompletion = (
  errors: string[],
  value: unknown,
  path: string,
): void => {
  if (!isRecord(value)) {
    errors.push(`${path} must be an object`);
    return;
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
  if (value.type === "hyprland-window-activated") return;
  if (value.type === "narration-complete") {
    if (value.delayMs !== undefined) addPositiveNumberError(errors, value.delayMs, `${path}.delayMs`);
    if (value.durationMs !== undefined) addPositiveNumberError(errors, value.durationMs, `${path}.durationMs`);
    return;
  }
  errors.push(
    `${path}.type must be "hyprland-layer-open", "hyprland-window-activated", "hyprland-workspace-change", "narration-complete", or "action-success"`,
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
  if (value.detail !== undefined) addStringError(errors, value.detail, `${path}.detail`);
  const isTour = value.kind === "tour";
  if (value.kind !== undefined && !isTour) {
    errors.push(`${path}.kind must be "tour" when present`);
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
    validateRelativePath(errors, value.audio, `${path}.audio`);
    if (value.cleanup !== undefined) validateCommand(errors, value.cleanup, `${path}.cleanup`);
    validateCompletion(errors, value.completion, `${path}.completion`);
    validateHighlight(errors, value.highlight, `${path}.highlight`);
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
  validateRelativePath(errors, value.audio, `${path}.audio`);
  validateAction(errors, value.help, `${path}.help`);
  if (value.cleanup !== undefined) validateCommand(errors, value.cleanup, `${path}.cleanup`);
  validateCompletion(errors, value.completion, `${path}.completion`);
  if (isRecord(value.completion) && value.completion.type === "narration-complete") {
    errors.push(`${path}.completion.type "narration-complete" is only valid for tour steps`);
  }
  validateHighlight(errors, value.highlight, `${path}.highlight`);
  if (value.completionMessage !== undefined) {
    addStringError(errors, value.completionMessage, `${path}.completionMessage`);
  }
  validateRelativePath(errors, value.completionAudio, `${path}.completionAudio`);
  if (typeof value.completionAudio === "string" && typeof value.completionMessage !== "string") {
    errors.push(`${path}.completionAudio requires a completionMessage to narrate`);
  }
};

export function validateCourse(value: unknown): string[] {
  const errors: string[] = [];
  if (!isRecord(value)) return ["course must be an object"];

  if (value.schemaVersion !== 2) errors.push("course.schemaVersion must be 2");
  addStringError(errors, value.id, "course.id");
  addStringError(errors, value.title, "course.title");
  addStringError(errors, value.description, "course.description");

  if (!Array.isArray(value.lessons) || value.lessons.length === 0) {
    errors.push("course.lessons must be a non-empty array");
    return errors;
  }

  const seenLessonIds = new Set<string>();
  const seenStepIds = new Set<string>();
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
    addStringError(errors, lesson.icon, `${path}.icon`);
    addPositiveNumberError(errors, lesson.estimatedMinutes, `${path}.estimatedMinutes`);
    if (!Array.isArray(lesson.steps) || lesson.steps.length === 0) {
      errors.push(`${path}.steps must be a non-empty array`);
      return;
    }
    lesson.steps.forEach((step, stepIndex) =>
      validateStep(errors, step, `${path}.steps[${stepIndex}]`, seenStepIds),
    );
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
