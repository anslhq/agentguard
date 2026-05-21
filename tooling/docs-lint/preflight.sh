#!/usr/bin/env bash
# Compatibility wrapper. The grep-based preflight from Issue 00 was retired
# by Issue 26's full docs-lint tool. This wrapper preserves the old
# `preflight.sh` entry point used by README's pre-implementation gate.
#
# All actual logic lives in `docs-lint.sh`.

exec "$(dirname "${BASH_SOURCE[0]}")/docs-lint.sh" "$@"
