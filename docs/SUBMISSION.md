# RealmCheck: DoraHacks submission package (M7 draft)

Gnome Tavern Hackathon, DoraHacks, Gno.land, Onyx testnet.
Drafted 27 Nov 2026. DO NOT submit until Duan gives explicit final
approval (M8, 17 Dec; submit 18 Dec). Nothing in this file has been
submitted or published.

## 1. Submission fields (drafted)

Field names and limits below are the standard DoraHacks project
fields as understood from the hackathon requirements. The exact live
form fields were NOT re-checked on the DoraHacks page for this draft:
re-check them on the live form before submitting (see section 4).
Where a field is marked TBD, the value does not exist yet.

| Field | Draft value |
| --- | --- |
| Project name | RealmCheck |
| Tagline | Read the source before you trust the realm. |
| Short description | RealmCheck is a deterministic auditor for Gno.land realms. Paste any realm path and get a risk score from 0 to 100, with findings that cite the exact source lines, plus a plain-English explanation of each finding and the fix pattern. Reports are stored on chain, so anyone can re-run the audit and compare. |
| Track / category | None. The hackathon has no tracks or themes: "Build ANYTHING real on the Gno.land testnet." Leave any track field blank or select none; do not invent a track. |
| Public repo URL | https://github.com/dunoil/realmcheck |
| Deployment link (live testnet deployment) | https://onyx.testnets.gno.land/r/g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu/realmcheck (LIVE, verified 27 Nov 2026; all 7 packages enabled, reports #1 and #2 stored on chain; see checklist item 4.) |
| Live demo URL (web UI) | https://dunoil.github.io/realmcheck/ (LIVE since 27 Nov 2026 16:35 WITA; verified HTTP 200 and renders the app. Redeployed 27 Nov 2026 18:15 WITA after the post-deploy UI copy push: workflow run 45980432341, success in 30s, serves the updated UI with the deployed realm.) |
| Demo video URL | TBD (not uploaded anywhere yet). The Onyx cut is ready: docs/demo-video/realmcheck-demo.mp4, 103.0s, 1920x1080, recorded 27 Nov 2026 against the live Onyx deploy, QA passed; the local-chain cut is kept as realmcheck-demo-local.mp4 (107s). Upload to YouTube needs Duan's explicit approval. Do not submit without it: a demo video is required. |
| Team | Solo. Builder: Duan, DoraHacks username dunoil. |
| Tags (if the form asks) | Go, Blockchain, Smart Contracts, Layer 1, dApps, AI. These are the tags listed on the hackathon page. |

### Long description (draft for the project page)

RealmCheck answers one question before you call a realm: is it safe?

On most chains a contract is opaque bytecode, so an auditor must
decompile it and guess. On Gno.land every realm is readable source on
chain, so RealmCheck audits exactly the source that is deployed: no
decompiler, no off-chain repository that might differ from the
deployed code.

Paste any realm path and RealmCheck returns a risk score from 0 to
100, findings that cite the exact source lines, and a plain-English
explanation of each finding with the fix pattern. Eight deterministic
rules (RC-01 to RC-08) produce the score: unrestricted mint, admin
backdoor, missing caller checks, unbounded storage, unchecked funds,
weak randomness, unchecked cross-realm calls, and unguarded state
mutation. The score is deterministic: the same source always produces
the same score. An LLM only explains findings, it never scores.

Reports are stored on chain in the RealmCheck report realm, with the
realm path, source hash, score, and findings, so anyone can load a
stored report and re-run the audit to compare. The audit rules are a
pure package (`auditrules`) that any other project can import, and the
report realm renders reports as readable web pages through `Render()`.

Five deliberately vulnerable demo realms prove detection works, with
ground truth verified against the real Gno `Audit()`: vulnmint 75/100
(unrestricted mint), unguardedvault 70/100 (unchecked deposits),
greedystore 92/100 (unbounded storage), luckydice 62/100 (weak
randomness), adminbackdoor 37/100 (single-admin drain). The same rules
were verified live against real Onyx realms: `gov/dao` 100/100,
`sys/params` 85/100.

Agent mode (`agent/`) adds an MCP server config and a `gno` agent
skill, so a coding agent can run the same audit from chat: read, audit,
store, verify. The `gnomcp` path is the intended path and is stated as
unverified on the build machine in the README; the verified path is
`vm/qfile` plus `gnokey` plus node.

