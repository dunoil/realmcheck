# M4 local end-to-end status

Date: 27 Nov 2026. Last full harness run: 14:12 WITA (06:12 UTC).
Harness: `scripts/e2e-local.sh` (see `tests/e2e-local-checklist.md`
for the exact commands and pass criteria).

## Headline

The whole product loop works locally on a fresh gnodev chain, and the
UI env vars have landed and are verified. The run is NOT fully green
yet, for one known reason owned by other agents: the contracts agent
changed rule RC-03 mid-day (27 Nov 06:08 UTC) so it now fires on
adminbackdoor, and the JavaScript port plus `expected-findings.json`
have not caught up. The harness records that drift as FAIL lines and
still proves every chain step with the real Gno Audit() findings as
truth, using `E2E_CONTINUE_ON_AUDIT_MISMATCH=1`. A clean M4 run must
pass without that flag, after requested change 1 below is done.

## Harness files (owned by the e2e agent)

- `scripts/e2e-local.sh`: starts and stops its own gnodev and Vite
  dev server, stages and deploys the demo realms, submits both
  reports, verifies, checks the UI. Self-teeing log.
- `scripts/e2e-local.mjs`: audit driver (`audit`, `verify`,
  `latest` modes). vm/qfile source read, real Gno Audit() through a
  temporary test (`contracts/realmcheck/e2e_audit_test.gno`, deleted
  after every run), JS port audit, comparison against
  `ui/scripts/expected-findings.json`.
- `scripts/ui-local-audit.mjs`: runs the UI's own `fetchRealmFiles`
  plus `audit.js` under node against the configured RPC.
- `scripts/e2e-local-last-run.log`: full output of the latest run.
- `scripts/gnodev-e2e.log`: gnodev output of the latest run.
- `scripts/e2e-work/`: per-realm JSON, `reports.json`,
  `submits.txt`, `submit-<realm>.txt`, `addpkg-<realm>.txt`,
  `vite-dev.log`.
- `scripts/e2e-work-stage/`: staged demo realm copies for addpkg.
- `tests/e2e-local-checklist.md`: commands, pass criteria, manual
  browser step.

No file outside `scripts/`, `tests/`, and this status file was touched
by the e2e agent. In particular `contracts/**`, `ui/src/**`,
`ui/scripts/**`, and `ui/README.md` were not edited.

## Latest full run result (14:12 WITA, with the continue flag)

Chain: fresh gnodev local, chain ID dev, RPC
`http://127.0.0.1:26658`, gnoweb `http://127.0.0.1:8889`.
Baseline ReportCount 0. Port note: 127.0.0.1:26657 was already in use
by a pre-existing gnodev (pid 15600, started before this work, not
ours), so the harness used 26658 / 8889 and left that chain alone.
The coordinator's literal 26657 / 8888 applies when the port is free;
all env vars below were pointed at the harness chain actually used.

### Deploy (staged addpkg, vulnmint first)

| Realm | Gas used | Height | Tx hash |
| --- | --- | --- | --- |
| vulnmint | 6,785,211 | 3 | IScoKdTJ7LSx+3/GvmrolWIyB44DwyhyzNXJeGM3sVc= |
| adminbackdoor | 9,874,086 | 5 | fs115o2UPzGmjCte4a1BrYj6wUJ1cZOaGkqM6QsV6gc= |

### Audit (real Gno Audit() against the vm/qfile source)

| Realm | Score | Findings |
| --- | --- | --- |
| vulnmint | 75 | RC-02 critical line 41 Unrestricted mint |
| adminbackdoor | 37 | RC-01 high line 105 Sensitive function without caller check; RC-03 critical line 75 Single admin backdoor; RC-07 medium line 84 Unchecked external realm call; RC-08 high line 53 Public state mutation without guard |

Source hashes (SHA-256 of the exact source audited, byte-identical
between vm/qfile and the local files): vulnmint
`f8616d8b7c69e820e2b20aa49f970c8a7fe64e6e390367ae464f93db627f5b7e`,
adminbackdoor
`a90ab97b23f02dedac27504008afc93d0ecbbf4e4d2270346fe38f494e36cc90`.

vulnmint matches Gno Audit(), the JS port, and
`expected-findings.json` exactly. adminbackdoor matches on the Gno
side only; the JS port and `expected-findings.json` still say 3
findings, score 62 (see requested change 1).

### Submit (SubmitReport, auditor g1yzqhuxczln72kwm9pstcmjerhnu0uverkuyz4h)

| Report ID | Realm | Score | Findings | Gas wanted | Gas used | Height | Tx hash |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | vulnmint | 75 | 1 | 17,000,000 | 8,904,806 | 3 | 4V1s9MAC5jFXuhvmqERllSjTPcP5vFbDvAOgg733vQE= |
| 2 | adminbackdoor | 37 | 4 | 38,000,000 | 26,292,230 | 5 | RpQVsoJ14PC5/TRxaNAWRnU4WWVcMT1PU2Ns4vxEef8= |

