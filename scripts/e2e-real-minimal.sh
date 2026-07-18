#!/usr/bin/env bash
# Copyright (c) 2026 Pedro Shakour
# SPDX-License-Identifier: Apache-2.0

# Minimal real grok smoke: one short prompt via ACP (keep API cost negligible).
# Usage: XAI_API_KEY=xai-... bash scripts/e2e-real-minimal.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BRIDGE_PY="$ROOT/companion/scripts/acp_tcp_bridge.py"
export GROK_COMPANION_STATE_DIR="${GROK_COMPANION_STATE_DIR:-$ROOT/.grok-companion-state}"
export GROK_COMPANION_CWD="${GROK_COMPANION_CWD:-$ROOT}"
HOST="${GROK_ACP_HOST:-127.0.0.1}"
PORT="${GROK_ACP_PORT:-7391}"
BRIDGE_PID=""

if [[ -z "${XAI_API_KEY:-}" ]]; then
  echo "FAIL: set XAI_API_KEY (not stored in repo)" >&2
  exit 1
fi

cleanup() {
  if [[ -n "$BRIDGE_PID" ]] && kill -0 "$BRIDGE_PID" 2>/dev/null; then
    kill "$BRIDGE_PID" 2>/dev/null || true
    wait "$BRIDGE_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if command -v lsof >/dev/null 2>&1; then
  STALE=$(lsof -ti tcp:"$PORT" 2>/dev/null || true)
  if [[ -n "$STALE" ]]; then
    kill $STALE 2>/dev/null || true
    sleep 0.5
  fi
fi

echo "=== ACP e2e smoke (real grok, minimal prompt) ==="

export GROK_COMPANION_INSECURE=1
python3 "$BRIDGE_PY" --real --no-tls --no-pair --host "$HOST" --port "$PORT" &
BRIDGE_PID=$!

for _ in $(seq 1 20); do
  if python3 -c "import socket; s=socket.create_connection(('$HOST', $PORT), 1); s.close()" 2>/dev/null; then
    break
  fi
  sleep 0.25
done

if ! python3 -c "import socket; s=socket.create_connection(('$HOST', $PORT), 1); s.close()" 2>/dev/null; then
  echo "FAIL: real bridge did not start on ${HOST}:${PORT}" >&2
  exit 1
fi

python3 - "$HOST" "$PORT" <<'PY'
import json
import os
import socket
import sys
import time

host, port = sys.argv[1], int(sys.argv[2])
api_key = os.environ["XAI_API_KEY"]

def rpc(sock, method, params, req_id):
    msg = {"jsonrpc": "2.0", "method": method, "params": params, "id": req_id}
    sock.sendall((json.dumps(msg) + "\n").encode("utf-8"))

def read_lines(sock, timeout=45.0, max_lines=64):
    sock.settimeout(2.0)
    buf = b""
    lines = []
    deadline = time.time() + timeout
    while len(lines) < max_lines and time.time() < deadline:
        try:
            chunk = sock.recv(8192)
        except socket.timeout:
            continue
        if not chunk:
            break
        buf += chunk
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            text = line.decode("utf-8", errors="replace").strip()
            if text:
                lines.append(json.loads(text))
    return lines

sock = socket.create_connection((host, port), timeout=10)
rpc(sock, "initialize", {"protocolVersion": 1}, 1)
rpc(sock, "authenticate", {
    "methodId": "xai.api_key",
    "_meta": {"xaiApiKey": api_key},
}, 2)
rpc(sock, "session/new", {"cwd": os.environ.get("GROK_COMPANION_CWD", "/tmp"), "mcpServers": []}, 3)

lines = read_lines(sock, timeout=30.0)
sid = None
for obj in lines:
    sid = (obj.get("result") or {}).get("sessionId") or sid

if not sid:
    print("FAIL: no sessionId", file=sys.stderr)
    sys.exit(1)

# Cheapest meaningful check: one-line reply, no tools requested.
rpc(sock, "session/prompt", {
    "sessionId": sid,
    "prompt": [{"type": "text", "text": "Reply with exactly: OK"}],
}, 4)

more = read_lines(sock, timeout=60.0)
lines.extend(more)
sock.close()

assistant = False
snippet = ""
for obj in lines:
    if obj.get("method") == "session/update":
        upd = (obj.get("params") or {}).get("update") or {}
        if upd.get("sessionUpdate") == "agent_message_chunk":
            text = (upd.get("content") or {}).get("text") or ""
            if text.strip():
                assistant = True
                snippet += text

if not assistant:
    print("FAIL: no assistant chunk from real grok", file=sys.stderr)
    sys.exit(1)

preview = snippet.strip().replace("\n", " ")[:120]
print(f"OK: real grok replied ({len(snippet)} chars): {preview!r}")
PY

echo "=== ACP e2e real minimal passed ==="
