#!/usr/bin/env bash
# run-audit-local.sh: the RealmCheck agent-mode audit, run end to end.
#
# This is the runnable form of agent/SKILL.md against a LOCAL gnodev
# chain (chain ID dev). It audits adminbackdoor only, the demo realm
# with the richest ground truth (score 37, 4 findings), and stores the
# report on chain with SubmitReport. It is the M5 proof run.
#
# Steps, in skill order:
#   (a) start a fresh local gnodev chain, deploy vulnmint (adminbackdoor
#       imports it) and adminbackdoor from staged byte-identical copies;
#   (b) read the adminbackdoor source from the chain with vm/qfile and
#       audit the fetched text with the JS port (agent/audit.mjs);
#   (c) cross-check the findings with the real Gno Audit() through the
#       project's existing driver (node scripts/e2e-local.mjs audit),
#       which owns its own temporary test and deletes it afterwards;
#   (d) submit the report with gnokey maketx call (SubmitReport,
#       gas-wanted 10,000,000 + 7,000,000 per finding, gas-fee
#       gas-wanted / 500, chain ID dev);
#   (e) verify the stored report with agent/verify-report.mjs
#       (GetReport, ReportFindings, LatestReport, ReportCount, Render,
#       and the gnoweb report page).
#
# The gnomcp path is NOT used here: gnomcp could not be built or run on
# this VM (see M5-AGENT-STATUS.md), so this script is the documented
# fallback path, gnokey plus node, and the skill documents it as such.
# No money is spent and nothing leaves the local chain.
#
# Run from the project root:  bash agent/run-audit-local.sh
# Full output is also written to agent/m5-agent-run.log.
# Exit code 0 means every step passed.

set -u

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT="$PROJECT/agent"
LOG="$AGENT/m5-agent-run.log"
WORK="$AGENT/m5-work"
STAGE="$AGENT/stage"
KEY_NAME="realmcheck-dev"
KEY_ADDR="g1yzqhuxczln72kwm9pstcmjerhnu0uverkuyz4h"
REALMCHECK_REALM="gno.land/r/dunoil/realmcheck"
REALM="adminbackdoor"
REALM_PATH="gno.land/r/dunoil/$REALM"

# Self-tee: on the outer invocation, re-run inner with output teed to the log.
if [ -z "${M5_INNER:-}" ]; then
  mkdir -p "$AGENT"
  M5_INNER=1 bash "$0" "$@" 2>&1 | tee "$LOG"
  exit "${PIPESTATUS[0]}"
fi

export PATH="$PATH:$HOME/workspace/tools/go/bin:$HOME/workspace/tools/gno/bin"
export GNOROOT="$HOME/workspace/tools/gno"
export GOMAXPROCS=2

FAILURES=0
GNODEV_PID=""
RPC_PORT=""
WEB_PORT=""

note_pass() { echo "PASS $1"; }
note_fail() { echo "FAIL $1"; FAILURES=$((FAILURES + 1)); }
note_info() { echo "INFO $1"; }

