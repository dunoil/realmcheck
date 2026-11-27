# M4 UI Status (UI polish, 27 Nov 2026)

Owner: UI polish subagent. Scope: `ui/src/App.tsx`, `ui/src/index.css`,
`ui/src/lib/gnoRpc.js` (endpoint configuration only),
`ui/src/lib/explain.js` (new), `ui/scripts/demo-sources.*` (new),
`ui/vite.config.ts`, `ui/public/**`. Not touched: `ui/src/lib/audit.js`,
`contracts/**`, `ui/scripts/expected-findings.json`, `ui/README.md`
(verified by file timestamps: those files predate this session).
Two supporting edits outside the listed files, both required by the
work: `ui/package.json` (prebuild script for the demo build step) and
`ui/src/lib/gnoRpc.d.ts` (type declarations for the new endpoint
exports, so `tsc` passes). Nothing was spent, submitted, or published.

## 1. Configurable endpoints (`ui/src/lib/gnoRpc.js`)

`GNO_RPC`, `GNO_GNOWEB`, and `REALMCHECK_REALM` are read from Vite env
vars `VITE_GNO_RPC`, `VITE_GNOWEB`, `VITE_REALMCHECK_REALM`, defaulting
to the Onyx values (`https://rpc.onyx.testnets.gno.land`,
`https://onyx.testnets.gno.land`, `gno.land/r/dunoil/realmcheck`). In
plain node `import.meta.env` is undefined, so the same names fall back
to `process.env`, then the defaults. `ONYX_RPC` and `ONYX_GNOWEB` stay
as aliases. `abciQuery`, `gnowebUrl`, and `buildSubmitCommand` now use
the configured values instead of hardcoded URLs. `App.tsx` also uses
`REALMCHECK_REALM` in `loadStored` instead of a hardcoded realm path.

Verified in node:
`GNO_RPC= https://rpc.onyx.testnets.gno.land`, `GNO_GNOWEB=
https://onyx.testnets.gno.land`, `REALM= gno.land/r/dunoil/realmcheck`
by default; with env vars set, `override RPC= http://localhost:26657`,
`web= http://localhost:3000`, `realm= gno.land/r/test/realmcheck`.
The Onyx smoke test below re-verifies the defaults live.

## 2. "Explain this function" view (`ui/src/lib/explain.js`, new)

`extractEnclosingFunction(source, line)` finds the function or method
containing a finding line (brace tracking with comments and strings
blanked, methods included), capped at 120 lines around the finding.
`RULE_EXPLAIN` holds per-rule plain-English text: why the shape is
risky, what an attacker could do with it, what to check before calling
the realm, and the fix pattern. `explainRule(ruleID)` returns the entry
or a generic fallback for unknown IDs. Each finding card now has an
"Explain this function" toggle showing the enclosing function with the
finding line highlighted, plus the four explanation paragraphs. Stored
reports have no full source, so their cards show the explanation text
with a note that the function cannot be shown there.

Verified by `node ui/scripts/verify-m4-ui.mjs` (new script, checks the
explain view on both live Onyx realms and all five demo realms):
gov/dao RC-08 types.gno:140 renders function `SetProposal`, lines
138-146; sys/params RC-08 run_submitters.gno:122 renders
`ProposeSetRunSubmittersManager` lines 98-128, line 151 renders
`ProposeClearRunSubmittersManager` lines 138-155, line 269 renders
`RemoveRunSubmitters` lines 222-273. Every finding line was found
inside its function and flagged as the finding line, and every rule had
explanation text. The same check passed for all 9 demo findings.
A real headless-Chromium run (CDP, 390px, `?demo=vulnmint`, click the
button) also rendered it: enclosing function `Mint`, lines 41-50,
finding line highlighted, risk, attacker, and fix text all present,
no horizontal overflow.

## 3. Demo showcase (`ui/scripts/demo-sources.mjs`, new build step)

