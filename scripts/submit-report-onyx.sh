#!/usr/bin/env bash
# submit-report-onyx.sh: submit one audit report for a deployed Onyx demo
# realm through the same offline-sign flow as scripts/offline-sign-deploy.sh
# (gnokey maketx -broadcast=false plus gnokey sign, txbin, curl
# broadcast_tx_commit). Used for the second stored report the demo video
# needs (adminbackdoor, report #2) after the deploy resume stored #1.
#
# The report is the real audit output, not a hardcoded string: the UI's
# own audit port runs over the STAGED source (the exact bytes deployed
# on chain, namespace swap included), and the score and finding count
# must match the expected ground truth before anything is submitted.
#
# Usage:
#   bash scripts/submit-report-onyx.sh --realm adminbackdoor \
#     --expected-score 37 --expected-rules RC-01,RC-03,RC-07,RC-08
# Log: scripts/offline-work/submit-<realm>-<time>.log
# Exit 0 when the report is stored and reads back correctly.

set -u

ORIG_ARGS=("$@")
PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$PROJECT/scripts/offline-work"
STAGE="$WORK/stage"
TXBIN="$PROJECT/scripts/txbin/txbin"
KEY_NAME="realmcheck-onyx"
DEPLOYER="g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu"
RPC="https://rpc.onyx.testnets.gno.land:443"
CHAINID="onyx-1"
GNOKEY_HOME="$PROJECT/.gnokey"
PASS_FILE="$PROJECT/.gnokey/password.txt"
RC_REALM="gno.land/r/$DEPLOYER/realmcheck"

REALM=""
EXPECTED_SCORE=""
EXPECTED_RULES=""

while [ $# -gt 0 ]; do
  case "$1" in
    --realm) REALM="$2"; shift 2 ;;
    --expected-score) EXPECTED_SCORE="$2"; shift 2 ;;
    --expected-rules) EXPECTED_RULES="$2"; shift 2 ;;
    --help) echo "Usage: bash scripts/submit-report-onyx.sh --realm <name> --expected-score <n> --expected-rules <RC-01,RC-02,...>"; exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done
[ -n "$REALM" ] && [ -n "$EXPECTED_SCORE" ] && [ -n "$EXPECTED_RULES" ] || {
  echo "FAIL --realm, --expected-score, and --expected-rules are all required."
  exit 1
}

if [ -z "${SUBMIT_INNER:-}" ]; then
  mkdir -p "$WORK"
  LOG="$WORK/submit-$REALM-$(date +%Y%m%d-%H%M%S).log"
  echo "Logging to $LOG"
  SUBMIT_INNER=1 "$0" "${ORIG_ARGS[@]}" 2>&1 | tee "$LOG"
  exit "${PIPESTATUS[0]}"
fi

export PATH="$PATH:$HOME/workspace/tools/go/bin:$HOME/workspace/tools/gno/bin"
export GNOROOT="$HOME/workspace/tools/gno"

FAILURES=0
note_pass() { echo "PASS $1"; }
note_fail() { echo "FAIL $1"; FAILURES=$((FAILURES + 1)); }
note_info() { echo "INFO $1"; }

REALM_PATH="gno.land/r/$DEPLOYER/$REALM"
STAGED_FILE="$STAGE/$REALM/$REALM.gno"
[ -f "$STAGED_FILE" ] || { note_fail "Staged source not found: $STAGED_FILE (run the deploy script first)."; echo "RESULT: FAILED"; exit 1; }

rpc_abci() {
  local path="$1" data="$2" hex resp
  hex="$(printf '%s' "$data" | od -An -tx1 | tr -d ' \n')"
  resp="$(curl -s -m 20 -G "$RPC/abci_query" --data-urlencode "path=\"$path\"" --data-urlencode "data=0x$hex" || true)"
  [ -n "$resp" ] || { echo "RPC request failed (empty reply) for $path" >&2; return 1; }
  printf '%s' "$resp" | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{try{const j=JSON.parse(s);const b=j&&j.result&&j.result.response&&j.result.response.ResponseBase;if(!b){console.error('unexpected RPC response shape for $path');process.exit(1);}if(b.Error){console.error('chain error: '+JSON.stringify(b.Error));process.exit(1);}process.stdout.write(b.Data?Buffer.from(b.Data,'base64').toString('utf-8'):'');}catch(e){console.error('RPC parse failed for $path: '+e.message);process.exit(1);}})"
}

