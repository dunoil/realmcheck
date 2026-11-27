# RealmCheck: Onyx Testnet (onyx-1) Environment Verification

Verified live: 27 Nov 2026, about 13:15 to 13:35 WITA (05:15 to 05:35 UTC).
Method: curl from this VM plus official docs pages fetched as text and web search.
Scope: read-only checks only. No keys created, no faucet funds requested, no deploys, no money spent.

## 1. Headline correction: the old testnet hostnames are dead

The hostnames in the original task brief (`rpc.testnet.gno.land`, `faucet.testnet.gno.land`, `testnet.gno.land`) are legacy pre-Onyx hostnames and do NOT answer from this VM. The current Onyx scheme is `*.onyx.testnets.gno.land`. Every current endpoint below was verified live. Use the current hostnames in all commands, not the old ones.

## 2. Endpoint status

| Endpoint | URL | Status | Sample / notes |
|---|---|---|---|
| Onyx RPC | https://rpc.onyx.testnets.gno.land | HTTP 200 | `/status` returns JSON-RPC: `"network": "onyx-1"`, `"latest_block_height": "1443524"`, `"latest_block_time": "2026-11-27T05:16:07.218320385Z"`, `"catching_up": false`, `"build_version": "v1.8.0-rc.1"`, moniker `gno-core-rpc-public-i-0525e287d7d4e058d`, `"tx_index": "off"`. Root `/` returns a 1,295 byte JSON-RPC style body. |
| Onyx RPC, latest alias | https://rpc.latest.testnets.gno.land:443 | HTTP 200 | `/status` returns the same result as the Onyx RPC (same height 1443524). Per docs, this alias always points at the current testnet, today Onyx (`onyx-1`). |
| Onyx gnoweb | https://onyx.testnets.gno.land | HTTP 200 | 72,664 bytes. Title: `Welcome to Gno.land`. Page shows `onyx-1` and `onyx.testnets.gno.land`. Live realm browser for Onyx. |
| Onyx faucet (web) | https://onyx.testnets.gno.land/faucet | HTTP 302 | Redirects to https://faucet.gno.land (Faucet Hub). Cloudflare fronted. |
| Faucet Hub | https://faucet.gno.land | HTTP 200 | 1,668 bytes, JS single page app titled `Gno Faucet Hub`. The hub page loads the Google reCAPTCHA script. The Onyx faucet entry inside the hub bundle uses hCaptcha (see section 4). |
| Faucet API | https://faucet.onyx.testnets.gno.land | HTTP 405 on GET | Expected: this is a POST-only JSON-RPC service (`drip` method). GET correctly returns 405. Do not treat the 405 as down. |
| Onyx tx-indexer GraphQL | https://indexer.onyx.testnets.gno.land/graphql/query | HTTP 200 | POST `{"query":"{ latestBlockHeight }"}` returned `{"data":{"latestBlockHeight":1443627}}` in 0.8s. A GET with no operation returns HTTP 422 with `{"errors":[{"message":"no operation provided","extensions":{"code":"GRAPHQL_VALIDATION_FAILED"}}]}`, which itself proves a live GraphQL server. Note: one earlier POST timed out at a 20s limit and succeeded on retry, so allow a generous timeout or retry once on first contact. The `/graphql/query` suffix is required, not optional. |
| Gnockpit (chain dashboard) | https://gnockpit.onyx.testnets.gno.land | HTTP 200 | 317,081 bytes, HTML app titled `gnockpit`. Shows chain state, blocks, validators, peers. |
| GnoScan testnet | https://testnet.gnoscan.io | NOT reachable from this VM | curl returns HTTP 000, empty reply after a successful TLS handshake, same failure pattern as the legacy hostnames. Main explorer https://gnoscan.io returns HTTP 200. Needs a re-check from another network or a live browser before it is declared down. |
| Legacy RPC | https://rpc.testnet.gno.land | NOT reachable from this VM | HTTP 000, empty reply after TLS handshake. DNS resolves to 198.18.200.160. Do not use. |
| Legacy faucet | https://faucet.testnet.gno.land | NOT reachable from this VM | HTTP 000, empty reply after TLS handshake. DNS resolves to 198.18.200.161. Do not use. |
| Legacy gnoweb | https://testnet.gno.land | NOT reachable from this VM | HTTP 000, empty reply after TLS handshake. DNS resolves to 198.18.200.162. Do not use. |
| Docs | https://docs.gno.land | HTTP 200 | Docusaurus site, live. All command pages below fetched from it. |

