# txbin: signed Amino JSON tx to binary Amino bytes

`gnokey broadcast` does two things: it reads a signed Amino JSON tx
document, unmarshals it into a `std.Tx`, marshals that tx to binary Amino
bytes, and posts those bytes to the node's `broadcast_tx_commit` RPC. The
posting half needs gnokey's own RPC client, which cannot reach Onyx from a
machine behind an egress proxy. This helper does only the conversion half,
so the broadcast itself can go through `curl` instead.

```bash
go build -o txbin .
./txbin <signed-tx.json> [output-file]
```

With no output file the base64-encoded binary bytes go to stdout, ready
for the Tendermint RPC `broadcast_tx_commit` `tx` parameter. With an
output file the raw binary bytes are written there and the base64 form is
still printed on stdout.

The build uses the local Gno source tree through the `replace` directive
in `go.mod` (`github.com/gnolang/gno => ../../../tools/gno`), so it
always matches the installed `gnokey` version. The blank imports of
`gno.land/pkg/sdk/vm` and `tm2/pkg/sdk/bank` register the message types
(`MsgAddPackage`, `MsgCall`, `MsgRun`, `MsgSend`) with the global Amino
codec, the same registration `gnokey` gets by importing `keyscli`;
without them the JSON unmarshal cannot decode the concrete message
inside the tx.

The `txbin` binary itself is gitignored; build it when needed
(`scripts/offline-sign-deploy.sh` builds it automatically when it is
missing or stale).
