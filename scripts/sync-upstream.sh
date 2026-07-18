#!/usr/bin/env bash
# Copyright (c) 2026 Pedro Shakour
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UP="$ROOT/upstream-grok-build"
PIN="$(tr -d '[:space:]' < "$ROOT/UPSTREAM_PIN")"
if [[ ! -d "$UP/.git" ]]; then
  echo "FAIL: run git submodule update --init" >&2
  exit 1
fi
cd "$UP"
git fetch origin main --quiet 2>/dev/null || true
git checkout "$PIN" --quiet
bash "$ROOT/scripts/check-source-rev.sh"
