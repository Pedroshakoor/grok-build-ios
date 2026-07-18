#!/usr/bin/env bash
# Copyright (c) 2026 Pedro Shakour
# SPDX-License-Identifier: Apache-2.0

# Primary simulator demo — official `grok agent serve` (WebSocket + Secret).
# Usage:
#   export XAI_API_KEY=xai-...
#   ./scripts/run-simulator-demo.sh
#
# Test-only stub (no API key): ./scripts/run-simulator-stub-demo.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/ios/GrokApp/GrokApp.xcodeproj"
SCHEME="GrokApp"
BUNDLE_ID="app.grokbuild.ios"
DERIVED="$ROOT/build/DerivedData-sim-demo"
HOST="${GROK_ACP_HOST:-127.0.0.1}"
PORT="${GROK_ACP_PORT:-2419}"
SECRET="${GROK_AGENT_SECRET:-$(openssl rand -hex 12)}"
SERVE_PID=""
SERVE_LOG="$ROOT/build/serve-demo.log"
SIM_UDID=""

cleanup() {
  :
}
trap cleanup EXIT

if [[ -z "${XAI_API_KEY:-}" ]]; then
  echo "FAIL: export XAI_API_KEY=xai-... then re-run" >&2
  echo "      (test-only stub: ./scripts/run-simulator-stub-demo.sh)" >&2
  exit 1
fi

if ! command -v grok >/dev/null 2>&1; then
  echo "FAIL: install official grok CLI (https://x.ai/cli)" >&2
  exit 1
fi

pick_simulator() {
  xcrun simctl list devices available 2>/dev/null \
    | awk -F'[()]' '
        /iPhone 17 Pro \(/ && !u { u=$2; n=$1 }
        /iPhone 17 \(/ && !u { u=$2; n=$1 }
        /iPhone/ && !u { u=$2; n=$1 }
        END {
          if (u) {
            gsub(/^[[:space:]]+/, "", n)
            print u "\t" n
          }
        }'
}

echo "=== GrokApp simulator demo (official grok agent serve) ==="

pkill -9 -f "grok agent serve" 2>/dev/null || true
pkill -9 -f acp_tcp_bridge.py 2>/dev/null || true
sleep 0.4

if command -v lsof >/dev/null 2>&1; then
  STALE=$(lsof -ti tcp:"$PORT" 2>/dev/null || true)
  if [[ -n "$STALE" ]]; then
    kill $STALE 2>/dev/null || true
    sleep 0.5
  fi
fi

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
  echo "FAIL: grok agent serve did not bind ${HOST}:${PORT}" >&2
  tail -20 "$SERVE_LOG" >&2 || true
  exit 1
fi
echo "OK: grok agent serve on ${HOST}:${PORT} (pid $SERVE_PID)"
echo "    Secret: $SECRET"

PICK=$(pick_simulator || true)
if [[ -z "$PICK" ]]; then
  echo "FAIL: no iPhone simulator" >&2
  exit 1
fi
SIM_UDID="${PICK%%$'\t'*}"
SIM_NAME="${PICK#*$'\t'}"
echo "OK: simulator $SIM_NAME ($SIM_UDID)"

xcrun simctl boot "$SIM_UDID" 2>/dev/null || true
open -a Simulator 2>/dev/null || true

mkdir -p "$DERIVED"
echo "--- xcodebuild ---"
xcodebuild build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "id=$SIM_UDID" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  -quiet

APP_PATH="$DERIVED/Build/Products/Debug-iphonesimulator/GrokApp.app"
xcrun simctl install "$SIM_UDID" "$APP_PATH"

CONTAINER=$(xcrun simctl get_app_container "$SIM_UDID" "$BUNDLE_ID" data)
PLIST="$CONTAINER/Library/Preferences/${BUNDLE_ID}.plist"
mkdir -p "$(dirname "$PLIST")"
/usr/libexec/PlistBuddy -c "Clear dict" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add GROK_ACP_HOST string $HOST" "$PLIST"
/usr/libexec/PlistBuddy -c "Add GROK_ACP_PORT integer $PORT" "$PLIST"
/usr/libexec/PlistBuddy -c "Add GROK_USE_TLS bool false" "$PLIST"
/usr/libexec/PlistBuddy -c "Add GROK_USE_WEBSOCKET bool true" "$PLIST"
/usr/libexec/PlistBuddy -c "Add GROK_PAIR_PIN string $SECRET" "$PLIST"
/usr/libexec/PlistBuddy -c "Add GROK_ONBOARDED bool false" "$PLIST"

xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID"

echo ""
echo "=== Simulator demo ready (golden path) ==="
echo "App: GrokApp on $SIM_NAME"
echo "Serve: ws://${HOST}:${PORT}/ws?server-key=…"
echo "Secret (paste in Setup): $SECRET"
echo ""
echo "How to film the 30s demo:"
echo "  1. Setup → Secret is pre-filled if you used this script"
echo "  2. connect → continue → New worktree"
echo "  3. Prompt that triggers a tool (e.g. list files in cwd)"
echo ""
echo "Serve pid $SERVE_PID — leave running (kill: kill $SERVE_PID)"
disown "$SERVE_PID" 2>/dev/null || true
