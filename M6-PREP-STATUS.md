# M6 preparation status (27 Nov 2026)

M6 preparation work that does not need faucet funds, done 27 Nov 2026.
The Onyx deploy itself is still blocked (see section 5). Nothing in this
milestone spent money, submitted anything, published anything, or did any
KYC. Everything below was verified with real runs, not by reading code
alone.

## 1. Public repo: created and pushed

- Repo: https://github.com/dunoil/realmcheck (public, MIT, default branch
  `main`).
- Initial commit `63dd690` (96 files): RealmCheck M1 to M5, the new
  README, `.gitignore`, the deploy script, the Onyx deploy checklist,
  and the Adena signing implementation. Pushed `main -> main`, branch
  tracking `origin/main`.
- The `gh` CLI was authenticated on this VM (`gh auth status`: logged in
  to github.com as dunoil, token scopes gist, read:org, repo), so the
  repo was created with `gh repo create realmcheck --public` and pushed
  with `git push -u origin main`. One snag: `gh repo create` without
  `--source` did not add the `origin` remote, so the first push failed
  with no remote configured. Fixed with `git remote add origin
  https://github.com/dunoil/realmcheck.git`, then the push succeeded.
- This status file is a second commit on top of the initial commit.

### Secrets sweep (before the first commit)

Swept the whole project for private keys, mnemonics, passwords, and
tokens (pattern grep plus a per-file review of the hits).

Found:

- **Four log files contain a gnodev-generated default-account mnemonic**
  (line 3 of each): `gnodev-local.log`, `agent/gnodev-m5.log`,
  `scripts/gnodev-e2e.log`, `scripts/gnodev-manual.log`. The mnemonic
  belongs to gnodev's throwaway local test account
  (`g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5`), but a mnemonic is a
  mnemonic: none of these files is committed. They are excluded by the
  `*.log` rule in `.gitignore`.
- **The local dev key password `devpass`** appears in five files
  (`scripts/e2e-local.sh`, `agent/run-audit-local.sh`,
  `agent/SKILL.md`, `contracts/realmcheck/README.md`,
  `tests/e2e-local-checklist.md`). It unlocks only the `realmcheck-dev`
  key, which exists solely in this VM's gnokey keybase, holds funds only
  on throwaway local chains, and is useless anywhere else. The harness
  scripts need it for non-interactive local runs, so those files stay as
  M4 and M5 wrote them. Recorded here so the presence is a known
  decision, not an oversight.
