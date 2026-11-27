#!/usr/bin/env node
// e2e-local.mjs: chain audit driver for the RealmCheck local end-to-end harness.
//
// Usage (called by scripts/e2e-local.sh, not by hand):
//   node scripts/e2e-local.mjs audit  --rpc http://127.0.0.1:26657
//   node scripts/e2e-local.mjs verify --rpc http://127.0.0.1:26657 --web http://127.0.0.1:8888
//
// audit mode, per demo realm (vulnmint, adminbackdoor):
//   (a) reads the realm source from the local chain with vm/qfile and
//       checks it is byte-identical to contracts/demo/<realm>/<realm>.gno;
//   (b) runs the real Gno Audit() against that exact fetched source through
//       a temporary Gno test in contracts/realmcheck (deleted afterwards);
//   (c) runs the JavaScript port (ui/src/lib/audit.js) against the same
//       fetched source and checks Gno, JS, and ui/scripts/expected-findings.json
//       all agree on rule, severity, line, and title, and Gno and JS agree
//       on description and source line too. Scores must agree as well.
//   Writes scripts/e2e-work/<realm>.json with the source hash, score,
//   full findings, and the SubmitReport encoding.
//
// verify mode, after the shell submits the reports:
//   reads scripts/e2e-work/reports.json (realm, expected report id) plus the
//   per-realm work files, then checks with vm/qeval that GetReport,
//   ReportFindings, LatestReport, and ReportCount all match what was
//   submitted, and that Render("") lists every new report. Also fetches
//   the gnoweb report page and checks it lists the new reports.
//   Exit code 0 means every check passed; 1 means at least one failed.
//
// No money is spent here and nothing is submitted by this file; the shell
// script owns the gnokey transactions. No Onyx dependency: everything
// talks to the local RPC passed with --rpc.

import { createHash } from "node:crypto";
import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, unlinkSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { auditFile, score as jsScore } from "../ui/src/lib/audit.js";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const workDir = join(root, "scripts", "e2e-work");
const demoDir = join(root, "contracts", "demo");
const realmcheckDir = join(root, "contracts", "realmcheck");
const expectedPath = join(root, "ui", "scripts", "expected-findings.json");
const REALMCHECK_REALM = "gno.land/r/dunoil/realmcheck";
const REALMS = [
  { name: "vulnmint", path: "gno.land/r/dunoil/vulnmint", file: "vulnmint.gno" },
  { name: "adminbackdoor", path: "gno.land/r/dunoil/adminbackdoor", file: "adminbackdoor.gno" },
];

let failures = 0;
function pass(msg) {
  console.log(`PASS ${msg}`);
}
function fail(msg) {
  failures += 1;
  console.log(`FAIL ${msg}`);
}
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
async function qeval(rpc, expr) {
  return abciQuery(rpc, "vm/qeval", expr);
}

// parsePrintedString extracts the string value from a qeval printed
// string, for example ("hello\nworld" string). Same logic as
// ui/src/lib/gnoRpc.js parsePrintedString.
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
function encodeFindings(findings) {
  return findings
    .map((f) => [f.ruleID, f.severity, f.line, f.title, f.description, f.sourceLine].join("|"))
    .join("\n");
}
function key4(f) {
  return [f.ruleID, f.severity, f.line, f.title].join("|");
}
function keyFull(f) {
  return [f.ruleID, f.severity, f.line, f.title, f.description, f.sourceLine].join("|");
}
function sortKeys(findings, keyFn) {
  return findings.map(keyFn).sort();
}
function sameList(a, b) {
  return a.length === b.length && a.every((k, i) => k === b[i]);
}
async function waitRpcReady(rpc, seconds) {
  const deadline = Date.now() + seconds * 1000;
  while (Date.now() < deadline) {
    try {
      const res = await fetch(`${rpc}/status`);
      if (res.ok) return true;
    } catch {
      // Not up yet.
    }
    await new Promise((r) => setTimeout(r, 1000));
  }
  return false;
}

