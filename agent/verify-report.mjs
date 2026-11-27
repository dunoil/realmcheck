#!/usr/bin/env node
// verify-report.mjs: RealmCheck agent-mode verify step.
//
// Reads a stored report back from a live chain with vm/qeval and checks
// it against the audit work file written by agent/audit.mjs: GetReport,
// ReportFindings, LatestReport, ReportCount, and Render(""), plus the
// gnoweb report page. Read-only: no gas, no key, nothing submitted.
//
// Usage:
//   node agent/verify-report.mjs --rpc http://127.0.0.1:26657 \
//     --web http://127.0.0.1:8888 --work agent/m5-work/adminbackdoor.json \
//     --id 1 --height 12 --count 1 --auditor g1yzqhuxczln72kwm9pstcmjerhnu0uverkuyz4h
//
// Exit code 0 means every check passed; 1 means at least one failed.

import { readFileSync } from "node:fs";

function argValue(flag, fallback) {
  const i = process.argv.indexOf(flag);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
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
async function qeval(rpc, expr) {
  return abciQuery(rpc, "vm/qeval", expr);
}
function parsePrintedString(text) {
  if (!text) return "";
  const m = text.match(/\("((?:\\.|[^"\\])*)" string\)/);
  if (!m) return "";
  try {
    return JSON.parse(`"${m[1]}"`);
  } catch {
    return m[1]
      .replace(/\\n/g, "\n")
      .replace(/\\t/g, "\t")
      .replace(/\\"/g, '"')
      .replace(/\\\\/g, "\\");
  }
}
function parsePrintedReport(text) {
  if (!text || text.includes("(false bool)")) return null;
  const strings = [...text.matchAll(/\("([^"]*)" string\)/g)].map((m) => m[1]);
  const ints = [...text.matchAll(/\((\d+) int\)/g)].map((m) => parseInt(m[1], 10));
  const int64s = [...text.matchAll(/\((\d+) int64\)/g)].map((m) => parseInt(m[1], 10));
  if (strings.length < 3 || ints.length < 2) return null;
  return {
    id: ints[0],
    realmPath: strings[0],
    sourceHash: strings[1],
    score: ints[1],
    auditor: strings[2],
    height: int64s.length > 0 ? int64s[0] : 0,
  };
}

const rpc = argValue("--rpc", "http://127.0.0.1:26657");
const web = argValue("--web", "");
const workPath = argValue("--work", "");
const id = parseInt(argValue("--id", ""), 10);
const height = parseInt(argValue("--height", ""), 10);
const count = parseInt(argValue("--count", ""), 10);
const auditor = argValue("--auditor", "");
if (!workPath || Number.isNaN(id)) {
  console.log("Usage: node agent/verify-report.mjs --rpc <url> --web <url> --work <path> --id <n> --height <n> --count <n> --auditor <g1...>");
  process.exit(2);
}
const REALMCHECK_REALM = "gno.land/r/dunoil/realmcheck";
const work = JSON.parse(readFileSync(workPath, "utf-8"));

let failures = 0;
function pass(msg) {
  console.log(`PASS ${msg}`);
}
function fail(msg) {
  failures += 1;
  console.log(`FAIL ${msg}`);
}

const countRaw = await qeval(rpc, `${REALMCHECK_REALM}.ReportCount()`);
const countMatch = countRaw.match(/\((\d+) int\)/);
const countNow = countMatch ? parseInt(countMatch[1], 10) : null;
if (!Number.isNaN(count) && countNow === count) {
  pass(`ReportCount() is ${countNow} (expected ${count})`);
} else if (Number.isNaN(count)) {
  console.log(`INFO ReportCount() is ${countNow} (no expected count given)`);
} else {
  fail(`ReportCount() is ${countNow}, expected ${count}`);
}

const getRaw = await qeval(rpc, `${REALMCHECK_REALM}.GetReport(${id})`);
const stored = parsePrintedReport(getRaw);
if (!stored) {
  fail(`GetReport(${id}) returned no report`);
} else {
  if (stored.id === id) pass(`GetReport(${id}) returns ID ${id}`);
  else fail(`GetReport(${id}) returns ID ${stored.id}`);
  if (stored.realmPath === work.realmPath) pass(`stored realm path matches ${work.realmPath}`);
  else fail(`stored realm path ${stored.realmPath} differs from ${work.realmPath}`);
  if (stored.sourceHash === work.sourceHash) pass(`stored source hash matches ${work.sourceHash.slice(0, 16)}...`);
  else fail(`stored source hash ${stored.sourceHash} differs from ${work.sourceHash}`);
  if (stored.score === work.score) pass(`stored score matches ${work.score}`);
  else fail(`stored score ${stored.score} differs from ${work.score}`);
  if (auditor && stored.auditor === auditor) pass(`stored auditor matches ${auditor}`);
  else if (auditor) fail(`stored auditor ${stored.auditor} differs from ${auditor}`);
  if (!Number.isNaN(height) && stored.height === height) pass(`stored height matches ${height}`);
  else if (!Number.isNaN(height)) fail(`stored height ${stored.height} differs from submit height ${height}`);
}

const findingsRaw = await qeval(rpc, `${REALMCHECK_REALM}.ReportFindings(${id})`);
const findingsText = parsePrintedString(findingsRaw);
if (findingsText.trim() === work.encoded.trim()) {
  pass(`ReportFindings(${id}) matches the submitted encoding (${work.findings.length} finding(s))`);
} else {
  fail(`ReportFindings(${id}) differs from submitted encoding. Stored: ${JSON.stringify(findingsText)}. Submitted: ${JSON.stringify(work.encoded)}`);
}

const latestRaw = await qeval(rpc, `${REALMCHECK_REALM}.LatestReport("${work.realmPath}")`);
const latest = parsePrintedReport(latestRaw);
if (latest && latest.id === id && latest.score === work.score && latest.sourceHash === work.sourceHash) {
  pass(`LatestReport("${work.realmPath}") returns report ${id} with score ${work.score}`);
} else {
  fail(`LatestReport("${work.realmPath}") does not return report ${id} (got ${latest ? JSON.stringify(latest) : "none"})`);
}

let renderText = "";
try {
  const renderRaw = await qeval(rpc, `${REALMCHECK_REALM}.Render("")`);
  renderText = parsePrintedString(renderRaw);
} catch (e) {
  fail(`Render("") query failed: ${e.message}`);
}
if (renderText && renderText.includes(`#${id}`) && renderText.includes(work.realmPath) && renderText.includes(`score ${work.score}`)) {
  pass(`Render("") lists #${id} ${work.realmPath} score ${work.score}`);
} else if (renderText) {
  fail(`Render("") does not list #${id} ${work.realmPath} score ${work.score}. Render text: ${JSON.stringify(renderText.slice(0, 400))}`);
}

if (web) {
  try {
    const res = await fetch(`${web}/r/dunoil/realmcheck`);
    const body = await res.text();
    if (res.status === 200 && body.includes(work.realmPath) && body.includes(`score ${work.score}`)) {
      pass(`gnoweb ${web}/r/dunoil/realmcheck serves HTTP 200 and lists #${id} ${work.realmPath} score ${work.score}`);
    } else {
      fail(`gnoweb page check failed: HTTP ${res.status}, body starts ${JSON.stringify(body.slice(0, 200))}`);
    }
  } catch (e) {
    fail(`gnoweb page fetch failed: ${e.message}`);
  }
}

if (failures > 0) {
  console.log(`\nVerify step FAILED: ${failures} failure(s).`);
  process.exit(1);
}
console.log("\nVerify step PASSED: the stored report matches what was submitted, and Render lists it.");
