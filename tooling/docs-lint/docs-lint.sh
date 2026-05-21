#!/usr/bin/env bash
# Issue 26 (docs-lint) bash implementation.
#
# This is the working implementation of the AgentGuard docs-lint gate. The
# original Issue 26 design called for a Zero-based `tooling/docs-lint/docs_lint.0`
# program, but the Zero v0.1.3 direct-backend MVP cannot yet express the
# program shape (file walks + variable string-to-std-func calls — see
# AGENTS.md "Zero v0.1.3 direct-backend MVP subset"). Until the upstream
# backend lifts, this script is the canonical docs-lint. The original
# preflight.sh is kept as a thin redirect to this script.
#
# Behavior:
#   - Loads `tooling/docs-lint/forbidden.json` for the pattern list.
#   - Walks committed in-scope paths (skips zerolang/, node_modules/, .git/, etc.).
#   - Strips marker-bounded ranges (`<!-- docs-lint:allow-superseded-start --> ... -->`).
#   - Emits `DOC001` diagnostics per match.
#   - `--json` outputs one JSON envelope. Otherwise prints human-readable lines.
#   - Exit 0 on clean; exit 1 if any forbidden pattern matched outside markers.

set -u
umask 077

cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
ROOT="$(pwd)"

FORBIDDEN_FILE="$ROOT/tooling/docs-lint/forbidden.json"
if [[ ! -f "$FORBIDDEN_FILE" ]]; then
  echo "docs-lint: $FORBIDDEN_FILE not found" >&2
  exit 1
fi

JSON_OUTPUT=0
for arg in "$@"; do
  if [[ "$arg" == "--json" ]]; then
    JSON_OUTPUT=1
  fi
done

# Parse the forbidden list once into a temp file: each row is
# `pattern<TAB>severity<TAB>isRawToken<TAB>note`.
PATTERNS_TSV=$(mktemp)
trap 'rm -f "$PATTERNS_TSV"' EXIT
jq -r '.patterns[] | [.pattern, .severity, (.isRawToken // false), .note] | @tsv' "$FORBIDDEN_FILE" > "$PATTERNS_TSV"

MARKER_START=$(jq -r '.allowMarkers.start' "$FORBIDDEN_FILE")
MARKER_END=$(jq -r '.allowMarkers.end' "$FORBIDDEN_FILE")

# Build an awk-script-friendly ignore filter from forbidden.json's ignorePaths.
IGNORE_PATTERNS=$(jq -r '.ignorePaths[] | "|" + .' "$FORBIDDEN_FILE" | tr -d '\n')
IGNORE_RE="${IGNORE_PATTERNS#|}"

# Targets we lint.
TARGETS=(
  "$ROOT/.scratch"
  "$ROOT/docs"
  "$ROOT/src"
  "$ROOT/tests"
  "$ROOT/tools"
  "$ROOT/tooling"
  "$ROOT/plugins"
  "$ROOT/runtime"
  "$ROOT/CONTEXT.md"
  "$ROOT/CLAUDE.md"
  "$ROOT/AGENTS.md"
)

EXISTING=()
for t in "${TARGETS[@]}"; do
  [[ -e "$t" ]] && EXISTING+=("$t")
done

FILES=$(find "${EXISTING[@]}" -type f \
  \( -name '*.md' -o -name '*.0' -o -name '*.json' -o -name '*.sh' \) 2>/dev/null \
  | grep -vE "$IGNORE_RE" || true)

VIOLATIONS_JSON=()
VIOLATION_COUNT=0
FILES_CHECKED=0

for file in $FILES; do
  FILES_CHECKED=$((FILES_CHECKED + 1))

  STRIPPED=$(awk -v start="$MARKER_START" -v end="$MARKER_END" '
    BEGIN { inside = 0; ln = 0 }
    { ln++ }
    index($0, start) > 0 { inside = 1; print ""; next }
    index($0, end)   > 0 { inside = 0; print ""; next }
    inside == 0 { print }
    inside == 1 { print "" }
  ' "$file")

  while IFS=$'\t' read -r pattern severity is_raw note; do
    matched_lines=$(printf '%s\n' "$STRIPPED" | grep -nF -- "$pattern" 2>/dev/null || true)
    if [[ -z "$matched_lines" ]]; then
      continue
    fi
    while IFS= read -r match_line; do
      line_no="${match_line%%:*}"
      VIOLATION_COUNT=$((VIOLATION_COUNT + 1))
      if (( JSON_OUTPUT == 1 )); then
        diag_json=$(jq -nc \
          --arg path "${file#$ROOT/}" \
          --argjson line "${line_no:-0}" \
          --arg pattern "$pattern" \
          --arg severity "$severity" \
          --arg note "$note" \
          '{ code: "DOC001", severity: $severity, path: $path, line: $line, message: ("forbidden pattern: " + $pattern + " (" + $note + ")"), help: "wrap in <!-- docs-lint:allow-superseded-start --> ... <!-- docs-lint:allow-superseded-end --> if intentionally documenting the retired vocabulary; otherwise rename per the cited ADR." }')
        VIOLATIONS_JSON+=("$diag_json")
      else
        printf '%s:%s: %s: %s — %s\n' "${file#$ROOT/}" "$line_no" "$severity" "$pattern" "$note" >&2
      fi
    done <<< "$matched_lines"
  done < "$PATTERNS_TSV"
done

if (( JSON_OUTPUT == 1 )); then
  ok=true
  if (( VIOLATION_COUNT > 0 )); then ok=false; fi
  # Build the diagnostics array.
  diags_str=$(printf '%s\n' "${VIOLATIONS_JSON[@]:-}" | jq -sc '.')
  jq -nc \
    --argjson ok "$ok" \
    --argjson diagnostics "$diags_str" \
    --argjson filesChecked "$FILES_CHECKED" \
    '{ schemaVersion: 1, ok: $ok, diagnostics: $diagnostics, meta: { filesChecked: $filesChecked, truncated: false } }'
fi

if (( VIOLATION_COUNT == 0 )); then
  if (( JSON_OUTPUT == 0 )); then
    echo "docs-lint: clean ($FILES_CHECKED files checked)"
  fi
  exit 0
fi

if (( JSON_OUTPUT == 0 )); then
  echo "docs-lint: $VIOLATION_COUNT violation(s) across $FILES_CHECKED file(s)" >&2
fi
exit 1