Note on the failures: TLS handshakes to the dead hosts complete, then the server closes with an empty reply. DNS resolves (198.18.200.160-164 range). This looks like those hosts no longer serve anything on this network path, not a DNS problem. The same 198.18.200.x range also serves `testnet.gnoscan.io` (198.18.200.163) and `indexer.testnet.gno.land` (198.18.200.164), so treat any `*.testnet.gno.land` or `testnet.gnoscan.io` result from this VM with caution and re-verify elsewhere.

## 3. Chain ID and remote (the values to use in every command)

- Chain ID: `onyx-1`
- RPC remote: `https://rpc.onyx.testnets.gno.land:443`
- Latest alias remote (always the current testnet): `https://rpc.latest.testnets.gno.land:443`
- WebSocket: `wss://rpc.onyx.testnets.gno.land/websocket` (same request-response methods as HTTP, no event subscription)
- Seeds: `seed-1.onyx.testnets.gno.land`, `seed-2.onyx.testnets.gno.land`
- gnoweb: `https://onyx.testnets.gno.land`
- Onyx launched 28 Sep 2026 00:00 UTC, launch version v1.5.0, release tag `chain/onyx`, genesis sha256 `4b006fd7ccdec052865accc84dd29b2b76f8b57b2560789a15eedaa88f0e26c5`. It runs mainnet code one release candidate ahead and is upgraded whenever mainnet is.
- Mainnet for contrast: chain ID `gnoland-1`, remote `https://rpc.gno.land:443`, no faucet.
- The docs examples use the `latest` remote with a `<chain-id>` placeholder. For Onyx, substitute `onyx-1` and either remote above. Keep the faucet network choice, `-chainid`, and `-remote` consistent.

## 4. Faucet: exact flow, amounts, limits, captcha

Flow (per docs Quick Start and Getting Started):

1. Create a key first (section 5) and copy its `g1...` address (`gnokey list`).
2. Go to https://faucet.gno.land (the Faucet Hub). The Onyx faucet web path https://onyx.testnets.gno.land/faucet redirects here.
3. Paste the `g1...` address, pick the current testnet (Onyx) from the network dropdown, pick an amount, complete the captcha, submit.
4. Tokens arrive in seconds. Confirm with: `gnokey query bank/balances/<your-g1-addr> -remote https://rpc.latest.testnets.gno.land:443`

Amounts (verified in the live Faucet Hub JS bundle, `faucet.gno.land/assets/index-DalgKuER.js`, Onyx Faucet entry):

- Selectable per request: 100, 200, or 300 GNOT (`amounts:[100,200,300]`, `chain_id:"onyx-1"`, `url:"https://faucet.onyx.testnets.gno.land"`).
- 1 GNOT = 1,000,000 ugnot. The API converts with `convertToUgnot`, amount in GNOT times 1e6, and calls JSON-RPC method `drip` with params `[address, amount]`.
- Docs say: faucet is rate-limited per address, and one request is enough for the Quick Start. Exact cooldown length is NOT published in the docs pages read or in the hub JS bundle I inspected, so do not quote a number. If a re-request is rejected, wait out the cooldown.
- Captcha: the Onyx faucet entry in the hub bundle carries an hCaptcha site key (`85609fa2-6ed6-4fe0-904c-2bae865ab6ec`). The hub page itself also loads the Google reCAPTCHA script. Expect a captcha challenge in the browser flow; the API drip call takes a `captchaSecret` parameter.
- The faucet API host `https://faucet.onyx.testnets.gno.land` is POST-only JSON-RPC. A GET returns HTTP 405, which is normal for this service.
- Deploys cost gas plus a storage deposit, both paid in ugnot, so fund the key before deploying.

