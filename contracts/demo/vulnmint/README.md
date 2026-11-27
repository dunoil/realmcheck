# vulnmint: unrestricted mint demo realm

Module: `gno.land/r/dunoil/vulnmint`
Package: `vulnmint`
Files: `vulnmint.gno`, `vulnmint_test.gno`, `gnomod.toml`

## What it is

A small GRC20-like token with an internal ledger (`balances`, `totalSupply`).
It has `Mint`, `Transfer`, `BalanceOf`, `TotalSupply`, and `Render`. The token
works exactly like a normal token, except that minting is completely open.

## Rules it should trigger

| Rule | Where | Lines in `vulnmint.gno` |
| --- | --- | --- |
| Unrestricted mint | `Mint` never checks the caller: no owner check, no minter role, no allowlist, no supply cap. Any address can create any amount for any address. | Comment lines 34-40, function line 41, credits lines 48-49 |

`Transfer` (line 60) is deliberately the honest counterpart: it debits only
the immediate caller and returns an error on insufficient balance instead of
panicking, so a calling realm can observe a failed transfer. The
adminbackdoor demo realm ignores that error on purpose.

## How the tests prove it

`vulnmint_test.gno`, run with `gno test -p 1 .`:

- `TestMintByAnyone`: a stranger with no role mints 1,000,000 tokens to
  herself, then a second stranger mints 500,000 to himself. Total supply
  becomes 1,500,000.
- `TestMintToAnyAddress`: a stranger mints tokens straight into someone
  else's balance.
- `TestTransferMovesBalance` and `TestTransferInsufficientBalanceErrors`:
  transfers behave normally and an overdraw returns an error.
- `TestRender`: the realm renders a summary page.

## What the fix would be

Require the caller to be an authorized minter (check
`cur.Previous().Address()` against a stored minter or owner), and enforce a
supply cap in `Mint`.

## Deploy notes

No dependencies. Deploy any time. The `dunoil` namespace is a placeholder
for local development; the Onyx deploy phase may swap it for the deployer
`g1` address.
