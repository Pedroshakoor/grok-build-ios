#!/usr/bin/env bash
# Copyright (c) 2026 Pedro Shakour
# SPDX-License-Identifier: Apache-2.0

# Live smoke + stress WHILE Simulator is open.
# 1) Ensure companion  2) rebuild/install/launch  3) auto New Session + hi
# 4) stress: 20 stub handshakes + iOS-shaped session/new on real bridge
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_ID="app.grokbuild.ios"
DERIVED="$ROOT/build/DerivedData-sim-demo"
HOST="${GROK_ACP_HOST:-127.0.0.1}"
PORT="${GROK_ACP_PORT:-7391}"
PROMPT="${GROK_LIVE_SMOKE_PROMPT:-hi}"

echo "=== LIVE smoke + stress (watch Simulator) ==="

bash "$ROOT/scripts/keep-companion.sh"

SIM_UDID=$(xcrun simctl list devices booted 2>/dev/null | awk -F'[()]' '/iPhone/ && /Booted/ { print $2; exit }')
if [[ -z "$SIM_UDID" ]]; then
  echo "FAIL: no booted simulator — open Simulator first" >&2
  exit 1
fi
open -a Simulator
echo "OK: simulator $SIM_UDID"

echo "--- rebuild + install ---"
mkdir -p "$DERIVED"
xcodebuild build \
  -project "$ROOT/ios/GrokApp/GrokApp.xcodeproj" \
  -scheme GrokApp \
  -configuration Debug \
  -destination "id=$SIM_UDID" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  -quiet

xcrun simctl install "$SIM_UDID" "$DERIVED/Build/Products/Debug-iphonesimulator/GrokApp.app"

CONTAINER=$(xcrun simctl get_app_container "$SIM_UDID" "$BUNDLE_ID" data)
PLIST="$CONTAINER/Library/Preferences/${BUNDLE_ID}.plist"
mkdir -p "$(dirname "$PLIST")"
/usr/libexec/PlistBuddy -c "Add :GROK_ACP_HOST string $HOST" "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :GROK_ACP_HOST $HOST" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :GROK_ACP_PORT integer $PORT" "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :GROK_ACP_PORT $PORT" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :GROK_USE_TLS bool false" "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :GROK_USE_TLS false" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :GROK_ONBOARDED bool true" "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :GROK_ONBOARDED true" "$PLIST"
# Do not seed auto-prompt — that polluted New worktree for users.
/usr/libexec/PlistBuddy -c "Delete :GROK_LIVE_SMOKE_PROMPT" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Delete :GROK_LIVE_SMOKE_AUTO_AGENT" "$PLIST" 2>/dev/null || true

# API key: enter in Setup in the app (Debug uses session memory, not UserDefaults).
if [[ -n "${XAI_API_KEY:-}" ]]; then
  echo "OK: XAI_API_KEY set in env — paste same value in app Setup if needed"
else
  echo "WARN: no XAI_API_KEY in env — paste in Setup if live reply fails"
fi

echo ">>> WATCH SIMULATOR — open New worktree and type your own prompt (no auto-hi) <<<"
xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID"

LOG="${GROK_BRIDGE_LOG:-/tmp/grok-bridge-live.log}"
LOG_MARK=$(wc -l < "$LOG" 2>/dev/null | tr -d ' ' || echo 0)
echo ">>> Companion should see client when you start a session <<<"

echo "--- wait for iOS client on companion (90s) ---"
DEADLINE=$((SECONDS + 90))
GOT=0
while (( SECONDS < DEADLINE )); do
  if tail -n +"$((LOG_MARK + 1))" "$LOG" 2>/dev/null | grep -q "client paired\|spawning:"; then
    GOT=1
    break
  fi
  sleep 1
done

SHOT="$ROOT/build/sim-live-stress.png"
xcrun simctl io "$SIM_UDID" screenshot "$SHOT" >/dev/null || true
echo "screenshot: $SHOT"

if [[ "$GOT" -ne 1 ]]; then
  echo "FAIL: Simulator never reached companion" >&2
  tail -40 "$LOG" >&2 || true
  exit 1
fi
echo "OK: live smoke — companion saw Simulator client"

echo "--- stress: 20 rapid TCP connects to companion ---"
python3 - "$HOST" "$PORT" <<'PY'
import socket, sys
host, port = sys.argv[1], int(sys.argv[2])
ok = 0
for i in range(20):
    try:
        s = socket.create_connection((host, port), 2)
        s.close()
        ok += 1
    except OSError as e:
        print("FAIL connect", i, e, file=sys.stderr)
        sys.exit(1)
print(f"OK: {ok}/20 connects")
PY

echo "--- stress: iOS-shaped session/new (cwd '.') on real bridge ---"
python3 - "$HOST" "$PORT" <<'PY'
import json, socket, sys, time
host, port = sys.argv[1], int(sys.argv[2])

def rpc(sock, method, params, req_id, timeout=60):
    sock.sendall((json.dumps({"jsonrpc":"2.0","method":method,"params":params,"id":req_id})+"\n").encode())
    buf=b""; d=time.time()+timeout
    while time.time()<d:
        chunk=sock.recv(8192)
        if not chunk: break
        buf+=chunk
        while b"\n" in buf:
            line,buf=buf.split(b"\n",1)
            if not line.strip(): continue
            obj=json.loads(line)
            if obj.get("id")==req_id:
                if obj.get("error"):
                    raise RuntimeError(obj["error"])
                return obj
    raise TimeoutError(method)

sock=socket.create_connection((host,port),5)
rpc(sock,"initialize",{"protocolVersion":1,"clientCapabilities":{"fs":{"readTextFile":False,"writeTextFile":False}}},1)
rpc(sock,"authenticate",{"methodId":"xai.api_key","_meta":{"xaiApiKey":"stress-placeholder"}},2)
r=rpc(sock,"session/new",{"cwd":".","mcpServers":[]},3)
assert r.get("result",{}).get("sessionId"), r
print("OK: session/new with cwd '.'")
sock.close()
PY

echo "=== LIVE smoke + stress PASSED ==="
echo "Companion still running on ${HOST}:${PORT} — use the Simulator now."