### Verify (read back)

- ReportCount() is 2 (was 0, plus 2 new reports).
- GetReport(1) and GetReport(2): ID, realm path, source hash,
  score, auditor, and height all match what was submitted.
- ReportFindings(1) and ReportFindings(2) match the submitted
  encoding exactly (1 and 4 findings).
- LatestReport for each realm returns the new report with the right
  score and source hash.
- Render("") lists `#1 gno.land/r/dunoil/vulnmint score 75` and
  `#2 gno.land/r/dunoil/adminbackdoor score 37`.
- gnoweb `http://127.0.0.1:8889/r/dunoil/realmcheck` serves HTTP 200
  and lists both new reports.

### UI against the local chain (env vars landed)

- `ui/src/lib/gnoRpc.js` now reads `VITE_GNO_RPC`, `VITE_GNOWEB`,
  and `VITE_REALMCHECK_REALM`, defaulting to the Onyx values, and
  falls back to `process.env` under plain node. `ui/src/App.tsx`
  runs its live search path through `fetchRealmFiles` from that
  module.
- Dev server started with `VITE_GNO_RPC=http://127.0.0.1:26658`,
  `VITE_GNOWEB=http://127.0.0.1:8889`,
  `VITE_REALMCHECK_REALM=gno.land/r/dunoil/realmcheck` serves
  HTTP 200 on `http://127.0.0.1:5173/`.
- UI code-path audit under node: `fetchRealmFiles` returns the
  audited source for both realms (SHA-256 matches), and `audit.js`
  gives score 75 with 1 finding for vulnmint, identical to Gno
  Audit(). For adminbackdoor it gives score 62 with 3 findings,
  the known port drift (requested change 1).
- Note for the manual step: the UI demo buttons audit bundled
  `public/demo-sources/` files and never touch the chain. Only the
  search box and the `?realm=` deep link use the configured RPC.

### Run verdict

`RESULT: FAILED (1 failure(s))`, the single failure being the
adminbackdoor UI audit mismatch (score 62 vs 37). Everything else
in the run passed: 43 PASS lines in the log. The harness stopped its
own gnodev and dev server; all harness ports are free afterwards and
the temporary Gno test file is gone.

## Runs so far (idempotency evidence)

Five consecutive full runs, each starting a fresh chain, no leftover
state failing a later run:

1. 14:04 WITA: audit passed, submit failed. Two harness bugs found
   live: a 502 from `abci_query` simulation while gnodev was still
   reloading after the temp-test deletion, and adminbackdoor
   SubmitReport out of gas at gas-wanted 10,000,000 (used
   20,443,214). Fixed in the harness: settle wait after the reload
   plus submit retry on RPC errors, and gas scaled per finding.
2. 14:06 WITA: chain loop fully passed (reports 1 and 2, scores 75
   and 62 at that time). UI serve failed: Vite binds localhost
   only, unreachable by curl to 127.0.0.1. Fixed: `--host 127.0.0.1`.
3. 14:08 WITA: audit failed with the NEW RC-03 finding on
   adminbackdoor. The contracts agent had edited
   `contracts/auditrules/rules.gno` (06:08:11 UTC) and
   `auditrules.gno` (06:07:48 UTC) during the run.
4. 14:10 WITA: chain loop passed with the continue flag (scores 75
   and 37). UI serve failed on the Vite command lock: an orphaned
   vite child (pid 22592) from run 2 was still holding port 5173,
   because `npm run dev` had been killed but its vite child had not.
   Fixed: start vite directly and reap only orphaned vite processes
   for this project.
5. 14:12 WITA: as reported above. One more orphaned vite process
   (pid 17456, parent gone) was reaped before starting; it was not a
   live server.

Gas used varies slightly from run to run (vulnmint SubmitReport:
8,678,908, then 8,869,926, then 8,904,806). Addpkg gas and tx hashes
are identical across fresh-chain runs.

## Pending on other agents

- Manual browser click-through (needs a real browser). Exact steps
  in `tests/e2e-local-checklist.md`: open
  `http://127.0.0.1:5173/?realm=gno.land/r/dunoil/vulnmint` with the
  dev server pointed at a live local chain, check score 75 and the
  RC-02 finding, then search adminbackdoor and check score 37 with
  4 findings, then check the save-on-chain panel and the gnoweb
  link. Use the search box, not the demo buttons.
- Re-run the harness WITHOUT `E2E_CONTINUE_ON_AUDIT_MISMATCH` after
  requested changes 1 and 2 are done. Expected result: full PASS,
  `RESULT: PASSED (UI local-RPC check: configured)`.

## Requested changes to other agents' files

### 1. UI agent: port the new RC-03 shape to audit.js (blocks a clean run)