## 5. Keys: exact commands

Install the toolchain (docs Quick Start):

```bash
curl -fsSL https://raw.githubusercontent.com/gnolang/gno/master/misc/install.sh | sh
```

This installs `gno`, `gnokey`, and `gnodev`. Docker, source build, or a pinned version are covered in the docs install page.

Create a key (docs: Interacting with Gno.land using gnokey, and Getting Started):

```bash
gnokey add mykey
```

- `gnokey` asks for a password to encrypt the keypair to disk, then shows the public key, the derived `g1...` address, and a randomly generated 12-word mnemonic. Safeguard the mnemonic. It is the master password for the keypair, and if it is lost it is unrecoverable.
- Keys created this way are development-only. Do not reuse the mnemonic for real funds.
- List keys and copy the address:

```bash
gnokey list
```

- Recover an existing key from a mnemonic (per the Hazen Onyx setup guide, same `gnokey add` family):

```bash
gnokey add wallet --recover
```

- Check a key version: `gnokey version`
- The local keybase directory is controlled by the `-home` flag on `gnokey`.

## 6. Deploy a realm or package to Onyx: exact commands

Prepare the package (docs Quick Start, counter example):

```bash
mkdir counter && cd counter
gno mod init gno.land/r/myname/counter
```

The `gnomod.toml` module path must match the `-pkgpath` used at deploy. For a realm, the path pattern is `gno.land/r/<namespace>/<name>`, where the namespace is either a registered name or your own `g1...` address (no registration needed for your own address). For a pure package, `gno.land/p/<namespace>/<name>`.

Deploy (docs Quick Start, with Onyx values substituted):

```bash
gnokey maketx addpkg \
  -pkgpath "gno.land/r/<your-g1-addr>/counter" -pkgdir . \
  -gas-fee 5000ugnot -gas-wanted 5000000 \
  -chainid onyx-1 -remote https://rpc.onyx.testnets.gno.land:443 dev
```

Notes:

- In the docs the last argument is the key name (`dev` in the Quick Start, `alice` in Getting Started, `mykey` in the gnokey guide). Use your own key name.
- `addpkg` flags: `-pkgpath` (on-chain path), `-pkgdir` (local directory to upload), `-broadcast` (default true), `-send` (optional GNOT to send to the realm with the tx), `-max-deposit` (optional maximum GNOT to lock for storage deposit), `-gas-wanted` (gas upper limit), `-gas-fee` (flat fee in ugnot), `-chainid`, `-remote`.
- The equivalent with the `latest` alias remote is `-chainid onyx-1 -remote https://rpc.latest.testnets.gno.land:443`.
- The testnet enables a new package a few seconds after `addpkg`. If the first call fails, wait and retry. A refused package reason is at https://gpas.latest.testnets.gno.land (look up the exact package path). If it still says the package is not known after a minute, ask on Discord at https://discord.com/invite/gnoland.
- The deployed realm is viewable live at `https://latest.testnets.gno.land/r/<your-g1-addr>/counter` (and at `https://onyx.testnets.gno.land/r/<your-g1-addr>/counter`).

## 7. Call a realm function and read realm state: exact commands

Call a state-changing function (docs Quick Start, Onyx values substituted):

```bash
gnokey maketx call \
  -pkgpath "gno.land/r/<your-g1-addr>/counter" \
  -func "Increment" \
  -gas-fee 2000ugnot -gas-wanted 2000000 \
  -chainid onyx-1 -remote https://rpc.latest.testnets.gno.land:443 dev
```

Call with arguments and with coins attached (docs gnokey guide, wugnot `Deposit` example):

