#!/usr/bin/env node
// ui-local-audit.mjs: proves the UI's own code path can audit against the
// local gnodev chain, without a browser.
//
// The UI (ui/src/App.tsx runAudit) fetches realm source with
// fetchRealmFiles from ui/src/lib/gnoRpc.js and audits it with
// ui/src/lib/audit.js. This script runs exactly those two functions
// under node. gnoRpc.js reads VITE_GNO_RPC, VITE_GNOWEB, and
// VITE_REALMCHECK_REALM from process.env under node, so the harness
// runs this with the same values it passes to the Vite dev server.
//
// Usage (called by scripts/e2e-local.sh while the local chain is up):
//   VITE_GNO_RPC=http://127.0.0.1:26658 VITE_GNOWEB=http://127.0.0.1:8889 \
//     VITE_REALMCHECK_REALM=gno.land/r/dunoil/realmcheck \
//     node scripts/ui-local-audit.mjs
//
// It checks, per demo realm (vulnmint, adminbackdoor):
//   - fetchRealmFiles(realmPath) against the configured RPC returns the
//     same source the harness audited (same SHA-256 as scripts/e2e-work/<realm>.json);
//   - auditFile on that fetched source gives the same findings and score
//     as the real Gno Audit() in the work file.
// Exit code 0 means the UI code path audits both realms correctly
// against the configured (local) chain. The in-browser click-through
// (search box, not the demo buttons, which use bundled sources) stays
// a manual step in tests/e2e-local-checklist.md.

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createHash } from "node:crypto";
import { GNO_RPC, GNO_GNOWEB, REALMCHECK_REALM, fetchRealmFiles } from "../ui/src/lib/gnoRpc.js";
import { auditFile, score as jsScore } from "../ui/src/lib/audit.js";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const workDir = join(root, "scripts", "e2e-work");
const REALMS = [
  { name: "vulnmint", path: "gno.land/r/dunoil/vulnmint", file: "vulnmint.gno" },
  { name: "adminbackdoor", path: "gno.land/r/dunoil/adminbackdoor", file: "adminbackdoor.gno" },
];

let failures = 0;
function sha256Hex(text) {
  return createHash("sha256").update(text, "utf-8").digest("hex");
}
function key4(f) {
  return [f.ruleID, f.severity, f.line, f.title].join("|");
}

console.log(`UI endpoints in effect: GNO_RPC=${GNO_RPC} GNO_GNOWEB=${GNO_GNOWEB} REALMCHECK_REALM=${REALMCHECK_REALM}`);
if (!GNO_RPC.includes("127.0.0.1")) {
  console.log("FAIL UI endpoints do not point at the local chain (GNO_RPC is not 127.0.0.1).");
  process.exit(1);
}

for (const realm of REALMS) {
  const work = JSON.parse(readFileSync(join(workDir, `${realm.name}.json`), "utf-8"));
  let files;
  try {
    files = await fetchRealmFiles(realm.path);
  } catch (e) {
    console.log(`FAIL ${realm.name}: UI fetchRealmFiles("${realm.path}") threw: ${e.message}`);
    failures += 1;
    continue;
  }
  const fetched = files.find((f) => f.name === realm.file);
  if (!fetched) {
    console.log(`FAIL ${realm.name}: UI fetchRealmFiles returned files [${files.map((f) => f.name).join(", ")}], missing ${realm.file}.`);
    failures += 1;
    continue;
  }
  const hash = sha256Hex(fetched.source);
  if (hash === work.sourceHash) {
    console.log(`PASS ${realm.name}: UI fetchRealmFiles returns the audited source (SHA-256 ${hash.slice(0, 16)}...).`);
  } else {
    console.log(`FAIL ${realm.name}: UI fetched source hash ${hash} differs from audited ${work.sourceHash}.`);
    failures += 1;
  }
  const findings = auditFile(realm.file, fetched.source);
  const score = jsScore(findings);
  const wantKeys = work.findings.map(key4).sort();
  const gotKeys = findings.map(key4).sort();
  if (score === work.score && JSON.stringify(gotKeys) === JSON.stringify(wantKeys)) {
    console.log(`PASS ${realm.name}: UI audit.js on the fetched source gives score ${score} and the same ${findings.length} finding(s) as Gno Audit().`);
  } else {
    console.log(`FAIL ${realm.name}: UI audit differs (score ${score} vs ${work.score}; findings ${JSON.stringify(gotKeys)} vs ${JSON.stringify(wantKeys)}).`);
    failures += 1;
  }
}

if (failures > 0) {
  console.log(`\nUI local audit FAILED: ${failures} failure(s).`);
  process.exit(1);
}
console.log("\nUI local audit PASSED: the UI code path fetches and audits both demo realms correctly against the local chain.");
