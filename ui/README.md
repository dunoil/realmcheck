# RealmCheck UI

The web UI for RealmCheck, the Gno.land realm auditor built for the
Gnome Tavern Hackathon. Paste any realm path, and the UI fetches the
realm source live from the Onyx testnet, audits it in the browser, and
shows a report page with a risk score and findings that cite exact
source lines. Reports can be saved on chain in the RealmCheck report
realm, and anyone can load a stored report later.

## Run

```sh
npm install
npm run dev     # serves on http://localhost:5173
npm run build   # static output in dist/
npm run preview # serves the production build
```

Node 24 and npm 10 are on the VM. No backend is needed; the UI talks
directly to the Onyx testnet RPC.

## Verified Onyx endpoints

Chain ID `onyx-1`. RPC: `https://rpc.onyx.testnets.gno.land`.
gnoweb: `https://onyx.testnets.gno.land`. Faucet:
`https://faucet.gno.land`.

- `GET /abci_query?path="vm/qfile"&data=0x<hex of file path>` returns
  the file listing for a directory, or the file source for a file.
  The result is in `result.response.ResponseBase.Data` (base64); an
  error is in `result.response.ResponseBase.Error`. The data parameter
  must be 0x-prefixed hex, or the call fails with "illegal base64
  data".
- `GET /abci_query?path="vm/qeval"&data=0x<hex of expression>` returns
  the printed value in the same Data field. `qeval_json` returns
  structured JSON, but struct fields are positional and slices are
  references, so this UI uses plain `qeval` plus the report realm's
  `ReportFindings` function, which re-encodes findings as text.

Realms confirmed to exist on Onyx (27 Nov 2026):
`gno.land/r/sys/params`, `gno.land/r/gov/dao`. Confirmed absent:
`gno.land/r/demo/boards`, `gno.land/r/demo/microblog`,
`gno.land/r/demo/foo20`, `gno.land/r/gnoland/home`,
`gno.land/r/sys/validators/v3`. The five demo realms
(`gno.land/r/dunoil/vulnmint`, `unguardedvault`, `greedystore`,
`luckydice`, `adminbackdoor`) deploy to Onyx with the full release;
until then they are audited locally by the port test below.

Live smoke test (`node ui/scripts/smoke-onyx.mjs`, 27 Nov 2026),
which runs the same `fetchRealmFiles` + `audit.js` path as the UI:

- `gno.land/r/gov/dao`: 2 files, score 100/100, 0 findings (re-checked
  27 Nov 2026 after the M4 RC-08 receiver-target fix; was 85/100 with
  1 finding, RC-08 `types.gno:140`).
- `gno.land/r/sys/params`: 9 files, score 85/100, 1 finding (RC-08,
  `run_submitters.gno:151`, the DAO-proposal closure case, kept on
  purpose; was 55/100 with 3 findings). Realm sources unchanged
  (same SHA-256 as the M1-M3 check); only the rules improved.

Test files (`*_test.gno`) are never fetched: test code legitimately
calls realms without guards and ignores return values, so auditing it
only produces noise. On `sys/params`, 15 of 18 findings came from
test files alone (score 0/100 before the exclusion).

## Audit port test results

`src/lib/audit.js` is a plain JavaScript port of the on-chain audit
rules (`contracts/auditrules`, rules RC-01 to RC-08), written in plain
JavaScript on purpose so the same file runs in the browser and under
plain Node. The port was verified against the real Gno `Audit()`:

```sh
node ui/scripts/test-audit-port.mjs
```

Result, 27 Nov 2026 (M4 rules): all five demo realms match `Audit()` exactly.

| Realm | Findings | Rules fired |
| --- | --- | --- |
| vulnmint.gno | 1 | RC-02 critical, line 41 |
| unguardedvault.gno | 2 | RC-05 high, line 48; RC-08 high, line 51 |
| greedystore.gno | 1 | RC-04 medium, line 47 |
| luckydice.gno | 3 | RC-05 high, line 61; RC-06 medium, line 69; RC-08 high, line 103 |
| adminbackdoor.gno | 4 | RC-01 high line 105, RC-03 critical line 75, RC-07 medium line 84, RC-08 high line 53 |

