#!/usr/bin/env bash
# Build agentguard binary for darwin-arm64 using the --emit obj + cc link
# path. Required because std.fs.exists and other hosted I/O calls need the
# zero_runtime.c shim on darwin-arm64 (see AGENTS.md).
#
# For linux-musl-x64 CI, use zerolang/bin/zero build --emit exe directly.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
ROOT="$(pwd)"

ZERO="$ROOT/zerolang/bin/zero"
RUNTIME="$ROOT/runtime/zero_runtime.c"
OUT="$ROOT/bin/agentguard"
OBJ="$ROOT/.zero/build/agentguard.o"

if [[ ! -x "$ZERO" ]]; then
  echo "build: zerolang compiler not found at $ZERO" >&2
  echo "  run: make -C zerolang/native/zero-c" >&2
  exit 1
fi

mkdir -p "$(dirname "$OBJ")"

echo "build: compiling to object..."
"$ZERO" build --emit obj --target darwin-arm64 "$ROOT" --out "$OBJ"

echo "build: linking with runtime..."
/usr/bin/cc "$OBJ" "$RUNTIME" -o "$OUT"

echo "build: done → $OUT ($(wc -c < "$OUT" | tr -d ' ') bytes)"
"$OUT" --version
