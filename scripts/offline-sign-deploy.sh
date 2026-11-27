#!/usr/bin/env bash
# offline-sign-deploy.sh: deploy RealmCheck to Onyx (or a local chain)
# WITHOUT gnokey ever touching the network.
#
# Why this script exists: gnokey builds its own HTTP client with no proxy
# support, so from a machine behind an egress proxy it cannot reach the
# Onyx RPC at all (TLS handshake failure, verified 27 Nov 2026; see
# docs/ONYX-DEPLOY.md section 5). curl and node reach the RPC fine through
# the proxy. This script therefore splits every transaction into three
# steps, of which only the last one needs the network, and that step is
# plain curl:
#
#   1. gnokey maketx <sub> -broadcast=false ...   (offline, prints the
#      unsigned Amino JSON tx document to stdout; no chain contact, no
#      account query, no password)
#   2. curl abci_query auth/accounts/<addr>       (proxy-aware, gives the
#      account number and sequence the signature must commit to)
#   3. gnokey sign -tx-path <doc> -account-number N -account-sequence S
#      -chainid <id> <key>                         (offline, signs the doc
#      in place; password from a file on stdin, never printed)
#   4. scripts/txbin/txbin <signed-doc>          (offline, converts the
#      signed Amino JSON doc to binary Amino bytes, exactly the way
#      gnokey's own BroadcastHandler does: amino.UnmarshalJSON into a
#      std.Tx, then amino.Marshal; see scripts/txbin/main.go)
#   5. curl POST <rpc>/ broadcast_tx_commit with {"tx": "<base64 bytes>"}
#      (proxy-aware JSON-RPC; the node decodes, checks, and commits)
#
# The rest of the script mirrors scripts/deploy-onyx.sh exactly: the same
# staging and namespace swap, the same deploy order, the same gas
# settings, the same 20 GNOT funding gate, and the same verification
# (abci_query vm/qfile listing plus a byte diff of every staged .gno file
# against the on-chain copy, then the test SubmitReport with the same
# ground-truth checks).
#
# Modes (exactly one; default is the real Onyx deploy):
#   --check   Dry run. Stages the packages, applies and verifies the
#             namespace swap, prints every command that would run, and
#             exits. No chain contact, no transaction, no key needed.
#   --local   Full deploy against a fresh local gnodev chain, funded for
#             the Onyx deployer key (realmcheck-onyx,
#             g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu). Proves the whole
#             offline-sign path, including the real key and its password
#             file, end to end. The chain is started and stopped by this
#             run. No faucet, no Onyx.
#   (none)    Real Onyx deploy. Refuses to run without a funded key: the
#             key must exist in gnokey list and hold at least 20 GNOT.
#
# Onyx usage:
#   bash scripts/offline-sign-deploy.sh --key realmcheck-onyx --deployer g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu
#
# Local validation usage:
#   bash scripts/offline-sign-deploy.sh --local
#   bash scripts/offline-sign-deploy.sh --check
#
# The key password is read from --password-file (default
# $PROJECT/.gnokey/password.txt) and fed to `gnokey sign` on stdin. It is
# never printed, logged, or passed on a command line. When the file does
# not exist, gnokey sign prompts interactively instead.
#
# Full output is also written to scripts/offline-work/run-<mode>-<time>.log.
# Exit code 0 means every deploy and verification step passed.

set -u

# Save the original arguments: the parser below consumes $@, and the
# self-tee block re-invokes this script with them.
ORIG_ARGS=("$@")

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$PROJECT/scripts/offline-work"
STAGE="$WORK/stage"
CHAIN_DIR="$WORK/chain"
TXBIN_DIR="$PROJECT/scripts/txbin"
TXBIN="$TXBIN_DIR/txbin"

# --- Defaults (overridden by flags) -----------------------------------------
MODE="onyx"
KEY_NAME="realmcheck-onyx"
DEPLOYER="g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu"
RPC="https://rpc.onyx.testnets.gno.land:443"
CHAINID="onyx-1"
WEB="https://onyx.testnets.gno.land"
GNOKEY_HOME="$PROJECT/.gnokey"
PASS_FILE="$PROJECT/.gnokey/password.txt"

# Local mode values (gnodev local chain, same Onyx key, funded locally).
LOCAL_RPC_PORT=26660
LOCAL_WEB_PORT=8891

ADD_PKG_GAS_WANTED=70000000
ADD_PKG_GAS_FEE=140000
MIN_BALANCE_UGNOT=20000000
# 20 GNOT. Measured total for the whole deploy on a local chain is
# 12,050,000ugnot (7 addpkg transactions at 11,749,300ugnot plus the
# test SubmitReport at 300,700ugnot), so 20 GNOT leaves margin for
# Onyx-side differences. One faucet request (100 GNOT) covers it.

FAILURES=0
GNODEV_PID=""

usage() {
  cat <<EOF
Usage:
  bash scripts/offline-sign-deploy.sh --key <key-name> --deployer <g1-address> [--rpc <url>] [--chainid <id>]
  bash scripts/offline-sign-deploy.sh --local
  bash scripts/offline-sign-deploy.sh --check [--deployer <g1-address>]
Options:
  --key NAME        gnokey key name that signs the deploy (default: realmcheck-onyx)
  --deployer ADDR   deployer g1 address; becomes the namespace in every module path (default: $DEPLOYER)
  --rpc URL         RPC remote (default: $RPC)
  --chainid ID      chain id (default: $CHAINID)
  --home DIR        gnokey home holding the key (default: \$PROJECT/.gnokey)
  --password-file F file holding the key password, fed to gnokey sign on stdin (default: \$PROJECT/.gnokey/password.txt)
  --local           deploy everything against a fresh local gnodev chain instead of Onyx
  --check           dry run only: stage, swap, verify, print the plan, exit
  --help            show this text
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --key) KEY_NAME="$2"; shift 2 ;;
    --deployer) DEPLOYER="$2"; shift 2 ;;
    --rpc) RPC="$2"; shift 2 ;;
    --chainid) CHAINID="$2"; shift 2 ;;
    --home) GNOKEY_HOME="$2"; shift 2 ;;
    --password-file) PASS_FILE="$2"; shift 2 ;;
    --local) MODE="local"; shift ;;
    --check) MODE="check"; shift ;;
    --help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# Self-tee: on the outer invocation, re-run inner with output teed to the log.
