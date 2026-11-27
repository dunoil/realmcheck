# M5 Agent Mode Status (27 Nov 2026)

Milestone M5 (due 9 Dec) is DONE ahead of schedule, with one honest
exception: the gnomcp server itself could not be built or run on this
VM, so the agent-run audit went through the documented gnokey plus
node fallback path instead. Everything else in the milestone is built
and verified live on a local gnodev chain. Nothing was spent, nothing
was submitted outside the local chain, no KYC was done.

## 1. gnomcp: fetched and verified from docs, NOT built or run

Repo: `github.com/gnoverse/gno-mcp`, cloned 27 Nov 2026 into
`agent/gno-mcp-upstream/` (read-only reference copy, 10 MB). Exact
version used:

- HEAD commit: `e065fbc06fcca2b6967107fb89016cc0b566d21d`
- `git describe`: `v0.13.1-4-ge065fbc` (latest tag v0.13.1, plus 4 commits)
- Latest commit message: `build(deps): bump the actions group across
  1 directory with 2 updates (#118)`

What was verified by reading (plain file viewing only, no execution):

- README: pre-release, unaudited, work in progress. Writes are
  confined to dev/testnet, no code path signs on mainnet. Built-in
  profiles are `local` (chain ID `dev`, RPC
  `http://127.0.0.1:26657`), `testnet` (chain ID `onyx-1`, RPC
  `https://rpc.onyx.testnets.gno.land:443`), and `mainnet`
  (`gnoland-1`, read-only).
- `docs/tools.md`: 25 tools, confirmed by reading the catalog. The
  tools this skill uses exist with these exact arguments: `gno_read`
  (path, file, symbols, full, profile; `full=true` plus `file` returns
  the raw whole file, which is what audit-grade review needs),
  `gno_render` (realm, path, profile), `gno_eval` (path, expr,
  profile), `gno_call` (profile, realm, func, args, send, simulate,
  identity, key; no gas arguments), `gno_status`, `gno_account`,
  `gno_key_address`, `gno_key_list`, `gno_key_generate`,
  `gno_faucet_fund`. Sessions (`gno_session_propose`,
  `gno_session_revoke`) are work in progress.
- `docs/gnomcp.md`: stdio MCP config shape
  (`{"mcpServers": {"gnomcp": {"command": "gnomcp", "args": []}}}`),
  profiles live in `profiles.toml`, local profiles sign writes with
  the built-in `test1` agent key, and the user's keys never enter the
  gnomcp process.

What did NOT work, stated plainly: no gnomcp binary was built, no
server was started, and no tool call was ever made through gnomcp.
The freshly cloned upstream checkout failed an execution-risk check
on this VM: building, running, installing, or executing anything
from it was blocked, and the block also covers running git or package
manager commands inside the checkout and reproducing its install or
build commands. Per the task's own fallback rule, I did not stall on
this: I recorded the block here, verified gnomcp only from its
documentation by reading, and built the agent mode around the
gnokey plus node fallback path, which works without gnomcp. The
`gnomcp` server command in `agent/mcp-config.json` is therefore
UNVERIFIED on this machine, and the config file says so in its
`statusOnThisVM` field. The clone itself was never executed, never
put on PATH, and never installed anywhere; it sits in
`agent/gno-mcp-upstream/` as a reference copy only.

Consequence for the skill: `agent/SKILL.md` documents both paths for
every step, names the fallback as the verified working path, and
states that the `gno_read` and `gno_call` steps are the intended
path, not a verified path. One real difference between the paths is
recorded: on the `local` gnomcp profile, writes sign with the
built-in `test1` agent key, while the fallback signs with
`realmcheck-dev`, so the stored Auditor address differs by path.

## 2. Agent config and skill (agent/)

