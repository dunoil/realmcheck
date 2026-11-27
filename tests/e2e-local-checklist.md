# RealmCheck local end-to-end checklist (M4)

Proves the whole product loop on a local gnodev chain, with no Onyx
dependency and no money spent. The harness is
`scripts/e2e-local.sh`; it drives `scripts/e2e-local.mjs` (chain audit
driver) and `scripts/ui-local-audit.mjs` (UI code-path audit).

## Prerequisites

- Toolchain on PATH (see `ENV-TOOLCHAIN.md`):
  `export PATH=$PATH:$HOME/workspace/tools/go/bin:$HOME/workspace/tools/gno/bin`
  `export GNOROOT=$HOME/workspace/tools/gno`
  `export GOMAXPROCS=2`
- Local dev key `realmcheck-dev` present (`gnokey list` shows
  `g1yzqhuxczln72kwm9pstcmjerhnu0uverkuyz4h`). Local chain only.
- Node 24 (for the audit driver and the UI code-path audit).
- No chain needs to be running first. If port 26657 is already in use
  by another agent's gnodev, the harness starts its own chain on
  26658 / 8889 instead and never touches the other chain.

## Run the harness

From the project root:

```bash
cd ~/workspace/gnome-tavern-hackathon
bash scripts/e2e-local.sh
```

Full output is also written to `scripts/e2e-local-last-run.log`.
Exit code 0 means every step passed. The run takes about 2 minutes.

If another agent has changed the audit rules and the JavaScript port
has not caught up yet, the audit comparison fails by design. To still
prove the chain loop with the real Gno Audit() findings as truth, run:

```bash
E2E_CONTINUE_ON_AUDIT_MISMATCH=1 bash scripts/e2e-local.sh
```

Mismatches stay visible as FAIL lines in the log. Remove the flag
once the port is fixed; a clean M4 run must pass without it.

## What a pass looks like, step by step

### 0. Chain starts

- `PASS Local chain RPC is up` and `PASS Local gnoweb is up`.
- `PASS Baseline ReportCount() is 0 on the fresh chain`.
- Fail looks like: `FAIL Local chain RPC did not come up within 120s`.
  Check `scripts/gnodev-e2e.log`.

### 1. Demo realms deploy (staged addpkg)

- `PASS Staged vulnmint source is byte-identical to contracts/demo/vulnmint/vulnmint.gno.`
- `PASS Staged adminbackdoor source is byte-identical to contracts/demo/adminbackdoor/adminbackdoor.gno.`
- `PASS addpkg vulnmint succeeded (gas used about 6,785,211, height 3).`
- `PASS addpkg adminbackdoor succeeded (gas used about 9,874,086, height 5).`
- Why staged: `contracts/demo/*/` still ships a stale `gno.mod` next
  to `gnomod.toml`, and the chain rejects addpkg for such a package
  with "gno.mod file is deprecated and not allowed". The harness
  stages a copy holding only the `.gno` source and `gnomod.toml`
  under `scripts/e2e-work-stage/`. See the requested fix in
  `M4-E2E-STATUS.md`.
- Deploy order matters: vulnmint first, adminbackdoor imports it.

### 2. Audit driver (a) vm/qfile, (b) Gno Audit(), (c) JS port audit

- `PASS vulnmint: vm/qfile lists gno.land/r/dunoil/vulnmint (gnomod.toml, vulnmint.gno)`
- `PASS vulnmint: vm/qfile source is byte-identical to contracts/demo/vulnmint/vulnmint.gno`
- Same two lines for adminbackdoor.
- `PASS vulnmint: Gno Audit() matches expected-findings.json (1 finding(s))`
- `PASS vulnmint: JS port matches Gno Audit() on rule, severity, line, title (1 finding(s))`
- `PASS vulnmint: JS port matches Gno Audit() on description and source line too`
- `PASS vulnmint: score agrees, Gno 75 and JS 75`
- Finding: `RC-02 critical line 41 Unrestricted mint`.
- `PASS adminbackdoor: Gno Audit() matches expected-findings.json (4 finding(s))`
- Same JS match lines, score agrees, Gno 37 and JS 37 (after the
  RC-03 port fix; before the fix the JS side says 62 with 3 findings,
  see `M4-E2E-STATUS.md`).
