# RealmCheck: BUILD-PLAN

## Project

RealmCheck is Duan's solo entry for the Gnome Tavern Hackathon (DoraHacks, Gno.land), built to WIN.

- Builder: Duan, solo, DoraHacks username dunoil
- Registered: 27 Nov 2026 12:06 WITA
- Repo (to create when code is ready): https://github.com/dunoil/realmcheck (public, MIT)
- Language: everything built in English. Progress reported in Indonesian in the side chat at each milestone.

## Hackathon facts (verified live 27 Nov 2026)

- Submissions: 23 Nov to 18 Dec 2026 09:00 WITA (01:00 UTC). Internal safe submit date: **17 Dec 2026**.
- Deploy on Onyx testnet (onyx-1). Public repo + README + demo video required.
- Prize: $40,000 in GNOT. Upfront $10,000 across 16 projects: 1st $2,000, 2nd $1,000, 14x $500 Builder Awards. Retention prize up to $30,000 at months 3 and 6 for projects that stay live and used (needs mainnet deployment, 50/100 unique users, 500/1,500 realm calls, 20/50 monthly active users, at least 1 other project importing or using it, followers, regular updates).
- Judging: Technical quality 40%, User appeal 20%, Creativity 20%, Docs and demo 20%. Judged by the Gno.land team. Winners 21 Dec.
- Project names cannot use the "Gno" prefix.
- KYC is required only for winners at payout (deadline 22 Dec). KYC is DEFERRED. Do not do any KYC now.
- Source of truth: ~/workspace/research_notes/gno-land-ecosystem-20261127-0410/report.md, section 6, Idea 1.

## What RealmCheck is

Paste any realm path (gno.land/r/...) and get a beautiful report page: a risk score, plain-English findings with exact source lines cited, and a one-click "explain this function" view.

Why it can only exist on Gno.land: every contract is readable source on-chain, not opaque bytecode. An auditor can read a realm exactly like a codebase. The Gno.land team's own roadmap issue (#5661, use case U1) names pre-interaction safety checks as a target use case, and gnomcp was launched for exactly this.

## Architecture

1. **Audit-rules pure package** (`gno.land/p/dunoil/auditrules`, path to confirm against toolchain docs): deterministic, testable rules. Pure package so other projects can import it. This is the retention prize hook.
2. **Report realm** (`gno.land/r/dunoil/realmcheck`, path to confirm): stores audit reports on-chain (auditor, realm path, version/hash, findings, score) so reports are shareable and verifiable. Exposes Render() so a report is also a readable web page.
3. **Demo vulnerable realms** (3 to 5, on Onyx): deliberately vulnerable realms that prove detection works. Examples: unrestricted mint, missing caller check on a funds function, unbounded storage growth.
4. **Web UI**: polished static app. Search a realm, show the report page with score, findings, cited lines, share link. Calls the Onyx testnet via RPC/gnoweb and Adena wallet where needed. Deploy on GitHub Pages (free).
5. **gnomcp agent mode**: MCP server config + agent skill so a Claude/Cursor agent can run the same audit from chat using gno_read/gno_render. Additive only; the core product must work without it.

## Audit rules (initial set, 5 to 8, deterministic)

The deterministic rules produce the score. An LLM only explains findings, never scores.

1. Sensitive function callable without a caller check (no IsUser/IsRealm/OriginCaller guard on a function that moves funds or changes admin state).
2. Unrestricted mint (mint function with no access control).
3. Owner or admin backdoor (single-address admin can drain funds or rewrite state with no check or timelock).
4. Unbounded storage growth (persistent collections appended without a cap, which grows the storage deposit without bound).
5. Funds accepted without a check (a function receives coins without verifying sender or amount).
6. Weak randomness (block height or time used as a randomness source).
7. Unchecked external realm call (calling another realm and ignoring its return or failure).
8. Public state mutation with no guard (a state-changing function exposed with no caller restriction at all).

Phase 2 refines this list against the real Gnolang APIs (std.Coin, std.OriginCaller, etc.) and drops any rule that cannot be checked reliably from source.

## Phases and milestones

