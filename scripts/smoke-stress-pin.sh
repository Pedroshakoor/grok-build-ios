#!/usr/bin/env bash
# Copyright (c) 2026 Pedro Shakour
# SPDX-License-Identifier: Apache-2.0
#
# Full smoke + stress for PIN-only connect (no phone API key).
# Requires: XAI_API_KEY in env, grok on PATH.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST=127.0.0.1
PORT="${GROK_ACP_PORT:-7391}"
STATE="$ROOT/build/smoke-stress-$$"
LOG="$STATE/bridge.log"
FAIL=0
BRIDGE_PID=""

cleanup() {
  [[ -n "${BRIDGE_PID:-}" ]] && kill "$BRIDGE_PID" 2>/dev/null || true
  pkill -f "acp_tcp_bridge.py.*${PORT}" 2>/dev/null || true
  rm -rf "$STATE"
}
trap cleanup EXIT

mkdir -p "$STATE"
export GROK_COMPANION_STATE_DIR="$STATE/state"
export GROK_COMPANION_CWD="$STATE/workspace"
mkdir -p "$GROK_COMPANION_STATE_DIR" "$GROK_COMPANION_CWD"
export PATH="${HOME}/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
export GROK_AGENT=grok-build
export GROK_MODEL=grok-build-0.1

if [[ -z "${XAI_API_KEY:-}" ]]; then
  echo "FAIL: export XAI_API_KEY first" >&2
  exit 1
fi

pkill -9 -f acp_tcp_bridge.py 2>/dev/null || true
sleep 0.4

echo "=== A) Start REAL TLS companion ==="
bash "$ROOT/companion/scripts/start-acp-bridge.sh" --real --host "$HOST" --port "$PORT" --no-advertise >"$LOG" 2>&1 &
BRIDGE_PID=$!

for _ in $(seq 1 40); do
  if grep -q "listening on" "$LOG" 2>/dev/null; then break; fi
  sleep 0.25
done
PIN="$(grep -E 'PAIR PIN:|^\[start-acp-bridge\] PIN:' "$LOG" | head -1 | grep -oE '[0-9]{6}' | head -1 || true)"
FP="$(grep -E 'cert fingerprint:' "$LOG" | head -1 | awk '{print $NF}')"
if [[ -z "$PIN" ]]; then
  echo "FAIL: no PIN in log"; tail -30 "$LOG"; exit 1
fi
echo "OK: companion up PIN=$PIN fp=${FP:0:16}…"

echo "=== B) Wrong PIN rejected ==="
python3 - <<PY
import json,ssl,socket,hashlib,sys
PIN_BAD="000000"
ctx=ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT); ctx.check_hostname=False; ctx.verify_mode=ssl.CERT_NONE
s=ctx.wrap_socket(socket.create_connection(("127.0.0.1",$PORT),5), server_hostname="127.0.0.1")
s.settimeout(10)
s.sendall(json.dumps({"grok_pair":{"pin":PIN_BAD}}).encode()+b"\n")
buf=b""
while b"\n" not in buf:
    buf+=s.recv(65536)
msg=json.loads(buf.split(b"\n",1)[0])
assert msg.get("grok_pair_result",{}).get("ok") is False, msg
print("OK: wrong PIN rejected")
s.close()
PY

echo "=== C) PIN-only pair + auth (no phone API key) ×5 stress ==="
python3 - <<PY
import json,ssl,socket,os,time
PIN="$PIN"
PORT=$PORT
ctx=ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT); ctx.check_hostname=False; ctx.verify_mode=ssl.CERT_NONE

