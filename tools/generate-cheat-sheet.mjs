import { readFile, writeFile } from "node:fs/promises";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { parseCourseJson } from "../src/course.ts";

export function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, character =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[character]);
}

export function shortcutSections(course) {
  const seen = new Set();
  return course.lessons.flatMap(lesson => {
    const entries = lesson.steps.flatMap(step => {
      const dynamicDirection = Boolean(step.directionFromStep || step.swapWithStep);
      const keys = step.keys.map(key => dynamicDirection && ["LEFT", "RIGHT", "UP", "DOWN"].includes(key) ? "ARROW" : key);
      const directionNote = "Choose the arrow pointing toward the other practice window; the direction depends on the current layout.";
      const caution = [step.note, dynamicDirection ? directionNote : ""].filter(Boolean).join(" ");
      const references = step.shortcuts ?? (keys.length
        ? [{ keys, action: step.practicePrompt || step.help?.label || step.instruction, caution }]
        : []);
      return references.flatMap(reference => {
        const chord = reference.keys.join(" ");
        if (seen.has(chord)) return [];
        seen.add(chord);
        return [{ ...reference, stepId: step.id }];
      });
    });
    return entries.length ? [{ id: lesson.id, title: lesson.title, optional: lesson.optional === true, entries }] : [];
  });
}

export function renderCheatSheet(course) {
  const sections = shortcutSections(course).map(section => `<section id="${escapeHtml(section.id)}">
<h2>${escapeHtml(section.title)}${section.optional ? " <small>(optional)</small>" : ""}</h2>
<dl>${section.entries.map(entry => `<div data-step-id="${escapeHtml(entry.stepId)}"><dt>${escapeHtml(entry.keys.join(" "))}</dt><dd>${escapeHtml(entry.action)}${entry.caution ? `<small>${escapeHtml(entry.caution)}</small>` : ""}</dd></div>`).join("\n")}</dl></section>`).join("\n");
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(course.title)} — shortcut reference</title>
<style>
:root { color-scheme: light; font: 15px/1.4 system-ui, sans-serif; color: #17212b; background: white; }
body { max-width: 1060px; margin: 2rem auto; padding: 0 1.5rem; }
h1 { font-size: 1.7rem; margin-bottom: .3rem; } h2 { font-size: 1rem; margin: 0 0 .5rem; border-bottom: 1px solid #87939c; }
p { margin: .5rem 0; } .reference { columns: 2; column-gap: 2rem; margin-top: 1.5rem; }
section { break-inside: avoid; margin-bottom: 1.3rem; } dl { margin: 0; }
dl div { break-inside: avoid; margin-bottom: .6rem; } dt { font-weight: 750; font-size: .83rem; }
dd { margin: 0; } small { display: block; color: #4b5861; font-size: .78rem; font-weight: normal; }
h2 small { display: inline; } button { padding: .5rem 1rem; font: inherit; cursor: pointer; }
footer { border-top: 1px solid #87939c; padding-top: .6rem; font-size: .8rem; }
@media (max-width: 650px) { .reference { columns: 1; } }
@media print {
  @page { margin: 12mm; }
  :root { font-size: 10pt; } body { margin: 0; padding: 0; max-width: none; }
  button { display: none; } .reference { columns: 2; column-gap: 8mm; }
  h1 { font-size: 17pt; } section { margin-bottom: 4mm; }
}
</style></head><body>
<header><h1>${escapeHtml(course.title)}: shortcut reference</h1>
<p>Super is the Windows-logo key, or Command on a Mac keyboard. Return means Enter. Hold chord keys together unless the activity says otherwise.</p>
<p>MINUS and EQUAL name the two physical keys to the left of Backspace (codes 20 and 21), regardless of their printed labels. COMMA means the comma key.</p>
<p>Reference only: actions affect your real desktop. Use disposable windows, inspect notifications before invoking them, and check your current bindings with Super + K. Personal overrides may differ.</p>
<button type="button" onclick="window.print()">Print or save as PDF</button></header>
<main class="reference">${sections}</main>
<footer>Generated from the loaded course; duplicate chords are listed once. Optional references are introductions, not verified exercises. Practice progress stays in the app.</footer>
</body></html>
`;
}

export async function generateCheatSheet(coursePath, outputPath, check = false) {
  const parsed = parseCourseJson(await readFile(coursePath, "utf8"));
  if (!parsed.course || parsed.errors.length) throw new Error(parsed.errors.join("\n"));
  const html = renderCheatSheet(parsed.course);
  if (check) {
    if (await readFile(outputPath, "utf8") !== html) throw new Error("Printable shortcut reference is stale; regenerate it.");
  } else {
    await writeFile(outputPath, html, "utf8");
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  const check = args.includes("--check");
  const paths = args.filter(argument => argument !== "--check");
  const coursePath = resolve(paths[0] || "courses/omarchy-basics.json");
  const outputPath = resolve(paths[1] || resolve(dirname(coursePath), "omarchy-shortcuts.html"));
  generateCheatSheet(coursePath, outputPath, check).catch(error => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
