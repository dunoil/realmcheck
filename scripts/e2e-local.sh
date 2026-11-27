#!/usr/bin/env bash
# e2e-local.sh: re-runnable local end-to-end harness for RealmCheck.
#
# Proves the whole product loop on a local gnodev chain, with no Onyx
# dependency and no money spent:
#   1. Starts its own gnodev local chain (contracts workspace).
#   2. Deploys the two demo realms (vulnmint, adminbackdoor) with
#      gnokey maketx addpkg, from a staged copy under
#      scripts/e2e-work-stage/ (see the staging note below).
#   3. Runs scripts/e2e-local.mjs audit: vm/qfile source read, real Gno
#      Audit() via a temporary test, JS port audit, all compared against
#      ui/scripts/expected-findings.json.
#   4. Submits both audit reports on chain with gnokey maketx call
#      (SubmitReport, chain ID dev). Gas scales with the finding count:
#      a 1-finding report used 7,854,767 gas, a 3-finding report used
#      20,443,214, so gas-wanted is 10,000,000 plus 7,000,000 per finding
#      and gas-fee is gas-wanted divided by 500 (twice the 1 ugnot per
#      1,000 gas minimum). The flat 10,000,000 in docs/API.md only covers
#      one finding; see M4-E2E-STATUS.md for the requested doc fix.
#   5. Runs scripts/e2e-local.mjs verify: GetReport, ReportFindings,
#      LatestReport, ReportCount, Render(""), and the gnoweb report page.
#   6. Starts the UI dev server with the local endpoints configured and
#      checks it serves HTTP 200 (bound to 127.0.0.1 explicitly: Vite's
#      default localhost bind is unreachable by curl to 127.0.0.1 on
#      this VM), then runs scripts/ui-local-audit.mjs, which executes
#      the UI's own fetchRealmFiles + audit.js code path under node
#      against the local chain. The in-browser click-through stays a
#      manual step in tests/e2e-local-checklist.md.
#      When the UI agent has NOT landed configurable endpoints
#      (VITE_GNO_RPC, VITE_GNOWEB, VITE_REALMCHECK_REALM), the dev
#      server is started with the defaults and the local-RPC UI checks
#      are recorded as pending instead of failing the run.
#
# Staging note: contracts/demo/*/ still ships a stale gno.mod file next
# to gnomod.toml, and the chain rejects addpkg for such a package with
# "gno.mod file is deprecated and not allowed" (verified live). The
# harness therefore stages a copy holding only the .gno source and
# gnomod.toml, byte-identical source, and deploys that. The requested fix
# is in M4-E2E-STATUS.md: delete the stale gno.mod files in the demo
# dirs, after which the staging step can go away. contracts/** is never
# edited by this harness.
#
# Port note: the harness never kills a chain it did not start. If
# 127.0.0.1:26657 already answers (another agent's gnodev), the harness
# starts its own chain on 127.0.0.1:26658 / gnoweb 127.0.0.1:8889
# instead, and stops only that chain at the end. If both ports are busy
# it stops and says so.
#
# Idempotency: every run starts a fresh local chain, so report IDs start
# over and no leftover state can fail a second run. A second run in a
# row must pass exactly like the first.
#
# Run from the project root:  bash scripts/e2e-local.sh
# Full output is also written to scripts/e2e-local-last-run.log.
# Exit code 0 means every step passed, except the UI local-RPC check,
# which is pending until the UI env vars land and does not fail the run.
# E2E_CONTINUE_ON_AUDIT_MISMATCH=1 lets the run continue past a
# Gno-vs-JS-port (or Gno-vs-expected-findings.json) mismatch and submit
# the real Gno Audit() findings anyway, with the mismatch recorded as a
# FAIL in the log. Use it when another agent has changed the rules and
# the port has not caught up yet; the default (unset) fails fast.