cleanup() {
  if [ -n "${GNODEV_PID:-}" ] && kill -0 "$GNODEV_PID" 2>/dev/null; then
    kill "$GNODEV_PID" 2>/dev/null || true
    wait "$GNODEV_PID" 2>/dev/null || true
    note_info "Stopped gnodev (pid $GNODEV_PID)."
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

echo "=== RealmCheck agent-mode audit run (M5) ==="
echo "Project: $PROJECT"
echo "Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "Realm under audit: $REALM_PATH (expected score 37, 4 findings)"
echo "Path used: gnokey plus node fallback (gnomcp not runnable on this VM, see M5-AGENT-STATUS.md)"
for bin in gno gnokey gnodev node curl jq python3; do
  command -v "$bin" >/dev/null 2>&1 || { note_fail "Required tool missing from PATH: $bin"; }
done
[ "$FAILURES" -gt 0 ] && { echo "RESULT: FAILED (missing tools)"; exit 1; }
gnokey list 2>/dev/null | grep -q "$KEY_ADDR" || note_fail "Local dev key $KEY_NAME ($KEY_ADDR) not found in gnokey list."
[ "$FAILURES" -gt 0 ] && { echo "RESULT: FAILED (key check)"; exit 1; }
note_pass "Toolchain and local dev key $KEY_NAME ($KEY_ADDR) present."

# --- Step 0: pick ports and start our own gnodev ---------------------------
# Never kill a chain we did not start: if 26657 already answers, use
# alternate ports 26658 / 8889 for our own chain instead.
if curl -s -o /dev/null -m 3 http://127.0.0.1:26657/status 2>/dev/null; then
  note_info "Port 26657 already answers (another chain, left alone). Using alternate ports 26658 / 8889 for our own chain."
  RPC_PORT=26658
  WEB_PORT=8889
  if curl -s -o /dev/null -m 3 http://127.0.0.1:26658/status 2>/dev/null; then
    note_fail "Alternate port 26658 is also busy. Stop the stray gnodev on 26658 and re-run."
    echo "RESULT: FAILED (no free port)"; exit 1
  fi
else
  RPC_PORT=26657
  WEB_PORT=8888
fi
RPC="http://127.0.0.1:$RPC_PORT"
WEB="http://127.0.0.1:$WEB_PORT"
note_info "Using RPC $RPC, gnoweb $WEB."

mkdir -p "$WORK"
rm -rf "$STAGE"
cd "$PROJECT/contracts"
gnodev local -add-account "$KEY_ADDR=100000000ugnot" \
  -node-rpc-listener "127.0.0.1:$RPC_PORT" -web-listener "127.0.0.1:$WEB_PORT" \
  > "$AGENT/gnodev-m5.log" 2>&1 &
GNODEV_PID=$!
echo "$GNODEV_PID" > "$WORK/gnodev.pid"
note_info "Started gnodev (pid $GNODEV_PID), log agent/gnodev-m5.log."
wait_http "$RPC/status" 120 "Local chain RPC" || { echo "RESULT: FAILED (chain did not start)"; exit 1; }
wait_http "$WEB/" 60 "Local gnoweb" || { echo "RESULT: FAILED (gnoweb did not start)"; exit 1; }

# --- Step 0b: baseline report count ---------------------------------------
# The node answers /status before the VM can serve qeval (first query
# can 502 for about 13 seconds after start), so retry a few times.
COUNT_BEFORE=""
for _try in 1 2 3 4 5 6; do
  COUNT_BEFORE="$(gnokey query vm/qeval -data "$REALMCHECK_REALM.ReportCount()" -remote "127.0.0.1:$RPC_PORT" 2>/dev/null | grep -oE '\([0-9]+ int\)' | grep -oE '[0-9]+' | head -1)"
  [ -n "${COUNT_BEFORE:-}" ] && break
  sleep 5
done
if [ -z "${COUNT_BEFORE:-}" ]; then
  note_fail "Could not read ReportCount() from the fresh chain (realmcheck realm not reachable?)."
  echo "RESULT: FAILED (ReportCount unreadable)"; exit 1
fi
note_pass "Baseline ReportCount() is $COUNT_BEFORE on the fresh chain (expected 0)."

# --- Step 1: stage and deploy the demo realms ------------------------------
# Only the .gno source and gnomod.toml are staged: the stale gno.mod in
# contracts/demo/*/ makes the chain reject addpkg. Deploy order is
# vulnmint first: adminbackdoor imports vulnmint. contracts/** is never
# edited by this script.
for realm in vulnmint adminbackdoor; do
  mkdir -p "$STAGE/$realm"
  cp "$PROJECT/contracts/demo/$realm/$realm.gno" "$PROJECT/contracts/demo/$realm/gnomod.toml" "$STAGE/$realm/"
  cmp -s "$PROJECT/contracts/demo/$realm/$realm.gno" "$STAGE/$realm/$realm.gno" \
    && note_pass "Staged $realm source is byte-identical to contracts/demo/$realm/$realm.gno." \
    || note_fail "Staged $realm source differs from contracts/demo/$realm/$realm.gno."
done
[ "$FAILURES" -gt 0 ] && { echo "RESULT: FAILED (staging)"; exit 1; }

for realm in vulnmint adminbackdoor; do
  out_file="$WORK/addpkg-$realm.txt"
  printf 'devpass\n' | gnokey maketx addpkg -insecure-password-stdin \
    -pkgpath "gno.land/r/dunoil/$realm" -pkgdir "$STAGE/$realm" \
    -gas-fee 40000ugnot -gas-wanted 20000000 -chainid dev \
    -remote "127.0.0.1:$RPC_PORT" "$KEY_NAME" > "$out_file" 2>&1
  if grep -q -- "--= Error" "$out_file" || grep -q "invalid package" "$out_file"; then
    note_fail "addpkg $realm failed. See $out_file:"
    sed 's/^/    /' "$out_file" | head -20
  else
    gas="$(grep -oE 'GAS USED: +[0-9]+' "$out_file" | grep -oE '[0-9]+' | head -1)"
    height="$(grep -oE 'HEIGHT: +[0-9]+' "$out_file" | grep -oE '[0-9]+' | head -1)"
    txhash="$(grep -oE 'TX HASH: +[^ ]+' "$out_file" | awk '{print $3}' | head -1)"
    note_pass "addpkg $realm succeeded (gas used ${gas:-unknown}, height ${height:-unknown}, tx ${txhash:-unknown})."
  fi
done
[ "$FAILURES" -gt 0 ] && { echo "RESULT: FAILED (addpkg)"; exit 1; }

# --- Step (a)(b): chain source read, JS port audit --------------------------
echo "--- Skill step (a)(b): vm/qfile source read, JS port audit ---"
cd "$PROJECT"
node agent/audit.mjs --rpc "$RPC" --realm "$REALM_PATH" --file "$REALM.gno" \
  --local "contracts/demo/$REALM/$REALM.gno" --out "$WORK/$REALM.json" || {
  note_fail "Agent audit step failed (see above)."
  echo "RESULT: FAILED (audit)"; exit 1
}
# The skill's expected result for adminbackdoor: score 37, 4 findings.
agent_score="$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1])).score)" "$WORK/$REALM.json")"
agent_nfindings="$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1])).findings.length)" "$WORK/$REALM.json")"
if [ "$agent_score" = "37" ] && [ "$agent_nfindings" = "4" ]; then
  note_pass "JS port audit of $REALM gives the expected ground truth: score 37, 4 findings."
