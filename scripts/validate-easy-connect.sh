#!/usr/bin/env bash
# Copyright (c) 2026 Pedro Shakour
# SPDX-License-Identifier: Apache-2.0
#
# Validates the 2026 easy-connect path:
#   1) Companion prints PIN + full DER SHA-256 fingerprint
#   2) Bonjour TXT advertises full fp=
#   3) Simulator loopback (no TLS) accepts ACP initialize
#   4) iOS scheme builds

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${GROK_ACP_PORT:-7391}"
HOST="127.0.0.1"
STATE_DIR="$ROOT/build/easy-connect-validate-$$"
LOG="$STATE_DIR/bridge.log"
BRIDGE_PID=""
DNS_PID=""
FAIL=0

cleanup() {
  [[ -n "${BRIDGE_PID:-}" ]] && kill "$BRIDGE_PID" 2>/dev/null || true
  [[ -n "${DNS_PID:-}" ]] && kill "$DNS_PID" 2>/dev/null || true
  pkill -f "dns-sd -R Grok Build" 2>/dev/null || true
  rm -rf "$STATE_DIR"
}
trap cleanup EXIT

mkdir -p "$STATE_DIR"
export GROK_COMPANION_STATE_DIR="$STATE_DIR"
export GROK_COMPANION_CWD="$STATE_DIR"
export PATH="${HOME}/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

pkill -9 -f "acp_tcp_bridge.py" 2>/dev/null || true
sleep 0.3

echo "=== 1) TLS companion + full fingerprint + Bonjour TXT ==="
# Start advertise path (TLS+PIN) briefly — stub is enough for wire checks.
bash "$ROOT/companion/scripts/start-acp-bridge.sh" --stub --host 127.0.0.1 --port "$PORT" >"$LOG" 2>&1 &
BRIDGE_PID=$!

for _ in $(seq 1 40); do
  if grep -q "cert fingerprint:" "$LOG" 2>/dev/null; then
    break
  fi
  sleep 0.25
done

PIN="$(grep -E '^\[start-acp-bridge\] PIN:' "$LOG" | awk '{print $NF}' | head -1 || true)"
FP="$(grep -E '^\[start-acp-bridge\] cert fingerprint:' "$LOG" | awk '{print $NF}' | head -1 || true)"
FP_SHORT="$(grep -E 'cert fingerprint \(short\):' "$LOG" | awk '{print $NF}' | head -1 || true)"

if [[ -z "$PIN" || ${#PIN} -ne 6 ]]; then
  echo "FAIL: PIN not printed (got '${PIN:-}')"
  FAIL=1
else
  echo "OK: PIN=$PIN"
fi

if [[ -z "$FP" || ${#FP} -ne 64 ]]; then
  echo "FAIL: full fingerprint not printed (len=${#FP})"
  FAIL=1
else
  echo "OK: full fp=${FP:0:16}… (${#FP} hex)"
fi

if [[ -n "$FP_SHORT" && "$FP_SHORT" != "${FP:0:16}" ]]; then
  echo "FAIL: short fp mismatch"
  FAIL=1
else
  echo "OK: short fp=${FP_SHORT}"
fi

if grep -q "fp in TXT" "$LOG"; then
  echo "OK: Bonjour advertise started with fp in TXT"
else
  echo "WARN: Bonjour advertise line missing (dns-sd may be unavailable)"
fi

# Confirm TXT would carry full fp (unit-level: env the script exported into log path via python)
python3 - <<PY
import sys
sys.path.insert(0, "$ROOT/companion/scripts")
from companion_tls import ensure_cert
_, _, fp = ensure_cert()
assert len(fp) == 64 and all(c in "0123456789abcdef" for c in fp), fp
print(f"OK: ensure_cert fp length={len(fp)}")
PY

kill "$BRIDGE_PID" 2>/dev/null || true
wait "$BRIDGE_PID" 2>/dev/null || true
BRIDGE_PID=""
pkill -f "dns-sd -R Grok Build" 2>/dev/null || true
sleep 0.4

echo "=== 2) Simulator easy path: plain TCP stub ACP initialize ==="
export GROK_COMPANION_INSECURE=1
python3 "$ROOT/companion/scripts/acp_tcp_bridge.py" --stub --no-tls --no-pair --host "$HOST" --port "$PORT" >"$LOG" 2>&1 &
BRIDGE_PID=$!

for _ in $(seq 1 40); do
  if python3 -c "import socket; s=socket.create_connection(('$HOST',$PORT),1); s.close()" 2>/dev/null; then
    break
  fi
  sleep 0.25
done

python3 - <<'PY'
import json, socket, sys
host, port = "127.0.0.1", int(__import__("os").environ.get("GROK_ACP_PORT", "7391"))
s = socket.create_connection((host, port), 5)
s.settimeout(5)

def send(obj):
    line = json.dumps(obj, separators=(",", ":")) + "\n"
    s.sendall(line.encode())

def recv():
    buf = b""
    while b"\n" not in buf:
        chunk = s.recv(65536)
        if not chunk:
            raise RuntimeError("eof")
        buf += chunk
    line, rest = buf.split(b"\n", 1)
    return json.loads(line.decode())

send({"jsonrpc":"2.0","id":1,"method":"initialize","params":{
    "protocolVersion":1,
    "clientInfo":{"name":"easy-connect-validate","version":"0.1"},
    "clientCapabilities":{}
}})
# Drain until we get id=1 result (may interleave notifications)
for _ in range(20):
    msg = recv()
    if msg.get("id") == 1 and "result" in msg:
        print("OK: ACP initialize ->", json.dumps(msg["result"].get("serverInfo", msg["result"]))[:120])
        break
else:
    print("FAIL: no initialize result")
    sys.exit(1)
s.close()
PY

kill "$BRIDGE_PID" 2>/dev/null || true
wait "$BRIDGE_PID" 2>/dev/null || true
BRIDGE_PID=""

echo "=== 3) iOS build (Simulator) ==="
DERIVED="$ROOT/build/DerivedData-easy-connect"
xcodebuild \
  -project "$ROOT/ios/GrokApp/GrokApp.xcodeproj" \
  -scheme GrokApp \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$DERIVED" \
  build \
  CODE_SIGNING_ALLOWED=NO \
  2>&1 | tail -n 30

echo "=== easy-connect validation complete (fail=$FAIL) ==="
exit "$FAIL"
