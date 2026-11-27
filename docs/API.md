# RealmCheck API spec (v1)

Contract between the report realm, the web UI, and the agent mode. All paths use the
placeholder namespace `dunoil` for local dev. The Onyx deploy phase swaps the namespace
to the deployer `g1` address in every module path and in the adminbackdoor import.

## Audit-rules package

Path: `gno.land/p/dunoil/auditrules`
Source: `contracts/auditrules/`

- `Finding{RuleID, Severity, Title, Description, File, Line, SourceLine}` (Line is 1-based).
- `Rule{ID, Name, Severity, Description}`; `Rules() []Rule`; `RuleByID(id) (Rule, bool)`.
- `Audit(src string) []Finding`; `AuditFile(file, src string) []Finding`.
- `Score(findings) int`, 0 to 100. Weights: critical 25, high 15, medium 8, low 3.
- One `Check*` function per rule. Rules RC-01 to RC-08, see `contracts/auditrules/README.md`.

## Report realm

Path: `gno.land/r/dunoil/realmcheck`
Source: `contracts/realmcheck/` (to build in phase 3)
Imports: `gno.land/p/dunoil/auditrules`

Findings encoding for `SubmitReport`: one finding per line, fields separated by `|`:
`RULEID|Severity|Line|Title|Description|SourceLine`
Example line: `RC-02|Critical|14|Unrestricted mint|Mint has no access control|func Mint(to string, amount int) {`
The realm parses this with `strings.Split` into `[]auditrules.Finding`.

Functions:

- `SubmitReport(realmPath string, sourceHash string, score int, findings string) int`
  Stores a Report and returns its numeric ID. The caller address is recorded as
  Auditor. `sourceHash` is the hex SHA-256 of the exact source audited, so anyone
  can re-run the audit and compare.
- `GetReport(id int) (auditrules.Report, bool)` (read-only, use `vm/qeval`)
- `ReportFindings(id int) string` (read-only): the findings of the stored
  report, one per line in the SubmitReport encoding. Chain query printers
  show slices as references, not values, so a UI cannot read the findings
  list from GetReport directly. Returns "" for an unknown ID.
- `LatestReport(realmPath string) (auditrules.Report, bool)` (read-only)
- `ReportCount() int` (read-only)
- `Render() string` (read-only): Markdown page listing recent reports with realm
  path, score, finding count, and auditor.

## Gas (measured on a local dev chain, 27 Nov 2026)

- `SubmitReport` gas scales with the finding count (measured on a local
  dev chain, 27 Nov 2026: 1 finding used 8,904,806 gas, 3 findings
  20.4M, 4 findings 26.3M; a 1-finding report also stored 2,461 bytes,
  a 246,100 ugnot storage fee). Use gas-wanted 10,000,000 plus
  7,000,000 per finding. A flat 10,000,000 only covers a one-finding
  report and fails out of gas on larger ones.
- Minimum gas price is 1 ugnot per 1,000 gas, so the fee must be at least
  gas-wanted divided by 1,000. Use gas-fee gas-wanted divided by 500
  (twice the minimum, for safety). The same rule applies on Onyx.
- On `gnodev local`, workspace packages are lazy-loaded, so `addpkg` for a
  package already in the workspace fails with "package already exists".
  On Onyx, deploy with `addpkg`.
- `gnokey query vm/qrender` with the realm path as a positional argument
  printed usage on this toolchain. Use the `vm/qeval` form with `Render("")`.

Report struct (defined in the auditrules package so the UI, realm, and agent mode
share one shape):

- `Report{ID int, RealmPath string, SourceHash string, Score int, Auditor string, Height int, Findings []Finding}`

## Web UI

Source: `ui/` (to build in phase 3 and polish in phase 4)
Deploy: GitHub Pages (static, free)

Flow:

1. Home/search: user pastes a realm path, for example `gno.land/r/dunoil/vulnmint`.
2. The UI fetches the realm source live from Onyx (verify the endpoint first:
   `vm/qfile` over the RPC, or the gnoweb source view; record which one is used).
3. The UI runs the audit client-side in JavaScript, a direct port of rules RC-01
   to RC-08 from `contracts/auditrules/rules.gno`. The port must produce the same
   findings as `Audit()` on the demo realms (test this locally against the demo
   sources before calling it done).
4. The report page shows the score, findings with cited lines, and the source hash.
5. "Save on-chain": calls `SubmitReport` on the report realm. If Adena is present,
   sign with Adena. If not, show the exact `gnokey maketx call` command.
6. A saved report links to its gnoweb Render page and to the UI report view
   (`?realm=<path>` loads `LatestReport`, `?id=<n>` loads `GetReport`).

## Agent mode (gnomcp, phase 5)

- MCP server config plus a `gno` agent skill that exposes one audit flow:
  read a realm with `gno_read`/`gno_render`, run the audit, and store the report
  with `SubmitReport`.
- The agent mode reuses this same spec. No separate API.

## Notes

- Gnolang v1.8.0 has no `std` package. The plan's `std.Coin` / `std.OriginCaller`
  shorthand maps to `chain.Coins` and `cur.Previous().Address()` (or
  `chain/runtime/unsafe.OriginCaller()`). Use the real APIs.
- `gno mod init` writes `gnomod.toml` in v1.8.0, not `gno.mod`.
- Demo realm deploy order on Onyx: vulnmint first (adminbackdoor imports it).
  The `dunoil` namespace and the placeholder Admin address in adminbackdoor must
  be replaced at deploy time.