else
  note_fail "JS port audit of $REALM gives score $agent_score with $agent_nfindings finding(s), expected score 37 with 4 findings."
  echo "RESULT: FAILED (ground truth)"; exit 1
fi

# --- Step (b) cross-check: real Gno Audit() --------------------------------
echo "--- Skill step (b) cross-check: real Gno Audit() via scripts/e2e-local.mjs audit ---"
node scripts/e2e-local.mjs audit --rpc "$RPC" || {
  note_fail "Gno Audit() cross-check driver failed (see above)."
  echo "RESULT: FAILED (Gno cross-check)"; exit 1
}
gno_score="$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1])).score)" "$PROJECT/scripts/e2e-work/$REALM.json")"
gno_keys="$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1])).findings.map(f=>[f.ruleID,f.severity,f.line,f.title].join('|')).sort().join(';'))" "$PROJECT/scripts/e2e-work/$REALM.json")"
agent_keys="$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1])).findings.map(f=>[f.ruleID,f.severity,f.line,f.title].join('|')).sort().join(';'))" "$WORK/$REALM.json")"
if [ "$gno_score" = "$agent_score" ] && [ "$gno_keys" = "$agent_keys" ]; then
  note_pass "Gno Audit() agrees with the JS port exactly: score $gno_score, findings $gno_keys."
else
  note_fail "Gno Audit() differs from the JS port. Gno score $gno_score findings $gno_keys; JS score $agent_score findings $agent_keys."
  echo "RESULT: FAILED (Gno cross-check mismatch)"; exit 1
fi

# --- Step (c): submit the report on chain ----------------------------------
echo "--- Skill step (c): SubmitReport ---"
source_hash="$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1])).sourceHash)" "$WORK/$REALM.json")"
score="$agent_score"
nfindings="$agent_nfindings"
encoded="$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1])).encoded)" "$WORK/$REALM.json")"
# Gas scales with findings (measured: 1 finding 8,904,806 gas, 4 findings
# 26,292,230 gas). Fee stays twice the chain minimum.
gas_wanted=$((10000000 + 7000000 * nfindings))
gas_fee=$((gas_wanted / 500))
note_info "SubmitReport $REALM: score $score, $nfindings findings, gas-wanted $gas_wanted, gas-fee ${gas_fee}ugnot."
out_file="$WORK/submit-$REALM.txt"
attempt=0
submit_ok=0
while [ "$attempt" -lt 3 ] && [ "$submit_ok" -eq 0 ]; do
  attempt=$((attempt + 1))
  printf 'devpass\n' | gnokey maketx call -insecure-password-stdin \
    -pkgpath "$REALMCHECK_REALM" -func "SubmitReport" \
    -args "$REALM_PATH" -args "$source_hash" -args "$score" -args "$encoded" \
    -gas-fee "${gas_fee}ugnot" -gas-wanted "$gas_wanted" -chainid dev \
    -remote "127.0.0.1:$RPC_PORT" "$KEY_NAME" > "$out_file" 2>&1
  if grep -q -- "--= Error" "$out_file" || grep -q "success:false" "$out_file"; then
    if grep -q "502" "$out_file" || grep -q "unable to call RPC" "$out_file"; then
      note_info "SubmitReport $REALM attempt $attempt hit an RPC error (chain still settling). Retrying in 5s."
      sleep 5
      continue
    fi
    note_fail "SubmitReport $REALM failed (gas-wanted $gas_wanted, gas-fee ${gas_fee}ugnot). See $out_file:"
    sed 's/^/    /' "$out_file" | head -20
    break
  fi
  submit_ok=1