| Milestone | Date | Work |
|---|---|---|
| M1 | 28 Nov | Phase 1 done: environment verified, this plan final (DONE 27 Nov, ahead of schedule) |
| M2 | 1 Dec | Phase 2 done: rules package + unit tests + 3 demo vulnerable realms, passing on gnodev (DONE 27 Nov: 8 rules, 30 tests pass; 5 demo realms, 24 tests pass) |
| M3 | 4 Dec | Report realm done (store/query/score + Render), UI skeleton calling it (DONE 27 Nov: realm verified end to end on gnodev local with a real audit; UI skeleton done and verified: build outputs static dist/, dev serves HTTP 200, audit port matches Gno Audit() exactly on all 5 demo realms, live smoke test against Onyx: gov/dao 85/100, sys/params 55/100) |
| M4 | 7 Dec | UI polished, end-to-end audit flow working locally on gnodev (DONE 27 Nov, ahead of schedule: all 8 rules fire on the demos, false positives fixed, UI polished with explain view and demo showcase, local E2E harness PASSED end to end; see VERIFY-M4.md) |
| M5 | 9 Dec | gnomcp agent mode done (config + skill + one agent-run audit) (DONE 27 Nov, ahead of schedule: config + skill + agent-run audit PASSED on local chain; gnomcp server itself NOT built or run on this VM, blocked by an execution-risk check, verified from docs only, see VERIFY-M5.md) |
| M6 | 12 Dec | Onyx deployment done, end-to-end test against a real realm, issues fixed (PREP DONE 27 Nov: public repo live, deploy script validated on a local chain, Adena implemented; OFFLINE-SIGN PATH PROVEN 27 Nov: scripts/offline-sign-deploy.sh plus scripts/txbin/ deploy all 7 packages and the test SubmitReport end to end on a local chain with the real Onyx key, RESULT PASSED, and the same signed bytes reach the Onyx node, which decodes them and rejects only with UnknownAddressError because the key is unfunded; faucet funding still pending, see the deployer key section below) |
| M7 | 15 Dec | Demo video recorded, README done, submission package assembled |
| M8 | 17 Dec | Submission package ready, reported to Duan for final approval |
| Submit | 18 Dec | Submit only after Duan's explicit final approval |

## M6 deployer key (created 27 Nov 2026)

- Key name: realmcheck-onyx. Address: g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu.
- Key material lives ONLY in ~/workspace/gnome-tavern-hackathon/.gnokey/ (gnokey home: encrypted keybase in .gnokey/data/keys.db, mnemonic in .gnokey/deployer-mnemonic.txt, password in .gnokey/password.txt). All files mode 600, directory mode 700, excluded by .gitignore, never in the repo. Use it with `gnokey -home ~/workspace/gnome-tavern-hackathon/.gnokey` (the GNOHOME env var is not respected; pass -home explicitly).
- Funding (owner browser step, captcha): https://faucet.gno.land, paste the address above, pick Onyx (chain id onyx-1), amount 100, 200, or 300 GNOT per request. Funding gate in the deploy script is 20 GNOT; the whole deploy measured 12.05 GNOT on a local chain. One 100 GNOT request covers it.
- gnokey cannot reach Onyx from this VM (its RPC client ignores the egress proxy; verified 27 Nov). The deploy therefore uses the offline-sign path: sign with gnokey offline, broadcast the signed bytes with curl (proxy-aware). See scripts/offline-sign-deploy.sh (built and proven 27 Nov: full local deploy PASSED, Onyx broadcast test returned UnknownAddressError only because the key is unfunded) and docs/ONYX-DEPLOY.md section 9.

## Rules

- Free only, never spend money. Testnet GNOT comes from the faucet. Hosting is GitHub Pages. No paid services.
- No em dashes and no en dashes in anything produced. Use commas, periods, or colons.
- Everything built in English. Progress reports in Indonesian.
- NEVER submit the hackathon entry form or publish the demo video without Duan's explicit final approval. Creating the public repo and deploying to the Onyx testnet are part of the build and are approved.
- KYC is deferred (winners only, at payout). Do not do any KYC now.
- Keep all work inside ~/workspace/gnome-tavern-hackathon/. Never /tmp (VM restarts wipe it).
- Verify against the live service, not just the code. A fix is done only when it passes on gnodev or Onyx.

## Risks and mitigations

