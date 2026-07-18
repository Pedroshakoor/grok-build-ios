#!/usr/bin/env bash
# Copyright (c) 2026 Pedro Shakour
# SPDX-License-Identifier: Apache-2.0
#
# PIN demo for Simulator recording:
#   1) Starts REAL TLS+PIN companion on 127.0.0.1:7391
#   2) Prints PIN + fingerprint to copy into the app
#   3) Builds/installs/launches Simulator (does NOT inject API key)
#
# Usage:
#   export XAI_API_KEY=xai-...
#   ./scripts/run-pin-demo.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/ios/GrokApp/GrokApp.xcodeproj"
SCHEME="GrokApp"
BUNDLE_ID="app.grokbuild.ios"
DERIVED="$ROOT/build/DerivedData-pin-demo"
HOST="127.0.0.1"
PORT="${GROK_ACP_PORT:-7391}"
BRIDGE_PID=""

cleanup() { :; }
trap cleanup EXIT

if [[ -z "${XAI_API_KEY:-}" ]]; then
  echo "FAIL: export XAI_API_KEY=xai-... first" >&2
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

echo "=== PIN demo: TLS companion + Simulator ==="
UID_NUM="$(id -u)"
launchctl bootout "gui/${UID_NUM}/app.grokbuild.companion" 2>/dev/null || true
pkill -9 -f acp_tcp_bridge.py 2>/dev/null || true
sleep 0.4

export GROK_COMPANION_STATE_DIR="${GROK_COMPANION_STATE_DIR:-$HOME/Library/Application Support/GrokBuild/state}"
export GROK_COMPANION_CWD="${GROK_COMPANION_CWD:-$HOME/Library/Application Support/GrokBuild/workspace}"
mkdir -p "$GROK_COMPANION_STATE_DIR" "$GROK_COMPANION_CWD"
export PATH="${HOME}/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
export GROK_AGENT="${GROK_AGENT:-grok-build}"
export GROK_MODEL="${GROK_MODEL:-grok-build-0.1}"

# TLS + PIN (no GROK_COMPANION_INSECURE) — this is the recording path.
bash "$ROOT/companion/scripts/start-acp-bridge.sh" --real --host "$HOST" --port "$PORT" --no-advertise &
BRIDGE_PID=$!

LOG_WAIT=0
while [[ $LOG_WAIT -lt 40 ]]; do
  if python3 -c "import socket; s=socket.create_connection(('$HOST',$PORT),1); s.close()" 2>/dev/null; then
    break
  fi
  sleep 0.25
  LOG_WAIT=$((LOG_WAIT + 1))
done

if ! python3 -c "import socket; s=socket.create_connection(('$HOST',$PORT),1); s.close()" 2>/dev/null; then
  echo "FAIL: companion did not listen on ${HOST}:${PORT}" >&2
  exit 1
fi

echo ""
echo "┌──────────────────────────────────────────────────────────┐"
echo "│  In Simulator Setup: API key + PIN only                  │"
echo "│  (fingerprint is automatic after PIN succeeds)           │"
echo "│  Look above for:  PIN: ######                            │"
echo "└──────────────────────────────────────────────────────────┘"
echo ""

PICK=$(pick_simulator || true)
if [[ -z "$PICK" ]]; then
  echo "FAIL: no iPhone simulator" >&2
  exit 1
fi
SIM_UDID="${PICK%%$'\t'*}"
SIM_NAME="${PICK#*$'\t'}"
echo "OK: simulator $SIM_NAME ($SIM_UDID)"

xcrun simctl boot "$SIM_UDID" 2>/dev/null || true
open -a Simulator

mkdir -p "$DERIVED"
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
/usr/libexec/PlistBuddy -c "Add GROK_USE_TLS bool true" "$PLIST"
/usr/libexec/PlistBuddy -c "Add GROK_ONBOARDED bool false" "$PLIST"

xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID"

echo ""
echo "=== Recording steps ==="
echo "1. Simulator → Setup"
echo "2. Paste API key"
echo "3. Paste PIN from this terminal (only)"
echo "4. Tap Connect → wait for green Connected"
echo "5. Continue to Welcome → New worktree"
echo ""
echo "Companion pid $BRIDGE_PID — leave this terminal open (kill: kill $BRIDGE_PID)"
disown "$BRIDGE_PID" 2>/dev/null || true
