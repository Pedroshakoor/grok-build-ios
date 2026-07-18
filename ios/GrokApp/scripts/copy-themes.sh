#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
DEST="${SRCROOT}/GrokApp/Resources"
THEMES="${DEST}/themes"
mkdir -p "$THEMES"
cp -f "${ROOT}/shared/themes/"*.json "$THEMES/"
cp -f "${ROOT}/shared/slash-commands.json" "${DEST}/slash-commands.json"
cp -f "${ROOT}/shared/companion.defaults.json" "${DEST}/companion.defaults.json"
