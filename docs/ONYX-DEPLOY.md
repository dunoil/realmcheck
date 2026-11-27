# RealmCheck: Onyx testnet deploy checklist

How to deploy RealmCheck to Onyx (chain id `onyx-1`), what it costs, and
what to do when a step fails. The deploy is scripted:
`scripts/deploy-onyx.sh` does the staging, the namespace swap, the funding
gate, the deploys in order, and the verification. This document is the
human-readable version of the same plan, plus the faucet steps and the
failure notes the script cannot cover on its own.

Status 27 Nov 2026: the script is validated end to end against a fresh
local chain (`--local` run PASSED, see section 6). The real Onyx deploy
has NOT run yet: it is blocked on faucet funds and on gnokey reachability
from this VM (see sections 2 and 5).

## 1. What gets deployed, in order

| Step | Package | Path on Onyx (`<DEPLOYER>` is the deployer g1 address) |
| --- | --- | --- |
| 1 | auditrules (pure package) | `gno.land/p/<DEPLOYER>/auditrules` |
| 2 | realmcheck (realm) | `gno.land/r/<DEPLOYER>/realmcheck` |
| 3 | vulnmint (demo realm) | `gno.land/r/<DEPLOYER>/vulnmint` |
| 4 | greedystore (demo realm) | `gno.land/r/<DEPLOYER>/greedystore` |
| 5 | luckydice (demo realm) | `gno.land/r/<DEPLOYER>/luckydice` |
| 6 | unguardedvault (demo realm) | `gno.land/r/<DEPLOYER>/unguardedvault` |
| 7 | adminbackdoor (demo realm) | `gno.land/r/<DEPLOYER>/adminbackdoor` |

The order matters: realmcheck imports auditrules, and adminbackdoor
imports vulnmint, so auditrules goes first and adminbackdoor goes last.
The other three demo realms have no imports between them.

## 2. Prerequisites

- Toolchain: Go 1.25.9 and Gno v1.8.0 (see `ENV-TOOLCHAIN.md`).
- A gnokey key with the deployer address. Create one on the machine that
  will run the deploy:
  ```bash
  gnokey add <key-name>
  gnokey list   # copy the g1 address
  ```
  Safeguard the 12-word mnemonic gnokey prints. It is the only way back
  into the key.
- At least 20 GNOT on that address (see section 3). The script refuses
  to run below 20 GNOT and never attempts a transaction without funds.
