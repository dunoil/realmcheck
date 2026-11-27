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
| Deployment link (live testnet deployment) | https://onyx.testnets.gno.land/r/g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu/realmcheck (PENDING: the Onyx deploy is not verified yet; see section 3. Do not paste this link until the deploy is verified.) |
| Live demo URL (web UI) | https://dunoil.github.io/realmcheck/ (PENDING: GitHub Pages is not enabled yet; see section 3. Do not paste this link until the site is verified reachable.) |
| Demo video URL | TBD. The video does not exist yet (M7, due 15 Dec). Do not submit without it: a demo video is required. |
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
| 3 | Demo video done | RECORDED 27 Nov (local-chain cut): docs/demo-video/realmcheck-demo.mp4, 107s, 1920x1080, voiceover plus captions, QA passed (coordinator checked 5 frames). Shows a live audit of vulnmint (score 75, RC-02 at line 41), the explain view, and stored report #1. NOT YET the submission cut: re-record against Onyx after the deploy (see docs/DEMO-VIDEO.md), then upload to YouTube after Duan's approval. Keep it short; the hackathon page states no video length limit in the research report, so confirm the limit on the live form (see section 4). |
| 4 | Onyx deploy verified | TBD. The deploy script is proven on a local chain and the signed bytes were proven to reach the Onyx node, but the deploy has NOT run: faucet funding is pending (owner browser step, captcha, https://faucet.gno.land, 100 GNOT to g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu). After funding, run `bash scripts/offline-sign-deploy.sh --key realmcheck-onyx --deployer g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu`, then verify all 7 paths resolve on gnoweb and the test report reads back (score 75, RC-02 at line 41). |
| 5 | Name has no "Gno" prefix | DONE. The project is named RealmCheck. |
| 6 | No mockups | DONE. Everything submitted is working code: rules, report realm, demo realms, UI, agent mode. No slides, no concept art, no mockup screens. |
| 7 | GitHub Pages live | TBD. The workflow (`.github/workflows/pages.yml`) is in the repo and the build passes, but Pages is not enabled. Owner step: repo Settings, Pages, Build and deployment, Source: GitHub Actions. Then push to `main` and verify https://dunoil.github.io/realmcheck/ returns HTTP 200 and renders the app. |
| 8 | Post-deploy UI copy applied | TBD. Drafted in section 5 below. Apply only after the Onyx deploy is verified (item 4). |
| 9 | Live form re-checked | TBD. Re-check the live DoraHacks page before submitting (section 4). |
| 10 | Demo video URL in the form | TBD. Depends on item 3. |
| 11 | Duan final approval | TBD. M8, 17 Dec. Submit 18 Dec only after his explicit approval for that specific submission. |
| 12 | KYC | DEFERRED. KYC is required only for winners at payout (deadline 22 Dec). Do not do any KYC now. |

## 3. What is still TBD

- **Demo video URL.** No video exists yet. It is the only submission
  requirement with no artifact at all. Owner step near submission:
  Duan's own voice is not required by the hackathon rules as verified,
  but the video must show the product working.
- **Onyx deploy verification.** All 7 gnoweb links in the README are
  planned paths until the deploy runs and each path is checked live:
  the package listing resolves, the deployed source byte-matches the
  repo, and the test report reads back. The deployer key is unfunded
  until the faucet step runs.
- **GitHub Pages live check.** The workflow is ready and the build
  passes locally (`npm run build` in `ui/`, 27 Nov 2026), but Pages
  needs the repo-settings change, and the live URL has not been
  fetched. Do not claim the site is live until a fetch of
  https://dunoil.github.io/realmcheck/ returns HTTP 200 and the app
  renders.
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

## 5. Post-deploy UI copy change (DRAFT, do NOT apply yet)

Apply only after the Onyx deploy is verified (checklist item 4).
Until then the current copy is correct: the demo realms really do not
exist on Onyx yet, and the UI really does audit them from bundled
local sources. Changing the copy early would lie to users.

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

### 5.3 Behavior change behind the copy (not just text)

The demo cards currently audit bundled local sources
(`runDemoAudit`, `public/demo-sources/`). After the deploy, change
them to audit live from the chain: call the same `runAudit` path the
search box uses, with the demo realm path
(`gno.land/r/g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu/<name>`).
Keep the bundled sources as a fallback only if the live fetch fails,
and label that fallback clearly ("live fetch failed, showing the
bundled copy") instead of silently serving it. Do not keep the
bundled audit as the default while the copy claims the realms are
live: the copy and the behavior must agree.

After applying, verify before redeploying Pages:

1. `cd ui && npm run build` passes.
2. Open `?demo=adminbackdoor` on the built site and confirm score 37
   with 4 findings, fetched live (not bundled).
3. Open `?realm=gno.land/r/g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu/vulnmint`
   and confirm score 75 with RC-02 at line 41.
4. Save one report on chain from the UI (gnokey command or Adena)
   and confirm it reads back with the deployed auditor address.
5. Confirm no "does not exist on Onyx yet", "audited locally", or
   "Local demo" wording remains anywhere in `ui/src/`.

### 5.4 Docs to update at the same time

- `README.md` status line: the Onyx deploy is done, with the real
  gas used, tx hashes, and the verified paths. Remove "pending faucet
  funding".
- `README.md` live demo section: the Pages URL is live (only after
  the HTTP 200 check).
- `ui/README.md`: the "Demo realm paths" and "What is still a stub"
  sections, which say the demos deploy with the full release, and
  the example scores if they moved.
- `docs/ONYX-DEPLOY.md` section 8: record the real Onyx gas used,
  storage fees, tx hashes, and deployed paths.
- `M6-PREP-STATUS.md` (or the M6 close-out note): the real deploy
  record.
- This file: move checklist items 4, 7, and 8 to DONE with the
  verification evidence (URLs fetched, scores confirmed).
