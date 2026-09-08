import { resolve } from "node:path";
import { auditCourseAudio } from "./audio-coverage.ts";

try {
  const result = await auditCourseAudio(resolve(process.argv[2] ?? "courses/omarchy-basics.json"));
  for (const issue of result.issues) console.error(`${issue.clip.key}: ${issue.reasons.join(", ")}`);
  if (result.issues.length) {
    console.error(`${result.issues.length} of ${result.clips.length} required narration clips need attention.`);
    process.exitCode = 1;
  } else console.log(`Narration complete: ${result.clips.length} current recordings with matching text, voices, and file hashes.`);
} catch (error) {
  console.error(`Unable to validate narration: ${error instanceof Error ? error.message : String(error)}`);
  process.exitCode = 1;
}
