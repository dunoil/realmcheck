#!/usr/bin/env node
// demo-sources.mjs: build step that bundles the five deliberately
// vulnerable demo realms into the UI as a fallback for when the live
// Onyx fetch fails. The realms are live on Onyx under the deployer
// namespace (verified 27 Nov 2026); the bundled copies are used only
// on a live-fetch failure, and the report then says so.
//
// What it does:
//   - copies every non-test .gno source from contracts/demo/<realm>/ into
//     ui/public/demo-sources/<realm>/ (test files are excluded: they
//     legitimately call realms without guards and only add noise)
//   - writes ui/public/demo-sources/manifest.json listing each realm with
//     its vulnerability blurb, its files, its expected findings taken
//     from ui/scripts/expected-findings.json, and its expected score
//     computed from those findings with the same score() as the audit
//     port, so scores are never hardcoded and stay in sync when the
//     audit rules change.
//
// Run from the project root: node ui/scripts/demo-sources.mjs
// It also runs automatically before every build (package.json prebuild).
// Exit code 0 on success, 1 on any missing source or manifest error.

import { copyFileSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { score } from "../src/lib/audit.js";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..", "..");
const demoDir = join(root, "contracts", "demo");
// The deploy stages byte-exact copies of what went on chain in
// scripts/offline-work/stage/ (namespace swap included). When the
// stage exists, bundle those bytes so the fallback is byte-identical
// to the deployed source; otherwise fall back to the repo copies
// (a fresh clone has no stage directory, and the audit result is the
// same either way: the swap changes only import paths and addresses,
// never a finding or a line number).
const stageDir = join(root, "scripts", "offline-work", "stage");
const expectedPath = join(here, "expected-findings.json");
const outDir = join(here, "..", "public", "demo-sources");

// One-line vulnerability blurb per demo realm, from
// contracts/demo/README.md. These describe the demo, not a score.
const DEMOS = [
  {
    name: "vulnmint",
    realmPath: "gno.land/r/g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu/vulnmint",
    vulnerability:
      "A GRC20-like token whose Mint has no access control: anyone can mint any amount to any address.",
  },
  {
    name: "unguardedvault",
    realmPath: "gno.land/r/g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu/unguardedvault",
    vulnerability:
      "A vault that credits deposits without verifying any payment, and lets anyone call Withdraw to take anyone's funds.",
  },
  {
    name: "greedystore",
    realmPath: "gno.land/r/g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu/greedystore",
    vulnerability:
      "A registry that appends every entry to a persistent list with no cap, so storage grows without bound.",
  },
  {
    name: "luckydice",
    realmPath: "gno.land/r/g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu/luckydice",
    vulnerability:
      "A dice game whose winning number comes from block height and block time, readable in advance by anyone.",
  },
  {
    name: "adminbackdoor",
    realmPath: "gno.land/r/g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu/adminbackdoor",
    vulnerability:
      "A treasury where a single hard-coded admin can drain all funds at once, and bonus payouts ignore the result of an external realm call.",
  },
];

const expected = JSON.parse(readFileSync(expectedPath, "utf-8"));

mkdirSync(outDir, { recursive: true });

const realms = [];
for (const demo of DEMOS) {
  const srcDir = join(demoDir, demo.name);
  const files = readdirSync(srcDir)
    .filter((n) => n.endsWith(".gno") && !n.endsWith("_test.gno"))
    .sort();
  if (files.length === 0) {
    console.error(`demo-sources: no non-test .gno files in ${srcDir}`);
    process.exit(1);
  }
  const realmOut = join(outDir, demo.name);
  mkdirSync(realmOut, { recursive: true });
  // Prefer the staged (deployed) bytes when they exist.
  let staged = 0;
  for (const file of files) {
    const stagedFile = join(stageDir, demo.name, file);
    try {
      copyFileSync(stagedFile, join(realmOut, file));
      staged++;
    } catch {
      copyFileSync(join(srcDir, file), join(realmOut, file));
    }
  }
  if (staged === files.length) {
    console.log(`demo-sources: ${demo.name}: bundled from the deployed stage (byte-identical to Onyx)`);
  }
  // Expected findings for this realm, from expected-findings.json,
  // keyed by file name. The expected score is computed from them with
  // the audit port's own score(), never hardcoded.
  const expectedFindings = files.flatMap((file) =>
    (expected[file] || []).map((f) => ({ ...f, file })),
  );
  const expectedScore = score(expectedFindings);
  realms.push({
    name: demo.name,
    realmPath: demo.realmPath,
    vulnerability: demo.vulnerability,
    files,
    expectedFindings,
    expectedScore,
  });
  console.log(
    `demo-sources: ${demo.name}: ${files.join(", ")} -> ${expectedFindings.length} expected finding(s), score ${expectedScore}/100`,
  );
}

const manifest = {
  generatedAt: new Date().toISOString(),
  note: "Fallback demo sources, bundled with the UI. These realms are live on Onyx at the paths above; the bundled copies are used only when the live fetch fails, and the report then says so.",
  realms,
};
writeFileSync(join(outDir, "manifest.json"), JSON.stringify(manifest, null, 2) + "\n", "utf-8");
console.log(`demo-sources: wrote ${join(outDir, "manifest.json")} (${realms.length} realms)`);
