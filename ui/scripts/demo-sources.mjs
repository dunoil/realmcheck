#!/usr/bin/env node
// demo-sources.mjs: build step that bundles the five deliberately
// vulnerable demo realms into the UI so they can be audited locally
// with no network and before their M6 Onyx deploy.
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
const expectedPath = join(here, "expected-findings.json");
const outDir = join(here, "..", "public", "demo-sources");

// One-line vulnerability blurb per demo realm, from
// contracts/demo/README.md. These describe the demo, not a score.
const DEMOS = [
  {
    name: "vulnmint",
    realmPath: "gno.land/r/dunoil/vulnmint",
    vulnerability:
      "A GRC20-like token whose Mint has no access control: anyone can mint any amount to any address.",
  },
  {
    name: "unguardedvault",
    realmPath: "gno.land/r/dunoil/unguardedvault",
    vulnerability:
      "A vault that credits deposits without verifying any payment, and lets anyone call Withdraw to take anyone's funds.",
  },
  {
    name: "greedystore",
    realmPath: "gno.land/r/dunoil/greedystore",
    vulnerability:
      "A registry that appends every entry to a persistent list with no cap, so storage grows without bound.",
  },
  {
    name: "luckydice",
    realmPath: "gno.land/r/dunoil/luckydice",
    vulnerability:
      "A dice game whose winning number comes from block height and block time, readable in advance by anyone.",
  },
  {
    name: "adminbackdoor",
    realmPath: "gno.land/r/dunoil/adminbackdoor",
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
  for (const file of files) {
    copyFileSync(join(srcDir, file), join(realmOut, file));
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
  note: "Local demo sources, bundled with the UI. These realms do not exist on Onyx yet; they deploy with the M6 release.",
  realms,
};
writeFileSync(join(outDir, "manifest.json"), JSON.stringify(manifest, null, 2) + "\n", "utf-8");
console.log(`demo-sources: wrote ${join(outDir, "manifest.json")} (${realms.length} realms)`);