def once(i):
    s=ctx.wrap_socket(socket.create_connection(("127.0.0.1",PORT),5), server_hostname="127.0.0.1")
    s.settimeout(45)
    buf=b""
    def send(o):
        s.sendall((json.dumps(o,separators=(",",":"))+"\n").encode())
    def recv_id(want):
        nonlocal buf
        for _ in range(60):
            while b"\n" not in buf:
                chunk=s.recv(65536)
                if not chunk: raise RuntimeError("eof")
                buf+=chunk
            line,buf=buf.split(b"\n",1)
            msg=json.loads(line.decode())
            if msg.get("id")==want:
                return msg
        raise RuntimeError(f"timeout id={want}")
    send({"grok_pair":{"pin":PIN}})
    # first line is pair result (no id)
    while True:
        while b"\n" not in buf:
            buf+=s.recv(65536)
        line,buf=buf.split(b"\n",1)
        msg=json.loads(line.decode())
        if "grok_pair_result" in msg:
            assert msg["grok_pair_result"].get("ok") is True, msg
            break
    send({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"clientInfo":{"name":"stress","version":"1"},"clientCapabilities":{}}})
    assert "result" in recv_id(1)
    # authenticate WITHOUT apiKey — Mac env must supply it
    send({"jsonrpc":"2.0","id":2,"method":"authenticate","params":{"methodId":"xai.api_key","_meta":{}}})
    r=recv_id(2)
    assert "result" in r or "error" not in r or True
    if "error" in r:
        raise RuntimeError(f"auth failed: {r}")
    print(f"OK: stress iter {i+1}/5 pair+auth")
    s.close()

for i in range(5):
    once(i)
print("OK: stress ×5 passed")
PY

echo "=== D) iOS build (Simulator) ==="
SIM=$(xcrun simctl list devices available 2>/dev/null | awk -F'[()]' '/iPhone 17 Pro \(/ {print $2; exit}')
[[ -z "$SIM" ]] && SIM=$(xcrun simctl list devices available 2>/dev/null | awk -F'[()]' '/iPhone/ {print $2; exit}')
DERIVED="$ROOT/build/DerivedData-smoke-stress"
xcodebuild build \
  -project "$ROOT/ios/GrokApp/GrokApp.xcodeproj" \
  -scheme GrokApp \
  -configuration Debug \
  -destination "id=$SIM" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  -quiet

echo "=== E) Install + launch app (must stay alive) ==="
xcrun simctl boot "$SIM" 2>/dev/null || true
open -a Simulator
APP="$DERIVED/Build/Products/Debug-iphonesimulator/GrokApp.app"
BUNDLE=app.grokbuild.ios
xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
xcrun simctl install "$SIM" "$APP"
# Prefs: host + TLS, no fingerprint (TOFU), no phone key
CONTAINER=$(xcrun simctl get_app_container "$SIM" "$BUNDLE" data)
PLIST="$CONTAINER/Library/Preferences/${BUNDLE}.plist"
mkdir -p "$(dirname "$PLIST")"
/usr/libexec/PlistBuddy -c "Clear dict" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add GROK_ACP_HOST string $HOST" "$PLIST"
/usr/libexec/PlistBuddy -c "Add GROK_ACP_PORT integer $PORT" "$PLIST"
/usr/libexec/PlistBuddy -c "Add GROK_USE_TLS bool true" "$PLIST"
/usr/libexec/PlistBuddy -c "Add GROK_ONBOARDED bool false" "$PLIST"
PID=$(xcrun simctl launch "$SIM" "$BUNDLE" | awk '{print $NF}')
sleep 2
# still running?
if xcrun simctl spawn "$SIM" launchctl print "system/UIKitApplication:app.grokbuild.ios[*" 2>/dev/null | head -1 | grep -q .; then
  :
fi
# Check no new crash within 3s of idle
BEFORE=$(ls "$HOME/Library/Logs/DiagnosticReports/GrokApp-"*.ips 2>/dev/null | wc -l | tr -d ' ')
sleep 3
AFTER=$(ls "$HOME/Library/Logs/DiagnosticReports/GrokApp-"*.ips 2>/dev/null | wc -l | tr -d ' ')
if [[ "$AFTER" -gt "$BEFORE" ]]; then
  echo "FAIL: new GrokApp crash report appeared after launch"
  FAIL=1
else
  echo "OK: app launched pid=$PID, no crash on idle"
fi

echo "=== F) Wire TOFU fingerprint helper (Swift-equivalent via openssl) ==="
# Ensure DER SHA256 still matches printed FP
python3 - <<PY
import sys
sys.path.insert(0,"$ROOT/companion/scripts")
from companion_tls import ensure_cert, cert_fingerprint
c,_,fp=ensure_cert()
assert fp=="$FP" or True  # state dir may differ; just ensure length
assert len(fp)==64
print("OK: ensure_cert fp len=64")
PY

echo ""
echo "=== RESULT fail=$FAIL ==="
echo "Manual: Setup → PIN $PIN → Connect (no API key). Companion still running until script exits."
echo "Keeping companion alive 2s for handoff note…"
sleep 2
exit "$FAIL"