if [ -z "${DEPLOY_INNER:-}" ]; then
  mkdir -p "$WORK"
  LOG="$WORK/run-$MODE-$(date +%Y%m%d-%H%M%S).log"
  echo "Logging to $LOG"
  DEPLOY_INNER=1 "$0" "${ORIG_ARGS[@]}" 2>&1 | tee "$LOG"
  exit "${PIPESTATUS[0]}"
fi

export PATH="$PATH:$HOME/workspace/tools/go/bin:$HOME/workspace/tools/gno/bin"
export GNOROOT="$HOME/workspace/tools/gno"
export GOMAXPROCS=2

note_pass() { echo "PASS $1"; }
note_fail() { echo "FAIL $1"; FAILURES=$((FAILURES + 1)); }
note_info() { echo "INFO $1"; }

cleanup() {
  if [ -n "${GNODEV_PID:-}" ] && kill -0 "$GNODEV_PID" 2>/dev/null; then
    kill "$GNODEV_PID" 2>/dev/null || true
    wait "$GNODEV_PID" 2>/dev/null || true
    note_info "Stopped local gnodev (pid $GNODEV_PID)."
  fi
}
trap cleanup EXIT

wait_http() { # wait_http <url> <seconds> <label>
  local url="$1" seconds="$2" label="$3" i=0
  while [ "$i" -lt "$seconds" ]; do
    if curl -s -o /dev/null -m 3 "$url" 2>/dev/null; then
      note_pass "$label is up ($url)."
      return 0
    fi
    sleep 1
    i=$((i + 1))
  done
  note_fail "$label did not come up within ${seconds}s ($url)."
  return 1
}

echo "=== RealmCheck offline-sign deploy ==="
echo "Project: $PROJECT"
echo "Mode: $MODE"
echo "Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
for bin in gno gnokey gnodev node curl; do
  command -v "$bin" >/dev/null 2>&1 || note_fail "Required tool missing from PATH: $bin"
done
[ "$FAILURES" -gt 0 ] && { echo "RESULT: FAILED (missing tools)"; exit 1; }
note_pass "Toolchain present: $(gno version 2>/dev/null | head -1), $(gnokey version 2>/dev/null | head -1)."

# --- Mode setup ---------------------------------------------------------------
if [ "$MODE" = "local" ]; then
  RPC="http://127.0.0.1:$LOCAL_RPC_PORT"
  WEB="http://127.0.0.1:$LOCAL_WEB_PORT"
  CHAINID="dev"
elif [ "$MODE" = "check" ]; then
  DEPLOYER="${DEPLOYER:-g1EXAMPLEDEPLOYERADDRESSXXXXXXXXXXXXXXXXXXXX}"
  KEY_NAME="${KEY_NAME:-<key-name>}"
elif [ "$MODE" = "onyx" ]; then
  [ -n "$KEY_NAME" ] || { echo "FAIL Onyx mode needs --key <key-name>."; usage; exit 1; }
  [ -n "$DEPLOYER" ] || { echo "FAIL Onyx mode needs --deployer <g1-address>."; usage; exit 1; }
  case "$DEPLOYER" in
    g1*) ;;
    *) echo "FAIL --deployer must be a g1 address, got: $DEPLOYER"; exit 1 ;;
  esac
fi

# Packages in deploy order. Format: name|kind|source-dir (kind p or r).
# auditrules first (realmcheck imports it), vulnmint before adminbackdoor
# (adminbackdoor imports vulnmint), adminbackdoor last.
PACKAGES="auditrules|p|contracts/auditrules
realmcheck|r|contracts/realmcheck
vulnmint|r|contracts/demo/vulnmint
greedystore|r|contracts/demo/greedystore
luckydice|r|contracts/demo/luckydice
unguardedvault|r|contracts/demo/unguardedvault
adminbackdoor|r|contracts/demo/adminbackdoor"

pkgpath_of() { # pkgpath_of <name> <kind>
  echo "gno.land/$2/$DEPLOYER/$1"
}

