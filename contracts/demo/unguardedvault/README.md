# unguardedvault: missing caller check demo realm

Module: `gno.land/r/dunoil/unguardedvault`
Package: `unguardedvault`
Files: `unguardedvault.gno`, `unguardedvault_test.gno`, `gnomod.toml`

## What it is

A vault that accepts deposits and pays withdrawals. Funds are modeled as an
internal ledger (`deposits`, `paidOut`, `vaultBalance`, all in ugnot) so the
realm is self-contained and testable offline. A production vault would move
real ugnot with `banker.SendCoins`; the missing checks demonstrated here are
identical in that version, because the checks belong around the ledger update
and the payout, not inside the banker call.

## Rules it should trigger

| Rule | Where | Lines in `unguardedvault.gno` |
| --- | --- | --- |
| Funds accepted without a check (RC-05) | `Deposit` reads the coins actually sent through `unsafe.OriginSend()` and then ignores them, crediting the claimed amount instead. It never compares the sent amount with the claimed amount, and does not require a user call. | Comment lines 33-42, function line 43, `OriginSend` line 48, credits lines 50-51 |
| Public state mutation with no guard (RC-08) | `Deposit` changes persistent state (`vaultBalance`) with no caller restriction at all. | Function line 43, mutation line 51 |

`Withdraw` (function line 64, payout lines 74-75) is the vault's other
intentional vulnerability: it never checks who the caller is and never
checks that the caller owns the funds, so anyone can pay the vault's
pooled balance to any address. No rule flags it today, because the
payout is a ledger update with no banker call, and RC-08 skips
withdraw-style functions (they belong to RC-01, RC-02, and RC-03).
The behavior is proven by `TestAnyoneCanWithdraw` instead; see the
known limit in the audit-rules README about ledger payouts.

## How the tests prove it

`unguardedvault_test.gno`, run with `gno test -p 1 .`:

- `TestDepositWithoutSendingCoins`: Alice claims a deposit of 1000 without
  sending any coins, and the credit still lands.
- `TestDepositIgnoresSentAmount`: Alice really holds and sends 10 ugnot
  (banker setup with `testing.IssueCoins` and `testing.SetOriginSend`,
  verified through `testing.GetContext()`), then claims a deposit of
  1000, and the full 1000 is credited. The sent amount is ignored.
- `TestAnyoneCanWithdraw`: Alice deposits 1000, then an attacker who never
  deposited anything withdraws the full 1000 to itself. The vault balance
  drops to 0 while Alice's recorded deposit still reads 1000, so the books
  no longer add up.
- `TestWithdrawMoreThanBalanceErrors`: withdrawing more than the vault holds
  returns an error. The only check that exists is the balance check.
- `TestRender`: the realm renders a summary page.

## What the fix would be

In `Deposit`, read the sent coins from the transaction envelope
(`unsafe.OriginSend()`) and credit exactly that amount, and require a user
call. In `Withdraw`, require the caller to be the depositor (or an approved
spender) and debit that caller's own deposit balance, never the pooled
balance of strangers.

## Deploy notes

No dependencies. Deploy any time. The `dunoil` namespace is a placeholder
for local development; the Onyx deploy phase may swap it for the deployer
`g1` address.
