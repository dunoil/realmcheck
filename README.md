# RealmCheck

Read the source before you trust the realm.

RealmCheck is a deterministic auditor for Gno.land realms, built for the
Gnome Tavern Hackathon (DoraHacks, Gno.land, Onyx testnet). Paste any realm
path, get a risk score from 0 to 100 with findings that cite the exact
source lines, plus a plain-English explanation of each finding and the fix
pattern. Saving a report stores it on chain with its source hash, so
anyone can re-run the audit and compare.

## Status (27 Nov 2026)

M1 to M5 are done and verified: rules, report realm, demo realms, UI, and
agent mode all pass their checks on a local chain. M6 (Onyx deploy) is
prepared but NOT yet run: the deploy script is proven end to end on a
local chain with the real Onyx key, and the signed bytes were proven to
reach the Onyx node, which decoded them and rejected them only with
`UnknownAddressError` because the deployer key is unfunded. The Onyx
deploy is pending faucet funding: the deployer key needs GNOT from
https://faucet.gno.land (a captcha step in a browser). Until the deploy
lands, the seven Onyx paths below are the planned paths, not live links,
and the UI audits the demo realms from bundled local sources. The GitHub
Pages site is also not live yet: the workflow in this repo is ready, but
Pages still needs to be enabled in the repo settings (see
[Live demo](#live-demo)).

- Repo: https://github.com/dunoil/realmcheck (public, MIT)
- Hackathon: Gnome Tavern Hackathon, DoraHacks,
  https://dorahacks.io/hackathon/gnome-tavern/detail
- Submissions close 18 Dec 2026 01:00 UTC (09:00 WITA). Winners announced
  21 Dec 2026.

## Why this can only exist on Gno.land

On most chains a contract is opaque bytecode: an auditor must decompile
it and guess what the deployed code does. On Gno.land every realm is
readable source on chain. RealmCheck audits exactly the source that is
deployed, with no decompiler and no off-chain repository that might
differ from the deployed code. Reports are themselves stored on chain,
so a score is verifiable by anyone, and a realm's report page is
rendered by the report realm itself through `Render()`. The Gno.land
team's own roadmap issue (#5661, use case U1) names pre-interaction
safety checks as a target use case, and `gnomcp` was launched for
exactly this.

## What it does

1. **Paste a realm path** such as `gno.land/r/gov/dao`. The UI fetches
   the realm source live from the Onyx testnet with the `vm/qfile`
   query. No source ever leaves your browser except the report you
   choose to save.
2. **Eight deterministic rules (RC-01 to RC-08)** scan the source. The
   same rules run on chain as the `auditrules` package and in the
   browser as a plain JavaScript port, so the UI result and the
   on-chain result agree exactly.
3. **A score from 0 to 100**, 100 minus the severity weight of each
   finding: critical 25, high 15, medium 8, low 3. The score is
   deterministic: the same source always produces the same score. An
   LLM only explains findings, it never scores.
4. **Each finding cites the exact source line** and links to an
   "explain this function" view: the enclosing function with the
   finding line highlighted, the plain-English risk, the attacker
   view, what to check, and the fix pattern.
5. **Save the report on chain** in the report realm, with the realm
   path, source hash, score, and findings. Anyone can load a stored
   report later and re-run the audit to compare. Share links
   (`?realm=` and `?demo=`) auto-run the audit for the recipient.

Findings are signals for human review, not verdicts. A clean result
means no known shape was found, not that the realm is safe.
RealmCheck never moves funds and never calls a realm on your behalf.

## Architecture

| Part | Path | What |
| --- | --- | --- |
| Audit rules (pure package) | `contracts/auditrules/` | `auditrules` Gno package, rules RC-01 to RC-08. `Audit(src)` returns findings, `Score(findings)` returns 0 to 100. Pure and stateless, so other projects can import it. This is the retention prize hook: the hackathon rewards projects that other projects import. |
| Report realm | `contracts/realmcheck/` | `realmcheck` realm. `SubmitReport` stores a report (realm path, source hash, score, findings) and returns its ID. `GetReport`, `LatestReport`, `ReportCount`, `ReportFindings`, and `Render` read it back. `Render` makes a report a readable web page on gnoweb. |
| Demo vulnerable realms | `contracts/demo/` | Five deliberately vulnerable realms that prove detection works. Each is small, readable, valid, and passes its own `gno test` suite. The vulnerabilities are intentional and documented, not bugs. Do not use this code for a real token, vault, registry, game, or treasury. |
| Web UI | `ui/` | Static React app. Fetches realm source live, audits it in the browser with the JS port of the rules, shows the report page, and saves reports on chain with Adena or with a `gnokey` command. Deployed on GitHub Pages (free). |
| Agent mode | `agent/` | MCP server config plus a `gno` agent skill, so a coding agent can run the same audit flow from chat (read, audit, store, verify). See [Agent mode](#agent-mode). |

The deploy order matters: `realmcheck` imports `auditrules`, and
`adminbackdoor` imports `vulnmint`, so `auditrules` deploys first and
`adminbackdoor` deploys last.

## The eight rules

Full detail, including suppression conditions and known limits, is in
`contracts/auditrules/README.md`. The scanner is lexical, not a full
parser: it blanks comments and string contents, tracks brace depth to
find function spans, and looks for known risky shapes. A guard must
appear in the same function body as the sensitive action.

| ID | Rule | Severity | Weight | Triggers when |
| --- | --- | --- | --- | --- |
| RC-01 | Sensitive function without caller check | High | 15 | An exported function moves funds (`SendCoins`, `RemoveCoin`, `Transfer(`, `Withdraw`, admin setters) with no caller guard in its own body. |
| RC-02 | Unrestricted mint | Critical | 25 | An exported function named `Mint` issues coins or grows supply with no caller guard in its own body. |
| RC-03 | Single admin backdoor | Critical | 25 | A single admin or owner can drain funds or rewrite state, with no timelock or multi-signature check on the path. Two shapes: a stored admin variable on a drain path, or a hard-coded admin constant (an admin or owner variable initialized with an address literal) guarding a drain or state rewrite. |
| RC-04 | Unbounded storage growth | Medium | 8 | A persistent collection (a package-level slice or a struct field) is appended to with no length check or cap token in the same function. |
| RC-05 | Funds accepted without a check | High | 15 | A function reads coins sent with the transaction through `OriginSend` but never verifies the amount. |
| RC-06 | Weak randomness | Medium | 8 | Block height, block time, or `time.Now` is used with modulo (`%`) or a random call, or is passed as an argument to a helper in the same file that applies modulo or a random call to that parameter (taint follows parameters across calls in the same file, up to eight hops). |
| RC-07 | Unchecked external realm call | Medium | 8 | A cross-realm call through `cross()` is made as a bare statement, with no assignment and no error mention on the line. |
| RC-08 | Public state mutation without guard | High | 15 | An exported function mutates realm state (a package-level variable assignment or a `.Set(`, `.Delete(`, or `.Remove(` call) with no caller guard in its own body. `Render` is never flagged. |

Overlap policy, so one root cause does not produce a stack of findings:
`IssueCoin` is covered by RC-02, not RC-01. Mint and withdraw style
functions are covered by RC-01, RC-02, and RC-03, not RC-08. Append
growth is covered by RC-04, not RC-08.

### Scoring

`Score` starts at 100 and subtracts the severity weight of each
finding, floored at 0. One critical finding scores 75, one high
scores 85, one medium scores 92.

### Known limits (honest)

- Guards in wrapper functions do not count. A guard must appear in
  the same function body as the sensitive action.
- A mutation inside a closure passed to another function is scanned as
  part of the enclosing function, because the scanner cannot prove the
  callee only runs it after a vote. On live Onyx code this leaves one
  known false positive: `sys/params` `run_submitters.gno:151`, a state
  rewrite inside a closure passed to `newDelegateProposal`. It stays
  flagged on purpose; trusting the callee name would hide a real
  finding in a realm that invokes the closure immediately.
- RC-01 does not flag ledger payouts. A function that pays out by
  updating an internal ledger with no banker call contains no RC-01
  action token. The `unguardedvault.Withdraw` demo is that case; the
  missing caller check is proven by its test, not by a finding.
- RC-06 taint follows parameters in the same file only, not local
  variables, and stops after eight hops. RC-05 only detects the
  `OriginSend` shape. RC-03 needs a stored or hard-coded admin to
  fire.
- A clean audit is not proof of safety, and a finding is not proof of
  exploitability. Both need human review.

## Demo realms and ground truth

Ground truth is `ui/scripts/expected-findings.json`, regenerated from
the real Gno `Audit()`. The JavaScript port matches `Audit()` exactly
on all five realms. Scores verified 27 Nov 2026.

| Realm | Score | Findings | What it demonstrates |
| --- | --- | --- | --- |
| `vulnmint` | 75 | RC-02 critical, line 41 | A GRC20-like token whose `Mint` has no access control: anyone can mint any amount to any address. |
| `unguardedvault` | 70 | RC-05 high, line 48; RC-08 high, line 51 | A vault that credits deposits without verifying any payment, and lets anyone call `Withdraw` to take anyone's funds. |
| `greedystore` | 92 | RC-04 medium, line 47 | A registry that appends every entry to a persistent list with no cap, so storage grows without bound. |
| `luckydice` | 62 | RC-05 high, line 61; RC-06 medium, line 69; RC-08 high, line 103 | A dice game whose winning number comes from block height and block time, and is publicly readable before betting. |
| `adminbackdoor` | 37 | RC-01 high, line 105; RC-03 critical, line 75; RC-07 medium, line 84; RC-08 high, line 53 | A treasury where a single hard-coded admin can drain all funds at once, and bonus payouts ignore the result of an external realm call. |

All eight rules fire on at least one demo realm.

### Live Onyx smoke test (27 Nov 2026)

The same `fetchRealmFiles` plus `audit.js` path the UI uses, run
against real Onyx realms whose sources are unchanged since the M1-M3
baseline (same SHA-256):

- `gno.land/r/gov/dao`: 100/100, 0 findings.
- `gno.land/r/sys/params`: 85/100, 1 finding (RC-08,
  `run_submitters.gno:151`, the DAO-proposal closure case, kept on
  purpose).

Test files (`*_test.gno`) are never fetched: test code legitimately
calls realms without guards and ignores return values, so auditing it
only produces noise.

## Live demo

The UI is a static site served from GitHub Pages at:

- https://dunoil.github.io/realmcheck/

Status: the Pages workflow (`.github/workflows/pages.yml`) is in this
repo and the build passes, but Pages is not enabled yet, so this URL
is not live as of 27 Nov 2026. The owner step is in
`docs/SUBMISSION.md`: enable Pages in the repo settings (Settings,
Pages, Build and deployment, Source: GitHub Actions), then the next
push to `main` deploys it. The build uses relative asset paths
(`base: './'` in `ui/vite.config.ts`), so it serves correctly under
the `/realmcheck/` subpath.

Try it with a realm that exists on Onyx today: `gno.land/r/gov/dao`
(100/100) or `gno.land/r/sys/params` (85/100). The five demo realms
are one-click cards that audit bundled local sources in your browser
until the Onyx deploy lands; after the deploy the same cards will
audit them live from the chain.

## How to use the UI

- **Search:** paste any realm path (`gno.land/r/...`) and press Audit
  realm. The UI fetches the source live from the configured RPC
  (default Onyx) and shows the score, the findings with cited lines,
  and the explain view on every finding card.
- **Demo showcase:** the five demo realms are one-click cards with
  their expected scores and findings. They run entirely in your
  browser against bundled sources, clearly labeled as local demos,
  and saving on chain is disabled for them.
- **Explain this function:** every finding card expands to show the
  enclosing function with the finding line highlighted, plus the
  plain-English risk, the attacker view, what to check, and the fix
  pattern.
- **Share links:** `?realm=<path>` and `?demo=<name>` deep links
  auto-run the audit. A copy-link button sits on every report.
- **Save on chain:** the "Save this report on chain" panel shows the
  exact `gnokey maketx call` command for the report realm
  (gas-wanted 10,000,000 plus 7,000,000 per finding, gas-fee
  gas-wanted divided by 500). Adena connect is implemented and
  present but disabled until the live test with a real extension and
  a funded key lands; the `gnokey` command works today with a funded
  Onyx key.
- **Stored reports:** "View stored report" loads a report from the
  report realm by realm path, with its score, auditor, height, and
  source hash.

### Configuration

The UI reads three environment variables at build time, defaulting to
Onyx:

- `VITE_GNO_RPC` (default `https://rpc.onyx.testnets.gno.land`)
- `VITE_GNOWEB` (default `https://onyx.testnets.gno.land`)
- `VITE_REALMCHECK_REALM` (default `gno.land/r/dunoil/realmcheck`,
  the local placeholder namespace; see below)

After the Onyx deploy, build with the deployed path:
`VITE_REALMCHECK_REALM=gno.land/r/g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu/realmcheck`
and redeploy the static UI. Do not change the default in
`ui/src/lib/gnoRpc.js` until the deploy is verified; the
`dunoil` default is what the local end-to-end harness expects.

## Agent mode

`agent/` lets a coding agent run the same audit from chat: read a
realm, run the deterministic audit, store the report on chain, verify
it stored. The skill is `agent/SKILL.md` (four steps), the config is
`agent/mcp-config.json`, and `bash agent/run-audit-local.sh` runs the
whole flow against a fresh local chain in one command. It audited
`adminbackdoor` end to end on 27 Nov 2026: score 37, 4 findings,
stored as report ID 1, verified with `GetReport`,
`ReportFindings`, `LatestReport`, `ReportCount`, `Render`, and the
gnoweb page. See `agent/README.md` and `VERIFY-M5.md`.

Honest note on `gnomcp`: the intended agent path runs through the
official `gnomcp` MCP server (repo `github.com/gnoverse/gno-mcp`,
pinned commit `e065fbc`, version v0.13.1 plus 4 commits), with the
`gno_read` and `gno_call` tools. That path is NOT verified on this
machine: building or running the freshly cloned upstream checkout was
blocked by an execution-risk check on this VM, so no `gnomcp` binary
was built, no server was started, and no tool call was ever made
through it. The config and skill are therefore the intended path, not
a verified path. The verified path is `vm/qfile` plus `gnokey` plus
node, and the agent-run audit above went through that fallback.
`gnomcp` is also pre-release, unaudited, testnet-only by
construction, and its API is unstable, so agent mode is additive
only: if it breaks, the core product (rules package, report realm,
UI) still stands on its own. Live `gnomcp` verification needs a
machine where building it is allowed.

## Onyx deployment

Deployer key: `realmcheck-onyx`, address
`g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu`. Key material lives only
in the project `.gnokey/` directory (mode 600, gitignored, never in
the repo).

Planned paths on Onyx (chain id `onyx-1`), in deploy order:

| Step | Package | Path on Onyx |
| --- | --- | --- |
| 1 | auditrules (pure package) | `gno.land/p/g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu/auditrules` |
| 2 | realmcheck (realm) | `gno.land/r/g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu/realmcheck` |
| 3 | vulnmint (demo realm) | `gno.land/r/g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu/vulnmint` |
| 4 | greedystore (demo realm) | `gno.land/r/g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu/greedystore` |
| 5 | luckydice (demo realm) | `gno.land/r/g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu/luckydice` |
| 6 | unguardedvault (demo realm) | `gno.land/r/g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu/unguardedvault` |
| 7 | adminbackdoor (demo realm) | `gno.land/r/g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu/adminbackdoor` |

Gnoweb links (live once the deploy is verified):

- https://onyx.testnets.gno.land/p/g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu/auditrules
- https://onyx.testnets.gno.land/r/g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu/realmcheck
- https://onyx.testnets.gno.land/r/g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu/vulnmint
- https://onyx.testnets.gno.land/r/g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu/greedystore
- https://onyx.testnets.gno.land/r/g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu/luckydice
- https://onyx.testnets.gno.land/r/g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu/unguardedvault
- https://onyx.testnets.gno.land/r/g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu/adminbackdoor

### Deploy steps

Full checklist and failure notes: `docs/ONYX-DEPLOY.md`.

1. **Fund the key** (owner browser step, captcha):
   https://faucet.gno.land, paste the deployer address, pick Onyx
   (chain id `onyx-1`), pick 100, 200, or 300 GNOT. One 100 GNOT
   request covers the whole deploy several times over: the whole
   deploy measured 12.05 GNOT on a local chain, and the script
   refuses to run below 20 GNOT.
2. **Run the deploy** (offline-sign path, proven 27 Nov 2026):
   ```bash
   bash scripts/offline-sign-deploy.sh --key realmcheck-onyx --deployer g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu
   ```
   It signs with `gnokey` offline and broadcasts with `curl`, because
   `gnokey` cannot reach Onyx from this VM (its HTTP client ignores
   the egress proxy). The same path deployed all 7 packages and a
   test `SubmitReport` end to end on a local chain with the real Onyx
   key, and the signed bytes reached the Onyx node and decoded there.
   `scripts/deploy-onyx.sh` is the alternative for a machine where
   `gnokey` itself can reach Onyx.
3. **Verify:** the script byte-diffs every deployed `.gno` file
   against the on-chain copy, submits a test report for `vulnmint`,
   and expects the ground truth (score 75, RC-02 at line 41).

A package path on Gno.land is immutable: it cannot be overwritten or
deleted. A corrected deploy goes under a new path, and the old path is
recorded as superseded.

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
node ui/scripts/test-audit-rules.mjs   # 24 fixture cases for the rule shapes

# UI build
cd ui && npm install && npm run build

# Live Onyx smoke test (same code path as the UI)
node ui/scripts/smoke-onyx.mjs
```

The local end-to-end harness (`bash scripts/e2e-local.sh`) starts a
fresh local chain, deploys two demo realms, audits them, stores both
reports on chain, verifies them back, and checks the UI against the
local chain. It passed clean on 27 Nov 2026: report #1 vulnmint
score 75 (1 finding), report #2 adminbackdoor score 37 (4 findings).

## How this entry maps to the judging criteria

Judged by the Gno.land team. Technical quality 40%, User appeal 20%,
Creativity 20%, Docs and demo 20%.

- **Technical quality 40%:** real Gno throughout: a pure rules
  package with 52 unit tests, a report realm with 11 tests, five
  demo realms with 26 tests, a JS port that matches Gno `Audit()`
  exactly on all five realms, a local end-to-end harness that passes
  clean, and a deploy path proven on a local chain and proven to
  reach the Onyx node. The score is deterministic, and the rules
  were verified live against real Onyx realms (`gov/dao` 100/100,
  `sys/params` 85/100) with sources unchanged.
- **User appeal 20%:** anyone who has ever hesitated before calling
  an unknown realm is the user. Paste a path, get a readable report
  with cited lines, an explain view, and a share link. Reports are
  stored on chain, so a score can be checked by anyone before they
  interact with a realm.
- **Creativity 20%:** an auditor as a realm. Reports live on chain
  and are composable: other realms and UIs can query a realm's latest
  score before calling it. The audit itself is only possible because
  Gno.land keeps contracts as readable source on chain.
- **Docs and demo 20%:** this README, the per-package READMEs, the
  API and deploy docs, the verification records per milestone, five
  worked demo realms with ground truth, and the demo video (see
  `docs/SUBMISSION.md`, currently TBD).

## Hackathon facts

- Gnome Tavern Hackathon, DoraHacks, submissions 23 Nov to 18 Dec
  2026 01:00 UTC. Judging 18 to 21 Dec, winners announced 21 Dec.
- Prize: $40,000 total, paid in GNOT. Upfront $10,000 across 16
  projects: 1st $2,000, 2nd $1,000, 14 Builder Awards of $500.
  Retention prize up to $30,000 at months 3 and 6 for projects that
  stay live and used (mainnet deployment, 50/100 unique users,
  500/1,500 realm calls, 20/50 monthly active users, at least 1 other
  project importing or using it, followers, regular updates).
- No tracks or themes. No "Gno" prefix in the project name (this
  project is named RealmCheck).
- Disqualification: no working testnet deployment, no public repo, or
  no real use of Gno. Design mockups, slides, or concepts only are
  not eligible.
- KYC is required only for winners at payout (deadline 22 Dec).
  Nothing in this repo does KYC now.

## Docs

- `docs/API.md`: the API contract between the report realm, the UI,
  and agent mode (function shapes, finding encoding, gas formula).
- `docs/ONYX-DEPLOY.md`: the Onyx testnet deploy checklist and
  commands, including the offline-sign path and the faucet steps.
- `docs/SUBMISSION.md`: the DoraHacks submission package, drafted
  fields, pre-submit checklist, and the post-deploy UI copy change.
- `BUILD-PLAN.md`: the milestone plan (M1 to M8, submit 18 Dec only
  after explicit final approval).
- `VERIFY-M1M3.md`, `VERIFY-M4.md`, `VERIFY-M5.md`,
  `VERIFY-M6-PREP.md`: verification records per milestone.
- `ENV-ONYX.md`: the verified Onyx endpoints, faucet flow, and key
  commands.
- `ENV-TOOLCHAIN.md`: the Go and Gno toolchain setup.
- `contracts/auditrules/README.md`: the eight rules in detail,
  scoring, and known limits.
- `contracts/demo/README.md`: the five demo realms and their ground
  truth.
- `contracts/realmcheck/README.md`: the report realm API.
- `ui/README.md`: the UI in detail.
- `agent/README.md`: agent mode, the gnomcp config, and the honest
  limits.

## License

MIT.
