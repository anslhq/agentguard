#!/usr/bin/env bash
# Issue 20 bash implementation. Renders plugins/_shared/SKILL_SRC.md into
# host-specific skill files.
#
# The original Issue 20 plan called for a Zero program at
# tooling/render-skills.0, but the Zero v0.1.3 direct-backend MVP cannot
# express the program shape (writes a hosted file path that came from a
# runtime String — see AGENTS.md "Zero v0.1.3 direct-backend MVP subset").
# This bash version is the canonical render-skills implementation until the
# backend lifts; the Zero rewrite is tracked as future work.

set -u
umask 077

cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
ROOT="$(pwd)"

SRC="$ROOT/plugins/_shared/SKILL_SRC.md"
if [[ ! -f "$SRC" ]]; then
  echo "render-skills: $SRC not found" >&2
  exit 1
fi

declare -a TARGETS=(
  "plugins/claude-code/skills/agentguard/SKILL.md"
  "plugins/cursor/skills/agentguard/SKILL.md"
  "plugins/codex/.agents/skills/agentguard/SKILL.md"
)

CHANGED=0
for rel in "${TARGETS[@]}"; do
  dst="$ROOT/$rel"
  mkdir -p "$(dirname "$dst")"
  if [[ ! -f "$dst" ]] || ! cmp -s "$SRC" "$dst"; then
    cp "$SRC" "$dst"
    echo "  wrote: $rel"
    CHANGED=$((CHANGED + 1))
  else
    echo "  noop: $rel (unchanged)"
  fi
done

echo "render-skills: $CHANGED file(s) updated"
exit 0
