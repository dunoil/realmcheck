#!/usr/bin/env node
// audit.mjs: RealmCheck agent-mode audit step.
//
// Fetches a realm source from a live chain with vm/qfile, checks it is
// byte-identical to the local contract source, audits the FETCHED text
// with the JavaScript port of the audit rules (ui/src/lib/audit.js),
// and writes a JSON work file with the source hash, score, findings,
// and the SubmitReport encoding from docs/API.md.
//
// Why the JS port is the audit engine here (see agent/SKILL.md): the
// port matches Gno Audit() exactly on all 5 demo realms (verified in
// M4), it runs under plain node with no temp files and no writes into
// contracts/, and the Gno Audit() cross-check is done separately by the
// project's existing driver (node scripts/e2e-local.mjs audit), which
// owns its own temporary test. An LLM only explains findings, never
// scores: the score below comes from score() in audit.js, weights
// critical 25, high 15, medium 8, low 3.
//
// Usage:
//   node agent/audit.mjs --rpc http://127.0.0.1:26657 \
//     --realm gno.land/r/dunoil/adminbackdoor --file adminbackdoor.gno \
//     --local contracts/demo/adminbackdoor/adminbackdoor.gno \
//     --out agent/m5-work/adminbackdoor.json
//
// No money is spent here and nothing is submitted by this file.

import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { auditFile, score as jsScore } from "../ui/src/lib/audit.js";

function argValue(flag, fallback) {
  const i = process.argv.indexOf(flag);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}
function sha256Hex(text) {
  return createHash("sha256").update(text, "utf-8").digest("hex");
}
function hexEncode(str) {
  return [...new TextEncoder().encode(str)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
function base64Decode(b64) {
  return Buffer.from(b64, "base64").toString("utf-8");
}
async function abciQuery(rpc, path, data) {
  const url =
    `${rpc}/abci_query?path=${encodeURIComponent(JSON.stringify(path))}` +
    `&data=0x${hexEncode(data)}`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`RPC HTTP ${res.status} for ${path} ${data}`);
  const json = await res.json();
  const base = json?.result?.response?.ResponseBase;
  if (!base) throw new Error(`Unexpected RPC response shape for ${path} ${data}`);
  if (base.Error) {
    const log = (base.Log || "").replace(/\n/g, " | ").slice(0, 300);
    throw new Error(`Chain error for ${path} ${data}: ${log}`);
  }
  return base.Data ? base64Decode(base.Data) : "";
}
async function qfile(rpc, filepath) {
  return abciQuery(rpc, "vm/qfile", filepath);
}
function encodeFindings(findings) {
  return findings
    .map((f) => [f.ruleID, f.severity, f.line, f.title, f.description, f.sourceLine].join("|"))
    .join("\n");
}

const rpc = argValue("--rpc", "http://127.0.0.1:26657");
const realmPath = argValue("--realm", "");
const file = argValue("--file", "");
const localPath = argValue("--local", "");
const out = argValue("--out", "");
if (!realmPath || !file || !localPath || !out) {
  console.log("Usage: node agent/audit.mjs --rpc <url> --realm <path> --file <name> --local <path> --out <path>");
  process.exit(2);
}

let failures = 0;
const listing = await qfile(rpc, realmPath);
const names = listing.split("\n").map((s) => s.trim()).filter(Boolean);
if (!names.includes(file)) {
  console.log(`FAIL vm/qfile listing of ${realmPath} is missing ${file} (got: ${names.join(", ")})`);
  process.exit(1);
}
console.log(`PASS vm/qfile lists ${realmPath} (${names.join(", ")})`);

const fetched = await qfile(rpc, `${realmPath}/${file}`);
const local = readFileSync(localPath, "utf-8");
if (fetched === local) {
  console.log(`PASS vm/qfile source is byte-identical to ${localPath} (${fetched.length} bytes)`);
} else {
  console.log(`FAIL vm/qfile source differs from ${localPath} (chain ${fetched.length} bytes, local ${local.length} bytes)`);
  failures += 1;
}

const findings = auditFile(file, fetched);
const scoreValue = jsScore(findings);
console.log(`Audit result for ${realmPath}: score ${scoreValue}, ${findings.length} finding(s)`);
for (const f of findings) {
  console.log(`  finding: ${f.ruleID} ${f.severity} line ${f.line} ${f.title}`);
}
console.log(`  source SHA-256: ${sha256Hex(fetched)}`);
console.log(`  scoring weights: critical 25, high 15, medium 8, low 3 (100 minus the sum)`);

const result = {
  realmPath,
  file,
  sourceHash: sha256Hex(fetched),
  sourceBytes: fetched.length,
  score: scoreValue,
  findings,
  encoded: encodeFindings(findings),
};
mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, JSON.stringify(result, null, 2) + "\n", "utf-8");
console.log(`Wrote ${out}`);
if (failures > 0) process.exit(1);
console.log("Audit step PASSED.");
