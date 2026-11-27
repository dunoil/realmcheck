# M6 Preparation Verification Record (27 Nov 2026)

M6 prep (the work that does not need faucet funds) is DONE. The Onyx
deploy itself is BLOCKED on two owner steps (section 4). Full agent
record in M6-PREP-STATUS.md.

## 1. Public repo: live and verified by the coordinator

- Repo: https://github.com/dunoil/realmcheck (public, MIT, main).
- Commits: 63dd690 (initial, 96 files), 6cc684f (M6 prep status).
  Remote HEAD verified by the coordinator with git ls-remote:
  6cc684f. Pushed tree has 97 files, no log or secret-named files.
- Secrets sweep (before the first commit): 4 log files contain a
  gnodev-generated throwaway default-account mnemonic
  (gnodev-local.log, agent/gnodev-m5.log, scripts/gnodev-e2e.log,
  scripts/gnodev-manual.log); all excluded by the *.log rule, none
  committed. The local dev key password `devpass` appears in 5 harness
  files by design (it unlocks only the local-only realmcheck-dev key);
  recorded as a known decision. No private keys, tokens, or .env
  secrets. The gno-mcp clone and scratch research stay out of the repo
  (nested git repo / reproducible sources, excluded by .gitignore).

## 2. Deploy script: validated by the coordinator

- scripts/deploy-onyx.sh --check, run by the coordinator: RESULT
  PASSED (dry-run plan printed, swap verified), exit 0. The plan
  shows all 7 packages (auditrules, realmcheck, vulnmint, greedystore,
  luckydice, unguardedvault, adminbackdoor) with the namespace swap
  and gas-wanted 70,000,000 / fee 140,000ugnot.
- Local --local run log (scripts/onyx-deploy-work/run-local-20261127-065149.log):
  RESULT PASSED. All 7 packages deployed and byte-verified on a fresh
  local chain. Gas used: auditrules 62,350,936, realmcheck 13,940,230,
  vulnmint 6,839,468, greedystore 5,964,958, luckydice 9,505,532,
  unguardedvault 8,164,126, adminbackdoor 10,015,702. Test report #1
  for vulnmint, score 75, RC-02@41, tx
  0u9wb3ChIWbIOL/GjlF/vOA765vZ8y0Viep56GbMpag=. Whole-deploy cost
  12,050,000ugnot (12.05 GNOT), so the 20 GNOT funding gate has margin.
  The first --local run failed usefully (auditrules out of gas at
  50,000,000 wanted, used 62,350,946), which set the 70,000,000 default.
- Onyx-mode funding gate tested live with the unfunded key: balance
  read 0ugnot via curl, faucet steps printed, exited BLOCKED, no
  transaction attempted.

## 3. Adena: implemented, stub-verified by the coordinator

- ui/src/lib/adena.js (+ adena.d.ts), researched from the published
  @adena-wallet/sdk 0.1.3 and @gnolang/gno-js-client 3.1.0 (research
  tarball in scratch/adena-sdk-research/). Direct window.adena calls
  (AddEstablish, GetAccount, GetNetwork, SwitchNetwork, AddNetwork,
  DoContract); no SDK dependency. Save panel in App.tsx has working
  states (not installed, connecting, connected, signing, signed with
  tx hash, error with retry); gnokey command stays as Option 1.
  gnoRpc.js untouched.
- Coordinator stub check: the agent's stub verification was a one-off
  invocation, not a saved script, so the coordinator wrote
  ui/scripts/test-adena-stub.mjs and ran it: PASS (connect, params,
  gas parity, submit). Verified: MsgCall caller is the connected
  address, pkg gno.land/r/dunoil/realmcheck, func SubmitReport,
  gas 1 finding 17,000,000/34,000 (matches buildSubmitCommand
  exactly), 4 findings 38,000,000/76,000, submit returns hash and
  height. (First attempt failed on the coordinator's own harness
  passing `caller` instead of `address`; the module was correct.)
- Not verified live: real extension connect/sign in a browser (needs
  Adena installed plus a funded Onyx key). Belongs to the M6 deploy
  phase.

## 4. The two blockers (both verified by the coordinator)

1. **Faucet funds (human browser step).** No Onyx-funded key exists.
   Fund a key at https://faucet.gno.land (paste the g1 address, pick
   Onyx, 100/200/300 GNOT, complete the captcha). Then run
   `bash scripts/deploy-onyx.sh --key <key-name> --deployer
   <g1-address>`. The script re-checks the balance first (20 GNOT
   gate).

2. **gnokey cannot reach Onyx from this VM (verified by the
   coordinator, not assumed).** The coordinator reproduced it:
   curl to https://rpc.onyx.testnets.gno.land/status returns valid
   JSON (proxy-aware), while `gnokey query vm/qeval` fails with
   `tls: first record does not look like a TLS handshake`, and direct
   `openssl s_client` fails with `wrong version number` and no peer
   certificate. Root cause, read from the toolchain source: gnokey's
   RPC client builds a custom http.Transport with no Proxy, so it
   ignores the VM's egress proxy (HTTP_PROXY/HTTPS_PROXY are set) and
   connects directly, and the direct path does not complete TLS. All
   read-only checks (curl, node) work because they honor the proxy;
   only gnokey's own network calls fail. Consequence: the real deploy
   must run from a machine with direct internet access (for example
   the owner's PC with the toolchain and the funded key). The deploy
   script probes gnokey reachability after the funding gate and stops
   with this diagnosis before any transaction.
   Candidate workaround for the parent to consider (not implemented):
   sign transactions offline with gnokey (no network needed for
   signing) and broadcast the signed bytes with curl (proxy-aware) to
   the RPC broadcast endpoint. The Adena path in a real browser also
   bypasses gnokey entirely for saving reports.

## 5. Coordinator checks at the close

- `npm run build` passes (282.03 kB JS, 85.98 kB gzip).
- `gno test -p 1 .`: auditrules 52 PASS, realmcheck 11 PASS.
- Audit-port test green on all 5 demo realms.
- No em dashes or en dashes in any new or edited file.
- The two recorded exec failures in the agent's run were the
  expected ones: the first --local out-of-gas run and the funding
  gate BLOCKED exit, both by design and documented.
- The repo was synced after the close: the coordinator's new files
  (ui/scripts/test-adena-stub.mjs, VERIFY-M6-PREP.md, BUILD-PLAN.md
  M6 update) were committed and pushed to origin/main.

## Still open

- The two blockers above (owner steps).
- Adena live test, post-deploy UI steps (point the build at the
  deployed report realm via VITE_REALMCHECK_REALM, redeploy to
  GitHub Pages, audit the demo realms live, update the README status
  line and the UI copy that says the demo realms do not exist on Onyx
  yet), and the gnomcp live verification on a machine where building
  it is allowed (from M5).
- M7 (15 Dec): demo video, full README, submission package. M8
  (17 Dec): package ready, reported for final approval. Submit
  18 Dec only after Duan's explicit final approval.