# --- Step 1: stage and swap ---------------------------------------------------
echo "--- Staging packages with the namespace swap to $DEPLOYER ---"
rm -rf "$STAGE"
mkdir -p "$STAGE"
while IFS='|' read -r name kind srcdir; do
  [ -n "$name" ] || continue
  mkdir -p "$STAGE/$name"
  # Stage only the deployable files: non-test .gno sources and gnomod.toml.
  # Test files are local only and never deploy.
  for f in "$PROJECT/$srcdir"/*.gno; do
    case "$f" in *_test.gno) continue ;; esac
    cp "$f" "$STAGE/$name/"
  done
  cp "$PROJECT/$srcdir/gnomod.toml" "$STAGE/$name/"
  # Namespace swap. Module path in gnomod.toml, every dunoil path in the
  # sources, and the placeholder Admin address in adminbackdoor.
  sed -i "s|dunoil|$DEPLOYER|g" "$STAGE/$name/gnomod.toml"
  sed -i \
    -e "s|gno.land/p/dunoil/|gno.land/p/$DEPLOYER/|g" \
    -e "s|gno.land/r/dunoil/|gno.land/r/$DEPLOYER/|g" \
    -e "s|address(\"g1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq\")|address(\"$DEPLOYER\")|g" \
    "$STAGE/$name"/*.gno
  note_pass "Staged $name (pkgpath $(pkgpath_of "$name" "$kind"))."
done <<EOF
$PACKAGES
EOF

# Swap verification: no `dunoil` and no placeholder Admin address may
# survive in the staged copies, and every line that differs from the
# original must be a swap line (it mentions the deployer or dunoil).
if grep -r "dunoil" "$STAGE" >/dev/null 2>&1; then
  note_fail "Staged copies still contain 'dunoil':"
  grep -rn "dunoil" "$STAGE" | sed 's/^/    /'
fi
if grep -r "g1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq" "$STAGE" >/dev/null 2>&1; then
  note_fail "Staged copies still contain the placeholder Admin address."
fi
while IFS='|' read -r name kind srcdir; do
  [ -n "$name" ] || continue
  for f in "$STAGE/$name"/*.gno; do
    base="$(basename "$f")"
    orig="$PROJECT/$srcdir/$base"
    # Every changed line must be a swap line: a removed line mentions
    # dunoil or the placeholder Admin address, an added line mentions
    # the deployer address.
    bad="$(diff "$orig" "$f" 2>/dev/null | grep '^[<>]' | grep -v "$DEPLOYER" | grep -v dunoil | grep -v "g1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq" || true)"
    [ -n "$bad" ] && { note_fail "Unexpected diff in staged $name/$base (not a namespace swap):"; echo "$bad" | sed 's/^/    /'; }
  done
  diff_out="$(diff "$PROJECT/$srcdir/gnomod.toml" "$STAGE/$name/gnomod.toml" 2>/dev/null | grep '^[<>]' || true)"
  echo "$diff_out" | grep -q "$DEPLOYER" || note_fail "gnomod.toml for $name does not carry the deployer namespace."
done <<EOF
$PACKAGES
EOF
[ "$FAILURES" -gt 0 ] && { echo "RESULT: FAILED (staging or swap)"; exit 1; }
note_pass "Namespace swap verified: no 'dunoil' and no placeholder Admin address remain in the staged copies."
note_info "Staged module paths:"
grep -h "^module" "$STAGE"/*/gnomod.toml | sed 's/^/  /'

if [ "$MODE" = "check" ]; then
  echo "--- Dry-run plan (no chain contact, nothing deployed) ---"
  while IFS='|' read -r name kind srcdir; do
    [ -n "$name" ] || continue
    echo "addpkg $(pkgpath_of "$name" "$kind") from $STAGE/$name"
    echo "  1. gnokey maketx addpkg -broadcast=false -pkgpath \"$(pkgpath_of "$name" "$kind")\" -pkgdir $STAGE/$name -gas-fee ${ADD_PKG_GAS_FEE}ugnot -gas-wanted $ADD_PKG_GAS_WANTED -chainid $CHAINID -remote $RPC -home $GNOKEY_HOME $KEY_NAME > unsigned-$name.json"
    echo "  2. curl abci_query auth/accounts/$DEPLOYER (account number and sequence)"
    echo "  3. gnokey sign -tx-path unsigned-$name.json -account-number <N> -account-sequence <S> -chainid $CHAINID -home $GNOKEY_HOME -insecure-password-stdin $KEY_NAME < \$PASS_FILE"
    echo "  4. scripts/txbin/txbin unsigned-$name.json unsigned-$name.bin (base64 binary bytes)"
    echo "  5. curl POST $RPC/ broadcast_tx_commit {\"tx\": \"<base64>\"}"
    echo "  verify: abci_query vm/qfile for \"$(pkgpath_of "$name" "$kind")\" (curl, proxy-aware), then diff each staged .gno file against the on-chain copy"
  done <<EOF
$PACKAGES
EOF
  echo "test SubmitReport: same five steps with gnokey maketx call -pkgpath \"$(pkgpath_of realmcheck r)\" -func \"SubmitReport\" -gas-fee 34000ugnot -gas-wanted 17000000"
  echo "verify: ReportCount(), GetReport(1), ReportFindings(1), LatestReport(\"$(pkgpath_of vulnmint r)\"), Render(\"\")"
  echo "Funding gate for Onyx mode: key must hold at least $MIN_BALANCE_UGNOT ugnot (20 GNOT)."
  echo "Faucet when funds are missing: https://faucet.gno.land (see docs/ONYX-DEPLOY.md)."
  echo "RESULT: PASSED (dry-run plan printed, swap verified)"
  exit 0
fi

# --- RPC helpers (curl, proxy-aware) -----------------------------------------
# All chain contact goes through curl, not gnokey: gnokey builds its own
# HTTP client with no proxy support (see docs/ONYX-DEPLOY.md), so from a
# machine behind an egress proxy gnokey cannot reach Onyx at all, while
# curl can. gnokey is used only offline, for maketx and sign.
HTTP_RPC="$RPC"

