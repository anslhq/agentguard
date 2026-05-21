#!/usr/bin/env bash
# Issue 01 + Issue 19 stub: regression check for `agentguard explain <CODE>`.
#
# For each golden under tests/golden/explain/<CODE>.json, run the binary
# against <CODE>, capture stdout, and diff against the golden. Exits 0 on
# match, 1 otherwise. Pass --update to regenerate goldens.

set -u
umask 077

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
ROOT="$(pwd)"
BIN="$ROOT/bin/agentguard"
GOLDEN_DIR="$ROOT/tests/golden/explain"

if [[ ! -x "$BIN" ]]; then
  echo "explain-goldens: $BIN not built. Run: ./zerolang/bin/zero build --emit exe --target darwin-arm64 . --out bin/agentguard" >&2
  exit 1
fi

UPDATE=0
if [[ "${1:-}" == "--update" ]]; then
  UPDATE=1
fi

FAIL=0
COUNT=0

for golden in "$GOLDEN_DIR"/*.json; do
  [[ -e "$golden" ]] || continue
  CODE=$(basename "$golden" .json)
  COUNT=$((COUNT + 1))
  ACTUAL=$("$BIN" explain "$CODE" 2>/dev/null)
  if [[ "$UPDATE" -eq 1 ]]; then
    printf '%s' "$ACTUAL" > "$golden"
    echo "  updated: $CODE"
    continue
  fi
  EXPECTED=$(cat "$golden")
  if [[ "$ACTUAL" != "$EXPECTED" ]]; then
    echo "FAIL: $CODE"
    diff <(printf '%s' "$EXPECTED") <(printf '%s' "$ACTUAL") | head -10 >&2
    FAIL=$((FAIL + 1))
  else
    echo "  ok: $CODE"
  fi
done

# Also exercise the unknown-code path; this golden lives alongside but is
# generated on the fly to keep BOGUS-as-input out of the on-disk golden set.
ACTUAL=$("$BIN" explain BOGUS 2>/dev/null)
EXPECTED_FRAGMENT='"code":"CTX999"'
if [[ "$ACTUAL" != *"$EXPECTED_FRAGMENT"* ]]; then
  echo "FAIL: unknown-code path missing CTX999 fragment"
  echo "  got: $ACTUAL" >&2
  FAIL=$((FAIL + 1))
else
  echo "  ok: unknown-code (BOGUS → CTX999)"
fi
COUNT=$((COUNT + 1))

echo "ran $COUNT tests, $FAIL failed"
exit $FAIL