- LLM audit quality varies: deterministic rules produce the score, the LLM only writes explanations.
- gnomcp is pre-release, unaudited, testnet-only, and its API is unstable: agent mode is additive. If it breaks, the core product (rules package + realm + UI) still stands on its own.
- Onyx faucet or RPC limits: check on day 1 of phase 5, keep a local gnodev fallback for the demo.
- VM memory is tight (about 1GB free): build the toolchain with low parallelism; prefer prebuilt binaries if available.
- Scope creep: if time is short, cut to realm + one polished page + video. A working deployment beats a broad unfinished app; undeployed and mockup submissions are explicitly ineligible.

## Environment status (updated 27 Nov, Onyx verified live)

- Go toolchain: INSTALLED 27 Nov, Go 1.25.9 (official go.dev tarball, SHA256 verified), exactly matching Gno v1.8.0 go.mod. Path ~/workspace/tools/go.
- Gno v1.8.0, commit fc79041f (2026-11-17). gnokey v1.8.0, gnodev built, gnoland v1.8.0 (stretch goal done). Binaries in ~/workspace/tools/gno/bin/. PATH: export PATH=$PATH:$HOME/workspace/tools/go/bin:$HOME/workspace/tools/gno/bin, GNOROOT=$HOME/workspace/tools/gno, GOMAXPROCS=2.
- Build note: gnoland first failed with a GNOROOT panic because -trimpath disables the caller-stack fallback; fixed by embedding GNOROOT via ldflag. All three binaries now work with GNOROOT unset. RAM: builds used -p 1, GOMAXPROCS=2, CGO_ENABLED=0, zero OOM kills. Status in ENV-TOOLCHAIN.md.
- Onyx testnet: VERIFIED LIVE 27 Nov (ENV-ONYX.md). Chain ID onyx-1, RPC https://rpc.onyx.testnets.gno.land (block height 1443524, catching up false, build v1.8.0-rc.1). gnoweb https://onyx.testnets.gno.land. Tx-indexer GraphQL https://indexer.onyx.testnets.gno.land/graphql/query (allow a retry, first contact can time out). Gnockpit https://gnockpit.onyx.testnets.gno.land.
- Old hostnames are DEAD: do not use rpc.testnet.gno.land, faucet.testnet.gno.land, or testnet.gno.land. Use the *.onyx.testnets.gno.land scheme.
- Faucet: https://faucet.gno.land (Faucet Hub), 100/200/300 GNOT per request, captcha required (hCaptcha/reCAPTCHA), cooldown per address unpublished. Fund the build key there; the captcha step is a browser step.
- GnoScan testnet (https://testnet.gnoscan.io) is NOT reachable from this VM. Re-check from another network or live browser. Fallbacks: gnoweb, Gnockpit, tx-indexer.
- Deploy: gnokey maketx addpkg -pkgpath "gno.land/r/<g1-addr>/<name>" -pkgdir . -gas-fee 5000ugnot -gas-wanted 5000000 -chainid onyx-1 -remote https://rpc.onyx.testnets.gno.land:443 <keyname>. Call with maketx call, read state with gnokey query vm/qeval (no gas). New packages take a few seconds to become callable.
- Chain runs v1.8.0-rc.1, newer than the v1.5.0 launch version. Pin or re-check the toolchain version before deploying.
- DoraHacks prize split note: the $40,000 total and the $10,000 upfront plus up to $30,000 retention split were verified live on the DoraHacks page by the research pass on 27 Nov. The Onyx subagent could not re-read the page (HTTP 405 to fetchers, a fetch limitation, not a contradiction). Re-check the live page in a browser before submitting.
- Adena wallet: browser extension wallet. Deployment itself uses gnokey + faucet, so Adena is not a blocker for the build. The UI will support Adena connect for users.
- Workspace: ~/workspace/gnome-tavern-hackathon/ created 27 Nov with contracts, ui, agent, docs, scripts, tests.
- Toolchain notes: `gno mod init` writes `gnomod.toml` (not `gno.mod`) in v1.8.0; the `gno` CLI is the test runner (`gno test -p 1 .`). No `std` package in v1.8.0: use `chain.Coins` and `cur.Previous().Address()`. API spec in docs/API.md.
