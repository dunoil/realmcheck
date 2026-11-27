# RealmCheck demo vulnerable realms

Five deliberately vulnerable Gnolang realms that prove RealmCheck detection
works. Each realm is small, readable, valid, and passes its own `gno test`
suite. The vulnerabilities are intentional and documented, not bugs. Do not
use any of this code for a real token, vault, registry, game, or treasury.

Location: `~/workspace/gnome-tavern-hackathon/contracts/demo/`, one
subdirectory per realm. The `gnowork.toml` file in this directory is an
empty workspace marker, so `gno test` resolves the import of `vulnmint` by
`adminbackdoor` from the local workspace instead of from a chain.

## Realms

| Realm | Module | What it demonstrates |
| --- | --- | --- |
| `vulnmint` | `gno.land/r/dunoil/vulnmint` | A GRC20-like token whose `Mint` has no access control, anyone can mint any amount to any address. |
| `unguardedvault` | `gno.land/r/dunoil/unguardedvault` | A vault that credits deposits without verifying any payment, and lets anyone call `Withdraw` to take anyone's funds. |
| `greedystore` | `gno.land/r/dunoil/greedystore` | A registry that appends every entry to a persistent list with no cap and no size limit, so storage grows without bound. |
| `luckydice` | `gno.land/r/dunoil/luckydice` | A dice game whose winning number comes from block height and block time, and is publicly readable before betting. |
| `adminbackdoor` | `gno.land/r/dunoil/adminbackdoor` | A treasury where a single hard-coded admin can drain all funds at once, and bonus payouts ignore the result of an external realm call. |

Each realm has its own `README.md` stating which audit rules it should
trigger and on which lines, plus what the fix would be.

## Rule coverage

All eight audit rules from the RealmCheck plan are triggered by at least one
demo realm:

| Rule | Triggered by |
| --- | --- |
| Sensitive function callable without a caller check | `adminbackdoor.PayBonus` |
| Unrestricted mint | `vulnmint.Mint` |
| Owner/admin backdoor | `adminbackdoor.Drain` |
| Unbounded storage growth | `greedystore.Register` |
| Funds accepted without a check | `unguardedvault.Deposit`, `luckydice.BuyChips` |
| Weak randomness | `luckydice.DrawNumberAt`, reached through `luckydice.DrawNumber` |
| Unchecked external realm call | `adminbackdoor.FundBonusPool` (ignores the result of `vulnmint.Mint`) |
| Public state mutation with no guard | `unguardedvault.Deposit`, `luckydice.PlaceBet`, `adminbackdoor.Fund` |

## How funds are modeled

The vault, dice game, and treasury model funds as an internal ledger
(amounts tracked in memory) instead of moving real ugnot through the
banker. That keeps every realm self-contained, with no imports outside the
Gno standard library, and testable offline with `gno test`. The missing
checks demonstrated here are identical in a banker-based version, because
the checks belong around the ledger update and the payout, not inside the
banker call. Each realm README says this where it applies. `Deposit` and
`BuyChips` do read the real sent coins through
`chain/runtime/unsafe.OriginSend()` and then ignore them, so RC-05 fires
on the genuine shape; the ledger still holds the credited amounts.

## Module files

Each realm carries one module file, `gnomod.toml`, the canonical module
file in Gno v1.8.0 (`module = "gno.land/r/dunoil/<name>"`,
`gno = "0.9"`). The deprecated pre-v1.8 `gno.mod` file was deleted on
27 Nov 2026: it made `addpkg` and `gnodev -extra-root` fail with
"gno.mod file is deprecated and not allowed", so a plain chain could not
load the demo realms. `gno test` and the E2E harness pass without it.

## APIs used

The realms use only APIs available in Gnolang v1.8.0, verified against the
stdlib in `~/workspace/tools/gno`: `chain` (`chain.PackageAddress`,
`chain.Coins`), `chain/runtime` (`ChainHeight`), `chain/runtime/unsafe`
(`OriginSend`), `time` (`time.Now`), `strconv`, `strings`, `errors`,
`testing` (`testing.SetOriginCaller`, `testing.SetOriginSend`,
`testing.IssueCoins`, `testing.GetContext`), and the `realm`
type with `cross(cur)` and `cur.Previous().Address()` for caller identity.
Note for the audit-rules work: the plan's shorthand `std.Coin` and
`std.OriginCaller` map to `chain.Coins` and `cur.Previous().Address()` (or
`chain/runtime/unsafe.OriginCaller()`) in v1.8.0. There is no `std` package
in the v1.8.0 standard library.

## How to test

```bash
export PATH=$PATH:$HOME/workspace/tools/go/bin:$HOME/workspace/tools/gno/bin
export GNOROOT=$HOME/workspace/tools/gno
export GOMAXPROCS=2
cd ~/workspace/gnome-tavern-hackathon/contracts/demo
gno test -p 1 ./...
```

Test results, 27 Nov 2026: all five packages pass, 26 tests total
(vulnmint 5, unguardedvault 5, greedystore 4, luckydice 7, adminbackdoor 5).
`gno fmt -diff ./...` reports no formatting differences.

## Deploy order (Onyx testnet, later phase)

Deploy `vulnmint` before `adminbackdoor`, because `adminbackdoor` imports
`gno.land/r/dunoil/vulnmint` and calls it. The other three realms have no
dependencies and can deploy in any order. The `dunoil` namespace is a
placeholder for local development; the Onyx deploy phase may swap it for
the deployer `g1` address, in all five module paths and in the
`adminbackdoor` import together. Also replace the placeholder `Admin`
address in `adminbackdoor.gno` before any real use.

Nothing here has been deployed, no keys were created, and no funds were
requested or spent.
