#!/usr/bin/env bash
# Issue 21 + Issue 23 fixture tests for approve, ack, ack-bypass, lease,
# classify-stop.

set -u
umask 077

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

BIN="$(pwd)/bin/agentguard"

FAIL=0
PASS=0

assert() {
  local label="$1"
  local actual="$2"
  local want="$3"
  if [[ "$actual" == "$want" ]]; then
    echo "  ok: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label" >&2
    echo "  want: $want" >&2
    echo "  got:  $actual" >&2
    FAIL=$((FAIL + 1))
  fi
}

# Set up a clean fixture repo
FIX=$(mktemp -d)
cd "$FIX"
git init -q
"$BIN" init >/dev/null

# approve writes resolution
RESULT=$("$BIN" approve ap_test 2>/dev/null)
assert "approve event"     "$(jq -r '.event' <<<"$RESULT")"    "resolution"
assert "approve decision"  "$(jq -r '.decision' <<<"$RESULT")" "approved"

# ack writes resolution kind diagnostic_ack
RESULT=$("$BIN" ack CMD002 2>/dev/null)
assert "ack kind"          "$(jq -r '.kind' <<<"$RESULT")"     "diagnostic_ack"

# ack-bypass writes resolution kind bypass_ack
RESULT=$("$BIN" ack-bypass byp_test 2>/dev/null)
assert "ack-bypass kind"   "$(jq -r '.kind' <<<"$RESULT")"     "bypass_ack"

# lease starts as none (cache empty after init)
rm -f .agentguard/cache/lease-state.json
RESULT=$("$BIN" lease 2>/dev/null)
assert "lease none"        "$(jq -r '.leaseState' <<<"$RESULT")" "none"

# lease valid when cache exists
echo '{"valid":true}' > .agentguard/cache/lease-state.json
RESULT=$("$BIN" lease 2>/dev/null)
assert "lease valid"       "$(jq -r '.leaseState' <<<"$RESULT")" "valid"

# classify-stop no args -> no_claim
RESULT=$("$BIN" classify-stop 2>/dev/null)
assert "classify no args"  "$(jq -r '.decision' <<<"$RESULT")"  "no_claim"

# classify-stop "all done" with valid lease -> claim_with_valid_lease
RESULT=$("$BIN" classify-stop --message "all done shipping" 2>/dev/null)
assert "classify done+lease" "$(jq -r '.decision' <<<"$RESULT")" "claim_with_valid_lease"

# classify-stop "not done yet" -> no_claim (negative guard)
RESULT=$("$BIN" classify-stop --message "not done yet" 2>/dev/null)
assert "classify not-done"  "$(jq -r '.decision' <<<"$RESULT")"  "no_claim"

# classify-stop "task is done" with NO lease -> claim_without_lease
rm -f .agentguard/cache/lease-state.json
RESULT=$("$BIN" classify-stop --message "task is done" 2>/dev/null)
assert "classify no lease"  "$(jq -r '.decision' <<<"$RESULT")"  "claim_without_lease"

# Cleanup
cd /
rm -rf "$FIX"

echo
echo "lease-goldens: $PASS passed, $FAIL failed"
exit $((FAIL > 0))
