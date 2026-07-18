#!/usr/bin/env bash
# Copyright (c) 2026 Pedro Shakour
# SPDX-License-Identifier: Apache-2.0

# End-to-end ACP stub smoke (TEST-ONLY legacy TCP bridge).
# Golden path: scripts/e2e-serve-smoke.sh (`grok agent serve` WebSocket).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BRIDGE_PY="$ROOT/companion/scripts/acp_tcp_bridge.py"
export GROK_COMPANION_STATE_DIR="${GROK_COMPANION_STATE_DIR:-$ROOT/.grok-companion-state}"
HOST="${GROK_ACP_HOST:-127.0.0.1}"
PORT="${GROK_ACP_PORT:-7391}"
BRIDGE_PID=""

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

echo "=== ACP e2e smoke (stub) ==="

export GROK_COMPANION_INSECURE=1
python3 "$BRIDGE_PY" --stub --no-tls --no-pair --host "$HOST" --port "$PORT" &
BRIDGE_PID=$!

# Wait for TCP listener (up to 5s)
for _ in $(seq 1 10); do
  if python3 -c "import socket; s=socket.create_connection(('$HOST', $PORT), 1); s.close()" 2>/dev/null; then
    break
  fi
  sleep 0.5
done

if ! kill -0 "$BRIDGE_PID" 2>/dev/null; then
  echo "FAIL: bridge did not start" >&2
  exit 1
fi

python3 - "$HOST" "$PORT" <<'PY'
import json
import socket
import sys
import time

host, port = sys.argv[1], int(sys.argv[2])

def rpc(sock, method, params, req_id):
    msg = {"jsonrpc": "2.0", "method": method, "params": params, "id": req_id}
    sock.sendall((json.dumps(msg) + "\n").encode("utf-8"))

def read_lines(sock, timeout=5.0, max_lines=32):
    sock.settimeout(timeout)
    buf = b""
    lines = []
    deadline = time.time() + timeout
    while len(lines) < max_lines and time.time() < deadline:
        try:
            chunk = sock.recv(4096)
        except socket.timeout:
            break
        if not chunk:
            break
        buf += chunk
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            text = line.decode("utf-8", errors="replace").strip()
            if text:
                lines.append(json.loads(text))
    return lines

sock = socket.create_connection((host, port), timeout=5)
rpc(sock, "initialize", {"protocolVersion": 1}, 1)
rpc(sock, "authenticate", {
    "methodId": "xai.api_key",
    "_meta": {"xaiApiKey": "xai-smoke-test-key"},
}, 2)
rpc(sock, "session/new", {"cwd": "/tmp", "mcpServers": []}, 3)

# Read until sessionId
lines = []
buf = b""
sock.settimeout(3.0)
sid = None
deadline = time.time() + 5
while time.time() < deadline and sid is None:
    try:
        chunk = sock.recv(4096)
    except socket.timeout:
        break
    if not chunk:
        break
    buf += chunk
    while b"\n" in buf:
        line, buf = buf.split(b"\n", 1)
        text = line.decode("utf-8", errors="replace").strip()
        if not text:
            continue
        obj = json.loads(text)
        lines.append(obj)
        sid = (obj.get("result") or {}).get("sessionId")

if not sid:
    print("FAIL: no sessionId", file=sys.stderr)
    print("lines:", json.dumps(lines, indent=2)[:2000], file=sys.stderr)
    sys.exit(1)

rpc(sock, "session/prompt", {"sessionId": sid, "prompt": [{"type": "text", "text": "smoke test"}]}, 4)

more = read_lines(sock, timeout=6.0)
lines.extend(more)
sock.close()

assistant = False
tool = False
for obj in lines:
    if obj.get("method") == "session/update":
        upd = (obj.get("params") or {}).get("update") or {}
        kind = upd.get("sessionUpdate", "")
        if kind == "agent_message_chunk":
            content = upd.get("content") or {}
            if content.get("text"):
                assistant = True
        if kind in ("tool_call", "tool_call_update"):
            tool = True

if not assistant:
    print("FAIL: no assistant chunk in stub response", file=sys.stderr)
    print("lines:", json.dumps(lines, indent=2)[:2000], file=sys.stderr)
    sys.exit(1)
if not tool:
    print("FAIL: no tool_call in stub response", file=sys.stderr)
    print("lines:", json.dumps(lines, indent=2)[:2000], file=sys.stderr)
    sys.exit(1)

print("OK: assistant + tool_call received via ACP stub")
PY

echo "=== ACP e2e smoke passed ==="
