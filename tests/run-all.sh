#!/usr/bin/env bash
# Issue 19 test-harness entry point. Runs every test runner in sequence
# and reports a single pass/fail.
#
# Acceptance criterion: full test suite under 60 seconds.

set -u
umask 077

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

START=$(date +%s)
FAIL=0
RUN=0

run_test() {
  local label="$1"
  local script="$2"
  RUN=$((RUN + 1))
  echo "===== $label ====="
  if "$script"; then
    echo "$label: PASS"
  else
    echo "$label: FAIL" >&2
    FAIL=$((FAIL + 1))
  fi
}

run_test "docs-lint"           "./bin/docs-lint"
run_test "explain-goldens"     "./tests/run-explain-goldens.sh"
run_test "output-caps"         "./tests/validate-output-caps.sh"
run_test "docs-lint smoke"     "./tests/run-docs-lint-smoke.sh"
run_test "risk-goldens"        "./tests/run-risk-goldens.sh"
run_test "verify-goldens"      "./tests/run-verify-goldens.sh"
run_test "lease-goldens"       "./tests/run-lease-goldens.sh"
run_test "done-goldens"        "./tests/run-done-goldens.sh"
run_test "host-payload-smoke"  "./tests/run-host-payload-smoke.sh"
run_test "host-adapter"        "./tests/run-host-adapter.sh"
run_test "ledger-append"       "./tests/run-ledger-append.sh"
run_test "session"             "./tests/run-session.sh"
run_test "hooks-install"       "./tests/run-hooks-install.sh"
run_test "lease-evidence"      "./tests/run-lease-evidence.sh"
run_test "pack-state"          "./tests/run-pack-state.sh"

END=$(date +%s)
ELAPSED=$((END - START))

echo
echo "===== summary ====="
echo "ran $RUN suites in ${ELAPSED}s, $FAIL failed"

if (( ELAPSED > 60 )); then
  echo "WARN: suite took ${ELAPSED}s — over the 60s Issue 19 budget" >&2
fi

exit $((FAIL > 0))
