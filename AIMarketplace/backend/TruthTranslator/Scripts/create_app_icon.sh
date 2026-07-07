#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="${1:-$ROOT_DIR/TruthTranslator/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png}"

mkdir -p "$(dirname "$OUTPUT")"

CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/private/tmp/chaddrop-swift-module-cache}" \
  swift "$ROOT_DIR/Scripts/create_app_icon.swift" "$OUTPUT"

if command -v magick >/dev/null 2>&1; then
  magick "$OUTPUT" -alpha off "PNG24:$OUTPUT"
fi

echo "Created app icon: $OUTPUT"

echo ""
sips -g pixelWidth -g pixelHeight -g hasAlpha "$OUTPUT"