qeval_int() {
  rpc_abci vm/qeval "$1" 2>/dev/null \
    | grep -oE '\([0-9]+ int\)' | grep -oE '[0-9]+' | head -1
}

query_account() {
  local raw num seq
  raw="$(rpc_abci "auth/accounts/$1" "" 2>/dev/null || echo "")"
  if [ -z "$raw" ] || [ "$raw" = "null" ]; then echo "0 0"; return 0; fi
  num="$(printf '%s' "$raw" | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{try{const j=JSON.parse(s);const b=j.BaseAccount||j;console.log(String(b.account_number??b.AccountNumber??0));}catch{console.log('0');}})")"
  seq="$(printf '%s' "$raw" | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{try{const j=JSON.parse(s);const b=j.BaseAccount||j;console.log(String(b.sequence??b.Sequence??0));}catch{console.log('0');}})")"
  echo "${num:-0} ${seq:-0}"
}

echo "=== SubmitReport for $REALM_PATH (offline-sign) ==="
echo "Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"

# Build the report with the UI audit port over the staged source.
cat > "$WORK/build-report-$REALM.mjs" <<'MJS'
import { readFileSync, writeFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { auditFiles, score } from "../../ui/src/lib/audit.js";
import { encodeFindings } from "../../ui/src/lib/gnoRpc.js";
const [stagedFile, realmPath, outFile] = process.argv.slice(2);
const source = readFileSync(stagedFile, "utf-8");
const findings = auditFiles([{ name: realmPath.split("/").pop() + ".gno", source }]);
const sourceHash = createHash("sha256").update(source, "utf-8").digest("hex");
writeFileSync(outFile, JSON.stringify({
  realmPath, sourceHash, score: score(findings),
  encoded: encodeFindings(findings), findingCount: findings.length,
  findings: findings.map((f) => ({ ruleID: f.ruleID, line: f.line })),
}, null, 2));
MJS
node "$WORK/build-report-$REALM.mjs" "$STAGED_FILE" "$REALM_PATH" "$WORK/report-$REALM.json" \
  || { note_fail "Could not build the report with the UI audit port."; echo "RESULT: FAILED"; exit 1; }
TEST_SCORE="$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1])).score)" "$WORK/report-$REALM.json")"
TEST_N="$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1])).findingCount)" "$WORK/report-$REALM.json")"
TEST_HASH="$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1])).sourceHash)" "$WORK/report-$REALM.json")"
TEST_ENCODED="$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1])).encoded)" "$WORK/report-$REALM.json")"
TEST_RULES="$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1])).findings.map(f=>f.ruleID).sort().join(','))" "$WORK/report-$REALM.json")"
WANT_RULES="$(printf '%s' "$EXPECTED_RULES" | tr ',' '\n' | sort | paste -sd, -)"
[ "$TEST_SCORE" = "$EXPECTED_SCORE" ] && [ "$TEST_RULES" = "$WANT_RULES" ] \
  || { note_fail "Report does not match ground truth (score $TEST_SCORE rules $TEST_RULES; expected $EXPECTED_SCORE rules $WANT_RULES)."; echo "RESULT: FAILED (ground truth)"; exit 1; }
note_pass "Report built with the UI audit port: $REALM_PATH, score $TEST_SCORE, $TEST_N finding(s) ($TEST_RULES), sha256 ${TEST_HASH:0:16}..."

BASELINE_COUNT="$(qeval_int "$RC_REALM.ReportCount()" || echo "")"
[ -n "$BASELINE_COUNT" ] || { note_fail "Could not read ReportCount() from $RC_REALM."; echo "RESULT: FAILED"; exit 1; }
note_pass "Baseline ReportCount() is $BASELINE_COUNT."