Built by one person in three weeks, free only: Gno v1.8.0, a static
React UI on GitHub Pages, Onyx testnet, no paid services.

## 2. Pre-submit checklist

Check each item off only when it is verified, not when it is planned.
Status as of 27 Nov 2026.

| # | Item | Status |
| --- | --- | --- |
| 1 | Repo public | DONE. https://github.com/dunoil/realmcheck, public, MIT, main branch. |
| 2 | README done | DONE. Full README in the repo root (M7): what it is, why it can only exist on Gno.land, architecture, all 8 rules with weights, demo ground truth, UI use, agent mode with the honest gnomcp note, deploy steps, judging map, links. |
| 3 | Demo video done | DONE 27 Nov 2026 (Onyx cut): docs/demo-video/realmcheck-demo.mp4, 103.0s, 1920x1080, 29.99 fps, 8,335,311 bytes, Piper narration 155 wpm, -16.73 LUFS, true peak -1.32 dBTP, QA passed (11 frames checked, whisper transcript verified, every spoken number matches the on-chain reports). Shows a live audit of vulnmint on Onyx (score 75, RC-02 at line 41), the explain view, adminbackdoor live (score 37, 4 findings, "Live on Onyx" badge), and stored reports #1 and #2 on the Onyx Render page. The local-chain cut is kept as docs/demo-video/realmcheck-demo-local.mp4 (107s). NOT uploaded anywhere: YouTube upload needs Duan's approval. Confirmed on the live form 27 Nov 2026 18:45 WITA: no video length or size limit stated anywhere; the video is submitted by URL (YouTube, Vimeo, Loom, or a direct .mp4 link). |
| 4 | Onyx deploy verified | DONE 27 Nov 2026 18:06 WITA (10:06 UTC). All 7 packages live on Onyx after the GPAO approval gate (first submit 17:15 WITA, all stored inert, 5 passed checks, 2 in review queue; enabled by 10:05 UTC, about 50 minutes after passing). Resume run re-verified all 7 byte-identical (re-add refused with PkgExistError, as designed) and stored test report #1 (vulnmint, score 75, RC-02 at line 41, tx OSWTRLJrmBFTN0o4mAygIgF4+vssHaI7P7WvpU3q1T8=, height 1448446). Report #2 (adminbackdoor, score 37, tx GrhQXkQ4N+8OvWqfj5zSArTy/ns+hdQSulpBdV1hVuk=, height 1448498) stored and verified the same day. Live paths: https://onyx.testnets.gno.land/r/g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu/realmcheck and the five demo realms under the same namespace. Full record in docs/ONYX-DEPLOY.md sections 8 and 10. |
| 5 | Name has no "Gno" prefix | DONE. The project is named RealmCheck. |
| 6 | No mockups | DONE. Everything submitted is working code: rules, report realm, demo realms, UI, agent mode. No slides, no concept art, no mockup screens. |
| 7 | GitHub Pages live | DONE 27 Nov 2026 16:35 WITA. Workflow file committed via the GitHub web UI (afa31bc), Pages source set to GitHub Actions, first workflow run succeeded, https://dunoil.github.io/realmcheck/ verified HTTP 200 and rendering the full UI. |
| 8 | Post-deploy UI copy applied | DONE 27 Nov 2026. `VITE_REALMCHECK_REALM` set in `.github/workflows/pages.yml` and the `ui/src/lib/gnoRpc.js` default updated to the deployed realm; `ui/src/App.tsx` copy updated (live-on-Onyx badge and intro, demo cards audit live from the chain with the bundled sources as a labeled fallback only, save-on-chain enabled for demo reports, "After the M6 deploy" card deleted, `dunoil` paths replaced with the deployer namespace); `npm run build` passes, no stale wording remains in `ui/src/` (grep-verified), `bash scripts/e2e-local.sh` PASSED with the new default. |
| 9 | Live form re-checked | DONE 27 Nov 2026 18:45 WITA (read-only browser check, nothing typed, nothing saved, no draft created). Form fields confirmed: organizer questions (wallet address optional at submission, country*, contact*, deployment link*, realm path*, new-vs-pre-existing*, KYC Yes/No*, teammates radio, Terms checkbox) and BUIDL form (Name*, Brief description*, Tags, Team Info, links incl. Video/GitHub/Website, Contact Info Telegram* + backup*, Description*); requires a GitHub/GitLab/Bitbucket link and a demo video via YouTube/Vimeo/Loom/direct .mp4 link. No video length or size limit stated anywhere on the page, in the Terms, or in the form; video is by URL only (no upload control seen). Prize $40,000 confirmed (upfront 1st $2,000, 2nd $1,000, 14x $500; retention up to $30,000 with criteria: mainnet live, monthly release, 50/100 unique addresses, 500/1,500 tx, 20/50 MAU, one other project imports, community 200/500, 2 updates/month, not guaranteed). Close 18 Dec 2026 01:00 UTC, judging 18-21 Dec, winners 21 Dec, KYC deadline 22 Dec, payout 23-24 Dec. Name rule stands (no "Gno" prefix). KYC winners-only at payout; nuance: Timeline says missing 22 Dec delays payout, Terms §5 says unclaimed after 30 days is forfeited; the form only asks the Yes/No capability question. Could not verify: character limits (no counter shown), new-vs-pre-existing dropdown options, file upload vs link for the video. |
| 10 | Demo video URL in the form | TBD. Depends on item 3. |
| 11 | Duan final approval | TBD. M8, 17 Dec. Submit 18 Dec only after his explicit approval for that specific submission. |
| 12 | KYC | DEFERRED. KYC is required only for winners at payout (deadline 22 Dec). Do not do any KYC now. |
| 13 | Live source-hash display matches stored hash | DONE 27 Nov 2026 18:50 WITA. Manual click-through found the live view hashed the display string (filename header + source) while stored reports hash the raw source file, so the same source showed two different SHA-256 prefixes (vulnmint live 3499e691... vs stored f8616d8b...). Fixed in ui/src/lib/gnoRpc.js (new sourceHashFor) and ui/src/App.tsx (both audit paths): the live hash is now sha256 of the audited bytes, matching the stored convention and the save flow. Verified: npm run build passes, scripts/e2e-local.sh PASSED (UI fetchRealmFiles hash f8616d8b... equals the stored hash; local adminbackdoor hash matches its stored report). Video re-record DONE 27 Nov 11:00 WITA (scenes s2, s4, s5a re-recorded, QA passed, docs/demo-video/work/qa-onyx-v2.log); the video now shows the new hashes. |

