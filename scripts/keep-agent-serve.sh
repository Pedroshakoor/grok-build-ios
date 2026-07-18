#!/usr/bin/env bash
# Copyright (c) 2026 Pedro Shakour
# SPDX-License-Identifier: Apache-2.0

# Keep official `grok agent serve` running for iOS app (golden path).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST_BIND="${GROK_SERVE_BIND:-0.0.0.0:2419}"
PORT="${GROK_ACP_PORT:-2419}"
SECRET="${GROK_AGENT_SECRET:-$(openssl rand -hex 12)}"
LOG="$ROOT/build/serve-live.log"
PIDFILE="$ROOT/build/serve-live.pid"
export PATH="${HOME}/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

if [[ -z "${XAI_API_KEY:-}" ]]; then
  echo "FAIL: export XAI_API_KEY=xai-... first" >&2
  exit 1
fi

if ! command -v grok >/dev/null 2>&1; then
  echo "FAIL: grok CLI not on PATH" >&2
  exit 1
fi

mkdir -p "$ROOT/build"

if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  if python3 -c "import socket; s=socket.create_connection(('127.0.0.1',$PORT),1); s.close()" 2>/dev/null; then
    echo "OK: grok agent serve already running (pid $(cat "$PIDFILE"))"
    echo "Secret: $SECRET"
    LAN="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)"
    echo "Simulator host: 127.0.0.1  port: $PORT"
    [[ -n "$LAN" ]] && echo "Physical iPhone host: $LAN  port: $PORT"
    exit 0
  fi
fi

lsof -ti tcp:"$PORT" 2>/dev/null | xargs kill -9 2>/dev/null || true
pkill -9 -f "grok agent serve" 2>/dev/null || true
sleep 0.4

nohup grok agent serve --bind "$HOST_BIND" --secret "$SECRET" >>"$LOG" 2>&1 &
echo $! >"$PIDFILE"
disown

for _ in $(seq 1 30); do
  if python3 -c "import socket; s=socket.create_connection(('127.0.0.1',$PORT),1); s.close()" 2>/dev/null; then
    break
  fi
  sleep 0.25
done

if ! python3 -c "import socket; s=socket.create_connection(('127.0.0.1',$PORT),1); s.close()" 2>/dev/null; then
  echo "FAIL: grok agent serve did not start" >&2
  tail -20 "$LOG" >&2 || true
  exit 1
fi

LAN="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)"
echo "OK: grok agent serve running (pid $(cat "$PIDFILE"))"
echo "Secret: $SECRET"
echo "Simulator → Setup host 127.0.0.1  port $PORT"
if [[ -n "$LAN" ]]; then
  echo "Physical iPhone → Setup host $LAN  port $PORT"
else
  echo "Physical iPhone → use your Mac's Wi‑Fi IP (not 127.0.0.1)"
fi
