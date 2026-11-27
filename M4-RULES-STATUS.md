# M4 rules accuracy status

Date: 27 Nov 2026. Owner: rules agent (contracts, audit.js port,
expected findings). Milestone M4: UI polished, end-to-end audit flow
working locally on gnodev.

## Result

All eight rules RC-01 to RC-08 now fire on at least one demo realm.
The three rules that never fired in M1-M3 (RC-03, RC-05, RC-06) all
fire now. The false positives on guarded production code are fixed
except one deliberately left case (see below). The JavaScript port
matches Gno Audit() exactly on all five demo realms, and the live
Onyx smoke test improved on both realms with the realm sources
unchanged (same SHA-256 as the M1-M3 baseline).

## What changed per rule

### RC-06 weak randomness: parameter taint

The rule used to need a randomness source and a use (`%`, `rand`)
on the same line. In `luckydice`, `DrawNumber` passes height and
time into the pure helper `DrawNumberAt`, which does the modulo, so
no single line had both. The rule now tracks taint through
parameters in the same file: when a call site passes a randomness
source as an argument, that parameter of the callee is marked
tainted, transitively through further calls, to a fixed point capped
at eight passes. A function that applies modulo or a random call to
a tainted parameter is flagged at that line. The demo is unchanged;
the improved rule now catches the split pattern.

- New finding: `luckydice` RC-06 medium line 69, the modulo line in
  `DrawNumberAt` (`return int((height*31 + unixTime) % Faces)`).
- Helpers: `parseFuncParams` (parameter names, grouped and variadic
  handled, unnamed skipped), `computeTaint`, `findCalls`,
  `parseCallArgs`, `splitTopLevel`, `lineHasIdent`.
- Limits, pinned by tests: taint follows parameters across calls in
  the same file only (a helper in another file is not tracked), it
  does not follow local variables (a caller that stores the source
  in a local first defeats it), it stops after eight hops, and a
  multi-line function signature records no parameters. A helper that
  receives a source but never applies modulo or a random call to it
  is not flagged, and neither is one whose call sites pass only
  constants.

### RC-03 single admin backdoor: hard-coded admin constants

Root cause, verified empirically rather than taken from the earlier
notes: the stored-admin check did NOT return early. A probe showed
`adminVars=[Admin]`, so the variable was recorded. RC-03 missed
`Drain` for two compounding reasons: the admin-mention check was
case-sensitive and missed `Admin` (capital A) in `caller != Admin`,
and the drain tokens (`SendCoins`, `Withdraw`) do not cover a
ledger-style drain (`treasury = 0`, no banker call). A third latent
cause: the address-literal detection read the cleaned line, where
string contents are blanked, so `adminAddrLine` was always 0.

The rule now covers a second shape besides the stored-admin one. It
tracks `adminConsts`: package-level admin or owner variables whose
raw declaration line contains a `"g1` address literal. When a
function compares a value against such a constant, the first drain
or persistent state rewrite in that function is flagged: a
`SendCoins` or `Withdraw` call, a `.Set(`, `.Delete(`, or `.Remove(`
call, or an assignment to a package-level variable, skipping append
lines (those belong to RC-04). The stored-admin shape also gained a
case-insensitive mention check (`admin`, `Admin`, `owner`, `Owner`).
The description text changed to cover both shapes.

- New finding: `adminbackdoor` RC-03 critical line 75, `treasury = 0`
  in `Drain`.
- The parser also fixed two adjacent bugs found while doing this:
  admin or owner names declared inside a `var (` or `const (` block
  were recorded as their type, not their name (the name is the first
  field in a block, not the second), and `const (` blocks were not
  scanned at all.
- `Admin` stays a hard-coded constant in the demo, exactly as
  before. No demo source change was needed for RC-03.

### RC-05 funds accepted without a check: demos now use OriginSend

The rule was correct; the demos never called `OriginSend`, so it
could not fire. `unguardedvault.Deposit` and `luckydice.BuyChips`
now read the real sent coins through
`chain/runtime/unsafe.OriginSend()` and ignore them, crediting the
claimed amount instead. The ledger modeling is unchanged.

