import { constants } from "node:fs";
import { lstat, open, opendir, realpath, stat } from "node:fs/promises";
import { homedir } from "node:os";
import { isAbsolute, join, relative, resolve, sep } from "node:path";
import { pathToFileURL } from "node:url";
import { inflateSync } from "node:zlib";
import { introAssetPaths, validateIntroSequence } from "./intro-sequence.ts";

export const PACK_LIMITS = {
  manifestBytes: 256 * 1024, sequenceBytes: 64 * 1024,
  imageBytes: 16 * 1024 * 1024, imageSide: 16384, imagePixels: 32 * 1024 * 1024,
  packPixels: 32 * 1024 * 1024,
  runtimeFiles: 64, runtimeBytes: 128 * 1024 * 1024, catalogEntries: 512,
  userPacks: 64, packEntries: 256, outputBytes: 8 * 1024 * 1024,
} as const;
const ID = /^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$/;
const ROLES = ["idle", "talk", "point", "point-up", "flight", "point-blink", "point-up-blink", "speech"];
const CRC_TABLE = Uint32Array.from({ length: 256 }, (_, byte) => {
  let crc = byte;
  for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
  return crc >>> 0;
});

export function defaultUserPackRoot(env: Record<string, string | undefined> = process.env): string {
  const home = env.HOME && isAbsolute(env.HOME) ? env.HOME : homedir();
  const dataRoot = env.XDG_DATA_HOME && isAbsolute(env.XDG_DATA_HOME)
    ? env.XDG_DATA_HOME : join(home, ".local", "share");
  return join(dataRoot, "learn-omarchy", "characters");
}

