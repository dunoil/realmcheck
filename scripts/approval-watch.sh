#!/usr/bin/env bash
# approval-watch.sh: watch vm/qpkgmeta_json until all 7 RealmCheck packages
# report status "live", then re-run the offline-sign deploy (idempotent
# resume) to finish verification and the test SubmitReport.
#
# Why this exists: Onyx runs CodeSubmissionPolicyInert. The 7 addpkg
# transactions committed 27 Nov 2026 17:15 WITA, but the packages are
# stored INERT until a package approver enables them (GPAO:
# https://gpas.latest.testnets.gno.land, 5 passed, 2 in review queue;
# observed enable lag 2 to 5 hours after passing). Full diagnosis in
# docs/ONYX-DEPLOY.md section 10. Do NOT re-submit the packages while
# this watch runs: they are already stored, and re-adding would re-park
# them and reset the approval clock.
#
# Usage: bash scripts/offline-work/approval-watch.sh
# Log:   scripts/offline-work/approval-watch.log (appended, survives restarts)
# Exit 0 when the resume deploy PASSED; exit 1 on timeout (20 polls of
# 15 minutes, about 5 hours) or on a resume deploy failure. On timeout,
# re-run this script or check the statuses manually (see section 10.5).

set -u

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$PROJECT/scripts/offline-work"
LOG="$PROJECT/scripts/offline-work/approval-watch.log"
RPC="https://rpc.onyx.testnets.gno.land:443"
DEPLOYER="g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu"
MAX_POLLS=20
SLEEP_SECS=900

# kind/name pairs, deploy order.
PKGS="p|auditrules
r|realmcheck
r|vulnmint
r|greedystore
r|luckydice
r|unguardedvault
r|adminbackdoor"

log() { echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') $*" | tee -a "$LOG"; }

pkg_status() { # pkg_status <kind> <name>: prints live|inert|absent|error
  local kind="$1" name="$2" path hex resp
  path="gno.land/$kind/$DEPLOYER/$name"
  hex="$(printf '%s' "$path" | od -An -tx1 | tr -d ' \n')"
  resp="$(curl -s -m 30 -G "$RPC/abci_query" --data-urlencode "path=\"vm/qpkgmeta_json\"" --data-urlencode "data=0x$hex" || echo "")"
  [ -n "$resp" ] || { echo "error"; return 0; }
  printf '%s' "$resp" | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{try{const j=JSON.parse(s);const b=j&&j.result&&j.result.response&&j.result.response.ResponseBase;if(!b||b.Error){console.log('error');return;}const d=b.Data?Buffer.from(b.Data,'base64').toString('utf-8'):'';const m=JSON.parse(d);console.log(m.status||'error');}catch{console.log('error');}})"
}

log "Approval watch started (max $MAX_POLLS polls, ${SLEEP_SECS}s apart)."
poll=0
while [ "$poll" -lt "$MAX_POLLS" ]; do
  poll=$((poll + 1))
  live=0
  states=""
  while IFS='|' read -r kind name; do
    [ -n "$name" ] || continue
    st="$(pkg_status "$kind" "$name")"
    states="$states $name=$st"
    [ "$st" = "live" ] && live=$((live + 1))
  done <<EOF
$PKGS
EOF
  log "Poll $poll/$MAX_POLLS: live $live/7:$states"
  if [ "$live" -eq 7 ]; then
    log "All 7 packages live. Running the idempotent deploy resume."
    if bash "$PROJECT/scripts/offline-sign-deploy.sh" --key realmcheck-onyx --deployer "$DEPLOYER" >> "$LOG" 2>&1; then
      log "RESULT: RESUME PASSED (deploy verified, test SubmitReport stored). Continue with post-deploy UI (docs/SUBMISSION.md section 5) and the Onyx video re-record."
      exit 0
    else
      log "RESULT: RESUME FAILED (deploy script exit non-zero). Read the log above, fix the cause, re-run the deploy script manually."
      exit 1
    fi
  fi
  [ "$poll" -lt "$MAX_POLLS" ] && sleep "$SLEEP_SECS"
done
log "RESULT: TIMEOUT after $MAX_POLLS polls (about 5 hours). Packages not all live yet. Re-run this script to keep watching, or check statuses manually (docs/ONYX-DEPLOY.md section 10.5)."
exit 1