# Offline-sign the SubmitReport call.
NAME="submit-$REALM"
UNSIGNED="$WORK/$NAME-unsigned.json"
SIGNED="$WORK/$NAME-signed.json"
BIN="$WORK/$NAME.bin"
OUT="$WORK/$NAME-broadcast.json"
GAS_WANTED=$((10000000 + 7000000 * TEST_N))
GAS_FEE=$((GAS_WANTED / 500))
gnokey maketx call -broadcast=false -pkgpath "$RC_REALM" -func "SubmitReport" \
  -args "$REALM_PATH" -args "$TEST_HASH" -args "$TEST_SCORE" -args "$TEST_ENCODED" \
  -gas-fee "${GAS_FEE}ugnot" -gas-wanted "$GAS_WANTED" \
  -chainid "$CHAINID" -remote "$RPC" -home "$GNOKEY_HOME" "$KEY_NAME" > "$UNSIGNED" 2> "$WORK/$NAME-maketx.err" \
  || { note_fail "gnokey maketx call failed:"; sed 's/^/    /' "$WORK/$NAME-maketx.err" | head -10; echo "RESULT: FAILED"; exit 1; }
ACCT="$(query_account "$DEPLOYER")"
NUM="${ACCT%% *}"; SEQ="${ACCT##* }"
note_info "Signing with account number $NUM, sequence $SEQ (chain id $CHAINID)."
cp "$UNSIGNED" "$SIGNED"
if [ -f "$PASS_FILE" ]; then
  gnokey sign -tx-path "$SIGNED" -account-number "$NUM" -account-sequence "$SEQ" \
    -chainid "$CHAINID" -home "$GNOKEY_HOME" -insecure-password-stdin "$KEY_NAME" \
    < "$PASS_FILE" > "$WORK/$NAME-sign.log" 2>&1 \
    || { note_fail "gnokey sign failed:"; sed 's/^/    /' "$WORK/$NAME-sign.log" | head -10; echo "RESULT: FAILED"; exit 1; }
else
  gnokey sign -tx-path "$SIGNED" -account-number "$NUM" -account-sequence "$SEQ" \
    -chainid "$CHAINID" -home "$GNOKEY_HOME" "$KEY_NAME" \
    > "$WORK/$NAME-sign.log" 2>&1 \
    || { note_fail "gnokey sign failed:"; sed 's/^/    /' "$WORK/$NAME-sign.log" | head -10; echo "RESULT: FAILED"; exit 1; }
fi
B64="$("$TXBIN" "$SIGNED" "$BIN" 2> "$WORK/$NAME-txbin.err")" \
  || { note_fail "txbin failed:"; sed 's/^/    /' "$WORK/$NAME-txbin.err" | head -10; echo "RESULT: FAILED"; exit 1; }
curl -s -m 90 -X POST -H 'Content-Type: application/json' \
  -d "{\"jsonrpc\":\"2.0\",\"id\":\"realmcheck-$NAME\",\"method\":\"broadcast_tx_commit\",\"params\":{\"tx\":\"$B64\"}}" \
  "$RPC/" > "$OUT" 2> "$WORK/$NAME-curl.err" \
  || { note_fail "curl broadcast failed."; echo "RESULT: FAILED"; exit 1; }
CHECK_ERR="$(node -e "const j=JSON.parse(require('fs').readFileSync(process.argv[1],'utf-8'));const e=j.result&&j.result.check_tx&&j.result.check_tx.ResponseBase&&j.result.check_tx.ResponseBase.Error;console.log(e?JSON.stringify(e):'')" "$OUT")"
DELIVER_ERR="$(node -e "const j=JSON.parse(require('fs').readFileSync(process.argv[1],'utf-8'));const e=j.result&&j.result.deliver_tx&&j.result.deliver_tx.ResponseBase&&j.result.deliver_tx.ResponseBase.Error;console.log(e?JSON.stringify(e):'')" "$OUT")"
if [ -n "$CHECK_ERR" ] || [ -n "$DELIVER_ERR" ]; then
  note_fail "Node refused the transaction. check_tx: $CHECK_ERR deliver_tx: $DELIVER_ERR"
  echo "RESULT: FAILED"; exit 1
