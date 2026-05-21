#!/usr/bin/env bash
# Issue 07 verify fixture-table tests.
#
# Each case prepares a tmp dir, runs verify, asserts on requiredChecks
# composition.

set -u
umask 077

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

BIN="$(pwd)/bin/agentguard"

FAIL=0
PASS=0

assert_required_typecheck() {
  local label="$1"
  local dir="$2"
  local expect_required="$3"  # "yes" or "no"
  local got
  got=$("$BIN" verify 2>/dev/null)
  local has_typecheck
  has_typecheck=$(jq -r '(.requiredChecks // []) | map(select(.id == "typecheck")) | length' <<<"$got")
  if [[ "$expect_required" == "yes" && "$has_typecheck" == "1" ]]; then
    echo "  ok: $label → typecheck required"
    PASS=$((PASS + 1))
  elif [[ "$expect_required" == "no" && "$has_typecheck" == "0" ]]; then
    echo "  ok: $label → no typecheck"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label (expected typecheck=$expect_required, got $has_typecheck)" >&2
    FAIL=$((FAIL + 1))
  fi
}

# Case 1: TS repo (with tsconfig.json)
TS_DIR=$(mktemp -d)
(
  cd "$TS_DIR"
  git init -q
  echo '{}' > tsconfig.json
  assert_required_typecheck "ts repo" "$TS_DIR" "yes"
)

# Case 2: Plain repo (no tsconfig.json)
NTS_DIR=$(mktemp -d)
(
  cd "$NTS_DIR"
  git init -q
  echo "# plain repo" > README.md
  assert_required_typecheck "no-ts repo" "$NTS_DIR" "no"
)

# Case 3: Record-pass / record-fail
REC_DIR=$(mktemp -d)
(
  cd "$REC_DIR"
  git init -q
  echo '{}' > tsconfig.json
  mkdir -p .agentguard/cache
  RESULT=$("$BIN" verify --record-pass typecheck 2>/dev/null)
  STATUS=$(jq -r '.status' <<<"$RESULT")
  if [[ "$STATUS" == "recorded" ]]; then
    echo "  ok: record-pass returns recorded"
    PASS=$((PASS + 1))
  else
    echo "FAIL: record-pass got $STATUS" >&2
    FAIL=$((FAIL + 1))
  fi

  RESULT=$("$BIN" verify --record-fail typecheck 2>/dev/null)
  STATUS=$(jq -r '.status' <<<"$RESULT")
  if [[ "$STATUS" == "recorded" ]]; then
    echo "  ok: record-fail returns recorded"
    PASS=$((PASS + 1))
  else
    echo "FAIL: record-fail got $STATUS" >&2
    FAIL=$((FAIL + 1))
  fi
)

# Cleanup
rm -rf "$TS_DIR" "$NTS_DIR" "$REC_DIR"

echo
echo "verify-goldens: $PASS passed, $FAIL failed"
exit $((FAIL > 0))
