#!/usr/bin/env node
// verify-m4-ui.mjs: M4 UI verification that needs the network or the
// built bundle. It does NOT touch audit.js or the rules; it only checks
// the UI-owned pieces:
//
//   1. "Explain this function" renders for every finding on both live
//      Onyx realms (gov/dao and sys/params): extractEnclosingFunction
//      finds the enclosing function for the finding line, and the
//      finding line is inside it and flagged.
//   2. The bundled demo sources audit to exactly the manifest's
//      expected findings (rule, file, line), using the same auditFiles
//      path the demo cards use client-side.
//
// Run from the project root: node ui/scripts/verify-m4-ui.mjs
// Exit code 0 means every check passed, 1 means a check failed.

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { auditFiles } from "../src/lib/audit.js";
import { explainRule, extractEnclosingFunction } from "../src/lib/explain.js";
import { fetchRealmFiles } from "../src/lib/gnoRpc.js";

const here = dirname(fileURLToPath(import.meta.url));
const manifest = JSON.parse(
  readFileSync(join(here, "..", "public", "demo-sources", "manifest.json"), "utf-8"),
);

let failures = 0;
function check(ok, label) {
  console.log(`${ok ? "PASS" : "FAIL"} ${label}`);
  if (!ok) failures += 1;
}

// 1. Explain view on both live Onyx realms.
for (const realm of ["gno.land/r/gov/dao", "gno.land/r/sys/params"]) {
  const files = await fetchRealmFiles(realm);
  const findings = auditFiles(files);
  const byFile = new Map(files.map((f) => [f.name, f.source]));
  console.log(`\n${realm}: ${files.length} file(s), ${findings.length} finding(s)`);
  for (const f of findings) {
    const source = byFile.get(f.file);
    const fn = source ? extractEnclosingFunction(source, f.line) : null;
    const highlighted =
      fn !== null &&
      fn.lines.some((l) => l.isFinding && l.number === f.line);
    const explained = explainRule(f.ruleID).risk.length > 0;
    console.log(
      `  ${f.ruleID} ${f.severity} ${f.file}:${f.line} -> function ${fn ? fn.name : "(none)"} lines ${fn ? `${fn.startLine}-${fn.endLine}` : "-"}`,
    );
    check(fn !== null, `${realm} ${f.ruleID}:${f.line} enclosing function found`);
    check(highlighted, `${realm} ${f.ruleID}:${f.line} finding line highlighted`);
    check(explained, `${realm} ${f.ruleID} has a plain-English explanation`);
  }
}

// 2. Bundled demo sources audit to the manifest's expected findings.
console.log("\nDemo realms (bundled local sources, auditFiles path):");
const key = (f) => [f.ruleID, f.file, f.line].join("|");
for (const demo of manifest.realms) {
  const files = demo.files.map((name) => ({
    name,
    source: readFileSync(
      join(here, "..", "public", "demo-sources", demo.name, name),
      "utf-8",
    ),
  }));
  const got = auditFiles(files).map(key).sort();
  const want = demo.expectedFindings.map(key).sort();
  const same = got.length === want.length && got.every((k, i) => k === want[i]);
  check(same, `${demo.name}: bundled audit matches manifest (${got.length} finding(s), expected score ${demo.expectedScore}/100)`);
  if (!same) {
    console.log(`  got:  ${got.join(", ")}`);
    console.log(`  want: ${want.join(", ")}`);
  }
  // The explain view must also work on every demo finding.
  const byFile = new Map(files.map((f) => [f.name, f.source]));
  for (const f of auditFiles(files)) {
    const fn = extractEnclosingFunction(byFile.get(f.file), f.line);
    check(fn !== null, `${demo.name} ${f.ruleID}:${f.line} enclosing function found`);
  }
}

if (failures > 0) {
  console.log(`\n${failures} check(s) failed.`);
  process.exit(1);
}
console.log("\nAll M4 UI checks passed.");
