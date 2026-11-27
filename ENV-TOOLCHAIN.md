# RealmCheck Environment Toolchain, Phase 1 Verification

Date verified: 27 Nov 2026, 13:26 WITA (05:26 UTC).
Project: Gnome Tavern Hackathon, RealmCheck on Gno.land.
Status: COMPLETE. All four binaries build and run (gno CLI added in phase 2, see the gno row below). No money spent, no repo created, no deployment made, no faucet funds requested.

## Exact versions

| Tool | Version | Source |
| --- | --- | --- |
| Go | go1.25.9 linux/amd64 | Official tarball from go.dev, SHA256 verified: 00859d7bd6defe8bf84d9db9e57b9a4467b2887c18cd93ae7460e713db774bc1 |
| Gno | v1.8.0, commit fc79041f4cd1a7b3ed4b316dc5ac14162eb78730, dated 2026-11-17 | Latest stable release tag at clone time, cloned from https://github.com/gnolang/gno.git |
| gnokey | v1.8.0 (`gnokey version` output) | Built from the v1.8.0 source above |
| gnodev | built from v1.8.0, commit fc79041f4cd1a7b3ed4b316dc5ac14162eb78730 | Built from the v1.8.0 source above |
| gnoland | v1.8.0 (`gnoland version` output) | Built from the v1.8.0 source above, stretch goal, also done |
| gno | built from v1.8.0, commit fc79041f (`gno version: develop`) | Built 27 Nov by the phase 2 audit-rules agent with the same low-memory flags and GNOROOT ldflag; the test runner for Gno packages |

Go requirement check: the v1.8.0 `go.mod` says `go 1.25.9`, and the installed Go is exactly 1.25.9, so no toolchain download was needed at build time.

## Install paths

- Go toolchain: `~/workspace/tools/go` (binary `~/workspace/tools/go/bin/go`, 236 MB total)
- Gno source: `~/workspace/tools/gno` (351 MB total, shallow clone, depth 1, tag v1.8.0)
- Built binaries: `~/workspace/tools/gno/bin/` (197 MB total)
  - `~/workspace/tools/gno/bin/gnokey` (39 MB)
  - `~/workspace/tools/gno/bin/gnodev` (64 MB)
  - `~/workspace/tools/gno/bin/gnoland` (54 MB)
  - `~/workspace/tools/gno/bin/gno` (41 MB, added in phase 2)
- Go module cache and build cache live in the default locations under the home directory (`~/go/pkg/mod`, `~/.cache/go-build`). They are caches only, not part of the toolchain, and can be rebuilt by re-running the builds below.

Nothing was installed under `/usr/local`, so a VM restart will not wipe the toolchain.

## PATH and environment

Add these lines to the shell before use (or to `~/.bashrc` for persistence):

```bash
export PATH=$PATH:$HOME/workspace/tools/go/bin:$HOME/workspace/tools/gno/bin
export GNOROOT=$HOME/workspace/tools/gno
export GOMAXPROCS=2
```

Notes on the environment lines:

- `GNOROOT` is exported as a safety net. All three binaries were also built with GNOROOT embedded via `-ldflags "-X github.com/gnolang/gno/gnovm/pkg/gnoenv._GNOROOT=$HOME/workspace/tools/gno"`, so they work even with GNOROOT unset. See the failure note below for why the embedding matters.
- `GOMAXPROCS=2` keeps Go builds inside the tight RAM budget. See the RAM note below.

## Verification performed

All commands below were run on the VM on 27 Nov 2026 and passed:

- `go version` returns `go version go1.25.9 linux/amd64`.
- `gnokey --help` prints the keychain and client usage, subcommands add, delete, generate, list, sign, verify, query, broadcast, maketx, and others.
- `gnokey version` returns `gnokey version: v1.8.0`.
- `gnodev --help` prints the local and staging mode usage. `gnodev local -h` prints the local mode flags.
- `gnoland --help` prints the start, secrets, config, and version subcommands.
- `gnoland version` returns `gnoland version: v1.8.0`.

## How the builds were done

Builds used low parallelism because RAM is tight (see below). Each build ran with `GOMAXPROCS=2`, `CGO_ENABLED=0`, and `go build -p 1`:

- gnokey: `cd ~/workspace/tools/gno/gno.land && go build -p 1 -trimpath -ldflags "-X github.com/gnolang/gno/tm2/pkg/version.Version=v1.8.0 -X github.com/gnolang/gno/gnovm/pkg/gnoenv._GNOROOT=$HOME/workspace/tools/gno" -o ~/workspace/tools/gno/bin/gnokey ./cmd/gnokey`
- gnodev: `cd ~/workspace/tools/gno/contribs/gnodev && go build -p 1 -trimpath -ldflags "-X github.com/gnolang/gno/gnovm/pkg/gnoenv._GNOROOT=$HOME/workspace/tools/gno" -o ~/workspace/tools/gno/bin/gnodev .`
- gnoland: `cd ~/workspace/tools/gno/gno.land && go build -p 1 -trimpath -ldflags "-X github.com/gnolang/gno/tm2/pkg/version.Version=v1.8.0 -X github.com/gnolang/gno/gnovm/pkg/gnoenv._GNOROOT=$HOME/workspace/tools/gno" -o ~/workspace/tools/gno/bin/gnoland ./cmd/gnoland`

First gnokey build took about 5 minutes, mostly downloading Go modules. Later builds took seconds to about 2.5 minutes because the module cache was warm. No build was OOM killed.

## What worked

- Go 1.25.9 download, SHA256 check, extraction, and `go version` all worked first try.
- Gno v1.8.0 clone worked first try (shallow, depth 1, tag v1.8.0).
- gnokey built and verified.
- gnodev built and verified.
- gnoland, the optional stretch binary, also built and verified, so all three priority levels are done.

## What failed, and how it was fixed

1. gnoland first build panicked on every invocation (`gnoland --help` and `gnoland version` both panicked with `gno was unable to determine GNOROOT. Please set the GNOROOT environment variable`). Cause: the build used `-trimpath`, which disables the caller stack fallback GNOROOT guess, and the `go list` fallback fails when run outside the module directory. Fix: rebuilt gnoland with GNOROOT embedded in the binary via the `-X github.com/gnolang/gno/gnovm/pkg/gnoenv._GNOROOT=...` ldflag, and rebuilt gnokey the same way for consistency. After the rebuild, `gnoland --help` and `gnoland version` work with GNOROOT unset. gnodev never had this problem because its Makefile already embeds GNOROOT at build time.
2. `gnokey --version` is not a valid flag. It prints `flag provided but not defined: -version`. Use `gnokey version` (no dashes) instead. Same for gnoland: use `gnoland version`.
3. gnodev has no `version` subcommand. Running `gnodev version` makes it try to load a package directory named `version` and prints loader warnings. There is no clean version string for gnodev. Identify it by its source commit instead: v1.8.0, fc79041f4cd1a7b3ed4b316dc5ac14162eb78730. `gnodev --help` is the correct smoke test.

Nothing else failed. No OOM kills occurred during any build (0 recorded).

## RAM and disk notes

- RAM at build time: 7.7 GB total, only about 0.9 to 1.7 GB available during builds, swap about 0.5 GB free. Builds were run with `-p 1` and `GOMAXPROCS=2` and survived. Do not run Go builds with default full parallelism on this VM, and do not run a build at the same time as another heavy job.
- Disk: 120 GB free before the work, 120 GB free after (21 percent used). Toolchain plus source plus binaries use about 587 MB total. Disk is not a constraint.

## Next steps and blockers

- No blockers. Phase 1 environment verification is complete.
- Phase 2 can start: use `gnodev local` for the local dev chain and realm tests, and `gnokey` for key management and transactions.
- Before any testnet deployment, a key must be created with `gnokey add` and testnet funds obtained through the hackathon faucet. Neither step was done in this phase, by design.
- The Gno checkout is a shallow clone (depth 1, tag v1.8.0 only). If full git history is ever needed, run `git fetch --unshallow` inside `~/workspace/tools/gno`.
- If the VM restarts, re-export the PATH lines above. The toolchain itself survives because it lives under `~/workspace`.
