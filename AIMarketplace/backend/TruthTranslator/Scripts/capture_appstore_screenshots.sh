#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

DEVICE_ID="${1:-}"
if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID="$(xcrun simctl list devices booted | awk -F '[()]' '/iPhone/ && /Booted/ { print $2; exit }')"
fi

if [[ -z "$DEVICE_ID" ]]; then
  echo "No booted iPhone simulator found."
  echo "Open Simulator, boot an iPhone, then run this again."
  exit 1
fi

if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate >/dev/null
fi

DERIVED_DATA="${CHADDROP_SCREENSHOT_DERIVED_DATA:-/private/tmp/chaddrop_screenshot_dd}"
SETTLE_SECONDS="${CHADDROP_SCREENSHOT_SETTLE_SECONDS:-6}"

APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/TruthTranslator.app"
bundle_id_for_app() {
  local app_path="$1"
  /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app_path/Info.plist" 2>/dev/null || true
}

if [[ "${CHADDROP_SKIP_SCREENSHOT_BUILD:-0}" != "1" ]]; then
  if ! xcodebuild \
    -project TruthTranslator.xcodeproj \
    -scheme TruthTranslator \
    -derivedDataPath "$DERIVED_DATA" \
    -destination "generic/platform=iOS Simulator" \
    build \
    CODE_SIGNING_ALLOWED=NO; then
    echo ""
    echo "The automatic screenshot build failed. This can happen when CoreSimulator is refreshing iOS runtimes."
    echo "Trying the most recent existing simulator build instead."
  fi
else
  echo "Skipping screenshot build because CHADDROP_SKIP_SCREENSHOT_BUILD=1."
fi

if [[ -d "$APP_PATH" && "$(bundle_id_for_app "$APP_PATH")" != "com.chaddrop.app" ]]; then
  echo "Ignoring incomplete simulator app at $APP_PATH."
  APP_PATH=""
fi

if [[ -z "${APP_PATH:-}" || ! -d "$APP_PATH" ]]; then
  APP_PATH="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path "*/Build/Products/Debug-iphonesimulator/TruthTranslator.app" -print | sort | tail -n 1)"
fi

if [[ -z "${APP_PATH:-}" || ! -d "$APP_PATH" ]]; then
  echo "Could not find a built simulator app."
  echo "Open TruthTranslator.xcodeproj in Xcode, choose an iPhone simulator, press the Play button once, then run this script again."
  exit 1
fi

if [[ "$(bundle_id_for_app "$APP_PATH")" != "com.chaddrop.app" ]]; then
  echo "Found a simulator app, but it is not ChadDrop."
  echo "Expected bundle ID: com.chaddrop.app"
  echo "Actual bundle ID: $(bundle_id_for_app "$APP_PATH")"
  exit 1
fi

xcrun simctl terminate "$DEVICE_ID" com.chaddrop.app >/dev/null 2>&1 || true
xcrun simctl uninstall "$DEVICE_ID" com.chaddrop.app >/dev/null 2>&1 || true
xcrun simctl install "$DEVICE_ID" "$APP_PATH"
xcrun simctl launch "$DEVICE_ID" com.chaddrop.app >/dev/null
sleep "$SETTLE_SECONDS"

PUBLIC_DIR="$ROOT_DIR/AppStore/Screenshots/Public"
INTERNAL_DIR="$ROOT_DIR/AppStore/Screenshots/InternalWalkthrough"
mkdir -p "$PUBLIC_DIR" "$INTERNAL_DIR"

capture_public() {
  local name="$1"
  shift || true
  xcrun simctl terminate "$DEVICE_ID" com.chaddrop.app >/dev/null 2>&1 || true
  xcrun simctl launch "$DEVICE_ID" com.chaddrop.app "$@" >/dev/null
  sleep "$SETTLE_SECONDS"
  xcrun simctl io "$DEVICE_ID" screenshot "$PUBLIC_DIR/$name.png"
}

capture_internal() {
  local name="$1"
  shift || true
  xcrun simctl terminate "$DEVICE_ID" com.chaddrop.app >/dev/null 2>&1 || true
  xcrun simctl launch "$DEVICE_ID" com.chaddrop.app "$@" >/dev/null
  sleep "$SETTLE_SECONDS"
  xcrun simctl io "$DEVICE_ID" screenshot "$INTERNAL_DIR/$name.png"
}

capture_public "01-home"
capture_public "02-decoded-example" --chaddrop-demo-result
capture_internal "release-gateway-walkthrough" --chaddrop-show-release-gateway

echo ""
echo "Public App Store screenshot candidates:"
for image in "$PUBLIC_DIR"/*.png; do
  sips -g pixelWidth -g pixelHeight "$image" | sed "s#^#$image #"
done

echo ""
echo "Internal walkthrough screenshot:"
for image in "$INTERNAL_DIR"/*.png; do
  sips -g pixelWidth -g pixelHeight "$image" | sed "s#^#$image #"
done

if [[ "${CHADDROP_OPEN_SCREENSHOT_FOLDER:-1}" == "1" ]]; then
  open "$ROOT_DIR/AppStore/Screenshots" >/dev/null 2>&1 || echo "Screenshots captured. Could not open the folder automatically."
fi

echo ""
echo "Use Public screenshots for App Store Connect. The InternalWalkthrough image is only for guiding the release process."
