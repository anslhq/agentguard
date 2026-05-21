#!/usr/bin/env bash
# Issue 11 + Issue 18 fixture tests: done plan/finalize + bypass lifecycle.

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

FIX=$(mktemp -d)
cd "$FIX"
git init -q
"$BIN" init >/dev/null

# A3 evidence requirement: before lease can issue, verify --record-pass
# must have run (so check-state.json exists) and no edits since last reset
# (so changed-files.txt is absent). Set that baseline up here.
"$BIN" verify --record-pass typecheck >/dev/null

# 1. Clean state: done --json plan returns leaseDecision=none, status=ready
RESULT=$("$BIN" done 2>/dev/null)
assert "plan clean"        "$(jq -r '.leaseDecision' <<<"$RESULT")" "none"
assert "plan ready"        "$(jq -r '.status' <<<"$RESULT")"        "ready_to_finalize"

# 2. done --finalize issues lease
RESULT=$("$BIN" done --finalize 2>/dev/null)
assert "finalize issued"   "$(jq -r '.leaseDecision' <<<"$RESULT")" "issued"
[[ -f .agentguard/cache/lease-state.json ]] && PASS=$((PASS + 1)) || { echo "FAIL: lease-state.json missing" >&2; FAIL=$((FAIL + 1)); }
echo "  ok: lease-state.json written"

# 3. Add a strong-confidence bypass finding; done --finalize denied
echo '{"id":"byp_test","kind":"policy_edit_in_session","confidence":"strong"}' > .agentguard/cache/bypass-findings.json
RESULT=$("$BIN" done --finalize 2>/dev/null)
assert "denied w/ bypass"  "$(jq -r '.leaseDecision' <<<"$RESULT")" "denied"
assert "POL001 surfaced"   "$(jq -r '(.diagnostics // [])[0].code' <<<"$RESULT")" "POL001"

# 4. ack-bypass clears the finding
"$BIN" ack-bypass byp_test >/dev/null 2>&1
[[ ! -f .agentguard/cache/bypass-findings.json ]] && PASS=$((PASS + 1)) || { echo "FAIL: bypass-findings.json should have been removed" >&2; FAIL=$((FAIL + 1)); }
echo "  ok: ack-bypass removed bypass-findings.json"

# 5. done --finalize succeeds again
RESULT=$("$BIN" done --finalize 2>/dev/null)
assert "finalize after ack" "$(jq -r '.leaseDecision' <<<"$RESULT")" "issued"

# 6. plan mode also reports denied when bypass present
echo '{"id":"byp2","kind":"hook_config_edit","confidence":"strong"}' > .agentguard/cache/bypass-findings.json
RESULT=$("$BIN" done 2>/dev/null)
assert "plan w/ bypass"    "$(jq -r '.leaseDecision' <<<"$RESULT")" "denied"
assert "plan blockers[0]"  "$(jq -r '.blockers[0].kind' <<<"$RESULT")" "strong_bypass"

cd /
rm -rf "$FIX"

echo
echo "done-goldens: $PASS passed, $FAIL failed"
exit $((FAIL > 0))
