#!/bin/sh
# Resize iPhone screenshots to Apple's required App Store dimensions.
#
# Apple requires AT LEAST one screenshot at the 6.7" iPhone size:
#   1290 × 2796 (iPhone Pro Max class)
# A 1170×2532 screenshot from a non-Max iPhone has nearly the same
# aspect ratio, so a simple upscale works. Pixels get slightly soft
# but Apple accepts the result.
#
# Usage:
#   ./docs/aim/resize-screenshots.sh /path/to/input/dir /path/to/output/dir
#
# Or with defaults (current dir → ./resized/):
#   ./docs/aim/resize-screenshots.sh
#
# Requires: macOS (uses `sips`, which ships with macOS).

set -eu

IN_DIR="${1:-.}"
OUT_DIR="${2:-./resized}"
TARGET_W=1290
TARGET_H=2796

if [ ! -d "$IN_DIR" ]; then
  echo "Input dir not found: $IN_DIR"
  exit 1
fi

mkdir -p "$OUT_DIR"

echo "Resizing screenshots in $IN_DIR → $OUT_DIR (target: ${TARGET_W}x${TARGET_H})"
echo

count=0
for img in "$IN_DIR"/*.png "$IN_DIR"/*.PNG "$IN_DIR"/*.jpg "$IN_DIR"/*.JPG "$IN_DIR"/*.jpeg 2>/dev/null; do
  [ -f "$img" ] || continue
  name=$(basename "$img")
  out="$OUT_DIR/$name"
  # sips --resampleHeightWidth: upscale to exact pixel dimensions
  # (Apple checks pixel size, not aspect ratio, for App Store assets).
  sips --resampleHeightWidth "$TARGET_H" "$TARGET_W" "$img" --out "$out" >/dev/null
  echo "  ✓ $name → ${TARGET_W}x${TARGET_H}"
  count=$((count + 1))
done

if [ "$count" -eq 0 ]; then
  echo "No images found in $IN_DIR (looking for .png/.jpg/.jpeg)"
  exit 1
fi

echo
echo "Done. $count screenshot(s) ready for App Store Connect upload at $OUT_DIR/"
