# RealmCheck demo video

Status: RECORDED and QA PASSED 27 Nov 2026 against the LOCAL gnodev
chain (chain ID `dev`, RPC `http://127.0.0.1:26657`, gnoweb
`http://127.0.0.1:8888`). Deliverable:
`docs/demo-video/realmcheck-demo.mp4`, 107.0 seconds, 1920x1080,
29.3 fps, 8,036,351 bytes, with Piper narration and burned-in
captions. The Onyx re-record below still applies once the deploy
lands; this cut is the local-chain record, not the submission cut.

## Why local, not Onyx

The DoraHacks submission requires a demo video showing the product
working. The research report
(`~/workspace/research_notes/gno-land-ecosystem-20261127-0410/report.md`,
Gnome Tavern section) states no length limit for the video, so this cut
targets under 2 minutes at 1080p, a safe DoraHacks standard.

The Onyx deploy is proven via the offline-sign path but NOT YET RUN
(pending faucet funding by the owner), so the demo realms do not exist
on Onyx yet. This video was therefore recorded against a local chain,
where the full loop is verified end to end: the two demo realms are
deployed on chain, the UI audits them live from the chain with
`vm/qfile`, both reports are stored on chain with `SubmitReport`, and
the report realm `Render` page lists them. The UI flow is identical on
Onyx; only the network changes. See "Onyx re-record" below for the
exact follow-up run.

## Ground truth shown in the video (verified live 27 Nov 2026)

| Realm | Score | Findings |
| --- | --- | --- |
| `gno.land/r/dunoil/vulnmint` | 75 | 1: RC-02 critical, Unrestricted mint, line 41 |
| `gno.land/r/dunoil/adminbackdoor` | 37 | 4: RC-01 high line 105, RC-03 critical line 75, RC-07 medium line 84, RC-08 high line 53 |

On-chain reports on the local chain used for the recording: report #1
vulnmint score 75 (tx
`4V1s9MAC5jFXuhvmqERllSjTPcP5vFbDvAOgg733vQE=`, height 3), report #2
adminbackdoor score 37 (tx
`RpQVsoJ14PC5/TRxaNAWRnU4WWVcMT1PU2Ns4vxEef8=`, height 5). Auditor for
both: `g1yzqhuxczln72kwm9pstcmjerhnu0uverkuyz4h` (local dev key
`realmcheck-dev`).

## Narration script (about 100 seconds)

Narration is Piper TTS, voice `en_US-lessac-medium`, rendered offline
on the VM, no paid service. TTS text uses pronounceable spellings
("Gno dot land", "vuln mint", "R C zero two"); burned-in captions
show the exact on-screen strings ("gno.land", "vulnmint", "RC-02").

### Scene 0, title card, 0:00-0:02 (no voice)

On-screen text: "RealmCheck" / "Read the source before you trust the
realm." / "Gnome Tavern Hackathon, Gno.land".

### Scene 1, the problem, hero, about 20 seconds

"On most chains, a smart contract is compiled bytecode. You cannot
read it, so you trust that the published source matches what is really
deployed. On Gno.land, every contract is readable source, stored on
the chain itself. RealmCheck audits that source before you call the
realm."

Shot: the UI hero, slow scroll through the Score, Source, and Reports
cards and the eight rule chips RC-01 to RC-08.

### Scene 2, run the audit, about 24 seconds

"Paste any realm path. Here is vuln mint, a demo token realm deployed
on a local test chain. RealmCheck fetches its source live from the
chain and runs eight deterministic rules over it. No language model in
the score, so the same source always gives the same result."

Shot: the realm path is typed into the search box
(`gno.land/r/dunoil/vulnmint`), "Audit realm" is clicked, the report
appears with the score ring.

### Scene 3, the report, about 22 seconds

"Seventy five out of one hundred, with one finding. Rule R C zero
two, critical: unrestricted mint, at line forty one. The Mint function
never checks who the caller is, so anyone can create any amount of
tokens. The explain view shows the exact function, why it is risky,
and the fix."

Shot: score 75, "Review advised: some risky shapes found", the
Findings list, then "Explain this function" opens the enclosing
function `Mint`, lines 41 to 50, with the finding line highlighted,
plus the risk, attacker, and fix text.

### Scene 4, the demo realm showcase, about 16 seconds

"Five demo realms prove the rules work. Admin backdoor, a treasury
with a single hard coded admin, scores thirty seven, with four
findings. These run locally in the browser until the realms deploy to
the Onyx testnet."