- Findings: `RC-01 high line 105 Sensitive function without caller check`,
  `RC-03 critical line 75 Single admin backdoor`,
  `RC-07 medium line 84 Unchecked external realm call`,
  `RC-08 high line 53 Public state mutation without guard`.
- Per-realm work files: `scripts/e2e-work/vulnmint.json`,
  `scripts/e2e-work/adminbackdoor.json` (source hash, score, full
  findings, SubmitReport encoding).
- The temporary Gno test `contracts/realmcheck/e2e_audit_test.gno`
  is created and deleted by the driver. After the run,
  `ls contracts/realmcheck/ | grep e2e` must print nothing.

### 3. Submit (d) SubmitReport on chain

- `PASS SubmitReport vulnmint stored as report ID 1 (score 75, gas wanted 17000000, gas used about 8,900,000, height 3).`
- `PASS SubmitReport adminbackdoor stored as report ID 2 (score 37, gas wanted 38000000, gas used about 26,300,000, height 5).`
- Gas scales with findings: 1 finding used about 8.9M gas,
  4 findings about 26.3M. Gas-wanted is 10,000,000 plus 7,000,000
  per finding, fee is gas-wanted divided by 500. The flat
  10,000,000 in `docs/API.md` only covers one finding.
- Gas used varies slightly from run to run (a few tens of thousands).
  Report IDs are 1 and 2 on a fresh chain; on a reused chain they
  follow the baseline count.

### 4. Verify (e) read back, (f) Render

- `PASS ReportCount() is 2 (was 0, plus 2 new reports)`
- Per realm: `GetReport(<id>)` returns the ID, realm path, source
  hash, score, auditor
  `g1yzqhuxczln72kwm9pstcmjerhnu0uverkuyz4h`, and height;
  `ReportFindings(<id>)` matches the submitted encoding exactly;
  `LatestReport("<realm path>")` returns the new report;
  `Render("")` lists `#<id> <realm path> score <score>`.
- `PASS gnoweb http://127.0.0.1:8889/r/dunoil/realmcheck serves HTTP 200 and lists the new reports`
  (or port 8888 when the standard ports were free).
- `Verify mode PASSED` at the end of this section.

### 5. UI dev server against the local chain

- `PASS UI dev server serves HTTP 200 on http://127.0.0.1:5173/ (local-RPC config: configured).`
- `UI endpoints in effect: GNO_RPC=http://127.0.0.1:26658 GNO_GNOWEB=http://127.0.0.1:8889 REALMCHECK_REALM=gno.land/r/dunoil/realmcheck`
  (or 26657 / 8888 when the standard ports were free).
- `PASS vulnmint: UI fetchRealmFiles returns the audited source (SHA-256 f8616d8b7c69e820...).`
- `PASS vulnmint: UI audit.js on the fetched source gives score 75 and the same 1 finding(s) as Gno Audit().`
- Same two lines for adminbackdoor (score 37, 4 findings, after the
  RC-03 port fix).
- `UI local audit PASSED` at the end of this section.
- The dev server is started with `--host 127.0.0.1` and stopped by
  the harness. Vite is started directly, not through `npm run dev`,
  so its process is really stopped. Orphaned vite processes for this
  project (parent gone, working directory `ui/`) are reaped before
  starting; a live server owned by another agent is never touched.

### 6. Summary

- `RESULT: PASSED (UI local-RPC check: configured)`
- `INFO Stopped gnodev (pid ...).` The harness stops only the chain
  it started. Harness ports (26658 / 8889 / 5173) are free afterwards.

## Re-running

The harness is safe to run twice in a row. Every run starts a fresh
local chain, so report IDs start over and no leftover state can fail
the next run. Work files under `scripts/e2e-work/` and
`scripts/e2e-work-stage/` are overwritten each run.

## Manual browser step (needs a real browser, not scripted)

The harness stops its own chain at the end, so start a chain and the
UI by hand for this step. If port 26657 is free, use the standard
ports; if it is busy, use 26658 / 8889 everywhere below instead.

