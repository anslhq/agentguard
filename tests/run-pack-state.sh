#!/usr/bin/env bash
# pack: emits context informed by current state (lease/bypass/edits/check-state/session).
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

check_contains() {
  local label="$1"; local got="$2"; local needle="$3"
  if [[ "$got" == *"$needle"* ]]; then
    echo "  ok: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label" >&2
    echo "  needle: $needle" >&2
    echo "  got:    $got" >&2
    FAIL=$((FAIL + 1))
  fi
}

# Initial state — no check-state.
RESULT=$("$BIN" pack)
inst=$(jq -r '.sections[0].text' <<<"$RESULT")
state=$(jq -r '.sections[1].text' <<<"$RESULT")
check_contains "empty state: next_instruction asks for check-state" "$inst" "No check-state recorded"
check_contains "empty state: state flags show all clear/absent/missing" "$state" "lease=absent bypass=clear changedFiles=clear checkState=missing"

# After record-pass: ready_to_finalize.
"$BIN" verify --record-pass typecheck >/dev/null
RESULT=$("$BIN" pack)
inst=$(jq -r '.sections[0].text' <<<"$RESULT")
check_contains "with check-state: next_instruction says ready to finalize" "$inst" "Ready to finalize"

# Bypass present.
echo '{"file_path":"/x/AGENTS.md"}' | "$BIN" hook --host cursor --event afterFileEdit >/dev/null
RESULT=$("$BIN" pack)
inst=$(jq -r '.sections[0].text' <<<"$RESULT")
prompt=$(jq -r '.prompt' <<<"$RESULT")
check_contains "bypass: next_instruction tells agent to ack-bypass" "$inst" "ack-bypass"
check_contains "bypass: top-level prompt mentions bypass" "$prompt" "Bypass finding active"

# Clear bypass; should fall back to "edits since verify" since
# changed-files.txt still exists from the afterFileEdit hook above.
"$BIN" ack-bypass test >/dev/null
RESULT=$("$BIN" pack)
inst=$(jq -r '.sections[0].text' <<<"$RESULT")
check_contains "edits: next_instruction says re-verify" "$inst" "Files have been edited since the last verify"

# Clear edits; now state shows lease=present after finalize.
"$BIN" verify --reset >/dev/null
"$BIN" done --finalize >/dev/null
RESULT=$("$BIN" pack)
inst=$(jq -r '.sections[0].text' <<<"$RESULT")
state=$(jq -r '.sections[1].text' <<<"$RESULT")
check_contains "lease: next_instruction confirms lease present" "$inst" "Valid lease present"
check_contains "lease: state shows lease=present" "$state" "lease=present"

# Session start brings session=active.
"$BIN" session start --host cursor >/dev/null
RESULT=$("$BIN" pack)
state=$(jq -r '.sections[1].text' <<<"$RESULT")
check_contains "session: state shows session=active" "$state" "session=active"

# Token estimate varies by state.
RESULT=$("$BIN" pack)
tokens=$(jq -r '.estimatedTokens' <<<"$RESULT")
if [[ "$tokens" -ge 24 ]]; then
  echo "  ok: estimatedTokens is a sensible integer ($tokens)"
  PASS=$((PASS + 1))
else
  echo "FAIL: estimatedTokens missing or too small ($tokens)" >&2
  FAIL=$((FAIL + 1))
fi

cd /
rm -rf "$FIX"

echo
echo "pack-state: $PASS passed, $FAIL failed"
exit $((FAIL > 0))