Shot: the "Try the demo realms" cards, then "Audit adminbackdoor
locally" runs and its report shows score 37 with 4 findings. The UI
labels this a "Local demo report": the sources are bundled with the
page and audited in the browser, not fetched from Onyx.

### Scene 5, the report stored on chain, about 20 seconds

"Reports live on chain, not just in the browser. This is report number
one, stored in the RealmCheck report realm with its source hash.
Anyone can load it later and re-run the audit to compare. The realm
renders its own page, listing every stored report."

Shot: "View stored report" loads stored report #1 for vulnmint, score
75, from the chain. Then the gnoweb Render page for
`gno.land/r/dunoil/realmcheck` lists "#1 gno.land/r/dunoil/vulnmint
score 75" and "#2 gno.land/r/dunoil/adminbackdoor score 37".

### Scene 6, closing card, about 8 seconds

"RealmCheck. Read the source before you trust the realm. Find it at
github dot com slash dunoil slash realmcheck."

On-screen text: "RealmCheck" / "Read the source before you trust the
realm." / "github.com/dunoil/realmcheck".

## How it was recorded

Tool chain, all on this VM, nothing paid:

- Local chain: `gnodev local` from `contracts/`, RPC 26657, gnoweb
  8888, dev key funded with 100000000 ugnot. Demo realms deployed
  with `gnokey maketx addpkg` (vulnmint first, adminbackdoor imports
  it). Reports submitted with `gnokey maketx call SubmitReport`
  (gas-wanted 10000000 plus 7000000 per finding). Verified with
  `node scripts/e2e-local.mjs audit` and `verify`, both PASSED.
- UI: production build with the local endpoints baked in
  (`VITE_GNO_RPC=http://127.0.0.1:26657`,
  `VITE_GNOWEB=http://127.0.0.1:8888`,
  `VITE_REALMCHECK_REALM=gno.land/r/dunoil/realmcheck`), served with
  `vite preview` on `http://127.0.0.1:4173`. The `ui/dist/` build
  output is gitignored; only the env vars change for the recording,
  no UI source was edited.
- Screen capture: true screen recording, not screenshots. Headed
  Chromium (Playwright-bundled Chromium 1255) under Xvfb at
  1920x1080, window 1920x1400 shifted up by 151 pixels
  (`--window-position=0,-151`) so the tab bar, address bar, and the
  "Chrome for Testing" banner sit off screen and only the page is
  captured. `ffmpeg -f x11grab` at 30 fps, libx264 preset ultrafast
  (preset medium dropped half the frames on this 1.5-CPU VM, so the
  first assembly came out at 15 fps; all six scenes were re-recorded
  with ultrafast and the final cut is 29.3 fps). The browser is
  driven over CDP with plain Node (built-in WebSocket, no extra
  dependency): real clicks, character-by-character typing, and smooth
  scrolling. The real X pointer is moved with `xmov.py` (ctypes
  libX11 XWarpPointer), because CDP-injected mouse events do not move
  the X server pointer and the recorded cursor otherwise sat frozen
  at the screen center. Driver:
  `docs/demo-video/work/record.mjs` (working notes and proof of
  concept captures stay in `docs/demo-video/work/`).
- Narration: Piper 2023.11.14-2, voice `en_US-lessac-medium`
  (downloaded from HuggingFace, rendered offline), one WAV per scene
  at 22050 Hz mono, mixed under the video with ffmpeg. No paid TTS.
  Edge TTS was tried first and failed: the VM egress proxy breaks
  its websocket upgrade (TLS past the proxy works, the upgrade
  returns 101 "Invalid connection header"), so it is unusable here.
- Captions: the narration text burned in with ffmpeg `subtitles`
  (ASS, Noto Sans, bottom center), one caption per scene, matching
  the spoken words. The video also works with the sound off.
