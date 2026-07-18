#!/usr/bin/env bash
# Copyright (c) 2026 Pedro Shakour
# SPDX-License-Identifier: Apache-2.0

# Launch-phase smoke + stress: assets, stub ACP, iOS-shaped ACP, optional real grok.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAILED=0
PROJECT="$ROOT/ios/GrokApp/GrokApp.xcodeproj"
SCHEME="GrokApp"

fail() { echo "FAIL: $*" >&2; FAILED=1; }
pass() { echo "OK: $*"; }

echo "=== Grok Build iOS launch smoketest ==="

# --- Phase 1: baseline smoketest ---
if bash "$ROOT/scripts/smoketest.sh"; then
  pass "baseline smoketest"
else
  fail "baseline smoketest"
fi

# --- Phase 2: iOS-shaped ACP (cwd '.', clientCapabilities) via stub ---
export GROK_COMPANION_STATE_DIR="${GROK_COMPANION_STATE_DIR:-$ROOT/.grok-companion-state}"
BRIDGE_PY="$ROOT/companion/scripts/acp_tcp_bridge.py"
HOST="127.0.0.1"
PORT="7392"
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
  [[ -n "$STALE" ]] && kill $STALE 2>/dev/null || true
  sleep 0.3
fi

export GROK_COMPANION_INSECURE=1
python3 "$BRIDGE_PY" --stub --no-tls --no-pair --host "$HOST" --port "$PORT" &
BRIDGE_PID=$!
sleep 0.5

if python3 - "$HOST" "$PORT" <<'PY'; then
import json, socket, sys, time
host, port = sys.argv[1], int(sys.argv[2])

def rpc(sock, method, params, req_id, timeout=10):
    sock.sendall((json.dumps({"jsonrpc":"2.0","method":method,"params":params,"id":req_id})+"\n").encode())
    buf = b""
    deadline = time.time() + timeout
    while time.time() < deadline:
        chunk = sock.recv(8192)
        if not chunk:
            break
        buf += chunk
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            if not line.strip():
                continue
            obj = json.loads(line)
            if obj.get("id") == req_id:
                if obj.get("error"):
                    raise RuntimeError(obj["error"])
                return obj
    raise TimeoutError(method)

sock = socket.create_connection((host, port), 5)
# Exact iOS client params
rpc(sock, "initialize", {
    "protocolVersion": 1,
    "clientCapabilities": {"fs": {"readTextFile": False, "writeTextFile": False}},
}, 1)
rpc(sock, "authenticate", {"methodId": "xai.api_key", "_meta": {"xaiApiKey": "ios-shape-test"}}, 2)
r = rpc(sock, "session/new", {"cwd": ".", "mcpServers": []}, 3)
sid = r["result"]["sessionId"]
rpc(sock, "session/prompt", {"sessionId": sid, "prompt": [{"type": "text", "text": "hi"}]}, 4)
sock.close()
print("ios-shaped stub handshake + prompt")
PY
  pass "iOS-shaped ACP stub"
else
  fail "iOS-shaped ACP stub"
fi

# --- Phase 3: real bridge cwd normalization (no API spend if grok missing) ---
if command -v grok >/dev/null 2>&1; then
  kill "$BRIDGE_PID" 2>/dev/null || true
  wait "$BRIDGE_PID" 2>/dev/null || true
  BRIDGE_PID=""
  PORT=7393
  STALE=$(lsof -ti tcp:"$PORT" 2>/dev/null || true)
  [[ -n "$STALE" ]] && kill $STALE 2>/dev/null || true
  export GROK_COMPANION_CWD="$ROOT"
  export GROK_COMPANION_INSECURE=1
  python3 "$BRIDGE_PY" --real --no-tls --no-pair --host "$HOST" --port "$PORT" &
  BRIDGE_PID=$!
  sleep 1
  if python3 - "$HOST" "$PORT" <<'PY'; then
import json, socket, sys, time
host, port = sys.argv[1], int(sys.argv[2])

def rpc(sock, method, params, req_id, timeout=45):
    sock.sendall((json.dumps({"jsonrpc":"2.0","method":method,"params":params,"id":req_id})+"\n").encode())
    buf = b""
    deadline = time.time() + timeout
    while time.time() < deadline:
        chunk = sock.recv(8192)
        if not chunk:
            break
        buf += chunk
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            if not line.strip():
                continue
            obj = json.loads(line)
            if obj.get("id") == req_id:
                if obj.get("error"):
                    raise RuntimeError(obj["error"])
                return obj
    raise TimeoutError(method)

sock = socket.create_connection((host, port), 5)
rpc(sock, "initialize", {"protocolVersion": 1, "clientCapabilities": {"fs": {"readTextFile": False, "writeTextFile": False}}}, 1)
rpc(sock, "authenticate", {"methodId": "xai.api_key", "_meta": {"xaiApiKey": "cwd-normalize-test"}}, 2)
r = rpc(sock, "session/new", {"cwd": ".", "mcpServers": []}, 3, timeout=60)
assert r.get("result", {}).get("sessionId"), r
sock.close()
print("real bridge cwd '.' normalized")
PY
    pass "real bridge cwd normalization"
  else
    fail "real bridge cwd normalization"
  fi
else
  echo "SKIP: grok not on PATH (real cwd test)"
fi

# --- Phase 4: stress — 10 rapid stub handshakes ---
kill "$BRIDGE_PID" 2>/dev/null || true
wait "$BRIDGE_PID" 2>/dev/null || true
BRIDGE_PID=""
PORT=7394
STALE=$(lsof -ti tcp:"$PORT" 2>/dev/null || true)
[[ -n "$STALE" ]] && kill $STALE 2>/dev/null || true
export GROK_COMPANION_INSECURE=1
python3 "$BRIDGE_PY" --stub --no-tls --no-pair --host "$HOST" --port "$PORT" &
BRIDGE_PID=$!
sleep 0.5

if python3 - "$HOST" "$PORT" <<'PY'; then
import json, socket, sys
host, port = sys.argv[1], int(sys.argv[2])
for i in range(10):
    sock = socket.create_connection((host, port), 5)
    msg = {"jsonrpc":"2.0","method":"initialize","params":{"protocolVersion":1},"id":i}
    sock.sendall((json.dumps(msg)+"\n").encode())
    sock.close()
print("10 rapid connects")
PY
  pass "stress 10 rapid connects"
else
  fail "stress 10 rapid connects"
fi

# --- Phase 5: Swift unit tests ---
if command -v xcodebuild >/dev/null 2>&1; then
  SIM_UDID=$(xcrun simctl list devices available 2>/dev/null \
    | awk -F'[()]' '/iPhone 17 Pro \(/ && !u { u=$2 } /iPhone/ && !u { u=$2 } END { print u }')
  if [[ -n "$SIM_UDID" ]]; then
    echo "--- Swift unit tests ---"
    if xcodebuild test \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -destination "id=$SIM_UDID" \
      -only-testing:GrokAppTests/ACPProtocolTests \
      -only-testing:GrokAppTests/SlashCommandCatalogTests \
      CODE_SIGNING_ALLOWED=NO \
      -quiet 2>&1; then
      pass "Swift unit tests"
    else
      fail "Swift unit tests"
    fi
  else
    echo "SKIP: no simulator for unit tests"
  fi
fi

echo "=== launch smoketest complete ==="
if [[ "$FAILED" -ne 0 ]]; then
  exit 1
fi
echo "All launch checks passed."
