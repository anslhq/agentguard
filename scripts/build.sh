#!/usr/bin/env bash
# Build agentguard binary for darwin-arm64 using the --emit obj + cc link
# path. Required because std.fs.exists and other hosted I/O calls need
# the zero_runtime.c shim on darwin-arm64 (see AGENTS.md).
#
# The runtime now lives at zerolang/native/zero-c/runtime/zero_runtime.c
# (the upstream-PR-ready location). The previous standalone runtime at
# runtime/zero_runtime.c is kept for backwards-compat with older
# checkouts but no longer the source of truth.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
ROOT="$(pwd)"

ZERO="$ROOT/zerolang/bin/zero"
RUNTIME="$ROOT/zerolang/native/zero-c/runtime/zero_runtime.c"
RUNTIME_INCLUDE="$ROOT/zerolang/native/zero-c/include"
OUT="$ROOT/bin/agentguard"
OBJ="$ROOT/.zero/build/agentguard.o"

if [[ ! -x "$ZERO" ]]; then
  echo "build: zerolang compiler not found at $ZERO" >&2
  echo "  run: make -C zerolang/native/zero-c" >&2
  exit 1
fi

if [[ ! -f "$RUNTIME" ]]; then
  echo "build: zero_runtime.c not found at $RUNTIME" >&2
  echo "  the zerolang directory may be missing or out of date" >&2
  exit 1
fi

mkdir -p "$(dirname "$OBJ")"

echo "build: compiling to object..."
"$ZERO" build --emit obj --target darwin-arm64 "$ROOT" --out "$OBJ"

echo "build: linking with runtime..."
/usr/bin/cc "-I$RUNTIME_INCLUDE" "$OBJ" "$RUNTIME" -o "$OUT"

echo "build: done → $OUT ($(wc -c < "$OUT" | tr -d ' ') bytes)"
"$OUT" --version