## 3. What is still TBD

- **Demo video URL.** The Onyx cut is ready
  (docs/demo-video/realmcheck-demo.mp4, 103.0s, recorded 27 Nov 2026
  against the live Onyx deploy, QA passed) but is not uploaded
  anywhere. The upload needs Duan's explicit approval. Owner step
  near submission: Duan's own voice is not required by the hackathon
  rules as verified, but the video must show the product working.
  NOTE 27 Nov 18:50 WITA: the source-hash display fix changed the
  live hash shown in the vulnmint audit frame (was 3499e691..., now
  f8616d8b...). DONE 27 Nov 11:00 WITA: scenes s2, s4, s5a
  re-recorded against the fixed UI, QA passed
  (docs/demo-video/work/qa-onyx-v2.log); the video now shows the
  new hashes and is ready for upload once approved.
- **Onyx deploy verification.** DONE 27 Nov 2026 18:06 WITA
  (10:06 UTC): all 7 packages live on Onyx, byte-verified against
  the repo, test report #1 (vulnmint, score 75) and report #2
  (adminbackdoor, score 37) stored and read back. Full record in
  docs/ONYX-DEPLOY.md sections 8 and 10 and checklist item 4.
- **GitHub Pages live check.** DONE 27 Nov 2026 16:35 WITA:
  https://dunoil.github.io/realmcheck/ returns HTTP 200 and renders
  the app. Redeployed 27 Nov 2026 18:15 WITA after the post-deploy UI
  copy push (workflow run 45980432341, success in 30s); the live
  bundle is the updated UI (deployer realm, "Live on Onyx", new
  manifest with the deployed demo paths), verified by fetching the
  served JS.