```bash
gnokey maketx call \
  -pkgpath "gno.land/r/gnoland/wugnot" \
  -func "Deposit" \
  -send "1000ugnot" \
  -gas-fee 8000ugnot \
  -gas-wanted 8000000 \
  -chainid onyx-1 \
  -remote "https://rpc.latest.testnets.gno.land:443" \
  mykey
```

Expected success output shape (from the docs, values vary on testnet):

```text
OK!
GAS WANTED: 8000000
GAS USED:   6975797
HEIGHT:     2
STORAGE DELTA:  1043 bytes
STORAGE FEE:    104300ugnot
TOTAL TX COST:  112300ugnot
```

- Pass one `-args` flag per argument. For variadic functions, one `-args` flag per variadic element.
- `maketx call` refuses read-only (non-crossing) functions with `function <Name> is non-crossing and cannot be called with MsgCall; query with vm/qeval or use MsgRun`. Use a query instead, which costs no gas.

Read state, read-only queries (no gas, no key needed):

```bash
# Evaluate an expression against a realm (read-only)
gnokey query vm/qeval \
  -data "gno.land/r/gnoland/wugnot.BalanceOf(\"<your_address>\")" \
  -remote "https://rpc.latest.testnets.gno.land:443"

# Render a realm (shorthand for vm/qeval Render(""))
gnokey query vm/qrender -remote "https://rpc.latest.testnets.gno.land:443" gno.land/r/<your-g1-addr>/counter

# Balance of an address
gnokey query bank/balances/<your-g1-addr> -remote https://rpc.latest.testnets.gno.land:443

# Account info (number and sequence, needed for offline signing)
gnokey query auth/accounts/<your_address> -remote "https://rpc.latest.testnets.gno.land:443"
```

Other useful query paths: `vm/qfuncs` (exported functions for a pkgpath), `vm/qfile` (package contents), `vm/qdoc` (package docs as JSON), `vm/qpaths` (all package paths), `vm/qstorage` (storage usage and deposit locked in a realm), `bank/supply/ugnot` (total supply). JSON-structured variants exist: `vm/qeval_json`, `vm/qpkg_json`, `vm/qobject_json`, `vm/qtype_json` (see docs page Querying On-Chain State (JSON APIs)).

Send coins (docs gnokey guide):

```bash
gnokey maketx send \
  -to g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5 \
  -send 100ugnot \
  -gas-fee 2000ugnot \
  -gas-wanted 2000000 \
  -chainid onyx-1 \
  -remote "https://rpc.latest.testnets.gno.land:443" \
  mykey
```

## 8. DoraHacks Gnome Tavern re-check

- Direct page check FAILED for a technical reason, not a content reason: https://dorahacks.io/hackathon/gnome-tavern/detail returns HTTP 405 to curl and to the page fetcher. DoraHacks blocks non-browser fetches. The live page could not be read from this VM. A live browser check is still needed for exact on-page prize breakdown and counts.
- Corroborated from other sources, 27 Nov 2026:
  - Prize pool is now $40,000 in GNOT, not the original $20,000. Source: @_gnoland post (via TopKOLs): "We've added $20,000 to the Gnome Tavern Hackathon prize pool, bringing the total to $40,000. Ship something real on Gno.land, keep building, and get paid in GNOT. Submissions are open until Dec 18." Hackathon Radar also lists the event as $40K, Nov 24 to Dec 18, 2026, ongoing.
  - Deadline still 18 Dec 2026. Sources: the same @_gnoland post (Dec 18), Eventbrite listing (23 Nov 2026 16:00 PST to 18 Dec 2026 09:00 PST), Hack123 (submissions 23 Nov to 18 Dec 2026, 01:00 UTC). Safe interpretation: submit by 18 Dec 2026 01:00 UTC.
  - Original prize structure (for the first $20,000, per Hack123 and AlphaGrowth, which still show the stale $20,000 total): $10,000 upfront across 16 projects (1st $2,000, 2nd $1,000, 14 Builder Awards of $500) plus up to $10,000 in Builder Retention Prizes paid at 3 and 6 months for winners who keep shipping. How the added $20,000 is split is NOT confirmed in the sources I could read. Verify on the live DoraHacks page.
  - Build / hacker counts: NOT verifiable from this VM. No BUIDL count or hacker count appeared in any search result, and the DoraHacks page itself (where those counts live) returns 405 to fetchers. Open question, needs a live browser check.
