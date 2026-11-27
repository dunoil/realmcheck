# RealmCheck agent mode (M5)

Agent mode lets a coding agent run a RealmCheck audit from chat: read a
realm, run the deterministic audit, store the report on chain, verify
it stored. The contract is `docs/API.md`. The score always comes from
the deterministic rules RC-01 to RC-08; an LLM only explains findings,
never scores.

## What is here

| File | What |
| --- | --- |
| `mcp-config.json` | MCP server config: the `gnomcp` server command, the local and Onyx endpoints, and the `realmcheck-dev` key reference by name only. Never a private key or mnemonic. |
| `SKILL.md` | The agent skill: the full audit flow in four steps, with the gnomcp tool calls and the gnokey fallback for each step. |
| `audit.mjs` | Step 1 and 2 helper: reads a realm source from the chain with `vm/qfile`, checks it is byte-identical to the local source, audits the fetched text with the JS port, writes a work JSON file. |
| `verify-report.mjs` | Step 4 helper: verifies a stored report with `GetReport`, `ReportFindings`, `LatestReport`, `ReportCount`, `Render`, and the gnoweb page. |
| `run-audit-local.sh` | The one-command audit flow against a fresh local gnodev chain. Starts its own chain, deploys the demo realms, audits adminbackdoor, cross-checks with Gno `Audit()`, submits the report, verifies it, stops the chain. |
| `gno-mcp-upstream/` | Reference clone of `github.com/gnoverse/gno-mcp` at commit `e065fbc06fcca2b6967107fb89016cc0b566d21d` (v0.13.1 plus 4 commits). Read-only reference; never built, never run, not on PATH. |
| `m5-work/` | Work files from the M5 proof run (audit JSON, report record). |
| `stage/` | Staged byte-identical copies of the demo realms used for `addpkg` during the run. |

## Install and configure

### gnomcp (intended path, NOT verified on this VM)

gnomcp is the official Gno MCP server, repo
`github.com/gnoverse/gno-mcp`, docs at `https://mcp.gno.dev`.
Version used here: commit
`e065fbc06fcca2b6967107fb89016cc0b566d21d` (v0.13.1 plus 4 commits),
cloned 27 Nov 2026. Install the binary per the upstream README at
that commit, then point your MCP client at it with `mcp-config.json`
in this directory (stdio server, command `gnomcp`, no arguments; the
built-in `local`, `testnet`, and `mainnet` profiles ship with the
server). Restart the client so it loads the server, then confirm the
tools are present (`gno_read`, `gno_call`, `gno_eval`, `gno_status`,
and the rest of the 25 tools listed in the upstream `docs/tools.md`).

Why this is not verified here: building or running the freshly cloned
upstream checkout on this VM was blocked by an execution-risk check,
so no binary was built, no server was started, and no tool call was
ever made through gnomcp. The config above is therefore unverified on
this machine. See `M5-AGENT-STATUS.md` for the exact record. Do not
treat the gnomcp path as working until it is installed and verified
on a machine where building it is allowed.

### Fallback path (verified, and the working path today)

No gnomcp needed. The fallback uses only the project toolchain
(Go 1.25.9, Gno v1.8.0) and node:

```bash
export PATH="$PATH:$HOME/workspace/tools/go/bin:$HOME/workspace/tools/gno/bin"
export GNOROOT="$HOME/workspace/tools/gno"
export GOMAXPROCS=2
```

Then run the one-command audit flow (from the project root):

```bash
bash agent/run-audit-local.sh
```

It needs the local dev key `realmcheck-dev` in `gnokey list` (address
`g1yzqhuxczln72kwm9pstcmjerhnu0uverkuyz4h`). It starts its own fresh
local chain, so report IDs start at 1 on every run.

## The one-command audit flow

`bash agent/run-audit-local.sh` audits `adminbackdoor` end to end:

1. Starts a fresh local gnodev chain (chain ID `dev`) and deploys
   `vulnmint`, then `adminbackdoor` (adminbackdoor imports vulnmint).
2. Reads the adminbackdoor source from the chain with `vm/qfile` and
   audits the fetched text with the JS port (`agent/audit.mjs`).
3. Cross-checks the findings with the real Gno `Audit()` through the
   project's existing driver (`node scripts/e2e-local.mjs audit`).
4. Submits the report with `SubmitReport` (gas-wanted 38,000,000,
   gas-fee 76,000 ugnot for 4 findings).
5. Verifies the stored report (`agent/verify-report.mjs`) and stops
   the chain.

Full output is teed to `agent/m5-agent-run.log`.

## Local-chain proof (M5 run, 27 Nov 2026)

The proof run followed `SKILL.md` step by step through the fallback
path, twice in a row with identical results. Full log:
`agent/m5-agent-run.log` (36 PASS, 0 FAIL on the second run).
Status: `M5-AGENT-STATUS.md` in the project root.

- Realm audited: `gno.land/r/dunoil/adminbackdoor`
- Score: 37 (expected 37), 4 findings, all matching ground truth:
  RC-01 high at line 105, RC-03 critical at line 75, RC-07 medium at
  line 84, RC-08 high at line 53
- JS port and Gno `Audit()` agreed exactly on rule, severity, line,
  title, description, and source line
- Stored report ID: 1 (fresh local chain), verified with `GetReport`,
  `ReportFindings`, `LatestReport`, `ReportCount`, and `Render`, plus
  the gnoweb report page
- Gas used: 26,277,587 (gas-wanted 38,000,000, gas-fee 76,000 ugnot),
  height 3, transaction hash
  `9SSLsnSo9O6lSA58l7bEGyfXJJ7P90HZtP7ojM+dsLM=`
- Source SHA-256:
  `a90ab97b23f02dedac27504008afc93d0ecbbf4e4d2270346fe38f494e36cc90`
- Auditor: `g1yzqhuxczln72kwm9pstcmjerhnu0uverkuyz4h`
  (`realmcheck-dev`)
- Record: `agent/m5-work/report.json` and `agent/m5-agent-run.log`

## Honest limits

- gnomcp is pre-release, unaudited, and testnet/dev only by
  construction. Mainnet is read-only; no code path signs on mainnet.
  Sessions are still work in progress; this flow does not use them.
- gnomcp was not built or run on this VM, so the `gno_read` and
  `gno_call` steps in `SKILL.md` are the intended path, not a verified
  path. The verified path is `vm/qfile` plus `gnokey` plus node.
- On the `local` gnomcp profile, writes sign with the built-in `test1`
  agent key, not with `realmcheck-dev`. The stored Auditor address
  differs between the two paths; that is expected.
- The deterministic rules catch known shapes only. A score of 100
  means no rule fired, not that the realm is safe.
- The local chain is throwaway: a fresh start resets report IDs to 1.
  Quote a report ID together with the chain it lives on.
- No Onyx run yet: the Onyx faucet needs a captcha, a browser step,
  and no Onyx-funded key exists. The Onyx run belongs to M6.
- Never spend money, never submit anything, never do KYC. This
  milestone spends nothing and submits nothing outside the local chain.
