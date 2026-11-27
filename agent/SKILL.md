# RealmCheck agent skill: run an audit from chat

You are running a RealmCheck audit. The contract is `docs/API.md` in the
project root. Read it first; it is the single source of truth for the
API between the audit rules, the report realm, and this agent mode. The
scoring rule is fixed and deterministic. An LLM only explains findings,
never scores.

## The one rule about scoring

The score comes only from the deterministic rules RC-01 to RC-08 in
`contracts/auditrules/`. Weights: critical 25, high 15, medium 8, low 3.
Score is 100 minus the sum of the weights of all findings, floored at 0.
You do not invent, adjust, or round a score. You do not add findings
the rules did not produce, and you do not drop findings the rules did
produce. Your words explain what a finding means, who it hurts, and
how to fix it. The numbers come from the audit run, never from you.

## Which audit engine to use, and why

Use the JavaScript port `ui/src/lib/audit.js` under node. It is a direct
port of Gno `Audit()` and it matches `Audit()` exactly on all 5 demo
realms (verified in M4: same rule, severity, line, title, description,
and source line on every finding). It runs under plain node with no temp
files and no writes into `contracts/`. Cross-check with the real Gno
`Audit()` whenever you can, through the project's existing driver:

```bash
node scripts/e2e-local.mjs audit --rpc <rpc-url>
```

That driver runs `Audit()` through its own temporary test and deletes
the test afterwards. If the JS port and Gno `Audit()` disagree, Gno
`Audit()` is the truth, the disagreement is a bug, and you stop and
report it instead of submitting.

## The audit flow

### Step 0. Know which chain you are on

- Local dev: chain ID `dev`, RPC `http://127.0.0.1:26657`, gnoweb
  `http://127.0.0.1:8888`. Key `realmcheck-dev`
  (`g1yzqhuxczln72kwm9pstcmjerhnu0uverkuyz4h`), funded on the local
  chain with `-add-account`. No real money exists here.
- Onyx testnet: chain ID `onyx-1`, RPC
  `https://rpc.onyx.testnets.gno.land:443`, gnoweb
  `https://onyx.testnets.gno.land`. Needs a funded key; the faucet
  needs a captcha, a browser step, and no Onyx-funded key exists yet.
- Mainnet: read-only, always. Never sign a write on mainnet, and never
  try to work around that.

### Step 1. Read the realm source

With gnomcp, use `gno_read` and ask for the whole file. The default
outline is not enough for an audit; audit-grade review reads whole
files.

```text
gno_read(path="gno.land/r/dunoil/adminbackdoor", file="adminbackdoor.gno", full=true, profile="local")
```

Without gnomcp, use `vm/qfile` over the RPC, which returns the same
bytes. The helper `agent/audit.mjs` does this for you and also checks
the fetched source is byte-identical to the local contract source:

```bash
node agent/audit.mjs --rpc http://127.0.0.1:26657 \
  --realm gno.land/r/dunoil/adminbackdoor --file adminbackdoor.gno \
  --local contracts/demo/adminbackdoor/adminbackdoor.gno \
  --out agent/m5-work/adminbackdoor.json
```

Record the SHA-256 of the exact source you audited. The stored report
carries this hash so anyone can re-run the audit and compare.

### Step 2. Run the audit

Run the JS port against the exact source fetched in step 1, using
`agent/audit.mjs` (step 1 command), which runs `auditFile` and `score`
from `ui/src/lib/audit.js` and writes a work file with the source hash,
the score, the findings, and the `SubmitReport` encoding. Or run the
one-command flow in `agent/run-audit-local.sh`, which does steps 1 to 4
for you.

Expected result for `adminbackdoor`, the reference audit: score 37
with 4 findings, RC-01 high at line 105, RC-03 critical at line 75,
RC-07 medium at line 84, RC-08 high at line 53. Check the arithmetic:
25 plus 15 plus 8 plus 15 is 63, and 100 minus 63 is 37. If you get a
different result on this realm, stop and say so; do not submit.

The findings encoding for `SubmitReport` is one finding per line,
fields separated by `|`:

```text
RULEID|Severity|Line|Title|Description|SourceLine
```

Example line:

```text
RC-02|Critical|14|Unrestricted mint|Mint has no access control|func Mint(to string, amount int) {
```

Severity in the encoding uses the catalog severity with a capital
first letter (`Critical`, `High`, `Medium`, `Low`).

### Step 3. Store the report with SubmitReport

Report realm: `gno.land/r/dunoil/realmcheck`. Function:

```text
SubmitReport(realmPath string, sourceHash string, score int, findings string) int
```

