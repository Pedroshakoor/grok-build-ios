#!/usr/bin/env bash
# Copyright (c) 2026 Pedro Shakour
# SPDX-License-Identifier: Apache-2.0

# Install + start persistent companion via launchd (survives shell exits).
#
# Copies bridge modules to ~/Library/Application Support/GrokBuild/runtime/
# so launchd is not blocked by macOS TCC on Desktop/Documents.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="app.grokbuild.companion"
UID_NUM="$(id -u)"
SUPPORT="$HOME/Library/Application Support/GrokBuild"
RUNTIME="$SUPPORT/runtime"
STATE="$SUPPORT/state"
WORKSPACE="$SUPPORT/workspace"
DEST="$HOME/Library/LaunchAgents/${LABEL}.plist"
LOG="/tmp/grok-bridge-live.log"

PYTHON=""
for cand in /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3; do
  if [[ -x "$cand" ]]; then
    PYTHON="$cand"
    break
  fi
done
if [[ -z "$PYTHON" ]]; then
  echo "FAIL: no python3 found" >&2
  exit 1
fi

# PATH for grok/cargo without machine-specific entries
PATH_EXPORT="/opt/homebrew/bin:/usr/local/bin:${HOME}/.local/bin:/usr/bin:/bin"

mkdir -p "$HOME/Library/LaunchAgents" "$RUNTIME" "$STATE" "$WORKSPACE"
# Seed workspace if empty so agent has a safe cwd (Desktop is TCC-blocked).
if [[ ! -f "$WORKSPACE/NOTES.md" ]]; then
  echo "Grok Build companion workspace" > "$WORKSPACE/NOTES.md"
fi

cp "$ROOT/companion/scripts/acp_tcp_bridge.py" "$RUNTIME/"
cp "$ROOT/companion/scripts/companion_tls.py" "$RUNTIME/"
cp "$ROOT/companion/scripts/companion_ext.py" "$RUNTIME/"

if [[ -d "$ROOT/.grok-companion-state" && ! -e "$STATE/migrated" ]]; then
  cp -R "$ROOT/.grok-companion-state/." "$STATE/" 2>/dev/null || true
  touch "$STATE/migrated"
fi

cat >"$DEST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>${LABEL}</string>
	<key>ProgramArguments</key>
	<array>
		<string>${PYTHON}</string>
		<string>${RUNTIME}/acp_tcp_bridge.py</string>
		<string>--real</string>
		<string>--host</string>
		<string>127.0.0.1</string>
		<string>--port</string>
		<string>7391</string>
	</array>
	<key>WorkingDirectory</key>
	<string>${WORKSPACE}</string>
	<key>EnvironmentVariables</key>
	<dict>
		<key>GROK_COMPANION_STATE_DIR</key>
		<string>${STATE}</string>
		<key>GROK_COMPANION_CWD</key>
		<string>${WORKSPACE}</string>
		<key>PATH</key>
		<string>${PATH_EXPORT}</string>
		<key>PYTHONPATH</key>
		<string>${RUNTIME}</string>
	</dict>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
	<key>StandardOutPath</key>
	<string>${LOG}</string>
	<key>StandardErrorPath</key>
	<string>${LOG}</string>
	<key>ThrottleInterval</key>
	<integer>2</integer>
</dict>
</plist>
EOF

launchctl bootout "gui/${UID_NUM}/${LABEL}" 2>/dev/null || true
if lsof -ti tcp:7391 >/dev/null 2>&1; then
  kill $(lsof -ti tcp:7391) 2>/dev/null || true
  sleep 0.5
fi

: >"$LOG"

launchctl bootstrap "gui/${UID_NUM}" "$DEST"
launchctl enable "gui/${UID_NUM}/${LABEL}" 2>/dev/null || true
launchctl kickstart -k "gui/${UID_NUM}/${LABEL}" 2>/dev/null || true

for _ in $(seq 1 40); do
  if python3 -c "import socket; s=socket.create_connection(('127.0.0.1',7391),1); s.close()" 2>/dev/null; then
    echo "OK: companion launchd ${LABEL} listening on 127.0.0.1:7391 (TLS+PIN)"
    echo "    runtime=${RUNTIME}"
    echo "    python=${PYTHON}"
    launchctl print "gui/${UID_NUM}/${LABEL}" 2>/dev/null | rg "state =|pid =" | head -5 || true
    exit 0
  fi
  sleep 0.25
done

echo "FAIL: companion did not start" >&2
tail -40 "$LOG" >&2 || true
launchctl print "gui/${UID_NUM}/${LABEL}" 2>/dev/null | head -40 >&2 || true
exit 1
