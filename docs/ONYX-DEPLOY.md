# RealmCheck: Onyx testnet deploy checklist

How to deploy RealmCheck to Onyx (chain id `onyx-1`), what it costs, and
what to do when a step fails. The deploy is scripted:
`scripts/deploy-onyx.sh` does the staging, the namespace swap, the funding
gate, the deploys in order, and the verification. This document is the
human-readable version of the same plan, plus the faucet steps and the
failure notes the script cannot cover on its own.

Status 27 Nov 2026: the script is validated end to end against a fresh
local chain (`--local` run PASSED, see section 6). The real Onyx deploy
has NOT run yet: it is blocked only on faucet funds. The gnokey
reachability blocker (section 5) is now worked around by the offline-sign
path: `scripts/offline-sign-deploy.sh` signs with gnokey offline and
broadcasts with curl, and that path is proven end to end on a local chain
and proven to reach the Onyx node (see section 9). Once the deployer key
holds at least 20 GNOT, run the offline-sign script; `deploy-onyx.sh`
remains the alternative for a machine where gnokey itself can reach Onyx.

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
- A way to get a signed transaction to the Onyx RPC. The default path is
  the offline-sign deploy (`scripts/offline-sign-deploy.sh`, section 9):
  gnokey signs offline and curl broadcasts, so gnokey itself never needs
  to reach the RPC. The older path (`scripts/deploy-onyx.sh`) needs a
  machine from which **gnokey itself can reach the Onyx RPC**. This is
  a real constraint, verified 27 Nov 2026: gnokey builds its own HTTP
  client with no proxy support, so on a machine behind an egress proxy
  it connects directly and the direct path to the Onyx RPC does not
  complete a TLS handshake (`tls: first record does not look like a TLS
  handshake`). curl and node reach the RPC fine through the proxy;
  gnokey does not. The direct script probes gnokey reachability before
  any transaction and stops with this diagnosis when the probe fails.
  The deploy therefore runs from a machine with direct internet access
  (for example the owner's PC with the toolchain and the funded key), not
  from this VM, unless the offline-sign script is used. See section 5.

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
The preferred workaround is the offline-sign path instead
(`scripts/offline-sign-deploy.sh`, section 9): it runs from this VM, it
needs no direct egress for gnokey, and it is proven end to end on a local
chain and proven to reach the Onyx node.

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

Offline-sign path, same day: `bash scripts/offline-sign-deploy.sh
--local` PASSED end to end on a fresh local chain (exit 0,
`RESULT: PASSED (offline-sign deploy complete and verified)`), using the
real Onyx deployer key `realmcheck-onyx` funded locally with 100 GNOT.
All 7 packages deployed and byte-verified, test SubmitReport stored as
report #1 (score 75, RC-02@41, auditor the deployer). Gas used matched
the direct script within a few thousand per package (auditrules
62,350,998; realmcheck 13,940,292; vulnmint 6,839,530; greedystore
5,965,020; luckydice 9,505,594; unguardedvault 8,164,188; adminbackdoor
10,015,764; SubmitReport 9,285,027). Full log:
`scripts/offline-work/run-local-20261127-071102.log` (gitignored work
dir). See section 9 for the flow and the Onyx broadcast test.

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

## 9. Offline-sign deploy path (proven 27 Nov 2026)

This is the deploy path that runs from this VM despite the section 5
blocker. It never asks gnokey to touch the network: gnokey only builds
the unsigned tx and signs it, both offline, and curl does every network
call (account query, broadcast, verification), because curl honors the
egress proxy and gnokey does not. The script is
`scripts/offline-sign-deploy.sh`; it mirrors `deploy-onyx.sh` exactly in
staging, namespace swap, deploy order, gas settings, the 20 GNOT funding
gate, and verification, and differs only in how a transaction gets to the
chain.

### The five steps, per transaction

All five are implemented in the script's `offline_tx` function. The
example below is one addpkg; a `call` (SubmitReport) and a `send` work
the same way with their own maketx subcommand and flags.

```bash
export PATH="$PATH:$HOME/workspace/tools/go/bin:$HOME/workspace/tools/gno/bin"
export GNOROOT="$HOME/workspace/tools/gno"
GNOKEY_HOME="$HOME/workspace/gnome-tavern-hackathon/.gnokey"
DEPLOYER=g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu
RPC="https://rpc.onyx.testnets.gno.land:443"

# 1. Unsigned tx: maketx with -broadcast=false prints the unsigned Amino
#    JSON tx document to stdout. Verified from the source
#    (gno.land/pkg/keyscli/addpkg.go, execMakeAddPkg): with Broadcast
#    false it runs io.Println(string(amino.MustMarshalJSON(tx))) and
#    returns, so there is no account query, no simulation, no password,
#    and no chain contact at all. Verified live: the same command with
#    the unreachable Onyx remote exits 0 and prints pure JSON.
gnokey maketx addpkg -broadcast=false \
  -pkgpath "gno.land/p/$DEPLOYER/auditrules" \
  -pkgdir scripts/onyx-deploy-work/stage/auditrules \
  -gas-fee 140000ugnot -gas-wanted 70000000 \
  -chainid onyx-1 -remote "$RPC" -home "$GNOKEY_HOME" realmcheck-onyx \
  > unsigned.json

# 2. Account number and sequence, over curl (proxy-aware). The query path
#    is auth/accounts/<address>, verified from the source
#    (gno.land/pkg/gnoclient/client_queries.go, QueryAccount, and
#    tm2/pkg/crypto/keys/client/maketx.go, SignAndBroadcastHandler, which
#    queries the same path and unmarshals BaseAccount). The ABCI Data
#    field is base64; it decodes to JSON with a BaseAccount object whose
#    account_number and sequence are strings. A never-seen address
#    returns Data "null": that is a new account, number 0 and sequence 0,
#    which is also what gnokey's own maketx would sign with after its
#    account query unmarshals the same null.
curl -s -G "$RPC/abci_query" \
  --data-urlencode 'path="auth/accounts/g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu"' \
  --data-urlencode 'data=0x'

# 3. Sign offline. gnokey sign reads the tx doc, signs it with the key,
#    and, with no -output-document, writes the signed doc back over the
#    same file (tm2/pkg/crypto/keys/client/sign.go, execSign and saveTx).
#    It makes no network call. The password comes from the password file
#    on stdin and is never printed or passed on a command line.
gnokey sign -tx-path unsigned.json \
  -account-number <N> -account-sequence <S> -chainid onyx-1 \
  -home "$GNOKEY_HOME" -insecure-password-stdin realmcheck-onyx \
  < .gnokey/password.txt

# 4. Signed Amino JSON to binary Amino bytes, with scripts/txbin/txbin.
#    It performs exactly the two calls gnokey's own BroadcastHandler
#    makes (tm2/pkg/crypto/keys/client/broadcast.go): amino.UnmarshalJSON
#    into a std.Tx, then amino.Marshal. See "The txbin helper" below.
scripts/txbin/txbin unsigned.json unsigned.bin
#    stdout: the base64-encoded binary bytes, ready for the RPC.

# 5. Broadcast with curl: a JSON-RPC POST of broadcast_tx_commit with the
#    base64 bytes as the tx parameter. broadcast_tx_commit waits for the
#    tx to commit and returns check_tx, deliver_tx, hash, and height in
#    one response. (broadcast_tx_sync also works; it returns only the
#    check_tx result and the hash, so the script uses commit.)
curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":"realmcheck-1","method":"broadcast_tx_commit","params":{"tx":"<base64>"}}' \
  "$RPC/"
```

The sequence matters: the account query (step 2) is re-run before every
transaction, because each committed tx increments the sequence by 1. A
stale sequence is refused with a signature verification error, so never
reuse one query for two transactions.

### The txbin helper

`scripts/txbin/` holds a small Go program (`main.go`, `go.mod`,
`go.sum`, `README.md`) that converts a signed Amino JSON tx document to
binary Amino bytes and prints the base64 form on stdout. It does exactly
what `gnokey broadcast` does before its network call:

```go
var tx std.Tx
amino.UnmarshalJSON(jsonbz, &tx) // execBroadcast, same call
bz, err := amino.Marshal(tx)     // BroadcastHandler, same call
```

The blank imports of `gno.land/pkg/sdk/vm` and `tm2/pkg/sdk/bank`
register the message types (`MsgAddPackage`, `MsgCall`, `MsgRun`,
`MsgSend`) with the global Amino codec, the same registration gnokey
gets by importing `keyscli`; without them the JSON unmarshal cannot
decode the concrete message inside the tx. `go.mod` pins the local Gno
source with a `replace` directive (`github.com/gnolang/gno =>
../../../tools/gno`), so the helper always matches the installed gnokey
version. Build it with `go build -o txbin .` in `scripts/txbin/`; the
binary is gitignored and `scripts/offline-sign-deploy.sh` builds it
automatically when it is missing or stale.

### Running it

```bash
# 1. Dry run: stage, swap, verify, print every command. No chain contact.
bash scripts/offline-sign-deploy.sh --check

# 2. Local rehearsal: full deploy against a fresh local gnodev chain,
#    funded for the real Onyx key (100 GNOT). Proves the whole path,
#    including the real key and its password file.
bash scripts/offline-sign-deploy.sh --local

# 3. Real deploy. Same 20 GNOT funding gate as deploy-onyx.sh; refuses
#    to run below 20 GNOT and never attempts a transaction without funds.
bash scripts/offline-sign-deploy.sh --key realmcheck-onyx --deployer g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu
```

Options: `--rpc` and `--chainid` override the Onyx defaults,
`--home` overrides the gnokey home (default `$PROJECT/.gnokey`),
`--password-file` overrides the password file (default
`$PROJECT/.gnokey/password.txt`). Without a password file, `gnokey sign`
prompts interactively. Logs and per-transaction artifacts (unsigned and
signed docs, binary bytes, base64, broadcast responses) land in
`scripts/offline-work/` (gitignored).

### Local validation (27 Nov 2026, PASSED)

`bash scripts/offline-sign-deploy.sh --local`, exit 0,
`RESULT: PASSED (offline-sign deploy complete and verified)`. Full log:
`scripts/offline-work/run-local-20261127-071102.log`. A manual MsgSend
probe through the same five steps also committed first (gas used
927,746, height 3, hash
`O0n85NvOoIjimXF8qTdvwZ5UZbfxzqv2EbPA1zHkspE=`; the account sequence
moved 0 to 1 and the balance dropped by exactly the 2,000ugnot fee).
The full run then deployed all 7 packages with byte verification and
stored the test SubmitReport as report #1 (score 75, RC-02@41, auditor
the deployer). Gas used per package is in section 6. One probe detail
worth keeping: the first manual send used gas-wanted 100,000 and the
node refused it in check_tx with `std.OutOfGasError`, gas used 311,584
during the ante handler alone, so a plain send needs on the order of
1,000,000 gas-wanted; the addpkg and SubmitReport values in section 4
already carry far more than that.