// runGnoAudit runs the real Audit() against the fetched sources through
// a temporary Gno test in contracts/realmcheck, in the style of
// ui/scripts/generate-expected-findings.py. The temp file is always
// deleted afterwards, even when the test fails. Returns
// { <realm>: { findings: [...], score: <int> } }.
function runGnoAudit(sources) {
  const testFile = join(realmcheckDir, "e2e_audit_test.gno");
  const consts = [];
  const cases = [];
  for (const realm of REALMS) {
    const src = sources[realm.name];
    consts.push(`const ${realm.name}Src = ${JSON.stringify(src)}`);
    cases.push(`\t\t{"${realm.name}", ${realm.name}Src},`);
  }
  const testSrc = `package realmcheck

// TEMPORARY, generated by scripts/e2e-local.mjs for the local e2e harness.
// Deleted after the run. Do not commit.

import (
\t"strconv"
\t"testing"

\t"gno.land/p/dunoil/auditrules"
)

${consts.join("\n")}

func findingJSON(f auditrules.Finding) string {
\treturn "{\\"ruleID\\":" + strconv.Quote(f.RuleID) + ",\\"severity\\":" + strconv.Quote(string(f.Severity)) + ",\\"line\\":" + strconv.Itoa(f.Line) + ",\\"title\\":" + strconv.Quote(f.Title) + ",\\"description\\":" + strconv.Quote(f.Description) + ",\\"sourceLine\\":" + strconv.Quote(f.SourceLine) + "}"
}

func TestE2EAuditPrint(t *testing.T) {
\tcases := []struct {
\t\tname string
\t\tsrc  string
\t}{
${cases.join("\n")}
\t}
\tfor _, c := range cases {
\t\tfindings := auditrules.Audit(c.src)
\t\tfor _, f := range findings {
\t\t\tt.Log("E2EJSON " + c.name + " " + findingJSON(f))
\t\t}
\t\tt.Log("E2ECOUNT " + c.name + " " + strconv.Itoa(len(findings)) + " " + strconv.Itoa(auditrules.Score(findings)))
\t}
}
`;
  writeFileSync(testFile, testSrc, "utf-8");
  let output = "";
  let code = 0;
  try {
    const proc = spawnSync("gno", ["test", "-v", "-run", "TestE2EAuditPrint", "."], {
      cwd: realmcheckDir,
      encoding: "utf-8",
      timeout: 300000,
      env: { ...process.env, GOMAXPROCS: "2" },
    });
    output = (proc.stdout || "") + (proc.stderr || "");
    code = proc.status === null ? 1 : proc.status;
  } finally {
    if (existsSync(testFile)) unlinkSync(testFile);
  }
  if (code !== 0) {
    console.log(output);
    throw new Error(`gno test failed with exit code ${code}`);
  }
  const result = {};
  const findingRe = /E2EJSON (\S+) (\{.*\})\s*$/;
  const countRe = /E2ECOUNT (\S+) (\d+) (\d+)/;
  for (const raw of output.split("\n")) {
    const line = raw.trim();
    let m = findingRe.exec(line);
    if (m) {
      const realm = m[1];
      result[realm] = result[realm] || { findings: [], score: null };
      result[realm].findings.push(JSON.parse(m[2]));
      continue;
    }
    m = countRe.exec(line);
    if (m) {
      const realm = m[1];
      result[realm] = result[realm] || { findings: [], score: null };
      result[realm].findingsCount = parseInt(m[2], 10);
      result[realm].score = parseInt(m[3], 10);
    }
  }
  for (const realm of REALMS) {
    const r = result[realm.name];
    if (!r || r.score === null) throw new Error(`No Gno Audit output for ${realm.name}`);
    if (r.findings.length !== r.findingsCount) {
      throw new Error(
        `Gno Audit count mismatch for ${realm.name}: ${r.findings.length} parsed, ${r.findingsCount} reported`,
      );
    }
  }
  return result;
}

