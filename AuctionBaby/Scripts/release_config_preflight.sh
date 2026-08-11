#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"

failed=0
fail() {
  echo "FAIL: $*" >&2
  failed=1
}

if [[ "$(/usr/libexec/PlistBuddy -c 'Print :ITSAppUsesNonExemptEncryption' AuctionBaby/Resources/Info.plist 2>/dev/null)" != "false" ]]; then
  fail "ITSAppUsesNonExemptEncryption must be false"
fi

if rg -n '\[(LEGAL ENTITY NAME|EFFECTIVE_DATE|SUPPORT_EMAIL|DMCA_EMAIL|ADDRESS|JURISDICTION|ARBITRATION BODY|EU_REP)\]' legal >/dev/null; then
  fail "legal documents still contain publication placeholders"
fi

settings="$(xcodebuild -project AuctionBaby.xcodeproj -scheme AuctionBaby -configuration Release -showBuildSettings 2>/dev/null)"
for key in AB_WORKER_URL AB_AUTH_URL AB_MATCHING_URL AB_TERMS_URL AB_PRIVACY_URL; do
  value="$(awk -F ' = ' -v wanted="$key" '$1 ~ "^[[:space:]]*" wanted "$" {print $2; exit}' <<<"$settings")"
  if [[ -z "$value" ]]; then
    fail "$key is empty in Release"
  elif [[ "$value" != https://* ]]; then
    fail "$key must resolve to a complete https:// URL (got ${value%%:*}:...)"
  fi
done

# Review v1 must not ingest externally purchased digital currency. Reserve is
# intentionally disabled with the same unconfigured consumables endpoint.
consumables="$(awk -F ' = ' '$1 ~ /^[[:space:]]*AB_CONSUMABLES_URL$/ {print $2; exit}' <<<"$settings")"
if [[ -n "$consumables" ]]; then
  fail "AB_CONSUMABLES_URL must be empty for the v1 App Review archive"
fi

if (( failed )); then
  exit 1
fi

echo "Auction Baby Release configuration preflight passed."
