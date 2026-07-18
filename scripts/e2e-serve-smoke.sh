#!/usr/bin/env bash
# Copyright (c) 2026 Pedro Shakour
# SPDX-License-Identifier: Apache-2.0

# Golden-path smoke: official `grok agent serve` over WebSocket + Secret.
# Usage: XAI_API_KEY=xai-... bash scripts/e2e-serve-smoke.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${GROK_ACP_HOST:-127.0.0.1}"
PORT="${GROK_ACP_PORT:-2419}"
SECRET="${GROK_AGENT_SECRET:-$(openssl rand -hex 12)}"
SERVE_PID=""
SERVE_LOG="$ROOT/build/e2e-serve-smoke.log"

cleanup() {
  if [[ -n "$SERVE_PID" ]] && kill -0 "$SERVE_PID" 2>/dev/null; then
    kill "$SERVE_PID" 2>/dev/null || true
    wait "$SERVE_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if [[ -z "${XAI_API_KEY:-}" ]]; then
  echo "SKIP: e2e-serve-smoke (set XAI_API_KEY to run against real grok agent serve)"
  exit 0
fi

if ! command -v grok >/dev/null 2>&1; then
  echo "SKIP: e2e-serve-smoke (grok CLI not on PATH)"
  exit 0
fi

if command -v lsof >/dev/null 2>&1; then
  STALE=$(lsof -ti tcp:"$PORT" 2>/dev/null || true)
  if [[ -n "$STALE" ]]; then
    kill $STALE 2>/dev/null || true
    sleep 0.5
  fi
fi

echo "=== ACP e2e smoke (grok agent serve / WebSocket) ==="
mkdir -p "$ROOT/build"
export PATH="${HOME}/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
grok agent serve --bind "${HOST}:${PORT}" --secret "$SECRET" >"$SERVE_LOG" 2>&1 &
SERVE_PID=$!

for _ in $(seq 1 40); do
  if python3 -c "import socket; s=socket.create_connection(('$HOST',$PORT),1); s.close()" 2>/dev/null; then
    break
  fi
  sleep 0.25
done

if ! python3 -c "import socket; s=socket.create_connection(('$HOST',$PORT),1); s.close()" 2>/dev/null; then
  echo "FAIL: grok agent serve did not start" >&2
  tail -30 "$SERVE_LOG" >&2 || true
  exit 1
fi

python3 "$ROOT/companion/scripts/ws_acp_smoke.py" \
  --host "$HOST" \
  --port "$PORT" \
  --secret "$SECRET" \
  --cwd "${GROK_COMPANION_CWD:-/tmp}"

echo "=== ACP e2e serve smoke passed ==="
