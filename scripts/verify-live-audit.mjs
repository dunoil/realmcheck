// verify-live-audit.mjs: audit one or more deployed Onyx realms with the
// UI's own code path (fetchRealmFiles from gnoRpc.js plus auditFiles and
// score from audit.js) and compare the fetched source byte-for-byte with
// the staged repo copy. Usage:
//   node scripts/verify-live-audit.mjs <realm-path> [<staged-file>]
// Exit 0 when every realm audits and every staged comparison matches.
import { readFileSync } from "node:fs";
import { fetchRealmFiles } from "../ui/src/lib/gnoRpc.js";
import { auditFiles, score } from "../ui/src/lib/audit.js";

const args = process.argv.slice(2);
if (args.length === 0 || args.length % 2 !== 0) {
  console.error(
    "Usage: node scripts/verify-live-audit.mjs <realm-path> [<staged-file>] ...",
  );
  process.exit(2);
}
let failures = 0;
for (let i = 0; i < args.length; i += 2) {
  const realmPath = args[i];
  const stagedFile = args[i + 1];
  const name = realmPath.split("/").pop();
  try {
    const files = await fetchRealmFiles(realmPath);
    const findings = auditFiles(files);
    console.log(
      `${name}: live fetch OK (${files.length} file(s)), score ${score(findings)}, ${findings.length} finding(s): ` +
        findings.map((f) => `${f.ruleID}@${f.line}`).join(", "),
    );
    if (stagedFile) {
      const staged = readFileSync(stagedFile, "utf-8");
      const fetched = files.find((f) => f.name === `${name}.gno`);
      if (!fetched) {
        console.log(`  FAIL: fetched listing has no ${name}.gno`);
        failures++;
      } else if (fetched.source !== staged) {
        console.log(
          `  FAIL: live source differs from staged ${stagedFile} (live ${fetched.source.length} bytes, staged ${staged.length} bytes)`,
        );
        failures++;
      } else {
        console.log(`  PASS: live source is byte-identical to ${stagedFile}`);
      }
    }
  } catch (e) {
    console.log(`${name}: FAIL: ${e instanceof Error ? e.message : String(e)}`);
    failures++;
  }
}
console.log(failures === 0 ? "RESULT: PASSED" : `RESULT: FAILED (${failures} failure(s))`);
process.exit(failures === 0 ? 0 : 1);