done
[ "$submit_ok" -eq 1 ] || { echo "RESULT: FAILED (submit)"; exit 1; }
gas_used="$(grep -oE 'GAS USED: +[0-9]+' "$out_file" | grep -oE '[0-9]+' | head -1)"
txhash="$(grep -oE 'TX HASH: +[^ ]+' "$out_file" | awk '{print $3}' | head -1)"
maketx_id="$(grep -oE '\([0-9]+ int\)' "$out_file" | head -1 | grep -oE '[0-9]+')"
maketx_height="$(grep -oE 'HEIGHT: +[0-9]+' "$out_file" | grep -oE '[0-9]+' | head -1)"
# Authoritative ID and height: the just-stored report is the latest for
# this realm.
latest_json="$(node scripts/e2e-local.mjs latest --rpc "$RPC" --realm "$REALM_PATH" 2>/dev/null)"
report_id="$(echo "$latest_json" | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{try{console.log(JSON.parse(s).id)}catch{console.log('')}})")"
height="$(echo "$latest_json" | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{try{console.log(JSON.parse(s).height)}catch{console.log('')}})")"
if [ -n "${maketx_id:-}" ] && [ "${maketx_id:-}" != "${report_id:-}" ]; then
  note_fail "SubmitReport $REALM: maketx returned ID $maketx_id but LatestReport says $report_id."
  echo "RESULT: FAILED (submit)"; exit 1
fi
if [ -n "${maketx_height:-}" ] && [ "${maketx_height:-}" != "${height:-}" ]; then
  note_fail "SubmitReport $REALM: maketx height $maketx_height but LatestReport height $height."
  echo "RESULT: FAILED (submit)"; exit 1
fi
if [ -z "${report_id:-}" ]; then
  note_fail "SubmitReport $REALM: could not read the new report ID back with LatestReport."
  echo "RESULT: FAILED (submit)"; exit 1
fi
note_pass "SubmitReport $REALM stored as report ID $report_id (score $score, gas wanted $gas_wanted, gas used ${gas_used:-unknown}, height ${height:-unknown}, tx ${txhash:-unknown})."
cat > "$WORK/report.json" <<EOF
{
  "realm": "$REALM",
  "realmPath": "$REALM_PATH",
  "reportId": $report_id,
  "height": ${height:-0},
  "gasWanted": $gas_wanted,
  "gasFeeUgnot": $gas_fee,
  "gasUsed": ${gas_used:-null},
  "txHash": "${txhash:-}",
  "auditor": "$KEY_ADDR",
  "score": $score,
  "sourceHash": "$source_hash"
}
EOF

# --- Step (d): verify the stored report ------------------------------------
echo "--- Skill step (d): verify the stored report ---"
expected_count=$((COUNT_BEFORE + 1))
node agent/verify-report.mjs --rpc "$RPC" --web "$WEB" --work "$WORK/$REALM.json" \
  --id "$report_id" --height "$height" --count "$expected_count" --auditor "$KEY_ADDR" || {
  note_fail "Verify step failed (see above)."
  echo "RESULT: FAILED (verify)"; exit 1
}

# --- Summary -----------------------------------------------------------------
echo "=== Summary ==="
echo "Chain: $RPC (gnoweb $WEB), fresh local chain started and stopped by this run."
echo "Realm audited: $REALM_PATH"
echo "Report #$report_id: score $score, $nfindings finding(s), gas wanted $gas_wanted, gas used ${gas_used:-unknown}, height ${height:-unknown}, tx ${txhash:-unknown}"
echo "Auditor: $KEY_ADDR ($KEY_NAME)"
echo "Source SHA-256: $source_hash"
echo "Work files: $WORK/$REALM.json, $WORK/report.json; full log: $LOG"
if [ "$FAILURES" -eq 0 ]; then
  echo "RESULT: PASSED"
  exit 0
else
  echo "RESULT: FAILED ($FAILURES failure(s))"
  exit 1
fi
