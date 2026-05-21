#!/usr/bin/env bash
# A4 verification: ledger.jsonl is append-only across separate binary
# invocations. Before C1 (std.fs.appendBytes) landed, every resolution
# event overwrote the file, so the ledger could only ever hold one row.
# This test proves the append behavior holds.

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

assert_lines() {
  local label="$1"
  local want="$2"
  local got
  got=$(wc -l < .agentguard/ledger.jsonl | tr -d ' ')
  if [[ "$got" == "$want" ]]; then
    echo "  ok: $label [$want rows]"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label (want $want rows, got $got)" >&2
    echo "  contents:" >&2
    sed 's/^/    /' .agentguard/ledger.jsonl >&2
    FAIL=$((FAIL + 1))
  fi
}

# Right after init: empty.
assert_lines "ledger empty after init" 0

# One approval → 1 row.
"$BIN" approve CMD002 >/dev/null
assert_lines "ledger has 1 row after first approve" 1

# Second approval → 2 rows (not 1).
"$BIN" approve CMD002 >/dev/null
assert_lines "ledger has 2 rows after second approve (NOT overwritten)" 2

# Three more events of different kinds → 5 rows total.
"$BIN" ack CMD007 >/dev/null
touch .agentguard/cache/bypass-findings.json
"$BIN" ack-bypass policy-edit-1 >/dev/null

# done --finalize will refuse if bypass-findings.json is still present;
# remove it first (ack-bypass should have, but verify).
rm -f .agentguard/cache/bypass-findings.json
# A3 evidence requirement: also need check-state.json + no changed-files.
"$BIN" verify --record-pass typecheck >/dev/null
"$BIN" done --finalize >/dev/null
assert_lines "ledger has 5 rows after mixed events" 5

# Verify the rows are distinguishable (not the same event repeated).
got=$(jq -r '.event + ":" + .kind' .agentguard/ledger.jsonl 2>/dev/null | sort -u | wc -l | tr -d ' ')
# Expected unique (event,kind) pairs:
#   resolution:approval, resolution:diagnostic_ack, resolution:bypass_ack, done:null
# = 4 distinct combinations.
if [[ "$got" == "4" ]]; then
  echo "  ok: ledger contains 4 distinct event kinds"
  PASS=$((PASS + 1))
else
  echo "FAIL: expected 4 distinct (event,kind) pairs, got $got" >&2
  FAIL=$((FAIL + 1))
fi

# Final sanity: every row is valid JSON.
bad_rows=0
while IFS= read -r row; do
  if ! jq -e . >/dev/null 2>&1 <<<"$row"; then
    bad_rows=$((bad_rows + 1))
  fi
done < .agentguard/ledger.jsonl
if [[ "$bad_rows" == "0" ]]; then
  echo "  ok: every ledger row is valid JSON"
  PASS=$((PASS + 1))
else
  echo "FAIL: $bad_rows ledger rows are not valid JSON" >&2
  FAIL=$((FAIL + 1))
fi

cd /
rm -rf "$FIX"

echo
echo "ledger-append: $PASS passed, $FAIL failed"
exit $((FAIL > 0))