| File | What |
| --- | --- |
| `agent/mcp-config.json` | MCP server config: `gnomcp` stdio command with no arguments, the local (`dev`, 127.0.0.1:26657) and Onyx (`onyx-1`) endpoints, the `realmcheck-dev` key reference by name only (address `g1yzqhuxczln72kwm9pstcmjerhnu0uverkuyz4h`), the pinned gnomcp commit, and the unverified-on-this-VM status note. No private key or mnemonic anywhere in the file. |
| `agent/SKILL.md` | The agent skill: contract (`docs/API.md`), scoring weights (critical 25, high 15, medium 8, low 3; score is 100 minus the sum), the rule that an LLM only explains findings and never scores, the audit engine choice (JS port under node, with the reason and the Gno `Audit()` cross-check), and the four steps: (a) read with `gno_read` (`full=true`, whole file) or `vm/qfile`; (b) audit with `ui/src/lib/audit.js` under node; (c) store with `SubmitReport` (gas-wanted 10,000,000 plus 7,000,000 per finding, gas-fee gas-wanted divided by 500, chain ID `dev` locally or `onyx-1` on Onyx); (d) verify with `GetReport`, `ReportFindings`, `LatestReport`, `ReportCount`, and `Render`, then report score, findings with cited lines, and report ID. Ground truth table for all 5 demo realms included. |
| `agent/audit.mjs` | Steps (a) and (b) as a runnable helper: `vm/qfile` fetch, byte-identity check against the local source, JS port audit, writes a work JSON file with source hash, score, findings, and the `SubmitReport` encoding. |
| `agent/verify-report.mjs` | Step (d) as a runnable helper: all five read-back checks plus the gnoweb page, exit 0 only when every check passes. |
| `agent/run-audit-local.sh` | The one-command audit flow. Starts its own fresh local chain, deploys vulnmint then adminbackdoor from staged byte-identical copies, runs the skill steps, submits, verifies, stops the chain. Output teed to `agent/m5-agent-run.log`. |
| `agent/README.md` | What agent mode is, how to install and configure it (including the gnomcp version verified and the honest unverified status), the one-command flow, the local-chain proof, and the limits. |
| `agent/gno-mcp-upstream/` | Reference clone at the pinned commit. Never built, never run. |

## 3. Agent-run audit, end to end (local gnodev chain)

Run twice in a row from a clean shell with the verbatim command
`bash agent/run-audit-local.sh` (27 Nov 2026, 14:34 and 14:35 WITA).
Both runs PASSED with byte-identical results. Full log:
`agent/m5-agent-run.log` (second run: 36 PASS, 0 FAIL).

- Realm audited: `gno.land/r/dunoil/adminbackdoor`
- Source read from the chain with `vm/qfile`, byte-identical to
  `contracts/demo/adminbackdoor/adminbackdoor.gno` (4,872 bytes)
- Source SHA-256:
  `a90ab97b23f02dedac27504008afc93d0ecbbf4e4d2270346fe38f494e36cc90`
- Score: 37, exactly the expected ground truth
- Findings (4): RC-01 high at line 105 (Sensitive function without
  caller check), RC-03 critical at line 75 (Single admin backdoor),
  RC-07 medium at line 84 (Unchecked external realm call), RC-08 high
  at line 53 (Public state mutation without guard). Arithmetic check:
  25 plus 15 plus 8 plus 15 is 63, and 100 minus 63 is 37.
- Gno `Audit()` cross-check: the JS port and Gno `Audit()` agreed
  exactly on rule, severity, line, title, description, and source
  line (also for vulnmint: score 75, RC-02 at line 41, in the same
  driver run)
- Stored report ID: 1 (fresh local chain)
- Gas: wanted 38,000,000, used 26,277,587, fee 76,000 ugnot
- Height: 3
- Transaction hash: `9SSLsnSo9O6lSA58l7bEGyfXJJ7P90HZtP7ojM+dsLM=`
- Auditor: `g1yzqhuxczln72kwm9pstcmjerhnu0uverkuyz4h`
  (`realmcheck-dev`)
- Verified after storing: `GetReport(1)`, `ReportFindings(1)`,
  `LatestReport("gno.land/r/dunoil/adminbackdoor")`,
  `ReportCount()` is 1, `Render("")` lists `#1 ... score 37`, and the
  gnoweb page `http://127.0.0.1:8888/r/dunoil/realmcheck` serves
  HTTP 200 listing the report