- A machine from which **gnokey itself can reach the Onyx RPC**. This is
  a real constraint, verified 27 Nov 2026: gnokey builds its own HTTP
  client with no proxy support, so on a machine behind an egress proxy
  it connects directly and the direct path to the Onyx RPC does not
  complete a TLS handshake (`tls: first record does not look like a TLS
  handshake`). curl and node reach the RPC fine through the proxy;
  gnokey does not. The script probes gnokey reachability before any
  transaction and stops with this diagnosis when the probe fails. The
  deploy therefore runs from a machine with direct internet access (for
  example the owner's PC with the toolchain and the funded key), not
  from this VM. See section 5.

## 3. Funding the key (faucet)

No Onyx-funded key exists yet. Funding is a human browser step because
the faucet needs a captcha.

1. Go to https://faucet.gno.land (the Gno Faucet Hub). The Onyx faucet
   web path https://onyx.testnets.gno.land/faucet redirects here.
2. Paste the deployer `g1...` address.
3. Pick the Onyx network (chain id `onyx-1`) from the network dropdown.
4. Pick an amount: 100, 200, or 300 GNOT per request. One 100 GNOT
   request covers the whole deploy several times over.
5. Complete the captcha (hCaptcha on the Onyx entry; the hub page also
   loads a Google reCAPTCHA script) and submit. Tokens arrive in seconds.
6. Confirm the balance:
   ```bash
   curl -s -G "https://rpc.onyx.testnets.gno.land/abci_query" \
     --data-urlencode 'path="bank/balances/<your-g1-address>"' \
     --data-urlencode 'data=0x'
   ```
   The base64 `Data` field decodes to `"<amount>ugnot"`. The script
   reads the balance the same way and requires at least 20,000,000ugnot.

The faucet is rate-limited per address, and the exact cooldown length is
not published. If a re-request is rejected, wait it out. Do not quote a
cooldown number to anyone; it is unverified.

## 4. Running the deploy

From the project root, on the machine that will deploy:

```bash
# 1. Dry run: stage, swap, verify, print every command. No chain contact.
bash scripts/deploy-onyx.sh --check

# 2. Optional local rehearsal: full deploy against a fresh local chain.
bash scripts/deploy-onyx.sh --local

# 3. Real deploy. The key password is asked interactively per transaction.
bash scripts/deploy-onyx.sh --key <key-name> --deployer <g1-address>
```

The `--check` run accepts an optional `--deployer` to preview the swap
for a real address. `--rpc` and `--chainid` override the Onyx defaults
(`https://rpc.onyx.testnets.gno.land:443`, `onyx-1`).

### The namespace swap

The script stages copies under `scripts/onyx-deploy-work/stage/` (never
`contracts/**`) and applies these replacements:

| Where | Before | After |
| --- | --- | --- |
| every `gnomod.toml` | `module = "gno.land/p/dunoil/auditrules"` (and the `r/dunoil/<name>` forms) | `module = "gno.land/p/<DEPLOYER>/auditrules"` (and `r/<DEPLOYER>/<name>`) |
| `contracts/realmcheck/realmcheck.gno` | `"gno.land/p/dunoil/auditrules"` | `"gno.land/p/<DEPLOYER>/auditrules"` |
| `contracts/demo/adminbackdoor/adminbackdoor.gno` | `vulnmint "gno.land/r/dunoil/vulnmint"` | `vulnmint "gno.land/r/<DEPLOYER>/vulnmint"` |
| `contracts/demo/adminbackdoor/adminbackdoor.gno` | `chain.PackageAddress("gno.land/r/dunoil/adminbackdoor")` | `chain.PackageAddress("gno.land/r/<DEPLOYER>/adminbackdoor")` |
| `contracts/demo/adminbackdoor/adminbackdoor.gno` | `var Admin = address("g1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq")` | `var Admin = address("<DEPLOYER>")` |

The script verifies the swap before deploying: no `dunoil` and no
placeholder Admin address may remain in the staged copies, and every
line that differs from the original must be a swap line.

### Gas and cost (measured on a local dev chain, 27 Nov 2026)

addpkg uses gas-wanted 70,000,000 and gas-fee 140,000ugnot for every
package (the flat fee is what is charged; unused gas is not billed).

| Package | Gas used (local) | Storage fee | Total tx cost |
| --- | --- | --- | --- |
| auditrules | 62,350,936 | 5,318,000ugnot (53,180 bytes) | 5,458,000ugnot |
| realmcheck | 13,940,230 | 1,154,600ugnot (11,546 bytes) | 1,294,600ugnot |
| vulnmint | 6,839,468 | 679,100ugnot (6,791 bytes) | 819,100ugnot |
| greedystore | 5,964,958 | 566,200ugnot (5,662 bytes) | 706,200ugnot |
| luckydice | 9,505,532 | 1,081,900ugnot (10,819 bytes) | 1,221,900ugnot |
| unguardedvault | 8,164,126 | 833,300ugnot (8,333 bytes) | 973,300ugnot |
| adminbackdoor | 10,015,702 | 1,136,200ugnot (11,362 bytes) | 1,276,200ugnot |
| **7 addpkg total** | | | **11,749,300ugnot** |
| Test SubmitReport (1 finding) | 9,271,707 | 266,700ugnot (2,667 bytes) | 300,700ugnot |
| **Whole deploy** | | | **12,050,000ugnot (12.05 GNOT)** |

Notes on the numbers:

- The first `--local` run used gas-wanted 50,000,000 and auditrules ran
  out of gas at 62,350,946 used; the chain itself suggested gas-wanted
  65,468,494. That is why the script now uses 70,000,000. Do not lower
  it without re-measuring auditrules.
- Gas used varies a little between runs (auditrules measured 62,350,946
  then 62,350,936; vulnmint measured 9,874,086 in the M4 harness and
  6,839,468 here). Treat the table as an estimate with margin, not an
  exact quote. Record the real Onyx numbers after the first deploy.
- SubmitReport gas follows docs/API.md: gas-wanted 10,000,000 plus
  7,000,000 per finding, fee wanted/500. The test report has 1 finding,
  so 17,000,000 wanted and 34,000ugnot fee.
- Storage is charged at 100ugnot per stored byte. The fee is a deposit
  locked against the stored bytes, not a burn, but it leaves the deployer
  balance all the same.

### What the script verifies after each deploy

After every addpkg it fetches the on-chain file listing and byte-diffs
each staged `.gno` file against the on-chain copy (over `abci_query
vm/qfile`, through curl, so the check works behind a proxy too). A
deploy only counts when the diff is empty.

After realmcheck deploys, the script submits one test report for
vulnmint, built with the UI's own JS audit port over the staged source,
and expects the ground truth: score 75, one finding RC-02 at line 41,
source hash `f8616d8b...` (SHA-256 of the deployed `vulnmint.gno`). It
then checks, in order:

1. `ReportCount()` goes from its baseline to baseline plus 1.
2. `LatestReport("<deployed vulnmint path>")` is the new report, score
   75, auditor the deployer address.
3. `ReportFindings(<new id>)` contains the RC-02 finding.
4. `Render("")` on the report realm lists the test report with score 75.

The script also prints the gnoweb URL for every deployed package
(`https://onyx.testnets.gno.land/r/<address>/<name>`).

## 5. The gnokey reachability blocker (read before deploying from the VM)

Verified live 27 Nov 2026 from this VM:

```text
$ gnokey query vm/qfile -data "gno.land/r/gov/dao" -remote https://rpc.onyx.testnets.gno.land
--= Error =--
Data: unable to call RPC method abci_query, unable to send request,
  Post "https://rpc.onyx.testnets.gno.land:443":
  tls: first record does not look like a TLS handshake
```

The same command against the `latest` alias remote fails identically.
`curl` to the same URL returns HTTP 200, and `openssl s_client`
direct (no proxy) fails with `wrong version number`, while curl through
the VM's egress proxy succeeds. Root cause, read from the toolchain
source (`tm2/pkg/bft/rpc/lib/client/http/client.go`,
`defaultHTTPClient`): gnokey builds an `http.Client` with a custom
`http.Transport` that sets no `Proxy`, so it ignores the `https_proxy`
environment variable and connects directly, and the direct path to the
Onyx RPC does not complete a TLS handshake from this VM.

Consequences:

- No gnokey command (query or maketx) can reach Onyx from this VM.
  The Onyx deploy cannot run here, even with a funded key.
- The script's Onyx mode probes gnokey reachability right after the
  funding gate and exits with `RESULT: BLOCKED (gnokey cannot reach
  Onyx from this machine)` when the probe fails. No transaction is
  attempted in that case.
- All read-only checks in the script (balance, qfile, qeval) use curl
  and node instead, which honor the proxy, so they work from this VM.
  Only signing and broadcasting need gnokey, and therefore direct egress.

Workaround: run `scripts/deploy-onyx.sh` from a machine with direct
internet access. That machine needs the toolchain, this repo, the funded
gnokey key, and the key password. Nothing else about the deploy changes.

## 6. Validation evidence (local chain, 27 Nov 2026)

`bash scripts/deploy-onyx.sh --local`, second run, exit 0,
`RESULT: PASSED (Onyx deploy complete and verified)`. Full log:
`scripts/onyx-deploy-work/run-local-20261127-*.log` (gitignored work dir;
the numbers are also recorded in `M6-PREP-STATUS.md`).

- Fresh local gnodev chain started from an empty directory (no workspace
  packages lazy-loaded), RPC on 127.0.0.1:26659, gnoweb on 127.0.0.1:8890.
- Namespace swapped to the local deployer
  `g1yzqhuxczln72kwm9pstcmjerhnu0uverkuyz4h` (realmcheck-dev key).
- All 7 packages deployed and byte-verified; gas used per package is in
  the table in section 4.
- Test SubmitReport stored as report #1 for the deployed vulnmint path:
  score 75, RC-02@41, auditor the deployer address, gas wanted
  17,000,000, used 9,271,707, tx
  `0u9wb3ChIWbIOL/GjlF/vOA765vZ8y0Viep56GbMpag=`. ReportCount 0 to 1,
  LatestReport, ReportFindings, and Render all checked.
- The chain was stopped by the script afterwards; no stray gnodev left.
- The first `--local` run (gas-wanted 50,000,000) failed exactly as a
  validation run should: auditrules ran out of gas at 62,350,946 used,
  and realmcheck then failed type checking because its auditrules import
  was not on chain yet. That failure is what set the 70,000,000 default.

`bash scripts/deploy-onyx.sh --check` also passes: it stages, verifies
the swap, and prints the full plan with no chain contact.

Onyx-mode funding gate, tested live with the unfunded key
`realmcheck-dev` on 27 Nov 2026: the script read the on-chain balance
(0ugnot) through the curl path, printed the faucet steps, and exited
with `RESULT: BLOCKED (funds missing, faucet step above)`, exit code 1,
no transaction attempted.

## 7. Rollback and retry notes

- **Re-running the script is safe.** Before each addpkg it checks
  nothing; after a failed addpkg it checks whether the package already
  exists on chain with content identical to the staged source. When it
  does, that step counts as deployed and the run continues. When it
  does not, the run fails loudly with the failing output. A second run
  after fixing the cause resumes from the failed step instead of
  redeploying everything.
- **Check whether a package already exists** without deploying:
  ```bash
  curl -s -G "https://rpc.onyx.testnets.gno.land/abci_query" \
    --data-urlencode 'path="vm/qfile"' \
    --data-urlencode "data=0x$(printf '%s' 'gno.land/r/<address>/<name>' | od -An -tx1 | tr -d ' \n')"
  ```
  A base64 `Data` field that decodes to a file listing means the package
  exists. An error naming the package means it does not. The same query
  with `vm/qfile` and the path plus `/<file>.gno` returns one file's
  source for a byte comparison.
- **addpkg fails with "out of gas".** Raise the gas-wanted in
  `scripts/deploy-onyx.sh` (`ADD_PKG_GAS_WANTED`) above the gas used the
  chain reports, and re-run. The auditrules value (70,000,000) is the
  one most likely to need raising on Onyx if the chain's gas schedule
  differs from local.
- **addpkg fails with "type check failed" naming an unknown import.**
  A dependency did not deploy yet. Check the deploy order (auditrules
  before realmcheck, vulnmint before adminbackdoor) and re-run; the
  script resumes from the failed step.
- **addpkg fails with "package already exists" and the content differs.**
  A package path on Gno.land is immutable: it cannot be overwritten or
  deleted. Do not force it. Deploy the corrected code under a new path
  (a new name, or a new deployer namespace) and update everything that
  imports the old path. Record the old path as superseded in the deploy
  log.
- **A transaction is refused or the package is not visible afterwards.**
  Wait a minute and re-query; the testnet enables a new package a few
  seconds after addpkg. The package status page is
  https://gpas.latest.testnets.gno.land (look up the exact package path).
  If it still says the package is not known, ask on Discord at
  https://discord.com/invite/gnoland.
- **SubmitReport fails out of gas.** The gas formula scales with the
  finding count (10,000,000 plus 7,000,000 per finding). A flat
  10,000,000 only covers a one-finding report. The script computes the
  wanted value from the actual finding count; if a future report is
  larger, the same formula still applies.
- **The deploy key runs out of funds mid-run.** Fund it again at
  https://faucet.gno.land (100 to 300 GNOT per request, captcha, rate
  limited per address), then re-run the script. Already-deployed
  packages are detected and skipped.

## 8. After the deploy

1. Record the real Onyx gas used, storage fees, tx hashes, and the
   deployed paths in `M6-PREP-STATUS.md` (or the M6 close-out note) and
   correct the estimates in section 4 if Onyx differs from local.
2. Point the UI at the deployed report realm: build with
   `VITE_REALMCHECK_REALM=gno.land/r/<DEPLOYER>/realmcheck` (the RPC
   default is already Onyx) and redeploy the static UI to GitHub Pages.
3. Audit each demo realm live from the UI and confirm the scores match
   the ground truth (vulnmint 75, unguardedvault 70, greedystore 92,
   luckydice 62, adminbackdoor 37). The UI still audits them from
   bundled local sources until this step lands.
4. Run the Adena live test: connect Adena in a real browser, save one
   report through the extension, and confirm the stored report reads
   back. See `M6-PREP-STATUS.md` for what the Adena implementation
   covers and what is still unverified.
5. Update the README status line (it currently says the Onyx deploy is
   blocked on faucet funds) and the UI copy that says the demo realms
   do not exist on Onyx yet.
