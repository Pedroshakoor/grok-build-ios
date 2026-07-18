#!/usr/bin/env bash
# Copyright (c) 2026 Pedro Shakour
# SPDX-License-Identifier: Apache-2.0

# Live simulator smoke WHILE the Simulator is on screen:
# rebuild → install → seed prefs → auto-send "hi" → watch bridge for reply.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/ios/GrokApp/GrokApp.xcodeproj"
SCHEME="GrokApp"
BUNDLE_ID="app.grokbuild.ios"
DERIVED="$ROOT/build/DerivedData-sim-demo"
PROMPT="${GROK_LIVE_SMOKE_PROMPT:-hi}"
HOST="${GROK_ACP_HOST:-127.0.0.1}"
PORT="${GROK_ACP_PORT:-7391}"
BRIDGE_LOG="${GROK_BRIDGE_LOG:-/tmp/grok-bridge-live.log}"
BRIDGE_PID=""

cleanup() {
  # Keep bridge alive for the user after the script exits.
  :
}
trap cleanup EXIT

echo "=== LIVE simulator smoke (watch the Simulator) ==="

pick_sim() {
  xcrun simctl list devices booted 2>/dev/null | awk -F'[()]' '/iPhone/ && /Booted/ { print $2; exit }'
}
SIM_UDID="$(pick_sim || true)"
if [[ -z "$SIM_UDID" ]]; then
  SIM_UDID=$(xcrun simctl list devices available 2>/dev/null \
    | awk -F'[()]' '/iPhone 17 Pro \(/ && !u { u=$2 } /iPhone/ && !u { u=$2 } END { print u }')
  xcrun simctl boot "$SIM_UDID" 2>/dev/null || true
fi
open -a Simulator
echo "OK: simulator $SIM_UDID"

# Bridge must be up before the app connects
if ! lsof -ti tcp:"$PORT" >/dev/null 2>&1; then
  export GROK_COMPANION_STATE_DIR="${GROK_COMPANION_STATE_DIR:-$ROOT/.grok-companion-state}"
  export GROK_COMPANION_CWD="${GROK_COMPANION_CWD:-$ROOT}"
  : > "$BRIDGE_LOG"
  export GROK_COMPANION_INSECURE=1
  nohup python3 "$ROOT/companion/scripts/acp_tcp_bridge.py" --real --no-tls --no-pair --host "$HOST" --port "$PORT" \
    >>"$BRIDGE_LOG" 2>&1 &
  BRIDGE_PID=$!
  for _ in $(seq 1 20); do
    python3 -c "import socket; s=socket.create_connection(('$HOST',$PORT),1); s.close()" 2>/dev/null && break
    sleep 0.25
  done
  echo "OK: bridge started pid=${BRIDGE_PID:-?} log=$BRIDGE_LOG"
else
  echo "OK: bridge already on $HOST:$PORT"
fi

echo "--- build + install ---"
mkdir -p "$DERIVED"
xcodebuild build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "id=$SIM_UDID" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  -quiet

APP="$DERIVED/Build/Products/Debug-iphonesimulator/GrokApp.app"
xcrun simctl install "$SIM_UDID" "$APP"

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
# Never leave auto-prompt keys in prefs — they polluted "New worktree" for users.
/usr/libexec/PlistBuddy -c "Delete :GROK_LIVE_SMOKE_PROMPT" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Delete :GROK_LIVE_SMOKE_AUTO_AGENT" "$PLIST" 2>/dev/null || true

echo "OK: seeded host=$HOST port=$PORT (no auto-prompt — type in Simulator)"
echo ">>> WATCH SIMULATOR — open New worktree, type a prompt manually <<<"

xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID"

# Wait for bridge activity
echo "--- waiting for companion traffic (up to 90s) ---"
DEADLINE=$((SECONDS + 90))
GOT_CLIENT=0
GOT_SPAWN=0
while (( SECONDS < DEADLINE )); do
  if [[ -f "$BRIDGE_LOG" ]]; then
    grep -q "client paired\|stub client connected\|injected XAI_API_KEY\|spawning:" "$BRIDGE_LOG" 2>/dev/null && GOT_CLIENT=1
    grep -q "spawning:" "$BRIDGE_LOG" 2>/dev/null && GOT_SPAWN=1
  fi
  # Also accept any established connection on 7391 from sim
  if [[ "$GOT_CLIENT" -eq 1 ]]; then
    break
  fi
  sleep 1
done

SHOT="$ROOT/build/sim-live-smoke.png"
xcrun simctl io "$SIM_UDID" screenshot "$SHOT" >/dev/null
echo "screenshot: $SHOT"

if [[ "$GOT_CLIENT" -eq 1 ]]; then
  echo "OK: LIVE smoke — companion saw the iOS client"
  [[ "$GOT_SPAWN" -eq 1 ]] && echo "OK: grok agent spawned"
  echo "Look at Simulator for Connected. + assistant reply (or model error)."
  exit 0
fi

echo "FAIL: no companion client from Simulator within 90s" >&2
echo "--- bridge log tail ---" >&2
tail -40 "$BRIDGE_LOG" 2>/dev/null || true
exit 1
