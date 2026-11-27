# greedystore: unbounded storage growth demo realm

Module: `gno.land/r/dunoil/greedystore`
Package: `greedystore`
Files: `greedystore.gno`, `greedystore_test.gno`, `gnomod.toml`

## What it is

A registry of entries (`Entry` records with ID, author, title, and data).
Anyone can register an entry with `Register`, and entries can be read back
with `GetEntry` and counted with `EntryCount`. The list is never pruned,
capped, or paged.

## Rules it should trigger

| Rule | Where | Lines in `greedystore.gno` |
| --- | --- | --- |
| Unbounded storage growth | `Register` appends to the persistent `entries` slice on every call, with no maximum entry count, no maximum entry size, no per-user quota, and no deduplication. Each call permanently grows on-chain state, so the storage deposit grows without bound. | Comment lines 32-39, function line 40, append line 47 |

`Register` has no caller check of any kind, but no second rule flags
it: append growth belongs to RC-04, and RC-08 skips append lines, so
the one finding is the unbounded append itself.

## How the tests prove it

`greedystore_test.gno`, run with `gno test -p 1 .`:

- `TestRegisterByAnyone`: two strangers with no role both register entries
  and both are stored with the correct authors.
- `TestStorageGrowsWithoutBound`: 300 registrations in a row, and nothing
  stops any of them. The count is kept modest so the suite stays fast; the
  code contains no limit at any size.
- `TestOversizedEntryAccepted`: a single 100,000 character entry is stored
  without complaint. There is no per-entry size limit either.
- `TestRender`: the realm renders a summary page.

## What the fix would be

Cap the total entry count, cap the size of each entry, add a per-user quota
or a fee, deduplicate entries, and restrict who may register.

## Deploy notes

No dependencies. Deploy any time. The `dunoil` namespace is a placeholder
for local development; the Onyx deploy phase may swap it for the deployer
`g1` address.