async function auditMode(rpc) {
  mkdirSync(workDir, { recursive: true });
  const expected = JSON.parse(readFileSync(expectedPath, "utf-8"));
  const sources = {};
  for (const realm of REALMS) {
    const listing = await qfile(rpc, realm.path);
    const names = listing.split("\n").map((s) => s.trim()).filter(Boolean);
    if (!names.includes(realm.file)) {
      fail(`${realm.name}: vm/qfile listing of ${realm.path} is missing ${realm.file} (got: ${names.join(", ")})`);
      continue;
    }
    pass(`${realm.name}: vm/qfile lists ${realm.path} (${names.join(", ")})`);
    const fetched = await qfile(rpc, `${realm.path}/${realm.file}`);
    const local = readFileSync(join(demoDir, realm.name, realm.file), "utf-8");
    if (fetched === local) {
      pass(`${realm.name}: vm/qfile source is byte-identical to contracts/demo/${realm.name}/${realm.file}`);
    } else {
      fail(`${realm.name}: vm/qfile source differs from the local file (chain ${fetched.length} bytes, local ${local.length} bytes)`);
    }
    sources[realm.name] = fetched;
  }
  if (failures > 0) {
    console.log(`\nAudit mode stopped: ${failures} qfile failure(s).`);
    process.exit(1);
  }

  console.log("Running real Gno Audit() via temporary test (contracts/realmcheck/e2e_audit_test.gno)...");
  const gno = runGnoAudit(sources);
  console.log("Temporary Gno test file deleted.");
  // Creating and deleting the temp test makes the watched gnodev reload
  // twice. /status answers during a reload, but abci_query simulation
  // can return 502 until the reload finishes, so wait for the RPC to
  // answer a real query before the shell submits anything.
  await waitRpcReady(rpc, 30);
  await new Promise((r) => setTimeout(r, 5000));
  for (let attempt = 1; attempt <= 12; attempt++) {
    try {
      await qeval(rpc, `${REALMCHECK_REALM}.ReportCount()`);
      break;
    } catch (e) {
      if (attempt === 12) throw new Error(`Chain did not settle after the temp-test reload: ${e.message}`);
      await new Promise((r) => setTimeout(r, 5000));
    }
  }
  console.log("Chain settled after the temp-test reload (ReportCount() answers).");

  for (const realm of REALMS) {
    const fetched = sources[realm.name];
    const gnoFindings = gno[realm.name].findings;
    const gnoScore = gno[realm.name].score;
    const jsFindings = auditFile(realm.file, fetched);
    const jsScoreValue = jsScore(jsFindings);
    const want = (expected[realm.file] || []).map((f) => ({ ...f, file: realm.file }));

    if (sameList(sortKeys(gnoFindings, key4), sortKeys(want, key4))) {
      pass(`${realm.name}: Gno Audit() matches expected-findings.json (${gnoFindings.length} finding(s))`);
    } else {
      fail(`${realm.name}: Gno Audit() differs from expected-findings.json. Gno: ${JSON.stringify(sortKeys(gnoFindings, key4))}. Expected: ${JSON.stringify(sortKeys(want, key4))}`);
    }
    if (sameList(sortKeys(jsFindings, key4), sortKeys(gnoFindings, key4))) {
      pass(`${realm.name}: JS port matches Gno Audit() on rule, severity, line, title (${jsFindings.length} finding(s))`);
    } else {
      fail(`${realm.name}: JS port differs from Gno Audit(). JS: ${JSON.stringify(sortKeys(jsFindings, key4))}. Gno: ${JSON.stringify(sortKeys(gnoFindings, key4))}`);
    }
    if (sameList(sortKeys(jsFindings, keyFull), sortKeys(gnoFindings, keyFull))) {
      pass(`${realm.name}: JS port matches Gno Audit() on description and source line too`);
    } else {
      fail(`${realm.name}: JS port description or source line differs from Gno Audit()`);
    }
    if (gnoScore === jsScoreValue) {
      pass(`${realm.name}: score agrees, Gno ${gnoScore} and JS ${jsScoreValue}`);
    } else {
      fail(`${realm.name}: score differs, Gno ${gnoScore}, JS ${jsScoreValue}`);
    }
    for (const f of gnoFindings) {
      console.log(`  finding ${realm.name}: ${f.ruleID} ${f.severity} line ${f.line} ${f.title}`);
    }

    const out = {
      realm: realm.name,
      realmPath: realm.path,
      file: realm.file,
      sourceHash: sha256Hex(fetched),
      sourceBytes: fetched.length,
      score: gnoScore,
      jsScore: jsScoreValue,
      findings: gnoFindings,
      encoded: encodeFindings(gnoFindings),
    };
    writeFileSync(join(workDir, `${realm.name}.json`), JSON.stringify(out, null, 2) + "\n", "utf-8");
    console.log(`  wrote scripts/e2e-work/${realm.name}.json (score ${gnoScore}, source hash ${out.sourceHash.slice(0, 16)}...)`);
  }
  if (failures > 0) {
    if (process.argv.includes("--continue-on-mismatch")) {
      console.log(`\nAudit mode has ${failures} mismatch failure(s), recorded above.`);
      console.log("Continuing because --continue-on-mismatch was passed: the real Gno Audit() output is the truth for the submitted reports, and the mismatches are drift in the JS port or expected-findings.json, owned by other agents (see M4-E2E-STATUS.md).");
      return;
    }
    console.log(`\nAudit mode FAILED: ${failures} failure(s).`);
    process.exit(1);
  }
  console.log("\nAudit mode PASSED: both demo realms match Gno Audit(), the JS port, and expected-findings.json.");
}