`node ui/scripts/demo-sources.mjs` copies every non-test `.gno` source
from `contracts/demo/<realm>/` into `ui/public/demo-sources/<realm>/`
and writes `ui/public/demo-sources/manifest.json` with each realm's
vulnerability blurb, files, expected findings taken from
`ui/scripts/expected-findings.json`, and expected score computed from
those findings with the audit port's own `score()`, never hardcoded.
It runs automatically before every build (`prebuild` in
`ui/package.json`; also runnable as `npm run demo-sources`). The UI
fetches the manifest on load and shows a "Try the demo realms" section
with one-click cards (name, vulnerability, expected findings with rule,
severity, title, line, expected score). Clicking a card fetches the
bundled sources and audits them client-side with the same `auditFiles`
path, no network needed. Every card and the resulting report are
labeled "Local demo" until the M6 Onyx deploy, and the save-on-chain
panel is disabled for demo reports with an explanation.

Build output: vulnmint 1 finding, score 75/100; unguardedvault 1
finding, 85/100; greedystore 1 finding, 92/100; luckydice 1 finding,
85/100; adminbackdoor 3 findings, 62/100. All five scores are computed
from `expected-findings.json` at build time, so they move with the
rules. `verify-m4-ui.mjs` also confirms the bundled sources audit to
exactly the manifest's expected findings (rule, file, line) for all
five realms.

## 4. Share links

`?realm=gno.land/r/...` auto-runs the live audit on page load, and
`?demo=<name>` auto-runs a bundled demo audit. Every completed audit
writes its deep link into the address bar with `history.replaceState`.
The report view has a "Copy link to this report" button that copies
the deep link (`?realm=` for live reports, `?demo=` for demo reports),
with a clipboard fallback for browsers without async clipboard.

Verified in a real headless-Chromium run (Playwright-bundled Chromium,
`--dump-dom` and CDP): `?demo=vulnmint` renders "Local demo report",
score 75, "Explain this function", and "Copy link to this report",
with no audit error. The `?realm=` branch was proven to fire in the
same browser (the page showed "Audit failed: Failed to fetch", which
only appears when `runAudit` runs), but the fetch itself cannot
succeed in headless Chrome on this VM: this VM's headless Chrome has
no external internet at all (it also fails to load example.com),
while node and curl reach the Onyx RPC fine and the RPC sends
`access-control-allow-origin: *`. The live `?realm=` render in a
normal browser still needs one recheck on a machine with browser
internet; the identical code path is verified live by the node smoke
test below, and the browser-side param parsing and report rendering
are verified by the `?demo=` run. The built bundle contains
`URLSearchParams` handling and the `demo-sources/manifest.json`
fetch (checked in `dist/assets/*.js`).

## 5. Visual polish

Kept the dark zinc and emerald design. New hero section: "Read the
source before you trust the realm.", what RealmCheck is, why
source-on-chain auditing only works on Gno.land (the source lives on
the chain and is readable by anyone, so the audit runs against exactly
what is deployed, with no bytecode to decompile and no off-chain repo
that might differ), the 8 rule chips, and Score / Source / Reports
explainer cards. New "The eight rules" catalog section lists all 8
rules with severity and description, read from the `RULES` export in
`audit.js` so it stays in sync with the rules. Cleaner footer with
Project and Gno.land link columns, the report realm on gnoweb, and the
findings-are-signals disclaimer. ScoreRing, FindingCard, save-on-chain
panel, and stored-report view are unchanged in behavior; the Adena
button stays a disabled stub, per the task (real Adena signing comes
with the M6 deploy).

Layout check, headless Chromium (CDP, real rendering): at 390px with
a demo report rendered, `documentElement.scrollWidth` is 390,
`innerWidth` is 390, no element extends past the viewport, and the
same holds with the explanation expanded and at 1280px desktop
(scrollWidth 1265 at innerWidth 1280). Visual screenshots at 390px
and 1280px confirm the hero, form, report, demo cards, rule catalog,
and footer render without clipped text. Evidence:
`m4-verify/shot-390-realm-dao.png`,
`m4-verify/shot-desktop-dao.png`,
`m4-verify/shot-390-full-demo.png`,
`m4-verify/dom-demo-vulnmint.html`,
`m4-verify/cdp-check.mjs` (the CDP script used for the measurements).

## Fresh Onyx scores (sync check, 27 Nov 2026, `node ui/scripts/smoke-onyx.mjs`)