- **Adena live test.** The Adena connect flow is implemented but
  disabled; the live test (real extension, funded key, save one
  report) is still pending. It is not a submission blocker: the
  `gnokey` command path works today. Do not claim Adena works until
  that test passes.

## 4. Live-page re-checks before submitting

The hackathon facts in this package were verified live on the official
DoraHacks page on 27 Nov 2026 (research report, section 4). Re-check
each of these on the live page in a browser before submitting, because
the page itself says program dates and award counts may be adjusted:

Verified live 27 Nov 2026 18:45 WITA (read-only browser check, no draft created); findings are recorded in checklist item 9.

1. **Submission form fields.** Confirm the exact field names, which
   fields are required, and any character limits (especially the
   description and tagline). This draft assumes standard DoraHacks
   fields; the exact form was not opened for this draft.
2. **Demo video rules.** Confirm whether a length limit, file size
   limit, or hosting requirement (YouTube, or a direct upload) is
   stated. The research report records no length limit for this
   hackathon; do not assume one, and do not assume there is none.
3. **Prize pool and dates.** Confirm the $40,000 total, the $10,000
   upfront split (1st $2,000, 2nd $1,000, 14 times $500), the
   retention criteria, the 18 Dec 2026 01:00 UTC close, judging
   18 to 21 Dec, and winners 21 Dec. Aggregators still showed the
   stale $20,000 launch figure on 27 Nov; trust only the live
   DoraHacks page.
4. **Submission requirements.** Confirm the live deployment link, the
   public repo link, the README, and the demo video are still the
   five requirements, and that no new requirement (for example a
   track selection, a pitch deck, or a social post) has appeared.
5. **Name rule.** Confirm the "no Gno prefix" rule still stands and
   that RealmCheck complies.
6. **KYC timing.** Confirm KYC is still winners only, at payout, with
   the 22 Dec deadline.

## 5. Post-deploy UI copy change (APPLIED 27 Nov 2026)

Applied after the Onyx deploy was verified (checklist item 4). The
change table below is the record of what was applied; the copy in
`ui/src/` is now the live copy. The draft text in this section
describes the state before the change, kept for review.

### 5.1 `VITE_REALMCHECK_REALM` wiring

The UI default is still the local placeholder namespace
(`gno.land/r/dunoil/realmcheck` in `ui/src/lib/gnoRpc.js`, line 45
area). That default is what the local end-to-end harness expects, so
do not change the file default before the deploy. At deploy time, do
both of these:

1. In `.github/workflows/pages.yml`, add to the Build step:
   ```yaml
   env:
     VITE_REALMCHECK_REALM: gno.land/r/g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu/realmcheck
   ```
   This makes the Pages build point "View stored report", the
   save-on-chain panel, and the footer gnoweb link at the deployed
   report realm.
2. In `ui/src/lib/gnoRpc.js`, update the `REALMCHECK_REALM` fallback
   (and the comment above it) from `gno.land/r/dunoil/realmcheck` to
   `gno.land/r/g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu/realmcheck`,
   so a local `npm run dev` without env vars also points at the
   deployed realm. Then re-run `bash scripts/e2e-local.sh` once to
   confirm the harness still passes with its own env overrides (it
   sets `VITE_REALMCHECK_REALM` explicitly, so the new default must
   not break it).

`VITE_GNO_RPC` and `VITE_GNOWEB` need no change: their defaults are
already the Onyx endpoints.

### 5.2 Copy edits in `ui/src/App.tsx`

Line numbers are from the 27 Nov 2026 file; re-check them before
editing, they move as the file changes.

