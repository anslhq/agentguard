#!/usr/bin/env bash
# Issue 26 smoke test. Confirms that:
#   1. docs-lint passes against the current repo state.
#   2. docs-lint detects the forbidden pattern when the test fixture's
#      allow-superseded markers are removed.

set -u
umask 077

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
ROOT="$(pwd)"

FAIL=0

# Phase 1: clean state.
if ! "$ROOT/bin/docs-lint" >/dev/null 2>&1; then
  echo "FAIL: docs-lint reported violations against the clean repo state" >&2
  "$ROOT/bin/docs-lint" >&2
  FAIL=$((FAIL + 1))
else
  echo "  ok: docs-lint clean on current repo"
fi

# Phase 2: poisoned state — strip the markers from the fixture and confirm
# the linter catches the in-file forbidden-vocabulary token.
# (The token name itself is intentionally not spelled here so this script
# does not become a docs-lint violation when reviewed.)
FIXTURE="$ROOT/tests/fixtures/docs-lint/bad-fixture.md"
ORIGINAL=$(cat "$FIXTURE")
trap 'printf "%s" "$ORIGINAL" > "$FIXTURE"' EXIT

awk '!/docs-lint:allow-superseded-(start|end)/' "$FIXTURE" > "$FIXTURE.stripped"
mv "$FIXTURE.stripped" "$FIXTURE"

OUTPUT=$("$ROOT/bin/docs-lint" 2>&1 || true)
if [[ "$OUTPUT" == *"bad-fixture.md"* ]]; then
  echo "  ok: docs-lint catches the poisoned fixture when markers are removed"
else
  echo "FAIL: docs-lint did not catch the poisoned fixture" >&2
  echo "  saw: $OUTPUT" >&2
  FAIL=$((FAIL + 1))
fi

# trap restores the fixture on exit

if (( FAIL == 0 )); then
  echo "docs-lint smoke: ok"
fi
exit $FAIL