set -u

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$PROJECT/scripts/e2e-local-last-run.log"
WORK="$PROJECT/scripts/e2e-work"
STAGE="$PROJECT/scripts/e2e-work-stage"
KEY_NAME="realmcheck-dev"
KEY_ADDR="g1yzqhuxczln72kwm9pstcmjerhnu0uverkuyz4h"
REALMCHECK_REALM="gno.land/r/dunoil/realmcheck"
UI_PORT=5173

# Self-tee: on the outer invocation, re-run inner with output teed to the log.
if [ -z "${E2E_INNER:-}" ]; then
  mkdir -p "$PROJECT/scripts"
  E2E_INNER=1 "$0" "$@" 2>&1 | tee "$LOG"
  exit "${PIPESTATUS[0]}"
fi

export PATH="$PATH:$HOME/workspace/tools/go/bin:$HOME/workspace/tools/gno/bin"
export GNOROOT="$HOME/workspace/tools/gno"
export GOMAXPROCS=2

FAILURES=0
GNODEV_PID=""
VITE_PID=""
RPC_PORT=""
WEB_PORT=""
UI_LOCAL_RPC="pending"

note_pass() { echo "PASS $1"; }
note_fail() { echo "FAIL $1"; FAILURES=$((FAILURES + 1)); }
note_info() { echo "INFO $1"; }