```bash
cd ~/workspace/gnome-tavern-hackathon
export PATH=$PATH:$HOME/workspace/tools/go/bin:$HOME/workspace/tools/gno/bin
export GNOROOT=$HOME/workspace/tools/gno
export GOMAXPROCS=2

# 1. Local chain (same flags as the harness)
cd contracts
gnodev local -add-account g1yzqhuxczln72kwm9pstcmjerhnu0uverkuyz4h=100000000ugnot
# Leave it running. In a second terminal:

# 2. Deploy the demo realms from the staged copy the harness built
#    (run the harness once first if scripts/e2e-work-stage/ is empty)
cd ~/workspace/gnome-tavern-hackathon
printf 'devpass\n' | gnokey maketx addpkg -insecure-password-stdin \
  -pkgpath "gno.land/r/dunoil/vulnmint" -pkgdir "scripts/e2e-work-stage/vulnmint" \
  -gas-fee 40000ugnot -gas-wanted 20000000 -chainid dev -remote 127.0.0.1:26657 realmcheck-dev
printf 'devpass\n' | gnokey maketx addpkg -insecure-password-stdin \
  -pkgpath "gno.land/r/dunoil/adminbackdoor" -pkgdir "scripts/e2e-work-stage/adminbackdoor" \
  -gas-fee 40000ugnot -gas-wanted 20000000 -chainid dev -remote 127.0.0.1:26657 realmcheck-dev

# 3. UI dev server pointed at the local chain
cd ui
VITE_GNO_RPC=http://127.0.0.1:26657 VITE_GNOWEB=http://127.0.0.1:8888 \
  VITE_REALMCHECK_REALM=gno.land/r/dunoil/realmcheck \
  ./node_modules/.bin/vite --host 127.0.0.1 --port 5173 --strictPort
```

Then, in a real browser:

1. Open `http://127.0.0.1:5173/?realm=gno.land/r/dunoil/vulnmint`.
   The page must auto-run a live audit and show score 75, one
   finding (RC-02 critical, line 41, Unrestricted mint), and the
   source hash starting `f8616d8b`.
2. In the search box, paste `gno.land/r/dunoil/adminbackdoor` and
   run the audit. It must show score 37 and four findings (RC-01
   line 105, RC-03 line 75, RC-07 line 84, RC-08 line 53). Before
   the RC-03 port fix it shows score 62 and three findings instead.
3. Do NOT use the demo buttons for this check: they audit the
   bundled `public/demo-sources/` files and never touch the chain.
   Only the search box (and the `?realm=` deep link) uses the
   configured RPC.
4. On the vulnmint report page, open the "Save this report on
   chain" panel. It must show the `gnokey maketx call` command for
   `gno.land/r/dunoil/realmcheck` with the local realm path and
   score 75. Do not run a submit from the browser in this step; the
   harness already proves SubmitReport on chain.
5. Follow the gnoweb link on the report page. It must open the local
   gnoweb report list at `http://127.0.0.1:8888/r/dunoil/realmcheck`
   and list the stored reports.
6. Stop the chain and the dev server (Ctrl-C in each terminal) when
   done. Nothing from this manual step is submitted or published.

## Files

- `scripts/e2e-local.sh`: the harness. Starts and stops its own
  gnodev and Vite dev server, deploys, submits, verifies.
- `scripts/e2e-local.mjs`: audit driver (`audit`, `verify`,
  `latest` modes). Temp Gno test, qfile/qeval, comparisons.
- `scripts/ui-local-audit.mjs`: runs the UI's own `fetchRealmFiles`
  plus `audit.js` under node against the configured RPC.
- `scripts/e2e-local-last-run.log`: full output of the latest run.
- `scripts/gnodev-e2e.log`: gnodev output of the latest run.
- `scripts/e2e-work/`: per-realm JSON (`vulnmint.json`,
  `adminbackdoor.json`), `reports.json`, `submits.txt`,
  `submit-<realm>.txt`, `addpkg-<realm>.txt`, `vite-dev.log`.
- `scripts/e2e-work-stage/`: staged demo realm copies for addpkg
  (only `.gno` source plus `gnomod.toml`, byte-identical source).
- `M4-E2E-STATUS.md`: latest results, pending items, requested
  changes to other agents' files.