### Onyx broadcast test (27 Nov 2026, unfunded key)

One small transaction, a MsgSend of 1,000ugnot from the deployer to
itself (gas-wanted 2,000,000, gas-fee 4,000ugnot, chain id onyx-1,
account number 0, sequence 0), signed offline with `realmcheck-onyx`,
converted with txbin (260 binary bytes), and broadcast with curl to
`https://rpc.onyx.testnets.gno.land:443/` `broadcast_tx_commit`. The
exact node response (full JSON in
`scripts/offline-work/onyx-send-broadcast.json`):

```json
{
  "jsonrpc": "2.0",
  "id": "realmcheck-onyx-test-1",
  "result": {
    "check_tx": {
      "ResponseBase": {
        "Error": { "@type": "/std.UnknownAddressError" },
        "Log": "--= Error =--\nData: std.UnknownAddressError{abciError:std.abciError{}}\nMsg Traces:\n    0  /gnoroot/tm2/pkg/std/errors.go:102 - account g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu does not exist\nStack Trace:\n    0  /gnoroot/tm2/pkg/errors/errors.go:93\n    1  /gnoroot/tm2/pkg/std/errors.go:102\n    2  /gnoroot/tm2/pkg/sdk/auth/ante.go:391\n    3  /gnoroot/tm2/pkg/sdk/auth/ante.go:163\n    4  /gnoroot/gno.land/pkg/gnoland/app.go:242\n    5  /gnoroot/tm2/pkg/sdk/baseapp.go:1057\n    6  /gnoroot/tm2/pkg/sdk/baseapp.go:709\n    7  /gnoroot/tm2/pkg/bft/abci/client/local_client.go:103\n    8  /gnoroot/tm2/pkg/bft/appconn/app_conn.go:115\n    9  /gnoroot/tm2/pkg/bft/mempool/clist_mempool.go:284\n   10  /gnoroot/tm2/pkg/bft/mempool/clist_mempool.go:214\n... 18 more lines elided"
      },
      "GasWanted": "0",
      "GasUsed": "0"
    },
    "deliver_tx": { "ResponseBase": { "Error": null }, "GasWanted": "0", "GasUsed": "0" },
    "hash": "eJcSIYd72SU1siKKI6wqndinThWlk4QMmCN4VnFItEo=",
    "height": "0"
  }
}
```