- `gno.land/r/gov/dao`: 85/100, 1 finding, RC-08 high types.gno:140,
  2 files, source SHA-256 fb63d4d4dead8faf1633163a7639da43c9af882230bd5c559f15677f26e77432.
- `gno.land/r/sys/params`: 55/100, 3 findings, all RC-08 high,
  run_submitters.gno lines 122, 151, 269, 9 files, source SHA-256
  ba961fd06c3e67e9c1f94ec05387b417fefab826e33f1ec0a7ba156655a761cc.

Unchanged from M1-M3. The old hardcoded score text in `App.tsx`
("(scores 85/100, one finding to review)") was removed entirely: the
example paragraph now says scores change as the rules improve and to
run the audit for the current result, so no stale score text remains
to sync. Demo expected scores are computed at build time (item 3).

## Verification commands and results (all run 27 Nov 2026)

- `node ui/scripts/test-audit-port.mjs`: PASS, all 5 demo realms
  match Gno Audit() exactly (audit.js untouched).
- `node ui/scripts/demo-sources.mjs`: 5 realms bundled, manifest
  written, scores 75 / 85 / 92 / 85 / 62.
- `npm run build` in `ui/`: passes, `tsc -b` with no TypeScript
  errors, prebuild regenerates the demo sources first, vite builds 19
  modules, `dist/` includes `demo-sources/` with all 5 realms and the
  manifest.
- `npm run dev` in `ui/` (port 5175): HTTP 200 for `/` and for
  `/demo-sources/manifest.json`, title "RealmCheck: is this realm
  safe to call?". Server stopped afterwards.
- `npm run preview` on the built `dist/` (port 4173): HTTP 200 for
  `/`, `/demo-sources/manifest.json`,
  `/demo-sources/vulnmint/vulnmint.gno`, and `/?realm=gno.land/r/gov/dao`.
  Server stopped afterwards. (An unrelated preview server on port 5200,
  PID 17456, was already running and was left alone.)
- `node ui/scripts/verify-m4-ui.mjs`: all checks passed (explain view
  on both live realms, bundled demo audits match the manifest, explain
  extraction works on all demo findings).
- `node ui/scripts/smoke-onyx.mjs gno.land/r/gov/dao` and
  `... gno.land/r/sys/params`: both "smoke test OK", scores above.
- No em dashes or en dashes in any owned file (grep check clean).

## Deliberately left out, with reasons

- `ui/src/index.css`: no changes. The dark zinc and emerald theme,
  fonts, and selection color were already defined there; the polish
  was done with Tailwind classes in `App.tsx`.
- `ui/vite.config.ts`: no changes. `base: './'` was already correct
  for relative asset paths, and the demo manifest is fetched through
  `import.meta.env.BASE_URL`, which respects it.
- Adena signing: still a disabled stub with the "coming with the full
  release" note, per the task. Real signing comes with the M6 deploy.
- Clipboard write observation: the "Copy link" button wiring and link
  construction are verified (the app sets `?demo=` / `?realm=` in the
  address bar on every completed audit, and the button is present in
  the rendered report), but the actual clipboard write was not observed
  in headless Chrome, where clipboard access needs a user gesture.
- Live `?realm=` render in a browser: see item 4. The wiring fired in
  headless Chrome but the network leg cannot run there; one recheck in
  a normal browser is still open.
- No physical phone check: mobile layout was verified at 390px in
  headless Chromium (CDP measurements plus screenshots), not on a
  device.

## Files created or changed

- Changed: `ui/src/App.tsx` (hero, explain toggle, demo showcase,
  share links, rule catalog, footer, hardcoded scores removed),
  `ui/src/lib/gnoRpc.js` (env endpoints), `ui/src/lib/gnoRpc.d.ts`
  (new endpoint exports), `ui/package.json` (prebuild and
  demo-sources scripts).
- New: `ui/src/lib/explain.js`, `ui/src/lib/explain.d.ts`,
  `ui/scripts/demo-sources.mjs`, `ui/scripts/verify-m4-ui.mjs`,
  `ui/public/demo-sources/` (5 bundled `.gno` files plus
  `manifest.json`, regenerated by the build step),
  `M4-UI-STATUS.md` (this file), `m4-verify/` (screenshots, DOM
  dumps, CDP check script), `preview-m4.log`, `dev-m4.log`.