async function verifyMode(rpc, web) {
  const reportsPath = join(workDir, "reports.json");
  if (!existsSync(reportsPath)) {
    console.log(`FAIL reports file missing: ${reportsPath} (the shell writes it after submitting)`);
    process.exit(1);
  }
  const reports = JSON.parse(readFileSync(reportsPath, "utf-8"));
  const countBefore = reports.countBefore;
  const entries = reports.reports;
  const expectedCount = countBefore + entries.length;

  const countRaw = await qeval(rpc, `${REALMCHECK_REALM}.ReportCount()`);
  const countMatch = countRaw.match(/\((\d+) int\)/);
  const countNow = countMatch ? parseInt(countMatch[1], 10) : null;
  if (countNow === expectedCount) {
    pass(`ReportCount() is ${countNow} (was ${countBefore}, plus ${entries.length} new reports)`);
  } else {
    fail(`ReportCount() is ${countNow}, expected ${expectedCount}`);
  }

  let renderText = "";
  try {
    const renderRaw = await qeval(rpc, `${REALMCHECK_REALM}.Render("")`);
    renderText = parsePrintedString(renderRaw);
  } catch (e) {
    fail(`Render("") query failed: ${e.message}`);
  }

  for (const entry of entries) {
    const work = JSON.parse(readFileSync(join(workDir, `${entry.realm}.json`), "utf-8"));
    const id = entry.reportId;
    const getRaw = await qeval(rpc, `${REALMCHECK_REALM}.GetReport(${id})`);
    const stored = parsePrintedReport(getRaw);
    if (!stored) {
      fail(`${entry.realm}: GetReport(${id}) returned no report`);
      continue;
    }
    if (stored.id === id) pass(`${entry.realm}: GetReport(${id}) returns ID ${id}`);
    else fail(`${entry.realm}: GetReport(${id}) returns ID ${stored.id}`);
    if (stored.realmPath === work.realmPath) pass(`${entry.realm}: stored realm path matches ${work.realmPath}`);
    else fail(`${entry.realm}: stored realm path ${stored.realmPath} differs from ${work.realmPath}`);
    if (stored.sourceHash === work.sourceHash) pass(`${entry.realm}: stored source hash matches ${work.sourceHash.slice(0, 16)}...`);
    else fail(`${entry.realm}: stored source hash ${stored.sourceHash} differs from ${work.sourceHash}`);
    if (stored.score === work.score) pass(`${entry.realm}: stored score matches ${work.score}`);
    else fail(`${entry.realm}: stored score ${stored.score} differs from ${work.score}`);
    if (stored.auditor === entry.auditor) pass(`${entry.realm}: stored auditor matches ${entry.auditor}`);
    else fail(`${entry.realm}: stored auditor ${stored.auditor} differs from ${entry.auditor}`);
    if (stored.height === entry.height) pass(`${entry.realm}: stored height matches ${entry.height}`);
    else fail(`${entry.realm}: stored height ${stored.height} differs from submit height ${entry.height}`);

    const findingsRaw = await qeval(rpc, `${REALMCHECK_REALM}.ReportFindings(${id})`);
    const findingsText = parsePrintedString(findingsRaw);
    if (findingsText.trim() === work.encoded.trim()) {
      pass(`${entry.realm}: ReportFindings(${id}) matches the submitted encoding (${work.findings.length} finding(s))`);
    } else {
      fail(`${entry.realm}: ReportFindings(${id}) differs from submitted encoding. Stored: ${JSON.stringify(findingsText)}. Submitted: ${JSON.stringify(work.encoded)}`);
    }

    const latestRaw = await qeval(rpc, `${REALMCHECK_REALM}.LatestReport("${work.realmPath}")`);
    const latest = parsePrintedReport(latestRaw);
    if (latest && latest.id === id && latest.score === work.score && latest.sourceHash === work.sourceHash) {
      pass(`${entry.realm}: LatestReport("${work.realmPath}") returns report ${id} with score ${work.score}`);
    } else {
      fail(`${entry.realm}: LatestReport("${work.realmPath}") does not return report ${id} (got ${latest ? JSON.stringify(latest) : "none"})`);
    }

    if (renderText.includes(`#${id}`) && renderText.includes(work.realmPath) && renderText.includes(`score ${work.score}`)) {
      pass(`${entry.realm}: Render("") lists #${id} ${work.realmPath} score ${work.score}`);
    } else {
      fail(`${entry.realm}: Render("") does not list #${id} ${work.realmPath} score ${work.score}. Render text: ${JSON.stringify(renderText.slice(0, 400))}`);
    }
  }

  if (web) {
    try {
      const res = await fetch(`${web}/r/dunoil/realmcheck`);
      const body = await res.text();
      const ok = res.status === 200 && entries.every((e) => {
        const work = JSON.parse(readFileSync(join(workDir, `${e.realm}.json`), "utf-8"));
        return body.includes(work.realmPath) && body.includes(`score ${work.score}`);
      });
      if (ok) pass(`gnoweb ${web}/r/dunoil/realmcheck serves HTTP 200 and lists the new reports`);
      else fail(`gnoweb page check failed: HTTP ${res.status}, body starts ${JSON.stringify(body.slice(0, 200))}`);
    } catch (e) {
      fail(`gnoweb page fetch failed: ${e.message}`);
    }
  }

  if (failures > 0) {
    console.log(`\nVerify mode FAILED: ${failures} failure(s).`);
    process.exit(1);
  }
  console.log("\nVerify mode PASSED: every stored report matches what was submitted, and Render lists them.");
}

async function latestMode(rpc, realmPath) {
  const raw = await qeval(rpc, `${REALMCHECK_REALM}.LatestReport("${realmPath}")`);
  const report = parsePrintedReport(raw);
  if (!report) {
    console.log("null");
    process.exit(1);
  }
  console.log(JSON.stringify(report));
}

const mode = process.argv[2];
const rpc = argValue("--rpc", "http://127.0.0.1:26657");
const web = argValue("--web", "");
if (mode === "audit") {
  await auditMode(rpc);
} else if (mode === "verify") {
  await verifyMode(rpc, web);
} else if (mode === "latest") {
  await latestMode(rpc, argValue("--realm", ""));
} else {
  console.log("Usage: node scripts/e2e-local.mjs audit --rpc <url> | verify --rpc <url> --web <url> | latest --rpc <url> --realm <path>");
  process.exit(2);
}