`broadcast_tx_sync` with the same bytes returns the identical
`UnknownAddressError` and the identical hash
`eJcSIYd72SU1siKKI6wqndinThWlk4QMmCN4VnFItEo=` (full JSON in
`scripts/offline-work/onyx-send-broadcast-sync.json`).

What this proves, and what it does not:

- Proved: curl reaches the Onyx RPC and the node accepts the
  `broadcast_tx_commit` call; the node decoded the binary Amino bytes
  into a valid tx (it extracted the signer address and looked the
  account up); the encoding, the JSON-RPC shape, and the broadcast
  mechanics all work against the real Onyx node.
- The rejection is `UnknownAddressError`, "account ... does not exist",
  from the ante handler's signer-account lookup
  (`tm2/pkg/sdk/auth/ante.go:391`, `GetSignerAcc`). That lookup runs
  before signature verification and before any funds check, so the
  chain never got far enough to check the signature or the balance.
  This is the expected outcome for a never-funded key: the account
  query for the deployer returns Data `null` and the balance is
  0ugnot, so the account does not exist on Onyx yet. It is not a funds
  error, and it is not an encoding error.
- Not proved by this test alone: that the signature verifies. That is
  proved by the local run instead, where the same five steps committed
  8 transactions (7 addpkg plus the test SubmitReport) with valid
  signatures, each at the next sequence. Together the two tests cover
  the whole path: local proves sign plus encode plus execute, Onyx
  proves the bytes reach the real node and decode there.