cleanup() {
  if [ -n "${VITE_PID:-}" ] && kill -0 "$VITE_PID" 2>/dev/null; then
    kill "$VITE_PID" 2>/dev/null || true
    wait "$VITE_PID" 2>/dev/null || true
    note_info "Stopped UI dev server (pid $VITE_PID)."
  fi
  if [ -n "${GNODEV_PID:-}" ] && kill -0 "$GNODEV_PID" 2>/dev/null; then
    kill "$GNODEV_PID" 2>/dev/null || true
    wait "$GNODEV_PID" 2>/dev/null || true
    note_info "Stopped gnodev (pid $GNODEV_PID)."
  fi
  # Belt and braces: the audit driver deletes its temp test itself, but
  # never leave one behind if the run died mid-step.
  rm -f "$PROJECT/contracts/realmcheck/e2e_audit_test.gno"
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

echo "=== RealmCheck local end-to-end harness ==="
echo "Project: $PROJECT"
echo "Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
for bin in gno gnokey gnodev node npm curl jq python3; do
  command -v "$bin" >/dev/null 2>&1 || { note_fail "Required tool missing from PATH: $bin"; }
done
[ "$FAILURES" -gt 0 ] && { echo "RESULT: FAILED (missing tools)"; exit 1; }
gnokey list 2>/dev/null | grep -q "$KEY_ADDR" || note_fail "Local dev key $KEY_NAME ($KEY_ADDR) not found in gnokey list."
[ "$FAILURES" -gt 0 ] && { echo "RESULT: FAILED (key check)"; exit 1; }
note_pass "Toolchain and local dev key $KEY_NAME ($KEY_ADDR) present."

# --- Step 0: pick ports and start our own gnodev ---------------------------
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
  > "$PROJECT/scripts/gnodev-e2e.log" 2>&1 &
GNODEV_PID=$!
echo "$GNODEV_PID" > "$WORK/gnodev.pid"
note_info "Started gnodev (pid $GNODEV_PID), log scripts/gnodev-e2e.log."
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
# See the staging note at the top of this file: only the .gno source and
# gnomod.toml are staged, because the stale gno.mod in contracts/demo/*/
# makes the chain reject addpkg. Deploy order is vulnmint first:
# adminbackdoor imports vulnmint.
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

# --- Steps (a)(b)(c): chain source read, Gno Audit, JS port audit ----------
echo "--- Audit driver: vm/qfile, Gno Audit(), JS port audit ---"
cd "$PROJECT"
AUDIT_ARGS=""
if [ "${E2E_CONTINUE_ON_AUDIT_MISMATCH:-0}" = "1" ]; then
  AUDIT_ARGS="--continue-on-mismatch"
  note_info "E2E_CONTINUE_ON_AUDIT_MISMATCH=1: audit mismatches will be recorded but will not stop the run; Gno Audit() is the truth for the reports."
fi
node scripts/e2e-local.mjs audit --rpc "$RPC" $AUDIT_ARGS || {
  note_fail "Audit driver failed (see above)."
  echo "RESULT: FAILED (audit driver)"; exit 1
}

# --- Step (d): submit both reports on chain --------------------------------
echo "--- Submitting reports with SubmitReport ---"
: > "$WORK/submits.txt"
for realm in vulnmint adminbackdoor; do
  realm_path="gno.land/r/dunoil/$realm"
  source_hash="$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1])).sourceHash)" "$WORK/$realm.json")"
  score="$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1])).score)" "$WORK/$realm.json")"
  nfindings="$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1])).findings.length)" "$WORK/$realm.json")"
  encoded="$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1])).encoded)" "$WORK/$realm.json")"
  # Gas scales with findings (measured: 1 finding 7,854,767 gas,
  # 3 findings 20,443,214 gas). Fee stays twice the chain minimum.
  gas_wanted=$((10000000 + 7000000 * nfindings))
  gas_fee=$((gas_wanted / 500))
  out_file="$WORK/submit-$realm.txt"
  attempt=0
  submit_ok=0
  while [ "$attempt" -lt 3 ] && [ "$submit_ok" -eq 0 ]; do
    attempt=$((attempt + 1))
    printf 'devpass\n' | gnokey maketx call -insecure-password-stdin \
      -pkgpath "$REALMCHECK_REALM" -func "SubmitReport" \
      -args "$realm_path" -args "$source_hash" -args "$score" -args "$encoded" \
      -gas-fee "${gas_fee}ugnot" -gas-wanted "$gas_wanted" -chainid dev \
      -remote "127.0.0.1:$RPC_PORT" "$KEY_NAME" > "$out_file" 2>&1
    if grep -q -- "--= Error" "$out_file" || grep -q "success:false" "$out_file"; then
      if grep -q "502" "$out_file" || grep -q "unable to call RPC" "$out_file"; then
        note_info "SubmitReport $realm attempt $attempt hit an RPC error (chain still settling). Retrying in 5s."
        sleep 5
        continue
      fi
      note_fail "SubmitReport $realm failed (gas-wanted $gas_wanted, gas-fee ${gas_fee}ugnot). See $out_file:"
      sed 's/^/    /' "$out_file" | head -20
      break
    fi
    submit_ok=1
  done
  [ "$submit_ok" -eq 0 ] && continue
  gas="$(grep -oE 'GAS USED: +[0-9]+' "$out_file" | grep -oE '[0-9]+' | head -1)"
  txhash="$(grep -oE 'TX HASH: +[^ ]+' "$out_file" | awk '{print $3}' | head -1)"
  # Authoritative ID and height: the just-stored report is the latest for
  # this realm. Parsed with the same printer parser the verify driver
  # uses (node), because grepping the printed struct for int64 values
  # proved unreliable: the print contains a second int64-looking value.
  latest_json="$(node scripts/e2e-local.mjs latest --rpc "$RPC" --realm "$realm_path" 2>/dev/null)"
  report_id="$(echo "$latest_json" | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{try{console.log(JSON.parse(s).id)}catch{console.log('')}})")"
  height="$(echo "$latest_json" | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{try{console.log(JSON.parse(s).height)}catch{console.log('')}})")"
  maketx_id="$(grep -oE '\([0-9]+ int\)' "$out_file" | head -1 | grep -oE '[0-9]+')"
  maketx_height="$(grep -oE 'HEIGHT: +[0-9]+' "$out_file" | grep -oE '[0-9]+' | head -1)"
  if [ -n "${maketx_id:-}" ] && [ "${maketx_id:-}" != "${report_id:-}" ]; then
    note_fail "SubmitReport $realm: maketx returned ID $maketx_id but LatestReport says $report_id."
    continue
  fi
  if [ -n "${maketx_height:-}" ] && [ "${maketx_height:-}" != "${height:-}" ]; then
    note_fail "SubmitReport $realm: maketx height $maketx_height but LatestReport height $height."
    continue
  fi
  if [ -z "${report_id:-}" ]; then
    note_fail "SubmitReport $realm: could not read the new report ID back with LatestReport."
    continue
  fi
  echo "$realm|$report_id|$height|$gas|$txhash" >> "$WORK/submits.txt"
  note_pass "SubmitReport $realm stored as report ID $report_id (score $score, gas wanted $gas_wanted, gas used ${gas:-unknown}, height ${height:-unknown}, tx ${txhash:-unknown})."