- Edit: ffmpeg only. Per-scene takes trimmed to the narration, 0.4
  second fades between scenes, title and closing cards generated
  with `drawtext` on the UI zinc background (#09090b) with emerald
  (#10b981) accents.

## Known on-screen artifacts (disclosed, not hidden)

- The UI header badge reads "Onyx testnet, onyx-1" and some helper
  text mentions Onyx. That badge is hardcoded in `ui/src/App.tsx`
  and the build used for this recording points at the local chain.
  The narration says "local test chain" where the footage is local,
  and this file states the fact. The Onyx re-record below fixes it
  for real.
- The demo showcase section says the five demo realms "do not exist
  on Onyx yet; they deploy with the M6 release". True at recording
  time; the re-record updates it by re-running the deploy.
- The live audit shows a source SHA-256 of `3499e6917c283aa3...`
  while the stored report (and the audit driver) show
  `f8616d8b7c69e820...` for the same vulnmint source. Both are
  correct for their own input: the UI hashes the combined text
  `===== vulnmint.gno =====` plus the source (`App.tsx`, `runAudit`),
  while the audit driver hashes the raw source bytes. Scores and
  findings agree exactly; only the hash input differs. Flagged here
  so the coordinator can decide whether the two hashes should be
  unified; the video does not quote either hash in narration.
- The "Save this report on chain" panel is not clicked in the video.
  The reports were already stored before recording (via the same
  `gnokey maketx call SubmitReport` the panel shows), and clicking
  save again would create duplicate reports. The video shows the
  stored report being loaded from the chain instead, which is the
  proof that matters.

## QA (27 Nov 2026, final cut)

Result: PASS. Full log: `docs/demo-video/work/qa.log`.

- File: 107.000 seconds, 1920x1080, H.264, 3133 frames (29.3 fps
  effective), 8,036,351 bytes, AAC 128k.
- Frames extracted at every scene boundary and at the score ring,
  the explain view, the demo cards, the stored report, and the
  Render page: UI text readable at 1080p, no clipped text, no
  horizontal overflow, no browser chrome in any frame, captions
  match the spoken words.
- Audio: narration loudness -16.74 LUFS integrated, true peak
  -1.32 dBTP, mean -17.5 dB, max -1.3 dB, no clipping. Silences of
  0.6 seconds or more are only the 7 inter-scene gaps (2.4 to 3.4
  seconds each) plus the silent 2.5 second title card; in every gap
  the picture keeps moving (scroll, typing, report rendering), so
  there is no dead stretch.
- Intelligibility: the final audio was transcribed with whisper
  tiny.en (`docs/demo-video/work/qa-transcript.txt`). All 25
  segments present, in order, numbers correct (75 out of 100, one
  finding, line 41, 37, four findings, report number one). The tiny
  model garbles proper nouns ("volume-int" for vuln mint, "Rolar
  C02" for R C zero two, "github.com-dunnoils-rel-check" for
  github.com/dunoil/realmcheck); the burned-in captions carry the
  exact spellings for every name and number.
- Facts: every number spoken (75, 1 finding, RC-02, line 41, 37, 4
  findings) matches the on-screen report and the ground truth table
  above.

## Onyx re-record (follow-up step, after the M6 deploy)

Do not reuse this cut for the submission once Onyx is live; re-record
with the same script and the same driver, changing only the network:

1. Deploy to Onyx with `scripts/deploy-onyx.sh` (see
   `docs/ONYX-DEPLOY.md`): realmcheck report realm, the auditrules
   package, and the five demo realms in order (vulnmint before
   adminbackdoor). Confirm the five demo paths resolve on Onyx.
2. Rebuild the UI with the Onyx defaults (plain `npm run build` in
   `ui/`, no `VITE_` overrides) and serve it with `vite preview`.
   The header badge will then be correct.
3. Re-run the audit driver against Onyx
   (`node ui/scripts/smoke-onyx.mjs`) and re-submit both reports on
   Onyx so the stored reports exist there. Record the new report
   IDs, tx hashes, and heights in this file.
4. Re-run `docs/demo-video/work/record.mjs` unchanged, except the
   scene 2 and scene 5 narration lines: drop "on a local test chain"
   and say "deployed on the Onyx testnet", and drop the scene 4
   caveat ("These run locally in the browser until the realms deploy
   to the Onyx testnet") since the demo cards will then audit live
   from the chain. Re-render the narration for the changed lines
   only; the rest of the script is unchanged.
5. The Render page shot becomes
   `https://onyx.testnets.gno.land/r/dunoil/realmcheck` (or the final
   deployer namespace if it changes; update the script line if the
   realm path changes).
6. Re-run the QA steps above on the new cut, replace
   `docs/demo-video/realmcheck-demo.mp4`, and update the status line
   and ground truth table at the top of this file. Keep this local
   cut as `docs/demo-video/realmcheck-demo-local.mp4` for the record.

## Files

- `docs/demo-video/realmcheck-demo.mp4`: the finished video.
- `docs/demo-video/work/`: recording driver (`record.mjs`), per-scene
  narration WAVs and the TTS render script, the Piper binary and
  voice model, proof of concept captures, chain and deploy logs, and
  the QA log. Not part of the submission; kept so the Onyx re-record
  can reuse the exact setup.
- `docs/demo-video/` is gitignored (see `.gitignore`): the mp4 goes
  to YouTube only at submission time, after Duan's explicit approval.
  Never commit video files to the repo.