# rpc_abci <path> <data>: one ABCI query, prints the decoded Data string.
# Returns 1 on HTTP failure, chain error, or an unparsable response.
rpc_abci() {
  local path="$1" data="$2" hex resp
  hex="$(printf '%s' "$data" | od -An -tx1 | tr -d ' \n')"
  resp="$(curl -s -m 20 -G "$HTTP_RPC/abci_query" --data-urlencode "path=\"$path\"" --data-urlencode "data=0x$hex" || true)"
  [ -n "$resp" ] || { echo "RPC request failed (empty reply) for $path" >&2; return 1; }
  printf '%s' "$resp" | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{try{const j=JSON.parse(s);const b=j&&j.result&&j.result.response&&j.result.response.ResponseBase;if(!b){console.error('unexpected RPC response shape for $path');process.exit(1);}if(b.Error){console.error('chain error: '+JSON.stringify(b.Error));process.exit(1);}process.stdout.write(b.Data?Buffer.from(b.Data,'base64').toString('utf-8'):'');}catch(e){console.error('RPC parse failed for $path: '+e.message);process.exit(1);}})"
}

# qeval_int <expr>: evaluates an expression expected to print one int.
qeval_int() {
  rpc_abci vm/qeval "$1" 2>/dev/null \
    | grep -oE '\([0-9]+ int\)' | grep -oE '[0-9]+' | head -1
}

# balance_ugnot <addr>: ugnot balance, 0 when the account holds nothing.
balance_ugnot() {
  local raw
  raw="$(rpc_abci "bank/balances/$1" "" 2>/dev/null || echo "")"
  printf '%s' "$raw" | grep -oE '[0-9]+ugnot' | grep -oE '[0-9]+' | head -1
}

# query_account <addr>: prints "<account-number> <sequence>" for the
# address. A never-seen address returns no account (the ABCI Data decodes
# to "null"); that is a new account, number 0 and sequence 0, which is
# also what gnokey's own maketx would sign with after its account query
# unmarshals the same null. The node rejects the broadcast with
# "account ... does not exist" until the address is funded, which is the
# correct signal: the funding gate below stops a real deploy before then.
query_account() {
  local raw num seq
  raw="$(rpc_abci "auth/accounts/$1" "" 2>/dev/null || echo "")"
  if [ -z "$raw" ] || [ "$raw" = "null" ]; then
    echo "0 0"
    return 0
  fi
  num="$(printf '%s' "$raw" | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{try{const j=JSON.parse(s);const b=j.BaseAccount||j;console.log(String(b.account_number??b.AccountNumber??0));}catch{console.log('0');}})")"
  seq="$(printf '%s' "$raw" | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{try{const j=JSON.parse(s);const b=j.BaseAccount||j;console.log(String(b.sequence??b.Sequence??0));}catch{console.log('0');}})")"
  echo "${num:-0} ${seq:-0}"
}

# --- txbin: build it when missing or stale ------------------------------------
if [ ! -x "$TXBIN" ] || [ "$TXBIN_DIR/main.go" -nt "$TXBIN" ]; then
  echo "--- Building scripts/txbin (amino JSON to binary converter) ---"
  (cd "$TXBIN_DIR" && go build -o txbin .) \
    || { note_fail "Could not build scripts/txbin. See scripts/txbin/README below and docs/ONYX-DEPLOY.md section 5."; echo "RESULT: FAILED (txbin build)"; exit 1; }
  note_pass "Built $TXBIN."
fi

# --- Local chain (local mode only) -------------------------------------------
if [ "$MODE" = "local" ]; then
  echo "--- Starting a fresh local gnodev chain (funded for the Onyx key) ---"
  if curl -s -o /dev/null -m 3 "http://127.0.0.1:$LOCAL_RPC_PORT/status" 2>/dev/null; then
    note_fail "Local RPC port $LOCAL_RPC_PORT is already busy. Stop the stray chain and re-run."
    echo "RESULT: FAILED (port busy)"; exit 1
  fi
  rm -rf "$CHAIN_DIR"
  mkdir -p "$CHAIN_DIR"
  cd "$CHAIN_DIR"
  gnodev local -add-account "$DEPLOYER=100000000ugnot" \
    -node-rpc-listener "127.0.0.1:$LOCAL_RPC_PORT" -web-listener "127.0.0.1:$LOCAL_WEB_PORT" \
    > "$WORK/gnodev-local.log" 2>&1 &
  GNODEV_PID=$!
  echo "$GNODEV_PID" > "$WORK/gnodev.pid"
  note_info "Started gnodev (pid $GNODEV_PID), log $WORK/gnodev-local.log."
  cd "$PROJECT"
  wait_http "$HTTP_RPC/status" 120 "Local chain RPC" || { echo "RESULT: FAILED (chain did not start)"; exit 1; }
  wait_http "$WEB/" 60 "Local gnoweb" || { echo "RESULT: FAILED (gnoweb did not start)"; exit 1; }
  gnokey list -home "$GNOKEY_HOME" 2>/dev/null | grep -q "$DEPLOYER" \
    && note_pass "Key $KEY_NAME ($DEPLOYER) present in $GNOKEY_HOME." \
    || { note_fail "Key $KEY_NAME ($DEPLOYER) not found in $GNOKEY_HOME."; echo "RESULT: FAILED (key check)"; exit 1; }
fi