done
[ "$FAILURES" -gt 0 ] && { echo "RESULT: FAILED (submit)"; exit 1; }
[ "$(wc -l < "$WORK/submits.txt")" -eq 2 ] || { note_fail "Expected 2 submitted reports, got $(wc -l < "$WORK/submits.txt")."; echo "RESULT: FAILED (submit)"; exit 1; }

python3 - "$WORK" "$COUNT_BEFORE" "$KEY_ADDR" <<'PYEOF'
import json, sys
work, count_before, auditor = sys.argv[1], int(sys.argv[2]), sys.argv[3]
reports = []
for line in open(f"{work}/submits.txt"):
    realm, rid, height, gas, tx = line.strip().split("|")
    reports.append({"realm": realm, "reportId": int(rid), "height": int(height),
                    "gasUsed": int(gas) if gas else None, "txHash": tx, "auditor": auditor})
json.dump({"countBefore": count_before, "reports": reports},
          open(f"{work}/reports.json", "w"), indent=2)
print(f"wrote {work}/reports.json")
PYEOF

# --- Step (e)(f): read the stored reports back, check Render ---------------
echo "--- Verifying stored reports and Render ---"
node scripts/e2e-local.mjs verify --rpc "$RPC" --web "$WEB" || {
  note_fail "Verify driver failed (see above)."
  echo "RESULT: FAILED (verify)"; exit 1
}

# --- Step 2: UI dev server against the local chain --------------------------
# Two checks: (1) the Vite dev server serves HTTP 200 with the local
# endpoints configured; (2) scripts/ui-local-audit.mjs runs the UI's own
# fetchRealmFiles + audit.js code path under node against the local
# chain. The in-browser click-through stays a manual step in
# tests/e2e-local-checklist.md (it needs a real browser), and it must
# use the search box or ?realm= deep link, not the demo buttons: the
# demo buttons audit bundled public/demo-sources files and never touch
# the chain.
# Vite binds to localhost by default, which curl to 127.0.0.1 cannot
# reach on this VM, so the dev server is started with --host 127.0.0.1.
# Vite is started directly (node_modules/.bin/vite), not through
# `npm run dev`: npm spawns vite as a child, and killing the npm process
# leaves the vite child orphaned on port 5173 (this happened on the
# 27 Nov 14:10 WITA run, pid 22592). Starting vite directly makes
# $VITE_PID the server itself, so cleanup really stops it. Before
# starting, orphaned vite processes for this project (parent pid 1,
# working directory ui/) are reaped; a live server owned by another
# agent (live parent) is never touched.
reap_orphaned_vite() {
  for pid in $(pgrep -f "node_modules/.bin/vite" 2>/dev/null || true); do
    ppid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
    cwd="$(readlink "/proc/$pid/cwd" 2>/dev/null)"
    if [ "$ppid" = "1" ] && [ "$cwd" = "$PROJECT/ui" ]; then
      note_info "Reaping orphaned vite process $pid from an earlier run (parent gone, cwd ui/)."
      kill "$pid" 2>/dev/null || true
    fi
  done
  sleep 1
}
echo "--- UI dev server check ---"
cd "$PROJECT/ui"
reap_orphaned_vite
UI_SERVE="failed"
VITE_BIN="$PROJECT/ui/node_modules/.bin/vite"
if grep -rqE "VITE_GNO_RPC|VITE_GNOWEB|VITE_REALMCHECK_REALM" src vite.config.ts 2>/dev/null; then
  UI_LOCAL_RPC="configured"
  note_info "UI reads VITE_GNO_RPC / VITE_GNOWEB / VITE_REALMCHECK_REALM. Starting dev server pointed at the local chain ($RPC, $WEB)."
  VITE_GNO_RPC="$RPC" VITE_GNOWEB="$WEB" VITE_REALMCHECK_REALM="$REALMCHECK_REALM" \
    "$VITE_BIN" --host 127.0.0.1 --port "$UI_PORT" --strictPort > "$WORK/vite-dev.log" 2>&1 &
