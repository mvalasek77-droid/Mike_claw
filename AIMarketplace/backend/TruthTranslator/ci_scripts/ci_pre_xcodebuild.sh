#!/bin/sh
set -eu

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ICON="$PROJECT_DIR/TruthTranslator/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"

echo "ChadDrop Xcode Cloud pre-xcodebuild"

/usr/bin/plutil -lint "$PROJECT_DIR/TruthTranslator/Resources/Info.plist"
/usr/bin/plutil -lint "$PROJECT_DIR/TruthTranslator/Resources/PrivacyInfo.xcprivacy"

ICON_INFO="$(/usr/bin/sips -g pixelWidth -g pixelHeight -g hasAlpha "$ICON" 2>/dev/null || true)"
echo "$ICON_INFO"

case "$ICON_INFO" in
  *"pixelWidth: 1024"*"pixelHeight: 1024"*"hasAlpha: no"*)
    echo "App icon is valid for App Store upload."
    ;;
  *)
    echo "App icon must be 1024 x 1024 with no alpha channel."
    exit 1
    ;;
esac
