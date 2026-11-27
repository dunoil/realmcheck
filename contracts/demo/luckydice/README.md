# luckydice: weak randomness demo realm

Module: `gno.land/r/dunoil/luckydice`
Package: `luckydice`
Files: `luckydice.gno`, `luckydice_test.gno`, `gnomod.toml`

## What it is

A dice game. Players buy chips with `BuyChips`, then bet 100 chips on a
number from 0 to 5 with `PlaceBet`. A win pays 500 chips. Chips are modeled
as an internal ledger so the realm is self-contained and testable offline.

## Rules it should trigger

| Rule | Where | Lines in `luckydice.gno` |
| --- | --- | --- |
| Weak randomness (RC-06) | `DrawNumber` passes `runtime.ChainHeight()` and `time.Now().Unix()` (the block time) into the pure helper `DrawNumberAt`, which applies the modulo there. Both values are public before the bet is placed, and the number is readable by anyone through `DrawNumber` itself, so any caller can compute the winner in advance, or simply read it, and then bet on it. The rule follows the values across the helper call and flags the modulo line in `DrawNumberAt`. | Helper function line 68, modulo line 69; caller function line 83, call line 84 |
| Funds accepted without a check (RC-05) | `BuyChips` reads the coins actually sent through `unsafe.OriginSend()` and then ignores them, crediting the claimed chip amount instead. It never compares the sent amount with the claimed amount. | Comment lines 46-55, function line 56, `OriginSend` line 61, credit line 63 |
| Public state mutation with no guard (RC-08) | `PlaceBet` changes persistent state (`totalWagered`) with no caller restriction at all. | Function line 94, mutation line 103 |

## How the tests prove it

`luckydice_test.gno`, run with `gno test -p 1 .`:

- `TestDrawNumberAtKnownValues`: the formula is exact and public. Hand
  computed values are asserted: `DrawNumberAt(10, 1700000000)` is 0 and
  `DrawNumberAt(11, 1700000000)` is 1, so anyone can reproduce the draw off
  chain.
- `TestDrawNumberMatchesFormula`: the live draw equals the public formula
  applied to the public height and time.
- `TestPredictedGuessWins`: an attacker reads the public winning number,
  bets on it, and ends up ahead. The test retries a few times in case a
  second ticks over between reading the number and placing the bet.
- `TestBuyChipsIgnoresSentAmount`: Alice really holds and sends 10 ugnot
  (banker setup with `testing.IssueCoins` and `testing.SetOriginSend`,
  verified through `testing.GetContext()`), then claims 1000 chips, and
  the full 1000 are credited. The sent amount is ignored.
- `TestPlaceBetInsufficientChips` and `TestPlaceBetBadGuess`: the ordinary
  input checks still work.
- `TestRender`: the realm renders a summary page, including the next winning
  number in plain sight.

## What the fix would be

Never seed a game of chance with block height or block time. Use a commit
and reveal scheme, a verifiable random function, or an oracle that reveals
the result only after bets close. At minimum, stop publishing the winning
number before the bet resolves.

## Deploy notes

No dependencies. Deploy any time. The `dunoil` namespace is a placeholder
for local development; the Onyx deploy phase may swap it for the deployer
`g1` address.
