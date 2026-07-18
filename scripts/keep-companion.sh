#!/usr/bin/env bash
# Copyright (c) 2026 Pedro Shakour
# SPDX-License-Identifier: Apache-2.0

# Ensure companion is up (prefers launchd KeepAlive).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if python3 -c "import socket; s=socket.create_connection(('127.0.0.1',7391),1); s.close()" 2>/dev/null; then
  echo "OK: companion already listening on 127.0.0.1:7391"
  exit 0
fi
exec bash "$ROOT/scripts/install-companion-launchd.sh"
