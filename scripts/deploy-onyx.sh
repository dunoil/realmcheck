#!/usr/bin/env bash
# deploy-onyx.sh: deploy RealmCheck to the Onyx testnet (or a local chain).
#
# Order: auditrules package, realmcheck realm, then the 5 demo realms
# (vulnmint first, adminbackdoor last, because adminbackdoor imports
# vulnmint). Every `dunoil` namespace becomes the deployer g1 address in
# every module path, in the realmcheck import, and in the adminbackdoor
# import and PackageAddress call; the placeholder Admin address in
# adminbackdoor becomes the deployer address. The swap happens on staged
# copies only; contracts/** is never edited.
#
# Modes (exactly one; default is the real Onyx deploy):
#   --check   Dry run. Stages the packages, applies and verifies the
#             namespace swap, prints every command that would run, and
#             exits. No chain contact, no transaction, no key needed.
#   --local   Full deploy against a fresh local gnodev chain, with the
#             namespace swapped to the local deployer address
#             (realmcheck-dev). Proves the order, the swap, the gas
#             settings, and the verification steps end to end. The chain
#             is started and stopped by this run. No faucet, no Onyx.
#   (none)    Real Onyx deploy. Refuses to run without a funded key: the
#             key must exist in gnokey list and hold at least 20 GNOT.
#             When funds are missing it prints the faucet URL and the
#             exact funding step and exits without attempting any
#             transaction.
#
# Onyx usage:
#   bash scripts/deploy-onyx.sh --key <key-name> --deployer <g1-address>
#   bash scripts/deploy-onyx.sh --key mykey --deployer g1abc... --rpc https://rpc.onyx.testnets.gno.land:443
#
# Local validation usage:
#   bash scripts/deploy-onyx.sh --local
#   bash scripts/deploy-onyx.sh --check
#
# Gas (measured on a local dev chain; see docs/ONYX-DEPLOY.md):
#   addpkg: gas-wanted 70,000,000, gas-fee 140,000ugnot (wanted/500).
#     auditrules is the largest package (about 43 KB of source, 53,180
#     stored bytes) and its addpkg used 62,350,946 gas on the local
#     chain; the chain itself suggested gas-wanted 65,468,494, so
#     70,000,000 carries a small margin. The demos used 6.0M to 10.0M
#     each. The flat gas fee is what is charged (unused gas is not
#     billed), so one generous wanted value is used for every package.
#   SubmitReport (test report): gas-wanted 10,000,000 plus 7,000,000 per
#     finding, gas-fee wanted/500 (docs/API.md formula).
#
# Full output is also written to scripts/onyx-deploy-work/run-<mode>-<time>.log.
# Exit code 0 means every deploy and verification step passed.

set -u

# Save the original arguments: the parser below consumes $@, and the
# self-tee block re-invokes this script with them.
ORIG_ARGS=("$@")

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$PROJECT/scripts/onyx-deploy-work"
STAGE="$WORK/stage"
CHAIN_DIR="$WORK/chain"

# --- Defaults (overridden by flags) -----------------------------------------
MODE="onyx"
KEY_NAME=""
DEPLOYER=""
RPC="https://rpc.onyx.testnets.gno.land:443"
CHAINID="onyx-1"
WEB="https://onyx.testnets.gno.land"

# Local mode values (gnodev local chain, realmcheck-dev key).
LOCAL_KEY="realmcheck-dev"
LOCAL_ADDR="g1yzqhuxczln72kwm9pstcmjerhnu0uverkuyz4h"
LOCAL_RPC_PORT=26659
LOCAL_WEB_PORT=8890
LOCAL_PASS="devpass"

ADD_PKG_GAS_WANTED=70000000
ADD_PKG_GAS_FEE=140000
MIN_BALANCE_UGNOT=20000000
# 20 GNOT. Measured total for the whole deploy on a local chain is
# 12,050,000ugnot (7 addpkg transactions at 11,749,300ugnot plus the
# test SubmitReport at 300,700ugnot), so 20 GNOT leaves margin for
# Onyx-side differences. One faucet request (100 GNOT) covers it.

