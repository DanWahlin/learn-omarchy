import { resolve } from "node:path";
import { auditCourseAudio } from "./audio-coverage.ts";

try {
  const args = process.argv.slice(2);
  const requireTimings = args.includes("--require-word-timings");
  const paths = args.filter(arg => arg !== "--require-word-timings");
  if (paths.length > 1 || paths.some(path => path.startsWith("--")))
    throw new Error("Usage: validate-course-audio.ts [course.json] [--require-word-timings]");
  const result = await auditCourseAudio(resolve(paths[0] ?? "courses/omarchy-basics.json"));
  for (const issue of result.issues) console.error(`${issue.clip.key}: ${issue.reasons.join(", ")}`);
  if (result.issues.length) {
    console.error(`${result.issues.length} of ${result.clips.length} required narration clips need attention.`);
    process.exitCode = 1;
  } else console.log(`Narration complete: ${result.clips.length} current recordings with matching text, voices, and file hashes.`);
  console.log(`Word timings: ${result.timedClips} current; ${result.missingTimings.length} recordings use full-text fallback.`);
  if (requireTimings && result.missingTimings.length) {
    for (const clip of result.missingTimings) console.error(`${clip.key}: word timings are required but missing`);
    process.exitCode = 1;
  }
} catch (error) {
  console.error(`Unable to validate narration: ${error instanceof Error ? error.message : String(error)}`);
  process.exitCode = 1;
}