Scores: vulnmint 75, unguardedvault 70, greedystore 92, luckydice 62,
adminbackdoor 37. All eight rules RC-01 to RC-08 fire on at least one
demo realm (M4 fixed the three blind spots below).

Ground truth is `ui/scripts/expected-findings.json`, generated from
the real Gno `Audit()` by
`ui/scripts/generate-expected-findings.py` (temporary Gno test,
deleted after the run). Regenerate after any rule change, then rerun
the port test. The vulnmint result (RC-02, line 41, score 75) also
matches the earlier on-chain end-to-end test on `gnodev local`.

## Fixed in M4: all eight rules now fire on the demo realms

RC-03 (single admin backdoor), RC-05 (funds accepted without a
check), and RC-06 (weak randomness) used to never fire on the demo
realms. Fixed 27 Nov 2026:

- RC-06 now follows randomness sources across calls in the same file
  (parameter taint, up to eight hops), so the split `DrawNumber` to
  `DrawNumberAt` pattern in `luckydice` is caught (RC-06, line 69).
- RC-05 now fires because `unguardedvault.Deposit` and
  `luckydice.BuyChips` read `OriginSend` and ignore the amount
  (banker setup in their tests proves the claimed amount lands).
- RC-03 now also tracks hard-coded admin constants (an admin or owner
  variable initialized with an address literal) guarding a drain or
  state rewrite, so `adminbackdoor` fires RC-03 at line 75.

All eight rules fire on at least one demo realm. The JavaScript port
mirrors the Gno behavior exactly, including these fixes (port test
green).

## Fixed in M4: false positives on guarded production code (one deliberate exception)

The scanner used to flag state mutations it could not see a guard
for. Fixed 27 Nov 2026, verified live on Onyx (realm sources
unchanged):

- `assert*` calls now count as guards, so `sys/params`
  `run_submitters.gno:269` (`RemoveRunSubmitters`, guarded by
  `assertDelegate`) and `:122` (guarded by `assertDelegatePath` in
  the enclosing function) no longer fire.
- Methods on unexported receiver types are never flagged, and a
  method whose only mutations target its own receiver is not flagged,
  so `gov/dao` `types.gno:140` (`SetProposal`, which mutates only its
  own receiver) no longer fires. Note: `Proposals` is exported by
  name (capital P), so the name-based skip does not cover it; the
  receiver-target refinement is what clears it.

Deliberate exception: `sys/params` `run_submitters.gno:151` stays
flagged on purpose. The mutation is inside a closure passed to
`newDelegateProposal`; the gate is the DAO vote, which the scanner
cannot see. No safe heuristic exists: trusting the callee name would
hide a real finding in a realm that invokes the closure immediately.
Documented in `rules.gno` and the audit-rules README.

## What is still a stub

- **Adena signing.** The "Save this report on chain" panel shows the
  exact `gnokey maketx call` command, which works today with a funded
  Onyx key (gas-wanted 10000000 plus 7000000 per finding, gas-fee
  gas-wanted divided by 500; the chain enforces a minimum gas price
  of 1 ugnot per 1000 gas). The Adena connect button is present but
  disabled, marked as coming with the full release.
- **Demo realm paths.** The example chips use `gno.land/r/gov/dao`
  (100/100) and `gno.land/r/sys/params` (85/100), which exist on Onyx
  today. The demo realm paths in the UI text
  (`gno.land/r/dunoil/vulnmint`, ...) resolve once phase 6 deploys
  them to Onyx.

## Files

- `src/lib/audit.js`: JavaScript port of the audit rules (RC-01 to
  RC-08, score weights, limits). No dependencies.
- `src/lib/gnoRpc.js`: read-only Onyx RPC helpers (`qfile`, `qeval`,
  `fetchRealmFiles`, findings encoding, printed-report parsing,
  submit-command builder).
- `src/App.tsx`: search page, audit flow, report page with score
  gauge and findings grouped by severity, save-on-chain panel, stored
  report view.
- `scripts/test-audit-port.mjs`: port verification, see above.
- `scripts/generate-expected-findings.py`: regenerates the ground
  truth from the real Gno `Audit()`.
- `scripts/expected-findings.json`: ground truth for the port test.