It stores a Report and returns its numeric ID. The caller address is
recorded as Auditor.

With gnomcp, use `gno_call`:

```text
gno_call(profile="local", realm="gno.land/r/dunoil/realmcheck", func="SubmitReport",
  args=["gno.land/r/dunoil/adminbackdoor", "<source-hash>", "37", "<findings-encoding>"])
```

Notes on the gnomcp path: `gno_call` takes no gas arguments in this
version; the server sizes the transaction, so always read gas used
back from the call result. On the `local` profile, writes sign with
the built-in `test1` agent key, not with `realmcheck-dev`, so the
stored Auditor will be the test1 address. Sessions are still work in
progress; do not use `identity=session` for this flow.

Without gnomcp, use `gnokey maketx call`. Gas scales with the finding
count (measured: 1 finding used 8,904,806 gas, 4 findings 26,292,230).
Use gas-wanted 10,000,000 plus 7,000,000 per finding, and gas-fee
gas-wanted divided by 500 (twice the 1 ugnot per 1,000 gas minimum).
A flat 10,000,000 only covers a one-finding report and fails out of
gas on larger ones. For adminbackdoor (4 findings): gas-wanted
38,000,000, gas-fee 76,000 ugnot.

```bash
printf 'devpass\n' | gnokey maketx call -insecure-password-stdin \
  -pkgpath "gno.land/r/dunoil/realmcheck" -func "SubmitReport" \
  -args "gno.land/r/dunoil/adminbackdoor" \
  -args "<source-hash>" -args "37" -args "<findings-encoding>" \
  -gas-fee 76000ugnot -gas-wanted 38000000 -chainid dev \
  -remote 127.0.0.1:26657 realmcheck-dev
```

On Onyx, the same command with `-chainid onyx-1`, the Onyx RPC, and a
funded Onyx key. Never paste a private key or mnemonic into a command,
a file, or chat. The key is referenced by name only.

### Step 4. Verify the stored report, then report it

Read it back with `gno_eval` (gnomcp) or `gnokey query vm/qeval`
(fallback). All four must agree with what you submitted:

```bash
gnokey query vm/qeval -data "gno.land/r/dunoil/realmcheck.GetReport(<id>)" -remote 127.0.0.1:26657
gnokey query vm/qeval -data "gno.land/r/dunoil/realmcheck.ReportFindings(<id>)" -remote 127.0.0.1:26657
gnokey query vm/qeval -data 'gno.land/r/dunoil/realmcheck.LatestReport("gno.land/r/dunoil/adminbackdoor")' -remote 127.0.0.1:26657
gnokey query vm/qeval -data "gno.land/r/dunoil/realmcheck.ReportCount()" -remote 127.0.0.1:26657
gnokey query vm/qeval -data 'gno.land/r/dunoil/realmcheck.Render("")' -remote 127.0.0.1:26657
```

The helper `agent/verify-report.mjs` runs all of these checks at once:

```bash
node agent/verify-report.mjs --rpc http://127.0.0.1:26657 --web http://127.0.0.1:8888 \
  --work agent/m5-work/adminbackdoor.json --id <id> --height <height> \
  --count <expected-count> --auditor g1yzqhuxczln72kwm9pstcmjerhnu0uverkuyz4h
```

Only after the stored report verifies do you report the result to the
user: the report ID, the score, the findings with cited lines, the
source hash, gas used, and the transaction hash. If any check fails,
say which one and do not present the report as stored.

## Ground truth (all 5 demo realms)

| Realm | Score | Findings |
| --- | --- | --- |
| vulnmint | 75 | RC-02@41 |
| unguardedvault | 70 | RC-05@48, RC-08@51 |
| greedystore | 92 | RC-04@47 |
| luckydice | 62 | RC-05@61, RC-06@69, RC-08@103 |
| adminbackdoor | 37 | RC-01@105, RC-03@75, RC-07@84, RC-08@53 |

## Honest limits

- gnomcp is pre-release, unaudited, and testnet/dev only by
  construction. Mainnet chain IDs are rejected for writes. Sessions
  are still work in progress.
- gnomcp was NOT built or run on this VM (see M5-AGENT-STATUS.md).
  The `gno_read` and `gno_call` steps above are the intended path, and
  the `vm/qfile` plus `gnokey` fallback path is the verified path.
  Until gnomcp is verified on a machine where building it is allowed,
  treat the fallback as the working path.
- The deterministic rules catch known shapes only. A score of 100
  means no rule fired, not that the realm is safe. Say that when you
  report a clean audit.
- The local chain is throwaway: every fresh `gnodev local` start
  resets report IDs to 1. Quote the report ID together with the chain
  it lives on, never alone.
