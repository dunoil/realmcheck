#!/usr/bin/env node
// test-audit-port.mjs: verifies the JavaScript audit port (src/lib/audit.js)
// produces exactly the same findings as the on-chain Gno audit rules
// (contracts/auditrules) for every demo realm source.
//
// Ground truth: scripts/expected-findings.json, generated from the real
// Gno Audit() by scripts/generate-expected-findings.py (temporary Gno
// test, deleted after the run). To regenerate after a rule change:
//   python3 ui/scripts/generate-expected-findings.py
//   node ui/scripts/test-audit-port.mjs
//
// Comparison key per finding: ruleID, severity, line, title, file.
// The Gno output has no file field (Audit takes one source string), so
// the expected file is the realm filename itself.
//
// Run from the project root: node ui/scripts/test-audit-port.mjs
// Exit code 0 means the port matches Gno exactly; 1 means a mismatch.

import { readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { auditFile } from "../src/lib/audit.js";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const demoDir = join(root, "contracts", "demo");
const expectedPath = join(
  dirname(fileURLToPath(import.meta.url)),
  "expected-findings.json",
);

const expected = JSON.parse(readFileSync(expectedPath, "utf-8"));

function key(f) {
  return [f.ruleID, f.severity, f.line, f.title, f.file].join("|");
}

function sortedKeys(findings) {
  return findings.map(key).sort();
}

let failures = 0;
for (const realm of readdirSync(demoDir, { withFileTypes: true })) {
  if (!realm.isDirectory()) continue;
  const file = `${realm.name}.gno`;
  const src = readFileSync(join(demoDir, realm.name, file), "utf-8");
  const got = auditFile(file, src);
  const want = (expected[file] || []).map((f) => ({ ...f, file }));
  const gotKeys = sortedKeys(got);
  const wantKeys = sortedKeys(want);
  const same =
    gotKeys.length === wantKeys.length &&
    gotKeys.every((k, i) => k === wantKeys[i]);
  if (same) {
    console.log(`PASS ${file}: ${got.length} finding(s), identical to Gno Audit()`);
    continue;
  }
  failures += 1;
  console.log(`FAIL ${file}: JS port differs from Gno Audit()`);
  for (const k of wantKeys.filter((x) => !gotKeys.includes(x))) {
    console.log(`  missing (Gno has, JS lacks): ${k}`);
  }
  for (const k of gotKeys.filter((x) => !wantKeys.includes(x))) {
    console.log(`  extra   (JS has, Gno lacks): ${k}`);
  }
}

if (failures > 0) {
  console.log(`\n${failures} realm(s) mismatched. Port is NOT verified.`);
  process.exit(1);
}
console.log("\nAll demo realms match Gno Audit() exactly. Port verified.");
