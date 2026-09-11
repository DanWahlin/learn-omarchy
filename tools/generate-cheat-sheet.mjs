import { readFile, writeFile } from "node:fs/promises";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { parseCourseJson, validateCourse } from "../src/course.ts";

export function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, character =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[character]);
}

export function shortcutSections(course) {
  return course.lessons.flatMap(lesson => {
    const entries = lesson.references ? lesson.references.map(reference => ({
      ...reference,
      stepId: reference.stepIds[0] || "",
      optional: reference.stepIds.length > 0 &&
        reference.stepIds.every(id => lesson.steps.find(step => step.id === id)?.optional === true),
    })) : lesson.steps.flatMap(step => {
      const dynamicDirection = Boolean(step.directionFromStep || step.swapWithStep);
      const keys = step.keys.map(key => dynamicDirection && ["LEFT", "RIGHT", "UP", "DOWN"].includes(key) ? "ARROW" : key);
      const references = step.shortcuts ?? (keys.length
        ? [{ keys, action: "Shortcut used by this guided activity.",
          caution: "Consult the lesson and your current bindings before using this shortcut outside the course." }]
        : []);
      return references.map(reference => ({
        ...reference, kind: "chord", stepId: step.id, stepIds: [step.id],
        sourceIds: [], optional: step.optional === true,
      }));
    });
    return entries.length ? [{ id: lesson.id, title: lesson.title, optional: lesson.optional === true, entries }] : [];
  }).sort((a, b) => Number(a.optional) - Number(b.optional));
}

export function renderCheatSheet(course) {
  const errors = validateCourse(course);
  if (errors.length) throw new Error(errors.join("\n"));
  const sources = course.reference?.sources || [];
  const kindLabels = { chord: "", sequence: "Press in order", gesture: "Mouse gesture", workflow: "Workflow" };
  const sourceLinks = entry => entry.sourceIds.map(id => {
    const index = sources.findIndex(source => source.id === id);
    return `<a href="#source-${escapeHtml(id)}" aria-label="${escapeHtml(sources[index].title)}">[${index + 1}]</a>`;
  }).join(" ");
  const sections = shortcutSections(course).map(section => `<section id="${escapeHtml(section.id)}">
<h2>${escapeHtml(section.title)}${section.optional ? " <small>(optional)</small>" : ""}</h2>
<dl>${section.entries.map(entry => `<div data-step-id="${escapeHtml(entry.stepId)}" data-step-ids="${escapeHtml(JSON.stringify(entry.stepIds))}" data-kind="${escapeHtml(entry.kind)}">
<dt>${kindLabels[entry.kind] ? `<span class="kind">${kindLabels[entry.kind]}: </span>` : ""}${escapeHtml(entry.keys.join(" "))}${entry.optional && !section.optional ? " <span class=\"kind\">(optional activity)</span>" : ""} <sup>${sourceLinks(entry)}</sup></dt>
<dd>${escapeHtml(entry.action)}${entry.caution ? `<small>${escapeHtml(entry.caution)}</small>` : ""}</dd></div>`).join("\n")}</dl></section>`).join("\n");
  const provenance = course.reference
    ? `<p><strong>${escapeHtml(course.reference.platform)} ${escapeHtml(course.reference.version)} defaults.</strong> Reviewed ${escapeHtml(course.reference.verifiedOn)} against the versioned sources below. Reference entries cover all ${course.lessons.length} lessons and ${course.lessons.reduce((count, lesson) => count + lesson.steps.length, 0)} activities.</p>`
    : `<p><strong>Unreviewed course reference.</strong> This course has no versioned reference metadata. Entries may be incomplete and are not a verified standalone shortcut guide.</p>`;
  const bibliography = sources.length ? `<aside class="sources"><h2>Sources and version scope</h2>
<p>Official sources are pinned to the stated release; course-specific practice sources describe Learn Omarchy, not native Omarchy features. Bundled paths are relative to Learn Omarchy's application directory. Newer releases and personal bindings may differ. Links are optional: reading and printing this sheet require no network access.</p>
<ol>${sources.map(source => `<li id="source-${escapeHtml(source.id)}">${source.url
    ? `<a href="${escapeHtml(source.url)}">${escapeHtml(source.title)}</a><span class="source-url">${escapeHtml(source.url)}</span>`
    : `${escapeHtml(source.title)}<span class="source-url">Bundled source: ${escapeHtml(source.path)}</span>`}</li>`).join("\n")}</ol></aside>` : "";
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(course.title)}: shortcut reference</title>
<style>
:root { color-scheme: light; font: 15px/1.4 system-ui, sans-serif; color: #17212b; background: white; }
body { max-width: 1060px; margin: 2rem auto; padding: 0 1.5rem; }
h1 { font-size: 1.7rem; margin-bottom: .3rem; } h2 { font-size: 1rem; margin: 0 0 .5rem; border-bottom: 1px solid #87939c; }
p { margin: .5rem 0; } .reference { columns: 2; column-gap: 2rem; margin-top: 1.5rem; }
section { margin-bottom: 1.3rem; } h2 { break-after: avoid; } dl { margin: 0; }
dl div { break-inside: avoid; margin-bottom: .6rem; } dt { font-weight: 750; font-size: .83rem; }
dd { margin: 0; } small { display: block; color: #4b5861; font-size: .78rem; font-weight: normal; }
h2 small { display: inline; } button { padding: .5rem 1rem; font: inherit; cursor: pointer; }
footer { border-top: 1px solid #87939c; padding-top: .6rem; font-size: .8rem; }
.kind { font-size: .9em; font-weight: normal; } sup { font-size: .75em; }
a { color: inherit; } .sources { margin-top: 1.5rem; font-size: .8rem; }
.sources ol { columns: 2; column-gap: 2rem; padding-left: 1.4rem; }
.sources li { break-inside: avoid; margin-bottom: .65rem; padding-right: .5rem; }
.source-url { display: block; overflow-wrap: anywhere; font-size: .85em; }
@media (max-width: 650px) { .reference, .sources ol { columns: 1; } }
@media print {
  @page { margin: 12mm; }
  :root { font-size: 10pt; } body { margin: 0; padding: 0; max-width: none; }
  button { display: none; } .reference { columns: 2; column-gap: 8mm; }
  h1 { font-size: 17pt; } section { margin-bottom: 4mm; }
}
</style></head><body>
<header><h1>${escapeHtml(course.title)}: shortcut reference</h1>
${provenance}
<p>Super is the Windows-logo key, or Command on a Mac keyboard; Alt is Option on a Mac keyboard. Return means Enter. Hold chord keys together. Entries marked <strong>Press in order</strong> are separate key presses, not held chords; <strong>Workflow</strong> entries describe menu paths or procedures.</p>
<p>MINUS and EQUAL name the two physical keys to the left of Backspace (codes 20 and 21), regardless of their printed labels. COMMA means the comma key.</p>
<p><strong>Outside the guided app, shortcuts affect your real focused window and desktop, not just lesson-created windows.</strong> Save your work, use disposable windows, and inspect notifications before invoking them. Super + K shows current bindings; Enter or clicking a result executes it. Custom bindings may differ.</p>
<button type="button" onclick="window.print()">Print or save as PDF</button></header>
<main class="reference">${sections}</main>
${bibliography}
<footer>Generated from the loaded course. Repeated activities share an entry within a lesson; relevant shortcuts remain in each lesson. Optional labels identify optional course material, not a claim that an action was performed. Guided exercises and simulated workflows are identified separately; progress stays in the app.</footer>
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