# --- Onyx funding gate (Onyx mode only) ---------------------------------------
if [ "$MODE" = "onyx" ]; then
  echo "--- Onyx funding gate: key $KEY_NAME must hold at least 20 GNOT ---"
  KEY_LINE="$(gnokey list -home "$GNOKEY_HOME" 2>/dev/null | grep -F "$KEY_NAME" | head -1 || true)"
  [ -n "$KEY_LINE" ] || { note_fail "Key '$KEY_NAME' not found in $GNOKEY_HOME. Create it first (see docs/ONYX-DEPLOY.md)."; echo "RESULT: FAILED (key missing)"; exit 1; }
  KEY_ADDR="$(printf '%s' "$KEY_LINE" | grep -oE 'g1[a-z0-9]+' | head -1)"
  if [ "$KEY_ADDR" != "$DEPLOYER" ]; then
    note_fail "Key '$KEY_NAME' resolves to $KEY_ADDR, but --deployer is $DEPLOYER. The deployer address must be the key's own address."
    echo "RESULT: FAILED (key and deployer differ)"; exit 1
  fi
  note_pass "Key '$KEY_NAME' resolves to the deployer address $DEPLOYER."
  BALANCE="$(balance_ugnot "$DEPLOYER")"
  BALANCE="${BALANCE:-0}"
  note_info "On-chain balance for $DEPLOYER is ${BALANCE}ugnot (minimum ${MIN_BALANCE_UGNOT}ugnot)."
  if [ "$BALANCE" -lt "$MIN_BALANCE_UGNOT" ]; then
    echo "FAIL Key $KEY_NAME ($DEPLOYER) holds ${BALANCE}ugnot, below the ${MIN_BALANCE_UGNOT}ugnot (20 GNOT) minimum. No transaction was attempted."
    echo ""
    echo "Fund the key first:"
    echo "  1. Go to https://faucet.gno.land (the Gno Faucet Hub)."
    echo "  2. Paste the address: $DEPLOYER"
    echo "  3. Pick the Onyx network (chain id onyx-1) and an amount: 100, 200, or 300 GNOT per request."
    echo "  4. Complete the captcha and submit. Tokens arrive in seconds."
    echo "  5. Re-run this script. It re-checks the balance before doing anything."
    echo "  Check the balance any time with:"
    echo "    curl -s -G \"$HTTP_RPC/abci_query\" --data-urlencode 'path=\"bank/balances/$DEPLOYER\"' --data-urlencode 'data=0x'"
    echo "RESULT: BLOCKED (funds missing, faucet step above)"
    exit 1
  fi
  note_pass "Funding gate passed: ${BALANCE}ugnot available."
fi

RC_REALM="$(pkgpath_of realmcheck r)"

