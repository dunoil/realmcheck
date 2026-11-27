# M5 Verification Record (27 Nov 2026)

Milestone M5 (due 9 Dec) is DONE ahead of schedule, with one honest
exception: the gnomcp server itself could not be built or run on
this VM. Everything else is built and verified live. Full agent
record in M5-AGENT-STATUS.md.

## What was built (agent/)

- agent/mcp-config.json: valid JSON, gnomcp stdio command, local
  (dev) and Onyx (onyx-1) endpoints, realmcheck-dev key by name only,
  pinned gnomcp commit e065fbc (v0.13.1-4-ge065fbc), and an explicit
  statusOnThisVM field saying NOT BUILT OR RUN HERE. No private key
  or mnemonic anywhere.
- agent/SKILL.md: four-step audit skill (read, audit, store, verify),
  cites docs/API.md, scoring weights (critical 25, high 15, medium 8,
  low 3), LLM explains only, gas formula (10,000,000 + 7,000,000 per
  finding, fee wanted/500), both the gnomcp calls and the gnokey/node
  fallback for every step, ground truth for all 5 demo realms.
- agent/audit.mjs, agent/verify-report.mjs, agent/run-audit-local.sh:
  runnable helpers and the one-command audit flow.
- agent/README.md: install/config, one-command flow, proof, limits.
- agent/gno-mcp-upstream/: read-only reference clone of
  github.com/gnoverse/gno-mcp at the pinned commit. Never built, never
  run, never on PATH, no binary exists anywhere in the project.

## The gnomcp block (stated plainly)

The freshly cloned upstream checkout failed an execution-risk check
on this VM: building, running, installing, or executing anything
from it was blocked, and the block also covers running git or package
manager commands inside the checkout and reproducing its install or
build commands. The agent handled it per the milestone's fallback
rule: recorded the block, verified gnomcp from its documentation by
reading only (25-tool catalog, profiles local/testnet/mainnet,
stdio config shape), and ran the audit through the gnokey plus node
fallback. The gnomcp calls in the skill are therefore the intended
path, not a verified path. Live gnomcp verification needs a machine
where building it is allowed; the skill documents the exact
gno_read and gno_call calls to use there. One real path difference is
recorded: on the gnomcp local profile, writes sign with the built-in
test1 agent key, while the fallback signs with realmcheck-dev, so the
stored Auditor address differs by path.

## Agent-run audit (coordinator re-ran it independently)

Command: bash agent/run-audit-local.sh, fresh local chain, run by the
coordinator after the agent's two runs. RESULT: PASSED, byte-identical
to the agent's runs (third identical result).

- Realm: gno.land/r/dunoil/adminbackdoor, source SHA-256
  a90ab97b23f02dedac27504008afc93d0ecbbf4e4d2270346fe38f494e36cc90
- Score 37, 4 findings: RC-01 high @105, RC-03 critical @75, RC-07
  medium @84, RC-08 high @53 (25 + 15 + 8 + 15 = 63; 100 - 63 = 37)
- Stored report ID 1, gas wanted 38,000,000, used 26,277,587, fee
  76,000 ugnot, height 3, tx
  9SSLsnSo9O6lSA58l7bEGyfXJJ7P90HZtP7ojM+dsLM=
- Auditor g1yzqhuxczln72kwm9pstcmjerhnu0uverkuyz4h (realmcheck-dev)
- Verified: ReportCount 1, GetReport, ReportFindings, LatestReport,
  Render lists #1 score 37, gnoweb page HTTP 200
- JS port and Gno Audit() agreed exactly (also vulnmint: score 75,
  RC-02 @41, in the same driver run)
- Chain stopped after the run; no stray gnodev left

## Coordinator checks at the close

- mcp-config.json parses as valid JSON.
- No em dashes or en dashes in any agent/ file.
- No gnomcp binary exists anywhere in the project.
- The /tmp file the agent briefly created was deleted (verified gone).
- scripts/e2e-work/*.json were rewritten by the audit driver by
  design (its normal output, same as the M4 harness produces); no
  script was edited.
- gno tests re-run by the coordinator: auditrules 52 PASS,
  realmcheck 11 PASS; audit-port test green on all 5 realms.

## Still open

- Verify gnomcp for real on a machine where building it is allowed:
  install at the pinned commit, register the server from
  agent/mcp-config.json, repeat the adminbackdoor audit through
  gno_read and gno_call, confirm the stored report and the test1
  auditor address on the local profile.
- M6 needs Onyx faucet funds; the faucet (https://faucet.gno.land)
  requires a captcha, a browser step. No Onyx-funded key exists yet.