- Registration: Duan already registered solo as @dunoil on 27 Nov 2026 (per project memory). This check did not re-verify registration.

## 9. Blockers and open questions

1. GnoScan testnet (https://testnet.gnoscan.io) is unreachable from this VM (HTTP 000, empty reply after TLS). Unknown whether it is down or only blocked on this network path. Re-check from another network or a live browser. Fallback explorers until then: gnoweb (https://onyx.testnets.gno.land), Gnockpit, and the tx-indexer GraphQL endpoint.
2. Legacy `*.testnet.gno.land` hostnames are dead from this VM. If any project doc or script still uses them, update to `*.onyx.testnets.gno.land`.
3. Faucet exact cooldown per address is unpublished in the docs and hub bundle I read. Only "rate-limited per address, one request is enough" is documented. Do not assume a number; test with one 100 GNOT request first when funding the build key (human step, not done here).
4. How the added $20,000 of the now $40,000 prize pool is split is unconfirmed. Verify on the live DoraHacks page.
5. DoraHacks BUIDL and hacker counts are unverified (page returns 405 to fetchers). Needs a live browser check.
6. First tx-indexer POST timed out at 20s and succeeded on retry in 0.8s. Treat the indexer as live but allow a retry and a longer timeout on first contact.
7. Onyx runs mainnet code one release candidate ahead and upgrades with mainnet. The build version seen live is v1.8.0-rc.1, newer than the v1.5.0 launch version in the announcement post. Pin or re-check the toolchain version before deploying, since the chain moves with mainnet releases.

## 10. Sources

- https://docs.gno.land/resources/gnoland-networks/
- https://docs.gno.land/builders/quickstart/
- https://docs.gno.land/builders/getting-started/
- https://docs.gno.land/users/interact-with-gnokey/
- https://gno.land/r/gnoland/blog:p/onyx-1 (Onyx launch announcement)
- https://faucet.gno.land (Faucet Hub, JS bundle inspected for amounts and captcha)
- https://guides.hazennetworksolutions.com/gnoland/ (Onyx setup guide, endpoint table and `gnokey add wallet --recover`)
- https://guides.hazennetworksolutions.com/gnoland-ai/ (official tx-indexer URL `https://indexer.onyx.testnets.gno.land/graphql/query`)
- https://dorahacks.io/hackathon/gnome-tavern/detail (returns HTTP 405 to fetchers, not read)
- https://topkols.com/kol/_gnoland (prize pool raised to $40,000)
- https://www.hackathonradar.com/discover/new ($40K listing)
- https://www.eventbrite.com/e/gnome-tavern-hackathon-gnoland-tickets-2005249519292 (dates 23 Nov to 18 Dec 2026)
- https://hack123.henryht.sh/en/h/gnome-tavern-hackathon-gnoland-2026 (stale $20,000, deadline 18 Dec 2026 01:00 UTC)

## 11. Bottom line for the build

- Chain ID `onyx-1`, remote `https://rpc.onyx.testnets.gno.land:443` (or the `latest` alias). RPC, gnoweb, faucet hub, tx-indexer, and Gnockpit are all live as of 27 Nov 2026 05:16 UTC, block height 1443524 and rising.
- Fund the build key at https://faucet.gno.land, 100 to 300 GNOT per request, captcha required, rate-limited per address.
- Deploy with `gnokey maketx addpkg`, call with `gnokey maketx call`, read state with `gnokey query vm/qeval` or `vm/qrender`.
- Do not use any `*.testnet.gno.land` hostname. Do not rely on GnoScan testnet until it is re-verified from another network.
