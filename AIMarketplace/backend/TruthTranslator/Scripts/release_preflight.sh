#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

failures=0

note() {
  printf "%s\n" "$1"
}

pass() {
  printf "[OK] %s\n" "$1"
}

warn() {
  printf "[TODO] %s\n" "$1"
}

fail() {
  printf "[FAIL] %s\n" "$1"
  failures=$((failures + 1))
}

need_command() {
  if command -v "$1" >/dev/null 2>&1; then
    pass "$1 is installed"
  else
    fail "$1 is missing"
  fi
}

read_config_value() {
  local key="$1"
  sed -n "s/^${key}[[:space:]]*=[[:space:]]*//p" Config/Release.xcconfig | head -n 1
}

note "ChadDrop release preflight"
note "Project: $ROOT_DIR"
note ""

need_command xcodebuild
need_command plutil
need_command sips

if command -v xcodegen >/dev/null 2>&1; then
  pass "xcodegen is installed"
  xcodegen generate >/dev/null
  pass "Xcode project generated"
else
  warn "xcodegen is missing. The existing TruthTranslator.xcodeproj can still be opened, but project regeneration is not automated."
fi

if plutil -lint TruthTranslator/Resources/Info.plist >/dev/null; then
  pass "Info.plist is valid"
else
  fail "Info.plist is not valid"
fi

if plutil -lint TruthTranslator/Resources/PrivacyInfo.xcprivacy >/dev/null; then
  pass "PrivacyInfo.xcprivacy is valid"
else
  fail "PrivacyInfo.xcprivacy is not valid"
fi

ICON_INFO="$(sips -g pixelWidth -g pixelHeight -g hasAlpha TruthTranslator/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png 2>/dev/null || true)"
if [[ "$ICON_INFO" == *"pixelWidth: 1024"* && "$ICON_INFO" == *"pixelHeight: 1024"* && "$ICON_INFO" == *"hasAlpha: no"* ]]; then
  pass "App icon is 1024x1024 with no alpha"
else
  fail "App icon must be 1024x1024 with no alpha"
fi

TEAM_ID="$(read_config_value DEVELOPMENT_TEAM | tr -d '[:space:]')"
AI_PROXY_URL="$(read_config_value AI_PROXY_URL | tr -d '[:space:]')"

if [[ -n "$TEAM_ID" ]]; then
  pass "DEVELOPMENT_TEAM is set to $TEAM_ID"
else
  warn "DEVELOPMENT_TEAM is blank. Sign in to Xcode and choose your Apple Developer Team before uploading."
fi

if [[ -n "$AI_PROXY_URL" ]]; then
  pass "AI_PROXY_URL is set"
else
  warn "AI_PROXY_URL is blank. This is fine for offline mode. Set it only after deploying the AI proxy."
fi

if [[ "${1:-}" == "--build" ]]; then
  note ""
  note "Running unsigned Release build check..."
  DERIVED_DATA="${CHADDROP_RELEASE_DERIVED_DATA:-/private/tmp/chaddrop_release_dd}"
  xcodebuild \
    -project TruthTranslator.xcodeproj \
    -scheme TruthTranslator \
    -derivedDataPath "$DERIVED_DATA" \
    -configuration Release \
    -destination "generic/platform=iOS" \
    build \
    CODE_SIGNING_ALLOWED=NO
  pass "Unsigned Release build passed"
fi

note ""
if [[ "$failures" -eq 0 ]]; then
  pass "Preflight complete"
else
  fail "$failures required check(s) failed"
  exit 1
fi