What remains before the real Onyx deploy: only funding. Fund the key
at https://faucet.gno.land (100 GNOT covers the measured 12.05 GNOT
whole-deploy cost several times over), then run
`bash scripts/offline-sign-deploy.sh --key realmcheck-onyx --deployer
g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu`. The funding creates the
account on chain, so the `UnknownAddressError` goes away with it, and
the deployer's account number and sequence will then come back from
the step 2 query instead of 0 and 0.

## 10. The inert-policy gate (found 27 Nov 2026, real Onyx deploy)

Funding landed 27 Nov 2026 17:14 WITA (100 GNOT, faucet, browser
Environment 2; Environment 1 failed on an IP rate limit). The real
Onyx deploy ran 27 Nov 2026 17:15 WITA (09:15 UTC) with
`bash scripts/offline-sign-deploy.sh --key realmcheck-onyx --deployer
g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu`. All 7 addpkg transactions
committed with success, but NONE of the packages became callable.
This section records exactly what happened, why, and how to resume.

### 10.1 What the chain did

| Package | Height | Tx hash (base64) | Gas used |
| --- | --- | --- | --- |
| auditrules | 1447578 | tmC0qxbqCj0X9XbScDid9Ib3Ob5hCzCEmNhRmn/aUQ8= | 58,136,226 |
| realmcheck | 1447580 | DsniB0bUEh4NFOBTvNCHXw43xwYAiF5cRCGbaLxlwgU= | 10,793,168 |
| vulnmint | 1447582 | W4AOXJVBNqxAy67PHV+fZFEOK3UyK+8Kycf7N0cy9h4= | 6,414,173 |
| greedystore | 1447584 | JIXsJryUFgB4uWy71a3e3EveAnmOTTxACokUvZfJw7s= | 5,606,075 |
| luckydice | 1447586 | 84EDSJbsI+Q70Co12VK+SxE9VGZyOXO6qdQcNH5c/+E= | 8,587,708 |
| unguardedvault | 1447587 | Knuy7ZmdGFe3d3dyjhrRvlg5A6dFNjZq5xOOjaLszmY= | 7,599,715 |
| adminbackdoor | 1447589 | 0iXscHXlKesorPPYTWqZezLdL8eZCF54LXGbtUoSeZM= | 8,843,432 |

Full broadcast responses: `scripts/offline-work/addpkg-<name>-broadcast.json`.
Account number 2550, sequences 0 to 6. Every `deliver_tx` log reads
`msg:0,success:true,log:,events:[]`, no error in check_tx or
deliver_tx. Balance after the 7 transactions: 99,020,000ugnot, down
exactly 980,000ugnot (7 times the 140,000ugnot gas fee). No storage
deposit was charged: under the inert policy the deposit is not taken
at submit time.

### 10.2 Why verification failed: the inert policy

`vm/qfile` on every deployed path returns
`InvalidPackageError: package "..." is not available`, and the
deploy script therefore reported `RESULT: FAILED (deploy)`. The
query method itself is correct: the same `vm/qfile` call returns a
file listing for `gno.land/r/gov/dao` and `gno.land/r/sys/params`.

