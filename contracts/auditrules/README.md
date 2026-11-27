# auditrules

A pure, stateless Gnolang package that audits the source text of a
Gno.land realm and returns deterministic findings with exact source
lines cited. It is the deterministic core of RealmCheck: these rules
produce the risk score, and an LLM only explains findings later, it
never scores.

Module path: `gno.land/p/dunoil/auditrules`

## What it does

`Audit(src)` takes realm source text and returns a list of findings.
Each finding names the rule, the severity, a plain English title and
description, and the exact 1-based line number plus the source line
that triggered it, so a report page can cite the line verbatim.

The scanner is lexical, not a full parser. It splits the source into
lines, blanks out comments and string contents for matching, tracks
brace depth to find function spans, and looks for known risky shapes.
A finding means "a human should look at this line". A clean result
means "no known shape was found", not "this realm is safe". See
[Known limits](#known-limits) for the false positive and false
negative cases this implies.

## Module path note

The namespace `dunoil` in `gno.land/p/dunoil/auditrules` is a
placeholder for local development. The Onyx deployment in a later
phase may swap it to the deployer `g1` address. The path lives in
exactly one place, the `gnomod.toml` file in this directory. Do not
hardcode it anywhere else; if it changes, change that file only.

Toolchain note: in Gno v1.8.0, `gno mod init <path>` writes
`gnomod.toml`, not `gno.mod`, even though its help text says
"gno.mod". This package therefore ships `gnomod.toml` with
`module = "gno.land/p/dunoil/auditrules"` and `gno = "0.9"`.

## Files

| File | Contents |
| --- | --- |
| `gnomod.toml` | Module path, the single source of truth for it. |
| `auditrules.gno` | Types, rule catalog, `Audit`, `AuditFile`, `Score`, source parsing, helpers. |
| `rules.gno` | The eight rule checks, one exported `Check*` function per rule. |
| `auditrules_test.gno` | Unit tests, a positive and a clean case per rule, plus API tests. |

## API

```go
package auditrules

type Severity string

const (
    SeverityCritical Severity = "critical"
    SeverityHigh     Severity = "high"
    SeverityMedium   Severity = "medium"
    SeverityLow      Severity = "low"
)

type Finding struct {
    RuleID      string
    Severity    Severity
    Title       string
    Description string
    File        string
    Line        int
    SourceLine  string
}

type Rule struct {
    ID          string
    Name        string
    Severity    Severity
    Description string
}
```

| Function | Description |
| --- | --- |
| `Audit(src string) []Finding` | Audit one realm source text. Findings come back in rule order, then line order. |
| `AuditFile(file string, src string) []Finding` | Same as `Audit`, with `file` attached to every finding. |
| `Rules() []Rule` | The full rule catalog in ID order. |
| `RuleByID(id string) (Rule, bool)` | One catalog entry by ID, or false for an unknown ID. |
| `Score(findings []Finding) int` | Deterministic 0 to 100 score. 100 means no findings. |
| `SeverityWeight(s Severity) int` | Score cost of one finding: critical 25, high 15, medium 8, low 3. |
| `CheckNoCallerGuard(src string) []Finding` | Rule RC-01 only. |
| `CheckUnrestrictedMint(src string) []Finding` | Rule RC-02 only. |
| `CheckAdminBackdoor(src string) []Finding` | Rule RC-03 only. |
| `CheckUnboundedStorage(src string) []Finding` | Rule RC-04 only. |
| `CheckFundsWithoutCheck(src string) []Finding` | Rule RC-05 only. |
| `CheckWeakRandomness(src string) []Finding` | Rule RC-06 only. |
| `CheckUncheckedExternalCall(src string) []Finding` | Rule RC-07 only. |
| `CheckPublicStateMutation(src string) []Finding` | Rule RC-08 only. |

Defensive caps, all exported constants:

| Constant | Value | Meaning |
| --- | --- | --- |
| `MaxSourceBytes` | 262144 | Inputs longer than 256 KiB are truncated before scanning. |
| `MaxLines` | 20000 | At most this many source lines are scanned. |
| `MaxFindings` | 256 | `Audit` returns at most this many findings. |

Findings are deduplicated by rule ID plus line number, so one line
never produces the same rule twice.

## Rules

All eight rules from the design were implemented. None was dropped.

| ID | Rule | Severity | Triggers when | Suppressed when |
| --- | --- | --- | --- | --- |
| RC-01 | Sensitive function without caller check | High | An exported function moves funds (`SendCoins`, `RemoveCoin`, `Transfer(`, `Withdraw`, admin setters) with no caller guard in its own body. | A guard token appears in the same function: `IsUserCall`, `IsUserRun`, `IsUser(`, `IsRealm(`, `OriginCaller`, `AssertOriginCall`, `PreviousRealm`, owner or admin checks, and related idioms. Any `assert*` helper call also counts as a guard, and admin or owner comparisons count in either order (`caller != Admin` and `Admin != caller`). |
| RC-02 | Unrestricted mint | Critical | An exported function named `Mint` issues coins or grows supply (`IssueCoin`, `Supply`, `balances`, `Balance`) with no caller guard in its own body. A `Mint` method on an unexported type is not flagged: only the realm's own code can reach it. | A caller guard appears in the same function. |
| RC-03 | Single admin backdoor | Critical | A single admin or owner can drain funds or rewrite state, and the path has no timelock or multi-signature check. Two shapes: a stored admin or owner variable mentioned on a `SendCoins` or `Withdraw` drain path, or a hard-coded admin or owner constant (an admin or owner variable initialized with an address literal) guarding a function that drains funds or rewrites persistent state. This is a design level flag: it may be intentional, but one key controls the funds. | A timelock token (`Timelock`, `UnlockTime`, `ExecuteAfter`, `MinDelay`, and similar) or a multi-signature token (`MultiSig`, `Threshold`, `Approvals`, and similar) appears in the drain function. |
| RC-04 | Unbounded storage growth | Medium | A persistent collection, a package-level slice or a struct field, is appended to with no length check or cap token in the same function. | Any `len(`, `Max`, `Limit`, or `limit` token appears in the same function. Appends to local slices are never flagged. |
| RC-05 | Funds accepted without a check | High | A function reads coins sent with the transaction through `OriginSend` but never verifies the amount. | An amount verification appears in the same function: `AmountOf`, `IsGTE`, `IsEqual`, `IsPositive`, `IsZero`, `GetCoin`. |
| RC-06 | Weak randomness | Medium | Block height, block time, or `time.Now` appears on the same line as modulo (`%`) or a random call (`rand`, `Random`, `Seed`), or is passed as an argument to a helper in the same file that applies modulo or a random call to that parameter. Taint follows parameters across calls in the same file, up to eight hops. | Height or time used without modulo or a random call, for example a deadline comparison, is not flagged. A helper that receives the value but never applies modulo or a random call to it is not flagged. |
| RC-07 | Unchecked external realm call | Medium | A cross-realm call through `cross()` is made as a bare statement, with no assignment and no error mention on the line. | The call is assigned, returned, or used in an `if`, or the line mentions `err`. |
| RC-08 | Public state mutation without guard | High | An exported function mutates realm state, through a package-level variable assignment or a `.Set(`, `.Delete(`, or `.Remove(` call, with no caller guard in its own body. | A caller guard appears in the same function. `Render` is never flagged. A method on an unexported type is never flagged. A method whose only mutations target its own receiver (`ps.Set`) is not flagged: the receiver is a value the caller already holds, so the call rewrites the caller's own instance, not shared realm state. |

Overlap policy, so one root cause does not produce a stack of
findings: `IssueCoin` is covered by RC-02, not RC-01. Mint and
withdraw style functions are covered by RC-01, RC-02, and RC-03, not
RC-08. Append growth is covered by RC-04, not RC-08.

### Scoring

`Score` starts at 100 and subtracts the severity weight of each
finding, floored at 0. One critical finding scores 75, one high
scores 85, one medium scores 92. The score is deterministic: the
same source always produces the same score.

## Running the tests

The `gno` CLI is required. Phase 1 built `gnokey`, `gnodev`, and
`gnoland`, but not `gno`; it was built from the same v1.8.0 source
during this phase and now lives at `~/workspace/tools/gno/bin/gno`.

```bash
export PATH=$PATH:$HOME/workspace/tools/go/bin:$HOME/workspace/tools/gno/bin
export GNOROOT=$HOME/workspace/tools/gno
export GOMAXPROCS=2
cd ~/workspace/gnome-tavern-hackathon/contracts/auditrules
gno test -p 1 .
```

Use `-p 1`: RAM is tight on the dev VM, and the default parallelism
can exhaust it. Add `-v` for per-test output including gas used.

Current result: 52 tests pass, 0 fail, including a positive and a
clean case for every rule, plus catalog, scoring, line number,
comment and string handling, combined audit, and input cap tests.
The 22 tests added for the M4 rule work cover the hard-coded admin
shape (including `const` and `var` blocks, reversed guards, and the
timelock and read-only clean cases), parameter taint for RC-06
(including multi-hop flow and the local-variable limit),
`assert*` guards, and methods on unexported receiver types.

## Gnolang research: what the stdlib can do in v1.8.0

Researched against the Gno v1.8.0 source in
`~/workspace/tools/gno`, the compatibility table in
`docs/resources/go-gno-compatibility.md`, and the stdlib docs in
`docs/resources/gno-stdlibs.md`. The local source is authoritative:
all four text packages ship as `.gno` files under
`gnovm/stdlibs/` with their own test suites.

| Package | Usable on-chain | Notes |
| --- | --- | --- |
| `strings` | Yes, full | `Contains`, `Index`, `Split`, `TrimSpace`, `Fields`, `HasPrefix`, `ToLower`, `Builder`, and the rest. This package uses it for all matching. |
| `strconv` | Yes, full | Full except the `complex64` and `complex128` helpers, which do not exist because Gno has no complex types. `Itoa` is used for finding keys. |
| `bytes` | Yes, full | Available, including `Buffer` and `Reader`. Not needed here: all scanning works on strings directly. |
| `regexp` | Yes, full | `Compile`, `MatchString`, `FindString`, and the rest, plus `regexp/syntax`, are all marked full and ship with tests. |
| `unicode`, `unicode/utf8` | Yes, full | Available for rune level work if a later rule needs it. |
| `sort` | Partial | `sort.Sort` with an explicit `sort.Interface` works. The closure helpers `sort.Slice`, `sort.SliceStable`, `sort.SliceIsSorted`, and `sort.Find` do not exist. Not needed: findings are already emitted in deterministic order. |
| `math/rand` | Yes, v2 names only | Gno ports Go `math/rand/v2`. The v1 names (`Intn`, `Seed`, `NewSource`) do not exist; use `IntN`, `New`, `NewPCG`. |
| `time` | Yes, full, with a catch | `time.Now` returns block time, not wall clock time, for determinism. `Sleep`, `After`, `Tick`, `NewTicker`, and `NewTimer` do not exist. This is why RC-06 treats `time.Now` as a weak randomness source. |
| `fmt` | Partial | Works in test files, but in package code it depends on `reflect`, which is not implemented, so most formatting verbs are unavailable. This package avoids `fmt` entirely and builds descriptions with string concatenation. |
| `errors` | Partial | `New`, `Is`, `Unwrap`, `Join` exist. `As` does not, it needs `reflect`. Not needed here. |
| `chain`, `chain/banker`, `chain/runtime` | Yes | The chain primitives the audited realms use: `Coin`, `Banker`, `ChainHeight`, `OriginCaller`, `OriginSend`, `IsUserCall`, and related calls. The scanner matches these names as text; it does not import them, because a pure package must stay stateless. |

### Other limits that shaped the design

- Language target is Go 1.17. No generics, no type parameters, no
  `min`, `max`, or `clear` builtins, no dot imports. `any` is
  supported as an alias for `interface{}`.
- No goroutines, no channels, no `select`, no `unsafe`, no `os`,
  no `net`. A pure package cannot read files or the network, which
  is why the audit input is a source string passed in by the caller.
- No `reflect`. Anything that needs reflection, including most of
  `fmt` and the `encoding` reflection helpers, is unavailable.
- Converting a `string` to `[]byte` or `[]rune` produces a slice
  with `cap == len`, for determinism.
- `regexp` was deliberately NOT used, even though it is available.
  Plain `strings.Contains` and `strings.Index` matching is cheaper
  in gas, cannot fail to compile a pattern at audit time, and keeps
  the scanner behavior obvious. A later rule that needs real pattern
  matching can add `regexp` without changing the API.
- Caller identity in Gno is subtle, and the scanner is honest about
  it. `IsUser()` accepts `MsgRun` ephemeral realms, so it is a
  weaker guard than `IsUserCall()` on payment paths that use
  `banker.OriginSend()`. This package counts `IsUser()` as a guard,
  per the rule definition; a stricter payment-path rule is future
  work, not a silent redefinition.
- `PreviousRealm()` only identifies the caller inside a crossing
  function. A `PreviousRealm` check inside a non-crossing function
  does not identify the immediate caller. The scanner counts the
  token wherever it appears, which is another reason findings are
  signals for human review, not verdicts.

## Known limits

- Guards in wrapper functions do not count. A guard must appear in
  the same function body as the sensitive action. This can produce a
  false positive when the guard lives in the caller.
- The same applies to a mutation inside a closure passed to another
  function, such as a DAO proposal executor: the closure body is
  scanned as part of the enclosing function, because the scanner
  cannot prove the callee only runs it after a vote, and trusting the
  callee name would hide a real finding in a realm that invokes the
  closure immediately. On live Onyx code this leaves one known false
  positive: `sys/params` `run_submitters.gno:151`, a state rewrite
  inside a closure passed to `newDelegateProposal`. It stays flagged
  on purpose; see `M4-RULES-STATUS.md`.
- The scanner is lexical. It blanks comments and string contents
  before matching, so keywords in comments or strings do not fire,
  but it does not parse types, so it cannot tell a local variable
  from a persistent one except through the package-level variable
  list and field access shapes.
- RC-04 is suppressed by any `len(` call in the same function, even
  one unrelated to a cap. RC-07 treats any assignment of a
  cross-realm call as handled, even when the error value is never
  checked afterwards.
- RC-05 only detects the `OriginSend` shape. A function that takes
  coins as a plain parameter and never checks them is not flagged.
- RC-03 needs a stored admin or owner variable, or a hard-coded admin
  or owner constant, to fire. An admin passed in as a parameter on
  every call is not tracked.
- RC-06 taint follows parameters across calls in the same file only.
  A helper defined in another file of the same realm is not tracked,
  taint does not follow local variables (a caller that stores the
  source in a local first defeats it), and taint stops after eight
  call hops. A multi-line function signature records no parameters,
  so calls to it are not tracked either.
- RC-08 skips methods whose only mutations target their own receiver,
  on the grounds that the receiver is caller-held state. A realm
  that hands out its stored instance through a getter defeats this:
  an external caller could then mutate shared state through the
  method, and the getter pattern is not detected.
- RC-01 does not flag ledger payouts. A function that pays out by
  updating an internal ledger (`vaultBalance -= amount`) with no
  banker call contains no RC-01 action token, so a missing caller
  check on such a payout is proven by tests, not by a finding. The
  `unguardedvault.Withdraw` demo is that case.
- Findings are heuristic. A clean audit is not proof of safety, and
  a finding is not proof of exploitability. Both need human review.
