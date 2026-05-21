#!/usr/bin/env bash
# Cursor hook: surface `zero check` diagnostics back to the agent whenever a
# Zero source file (.0) is written, edited, or read.
#
# Wired in /.cursor/hooks.json under `postToolUse` (matcher: Write|Edit|MultiEdit|Read).
# Always exits 0 with a JSON body containing `additional_context`. The hook is
# fail-open: if anything goes wrong (no zero on PATH, no .0 file, parse error in
# the hook itself), we return an empty JSON object so the agent loop is never
# blocked.
#
# Contract:
#   stdin  -> Cursor postToolUse JSON envelope.
#   stdout -> `{"additional_context": "..."}` or `{}`.
#
# Behavior:
#   - Pull `tool_input.file_path` (Read) or `tool_input.target_file` /
#     `tool_input.path` (Edit/Write variants) from the JSON.
#   - If the path does not end in `.0`, exit empty.
#   - Find the nearest enclosing `zero.json` walking upward. If found, run
#     `zero check --json <package-dir>` so package-mode diagnostics are honored.
#     Otherwise fall back to single-file mode `zero check --json <file>`.
#   - Filter to error/warning diagnostics only. Format each as
#     `path:line:col CODE severity: message` plus the `help` field when present.
#   - Cap total injected text to ~4 KiB (Cursor's per-hook payload budget is
#     small; oversized context is dropped silently with a TRUNCATED marker).

set -u
umask 077

# -------- 1. Read stdin envelope -----------------------------------------
INPUT=$(cat || true)
if [[ -z "${INPUT}" ]]; then
  echo '{}'
  exit 0
fi

# Pull file path. Different tools use different keys; jq's `//` picks the first
# non-null. Empty string when none match (so the .0 guard below trips).
FILE_PATH=$(jq -r '
  .tool_input.file_path
  // .tool_input.target_file
  // .tool_input.path
  // .file_path
  // empty
' <<<"${INPUT}" 2>/dev/null || true)

if [[ -z "${FILE_PATH}" ]]; then
  echo '{}'
  exit 0
fi

# Only act on Zero source. Skip everything else (markdown, json, sh, etc.).
case "${FILE_PATH}" in
  *.0) ;;
  *) echo '{}'; exit 0 ;;
esac

# -------- 2. Locate `zero` and resolve target ----------------------------
ZERO_BIN=""
if command -v zero >/dev/null 2>&1; then
  ZERO_BIN="$(command -v zero)"
elif [[ -x "${HOME}/.zero/bin/zero" ]]; then
  ZERO_BIN="${HOME}/.zero/bin/zero"
else
  echo '{}'
  exit 0
fi

# If the file is missing (deleted between tool call and hook), bail.
if [[ ! -e "${FILE_PATH}" ]]; then
  echo '{}'
  exit 0
fi

# Walk up to find the nearest `zero.json`. Package-mode check gives richer
# results (imports, manifest, targets). Stop at the workspace root to avoid
# climbing past the repo.
WORKSPACE_ROOT="/Users/harsha/Developer/agentguard"
PKG_DIR=""
search_dir="$(cd "$(dirname "${FILE_PATH}")" 2>/dev/null && pwd)" || search_dir=""
while [[ -n "${search_dir}" && "${search_dir}" != "/" ]]; do
  if [[ -f "${search_dir}/zero.json" ]]; then
    PKG_DIR="${search_dir}"
    break
  fi
  # Don't climb past the workspace.
  if [[ "${search_dir}" == "${WORKSPACE_ROOT}" ]]; then
    break
  fi
  search_dir="$(dirname "${search_dir}")"
done

# -------- 3. Run zero check ---------------------------------------------
TARGET="${PKG_DIR:-${FILE_PATH}}"
# 8-second budget; Cursor will kill the hook if it goes over the configured
# timeout, but `zero check` on small files completes in <500ms.
ZERO_OUT=$(timeout 8 "${ZERO_BIN}" check --json "${TARGET}" 2>/dev/null || true)

if [[ -z "${ZERO_OUT}" ]]; then
  echo '{}'
  exit 0
fi

# -------- 4. Filter + format diagnostics --------------------------------
# Keep only error and warning severities. Format as a compact block so the
# agent sees them on the next turn without extra parsing. Skip info/note.
DIAG_BLOCK=$(jq -r '
  if (.ok == true) then
    ""
  else
    [ .diagnostics[]?
      | select(.severity == "error" or .severity == "warning" or .severity == "warn")
      | "  \(.path // "?"):\(.line // 0):\(.column // 0)  \(.code // "???")  \(.severity | ascii_upcase): \(.message)"
        + (if .help and (.help | length) > 0 then "\n    help: \(.help)" else "" end)
    ] | join("\n")
  end
' <<<"${ZERO_OUT}" 2>/dev/null || true)

if [[ -z "${DIAG_BLOCK}" ]]; then
  # No actionable diagnostics. Stay silent so the agent's context isn't
  # spammed with "ok" markers on every edit.
  echo '{}'
  exit 0
fi

# Compose the human/agent-readable context block.
HEADER="[zero-diagnostics] (auto-run on ${FILE_PATH##*/}; target=${TARGET})"
FOOTER="(rerun with: ${ZERO_BIN##*/} check --json ${TARGET})"
CONTEXT_TEXT="${HEADER}
${DIAG_BLOCK}
${FOOTER}"

# Cap to ~4 KiB. Cursor's additional_context budget is small; oversize is
# dropped by Cursor anyway. Truncate explicitly so we know what got cut.
MAX_BYTES=4096
BYTES=${#CONTEXT_TEXT}
if (( BYTES > MAX_BYTES )); then
  CONTEXT_TEXT="${CONTEXT_TEXT:0:$((MAX_BYTES - 80))}
... [TRUNCATED — $((BYTES - MAX_BYTES + 80)) bytes dropped; run zero check manually for full list]"
fi

# Emit the JSON payload. jq -Rs builds a properly escaped JSON string.
jq -Rs '{ additional_context: . }' <<<"${CONTEXT_TEXT}"
exit 0