else
  UI_LOCAL_RPC="pending"
  note_info "UI env vars (VITE_GNO_RPC, VITE_GNOWEB, VITE_REALMCHECK_REALM) have NOT landed yet (ui/src/lib/gnoRpc.js still hardcodes Onyx). Starting dev server with defaults to check it serves; the local-RPC UI check stays pending on the UI agent."
  "$VITE_BIN" --host 127.0.0.1 --port "$UI_PORT" --strictPort > "$WORK/vite-dev.log" 2>&1 &
fi
VITE_PID=$!
if wait_http "http://127.0.0.1:$UI_PORT/" 60 "UI dev server"; then
  code="$(curl -s -o /dev/null -w '%{http_code}' -m 5 "http://127.0.0.1:$UI_PORT/")"
  if [ "$code" = "200" ]; then
    UI_SERVE="HTTP 200"
    note_pass "UI dev server serves HTTP 200 on http://127.0.0.1:$UI_PORT/ (local-RPC config: $UI_LOCAL_RPC)."
  else
    note_fail "UI dev server answered HTTP $code, expected 200."
  fi
else
  note_fail "UI dev server log tail:"
  tail -20 "$WORK/vite-dev.log" | sed 's/^/    /'
fi
# Stop the dev server now; cleanup() also covers it.
if kill -0 "$VITE_PID" 2>/dev/null; then kill "$VITE_PID" 2>/dev/null || true; wait "$VITE_PID" 2>/dev/null || true; VITE_PID=""; fi
cd "$PROJECT"

# --- Step 2b: UI code path audits against the local chain (no browser) -----
echo "--- UI code-path audit against the local chain ---"
if [ "$UI_LOCAL_RPC" = "configured" ]; then
  VITE_GNO_RPC="$RPC" VITE_GNOWEB="$WEB" VITE_REALMCHECK_REALM="$REALMCHECK_REALM" \
    node scripts/ui-local-audit.mjs
  ui_audit_code=$?
  if [ "$ui_audit_code" -ne 0 ]; then
    if [ "${E2E_CONTINUE_ON_AUDIT_MISMATCH:-0}" = "1" ]; then
      note_fail "UI code-path audit mismatch recorded above (Gno vs JS port drift); continuing to the summary because E2E_CONTINUE_ON_AUDIT_MISMATCH=1."
    else
      note_fail "UI code-path audit against the local chain failed (see above)."
      echo "RESULT: FAILED (UI local audit)"; exit 1
    fi
  fi
else
  note_info "UI code-path audit skipped: env vars not landed, so the UI code cannot be pointed at the local chain yet."
fi

# --- Summary -----------------------------------------------------------------
echo "=== Summary ==="
echo "Chain: $RPC (gnoweb $WEB), fresh local chain started and stopped by this run."
echo "Baseline ReportCount: $COUNT_BEFORE"
while IFS='|' read -r realm rid height gas tx; do
  s="$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1])).score)" "$WORK/$realm.json")"
  n="$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1])).findings.length)" "$WORK/$realm.json")"
  echo "Report #$rid: $realm, score $s, $n finding(s), gas used $gas, height $height, tx $tx"
done < "$WORK/submits.txt"
echo "UI dev server: $UI_SERVE; local-RPC config: $UI_LOCAL_RPC."
if [ "$FAILURES" -eq 0 ]; then
  echo "RESULT: PASSED (UI local-RPC check: $UI_LOCAL_RPC)"
  exit 0
else
  echo "RESULT: FAILED ($FAILURES failure(s))"
  exit 1
fi
