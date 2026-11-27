# RealmCheck

Read the source before you trust the realm.

RealmCheck is an AI-free, deterministic auditor for Gno.land realms, built
for the Gnome Tavern Hackathon (DoraHacks, Gno.land, Onyx testnet). Paste a
realm path, get a risk score from 0 to 100 with findings that cite the exact
source lines, plus a plain-English explanation of each finding and the fix
pattern. Saving a report stores it on chain with its source hash, so anyone
can re-run the audit and compare.

Source-on-chain auditing only works on Gno.land: every realm's source lives
on the chain itself and is readable by anyone, so the audit runs against
exactly what is deployed. There is no bytecode to decompile and no off-chain
repository that might differ from the deployed code.

## The three parts

- **Audit rules** (`contracts/auditrules/`): the `auditrules` Gno package,
  rules RC-01 to RC-08. `Audit(src)` returns findings, `Score(findings)`
  returns 0 to 100 (critical 25, high 15, medium 8, low 3). Same rules run
  on chain and in the browser.
- **Report realm** (`contracts/realmcheck/`): the `realmcheck` realm.
  `SubmitReport` stores a report (realm path, source hash, score, findings)
  and returns its ID. `GetReport`, `LatestReport`, `ReportCount`,
  `ReportFindings`, and `Render` read it back.
- **Web UI** (`ui/`): a static React app. It fetches realm source live with
  `vm/qfile`, runs the eight rules client-side (a direct port of the Gno
  rules), and saves reports on chain with Adena or with a `gnokey` command.
  Five deliberately vulnerable demo realms (`contracts/demo/`) prove the
  rules work; the UI audits their bundled sources locally.

Agent mode (`agent/`) adds an MCP server config and a `gno` agent skill that
runs the same audit flow (read, audit, store, verify). See `agent/README.md`.

## How to run the tests

Toolchain: Go 1.25.9 and Gno v1.8.0. See `ENV-TOOLCHAIN.md`.

```bash
# Gno contract tests (from the project root)
export PATH="$PATH:$HOME/workspace/tools/go/bin:$HOME/workspace/tools/gno/bin"
export GNOROOT="$HOME/workspace/tools/gno"
export GOMAXPROCS=2
gno test -p 1 ./contracts/auditrules/   # 52 tests
gno test -p 1 ./contracts/realmcheck/  # 11 tests
gno test -p 1 ./contracts/demo/...     # 26 tests across the 5 demo realms

# UI audit-port test (JS port must match the Gno rules on all 5 demos)
node ui/scripts/test-audit-port.mjs

# UI build
cd ui && npm run build
```

The local end-to-end harness (`bash scripts/e2e-local.sh`) starts a fresh
local chain, deploys two demo realms, audits them, stores both reports on
chain, verifies them back, and checks the UI against the local chain.

## Docs

- `docs/API.md`: the API contract between the report realm, the UI, and
  agent mode (function shapes, finding encoding, gas formula).
- `docs/ONYX-DEPLOY.md`: the Onyx testnet deploy checklist and commands.
- `BUILD-PLAN.md`: the milestone plan (M1 to M7).
- `VERIFY-M1M3.md`, `VERIFY-M4.md`, `VERIFY-M5.md`, `M6-PREP-STATUS.md`:
  verification records per milestone.
- `ENV-ONYX.md`: the verified Onyx endpoints, faucet flow, and key commands.
- `contracts/auditrules/README.md`: the eight rules in detail.
- `contracts/demo/README.md`: the five demo realms and their ground truth.
- `ui/README.md`: the UI in detail.

## Status (27 Nov 2026)

M1 to M5 are done and verified: rules, report realm, demo realms, UI, and
agent mode all pass their checks on a local chain. M6 (Onyx deploy) is in
preparation: the deploy script (`scripts/deploy-onyx.sh`) is validated
against a fresh local chain, the Adena signing flow is implemented in the UI
(live test with a real extension and a funded key still pending), and this
repo is ready to push. The Onyx deploy itself is blocked on faucet funds:
funding a key needs the Faucet Hub captcha in a browser
(https://faucet.gno.land). Until the deploy lands, the demo realms do not
exist on Onyx yet, and the UI audits them from bundled local sources.

## License

MIT.
