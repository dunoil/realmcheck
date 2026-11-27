# realmcheck: on-chain report store

Module: `gno.land/r/dunoil/realmcheck`
Package: `realmcheck`
Files: `realmcheck.gno`, `realmcheck_test.gno`, `gnomod.toml`
Imports: `gno.land/p/dunoil/auditrules`

## What it is

The on-chain store for RealmCheck audit reports. Audits run off chain (the UI
runs the audit-rules package against a realm's source text), and their results
are stored here so any report is public, shareable, and verifiable. The stored
source hash lets anyone re-run the audit against the same source and compare.
This realm never audits; it only stores, indexes, and renders reports.

Deploy order: deploy the audit-rules package first, then this realm, because
this realm imports it. On Onyx the `dunoil` namespace is swapped for the
deployer `g1` address in both module paths.

## API

- `SubmitReport(realmPath string, sourceHash string, score int, findings string) int`
  Stores a report and returns its numeric ID. `findings` is one finding per
  line, fields separated by `|`: `RULEID|Severity|Line|Title|Description|SourceLine`.
  A malformed line is skipped, never fatal. The severity stored for a finding
  is the catalog severity of its rule when the encoded severity is not one of
  the four known values. The caller address is recorded as Auditor, and the
  current block height as Height.
- `GetReport(id int) (auditrules.Report, bool)` (read-only)
- `LatestReport(realmPath string) (auditrules.Report, bool)` (read-only)
- `ReportCount() int` (read-only)
- `Render(path string) string` (read-only): Markdown page listing recent
  reports, newest first, up to 20 entries.

Input validation (added after reading the Gno repo security guide, which notes
`Render` receives attacker-controlled input): `SubmitReport` rejects realm
paths that are not `gno.land/` paths with safe characters only (letters,
digits, slash, dot, underscore, hyphen), and source hashes that are not hex
strings of at most 128 characters. This keeps user-supplied values from
injecting lines into the rendered page.

The `Report` struct lives in the auditrules package so the realm, the UI, and
the agent mode share one shape:
`Report{ID, RealmPath, SourceHash, Score, Auditor, Height, Findings []Finding}`.

## Gas notes (measured on a local dev chain, 27 Nov 2026)

- `SubmitReport` gas scales with the finding count (measured on a local
  dev chain, 27 Nov 2026: 1 finding used 8,904,806 gas, 3 findings
  20.4M, 4 findings 26.3M; a 1-finding report stored 2,461 bytes, a
  246,100 ugnot storage fee). Use gas-wanted 10,000,000 plus 7,000,000
  per finding. A flat 10,000,000 only covers a one-finding report.
- The chain enforces a minimum gas price of 1 ugnot per 1,000 gas, so the fee
  must be at least gas-wanted divided by 1,000. Use gas-fee gas-wanted
  divided by 500 (twice the minimum, for safety). A call with
  gas-wanted 10,000,000 and gas-fee 2,000 ugnot fails with an insufficient fee
  error, and a call with gas-wanted 2,000,000 fails with an out of gas error.
- The same minimum price applies on Onyx. Always set the fee from the
  gas-wanted value, never from the docs example alone. The M3 example
  command below used wanted 10,000,000 for a 1-finding report and
  succeeded because only 7,854,767 gas was used; the formula above is
  the safe general rule for new calls.

## Local end-to-end test (verified 27 Nov 2026)

The test ran against `gnodev local` (chain ID `dev`, RPC 127.0.0.1:26657),
with a local dev key `realmcheck-dev` funded by `-add-account`. The audit
was real: the audit-rules package `Audit()` ran against the actual
`vulnmint.gno` source and returned exactly 1 finding (RC-02 Critical,
line 41, score 75). That output, not a hand-written example, was stored.

Commands (from `~/workspace/gnome-tavern-hackathon/contracts`, with the
toolchain PATH lines from `ENV-TOOLCHAIN.md` exported):

```bash
# Start the local chain (workspace packages are lazy-loaded, see the note below)
gnodev local -add-account g1yzqhuxczln72kwm9pstcmjerhnu0uverkuyz4h=100000000ugnot

# Read-only checks (no gas, no key)
gnokey query vm/qeval -data "gno.land/r/dunoil/realmcheck.ReportCount()" -remote 127.0.0.1:26657
gnokey query vm/qeval -data "gno.land/p/dunoil/auditrules.Score(nil)" -remote 127.0.0.1:26657

# Store the real vulnmint audit (score 75, source SHA-256 f8616d8b...)
printf 'devpass\n' | gnokey maketx call -insecure-password-stdin \
  -pkgpath "gno.land/r/dunoil/realmcheck" -func "SubmitReport" \
  -args "gno.land/r/dunoil/vulnmint" \
  -args "f8616d8b7c69e820e2b20aa49f970c8a7fe64e6e390367ae464f93db627f5b7e" \
  -args "75" \
  -args 'RC-02|critical|41|Unrestricted mint|Function Mint mints new coins with no caller check in its own body. Restrict minting to an authorized minter or owner, and cap total supply where the design allows it. A guard in a wrapper function does not count for this check.|func Mint(cur realm, to address, amount int64) {' \
  -gas-fee 20000ugnot -gas-wanted 10000000 -chainid dev -remote 127.0.0.1:26657 realmcheck-dev

# Verify the stored report
gnokey query vm/qeval -data "gno.land/r/dunoil/realmcheck.GetReport(1)" -remote 127.0.0.1:26657
gnokey query vm/qeval -data 'gno.land/r/dunoil/realmcheck.LatestReport("gno.land/r/dunoil/vulnmint")' -remote 127.0.0.1:26657
gnokey query vm/qeval -data 'gno.land/r/dunoil/realmcheck.Render("")' -remote 127.0.0.1:26657
```

Observed results: SubmitReport returned `(1 int)`, OK, height 3, gas used
7,854,767, storage delta 2,461 bytes, total tx cost 266,100 ugnot.
GetReport(1) returned the full Report (ID 1, realm path, source hash, score
75, auditor the dev key address, height 3, 1 finding). LatestReport returned
the same report. Render returned Markdown listing `#1 ... vulnmint score 75,
1 findings`. The gnoweb page at `http://127.0.0.1:8888/r/dunoil/realmcheck`
served the rendered report list with title "RealmCheck reports - gno.land".

Unit tests: `gno test -p 1 .` in this directory, 8 tests pass. The auditrules
tests (30 tests) still pass after the Report struct was added.

## Notes

- On `gnodev local`, workspace packages are lazy-loaded at startup, so
  `gnokey maketx addpkg` for a package already in the workspace fails with
  "package already exists". That is a local-dev behavior, not a bug. On Onyx,
  deploy with `addpkg` as documented in `ENV-ONYX.md`.
- The local dev key `realmcheck-dev` (address
  g1yzqhuxczln72kwm9pstcmjerhnu0uverkuyz4h) is for the local chain only. It
  lives in the local gnokey home, never in the repo. The Onyx deploy uses a
  fresh key.
- `gnokey query vm/qrender` with the realm path as a positional argument
  printed usage on this toolchain. Use the `vm/qeval` form with
  `Render("")` instead, as shown above.
