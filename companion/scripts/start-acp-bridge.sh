#!/usr/bin/env bash
# Copyright (c) 2026 Pedro Shakour
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BRIDGE_PY="$ROOT/companion/scripts/acp_tcp_bridge.py"
HOST="${GROK_ACP_HOST:-0.0.0.0}"
PORT="${GROK_ACP_PORT:-7391}"
UPSTREAM="$ROOT/upstream-grok-build"
STUB=0
REAL=0
ADVERTISE=1
NO_TLS=0
NO_PAIR=0
DNS_PID=""

usage() {
  cat <<'EOF'
Usage: start-acp-bridge.sh [options]

Starts TLS ACP bridge for Grok Build iOS. Prints PIN + cert fingerprint on start.
EOF
}

cleanup() {
  [[ -n "$DNS_PID" ]] && kill -0 "$DNS_PID" 2>/dev/null && kill "$DNS_PID" 2>/dev/null || true
}
trap cleanup EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --stub) STUB=1; shift ;;
    --real) REAL=1; shift ;;
    --no-tls) NO_TLS=1; shift ;;
    --no-pair) NO_PAIR=1; shift ;;
    --no-advertise) ADVERTISE=0; shift ;;
    --upstream) UPSTREAM="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown: $1" >&2; exit 1 ;;
  esac
done

export GROK_COMPANION_CWD="${GROK_COMPANION_CWD:-$(pwd)}"

ARGS=(--host "$HOST" --port "$PORT" --upstream "$UPSTREAM")
[[ "$STUB" -eq 1 ]] && ARGS+=(--stub)
[[ "$REAL" -eq 1 ]] && ARGS+=(--real)
if [[ "$NO_TLS" -eq 1 || "$NO_PAIR" -eq 1 ]]; then
  if [[ "${GROK_COMPANION_INSECURE:-}" != "1" ]]; then
    echo "[start-acp-bridge] ERROR: --no-tls/--no-pair require GROK_COMPANION_INSECURE=1" >&2
    exit 1
  fi
fi
[[ "$NO_TLS" -eq 1 ]] && ARGS+=(--no-tls)
[[ "$NO_PAIR" -eq 1 ]] && ARGS+=(--no-pair)

# Prepare PIN + fingerprint for Bonjour (bridge reuses via env)
eval "$(python3 -c "
import sys
sys.path.insert(0, '$ROOT/companion/scripts')
from companion_tls import ensure_cert, fresh_pin
c,k,fp = ensure_cert()
pin = fresh_pin()
print(f'export GROK_COMPANION_PIN={pin}')
print(f'export GROK_COMPANION_FP={fp}')
print(f'export GROK_COMPANION_FP_SHORT={fp[:16]}')
")"

echo "[start-acp-bridge] PIN: ${GROK_COMPANION_PIN}"
echo "[start-acp-bridge] cert fingerprint: ${GROK_COMPANION_FP}"
echo "[start-acp-bridge] cert fingerprint (short): ${GROK_COMPANION_FP_SHORT}"

if [[ "$ADVERTISE" -eq 1 ]] && command -v dns-sd >/dev/null 2>&1; then
  # Full DER SHA-256 in TXT so the phone can pin without pasting.
  dns-sd -R "Grok Build" _grok-build._tcp local "$PORT" "fp=${GROK_COMPANION_FP}" "fps=${GROK_COMPANION_FP_SHORT}" >/dev/null 2>&1 &
  DNS_PID=$!
  echo "[start-acp-bridge] Bonjour: Grok Build _grok-build._tcp :${PORT} (fp in TXT)"
fi

echo "[start-acp-bridge] workspace=${GROK_COMPANION_CWD}"
exec python3 "$BRIDGE_PY" "${ARGS[@]}"