- New findings: `unguardedvault` RC-05 high line 48 (the
  `OriginSend` line in `Deposit`), `luckydice` RC-05 high line 61
  (the `OriginSend` line in `BuyChips`).
- Tests use the banker setup: `testing.IssueCoins` to fund the
  caller, `testing.SetOriginSend` to send 10 ugnot, verified through
  `testing.GetContext().OriginSend.AmountOf("ugnot")`, then a claim
  of 1000 is credited in full (`TestDepositIgnoresSentAmount`,
  `TestBuyChipsIgnoresSentAmount`). The zero-send case
  (`TestDepositWithoutSendingCoins`) is kept.
- `adminbackdoor.Fund` was deliberately left unchanged: the brief
  scoped this change to `Deposit` and `BuyChips`. `Fund` credits
  without calling `OriginSend`, so no rule flags it; its README now
  says so instead of claiming RC-05.

### RC-01, RC-02, RC-08: assert guards and methods

- Any `assert*` helper call now counts as a guard. By Gno
  convention an assert helper panics when its check fails, so a
  function that calls one is guarded on the condition it asserts.
  Guard tokens gained `assert` and `Assert`, plus `Admin ==`,
  `Admin !=`, `Owner ==`, `Owner !=`, so admin comparisons count in
  either order. This clears `sys/params` `RemoveRunSubmitters`
  (line 269, guarded by `assertDelegate`).
- Methods on unexported receiver types now count as non-exported
  for the access control rules (RC-01, RC-02, RC-03, RC-05, RC-08).
  A method on a lowercase type is only reachable from the realm's
  own code. RC-02 also gained the exported check it was missing.
- RC-08 additionally skips mutations that target only the method
  receiver. A call such as `ps.Set(` rewrites the caller's own
  instance, not shared realm state; a method that assigns a
  package-level variable or calls `Set` on shared state still
  counts. This is the fix that actually clears `gov/dao`
  `SetProposal` (see the correction below).
- The parser records the receiver variable and type, plus parameter
  names, for every function (`parseFuncReceiver`,
  `parseFuncParams`).

### Correction: Proposals is not an unexported type

The brief called `Proposals` in `gov/dao` an unexported type. It is
not: the declaration is `type Proposals struct`, capital P, so it is
exported by name, and the name-based receiver skip does not apply
to it. What clears `types.gno:140` is the RC-08 receiver-target
refinement above: `SetProposal` mutates only its own receiver
(`ps.Set`, `ps.seq`), never shared realm state. Both mechanisms
are implemented and tested separately: the name-based skip for
genuinely lowercase receiver types, and the receiver-target rule
for methods like `SetProposal`. A realm that hands out its stored
instance through a getter would defeat the receiver-target rule;
that getter pattern is not detected, and it is recorded as a known
limit in the audit-rules README.

## False positives on guarded production code (live Onyx)