type Point = { x: number; y: number };
type Box = Point & { width: number; height: number };
export type Sprite = {
  path: string; frameWidth: number; frameHeight: number; frames: number;
  fps?: number; timeline?: { frame: number; durationMs: number }[];
};
export type Pose = {
  frameWidth: number; scale: number; offset: Point; baseline?: number; bodyAnchorX?: number;
  tip?: Point; flameSockets?: Point[];
  speech?: { sprite?: string; frameWidth?: number; restFrame?: number; source: Box; destination: Box };
};
export type CharacterManifest = {
  formatVersion: 1; id: string; displayName: string; spokenName?: string; description: string;
  author: { name: string | null; status: "declared" | "unresolved"; note?: string };
  license: { status: "declared" | "unresolved"; identifier?: string; note?: string };
  preview: { sprite: "idle"; frame: 0 };
  sprites: Record<string, Sprite>;
  renderer: { canvas: { width: 224; height: 192 }; baseline: number; bodyAnchorX: number;
    registrationNote?: string; poses: Record<string, Pose> };
  effects: { thrusters: boolean };
  motion: { tourFlight: "upright" | "sprite" };
  blink?: { periodMs: number; startMs: number; durationMs: number };
  intro?: { sequence: string };
  narration: { mode: "own"; audioSet: string; playbackRate?: number; voices?: { azure?: string; edge?: string } }
    | { mode: "borrowed"; audioSet: "ohm-1" | "owl" } | { mode: "silent" };
};
export type ResolvedPack = {
  id: string; root: string; assetUrl: string; manifest: CharacterManifest;
  intro: unknown | null; runtimeFiles: string[]; diagnostics: string[];
};
export type CharacterCatalog = {
  version: 1; packs: ResolvedPack[]; diagnostics: string[]; fallbackId: string | null;
  invalidBundledIds: string[];
};
function fail(message: string): never { throw new Error(message); }
function record(value: unknown, label: string): asserts value is Record<string, any> {
  if (!value || typeof value !== "object" || Array.isArray(value)) fail(`${label} must be an object`);
}
function keys(value: Record<string, any>, allowed: string[], label: string) {
  for (const key of Object.keys(value)) if (!allowed.includes(key)) fail(`${label}.${key} is not supported`);
}
function text(value: unknown, label: string, maximum = 2048): asserts value is string {
  if (typeof value !== "string" || !value.trim() || value.length > maximum || /[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(value))
    fail(`${label} must be nonempty text (at most ${maximum} characters)`);
}
function number(value: unknown, label: string, min: number, max: number, integer = false): asserts value is number {
  if (typeof value !== "number" || !Number.isFinite(value) || value < min || value > max || (integer && !Number.isInteger(value)))
    fail(`${label} must be ${integer ? "an integer" : "finite"} between ${min} and ${max}`);
}
function safeId(value: unknown): asserts value is string {
  if (typeof value !== "string" || value.length > 64 || !ID.test(value)) fail(`Invalid character ID: ${String(value)}`);
}
export function validatePackPath(value: unknown, extension: ".png" | ".json"): asserts value is string {
  if (typeof value !== "string" || value.length > 240 || isAbsolute(value)
    || !/^[a-zA-Z0-9_./-]+$/.test(value) || value.split("/").some(part => !part || part === "." || part === "..")
    || !value.endsWith(extension)) fail(`Unsafe ${extension} pack-relative path: ${String(value)}`);
}
function point(value: unknown, label: string, width: number, height: number) {
  record(value, label); keys(value, ["x", "y"], label);
  number(value.x, `${label}.x`, 0, width); number(value.y, `${label}.y`, 0, height);
}
function box(value: unknown, label: string, width: number, height: number) {
  record(value, label); keys(value, ["x", "y", "width", "height"], label);
  number(value.x, `${label}.x`, 0, width); number(value.y, `${label}.y`, 0, height);
  number(value.width, `${label}.width`, 1, width); number(value.height, `${label}.height`, 1, height);
  if (value.x + value.width > width || value.y + value.height > height) fail(`${label} crop exceeds its frame`);
}

export function validateCharacterManifest(value: unknown): asserts value is CharacterManifest {
  record(value, "manifest");
  keys(value, ["formatVersion", "id", "displayName", "spokenName", "description", "author", "license", "preview", "sprites",
    "renderer", "effects", "motion", "blink", "intro", "narration"], "manifest");
  if (value.formatVersion !== 1) fail("formatVersion must be 1");
  safeId(value.id); text(value.displayName, "displayName", 80); text(value.description, "description");
  if (value.spokenName !== undefined) text(value.spokenName, "spokenName", 80);
  for (const label of ["author", "license"]) {
    const item = value[label]; record(item, label);
    keys(item, label === "author" ? ["name", "status", "note"] : ["identifier", "status", "note"], label);
    if (!["declared", "unresolved"].includes(item.status)) fail(`${label}.status must be declared or unresolved`);
    if (item.note !== undefined) text(item.note, `${label}.note`);
    if (label === "author") {
      if (item.name !== null) text(item.name, "author.name", 200);
      if (item.status === "declared" && item.name === null) fail("Declared author requires a name");
    } else {
      if (item.identifier !== undefined) text(item.identifier, "license.identifier", 200);
      if (item.status === "declared" && !item.identifier) fail("Declared license requires an identifier");
    }
  }
  record(value.preview, "preview"); keys(value.preview, ["sprite", "frame"], "preview");
  if (value.preview.sprite !== "idle" || value.preview.frame !== 0) fail("preview must use idle frame 0");
  record(value.sprites, "sprites"); keys(value.sprites, ROLES, "sprites");
  for (const required of ["idle", "talk", "point", "point-up"]) if (!value.sprites[required]) fail(`Missing sprites.${required}`);
  for (const [name, sprite] of Object.entries(value.sprites)) {
    record(sprite, `sprites.${name}`); keys(sprite, ["path", "frameWidth", "frameHeight", "frames", "fps", "timeline"], `sprites.${name}`);
    validatePackPath(sprite.path, ".png");
    number(sprite.frameWidth, `${name}.frameWidth`, 1, 2048, true);
    number(sprite.frameHeight, `${name}.frameHeight`, name === "speech" ? 1 : 192, 192, true);
    number(sprite.frames, `${name}.frames`, 1, 256, true);
    if (sprite.fps !== undefined) number(sprite.fps, `${name}.fps`, 0.1, 60);
    if (sprite.timeline !== undefined) {
      if (!Array.isArray(sprite.timeline) || !sprite.timeline.length || sprite.timeline.length > 256) fail(`${name}.timeline needs 1–256 entries`);
      let duration = 0;
      for (const entry of sprite.timeline) {
        record(entry, `${name}.timeline entry`); keys(entry, ["frame", "durationMs"], `${name}.timeline entry`);
        number(entry.frame, `${name}.timeline.frame`, 0, sprite.frames - 1, true);
        number(entry.durationMs, `${name}.timeline.durationMs`, 16, 60000, true);
        duration += entry.durationMs;
      }
      if (duration > 60000) fail(`${name}.timeline exceeds 60 seconds`);
    }
    if (sprite.frames > 1 && sprite.fps === undefined && sprite.timeline === undefined) fail(`${name} animation requires fps or timeline`);
    if (sprite.fps !== undefined && sprite.timeline !== undefined) fail(`${name} must choose fps or timeline, not both`);
  }
  if (value.sprites.talk.frameWidth !== value.sprites.idle.frameWidth)
    fail("talk frameWidth must match idle because both use idle pose registration");
  const renderer = value.renderer; record(renderer, "renderer");
  keys(renderer, ["canvas", "baseline", "bodyAnchorX", "registrationNote", "poses"], "renderer");
  record(renderer.canvas, "renderer.canvas"); keys(renderer.canvas, ["width", "height"], "renderer.canvas");
  if (renderer.canvas.width !== 224 || renderer.canvas.height !== 192) fail("v1 renderer.canvas must be 224×192");
  number(renderer.baseline, "renderer.baseline", 0, 192);
  number(renderer.bodyAnchorX, "renderer.bodyAnchorX", 0, 224);
  if (renderer.registrationNote !== undefined) text(renderer.registrationNote, "renderer.registrationNote");
  record(renderer.poses, "renderer.poses"); keys(renderer.poses, ["idle", "point", "point-up", "flight"], "renderer.poses");
  for (const name of ["idle", "point", "point-up", ...(value.sprites.flight ? ["flight"] : [])]) {
    const pose = renderer.poses[name]; record(pose, `renderer.poses.${name}`);
    keys(pose, ["frameWidth", "scale", "offset", "baseline", "bodyAnchorX", "tip", "flameSockets", "speech"], name);
    const sprite = value.sprites[name];
    if (pose.frameWidth !== sprite.frameWidth) fail(`${name} renderer frameWidth must match its sprite`);
    number(pose.scale, `${name}.scale`, 0.1, 4);
    record(pose.offset, `${name}.offset`); keys(pose.offset, ["x", "y"], `${name}.offset`);
    number(pose.offset.x, `${name}.offset.x`, -448, 448); number(pose.offset.y, `${name}.offset.y`, -384, 384);
    if (pose.frameWidth * pose.scale > 896 || 192 * pose.scale > 768
      || pose.offset.x >= 224 || pose.offset.x + pose.frameWidth * pose.scale <= 0
      || pose.offset.y >= 192 || pose.offset.y + 192 * pose.scale <= 0) fail(`${name} transformed frame misses or exceeds reasonable canvas bounds`);
    if (name !== "flight") {
      number(pose.baseline, `${name}.baseline`, 0, 192);
      number(pose.bodyAnchorX, `${name}.bodyAnchorX`, 0, pose.frameWidth);
      if (Math.abs(pose.baseline * pose.scale + pose.offset.y - renderer.baseline) > 0.05
        || Math.abs(pose.bodyAnchorX * pose.scale + pose.offset.x - renderer.bodyAnchorX) > 0.05) fail(`${name} baseline/bodyAnchorX registration does not match the canvas`);
    } else {
      if (pose.baseline !== undefined) number(pose.baseline, "flight.baseline", 0, 192);
      if (pose.bodyAnchorX !== undefined) number(pose.bodyAnchorX, "flight.bodyAnchorX", 0, pose.frameWidth);
    }
    if (name === "point" || name === "point-up" || pose.tip !== undefined) {
      point(pose.tip, `${name}.tip`, sprite.frameWidth, 192);
      const x = pose.tip.x * pose.scale + pose.offset.x, y = pose.tip.y * pose.scale + pose.offset.y;
      if (x < 0 || x > 224 || y < 0 || y > 192) fail(`${name}.tip falls outside the canvas`);
    }
    if (pose.flameSockets !== undefined) {
      if (!Array.isArray(pose.flameSockets) || pose.flameSockets.length > 8) fail(`${name}.flameSockets must contain at most 8 points`);
      pose.flameSockets.forEach((socket: unknown) => point(socket, `${name}.flameSocket`, sprite.frameWidth, 192));
    }
    if (pose.speech !== undefined) {
      const speech = pose.speech; record(speech, `${name}.speech`);
      keys(speech, ["sprite", "frameWidth", "restFrame", "source", "destination"], `${name}.speech`);
      const sourceName = speech.sprite ?? "talk";
      if (!["talk", "speech"].includes(sourceName) || !value.sprites[sourceName]) fail(`${name}.speech references an unknown speech sprite`);
      const source = value.sprites[sourceName];
      if (speech.restFrame !== undefined) number(speech.restFrame, `${name}.speech.restFrame`, 0, source.frames - 1, true);
      if (speech.frameWidth !== undefined && speech.frameWidth !== source.frameWidth) fail(`${name}.speech.frameWidth mismatch`);
      box(speech.source, `${name}.speech.source`, source.frameWidth, source.frameHeight);
      box(speech.destination, `${name}.speech.destination`, sprite.frameWidth, 192);
    }
  }
  if (!value.sprites.flight && renderer.poses.flight) fail("flight pose requires sprites.flight");
  for (const name of ["point", "point-up"]) {
    const alternate = value.sprites[name + "-blink"];
    if (alternate && alternate.frameWidth !== value.sprites[name].frameWidth) fail(`${name}-blink width must match ${name}`);
  }
  record(value.effects, "effects"); keys(value.effects, ["thrusters"], "effects");
  if (typeof value.effects.thrusters !== "boolean") fail("effects.thrusters must be boolean");
  record(value.motion, "motion"); keys(value.motion, ["tourFlight"], "motion");
  if (!["upright", "sprite"].includes(value.motion.tourFlight)) fail("motion.tourFlight must be upright or sprite");
  if (value.motion.tourFlight === "sprite" && !value.sprites.flight) fail("sprite tourFlight requires a flight sprite");
  if (value.blink !== undefined) {
    record(value.blink, "blink"); keys(value.blink, ["periodMs", "startMs", "durationMs"], "blink");
    number(value.blink.periodMs, "blink.periodMs", 100, 60000, true);
    number(value.blink.startMs, "blink.startMs", 0, value.blink.periodMs, true);
    number(value.blink.durationMs, "blink.durationMs", 16, value.blink.periodMs, true);
    if (value.blink.startMs + value.blink.durationMs > value.blink.periodMs) fail("blink extends beyond its period");
  }
  // Intro errors are deliberately handled separately, so graphics-only packs remain usable.
  const narration = value.narration; record(narration, "narration");
  if (!["own", "borrowed", "silent"].includes(narration.mode)) fail("Unknown narration.mode");
  keys(narration, narration.mode === "own" ? ["mode", "audioSet", "voices", "playbackRate"] : narration.mode === "borrowed" ? ["mode", "audioSet"] : ["mode"], "narration");
  if (narration.mode === "own") {
    if (narration.audioSet !== value.id) fail("Own narration.audioSet must equal pack id");
    if (narration.playbackRate !== undefined) number(narration.playbackRate, "narration.playbackRate", 0.5, 2);
    if (narration.voices !== undefined) {
      record(narration.voices, "narration.voices"); keys(narration.voices, ["azure", "edge"], "narration.voices");
      for (const [name, voice] of Object.entries(narration.voices)) text(voice, `narration.voices.${name}`, 200);
    }
  } else if (narration.mode === "borrowed" && !["ohm-1", "owl"].includes(narration.audioSet)) fail("Borrowed narration.audioSet must be ohm-1 or owl");
}

function contained(root: string, target: string) {
  const name = relative(root, target);
  return !!name && !name.startsWith(`..${sep}`) && name !== ".." && !isAbsolute(name);
}
async function boundedRead(file: string, maximum: number): Promise<Buffer> {
  const before = await stat(file);
  if (!before.isFile() || before.size > maximum) fail(`${file} must be a regular file no larger than ${maximum} bytes`);
  const handle = await open(file, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const info = await handle.stat();
    if (!info.isFile() || info.size > maximum) fail(`${file} must be a regular file no larger than ${maximum} bytes`);
    const buffer = Buffer.alloc(info.size + 1);
    let total = 0;
    while (total < buffer.length) {
      const { bytesRead } = await handle.read(buffer, total, buffer.length - total, null);
      if (!bytesRead) break;
      total += bytesRead;
    }
    if (total !== info.size) fail(`${file} changed size while reading`);
    return buffer.subarray(0, total);
  } finally { await handle.close(); }
}
async function json(file: string, maximum: number): Promise<unknown> {
  const bytes = await boundedRead(file, maximum);
  try { return JSON.parse(bytes.toString("utf8")); }
  catch { fail(`${file}: invalid JSON`); }
}
function crc32(bytes: Buffer) {
  let crc = 0xffffffff;
  for (const byte of bytes) crc = (crc >>> 8) ^ CRC_TABLE[(crc ^ byte) & 0xff];
  return (crc ^ 0xffffffff) >>> 0;
}
function pngInfo(bytes: Buffer, label: string, remainingPixels: number) {
  if (bytes.length < 45 || bytes.subarray(0, 8).toString("hex") !== "89504e470d0a1a0a"
    || bytes.readUInt32BE(8) !== 13 || bytes.toString("ascii", 12, 16) !== "IHDR") fail(`${label}: invalid PNG IHDR`);
  const width = bytes.readUInt32BE(16), height = bytes.readUInt32BE(20);
  if (!width || !height || width > PACK_LIMITS.imageSide || height > PACK_LIMITS.imageSide
    || width * height > PACK_LIMITS.imagePixels) fail(`${label}: PNG dimensions exceed limits`);
  if (width * height > remainingPixels) fail(`${label}: aggregate decoded-pixel budget exceeded`);
  const channels = ({ 0: 1, 2: 3, 4: 2, 6: 4 } as Record<number, number>)[bytes[25]];
  if (bytes[24] !== 8 || !channels || bytes[26] !== 0 || bytes[27] !== 0 || bytes[28] !== 0)
    fail(`${label}: use noninterlaced 8-bit grayscale, RGB, or RGBA PNG`);
  const chunks: Buffer[] = []; let ended = false;
  for (let offset = 8; offset < bytes.length;) {
    if (offset + 12 > bytes.length) fail(`${label}: truncated PNG chunk`);
    const length = bytes.readUInt32BE(offset), end = offset + length + 12;
    if (end > bytes.length) fail(`${label}: truncated PNG data`);
    const type = bytes.toString("ascii", offset + 4, offset + 8);
    if (crc32(bytes.subarray(offset + 4, end - 4)) !== bytes.readUInt32BE(end - 4)) fail(`${label}: PNG checksum mismatch`);
    if (type === "IHDR" && offset !== 8) fail(`${label}: duplicate PNG header`);
    if (type === "IDAT") chunks.push(bytes.subarray(offset + 8, end - 4));
    if (type === "IEND") {
      if (length || end !== bytes.length) fail(`${label}: invalid PNG ending`);
      ended = true;
    }
    offset = end;
  }
  if (!ended || !chunks.length) fail(`${label}: incomplete PNG`);
  const stride = width * channels + 1, expected = height * stride;
  let raw: Buffer;
  try { raw = inflateSync(Buffer.concat(chunks), { maxOutputLength: expected }); }
  catch { fail(`${label}: invalid or oversized PNG compressed pixels`); }
  if (raw.length !== expected) fail(`${label}: incorrect decoded PNG size`);
  for (let y = 0; y < height; y++) if (raw[y * stride] > 4) fail(`${label}: invalid PNG scanline filter`);
  return { width, height };
}
function message(error: unknown) { return error instanceof Error ? error.message : String(error); }

async function inspectPackFiles(root: string, bundled: boolean) {
  let entries = 0, bytes = 0;
  const executable = /\.(?:qml|js|mjs|cjs|sh|bash|py|pl|rb|exe|dll|so|wasm)$/i;
  async function inspect(directory: string) {
    for await (const entry of await opendir(directory)) {
      const file = join(directory, entry.name);
      const name = relative(root, file);
      if (bundled && (name === "concepts" || name === "sprites.conf")) continue;
      if (++entries > PACK_LIMITS.packEntries) fail(`Pack exceeds ${PACK_LIMITS.packEntries} filesystem entries`);
      if (executable.test(entry.name)) fail(`${name}: executable files are not allowed in data-only packs`);
      const info = await lstat(file);
      if (info.isSymbolicLink()) {
        // Do not follow unreferenced links. Referenced links undergo containment
        // checks during asset loading, including optional-intro error isolation.
        continue;
      }
      if (info.isDirectory()) await inspect(file);
      else if (info.isFile()) {
        bytes += info.size;
        if (bytes > PACK_LIMITS.runtimeBytes) fail("Pack filesystem byte limit exceeded");
      } else fail(`${name}: only regular files and directories are supported`);
    }
  }
  await inspect(root);
}

export async function loadCharacterPack(path: string, options: { expectedId?: string; bundled?: boolean } = {}): Promise<ResolvedPack> {
  const root = await realpath(resolve(path));
  if (!(await stat(root)).isDirectory()) fail(`${root}: pack must be a directory`);
  await inspectPackFiles(root, options.bundled === true);
  const files = new Map<string, number>();
  async function asset(name: string, extension: ".json" | ".png", maximum: number) {
    validatePackPath(name, extension);
    const file = await realpath(join(root, name));
    if (!contained(root, file)) fail(`${name}: symlink escapes pack root`);
    const bytes = await boundedRead(file, maximum);
    files.set(name, bytes.length);
    if (files.size > PACK_LIMITS.runtimeFiles || [...files.values()].reduce((a, b) => a + b, 0) > PACK_LIMITS.runtimeBytes)
      fail("Pack runtime file/byte limit exceeded");
    return bytes;
  }
  let value: unknown;
  try { value = JSON.parse((await asset("character.json", ".json", PACK_LIMITS.manifestBytes)).toString("utf8")); }
  catch (error) { fail(`character.json: ${message(error)}`); }
  validateCharacterManifest(value);
  if (options.expectedId !== undefined && value.id !== options.expectedId) fail(`Pack id ${value.id} does not match directory/catalog id ${options.expectedId}`);
  const diagnostics: string[] = [];
  for (const field of ["author", "license"] as const) if (value[field].status === "unresolved") diagnostics.push(`${value.id}: ${field} is unresolved; review attribution and redistribution rights`);
  const images = new Map<string, { width: number; height: number }>();
  let decodedPixels = 0;
  async function image(name: string) {
    if (!images.has(name)) {
      const dimensions = pngInfo(await asset(name, ".png", PACK_LIMITS.imageBytes), name, PACK_LIMITS.packPixels - decodedPixels);
      images.set(name, dimensions);
      decodedPixels += dimensions.width * dimensions.height;
    }
    return images.get(name)!;
  }
  for (const [name, sprite] of Object.entries(value.sprites)) {
    const dimensions = await image(sprite.path);
    if (dimensions.width !== sprite.frameWidth * sprite.frames || dimensions.height !== sprite.frameHeight)
      fail(`${name}: PNG dimensions do not match frameWidth × frames and frameHeight`);
  }
  let intro: unknown | null = null;
  const graphicFiles = new Map(files);
  if (value.intro !== undefined) {
    try {
      record(value.intro, "intro"); keys(value.intro, ["sequence"], "intro");
      validatePackPath(value.intro.sequence, ".json");
      const sequence = JSON.parse((await asset(value.intro.sequence, ".json", PACK_LIMITS.sequenceBytes)).toString("utf8"));
      const errors = validateIntroSequence(sequence);
      if (errors.length) fail(errors.join("; "));
      for (const name of introAssetPaths(sequence)) await image(name);
      intro = sequence;
    } catch (error) {
      diagnostics.push(`${value.id}: intro disabled: ${message(error)}`);
      files.clear(); for (const [name, size] of graphicFiles) files.set(name, size);
    }
  } else diagnostics.push(`${value.id}: no intro sequence; graphics-only pack`);
  return { id: value.id, root, assetUrl: pathToFileURL(root).href.replace(/\/$/, ""), manifest: value, intro,
    runtimeFiles: [...files.keys()].sort(), diagnostics };
}

export async function discoverCharacterPacks(options: { bundledRoot: string; userRoot?: string }): Promise<CharacterCatalog> {
  const result: CharacterCatalog = { version: 1, packs: [], diagnostics: [], fallbackId: null, invalidBundledIds: [] };
  let outputBytes = 0;
  const reserved = new Set<string>();
  let bundleRoot: string | undefined;
  let catalogRoot: string | undefined;
  let allowUserPacks = true;
  try {
    bundleRoot = await realpath(options.bundledRoot);
    catalogRoot = bundleRoot;
    const indexPath = await realpath(join(bundleRoot, "index.json"));
    if (!contained(bundleRoot, indexPath)) fail("Bundled catalog symlink escapes its root");
    const index = await json(indexPath, PACK_LIMITS.manifestBytes);
    record(index, "catalog");
    if (index.formatVersion !== 1 || !Array.isArray(index.characters) || index.characters.length > PACK_LIMITS.catalogEntries)
      fail("Bundled index requires formatVersion:1 and a bounded characters array");
    for (const entry of index.characters) {
      try {
        record(entry, "catalog entry"); safeId(entry.id);
        if (reserved.has(entry.id)) fail(`Duplicate bundled ID ${entry.id}`);
        reserved.add(entry.id);
      } catch (error) {
        result.diagnostics.push(`Bundled catalog: ${message(error)}`);
        if (!result.invalidBundledIds.includes("index.json")) result.invalidBundledIds.push("index.json");
      }
    }
  } catch (error) {
    result.diagnostics.push(`Bundled catalog: ${message(error)}`);
    // Without a trustworthy catalog, never let local packs impersonate shipped IDs.
    reserved.add("ohm-1"); reserved.add("owl");
    bundleRoot = undefined;
  }
  const bundledIds = [...reserved].sort();
  if (catalogRoot && (!bundleRoot || result.invalidBundledIds.includes("index.json"))) {
    reserved.add("ohm-1"); reserved.add("owl");
    try {
      let entries = 0;
      for await (const entry of await opendir(catalogRoot)) {
        if (++entries > PACK_LIMITS.catalogEntries) fail(`Bundled root exceeds ${PACK_LIMITS.catalogEntries} entries`);
        if (!entry.isDirectory() && !entry.isSymbolicLink()) continue;
        if (entry.name.length <= 64 && ID.test(entry.name)) reserved.add(entry.name);
      }
    } catch (error) {
      // An incomplete reservation scan cannot safely distinguish a new official
      // ID from an impersonating user pack, so fail closed for user discovery.
      allowUserPacks = false;
      result.diagnostics.push(`Bundled ID reservation failed; user discovery disabled: ${message(error)}`);
    }
  }
  async function add(root: string, id: string, bundled: boolean) {
    try {
      const candidate = await realpath(join(root, id));
      if (!contained(root, candidate)) fail("Pack directory symlink escapes discovery root");
      const pack = await loadCharacterPack(candidate, { expectedId: id, bundled });
      const packBytes = Buffer.byteLength(JSON.stringify(pack));
      if (outputBytes + packBytes > PACK_LIMITS.outputBytes - 1024 * 1024) fail("Discovery output size limit exceeded");
      outputBytes += packBytes;
      result.packs.push(pack); result.diagnostics.push(...pack.diagnostics);
    } catch (error) {
      result.diagnostics.push(`${bundled ? "Bundled" : "User"} pack ${id}: ${message(error)}`);
      if (bundled) result.invalidBundledIds.push(id);
    }
  }
  if (bundleRoot) for (const id of bundledIds) await add(bundleRoot, id, true);
  else result.invalidBundledIds.push(...[...reserved].sort());
  if (options.userRoot && allowUserPacks) {
    try {
      const root = await realpath(options.userRoot);
      const entries = [];
      for await (const entry of await opendir(root)) {
        entries.push(entry);
        if (entries.length > PACK_LIMITS.catalogEntries) fail(`User pack directory exceeds ${PACK_LIMITS.catalogEntries} entries`);
      }
      let candidates = 0;
      for (const entry of entries.sort((a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0)) {
        if (!entry.isDirectory() && !entry.isSymbolicLink()) continue;
        if (++candidates > PACK_LIMITS.userPacks) {
          result.diagnostics.push(`User pack discovery limited to ${PACK_LIMITS.userPacks} directories; remaining entries ignored`);
          break;
        }
        try { safeId(entry.name); }
        catch (error) { result.diagnostics.push(`User directory: ${message(error)}`); continue; }
        if (reserved.has(entry.name)) { result.diagnostics.push(`User pack ${entry.name}: bundled ID is reserved; ignored`); continue; }
        await add(root, entry.name, false);
      }
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") result.diagnostics.push(`User packs: ${message(error)}`);
    }
  }
  result.packs.sort((a, b) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
  result.fallbackId = result.packs.some(pack => pack.id === "ohm-1") ? "ohm-1" : result.packs[0]?.id ?? null;
  if (!result.packs.length) result.diagnostics.push("No valid character packs are available");
  result.diagnostics = result.diagnostics.slice(0, 200).map(diagnostic => diagnostic.slice(0, 400));
  return result;
}
