#!/usr/bin/env bash
# Copyright (c) 2026 Pedro Shakour
# SPDX-License-Identifier: Apache-2.0

# Archive GrokApp for TestFlight / App Store Connect (or development export fallback).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/ios/GrokApp/GrokApp.xcodeproj"
SCHEME="GrokApp"
ARCHIVE_PATH="$ROOT/build/GrokApp.xcarchive"
EXPORT_PATH="$ROOT/build/GrokApp-export"
EXPORT_OPTS="$ROOT/ios/GrokApp/ExportOptions.plist"
DEV_EXPORT_OPTS="$ROOT/build/ExportOptions-development.plist"
TEAM_ID="${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to your Apple Team ID}"
BUNDLE_ID="${PRODUCT_BUNDLE_IDENTIFIER:-app.grokbuild.ios}"


mkdir -p "$ROOT/build"

echo "=== GrokApp archive (team $TEAM_ID) ==="

# Try generic iOS device archive first
set +e
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  2>&1 | tee "$ROOT/build/archive.log"
ARCHIVE_STATUS=${PIPESTATUS[0]}
set -e

if [[ "$ARCHIVE_STATUS" -ne 0 ]]; then
  echo ""
  echo "WARN: generic iOS device archive failed (exit $ARCHIVE_STATUS)."
  echo "See $ROOT/build/archive.log for provisioning/signing details."
  echo ""
  echo "=== Build settings dump ==="
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showBuildSettings \
    | tee "$ROOT/build/build-settings.log" \
    | grep -E 'DEVELOPMENT_TEAM|PRODUCT_BUNDLE_IDENTIFIER|CODE_SIGN|PROVISIONING' || true
  echo ""
  echo "=== Simulator archive proof (fallback) ==="
  xcodebuild build \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=iOS Simulator" \
    CODE_SIGNING_ALLOWED=NO \
    2>&1 | tee "$ROOT/build/simulator-build.log"
  echo "BLOCKER: device archive failed — fix provisioning profile for app.grokbuild.ios before TestFlight upload."
  exit "$ARCHIVE_STATUS"
fi

echo "OK: archive at $ARCHIVE_PATH"

# Export IPA
if [[ ! -f "$EXPORT_OPTS" ]]; then
  echo "FAIL: missing ExportOptions.plist at $EXPORT_OPTS" >&2
  exit 1
fi

set +e
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTS" \
  2>&1 | tee "$ROOT/build/export.log"
EXPORT_STATUS=${PIPESTATUS[0]}
set -e

if [[ "$EXPORT_STATUS" -ne 0 ]]; then
  echo "WARN: app-store-connect export failed — trying development export."
  cat > "$DEV_EXPORT_OPTS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>development</string>
  <key>teamID</key>
  <string>$TEAM_ID</string>
  <key>signingStyle</key>
  <string>automatic</string>
</dict>
</plist>
EOF
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$DEV_EXPORT_OPTS" \
    2>&1 | tee -a "$ROOT/build/export.log"
  EXPORT_STATUS=${PIPESTATUS[0]}
fi

if [[ "$EXPORT_STATUS" -eq 0 ]]; then
  echo "OK: exported to $EXPORT_PATH"
  ls -la "$EXPORT_PATH" || true
else
  echo "WARN: export failed — archive still available at $ARCHIVE_PATH"
  exit "$EXPORT_STATUS"
fi

echo "=== Archive complete ==="
echo "Upload manually: xcrun altool --upload-app -f $EXPORT_PATH/*.ipa -t ios --apiKey ... --apiIssuer ..."