File: `ui/src/lib/audit.js`, function `checkAdminBackdoor`.
What changed in Gno: `contracts/auditrules/rules.gno`
`checkAdminBackdoor` now covers a second shape besides the old
stored-admin one. It tracks `adminConsts`: package-level admin or
owner variables whose declaration line contains a `"g1` address
literal (`auditrules.gno`, `adminConsts` list). When a function
compares against such a name (`firstHardcodedAdminDrain`), the first
drain or persistent state rewrite in that function is flagged: a
SendCoins or Withdraw call, a `.Set(`, `.Delete(`, or `.Remove(`
call, or an assignment to a package-level variable, skipping append
lines. The description text also changed to: "Function <name> lets
a single stored or hard-coded admin or owner drain funds or rewrite
state, with no timelock or multi-signature check on the path.
Consider a timelock, a multi-signature threshold, or a capped
withdrawal before deploying with real funds."
Why it fires now: adminbackdoor `Drain` compares
`caller != Admin` (Admin is `var Admin = address("g1...")` at line
31) and its first rewrite is `treasury = 0` at line 75, so Gno
Audit() returns RC-03 critical line 75. The JS port only has the
old stored-admin shape (adminVars plus SendCoins or Withdraw), so
it misses this finding entirely.
Requested: port the `adminConsts` tracking and the
`firstHardcodedAdminDrain` logic to `ui/src/lib/audit.js` with the
new description text, regenerate `ui/scripts/expected-findings.json`
with `python3 ui/scripts/generate-expected-findings.py`, and re-run
`node ui/scripts/test-audit-port.mjs`. Expected after the fix:
adminbackdoor 4 findings, score 37, port test green. This closes
known gap 1 from `VERIFY-M1M3.md` (RC-03 never fired).

### 2. Contracts agent: RC-08 regression, one auditrules unit test fails

File: `contracts/auditrules/rules.gno` (and/or `auditrules.gno`),
edited 27 Nov 06:07-06:08 UTC.
Evidence, verified by running `gno test -p 1 .` in
`contracts/auditrules`: exactly 1 failure,
`TestPublicMutationUnexportedReceiverClean`. It expects no RC-08
finding but now gets one: `Function SetProposal mutates realm state
but contains no caller check in its own body`, source line
`updated := ps.Set("1", p)` at line 8 of the test snippet.
`SetProposal` is a method on an unexported receiver type, which the
test name says must stay clean. This is known gap 2 from
`VERIFY-M1M3.md` (methods on unexported types). The realmcheck,
adminbackdoor, and vulnmint test suites still pass.
Requested: restore the unexported-receiver exemption for RC-08 (or
update the test if the new behavior is intended, and say so), so
`gno test -p 1 .` in `contracts/auditrules` is green again.

### 3. Contracts agent: delete the stale gno.mod files in the demo realms

Files: `contracts/demo/vulnmint/gno.mod`,
`contracts/demo/adminbackdoor/gno.mod`, and the same file in
`greedystore`, `luckydice`, and `unguardedvault` (each demo dir
ships both `gno.mod` and `gnomod.toml`).
Evidence: `gnokey maketx addpkg` for vulnmint fails on a local
chain with "gno.mod file is deprecated and not allowed, run 'gno
mod tidy' to upgrade to gnomod.toml", and `gnodev local
-extra-root contracts/demo` eager deploys all 5 demo packages with
the same "invalid package" failure, so `vm/qfile` for a demo realm
returns InvalidPackageError ("package not found"). The harness
works around it by deploying from a staged copy holding only the
`.gno` source and `gnomod.toml` (`scripts/e2e-work-stage/`), with
byte-identical source, so the audit and the stored source hash are
unaffected. After the stale files are deleted, the staging step can
go away and the demo realms will load from the workspace directly.

### 4. Docs: SubmitReport gas scales with the finding count

Files: `docs/API.md` and `contracts/realmcheck/README.md` (gas
notes). Both say to use gas-wanted 10000000 for SubmitReport, which
only covers one finding.
Measured on the local chain: 1 finding used 7,854,767 gas in the
first coordinator's run and 8,678,908 to 8,904,806 in later runs;
3 findings used 20,443,214 gas (out of gas at 10,000,000);
4 findings used 26,292,230 gas. The harness now uses gas-wanted
10,000,000 plus 7,000,000 per finding, with gas-fee at gas-wanted
divided by 500 (twice the 1 ugnot per 1,000 gas minimum).
Requested: document the scaling rule (or an equivalent formula) in
both gas notes, so a multi-finding report is not submitted with a
flat 10,000,000.

## Notes for the coordinator

- The RC-03 finding itself looks correct and intended: the demo's
  whole point is the single-admin drain, and the Gno rule change
  closes a documented gap. Only the port and the expected file are
  behind, plus the separate RC-08 test regression in request 2.
- Nothing was submitted or published. All transactions went to the
  harness's own fresh local chain, which was stopped at the end of
  each run. The pre-existing chain on 26657 (pid 15600) was never
  touched.
- The other agent's chain on 26657 already holds 1 report
  (vulnmint, score 75, from the first coordinator's run). That state
  was only read, never modified.
