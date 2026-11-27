# adminbackdoor: admin backdoor demo realm

Module: `gno.land/r/dunoil/adminbackdoor`
Package: `adminbackdoor`
Files: `adminbackdoor.gno`, `adminbackdoor_test.gno`, `gnomod.toml`

## What it is

A treasury realm controlled by a single hard-coded admin address (`Admin`,
line 31, currently a placeholder address of all `q` characters). The
treasury is funded with `Fund`, drained with `Drain`, and pays bonuses in
vulnmint tokens with `PayBonus`. Funds are modeled as an internal ledger so
the realm is self-contained and testable offline.

## Rules it should trigger

| Rule | Where | Lines in `adminbackdoor.gno` |
| --- | --- | --- |
| Owner/admin backdoor (RC-03) | `Drain` lets the single hard-coded admin send the entire treasury to any address in one call, with no timelock, no spending cap, no second approver, and no multisig. One compromised key, or one malicious admin, empties the treasury in a single transaction. The admin is the hard-coded constant `Admin` (line 31); the rule flags the first state rewrite on the guarded drain path. | Comment lines 58-65, function line 66, rewrite line 75 |
| Sensitive function without caller check (RC-01) | `PayBonus` calls `vulnmint.Transfer` with no caller check, so anyone can trigger a bonus payment to anyone. | Function line 104, call line 105 |
| Unchecked external realm call (RC-07) | `FundBonusPool` calls `vulnmint.Mint` through `cross()` as a bare statement and ignores the result, so a failed mint passes silently. `PayBonus` also discards the `Transfer` error with `_ =` and records the bonus as paid no matter what happened, but that line is assigned, so RC-07 does not flag it; RC-01 flags it instead. | Function line 83, unchecked call line 84; `PayBonus` function line 104, discarded call line 105, record line 106 |
| Public state mutation with no guard (RC-08) | `Fund` changes persistent state (`treasury`) with no caller check, so anyone can credit the treasury. | Function line 49, mutation line 53 |

`Fund` (function line 49, credit line 53) also credits the treasury
without verifying that any payment was actually sent, but no rule flags
it: it never calls `OriginSend`, so RC-05 does not apply. It is a
secondary demonstration in prose only, like the vault and dice demos
before they were changed to call `OriginSend`.

## How the tests prove it

`adminbackdoor_test.gno`, run with `gno test -p 1 .`:

- `TestNonAdminCannotDrain`: a non-admin drain returns an error and the
  treasury is untouched. The check that exists is only "is the caller the
  admin"; nothing else constrains the admin.
- `TestAdminDrainsEverythingImmediately`: the admin drains the whole
  treasury in one call, to an address of its choosing. No timelock, no cap,
  no second approver.
- `TestPayBonusIgnoresFailedTransfer`: a bonus larger than the whole bonus
  pool is "paid". The recipient's vulnmint balance does not change, but the
  realm records the full amount as paid.
- `TestPayBonusWorksWhenFunded`: after `FundBonusPool` mints tokens into the
  realm (possible because `vulnmint.Mint` has no access control), the same
  `PayBonus` call really pays, and the books match. The two tests together
  show that the only difference between a real and a fake payout is whether
  the external call happened to succeed.
- `TestRender`: the realm renders a summary page.

## What the fix would be

Replace the single admin with multiple approvers, add a timelock between
proposal and execution, cap each withdrawal, and check the error returned
by every external realm call, aborting the payment when the call fails.
Restrict who can trigger bonus payments.

## Deploy notes

Deploy `vulnmint` first: `PayBonus` and `FundBonusPool` call it, so the
`gno.land/r/dunoil/vulnmint` realm must already exist on the chain at deploy
time. The `dunoil` namespace is a placeholder for local development; the
Onyx deploy phase may swap it for the deployer `g1` address, in both realms
together, and must replace the placeholder `Admin` address with the real
admin address. Do not use this code for a real treasury.
