#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATEWAY="$ROOT_DIR/AppStore/ChadDrop_Release_Gateway.html"

if [[ ! -f "$GATEWAY" ]]; then
  echo "Could not find release gateway: $GATEWAY"
  exit 1
fi

open "$GATEWAY"

if [[ "${1:-}" == "--links" ]]; then
  open "https://developer.apple.com/account/"
  open "https://developer.apple.com/programs/enroll/"
  open "https://appstoreconnect.apple.com/apps"
  open "https://github.com/new"
  open "https://dash.cloudflare.com/?to=/:account/workers-and-pages"
  open "https://platform.openai.com/api-keys"
fi

echo "Opened ChadDrop Release Gateway."