FAILURES=0
GNODEV_PID=""
BASELINE_COUNT=""

usage() {
  cat <<EOF
Usage:
  bash scripts/deploy-onyx.sh --key <key-name> --deployer <g1-address> [--rpc <url>] [--chainid <id>]
  bash scripts/deploy-onyx.sh --local
  bash scripts/deploy-onyx.sh --check [--deployer <g1-address>]
Options:
  --key NAME        gnokey key name that signs the Onyx deploy (required for Onyx mode)
  --deployer ADDR   deployer g1 address; becomes the namespace in every module path (required for Onyx mode)
  --rpc URL         RPC remote (default: $RPC)
  --chainid ID      chain id (default: $CHAINID)
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

# gnokey_query <qpath> <data>: one read-only query, prints the raw output.
gnokey_query() {
  gnokey query "$1" -data "$2" -remote "$RPC" 2>&1
}

# qeval_int <expr>: evaluates an expression expected to print one int.
qeval_int() {
  gnokey_query vm/qeval "$1" 2>/dev/null \
    | grep -oE '\([0-9]+ int\)' | grep -oE '[0-9]+' | head -1
}

echo "=== RealmCheck Onyx deploy ==="
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
  KEY_NAME="$LOCAL_KEY"
  DEPLOYER="$LOCAL_ADDR"
  RPC="127.0.0.1:$LOCAL_RPC_PORT"
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
    echo "  gnokey maketx addpkg -pkgpath \"$(pkgpath_of "$name" "$kind")\" -pkgdir $STAGE/$name -gas-fee ${ADD_PKG_GAS_FEE}ugnot -gas-wanted $ADD_PKG_GAS_WANTED -chainid $CHAINID -remote $RPC <key-name>"
    echo "  verify: abci_query vm/qfile for \"$(pkgpath_of "$name" "$kind")\" (curl, proxy-aware), then diff each staged .gno file against the on-chain copy"
  done <<EOF
$PACKAGES
EOF
  echo "test SubmitReport: gnokey maketx call -pkgpath \"$(pkgpath_of realmcheck r)\" -func \"SubmitReport\" -args \"$(pkgpath_of vulnmint r)\" -args <sha256 of staged vulnmint.gno> -args 75 -args <RC-02 finding encoding> -gas-fee 34000ugnot -gas-wanted 17000000 -chainid $CHAINID -remote $RPC <key-name>"
  echo "verify: ReportCount(), GetReport(1), ReportFindings(1), LatestReport(\"$(pkgpath_of vulnmint r)\"), Render(\"\")"
  echo "Funding gate for Onyx mode: key must hold at least $MIN_BALANCE_UGNOT ugnot (20 GNOT)."
  echo "Faucet when funds are missing: https://faucet.gno.land (see docs/ONYX-DEPLOY.md)."
  echo "RESULT: PASSED (dry-run plan printed, swap verified)"
  exit 0
fi

# --- RPC helpers (curl, proxy-aware) -----------------------------------------
# All read-only checks go through curl, not gnokey: gnokey builds its own
# HTTP client with no proxy support (see docs/ONYX-DEPLOY.md), so from a
# machine behind an egress proxy gnokey cannot reach Onyx at all, while
# curl and node can. gnokey is used only for signing and broadcasting.
HTTP_RPC="$RPC"
if [ "$MODE" = "local" ]; then
  HTTP_RPC="http://127.0.0.1:$LOCAL_RPC_PORT"
fi

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

# --- Local chain (local mode only) -------------------------------------------
if [ "$MODE" = "local" ]; then
  echo "--- Starting a fresh local gnodev chain ---"
  if curl -s -o /dev/null -m 3 "http://127.0.0.1:$LOCAL_RPC_PORT/status" 2>/dev/null; then
    note_fail "Local RPC port $LOCAL_RPC_PORT is already busy. Stop the stray chain and re-run."
    echo "RESULT: FAILED (port busy)"; exit 1
  fi
  rm -rf "$CHAIN_DIR"
  mkdir -p "$CHAIN_DIR"
  cd "$CHAIN_DIR"
  gnodev local -add-account "$LOCAL_ADDR=100000000ugnot" \
    -node-rpc-listener "127.0.0.1:$LOCAL_RPC_PORT" -web-listener "127.0.0.1:$LOCAL_WEB_PORT" \
    > "$WORK/gnodev-local.log" 2>&1 &
  GNODEV_PID=$!
  echo "$GNODEV_PID" > "$WORK/gnodev.pid"
  note_info "Started gnodev (pid $GNODEV_PID), log $WORK/gnodev-local.log."
  cd "$PROJECT"
  wait_http "$HTTP_RPC/status" 120 "Local chain RPC" || { echo "RESULT: FAILED (chain did not start)"; exit 1; }
  wait_http "$WEB/" 60 "Local gnoweb" || { echo "RESULT: FAILED (gnoweb did not start)"; exit 1; }
  gnokey list 2>/dev/null | grep -q "$LOCAL_ADDR" \
    && note_pass "Local dev key $LOCAL_KEY ($LOCAL_ADDR) present." \
    || { note_fail "Local dev key $LOCAL_KEY ($LOCAL_ADDR) not found in gnokey list."; echo "RESULT: FAILED (key check)"; exit 1; }
fi

# --- Onyx funding gate and gnokey reachability (Onyx mode only) --------------
if [ "$MODE" = "onyx" ]; then
  echo "--- Onyx funding gate: key $KEY_NAME must hold at least 20 GNOT ---"
  KEY_LINE="$(gnokey list 2>/dev/null | grep -F "$KEY_NAME" | head -1 || true)"
  [ -n "$KEY_LINE" ] || { note_fail "Key '$KEY_NAME' not found in gnokey list. Create it first (see docs/ONYX-DEPLOY.md)."; echo "RESULT: FAILED (key missing)"; exit 1; }
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
  echo "--- gnokey reachability probe: gnokey must be able to reach the Onyx RPC ---"
  PROBE_OUT="$(gnokey query vm/qfile -data "gno.land/r/gov/dao" -remote "$RPC" 2>&1 || true)"
  if printf '%s' "$PROBE_OUT" | grep -q "unable to call RPC\|tls: first record"; then
    echo "FAIL gnokey cannot reach the Onyx RPC from this machine."
    echo "  Probe output: $(printf '%s' "$PROBE_OUT" | head -2 | tr '\n' ' ')"
    echo "  Cause (verified 27 Nov 2026): gnokey builds its own HTTP client with no"
    echo "  proxy support, so on a machine behind an egress proxy it connects directly"
    echo "  and the direct path to the Onyx RPC does not complete a TLS handshake."
    echo "  curl and node reach the RPC fine through the proxy; gnokey does not."
    echo "  No transaction was attempted."
    echo ""
    echo "Run this script instead from a machine with direct internet access"
    echo "(for example the owner's PC with the toolchain and the funded key),"
    echo "or fix the egress path so gnokey can reach $RPC directly."
    echo "See docs/ONYX-DEPLOY.md, section 5, for the full diagnosis."
    echo "RESULT: BLOCKED (gnokey cannot reach Onyx from this machine)"
    exit 1
  fi
  note_pass "gnokey reaches the Onyx RPC."
fi

RC_REALM="$(pkgpath_of realmcheck r)"

# maketx <outfile> <subcommand> <args...>: sign and broadcast one
# transaction. Local mode feeds the dev password on stdin; Onyx mode
# prompts for the key password interactively.
maketx() {
  local out="$1" sub="$2"; shift 2
  if [ "$MODE" = "local" ]; then
    printf '%s\n' "$LOCAL_PASS" | gnokey maketx "$sub" -insecure-password-stdin "$@" > "$out" 2>&1
  else
    gnokey maketx "$sub" "$@" > "$out" 2>&1
  fi
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

# deploy_pkg <name> <kind>: addpkg, then verify. When addpkg fails but the
# package already exists on chain with identical content, that counts as
# deployed (idempotent re-run) and the script continues with a warning.
deploy_pkg() {
  local name="$1" kind="$2" path out gas height txhash
  path="$(pkgpath_of "$name" "$kind")"
  out="$WORK/addpkg-$name.txt"
  maketx "$out" addpkg \
    -pkgpath "$path" -pkgdir "$STAGE/$name" \
    -gas-fee "${ADD_PKG_GAS_FEE}ugnot" -gas-wanted "$ADD_PKG_GAS_WANTED" \
    -chainid "$CHAINID" -remote "$RPC" "$KEY_NAME"
  if grep -q -- "--= Error" "$out" || grep -q "invalid package" "$out"; then
    note_info "addpkg $name failed; checking whether $path already exists on chain..."
    if verify_pkg "$name" "$kind" 2>/dev/null; then
      note_pass "addpkg $name was refused, but $path already exists on chain with identical content. Continuing (idempotent re-run)."
      echo "$name|$path|already-deployed||" >> "$WORK/deployed.txt"
      return 0
    fi
    note_fail "addpkg $name failed and $path is not verifiably deployed. See $out:"
    sed 's/^/    /' "$out" | head -20
    return 1
  fi
  gas="$(grep -oE 'GAS USED: +[0-9]+' "$out" | grep -oE '[0-9]+' | head -1)"
  height="$(grep -oE 'HEIGHT: +[0-9]+' "$out" | grep -oE '[0-9]+' | head -1)"
  txhash="$(grep -oE 'TX HASH: +[^ ]+' "$out" | awk '{print $3}' | head -1)"
  if ! verify_pkg "$name" "$kind"; then
    note_fail "addpkg $name broadcast, but verification of $path failed."
    return 1
  fi
  echo "$name|$path|${gas:-unknown}|${height:-unknown}|${txhash:-unknown}" >> "$WORK/deployed.txt"
  note_pass "addpkg $name deployed and verified (gas used ${gas:-unknown}, height ${height:-unknown}, tx ${txhash:-unknown})."
  return 0
}

# --- Step 2: deploy all packages in order ------------------------------------
echo "--- Deploying packages in order ---"
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
maketx "$WORK/submit-test.txt" call \
  -pkgpath "$RC_REALM" -func "SubmitReport" \
  -args "$TEST_REALM" -args "$TEST_HASH" -args "$TEST_SCORE" -args "$TEST_ENCODED" \
  -gas-fee "${TEST_GAS_FEE}ugnot" -gas-wanted "$TEST_GAS_WANTED" \
  -chainid "$CHAINID" -remote "$RPC" "$KEY_NAME"
if grep -q -- "--= Error" "$WORK/submit-test.txt" || grep -q "success:false" "$WORK/submit-test.txt"; then
  note_fail "Test SubmitReport failed (gas-wanted $TEST_GAS_WANTED, gas-fee ${TEST_GAS_FEE}ugnot). See $WORK/submit-test.txt:"
  sed 's/^/    /' "$WORK/submit-test.txt" | head -20
  echo "RESULT: FAILED (test SubmitReport)"; exit 1
fi
TEST_GAS_USED="$(grep -oE 'GAS USED: +[0-9]+' "$WORK/submit-test.txt" | grep -oE '[0-9]+' | head -1)"
TEST_TX="$(grep -oE 'TX HASH: +[^ ]+' "$WORK/submit-test.txt" | awk '{print $3}' | head -1)"
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
while IFS='|' read -r name path gas height tx; do
  echo "Deployed: $path (gas used $gas, height $height, tx $tx)"
  echo "  View: $WEB/${path#gno.land/}"
done < "$WORK/deployed.txt"
echo "Report realm: $RC_REALM"
echo "  View: $WEB/${RC_REALM#gno.land/}"
echo "Test report: #$NEW_ID for $TEST_REALM, score 75, auditor $DEPLOYER, tx ${TEST_TX:-unknown}."
if [ "$FAILURES" -eq 0 ]; then
  echo "RESULT: PASSED (Onyx deploy complete and verified)"
  exit 0
else
  echo "RESULT: FAILED ($FAILURES failure(s))"
  exit 1
fi
