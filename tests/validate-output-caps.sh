#!/usr/bin/env bash
# Issue 25 (OutputCapper) — ADR-0012 size-cap validator.
#
# Until the Zero v0.1.3 direct-backend MVP lifts enough to support an
# OutputCapper module with the planned shape, the cap rule is enforced by
# this validator on every JSON envelope emitted by AgentGuard subcommands.
# Each `tests/golden/<command>/<case>.json` is fed through here.
#
# Caps from ADR-0012:
#   - top-level envelope: 64 KiB
#   - nextAgentInstruction: 4 KiB
#   - additionalContext: 8 KiB
#   - diagnostics[]: soft 50 (overflow summarized in meta.truncated)
#
# Exit 0: all caps respected. Exit 1: at least one cap violated.

set -u
umask 077

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

ENV_CAP_BYTES=$((64 * 1024))
NAI_CAP_BYTES=$((4 * 1024))
ADDCTX_CAP_BYTES=$((8 * 1024))
DIAG_SOFT_CAP=50

violation_count=0
file_count=0

check_file() {
  local file="$1"
  file_count=$((file_count + 1))

  # Skip non-JSON files quietly.
  if ! jq -e . "$file" >/dev/null 2>&1; then
    return 0
  fi

  local size
  size=$(wc -c < "$file")
  if (( size > ENV_CAP_BYTES )); then
    echo "FAIL: $file: envelope is $size bytes (cap=$ENV_CAP_BYTES)" >&2
    violation_count=$((violation_count + 1))
  fi

  local nai_size
  nai_size=$(jq -r '.nextAgentInstruction // "" | length' "$file")
  if (( nai_size > NAI_CAP_BYTES )); then
    echo "FAIL: $file: nextAgentInstruction is $nai_size bytes (cap=$NAI_CAP_BYTES)" >&2
    violation_count=$((violation_count + 1))
  fi

  local addctx_size
  addctx_size=$(jq -r '.additionalContext // "" | length' "$file")
  if (( addctx_size > ADDCTX_CAP_BYTES )); then
    echo "FAIL: $file: additionalContext is $addctx_size bytes (cap=$ADDCTX_CAP_BYTES)" >&2
    violation_count=$((violation_count + 1))
  fi

  local diag_count
  diag_count=$(jq -r '.diagnostics // [] | length' "$file")
  local truncated
  truncated=$(jq -r '.meta.truncated // false' "$file")
  if (( diag_count > DIAG_SOFT_CAP )) && [[ "$truncated" != "true" ]]; then
    echo "FAIL: $file: diagnostics[] has $diag_count entries (soft cap=$DIAG_SOFT_CAP) but meta.truncated is not true" >&2
    violation_count=$((violation_count + 1))
  fi
}

# Walk every golden envelope under tests/golden/.
if [[ -d tests/golden ]]; then
  while IFS= read -r f; do
    check_file "$f"
  done < <(find tests/golden -type f -name '*.json')
fi

# Also accept files passed on the command line (for ad-hoc CI invocation).
for arg in "$@"; do
  if [[ -f "$arg" ]]; then
    check_file "$arg"
  fi
done

echo "output-caps: checked $file_count file(s); $violation_count violation(s)"
exit $((violation_count > 0))
