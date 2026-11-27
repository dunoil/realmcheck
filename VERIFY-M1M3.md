# M1-M3 Re-verification (continuation coordinator, 27 Nov 2026)

Re-ran every M1-M3 claim from scratch. Result: NO discrepancies. All
numbers below were produced by the coordinator, not copied from the
first coordinator's notes.

## M1: environment

- `go version`: go1.25.9 linux/amd64
- `gnokey version`: v1.8.0
- `gnoland version`: v1.8.0
- `gnodev --help`: works (local and staging mode usage)
- Binaries present in ~/workspace/tools/gno/bin/: gno, gnodev, gnokey, gnoland
- ui/node_modules present (npm install already done)

## M2: audit rules and demo realms (gno test -p 1 .)

| Package | Tests passed |
| --- | --- |
| contracts/auditrules | 30 |
| contracts/demo/adminbackdoor | 5 |
| contracts/demo/greedystore | 4 |
| contracts/demo/luckydice | 6 |
| contracts/demo/unguardedvault | 4 |
| contracts/demo/vulnmint | 5 |
| contracts/realmcheck | 11 |

Demo total: 24, matching the claim. Full log: verify-m1m3-gno-tests.log.

## M3: report realm, UI, audit port, Onyx smoke

- `npm run build` in ui/: succeeds (vite, 18 modules, dist/ output).
- `node ui/scripts/test-audit-port.mjs`: all 5 demo realms match Gno
  Audit() exactly (adminbackdoor 3 findings, greedystore 1, luckydice 1,
  unguardedvault 1, vulnmint 1).
- `node ui/scripts/smoke-onyx.mjs` (live Onyx RPC):
  - gno.land/r/sys/params: 9 files, score 55/100, 3 findings, all RC-08
    high, run_submitters.gno lines 122, 151, 269. Matches the claim.
  - gno.land/r/gov/dao: 2 files, score 85/100, 1 finding, RC-08 high,
    types.gno:140. Matches the claim.
  - Full log: verify-m1m3-smoke-onyx.log.
- gnodev local end-to-end: gnodev-local.log shows a real SubmitReport
  transaction on gno.land/r/dunoil/realmcheck for vulnmint, RC-02
  critical line 41, score 75, response success:true, gas used
  7,854,767. Matches the realmcheck README.

## Known gaps carried into M4 (from ui/README.md, still open)

1. RC-03, RC-05, RC-06 never fire on the demo realms (split patterns
   the rules do not see; OriginSend never called by the demos).
2. False positives on guarded production code: assert* helpers are not
   guard tokens, DAO-proposal closures, methods on unexported types.
3. Adena signing is a stub (disabled button, gnokey command only).
4. Demo realm paths resolve only after the M6 Onyx deploy.

## Keys

- Local dev key exists: realmcheck-dev (local),
  g1yzqhuxczln72kwm9pstcmjerhnu0uverkuyz4h. This key is for gnodev
  local only. No Onyx-funded key exists yet; M6 deploy needs faucet
  funds, and the faucet (https://faucet.gno.land) requires a captcha,
  which is a browser step.