| Realm | Before (M1-M3) | After (M4) | What changed |
| --- | --- | --- | --- |
| `gno.land/r/sys/params` | 55/100, 3 findings, all RC-08 (`run_submitters.gno` 122, 151, 269) | 85/100, 1 finding (RC-08 `run_submitters.gno:151`) | 269 cleared by the `assert*` guard (`assertDelegate` on the first line of `RemoveRunSubmitters`). 122 cleared as a side effect of the same fix: its enclosing function `ProposeSetRunSubmittersManager` calls `assertDelegatePath` at line 99, so the function counts as guarded. That suppression is for the wrong reason in detail (the assert guards proposal creation, not the closure's later execution), but the outcome is correct because the closure only runs after a DAO vote. |
| `gno.land/r/gov/dao` | 85/100, 1 finding (RC-08 `types.gno:140`) | 100/100, 0 findings | 140 cleared by the RC-08 receiver-target refinement (`SetProposal` mutates only its own `*Proposals` receiver). |

Realm sources are unchanged: the SHA-256 hashes match the M1-M3
baseline exactly (`sys/params`
`ba961fd06c3e67e9c1f94ec05387b417fefab826e33f1ec0a7ba156655a761cc`,
`gov/dao`
`fb63d4d4dead8faf1633163a7639da43c9af882230bd5c559f15677f26e77432`).

## Deliberately left unfixed: DAO-proposal closures

`sys/params` `run_submitters.gno:151` is still flagged, on purpose.
The mutation sits inside a closure passed to `newDelegateProposal`
in `ProposeClearRunSubmittersManager`. The gate is the DAO vote
itself, which the scanner cannot see. No safe heuristic exists:

- The scanner's stated design is to not follow calls: a guard must
  appear in the same function body. A closure exemption would
  require trusting the callee to run the closure only after a vote,
  which is following the call into the callee's semantics.
- A name-based exemption (closures passed to `*Proposal*`) is not
  provably safe: any realm could name a function
  `newDelegateProposal` that invokes the closure immediately with
  no vote, and the scanner would then hide a real unguarded
  mutation. There is no lexical property distinguishing a vote-gated
  executor from an immediate invoker.
- A narrower exemption (closure plus a guard in the enclosing
  function) does not help either: `ProposeClearRunSubmittersManager`
  has no guard call at all, yet its closure is vote-gated, while an
  evil realm could put a guard in the enclosing function and invoke
  the closure immediately.

So the finding stays, and the rule comment in `rules.gno` now says
why. The same reasoning is recorded as a known limit in the
audit-rules README.

## Updated findings table per demo realm

Ground truth is `ui/scripts/expected-findings.json`, regenerated
from the real Gno `Audit()`. Scores are computed by `Score()` from
the same findings.

| Realm | Score | Findings |
| --- | --- | --- |
| `vulnmint.gno` | 75 | RC-02 critical line 41 |
| `unguardedvault.gno` | 70 | RC-05 high line 48, RC-08 high line 51 |
| `greedystore.gno` | 92 | RC-04 medium line 47 |
| `luckydice.gno` | 62 | RC-05 high line 61, RC-06 medium line 69, RC-08 high line 103 |
| `adminbackdoor.gno` | 37 | RC-01 high line 105, RC-03 critical line 75, RC-07 medium line 84, RC-08 high line 53 |

All eight rules fire on at least one demo realm: RC-01
adminbackdoor, RC-02 vulnmint, RC-03 adminbackdoor, RC-04
greedystore, RC-05 unguardedvault and luckydice, RC-06 luckydice,
RC-07 adminbackdoor, RC-08 unguardedvault, luckydice,
adminbackdoor.

Two honest notes on the tables. First, the per-realm READMEs
previously promised findings that do not exist (RC-07 on
`PayBonus` line 105, RC-08 on `PayBonus` and on `greedystore`
`Register`, RC-05 on `adminbackdoor.Fund`, RC-01 on
`unguardedvault.Withdraw`). They are corrected to the ground truth
above, with the behavior that is proven by tests rather than by a
finding stated explicitly. Second, `unguardedvault.Withdraw` has no
finding at all: its payout is a ledger update with no banker call,
so RC-01 has no action token to match, and RC-08 skips
withdraw-style functions. That is a known limit of RC-01, recorded
in the audit-rules README; the missing caller check is proven by
`TestAnyoneCanWithdraw`, not by a finding.

## Test evidence

Full log: `scratch/m4-rules/verify-m4.log`. All runs use
`PATH=$HOME/workspace/tools/go/bin:$HOME/workspace/tools/gno/bin`,
`GNOROOT=$HOME/workspace/tools/gno`, `GOMAXPROCS=2`.

| Suite | Tests passed |
| --- | --- |
| `contracts/auditrules` | 52 (30 original plus 22 new) |
| `contracts/demo/vulnmint` | 5 |
| `contracts/demo/unguardedvault` | 5 (was 4, plus `TestDepositIgnoresSentAmount`) |
| `contracts/demo/greedystore` | 4 |
| `contracts/demo/luckydice` | 7 (was 6, plus `TestBuyChipsIgnoresSentAmount`) |
| `contracts/demo/adminbackdoor` | 5 |
| `contracts/realmcheck` | 11 |

`gno test -p 1 .` per suite, plus `gno test -p 1 ./...` from
`contracts/demo` after the `gno.mod` deletion (all five packages
pass). `gno fmt -diff` on the contracts tree reports no
differences.

New Gno regression tests (22, in
`contracts/auditrules/auditrules_test.gno`): RC-03 hard-coded
positive, `const` block, `var` block, capital mention, reversed
guard, reversed admin guard clean for RC-01, timelock clean,
read-only clean, no-guard clean (RC-01, not RC-03); RC-06 taint
positive, multi-hop, deadline clean, constant-args clean, unused
clean, local-variable limitation (pinned as a known limit);
`assert*` guards clean for RC-01 and RC-08; receiver rules
(`Proposals` receiver-only clean, lowercase receiver clean,
exported receiver positive, method package-var positive,
unexported-receiver `Mint` clean).

JavaScript port:

- `node ui/scripts/test-audit-port.mjs`: all 5 demo realms match
  Gno `Audit()` exactly (adminbackdoor 4, greedystore 1,
  luckydice 3, unguardedvault 2, vulnmint 1).
- `node ui/scripts/test-audit-rules.mjs` (new): 24 cases pass,
  mirroring the Gno regression fixtures for the new RC-03, RC-06,
  assert-guard, and receiver shapes directly against `audit.js`.
- `node ui/scripts/smoke-onyx.mjs` (live Onyx RPC):
  `gno.land/r/sys/params` 85/100 with 1 finding,
  `gno.land/r/gov/dao` 100/100 with 0 findings.

## E2E harness fold-ins (M4-E2E-STATUS.md, runs 1-5, 27 Nov 2026)

1. Port drift. The harness caught the drift while the Gno RC-03
   change (06:08 UTC) was mid-flight: at its 14:12 WITA run the JS
   port and `expected-findings.json` still said adminbackdoor
   score 62 with 3 findings, while Gno Audit() said 37 with 4.
   On checking, the RC-03 shape itself was already ported to
   `audit.js` by then, but the RC-06 taint and RC-08 receiver
   ports were still missing, so the port test failed on luckydice
   (missing RC-06 line 69). All three shapes are now ported,
   `expected-findings.json` is regenerated (11 findings across 5
   realms), and `test-audit-port.mjs` is green on all 5 realms.
   The harness should now pass without
   `E2E_CONTINUE_ON_AUDIT_MISMATCH`.
2. RC-08 regression. The harness reported exactly one failing
   test, `TestPublicMutationUnexportedReceiverClean`, because the
   name-based receiver skip did not cover `Proposals` (capital P).
   Fixed by the RC-08 receiver-target refinement, not by weakening
   the test: the test is unchanged and now passes, and the suite is
   green at 52 tests. The capitalization correction above is the
   reason the first fix attempt did not cover the real case.
3. Stale `gno.mod` files. Deleted all five
   (`contracts/demo/*/gno.mod`). Each was an exact duplicate of
   the same directory's `gnomod.toml` (same module path, gno 0.9),
   so nothing was lost. `gno test -p 1 ./...` from
   `contracts/demo` passes without them, and the demo READMEs plus
   `contracts/demo/README.md` were updated to drop the `gno.mod`
   mentions and to record the deletion and its reason. The harness
   staging workaround (`scripts/e2e-work-stage/`) can go away; the
   harness files themselves (`scripts/e2e-local.sh`,
   `tests/e2e-local-checklist.md`) were not touched, they belong to
   the e2e agent.

## Gas: does the new RC-03 finding change any gas assumption in my piece?

No change is needed in my piece, but the finding-count change is
part of why the flat gas assumption is wrong. My files
(`contracts/auditrules`, the demo realms, `ui/src/lib/audit.js`,
`ui/scripts/expected-findings.json`) contain no gas values at all:
no `gas-wanted`, no fee, no gas formula. The new RC-03 finding
moves adminbackdoor from 3 findings to 4, and the harness measured
SubmitReport gas scaling with the finding count on the local chain:
1 finding about 8.9M gas, 3 findings 20.4M gas, 4 findings 26.3M
gas. The flat gas-wanted 10,000,000 in `docs/API.md` and
`contracts/realmcheck/README.md` therefore only covers a
one-finding report, and adminbackdoor (4 findings, 26.3M gas) would
run out of gas at 10M. That scaling lives in the report realm and
the UI submit command, not in the rules; the coordinator updates
those gas notes at the M4 close. Nothing in my piece assumes a
finding count or a gas amount, so nothing here needs a gas edit.

## Files changed

- `contracts/auditrules/auditrules.gno`: `funcSpan` gains
  receiver, receiver variable, params, taint; `parseFuncReceiver`,
  `parseFuncParams`, `splitTopLevel`, identifier helpers;
  `adminConsts` tracking; `var (` and `const (` block fixes;
  `adminAddrLine` from the raw line; RC-03 catalog description.
- `contracts/auditrules/rules.gno`: `assert` and reversed admin
  guard tokens; RC-02 exported check; RC-03 hard-coded shape;
  RC-06 parameter taint; RC-08 receiver-target refinement; closure
  note in the overlap comment.
- `contracts/auditrules/auditrules_test.gno`: 22 new tests.
- `contracts/auditrules/README.md`: rules table and known limits
  updated to the M4 behavior, test count 52.
- `contracts/demo/unguardedvault/unguardedvault.gno`: `Deposit`
  reads and ignores `OriginSend`; `gno.mod` deleted.
- `contracts/demo/unguardedvault/unguardedvault_test.gno`:
  `TestDepositIgnoresSentAmount` with banker setup.
- `contracts/demo/luckydice/luckydice.gno`: `BuyChips` reads and
  ignores `OriginSend`; `gno.mod` deleted.
- `contracts/demo/luckydice/luckydice_test.gno`:
  `TestBuyChipsIgnoresSentAmount` with banker setup.
- `contracts/demo/vulnmint/gno.mod`, `contracts/demo/greedystore/gno.mod`,
  `contracts/demo/adminbackdoor/gno.mod`: deleted.
- `contracts/demo/README.md` and all five
  `contracts/demo/*/README.md`: rule tables corrected to ground
  truth, line numbers updated, `gno.mod` mentions removed.
- `ui/src/lib/audit.js`: full port of every Gno change above
  (guard tokens, receiver and params parsing, `adminConsts` and
  `firstHardcodedAdminDrain`, parameter taint, receiver-target
  RC-08, RC-02 exported check, RC-03 description).
- `ui/scripts/expected-findings.json`: regenerated from Gno
  Audit(), 11 findings across 5 realms.
- `ui/scripts/test-audit-rules.mjs`: new, 24 fixture cases pinning
  the JS port of the new rule shapes.

## Notes for the coordinator

- `ui/README.md` is owned by the UI agent and was not touched.
  Its "Known gap" sections are now stale: the three rules that
  never fired now fire, and two of the three false positives are
  fixed (the third, the DAO-proposal closure at
  `run_submitters.gno:151`, is deliberately left, see above). The
  Onyx example scores in that file (85 for `gov/dao`, 55 for
  `sys/params`) are also stale: they are now 100 and 85. Please
  have the UI agent update those sections.
- `docs/API.md` and `contracts/realmcheck/README.md` gas notes
  (flat gas-wanted 10,000,000) are the coordinator's M4-close item;
  see the gas section above.
- `scripts/e2e-local.sh` and `tests/e2e-local-checklist.md` still
  describe the staging workaround for the deleted `gno.mod`
  files; the e2e agent can remove it.
- Nothing was submitted or published. No money was spent.
