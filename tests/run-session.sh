#!/usr/bin/env bash
# B3: agentguard session start / current / end
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

assert() {
  local label="$1"; local got="$2"; local want="$3"
  if [[ "$got" == "$want" ]]; then
    echo "  ok: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label" >&2
    echo "  want: $want" >&2
    echo "  got:  $got" >&2
    FAIL=$((FAIL + 1))
  fi
}

# Before start: state=none.
state=$("$BIN" session current | jq -r '.state')
assert "session current before start = none" "$state" "none"

# After start --host cursor.
"$BIN" session start --host cursor >/dev/null
host=$(jq -r '.host' .agentguard/cache/session.json)
assert "session.json host = cursor" "$host" "cursor"

state=$("$BIN" session current | jq -r '.state')
assert "session current after start = active" "$state" "active"

# Ledger has session_start row.
last_event=$(tail -n 1 .agentguard/ledger.jsonl | jq -r '.event')
assert "ledger last event = session_start" "$last_event" "session_start"

# session end → file removed, state=none, ledger has session_end row.
"$BIN" session end >/dev/null
if [[ -f .agentguard/cache/session.json ]]; then
  echo "FAIL: session.json should be removed after session end" >&2
  FAIL=$((FAIL + 1))
else
  echo "  ok: session.json removed after end"
  PASS=$((PASS + 1))
fi
state=$("$BIN" session current | jq -r '.state')
assert "session current after end = none" "$state" "none"
last_event=$(tail -n 1 .agentguard/ledger.jsonl | jq -r '.event')
assert "ledger last event = session_end" "$last_event" "session_end"

# session start with no --host → host=unknown
"$BIN" session start >/dev/null
host=$(jq -r '.host' .agentguard/cache/session.json)
assert "session start (no --host) → unknown" "$host" "unknown"

# session start --host claude-code
"$BIN" session start --host claude-code >/dev/null
host=$(jq -r '.host' .agentguard/cache/session.json)
assert "session start --host claude-code" "$host" "claude-code"

# session start --host codex
"$BIN" session start --host codex >/dev/null
host=$(jq -r '.host' .agentguard/cache/session.json)
assert "session start --host codex" "$host" "codex"

# session start --host bogus → host=unknown
"$BIN" session start --host bogus-host >/dev/null
host=$(jq -r '.host' .agentguard/cache/session.json)
assert "session start --host bogus → unknown" "$host" "unknown"

# Unknown subcommand → stderr message
if "$BIN" session foo 2>&1 | grep -q "unknown subcommand"; then
  echo "  ok: session foo → unknown subcommand error"
  PASS=$((PASS + 1))
else
  echo "FAIL: session foo should emit unknown subcommand error" >&2
  FAIL=$((FAIL + 1))
fi

# session (no subcommand) → missing subcommand error on stderr
if "$BIN" session 2>&1 | grep -q "missing subcommand"; then
  echo "  ok: session (no arg) → missing subcommand error"
  PASS=$((PASS + 1))
else
  echo "FAIL: session no-arg should emit missing subcommand error" >&2
  FAIL=$((FAIL + 1))
fi

cd /
rm -rf "$FIX"

echo
echo "session: $PASS passed, $FAIL failed"
exit $((FAIL > 0))
