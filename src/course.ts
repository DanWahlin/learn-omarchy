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
  radius?: number;
  durationMs?: number;
}

export interface LayerOpenCompletion {
  type: "hyprland-layer-open";
  namespace: string;
}

export interface CourseStep {
  id: string;
  instruction: string;
  keys: string[];
  audio?: string | null;
  help?: {
    label: string;
    command: string[];
  };
  completion: LayerOpenCompletion;
  highlight: Highlight;
  completionMessage?: string;
}

export interface CourseLesson {
  id: string;
  title: string;
  steps: CourseStep[];
}

export interface Course {
  schemaVersion: 1;
  id: string;
  title: string;
  description?: string;
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
  if (typeof value === "number" && Number.isFinite(value) && value > 0) {
    return true;
  }
  errors.push(`${path} must be a positive number`);
  return false;
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
  if (value.type !== "hyprland-layer-open") {
    errors.push(`${path}.type must be "hyprland-layer-open"`);
  }
  addStringError(errors, value.namespace, `${path}.namespace`);
};

const validateHelp = (
  errors: string[],
  value: unknown,
  path: string,
): void => {
  if (value === undefined) return;
  if (!isRecord(value)) {
    errors.push(`${path} must be an object`);
    return;
  }
  addStringError(errors, value.label, `${path}.label`);
  if (
    !Array.isArray(value.command) ||
    value.command.length === 0 ||
    !value.command.every((part) => typeof part === "string" && part.length > 0)
  ) {
    errors.push(`${path}.command must be a non-empty array of non-empty strings`);
  }
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
  if (
    !Array.isArray(value.keys) ||
    value.keys.length === 0 ||
    !value.keys.every((key) => typeof key === "string" && key.trim().length > 0)
  ) {
    errors.push(`${path}.keys must be a non-empty array of key labels`);
  }
  validateRelativePath(errors, value.audio, `${path}.audio`);
  validateHelp(errors, value.help, `${path}.help`);
  validateCompletion(errors, value.completion, `${path}.completion`);
  validateHighlight(errors, value.highlight, `${path}.highlight`);
  if (value.completionMessage !== undefined) {
    addStringError(errors, value.completionMessage, `${path}.completionMessage`);
  }
};

export function validateCourse(value: unknown): string[] {
  const errors: string[] = [];
  if (!isRecord(value)) return ["course must be an object"];

  if (value.schemaVersion !== 1) errors.push("course.schemaVersion must be 1");
  addStringError(errors, value.id, "course.id");
  addStringError(errors, value.title, "course.title");
  if (value.description !== undefined) {
    addStringError(errors, value.description, "course.description");
  }

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
      if (seenLessonIds.has(lesson.id)) {
        errors.push(`${path}.id "${lesson.id}" is duplicated`);
      }
      seenLessonIds.add(lesson.id);
    }
    addStringError(errors, lesson.title, `${path}.title`);
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
  return errors.length === 0
    ? { course: value as Course, errors }
    : { errors };
}
