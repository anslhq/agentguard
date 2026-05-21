#!/usr/bin/env bash
# Issue 22 fixture-replay smoke test.
#
# For each Claude Code fixture, runs the equivalent direct agentguard CLI
# command and asserts the response shape matches expected. This validates
# that the rule decisions remain stable across releases. Real PreToolUse
# stdin parsing in the binary will land alongside std.fs.readBytes upstream
# patch (see AGENTS.md); until then, this maps fixtures to their CLI shapes.

set -u
umask 077

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

BIN="$(pwd)/bin/agentguard"
FIXDIR="$(pwd)/tests/fixtures/host_payloads/claude-code"

FAIL=0
PASS=0

# Helper: extract the command string from a Bash payload.
extract_cmd() {
  jq -r '.tool_input.command' < "$1"
}

# 1. PreToolUse_Bash_safe → risk should allow
CMD=$(extract_cmd "$FIXDIR/PreToolUse_Bash_safe/payload.json")
RESULT=$("$BIN" risk --command "$CMD" 2>/dev/null)
ACTION=$(jq -r '.action' <<<"$RESULT")
if [[ "$ACTION" == "allow" ]]; then
  echo "  ok: PreToolUse_Bash_safe → $ACTION"
  PASS=$((PASS + 1))
else
  echo "FAIL: PreToolUse_Bash_safe (want allow, got $ACTION)" >&2
  FAIL=$((FAIL + 1))
fi

# 2. PreToolUse_Bash_destructive → risk should notify (CMD002)
CMD=$(extract_cmd "$FIXDIR/PreToolUse_Bash_destructive/payload.json")
RESULT=$("$BIN" risk --command "$CMD" 2>/dev/null)
ACTION=$(jq -r '.action' <<<"$RESULT")
CODE=$(jq -r '(.diagnostics // [])[0].code' <<<"$RESULT")
if [[ "$ACTION" == "notify" && "$CODE" == "CMD002" ]]; then
  echo "  ok: PreToolUse_Bash_destructive → $ACTION + $CODE"
  PASS=$((PASS + 1))
else
  echo "FAIL: PreToolUse_Bash_destructive (want notify+CMD002, got $ACTION+$CODE)" >&2
  FAIL=$((FAIL + 1))
fi

# 3. PreToolUse_Bash_workspace_escape → risk should block (CMD003)
CMD=$(extract_cmd "$FIXDIR/PreToolUse_Bash_workspace_escape/payload.json")
RESULT=$("$BIN" risk --command "$CMD" 2>/dev/null)
ACTION=$(jq -r '.action' <<<"$RESULT")
CODE=$(jq -r '(.diagnostics // [])[0].code' <<<"$RESULT")
if [[ "$ACTION" == "block" && "$CODE" == "CMD003" ]]; then
  echo "  ok: PreToolUse_Bash_workspace_escape → $ACTION + $CODE"
  PASS=$((PASS + 1))
else
  echo "FAIL: PreToolUse_Bash_workspace_escape (want block+CMD003, got $ACTION+$CODE)" >&2
  FAIL=$((FAIL + 1))
fi

# 4. Stop_claim_without_lease → classify-stop with --message claims-but-no-lease
MSG=$(jq -r '.last_assistant_message' < "$FIXDIR/Stop_claim_without_lease/payload.json")
# Make sure no lease cache is present.
TMP=$(mktemp -d)
cd "$TMP"
git init -q
"$BIN" init >/dev/null
RESULT=$("$BIN" classify-stop --message "$MSG" 2>/dev/null)
DEC=$(jq -r '.decision' <<<"$RESULT")
if [[ "$DEC" == "claim_without_lease" ]]; then
  echo "  ok: Stop_claim_without_lease → $DEC"
  PASS=$((PASS + 1))
else
  echo "FAIL: Stop_claim_without_lease (want claim_without_lease, got $DEC)" >&2
  FAIL=$((FAIL + 1))
fi
cd - >/dev/null
rm -rf "$TMP"

# 5. Stop_no_claim → classify-stop returns no_claim
MSG=$(jq -r '.last_assistant_message' < "$FIXDIR/Stop_no_claim/payload.json")
RESULT=$("$BIN" classify-stop --message "$MSG" 2>/dev/null)
DEC=$(jq -r '.decision' <<<"$RESULT")
if [[ "$DEC" == "no_claim" ]]; then
  echo "  ok: Stop_no_claim → $DEC"
  PASS=$((PASS + 1))
else
  echo "FAIL: Stop_no_claim (want no_claim, got $DEC)" >&2
  FAIL=$((FAIL + 1))
fi

echo
echo "host-payload-smoke: $PASS passed, $FAIL failed"
exit $((FAIL > 0))
