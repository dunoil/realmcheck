// Command txbin converts a signed Amino JSON transaction document (the
// format gnokey sign writes) into the binary Amino bytes gnokey's own
// broadcast path sends to the node.
//
// It does exactly what gnokey's BroadcastHandler does in
// tm2/pkg/crypto/keys/client/broadcast.go, minus the network call:
//
//	var tx std.Tx
//	amino.UnmarshalJSON(jsonbz, &tx)   // execBroadcast, same call
//	bz, err := amino.Marshal(tx)       // BroadcastHandler, same call
//
// The blank imports register the message types that can appear in a tx
// (vm MsgAddPackage/MsgCall/MsgRun, bank MsgSend) with the global Amino
// codec, the same registration gnokey gets by importing keyscli. Without
// them UnmarshalJSON cannot decode the concrete message inside the tx.
//
// Usage:
//
//	txbin <signed-tx.json> [output-file]
//
// With no output file the base64-encoded binary bytes go to stdout, ready
// for the Tendermint RPC broadcast_tx_commit / broadcast_tx_sync `tx`
// parameter. With an output file the raw binary bytes are written there
// and the base64 form is still printed on stdout for logging.
package main

import (
	"encoding/base64"
	"fmt"
	"os"

	"github.com/gnolang/gno/tm2/pkg/amino"
	"github.com/gnolang/gno/tm2/pkg/std"

	_ "github.com/gnolang/gno/gno.land/pkg/sdk/vm"
	_ "github.com/gnolang/gno/tm2/pkg/sdk/bank"
)

func main() {
	if len(os.Args) < 2 || len(os.Args) > 3 {
		fmt.Fprintln(os.Stderr, "usage: txbin <signed-tx.json> [output-file]")
		os.Exit(2)
	}

	jsonbz, err := os.ReadFile(os.Args[1])
	if err != nil {
		fmt.Fprintf(os.Stderr, "txbin: reading tx document %s: %v\n", os.Args[1], err)
		os.Exit(1)
	}
	if len(jsonbz) == 0 {
		fmt.Fprintln(os.Stderr, "txbin: empty tx document")
		os.Exit(1)
	}

	var tx std.Tx
	if err := amino.UnmarshalJSON(jsonbz, &tx); err != nil {
		fmt.Fprintf(os.Stderr, "txbin: unmarshaling tx json bytes: %v\n", err)
		os.Exit(1)
	}

	bz, err := amino.Marshal(tx)
	if err != nil {
		fmt.Fprintf(os.Stderr, "txbin: remarshaling tx binary bytes: %v\n", err)
		os.Exit(1)
	}

	if len(os.Args) == 3 {
		if err := os.WriteFile(os.Args[2], bz, 0o644); err != nil {
			fmt.Fprintf(os.Stderr, "txbin: writing binary tx to %s: %v\n", os.Args[2], err)
			os.Exit(1)
		}
	}

	fmt.Println(base64.StdEncoding.EncodeToString(bz))
}
