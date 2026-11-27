# M4 Completion Record (27 Nov 2026)

Milestone M4 (due 7 Dec) is DONE ahead of schedule. Three parallel
pieces, all verified by the coordinator from scratch at the close.

## 1. Rules accuracy (M4-RULES-STATUS.md)

- RC-06 now follows randomness sources across calls in the same file
  (parameter taint, up to 8 hops). The split DrawNumber to
  DrawNumberAt pattern in luckydice is caught (line 69).
- RC-03 now also tracks hard-coded admin constants (admin/owner var
  initialized with an address literal) guarding a drain or state
  rewrite. adminbackdoor fires RC-03 critical at line 75.
- RC-05 now fires: unguardedvault.Deposit and luckydice.BuyChips read
  OriginSend and ignore the amount (banker setup in tests).
- False positives fixed: assert* calls count as guards; methods on
  unexported receiver types are never flagged; a method whose only
  mutations target its own receiver is not flagged. gov/dao types.gno:140
  and sys/params run_submitters.gno:122, 269 cleared.
- Deliberate exception: sys/params run_submitters.gno:151 stays flagged.
  The mutation sits inside a closure passed to newDelegateProposal; the
  gate is the DAO vote, which the scanner cannot see. No safe heuristic
  exists. Documented in rules.gno and the audit-rules README.
- Stale gno.mod files deleted from all five demo dirs (they broke
  addpkg and gnodev -extra-root on a plain chain).
- All 8 rules RC-01 to RC-08 fire on at least one demo realm.

## 2. UI polish (M4-UI-STATUS.md)

- Configurable endpoints: VITE_GNO_RPC, VITE_GNOWEB,
  VITE_REALMCHECK_REALM, defaulting to Onyx.
- "Explain this function" view on every finding card (enclosing
  function extracted client-side, finding line highlighted, plus
  plain-English risk, attacker view, what to check, fix pattern).
- Demo showcase: 5 demo realms as one-click cards auditing bundled
  local sources, scores computed from expected-findings.json, clearly
  labeled local demos, save-on-chain disabled for them.
- Share links: ?realm= and ?demo= deep links that auto-run the audit,
  copy-link button on reports.
- Hero, 8-rule catalog, cleaner footer. Adena stays a disabled stub
  (real signing comes with the M6 deploy).
- Verified in headless Chromium: ?demo=vulnmint renders the full
  report (score 75, explain expansion working); 390px mobile, zero
  overflowing elements.

## 3. Local end-to-end harness (M4-E2E-STATUS.md)

- scripts/e2e-local.sh + e2e-local.mjs + ui-local-audit.mjs, checklist
  in tests/e2e-local-checklist.md. Re-runnable, idempotent, starts
  and stops its own gnodev and Vite dev server.
- Final clean run (27 Nov, no mismatch flag): RESULT PASSED.
  Report #1 vulnmint score 75, 1 finding, gas used 8,904,806.
  Report #2 adminbackdoor score 37, 4 findings, gas used 26,292,230.
  ReportCount 2; GetReport, ReportFindings, LatestReport, Render all
  match; gnoweb report page HTTP 200; UI dev server HTTP 200 with
  local-RPC config; UI code path audits both realms identically to Gno.
- Coordinator fix at the close: the harness read ReportCount once and
  failed while gnodev was still loading (first qeval can 502 for
  about 13 seconds after start). Now retries 6 times, 5 seconds apart.
- Stray gnodev from the M3 run (pid 15600, holding 26657 and about
  540 MB RAM) was killed at the close; port 26657 is free again.

## Coordinator verification at the close (fresh runs, 27 Nov)

- Gno tests: auditrules 52 PASS (30 + 22 new regression tests);
  demos 5/4/7/5/5 = 26 PASS; realmcheck 11 PASS. Log:
  verify-m4-gno-tests.log.
- Audit-port test: all 5 demo realms match Gno Audit() exactly
  (adminbackdoor 4, greedystore 1, luckydice 3, unguardedvault 2,
  vulnmint 1). Rules mirror test: 24/24 pass.
- Live Onyx smoke test, realm sources unchanged (same SHA-256 as
  M1-M3): gov/dao 100/100, 0 findings (was 85/100); sys/params
  85/100, 1 finding (RC-08 run_submitters.gno:151, deliberate;
  was 55/100 with 3 findings).
- UI build passes (prebuild regenerates the demo manifest with the
  new scores: vulnmint 75, unguardedvault 70, greedystore 92,
  luckydice 62, adminbackdoor 37).
- Gas formula fixed everywhere it was flat: SubmitReport gas-wanted =
  10,000,000 + 7,000,000 per finding, gas-fee = gas-wanted / 500.
  Fixed in ui/src/lib/gnoRpc.js buildSubmitCommand (verified: 1
  finding gives 17,000,000 / 34,000ugnot; 4 findings gives 38,000,000
  / 76,000ugnot), docs/API.md, contracts/realmcheck/README.md, and
  ui/README.md. The old flat 10,000,000 only covered a one-finding
  report and would have failed out of gas on larger ones.
- ui/README.md synced: new smoke-test scores, new port-test table,
  both known-gap sections rewritten as fixed-in-M4 with the line 151
  exception, gas values updated.

## Ground truth after M4 (11 findings)

| Realm | Score | Findings |
| --- | --- | --- |
| vulnmint | 75 | RC-02@41 |
| unguardedvault | 70 | RC-05@48, RC-08@51 |
| greedystore | 92 | RC-04@47 |
| luckydice | 62 | RC-05@61, RC-06@69, RC-08@103 |
| adminbackdoor | 37 | RC-01@105, RC-03@75, RC-07@84, RC-08@53 |

## Still open (not blockers for M4)

- Manual browser click-through of the UI against a local chain
  (tests/e2e-local-checklist.md): open the dev server with local-RPC
  env vars, audit vulnmint via ?realm=, check score 75, then
  adminbackdoor, check score 37 with 4 findings. Needs a real browser.
- Live ?realm= render in a browser needs one recheck on a machine
  whose browser has internet (this VM's headless Chrome has no
  external internet; the node smoke test verifies the identical code
  path live, and ?demo= rendering is verified in headless Chrome).
- Clipboard write was not observed headless (needs a user gesture);
  button wiring and link construction are verified.
- M6 still needs Onyx faucet funds; the faucet
  (https://faucet.gno.land) requires a captcha, which is a browser
  step. No Onyx-funded key exists yet. Arrange before 12 Dec.