- Deploy transactions in the same run: vulnmint addpkg gas 6,785,211,
  height 3, tx `IScoKdTJ7LSx+3/GvmrolWIyB44DwyhyzNXJeGM3sVc=`;
  adminbackdoor addpkg gas 9,874,086, height 5, tx
  `fs115o2UPzGmjCte4a1BrYj6wUJ1cZOaGkqM6QsV6gc=`
- Work files: `agent/m5-work/adminbackdoor.json` (audit output),
  `agent/m5-work/report.json` (report record),
  `agent/m5-work/submit-adminbackdoor.txt` (raw maketx output),
  `agent/gnodev-m5.log` (chain log)
- Path used: gnokey plus node fallback. No tool-call trace through
  gnomcp exists, because gnomcp never ran here. This is the fallback
  the task asked for when gnomcp is unusable, and the skill documents
  it as the working path.

## Verification before finishing

- Skill commands re-run verbatim from a clean shell: the full driver
  ran twice (`bash agent/run-audit-local.sh`), both RESULT: PASSED,
  identical report ID, score, gas used, height, and transaction hash.
- Stored report verifies with `GetReport`: yes, see section 3 above
  (all five read-back checks plus gnoweb, in the log).
- `gno test -p 1 .` still passes, untouched: `contracts/auditrules`
  52 PASS, `contracts/realmcheck` 11 PASS (same counts as M4). Demo
  realms also re-ran clean (5 suites, all ok).
- No temporary test file left in `contracts/realmcheck/` (the
  cross-check driver deletes its own temp test; verified by listing
  the directory after the run).
- No stray gnodev left running: port 26657 is free after the run, and
  the driver stopped its own chain (pid 29126 on the second run).
- Files changed by this milestone: only `agent/**` (new) and this
  status file. `contracts/**`, `ui/**`, `scripts/**`, `tests/**`,
  `docs/**`, and all other READMEs were not edited.

## Side effects and small mistakes, disclosed

- The Gno cross-check runs the project's existing driver
  (`node scripts/e2e-local.mjs audit`), which writes its own work
  files to `scripts/e2e-work/` by design. That driver rewrote
  `scripts/e2e-work/adminbackdoor.json` and `vulnmint.json` during
  my run (06:36 timestamps). No script was edited; the files are the
  driver's normal output, the same as the M4 harness produces.
- During the verification re-run I briefly redirected a copy of the
  driver output to `/tmp/m5-rerun-out.txt`. The project rule is never
  `/tmp`. The file was deleted immediately afterwards, and the run
  log itself lives in `agent/m5-agent-run.log` as intended. No
  evidence was lost: both runs produced identical output.
- The first driver invocation failed at once with `Permission denied`
  (the self-tee re-invoked the script directly, but the file is not
  executable). Fixed by re-invoking through `bash` in the script
  itself. The fix is in `agent/run-audit-local.sh`.

## Deliberately left out, with reasons

- No live gnomcp tool-call trace: impossible here, the server could
  not be run on this VM (section 1). Revisit when gnomcp can be
  installed on a machine where building it is allowed; the skill
  already documents the exact `gno_read` and `gno_call` calls to use.
- No Onyx run: the Onyx faucet needs a captcha, a browser step, and
  no Onyx-funded key exists yet. The Onyx end-to-end run belongs to
  M6, not M5.
- No session-based writes: sessions are work in progress upstream,
  and this flow does not need them. The skill says so.
- No Adena signing: out of scope for agent mode; the UI keeps the
  Adena stub until M6.
- No install commands copied from the upstream README into the agent
  docs: the upstream checkout failed a safety check, so the docs
  point at the upstream README at the pinned commit instead of
  reproducing its commands. Read the README there before installing.

## Still open (not blockers for M5)

- Verify gnomcp for real on a machine where building it is allowed:
  install the binary at the pinned commit, register the server from
  `agent/mcp-config.json`, and repeat the adminbackdoor audit through
  `gno_read` and `gno_call`, confirming the stored report and noting
  the `test1` auditor address on the local profile.
- M6 still needs Onyx faucet funds; the faucet
  (https://faucet.gno.land) requires a captcha, a browser step.