# --- The offline-sign transaction flow ---------------------------------------
# offline_tx <name> <maketx-subcommand> <maketx-args...>
# Runs one transaction through the five offline-sign steps and writes the
# broadcast result JSON to $WORK/<name>-broadcast.json. On success it sets
# OFFLINE_TX_RESULT to "<gas-used> <height> <tx-hash>" and returns 0; on
# any failure it prints the failing output and returns 1. The signed tx doc,
# the binary bytes, and the base64 form are kept in $WORK for the record:
#   $WORK/<name>-unsigned.json, $WORK/<name>-signed.json,
#   $WORK/<name>.bin, $WORK/<name>.b64, $WORK/<name>-broadcast.json
offline_tx() {
  local name="$1" sub="$2"; shift 2
  local unsigned="$WORK/$name-unsigned.json"
  local signed="$WORK/$name-signed.json"
  local bin="$WORK/$name.bin"
  local b64file="$WORK/$name.b64"
  local out="$WORK/$name-broadcast.json"
  local acct num seq b64 gas height txhash check_err deliver_err

  # Step 1: unsigned Amino JSON tx document on stdout. No chain contact,
  # no account query, no password. The output must be pure JSON.
  if ! gnokey maketx "$sub" -broadcast=false -chainid "$CHAINID" -remote "$RPC" -home "$GNOKEY_HOME" "$@" "$KEY_NAME" > "$unsigned" 2> "$WORK/$name-maketx.err"; then
    echo "FAIL $name: gnokey maketx $sub failed. See $WORK/$name-maketx.err:" >&2
    sed 's/^/    /' "$WORK/$name-maketx.err" | head -20
    return 1
  fi
  if ! head -c 1 "$unsigned" | grep -q '{'; then
    echo "FAIL $name: maketx output is not a JSON tx document:" >&2
    head -c 300 "$unsigned" | sed 's/^/    /'
    return 1
  fi

  # Step 2: account number and sequence over curl (proxy-aware).
  acct="$(query_account "$DEPLOYER")"
  num="${acct%% *}"
  seq="${acct##* }"
  note_info "$name: signing with account number $num, sequence $seq (chain id $CHAINID)."

  # Step 3: sign offline, in place. The password comes from the password
  # file on stdin and is never printed; without the file gnokey prompts.
  cp "$unsigned" "$signed"
  if [ -f "$PASS_FILE" ]; then
    if ! gnokey sign -tx-path "$signed" -account-number "$num" -account-sequence "$seq" \
        -chainid "$CHAINID" -home "$GNOKEY_HOME" -insecure-password-stdin "$KEY_NAME" \
        < "$PASS_FILE" > "$WORK/$name-sign.log" 2>&1; then
      echo "FAIL $name: gnokey sign failed. See $WORK/$name-sign.log:" >&2
      sed 's/^/    /' "$WORK/$name-sign.log" | head -20
      return 1
    fi
  else
    if ! gnokey sign -tx-path "$signed" -account-number "$num" -account-sequence "$seq" \
        -chainid "$CHAINID" -home "$GNOKEY_HOME" "$KEY_NAME" \
        > "$WORK/$name-sign.log" 2>&1; then
      echo "FAIL $name: gnokey sign failed. See $WORK/$name-sign.log:" >&2
      sed 's/^/    /' "$WORK/$name-sign.log" | head -20
      return 1
    fi
  fi
  if grep -q '"signatures":null' "$signed"; then
    echo "FAIL $name: signed doc has no signatures." >&2
    return 1
  fi

  # Step 4: signed Amino JSON to binary Amino bytes (same two calls
  # gnokey's BroadcastHandler makes, minus the network).
  if ! b64="$("$TXBIN" "$signed" "$bin" 2> "$WORK/$name-txbin.err")"; then
    echo "FAIL $name: txbin failed. See $WORK/$name-txbin.err:" >&2
    sed 's/^/    /' "$WORK/$name-txbin.err" | head -20
    return 1
  fi
  printf '%s' "$b64" > "$b64file"
  [ -s "$bin" ] || { echo "FAIL $name: txbin produced empty binary bytes." >&2; return 1; }

  # Step 5: broadcast the base64 bytes with curl (proxy-aware JSON-RPC).
  # broadcast_tx_commit waits for the tx to commit and returns check_tx,
  # deliver_tx, hash, and height in one response.
  if ! curl -s -m 90 -X POST -H 'Content-Type: application/json' \
      -d "{\"jsonrpc\":\"2.0\",\"id\":\"realmcheck-$name\",\"method\":\"broadcast_tx_commit\",\"params\":{\"tx\":\"$b64\"}}" \
      "$HTTP_RPC/" > "$out" 2> "$WORK/$name-curl.err"; then
    echo "FAIL $name: curl broadcast failed. See $WORK/$name-curl.err:" >&2
    sed 's/^/    /' "$WORK/$name-curl.err" | head -20
    return 1
  fi
  if ! node -e "JSON.parse(require('fs').readFileSync(process.argv[1],'utf-8'))" "$out" 2>/dev/null; then
    echo "FAIL $name: broadcast response is not JSON:" >&2
    head -c 500 "$out" | sed 's/^/    /'
    return 1
  fi
  check_err="$(node -e "const j=JSON.parse(require('fs').readFileSync(process.argv[1],'utf-8'));const e=j.result&&j.result.check_tx&&j.result.check_tx.ResponseBase&&j.result.check_tx.ResponseBase.Error;console.log(e?JSON.stringify(e):'')" "$out")"
  deliver_err="$(node -e "const j=JSON.parse(require('fs').readFileSync(process.argv[1],'utf-8'));const e=j.result&&j.result.deliver_tx&&j.result.deliver_tx.ResponseBase&&j.result.deliver_tx.ResponseBase.Error;console.log(e?JSON.stringify(e):'')" "$out")"
  if [ -n "$check_err" ] || [ -n "$deliver_err" ]; then
    echo "FAIL $name: node refused the transaction." >&2
    [ -n "$check_err" ] && echo "  check_tx error: $check_err"
    [ -n "$deliver_err" ] && echo "  deliver_tx error: $deliver_err"
    node -e "const j=JSON.parse(require('fs').readFileSync(process.argv[1],'utf-8'));const r=j.result||{};const l=(r.check_tx&&r.check_tx.ResponseBase&&r.check_tx.ResponseBase.Log)||(r.deliver_tx&&r.deliver_tx.ResponseBase&&r.deliver_tx.ResponseBase.Log)||'';console.log(l.split('\n').slice(0,6).map(x=>'  '+x).join('\n'))" "$out"
    echo "  Full response: $out" >&2
    return 1
  fi
  gas="$(node -e "const j=JSON.parse(require('fs').readFileSync(process.argv[1],'utf-8'));console.log(j.result&&j.result.deliver_tx&&j.result.deliver_tx.GasUsed||'')" "$out")"
  height="$(node -e "const j=JSON.parse(require('fs').readFileSync(process.argv[1],'utf-8'));console.log(j.result&&j.result.height||'')" "$out")"
  txhash="$(node -e "const j=JSON.parse(require('fs').readFileSync(process.argv[1],'utf-8'));console.log(j.result&&j.result.hash||'')" "$out")"
  # Result in a global, not on stdout: callers run this function directly
  # (no command substitution), so diagnostics stay visible on the terminal
  # and the result is still available after the call.
  OFFLINE_TX_RESULT="${gas:-unknown} ${height:-unknown} ${txhash:-unknown}"
  note_info "$name: broadcast committed (gas used ${gas:-unknown}, height ${height:-unknown}, tx ${txhash:-unknown})."
  return 0
}

