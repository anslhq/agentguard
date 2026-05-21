#!/usr/bin/env bash
# B6: agentguard hooks install/uninstall --host cursor
set -u
umask 077
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
BIN="$(pwd)/bin/agentguard"

FAIL=0
PASS=0

assert() {
  local label="$1"; local got="$2"; local want="$3"
  if [[ "$got" == "$want" ]]; then
    echo "  ok: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label" >&2; echo "  want: $want" >&2; echo "  got:  $got" >&2
    FAIL=$((FAIL + 1))
  fi
}

# install --host cursor --print → valid JSON with the 7 expected events.
frag=$("$BIN" hooks install --host cursor --print 2>/dev/null)
if echo "$frag" | jq -e . >/dev/null 2>&1; then
  echo "  ok: hooks install --print emits valid JSON"
  PASS=$((PASS + 1))
else
  echo "FAIL: hooks install --print does not emit valid JSON" >&2
  echo "  got: $frag" >&2
  FAIL=$((FAIL + 1))
fi

keys=$(echo "$frag" | jq -r '.hooks | keys | join(",")' | tr ',' '\n' | sort | tr '\n' ',' | sed 's/,$//')
assert "fragment has 7 expected events" "$keys" "afterFileEdit,afterShellExecution,beforeReadFile,beforeShellExecution,sessionEnd,sessionStart,stop"

# Verify the binary path is absolute and points to bin/agentguard.
cmd=$(echo "$frag" | jq -r '.hooks.beforeShellExecution[0].command')
if [[ "$cmd" == /*/bin/agentguard\ hook\ --host\ cursor\ --event\ beforeShellExecution ]]; then
  echo "  ok: beforeShellExecution uses absolute path to bin/agentguard"
  PASS=$((PASS + 1))
else
  echo "FAIL: beforeShellExecution command unexpected (got: $cmd)" >&2
  FAIL=$((FAIL + 1))
fi

# Decision-bearing events do NOT have --log-only.
for evt in beforeShellExecution beforeReadFile stop; do
  cmd=$(echo "$frag" | jq -r ".hooks.$evt[0].command")
  if [[ "$cmd" == *"--log-only"* ]]; then
    echo "FAIL: $evt should NOT have --log-only (got: $cmd)" >&2
    FAIL=$((FAIL + 1))
  else
    echo "  ok: $evt is enforcing (no --log-only)"
    PASS=$((PASS + 1))
  fi
done

# Capture-only events DO have --log-only.
for evt in afterFileEdit afterShellExecution sessionStart sessionEnd; do
  cmd=$(echo "$frag" | jq -r ".hooks.$evt[0].command")
  if [[ "$cmd" == *"--log-only"* ]]; then
    echo "  ok: $evt is log-only"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $evt should have --log-only (got: $cmd)" >&2
    FAIL=$((FAIL + 1))
  fi
done

# The jq merge command in the help text actually works.
orig=$(mktemp)
frag_file=$(mktemp)
echo '{"version":1,"hooks":{"existing":[{"command":"other-tool"}]}}' > "$orig"
"$BIN" hooks install --host cursor --print 2>/dev/null > "$frag_file"
merged=$(jq -s '.[0] * .[1]' "$orig" "$frag_file")
keys=$(echo "$merged" | jq -r '.hooks | keys | join(",")' | tr ',' '\n' | sort | tr '\n' ',' | sed 's/,$//')
assert "merge preserves existing keys + adds 7 agentguard keys" "$keys" "afterFileEdit,afterShellExecution,beforeReadFile,beforeShellExecution,existing,sessionEnd,sessionStart,stop"

# Verify a SECOND merge is idempotent (jq * deep-merges, but for arrays it
# replaces — so the agentguard arrays just get re-written, no duplicates).
merged2=$(jq -s '.[0] * .[1]' "$frag_file" "$frag_file")
n=$(echo "$merged2" | jq '.hooks.beforeShellExecution | length')
assert "second merge keeps beforeShellExecution array at length 1 (no dupes)" "$n" "1"
rm -f "$orig" "$frag_file"

# install --host claude-code → fail with stderr message.
err=$("$BIN" hooks install --host claude-code 2>&1 >/dev/null)
if [[ "$err" == *"only --host cursor is implemented"* ]]; then
  echo "  ok: --host claude-code returns deferred message"
  PASS=$((PASS + 1))
else
  echo "FAIL: --host claude-code should report deferred (got: $err)" >&2
  FAIL=$((FAIL + 1))
fi

# install with no --host → missing-host error.
err=$("$BIN" hooks install 2>&1 >/dev/null)
if [[ "$err" == *"missing --host"* ]]; then
  echo "  ok: missing --host error"
  PASS=$((PASS + 1))
else
  echo "FAIL: missing --host should error (got: $err)" >&2
  FAIL=$((FAIL + 1))
fi

# uninstall --host cursor emits the jq removal command on stderr.
err=$("$BIN" hooks uninstall --host cursor 2>&1 >/dev/null)
if [[ "$err" == *"To remove AgentGuard hooks"* && "$err" == *"jq 'del"* ]]; then
  echo "  ok: hooks uninstall emits removal command"
  PASS=$((PASS + 1))
else
  echo "FAIL: hooks uninstall should emit removal command" >&2
  FAIL=$((FAIL + 1))
fi

# No subcommand → missing subcommand error.
err=$("$BIN" hooks 2>&1 >/dev/null)
if [[ "$err" == *"missing subcommand"* ]]; then
  echo "  ok: hooks no-subcommand error"
  PASS=$((PASS + 1))
else
  echo "FAIL: hooks no-subcommand should error" >&2
  FAIL=$((FAIL + 1))
fi

echo
echo "hooks-install: $PASS passed, $FAIL failed"
exit $((FAIL > 0))