| Location | Current text (paraphrased, check the file) | Replacement |
| --- | --- | --- |
| Search hint, around line 779 | "The five deliberately vulnerable demo realms below are audited locally for now and deploy to Onyx with the full release." | "The five deliberately vulnerable demo realms below are live on Onyx at the paths shown." |
| Search placeholder, line 731 | `placeholder="gno.land/r/dunoil/vulnmint"` | `placeholder="gno.land/r/g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu/vulnmint"` |
| Demo report banner, around lines 798 to 805 | "Local demo report: the sources below were bundled with this page and audited in your browser, not fetched from Onyx. The {demoName} realm does not exist on Onyx yet." | Delete the banner. Demo reports are live reports after the deploy, fetched from Onyx like any other search. |
| Save-on-chain disabled note, around lines 1022 to 1028 | "Saving on chain is disabled for local demos: the {demoName} realm does not exist on Onyx yet, so there is no deployed source for a stored report to point at. It deploys with the M6 release." | Delete the note. Saving works for deployed demos. |
| Demo section badge, around line 1085 | Badge "Local demo" | Badge "Live on Onyx" |
| Demo section intro, around lines 1092 to 1097 | "Five deliberately vulnerable realms, built to prove the rules work. Their sources are bundled with this page, so each audit runs entirely in your browser with no network. These realms do not exist on Onyx yet; they deploy with the M6 release. Expected findings and scores come from the rule set at build time and move with it." | "Five deliberately vulnerable realms, built to prove the rules work. Each audit fetches the live source from Onyx and runs the rules in your browser. Expected findings and scores come from the rule set at build time and move with it." |
| Demo card button, around line 1163 | `Audit {demo.name} locally` | `Audit {demo.name}` |
| "After the M6 deploy" card, around lines 1171 to 1178 | "These five realms will live on Onyx at the paths above. The same cards will then audit them live from the chain, and the local demo labels will come off." | Delete the card. The deploy it describes has happened. |
| Rules section, around lines 1188 and 1240 | "the same rules run on chain as the gno.land/p/dunoil/auditrules package" (appears twice) | "the same rules run on chain as the gno.land/p/g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu/auditrules package" (both places) |

### 5.3 Behavior change behind the copy (APPLIED 27 Nov 2026)

The demo cards audited bundled local sources
(`runDemoAudit`, `public/demo-sources/`). After the deploy, they
audit live from the chain: the same `runAudit` path the search box
uses, with the demo realm path
(`gno.land/r/g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu/<name>`).
The bundled sources remain as a fallback only if the live fetch
fails, labeled clearly ("live fetch failed, showing the bundled
copy") instead of silently served. The bundled fallback sources are
now byte-identical to the deployed sources
(`ui/scripts/demo-sources.mjs` prefers the deploy stage when it
exists), and the manifest realm paths point at the deployed
namespace, so a `?demo=` link resolves to the live realm. The copy
and the behavior agree.

Verification, 27 Nov 2026:

1. `cd ui && npm run build` passes (dist JS 281.33 kB).
2. `?demo=adminbackdoor` path verified through the UI's own code
   path (`scripts/verify-live-audit.mjs` runs the UI's
   `fetchRealmFiles` plus `audit.js` against Onyx): score 37, 4
   findings, live source byte-identical to the staged copy. A
   manual browser click-through of the built site is still due
   (parent-agent browser task).
3. `?realm=gno.land/r/g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu/vulnmint`
   verified the same way: score 75, RC-02 at line 41, live source
   byte-identical to the staged copy. Manual browser click-through
   still due.
4. Reports #1 (vulnmint, score 75) and #2 (adminbackdoor, score
   37) saved on chain through the UI's own report encoding
   (`scripts/offline-sign-deploy.sh` resume and
   `scripts/submit-report-onyx.sh`) and read back with the deployed
   auditor address
   `g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu`. The Adena live test
   is still pending (not a blocker: the `gnokey` command path
   works).
5. No "does not exist on Onyx yet", "audited locally", or "Local
   demo" wording remains anywhere in `ui/src/` or `ui/public/`
   (grep-verified 27 Nov 2026; the manifest note and realm paths
   were fixed, and the bundled demo sources are byte-identical to
   the live sources).

### 5.4 Docs updated at the same time (DONE 27 Nov 2026)

- `README.md` status line: the Onyx deploy is live, with the real
  gas used, tx hashes, and the verified paths. "Pending faucet
  funding" removed.
- `README.md` live demo section: the Pages URL is live.
- `ui/README.md`: the "Demo realm paths" section now says the demos
  resolve on Onyx since the 27 Nov 2026 deploy.
- `docs/ONYX-DEPLOY.md` section 8: the real Onyx gas used, storage
  fees, tx hashes, and deployed paths recorded.
- This file: checklist items 4 and 8 moved to DONE with the
  verification evidence (URLs fetched, scores confirmed). Item 7
  was already DONE (Pages live 16:35 WITA).
