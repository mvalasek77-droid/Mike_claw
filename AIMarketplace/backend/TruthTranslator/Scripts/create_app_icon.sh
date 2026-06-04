#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="${1:-$ROOT_DIR/TruthTranslator/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png}"

mkdir -p "$(dirname "$OUTPUT")"

if ! command -v magick >/dev/null 2>&1; then
  echo "ImageMagick is required for icon creation on this Mac."
  echo "Install it with Homebrew: brew install imagemagick"
  exit 1
fi

magick -size 1024x1024 gradient:"#35152f-#0b3038" \
  -fill "rgba(255,57,135,0.25)" -draw "circle 120,210 355,210" \
  -fill "rgba(68,199,255,0.22)" -draw "circle 840,180 1050,180" \
  -fill "rgba(158,240,87,0.14)" -draw "circle 850,890 1120,890" \
  -fill "rgba(0,0,0,0.24)" -draw "roundrectangle 176,300 848,774 106,106" \
  -fill white -draw "roundrectangle 176,266 848,740 106,106" \
  -fill white -draw "polygon 286,690 206,846 440,720" \
  -fill "#22232d" -draw "roundrectangle 308,398 414,506 42,42" \
  -fill "#22232d" -draw "polygon 356,492 306,608 416,492" \
  -fill "#22232d" -draw "roundrectangle 502,398 608,506 42,42" \
  -fill "#22232d" -draw "polygon 550,492 500,608 610,492" \
  -fill "#ff8734" -draw "circle 710,538 782,538" \
  -fill "#ff8734" -draw "polygon 710,430 642,555 782,538" \
  -alpha off "PNG24:$OUTPUT"

echo "Created app icon: $OUTPUT"

echo ""
sips -g pixelWidth -g pixelHeight -g hasAlpha "$OUTPUT"
