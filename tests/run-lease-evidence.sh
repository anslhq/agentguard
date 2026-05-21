#!/usr/bin/env bash
# A3: done --finalize is evidence-backed. Lease only issues when:
#   (a) no strong-confidence bypass findings
#   (b) no unverified file edits (changed-files.txt absent)
#   (c) check-state.json present (proves verify --record-pass ran)

set -u
umask 077
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

BIN="$(pwd)/bin/agentguard"
FIX=$(mktemp -d)
cd "$FIX"
git init -q
"$BIN" init >/dev/null

FAIL=0
PASS=0

check() {
  local label="$1"; local got="$2"; local want="$3"
  if [[ "$got" == "$want" ]]; then
    echo "  ok: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label" >&2; echo "  want: $want" >&2; echo "  got:  $got" >&2
    FAIL=$((FAIL + 1))
  fi
}

# 1. With no check-state.json → done --finalize denied with CTX004.
result=$("$BIN" done --finalize)
decision=$(jq -r '.leaseDecision' <<<"$result")
code=$(jq -r '.diagnostics[0].code // "none"' <<<"$result")
check "no check-state → leaseDecision=denied" "$decision" "denied"
check "no check-state → code=CTX004" "$code" "CTX004"

# 2. After verify --record-pass, finalize issues lease.
"$BIN" verify --record-pass typecheck >/dev/null
result=$("$BIN" done --finalize)
decision=$(jq -r '.leaseDecision' <<<"$result")
check "with check-state → leaseDecision=issued" "$decision" "issued"

# Verify lease file shape.
hash=$(jq -r '.diffHash' .agentguard/cache/lease-state.json)
check "lease has diffHash=none-since-reset" "$hash" "none-since-reset"
attest=$(jq -r '.checksAttested | join(",")' .agentguard/cache/lease-state.json)
check "lease has checksAttested" "$attest" "check-state.json"

# 3. After afterFileEdit, finalize is DENIED.
echo '{"file_path":"/proj/foo.ts"}' | "$BIN" hook --host cursor --event afterFileEdit >/dev/null
result=$("$BIN" done --finalize)
decision=$(jq -r '.leaseDecision' <<<"$result")
code=$(jq -r '.diagnostics[0].code // "none"' <<<"$result")
check "after edit → leaseDecision=denied" "$decision" "denied"
check "after edit → code=CTX003" "$code" "CTX003"

# 4. verify --reset clears the taint; finalize succeeds again.
"$BIN" verify --reset >/dev/null
result=$("$BIN" done --finalize)
decision=$(jq -r '.leaseDecision' <<<"$result")
check "after reset → leaseDecision=issued" "$decision" "issued"

# 5. Plan mode (no --finalize) reflects same gating.
echo '{"file_path":"/proj/bar.ts"}' | "$BIN" hook --host cursor --event afterFileEdit >/dev/null
result=$("$BIN" done)
decision=$(jq -r '.leaseDecision' <<<"$result")
blocker=$(jq -r '.blockers[0].kind // "none"' <<<"$result")
check "plan mode + edit → leaseDecision=denied" "$decision" "denied"
check "plan mode + edit → blocker=unverified_edits" "$blocker" "unverified_edits"

# Clear edits, then check plan-mode reports no_check_state if check-state.json absent.
"$BIN" verify --reset >/dev/null
rm -f .agentguard/cache/check-state.json
result=$("$BIN" done)
blocker=$(jq -r '.blockers[0].kind // "none"' <<<"$result")
check "plan mode + no check-state → blocker=no_check_state" "$blocker" "no_check_state"

# Restore check-state, no edits → ready_to_finalize.
"$BIN" verify --record-pass typecheck >/dev/null
result=$("$BIN" done)
status=$(jq -r '.status // "none"' <<<"$result")
check "plan mode + clean → status=ready_to_finalize" "$status" "ready_to_finalize"

# 6. Bypass findings still block (pre-existing behavior, regression check).
touch .agentguard/cache/bypass-findings.json
result=$("$BIN" done --finalize)
decision=$(jq -r '.leaseDecision' <<<"$result")
code=$(jq -r '.diagnostics[0].code // "none"' <<<"$result")
check "bypass-findings → leaseDecision=denied" "$decision" "denied"
check "bypass-findings → code=POL001" "$code" "POL001"

# Verify ledger has been growing.
n=$(wc -l < .agentguard/ledger.jsonl | tr -d ' ')
if [[ "$n" -ge 2 ]]; then
  echo "  ok: ledger contains >= 2 rows ($n)"
  PASS=$((PASS + 1))
else
  echo "FAIL: ledger should have multiple rows (got $n)" >&2
  FAIL=$((FAIL + 1))
fi

cd /
rm -rf "$FIX"

echo
echo "lease-evidence: $PASS passed, $FAIL failed"
exit $((FAIL > 0))