Root cause, from the chain source (`gno.land/pkg/sdk/vm/keeper.go`,
`AddPackage`, and `keeper_inert.go`): Onyx runs
`CodeSubmissionPolicyInert`. Under it, `AddPackage` stores the
package WITHOUT typechecking or execution. It becomes callable only
after an approver sends `MsgEnablePackage`. While parked,
`vm/qpkg_json` and `vm/qfile` both answer "package not found", the
same as for a path nobody ever used. The local gnodev chain does not
run this policy, which is why the M7 local rehearsal verified
byte-identical files and the Onyx run did not.

Authoritative status query: `vm/qpkgmeta_json` (ABCI, data is the
hex-encoded path). For our packages it returns, for example:

```json
{"path":"gno.land/p/g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu/auditrules","status":"inert","creator":"g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu","height":1447578,"max_deposit":"100000000ugnot","reason":"waiting for a package approver to enable it","pending":true}
```

All 7 packages report `status: inert`, `pending: true`, with that
reason, as of 27 Nov 2026 09:17 UTC. A control query for
`gno.land/r/gov/dao` returns `status: live`.

### 10.3 GPAO verdicts (the approval oracle)

https://gpas.latest.testnets.gno.land ("gno.land package status:
onyx"), mode automatic: "Packages that pass the checks are enabled
automatically." The check pass runs about once a minute. Verdicts for
our packages, 27 Nov 2026:

- PASSED: auditrules 09:15:18Z, vulnmint 09:15:30Z, greedystore
  09:15:36Z, luckydice 09:15:45Z, unguardedvault 09:15:48Z.
- IN REVIEW QUEUE: realmcheck, adminbackdoor (no verdict time yet).

The two queued packages are exactly the two with local imports
(realmcheck imports `gno.land/p/.../auditrules`, adminbackdoor
imports `gno.land/r/.../vulnmint`); the five that passed are all
standalone. Working hypothesis: the checker cannot fully verify a
package whose imports are not live yet, so dependents wait until
their imports are enabled, then get checked, then enabled. Do not
treat "in review queue" as a rejection: other packages sit in the
queue for hours and later pass.

Observed enable lag (same page, same day): a package that passed
04:13:15Z is live; a package that passed 07:16:48Z is still inert at
09:18Z. So enabling lags a pass by more than 2 hours and less than
about 5 hours. Our five passed at 09:15Z, so plausibly live
11:15-14:15Z (19:15-22:15 WITA); the two dependents then need another
check plus enable cycle, possibly late 27 Nov or 28 Nov. There is no
documented way to expedite, and no request form on the GPAO page.

### 10.4 What NOT to do

- Do NOT re-submit the packages. They are already stored on chain;
  re-adding would re-park them, burn more fees, and reset the
  approval clock if the checker keys on submit height.
- Do NOT treat this as a deploy failure. The transactions succeeded;
  activation is a chain-side approval gate, not a bug in the deploy
  path. The offline-sign flow itself is fully proven on the real
  chain now: 7 signed transactions, correct account number and
  sequences, committed at consecutive heights.
- Do NOT apply the post-deploy UI copy (docs/SUBMISSION.md section
  5) yet. The realms are not callable until live, so the UI would
  point at paths that still fail to fetch.

### 10.5 Resume (when all 7 report live)

Watch command (polls `vm/qpkgmeta_json` for all 7, every 15 min,
up to 5 h; runs the resume automatically when all 7 are live):

```bash
bash scripts/approval-watch.sh
# log: scripts/offline-work/approval-watch.log
```

Manual check for one package:

```bash
P="gno.land/r/g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu/realmcheck"
HEX=$(printf '%s' "$P" | od -An -tx1 | tr -d ' \n')
curl -s -G "https://rpc.onyx.testnets.gno.land/abci_query" \
  --data-urlencode "path=\"vm/qpkgmeta_json\"" \
  --data-urlencode "data=0x$HEX"
# want: "status":"live"
```

When all 7 are live, resume with the same script (idempotent: an
already-deployed package verifies byte-identical and continues):

```bash
bash scripts/offline-sign-deploy.sh --key realmcheck-onyx --deployer g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu
```

Then continue in order: on-chain verification and the test
SubmitReport (the script does both), post-deploy UI per
docs/SUBMISSION.md section 5, GitHub Pages redeploy check, Onyx demo
video re-record per docs/DEMO-VIDEO.md, docs and commit. YouTube
upload and the DoraHacks submission still need Duan's explicit
approval.