# verify_pkg <name> <kind>: qfile listing plus a byte diff of every staged
# .gno file against the on-chain copy. Returns 0 when the deployed package
# matches the staged source exactly.
verify_pkg() {
  local name="$1" kind="$2" path listing ok=1 f base fetched
  path="$(pkgpath_of "$name" "$kind")"
  listing="$(rpc_abci vm/qfile "$path" 2>/dev/null || echo "")"
  for f in "$STAGE/$name"/*.gno; do
    base="$(basename "$f")"
    printf '%s' "$listing" | grep -qx "$base" || { echo "FAIL $name: on-chain listing for $path is missing $base."; ok=0; }
    fetched="$WORK/qfile-$name-$base"
    rpc_abci vm/qfile "$path/$base" > "$fetched" 2>/dev/null || { echo "FAIL $name: could not fetch $path/$base from the chain."; ok=0; continue; }
    cmp -s "$f" "$fetched" || { echo "FAIL $name: on-chain $base differs from the staged source."; diff "$f" "$fetched" | head -5 | sed 's/^/    /'; ok=0; }
  done
  [ "$ok" -eq 1 ]
}

# deploy_pkg <name> <kind>: addpkg through the offline-sign flow, then
# verify. When addpkg fails but the package already exists on chain with
# identical content, that counts as deployed (idempotent re-run) and the
# script continues with a warning.
deploy_pkg() {
  local name="$1" kind="$2" path result gas height txhash
  path="$(pkgpath_of "$name" "$kind")"
  if ! offline_tx "addpkg-$name" addpkg \
    -pkgpath "$path" -pkgdir "$STAGE/$name" \
    -gas-fee "${ADD_PKG_GAS_FEE}ugnot" -gas-wanted "$ADD_PKG_GAS_WANTED"; then
    note_info "addpkg $name failed; checking whether $path already exists on chain..."
    if verify_pkg "$name" "$kind" 2>/dev/null; then
      note_pass "addpkg $name was refused, but $path already exists on chain with identical content. Continuing (idempotent re-run)."
      echo "$name|$path|already-deployed||" >> "$WORK/deployed.txt"
      return 0
    fi
    note_fail "addpkg $name failed and $path is not verifiably deployed."
    return 1
  fi
  gas="$(printf '%s' "$OFFLINE_TX_RESULT" | awk '{print $1}')"
  height="$(printf '%s' "$OFFLINE_TX_RESULT" | awk '{print $2}')"
  txhash="$(printf '%s' "$OFFLINE_TX_RESULT" | awk '{print $3}')"
  if ! verify_pkg "$name" "$kind"; then
    note_fail "addpkg $name broadcast, but verification of $path failed."
    return 1
  fi
  echo "$name|$path|${gas:-unknown}|${height:-unknown}|${txhash:-unknown}" >> "$WORK/deployed.txt"
  note_pass "addpkg $name deployed and verified (gas used ${gas:-unknown}, height ${height:-unknown}, tx ${txhash:-unknown})."
  return 0
}

# --- Step 2: deploy all packages in order ------------------------------------
echo "--- Deploying packages in order (offline-sign flow) ---"
: > "$WORK/deployed.txt"
while IFS='|' read -r name kind srcdir; do
  [ -n "$name" ] || continue
  deploy_pkg "$name" "$kind" || true
done <<EOF
$PACKAGES
EOF
[ "$FAILURES" -gt 0 ] && { echo "RESULT: FAILED (deploy)"; exit 1; }
[ "$(wc -l < "$WORK/deployed.txt")" -eq 7 ] || { note_fail "Expected 7 deployed packages, got $(wc -l < "$WORK/deployed.txt")."; echo "RESULT: FAILED (deploy count)"; exit 1; }
note_pass "All 7 packages deployed and verified."

# --- Step 3: test SubmitReport on the deployed realmcheck --------------------
# The test report is the real audit output, not a hardcoded string: the
# UI's own JS audit port runs over the staged vulnmint source, and the
# result must match the ground truth (score 75, one finding RC-02 at
# line 41) before anything is submitted.
echo "--- Test SubmitReport (vulnmint ground truth) ---"
cat > "$WORK/build-test-report.mjs" <<'MJS'
import { readFileSync, writeFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { auditFiles, score } from "../../ui/src/lib/audit.js";
import { encodeFindings } from "../../ui/src/lib/gnoRpc.js";
const [stagedFile, realmPath, outFile] = process.argv.slice(2);
const source = readFileSync(stagedFile, "utf-8");
const findings = auditFiles([{ name: "vulnmint.gno", source }]);
const sourceHash = createHash("sha256").update(source, "utf-8").digest("hex");
writeFileSync(outFile, JSON.stringify({
  realmPath,
  sourceHash,
  score: score(findings),
  encoded: encodeFindings(findings),
  findingCount: findings.length,
  findings: findings.map((f) => ({ ruleID: f.ruleID, line: f.line })),
}, null, 2));
MJS
node "$WORK/build-test-report.mjs" \
  "$STAGE/vulnmint/vulnmint.gno" "$(pkgpath_of vulnmint r)" "$WORK/test-report.json" \
  || { note_fail "Could not build the test report with the UI audit port."; echo "RESULT: FAILED (test report)"; exit 1; }
TEST_REALM="$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1])).realmPath)" "$WORK/test-report.json")"
TEST_HASH="$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1])).sourceHash)" "$WORK/test-report.json")"
TEST_SCORE="$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1])).score)" "$WORK/test-report.json")"
TEST_N="$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1])).findingCount)" "$WORK/test-report.json")"
TEST_ENCODED="$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1])).encoded)" "$WORK/test-report.json")"
[ "$TEST_SCORE" = "75" ] && [ "$TEST_N" = "1" ] \
  || { note_fail "Test report does not match the vulnmint ground truth (score $TEST_SCORE, $TEST_N finding(s); expected 75 and 1)."; echo "RESULT: FAILED (ground truth)"; exit 1; }
note_pass "Test report built with the UI audit port: $TEST_REALM, score 75, 1 finding (RC-02@41), sha256 ${TEST_HASH:0:16}..."

BASELINE_COUNT="$(qeval_int "$RC_REALM.ReportCount()" || echo "")"
[ -n "$BASELINE_COUNT" ] || { note_fail "Could not read ReportCount() from $RC_REALM after deploy."; echo "RESULT: FAILED (ReportCount unreadable)"; exit 1; }
note_pass "Baseline ReportCount() is $BASELINE_COUNT."

TEST_GAS_WANTED=$((10000000 + 7000000 * TEST_N))
TEST_GAS_FEE=$((TEST_GAS_WANTED / 500))
if ! offline_tx "submit-test" call \
  -pkgpath "$RC_REALM" -func "SubmitReport" \
  -args "$TEST_REALM" -args "$TEST_HASH" -args "$TEST_SCORE" -args "$TEST_ENCODED" \
  -gas-fee "${TEST_GAS_FEE}ugnot" -gas-wanted "$TEST_GAS_WANTED"; then
  note_fail "Test SubmitReport failed (gas-wanted $TEST_GAS_WANTED, gas-fee ${TEST_GAS_FEE}ugnot)."
  echo "RESULT: FAILED (test SubmitReport)"; exit 1
fi
TEST_GAS_USED="$(printf '%s' "$OFFLINE_TX_RESULT" | awk '{print $1}')"
TEST_TX="$(printf '%s' "$OFFLINE_TX_RESULT" | awk '{print $3}')"
note_pass "Test SubmitReport broadcast (gas wanted $TEST_GAS_WANTED, used ${TEST_GAS_USED:-unknown}, tx ${TEST_TX:-unknown})."

# --- Step 4: verify the stored report back -----------------------------------
# read-report.mjs reuses the UI's own qeval plus parsePrintedReport, so
# the check reads the chain the same way the UI does.
cat > "$WORK/read-report.mjs" <<'MJS'
import { qeval, parsePrintedReport, parsePrintedString, decodeFindings } from "../../ui/src/lib/gnoRpc.js";
const [mode, arg] = process.argv.slice(2);
const realm = process.env.REALMCHECK_REALM;
if (mode === "latest") {
  const printed = await qeval(`${realm}.LatestReport(${JSON.stringify(arg)})`);
  console.log(JSON.stringify(parsePrintedReport(printed)));
} else if (mode === "get") {
  const printed = await qeval(`${realm}.GetReport(${arg})`);
  console.log(JSON.stringify(parsePrintedReport(printed)));
} else if (mode === "findings") {
  const raw = await qeval(`${realm}.ReportFindings(${arg})`);
  console.log(JSON.stringify(decodeFindings(parsePrintedString(raw))));
} else {
  console.error("unknown mode: " + mode);
  process.exit(1);
}
MJS
export VITE_GNO_RPC="$HTTP_RPC"
export REALMCHECK_REALM="$RC_REALM"
AFTER_COUNT="$(qeval_int "$RC_REALM.ReportCount()" || echo "")"
[ "$AFTER_COUNT" = "$((BASELINE_COUNT + 1))" ] \
  || { note_fail "ReportCount() is $AFTER_COUNT after the test submit, expected $((BASELINE_COUNT + 1))."; echo "RESULT: FAILED (ReportCount)"; exit 1; }
note_pass "ReportCount() is $AFTER_COUNT after the test submit (was $BASELINE_COUNT)."
NEW_ID="$AFTER_COUNT"
LATEST_JSON="$(node "$WORK/read-report.mjs" latest "$TEST_REALM" 2>/dev/null || echo "null")"
LATEST_ID="$(printf '%s' "$LATEST_JSON" | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{try{console.log(JSON.parse(s).id)}catch{console.log('')}})")"
LATEST_SCORE="$(printf '%s' "$LATEST_JSON" | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{try{console.log(JSON.parse(s).score)}catch{console.log('')}})")"
LATEST_AUDITOR="$(printf '%s' "$LATEST_JSON" | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{try{console.log(JSON.parse(s).auditor)}catch{console.log('')}})")"
[ "$LATEST_ID" = "$NEW_ID" ] && [ "$LATEST_SCORE" = "75" ] && [ "$LATEST_AUDITOR" = "$DEPLOYER" ] \
  || { note_fail "LatestReport mismatch: id $LATEST_ID (expected $NEW_ID), score $LATEST_SCORE (expected 75), auditor $LATEST_AUDITOR (expected $DEPLOYER)."; echo "RESULT: FAILED (LatestReport)"; exit 1; }
note_pass "LatestReport($TEST_REALM) is report #$NEW_ID, score 75, auditor $DEPLOYER."
STORED_FINDINGS="$(node "$WORK/read-report.mjs" findings "$NEW_ID" 2>/dev/null || echo "[]")"
printf '%s' "$STORED_FINDINGS" | grep -q '"ruleID":"RC-02"' \
  || { note_fail "ReportFindings($NEW_ID) does not contain the RC-02 finding: $STORED_FINDINGS"; echo "RESULT: FAILED (ReportFindings)"; exit 1; }
note_pass "ReportFindings($NEW_ID) contains the RC-02 finding."
RENDER="$(rpc_abci vm/qeval "$RC_REALM.Render(\"\")" 2>/dev/null || echo "")"
printf '%s' "$RENDER" | grep -q "$TEST_REALM" && printf '%s' "$RENDER" | grep -q "75" \
  || { note_fail "Render(\"\") does not list the test report for $TEST_REALM with score 75."; echo "RESULT: FAILED (Render)"; exit 1; }
note_pass "Render(\"\") lists the test report for $TEST_REALM with score 75."

# --- Summary -------------------------------------------------------------------
echo "=== Summary ==="
echo "Chain: $RPC (chain id $CHAINID), deployer $DEPLOYER, key $KEY_NAME."
echo "Deploy method: offline-sign (gnokey maketx -broadcast=false plus gnokey sign, txbin, curl broadcast_tx_commit)."
while IFS='|' read -r name path gas height tx; do
  echo "Deployed: $path (gas used $gas, height $height, tx $tx)"
  echo "  View: $WEB/${path#gno.land/}"
done < "$WORK/deployed.txt"
echo "Report realm: $RC_REALM"
echo "  View: $WEB/${RC_REALM#gno.land/}"
echo "Test report: #$NEW_ID for $TEST_REALM, score 75, auditor $DEPLOYER, tx ${TEST_TX:-unknown}."
if [ "$FAILURES" -eq 0 ]; then
  echo "RESULT: PASSED (offline-sign deploy complete and verified)"
  exit 0
else
  echo "RESULT: FAILED ($FAILURES failure(s))"
  exit 1
fi
