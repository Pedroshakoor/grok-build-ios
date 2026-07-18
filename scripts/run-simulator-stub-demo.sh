#!/usr/bin/env bash
# Copyright (c) 2026 Pedro Shakour
# SPDX-License-Identifier: Apache-2.0

# TEST-ONLY: ACP stub bridge (no grok, no Secret). For CI / protocol checks only.
# Default demo: ./scripts/run-simulator-demo.sh (official `grok agent serve`).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/ios/GrokApp/GrokApp.xcodeproj"
SCHEME="GrokApp"
HOST="${GROK_ACP_HOST:-127.0.0.1}"
PORT="${GROK_ACP_PORT:-7391}"
BRIDGE_PID=""
SIM_UDID=""

cleanup() {
  if [[ -n "$BRIDGE_PID" ]] && kill -0 "$BRIDGE_PID" 2>/dev/null; then
    kill "$BRIDGE_PID" 2>/dev/null || true
    wait "$BRIDGE_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

pick_simulator() {
  xcrun simctl list devices available 2>/dev/null \
    | awk -F'[()]' '
        /iPhone 17 \(/ && !u { u=$2; n=$1 }
        /iPhone 16 \(/ && !u { u=$2; n=$1 }
        /iPhone 15 \(/ && !u { u=$2; n=$1 }
        /iPhone/ && !u { u=$2; n=$1 }
        END {
          if (u) {
            gsub(/^[[:space:]]+/, "", n)
            print u "\t" n
          }
        }'
}

echo "=== GrokApp simulator STUB demo (test-only — not for filming) ==="

if command -v lsof >/dev/null 2>&1; then
  STALE=$(lsof -ti tcp:"$PORT" 2>/dev/null || true)
  if [[ -n "$STALE" ]]; then
    kill $STALE 2>/dev/null || true
    sleep 0.5
  fi
fi

export GROK_COMPANION_STATE_DIR="${GROK_COMPANION_STATE_DIR:-$ROOT/.grok-companion-state}"
export GROK_COMPANION_INSECURE=1
python3 "$ROOT/companion/scripts/acp_tcp_bridge.py" --stub --no-tls --no-pair --host "$HOST" --port "$PORT" &
BRIDGE_PID=$!

for _ in $(seq 1 20); do
  if python3 -c "import socket; s=socket.create_connection(('$HOST', $PORT), 1); s.close()" 2>/dev/null; then
    break
  fi
  sleep 0.25
done

if ! python3 -c "import socket; s=socket.create_connection(('$HOST', $PORT), 1); s.close()" 2>/dev/null; then
  echo "FAIL: ACP stub bridge did not start on ${HOST}:${PORT}" >&2
  exit 1
fi
echo "OK: stub bridge on ${HOST}:${PORT} (pid $BRIDGE_PID)"

PICK=$(pick_simulator || true)
if [[ -z "$PICK" ]]; then
  echo "FAIL: no available iPhone simulator" >&2
  exit 1
fi
SIM_UDID="${PICK%%$'\t'*}"
SIM_NAME="${PICK#*$'\t'}"
echo "OK: using simulator $SIM_NAME ($SIM_UDID)"

xcrun simctl boot "$SIM_UDID" 2>/dev/null || true
open -a Simulator 2>/dev/null || true

DERIVED="$ROOT/build/DerivedData-sim-demo"
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
xcrun simctl launch "$SIM_UDID" "app.grokbuild.ios" || true

echo ""
echo "STUB path only — use run-simulator-demo.sh for the real golden path."
echo "Stub ACP: ${HOST}:${PORT} (legacy TCP, no Secret)"