- No private key files, no `.pem` or `.key` files, no GitHub or API
  tokens (`gho_`, `ghp_`), no `.env` files with secrets (only the
  upstream clone's `.env.example`, which is a template). The
  `package-lock.json` integrity hashes that matched a broad base64
  pattern are npm sha512 hashes, public by design.

Excluded by `.gitignore` (verified with `git check-ignore` per path):

- `*.log` and `*.pid` (the four mnemonic logs, all run logs, the stale
  `scripts/gnodev-manual.pid`).
- Work dirs: `scripts/e2e-work/`, `scripts/e2e-work-stage/`,
  `scripts/onyx-deploy-work/`, `agent/m5-work/`, `agent/stage/`,
  `m4-verify/`, `scratch/` (includes the Adena SDK research tarballs
  and extracted packages; reproducible with `npm pack`).
- `agent/gno-mcp-upstream/`: the read-only gno-mcp reference clone. It
  is a nested git repo (has its own `.git`) and 10 MB; it is not
  committed. Re-clone at the pinned commit `e065fbc` to reproduce it.
- `ui/node_modules/` and `ui/dist/` (also covered by the pre-existing
  `ui/.gitignore`).

Cleanliness proof: after `git add -A`, `git status` showed 96 staged
files and nothing else pending, and a grep over the staged file list
for secret patterns (private key headers, `gho_`/`ghp_` tokens,
`mnemonic=` followed by words) found nothing. Every `mnemonic` mention
in the staged files is prose (instructions to safeguard a mnemonic),
not a value.

## 2. Onyx deploy script and checklist (dry-run and local-chain validated)

New files: `scripts/deploy-onyx.sh` and `docs/ONYX-DEPLOY.md`.

### The script

`scripts/deploy-onyx.sh` deploys in order (auditrules, realmcheck,
vulnmint, greedystore, luckydice, unguardedvault, adminbackdoor), swaps
the `dunoil` namespace to the deployer g1 address in every module path,
in the realmcheck import, and in the adminbackdoor import and
`PackageAddress` call, and replaces the placeholder Admin address in
adminbackdoor with the deployer address. The swap runs on staged copies
under `scripts/onyx-deploy-work/stage/`; `contracts/**` is never edited.
The script verifies the swap (no `dunoil` and no placeholder address may
remain, and every changed line must be a swap line) before any deploy.

Gas: addpkg uses gas-wanted 70,000,000 and gas-fee 140,000ugnot for
every package. SubmitReport uses the docs/API.md formula (10,000,000
plus 7,000,000 per finding, fee wanted/500). After each addpkg the
script fetches the on-chain file listing and byte-diffs every staged
`.gno` file against the on-chain copy over `abci_query vm/qfile`. After
realmcheck it submits a test report for vulnmint built with the UI's own
JS audit port (ground truth: score 75, RC-02 at line 41), then checks
`ReportCount()`, `LatestReport`, `ReportFindings`, and `Render("")`.

Safety: Onyx mode refuses to run without a funded key. It checks the
key exists in `gnokey list`, checks the key address matches
`--deployer`, reads the on-chain balance, and requires at least 20 GNOT
(20,000,000ugnot). Below that it prints the faucet URL and the exact
funding steps and exits without attempting any transaction. It also
probes gnokey reachability to the Onyx RPC before any transaction (see
section 5). Re-running the script is idempotent: a failed addpkg is
followed by a check whether the package already exists on chain with
identical content, in which case that step counts as deployed.

### Validation evidence

- `bash scripts/deploy-onyx.sh --check`: PASSED. Stages all 7 packages,
  verifies the swap, prints the full plan, no chain contact. (One fix
  during validation: the swap-diff check first flagged the original
  placeholder Admin line as an unexpected diff; the check now allows
  the known placeholder on removed lines.)
- `bash scripts/deploy-onyx.sh --local`, first run: FAILED exactly as a
  validation run should. auditrules ran out of gas at gas-wanted
  50,000,000 (used 62,350,946; the chain suggested 65,468,494), and
  realmcheck then failed type checking because its auditrules import was
  not on chain yet. The other five demo realms deployed and verified in
  that run. The failure set the 70,000,000 default.
- `bash scripts/deploy-onyx.sh --local`, second run: PASSED, exit 0,
  `RESULT: PASSED (Onyx deploy complete and verified)`. Fresh local
  gnodev chain from an empty directory (RPC 127.0.0.1:26659, gnoweb
  127.0.0.1:8890), namespace swapped to the local deployer
  `g1yzqhuxczln72kwm9pstcmjerhnu0uverkuyz4h`. All 7 packages deployed
  and byte-verified. Gas used: auditrules 62,350,936, realmcheck
  13,940,230, vulnmint 6,839,468, greedystore 5,964,958, luckydice
  9,505,532, unguardedvault 8,164,126, adminbackdoor 10,015,702. Test
  SubmitReport stored as report #1 for the deployed vulnmint path:
  score 75, RC-02@41, auditor the deployer address, gas wanted
  17,000,000, used 9,271,707, tx
  `0u9wb3ChIWbIOL/GjlF/vOA765vZ8y0Viep56GbMpag=`. ReportCount 0 to 1,
  LatestReport, ReportFindings, and Render all checked. The chain was
  stopped afterwards; no stray gnodev left running.
- Measured whole-deploy cost on the local chain: 12,050,000ugnot
  (11,749,300 for the 7 addpkg transactions plus 300,700 for the test
  SubmitReport). The 20 GNOT funding gate leaves margin for Onyx-side
  differences. The per-package table is in `docs/ONYX-DEPLOY.md`.
- Onyx-mode funding gate, tested live with the unfunded key
  `realmcheck-dev` on 27 Nov 2026: the script read the on-chain balance
  (0ugnot) through the curl path, printed the faucet steps, and exited
  with `RESULT: BLOCKED (funds missing, faucet step above)`, exit code
  1. No transaction was attempted.
- Full run logs are in `scripts/onyx-deploy-work/run-<mode>-*.log`
  (gitignored work dir).

### The checklist

`docs/ONYX-DEPLOY.md` holds the exact commands for the real run, the
namespace swap table, the measured gas and cost table, the faucet steps
(URL, captcha, amounts 100/200/300 GNOT per request), the verification
steps, and the rollback and retry notes (already-exists check, out of
gas, type check failure, refused transactions, the immutable-package
rule, mid-run funding loss, and the post-deploy steps for the UI).

## 3. Adena signing in the UI (implemented, live test pending)

New files: `ui/src/lib/adena.js` and `ui/src/lib/adena.d.ts`. Edited:
the save panel only, in `ui/src/App.tsx`. `ui/src/lib/gnoRpc.js` was
not touched.

### Research (docs and code, not memory)

The official Adena docs are at https://docs.adena.app and the SDK is
`@adena-wallet/sdk`. The published 0.1.3 package was inspected
(`npm pack @adena-wallet/sdk@0.1.3`, README plus `bin/index.d.ts` and
`bin/index.mjs`), and the `MsgCall` field shape was confirmed from its
dependency `@gnolang/gno-js-client` 3.1.0
(`dist/proto/gno/vm.d.mts`). Verified API surface:

- The extension injects `window.adena`.
- Connect: `AddEstablish(siteName, chainIds?)`, then `GetAccount()`
  (data: address, accountNumber, coins, chainId, sequence, status,
  publicKey).
- Network: `GetNetwork()`, `SwitchNetwork(chainId)`, `AddNetwork({chainId,
  chainName, rpcUrl})`. Switch answers `SWITCH_NETWORK_SUCCESS`,
  `REDUNDANT_CHANGE_REQUEST`, or `UNADDED_NETWORK`.
- Sign and broadcast: `DoContract(params)` returns
  `BroadcastTxCommitResult` (`hash`, `height`, `check_tx`,
  `deliver_tx`). `SignTx` alone only returns an encoded transaction and
  does not broadcast, so it is not used.
- `TransactionParams`: `{messages, gasFee (number, ugnot), gasWanted
  (number), memo?, networkInfo?}`. A MsgCall message is
  `{type: "/vm.m_call", value: {caller, send, max_deposit, pkg_path,
  func, args}}`. Success is `status "success"` (code 0).
- The gno.land docs confirm Adena as the recommended third-party wallet
  and GnoConnect as the URL-based integration standard; the extension
  API above is the SDK path, which is what the UI uses.

The implementation calls `window.adena` directly instead of adding the
SDK as an npm dependency: the SDK is a thin wrapper over these same
calls, and the direct call keeps the bundle small (the SDK would pull
in `@gnolang/gno-js-client`, `@cosmjs`, Web3Auth, and viem). The choice
is recorded here so a later agent can revisit it with evidence instead
of guessing.

### What was built

`ui/src/lib/adena.js`:

- `isAdenaInstalled()`, `connectAdena()`, `submitReportWithAdena()`,
  `buildSubmitReportParams()`, `gasForFindings()`, `shortAddress()`,
  `chainDisplayName()`, `describeAdenaFailure()`, `AdenaError`.
- Connect flow: `AddEstablish("RealmCheck", [chainId])` (with a retry as
  a plain site approval when an older extension refuses the chained
  request), then `GetAccount()`, then a network check: when the wallet
  is not on the configured chain, `SwitchNetwork(chainId)`, adding the
  network first with `AddNetwork` when the wallet answers
  `UNADDED_NETWORK`.
- `buildSubmitReportParams` builds the exact `DoContract` params for a
  `SubmitReport` call: one `/vm.m_call` message with the caller address
  (which becomes the stored Auditor), the report realm path, and the
  four arguments (realm path, source hash, score, encoded findings from
  `encodeFindings` in `gnoRpc.js`), gas from the API.md formula, and
  `networkInfo` pinning the transaction to the configured chain and RPC.
- `submitReportWithAdena` signs and broadcasts through `DoContract`,
  returns `{hash, height}`, and treats a failed `deliver_tx` as an
  error even when the broadcast reports success, so an out-of-gas
  report is never shown as saved.
- The chain id comes from `VITE_GNO_CHAIN_ID` (default `onyx-1`), the
  RPC and report realm from `gnoRpc.js`. No change to `gnoRpc.js` was
  needed.

The save panel in `ui/src/App.tsx` now has, in place of the disabled
button, a working Option 2 with clear states: not installed (install
prompt with links to adena.app and the Chrome Web Store page),
connecting, connected with address, signing, signed with tx hash (plus
copy and "Load the stored report" actions), and error (wallet message
plus retry). The gnokey command stays as Option 1, unchanged, as the
fallback.

### Verification (without a funded key or a browser extension)

- `npm run build` passes with no TypeScript errors (tsc plus vite).
- The new module imports cleanly under node, and a stubbed
  `window.adena` drove the full connect plus sign flow: matching
  network (AddEstablish, GetAccount, GetNetwork only), wrong network
  (SwitchNetwork added), missing network (UNADDED_NETWORK, then
  AddNetwork with the Onyx chain id and RPC URL, then a second
  SwitchNetwork), a rejected DoContract (throws `AdenaError` with a
  rejection message), and no extension (throws `not-installed`).
- Gas parity with `gnoRpc.js` `buildSubmitCommand` checked for 0 to 5
  findings, and the params builder checked against the real vulnmint
  audit (RC-02@41, gas 17,000,000/34,000 for 1 finding).
- The built bundle contains the new panel strings ("Connect Adena to
  sign", "Sign and save this report", "Get Adena at adena.app").
- The audit-port test still passes on all 5 demo realms, and the Gno
  tests still pass (see section 4).

### What is NOT verified live (belongs to the M6 deploy phase)

- Actual Adena extension connect and sign in a real browser. That needs
  a browser with Adena installed and a funded Onyx key, neither of which
  exists in this prep work. The live test is: connect Adena, save one
  report through the extension, confirm the stored report reads back.
- The `networkInfo` pin and the `AddNetwork` fallback against a real
  extension version. The shapes come from the published SDK types, but
  only a real extension proves them.
- The DoContract result UI options were left at the SDK defaults (no
  explicit `withNotification`/`isVisibleResult`).

## 4. Other verification before finishing

- `npm run build`: passes (tsc plus vite, 282.03 kB JS, 85.98 kB gzip).
- `gno test -p 1 .` in `contracts/auditrules`: 52 PASS. In
  `contracts/realmcheck`: 11 PASS. Across `contracts/demo/*`: 26 PASS
  (5, 4, 7, 5, 5). Untouched by this work, as required, and still green.
- `node ui/scripts/test-audit-port.mjs`: all 5 demo realms match Gno
  `Audit()` exactly.
- No em dashes or en dashes in any new or edited file (grep-checked).
- The deploy script's `--local` run proves the deploy order, the swap,
  and the verification steps end to end (section 2).

## 5. What remains blocked

1. **Onyx faucet funds (human browser step).** No Onyx-funded key
   exists. Fund a key at https://faucet.gno.land: paste the `g1`
   address, pick Onyx and 100/200/300 GNOT, complete the captcha. Then
   run `bash scripts/deploy-onyx.sh --key <key-name> --deployer
   <g1-address>`. The script re-checks the balance first.
2. **gnokey cannot reach Onyx from this VM (verified, not assumed).**
   `gnokey query` against the Onyx RPC fails with `tls: first record
   does not look like a TLS handshake`, on both the Onyx and the `latest`
   alias remotes, while curl returns HTTP 200. Root cause, read from the
   toolchain source: gnokey's RPC client builds a custom
   `http.Transport` with no `Proxy`, so it ignores the VM's egress proxy
   and connects directly, and the direct path does not complete TLS.
   Direct `openssl s_client` fails the same way; curl through the proxy
   succeeds. The deploy must therefore run from a machine with direct
   internet access. The script probes this before any transaction and
   stops with the diagnosis when the probe fails. All read-only checks
   in the script use curl and node, which honor the proxy.
3. **Adena live test** (section 3): real extension plus funded key, in
   the M6 deploy phase.
4. **Post-deploy UI steps**: point the UI build at the deployed report
   realm (`VITE_REALMCHECK_REALM`), redeploy to GitHub Pages, audit the
   demo realms live, and update the README status line and the UI copy
   that says the demo realms do not exist on Onyx yet.

## 6. Deliberately left out, with the reason

- **No Onyx transaction, faucet request, or deploy.** Blocked on funds
  and on gnokey reachability (section 5). The script refuses to run
  without funds and stops on an unreachable RPC; nothing was attempted.
- **No `@adena-wallet/sdk` npm dependency.** The direct `window.adena`
  calls are the same API the SDK wraps, verified from its published
  code, and keep the UI bundle free of its heavy dependency tree
  (section 3).
- **No change to `contracts/**`, `agent/**`, `ui/src/lib/audit.js`,
  `ui/src/lib/gnoRpc.js`, `docs/API.md`, or any other README.** Out of
  scope for this piece; all were read, none edited. One requested
  change is recorded instead of made: none was needed in `gnoRpc.js`
  (the Adena module reads the chain id from `VITE_GNO_CHAIN_ID` and
  everything else from the existing exports).
- **No full README.** The root `README.md` is the minimal honest one
  page this task asked for; the full README is an M7 job.
- **The upstream gno-mcp clone and the research scratch files are not
  in the repo.** The clone is a nested git repo and the scratch files
  are local research; both are reproducible from their sources and are
  excluded by `.gitignore` (section 1).
- **No `gno.mod` cleanup.** The stale `gno.mod` files the M4 harness
  worked around are already gone from `contracts/demo/*/`; the deploy
  script stages only `.gno` sources plus `gnomod.toml` anyway.

## 7. Files owned by this piece

- Created: `.gitignore`, `README.md`, `scripts/deploy-onyx.sh`,
  `docs/ONYX-DEPLOY.md`, `ui/src/lib/adena.js`, `ui/src/lib/adena.d.ts`
  (companion type declarations for `adena.js`, required for the build
  to type-check, same pattern as `audit.d.ts` and `gnoRpc.d.ts`),
  `M6-PREP-STATUS.md` (this file).
- Edited: `ui/src/App.tsx` (save panel only: Adena state machine
  replacing the disabled button; gnokey option untouched).
- Not edited, as required: `contracts/**`, `agent/**`,
  `ui/src/lib/audit.js`, `ui/src/lib/gnoRpc.js`, `docs/API.md`, and all
  other READMEs.
