#!/bin/bash
# Build, install and launch Mehfil on a connected iPhone using a FREE personal Apple team.
#
# A personal team cannot provision Sign in with Apple or Push Notifications, so this build:
#   · signs with Mehfil-Personal.entitlements (empty) instead of Mehfil.entitlements
#   · compiles with -D PERSONAL_TEAM, which hides the Sign in with Apple button
#   · Google sign-in, phone OTP (via Firebase's reCAPTCHA fallback) and Firestore all work
# Apps signed this way stop launching after 7 days — re-run this script to refresh them.
#
# The App Store build is unaffected: archive normally from Xcode and it uses the full entitlements.
set -euo pipefail
cd "$(dirname "$0")"

BUNDLE_ID=${BUNDLE_ID:-com.anish.mehfil}
DEVICE=${1:-$(xcrun devicectl list devices 2>/dev/null | awk '/physical/ {for (i = 1; i <= NF; i++) if ($i == "(UDID)") { print $(i-1); exit }}')}
[ -n "$DEVICE" ] || { echo "No iPhone connected. Plug it in, unlock it, and trust this Mac."; exit 1; }
DD=build/DerivedDataDevice
APP="$DD/Build/Products/Debug-iphoneos/Mehfil.app"

echo "▸ Building for device $DEVICE"
xcodebuild -project Mehfil.xcodeproj -scheme Mehfil -configuration Debug \
  -destination "platform=iOS,id=$DEVICE" -derivedDataPath "$DD" -allowProvisioningUpdates \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  CODE_SIGN_ENTITLEMENTS=Mehfil/Mehfil-Personal.entitlements \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) PERSONAL_TEAM' \
  build | grep -E "error:|warning: .*(signing|provision)|BUILD" || true
[ -d "$APP" ] || { echo "Build did not produce $APP"; exit 1; }

echo "▸ Installing"
xcrun devicectl device install app --device "$DEVICE" "$APP" >/dev/null
echo "▸ Launching"
xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE_ID" >/dev/null
echo "✓ Mehfil is running on the device"
