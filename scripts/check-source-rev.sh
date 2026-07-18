#!/usr/bin/env bash
# Copyright (c) 2026 Pedro Shakour
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PIN="$(tr -d '[:space:]' < "$ROOT/UPSTREAM_PIN")"
HEAD="$(git -C "$ROOT/upstream-grok-build" rev-parse HEAD 2>/dev/null || echo missing)"
if [[ "$HEAD" != "$PIN" ]]; then
  echo "FAIL: UPSTREAM_PIN $PIN != submodule HEAD $HEAD" >&2
  echo "Run: bash scripts/sync-upstream.sh" >&2
  exit 1
fi
echo "OK: upstream submodule @ $PIN"
