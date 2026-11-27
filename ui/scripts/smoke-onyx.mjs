#!/usr/bin/env node
// smoke-onyx.mjs: live smoke test of the UI data path against the Onyx
// testnet. Fetches a real realm's source through the same gnoRpc.js
// helpers the UI uses, audits it with the same audit.js port, and
// prints the findings and score.
//
// Run from the project root: node ui/scripts/smoke-onyx.mjs [realm-path]
// Default realm: gno.land/r/sys/params (confirmed to exist on Onyx).
// Exit code 0 on success, 1 on any RPC or audit failure.

import { auditFiles, score } from "../src/lib/audit.js";
import { fetchRealmFiles, sha256Hex } from "../src/lib/gnoRpc.js";

const realmPath = process.argv[2] || "gno.land/r/sys/params";

const files = await fetchRealmFiles(realmPath);
console.log(`fetched ${files.length} file(s) from ${realmPath}:`);
for (const f of files) {
  console.log(`  ${f.name} (${f.source.length} bytes)`);
}
const findings = auditFiles(files);
const combined = files.map((f) => `===== ${f.name} =====\n${f.source}`).join("\n");
const hash = await sha256Hex(combined);
console.log(`score: ${score(findings)}/100, ${findings.length} finding(s)`);
console.log(`source SHA-256: ${hash}`);
for (const f of findings) {
  console.log(`  ${f.ruleID} ${f.severity} ${f.file}:${f.line} ${f.title}`);
}
console.log("smoke test OK");