fi
TX_GAS="$(node -e "const j=JSON.parse(require('fs').readFileSync(process.argv[1],'utf-8'));console.log(j.result&&j.result.deliver_tx&&j.result.deliver_tx.GasUsed||'')" "$OUT")"
TX_HEIGHT="$(node -e "const j=JSON.parse(require('fs').readFileSync(process.argv[1],'utf-8'));console.log(j.result&&j.result.height||'')" "$OUT")"
TX_HASH="$(node -e "const j=JSON.parse(require('fs').readFileSync(process.argv[1],'utf-8'));console.log(j.result&&j.result.hash||'')" "$OUT")"
note_pass "SubmitReport broadcast (gas wanted $GAS_WANTED, used ${TX_GAS:-unknown}, height ${TX_HEIGHT:-unknown}, tx ${TX_HASH:-unknown})."

# Verify the stored report reads back.
export VITE_GNO_RPC="$RPC"
export REALMCHECK_REALM="$RC_REALM"
AFTER_COUNT="$(qeval_int "$RC_REALM.ReportCount()" || echo "")"
[ "$AFTER_COUNT" = "$((BASELINE_COUNT + 1))" ] \
  || { note_fail "ReportCount() is $AFTER_COUNT after submit, expected $((BASELINE_COUNT + 1))."; echo "RESULT: FAILED"; exit 1; }
note_pass "ReportCount() is $AFTER_COUNT after submit (was $BASELINE_COUNT)."
NEW_ID="$AFTER_COUNT"
LATEST_JSON="$(node "$WORK/read-report.mjs" latest "$REALM_PATH" 2>/dev/null || echo "null")"
LATEST_ID="$(printf '%s' "$LATEST_JSON" | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{try{console.log(JSON.parse(s).id)}catch{console.log('')}})")"
LATEST_SCORE="$(printf '%s' "$LATEST_JSON" | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{try{console.log(JSON.parse(s).score)}catch{console.log('')}})")"
LATEST_AUDITOR="$(printf '%s' "$LATEST_JSON" | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{try{console.log(JSON.parse(s).auditor)}catch{console.log('')}})")"
[ "$LATEST_ID" = "$NEW_ID" ] && [ "$LATEST_SCORE" = "$EXPECTED_SCORE" ] && [ "$LATEST_AUDITOR" = "$DEPLOYER" ] \
  || { note_fail "LatestReport mismatch: id $LATEST_ID (expected $NEW_ID), score $LATEST_SCORE (expected $EXPECTED_SCORE), auditor $LATEST_AUDITOR (expected $DEPLOYER)."; echo "RESULT: FAILED"; exit 1; }
note_pass "LatestReport($REALM_PATH) is report #$NEW_ID, score $EXPECTED_SCORE, auditor $DEPLOYER."
STORED_FINDINGS="$(node "$WORK/read-report.mjs" findings "$NEW_ID" 2>/dev/null || echo "[]")"
for rule in $(printf '%s' "$EXPECTED_RULES" | tr ',' ' '); do
  printf '%s' "$STORED_FINDINGS" | grep -q "\"ruleID\":\"$rule\"" \
    || { note_fail "ReportFindings($NEW_ID) does not contain $rule: $STORED_FINDINGS"; echo "RESULT: FAILED"; exit 1; }
done
note_pass "ReportFindings($NEW_ID) contains all expected rules ($EXPECTED_RULES)."
echo "=== Summary ==="
echo "Report #$NEW_ID for $REALM_PATH, score $EXPECTED_SCORE, auditor $DEPLOYER, tx ${TX_HASH:-unknown}, height ${TX_HEIGHT:-unknown}, gas used ${TX_GAS:-unknown}."
echo "View: https://onyx.testnets.gno.land/r/$DEPLOYER/realmcheck"
if [ "$FAILURES" -eq 0 ]; then echo "RESULT: PASSED"; exit 0; else echo "RESULT: FAILED ($FAILURES failure(s))"; exit 1; fi
