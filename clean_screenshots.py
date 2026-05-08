#!/usr/bin/env python3
"""
clean_screenshots.py
Usage:  python3 clean_screenshots.py screenshot1.png screenshot2.png ...
Output: clean_screenshot1.png, clean_screenshot2.png ...

Replaces the iPhone status bar with a clean App Store version:
  • Time → 9:41
  • Back indicator → removed
  • Battery → full, white
  • Signal / WiFi → clean
"""

import sys, os
from PIL import Image, ImageDraw

# ── colours sampled from the chat screenshots ──────────────────────────────
# The toolbar background blurs the sky; approximate it with a semi-warm grey.
BAR_BG   = (178, 165, 145)   # matches the frosted nav bar in the screenshots
TEXT_COL = (255, 255, 255)   # white icons / text
MUTED    = (220, 210, 200)   # slightly dimmed white for secondary elements

def draw_status_bar(draw: ImageDraw.ImageDraw, w: int, bar_h: int, scale: int):
    """Draw a clean status bar at the top of the image."""
    s = scale   # 1 = 1× coords; multiply by s to get pixel coords

    # ── Background ────────────────────────────────────────────────────────
    draw.rectangle([0, 0, w, bar_h], fill=BAR_BG)

    # ── Time  "9:41" centred ──────────────────────────────────────────────
    # Draw as simple bold rectangles (avoids needing a font file)
    # We'll use a font if available, otherwise draw a placeholder bar.
    time_str = "9:41"
    try:
        from PIL import ImageFont
        # Try system fonts
        for font_path in [
            "/System/Library/Fonts/HelveticaNeue.ttc",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
            "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
        ]:
            if os.path.exists(font_path):
                font = ImageFont.truetype(font_path, size=int(15 * s))
                break
        else:
            font = ImageFont.load_default()
        bbox  = draw.textbbox((0, 0), time_str, font=font)
        tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
        draw.text(((w - tw) // 2, (bar_h - th) // 2 - int(1 * s)),
                  time_str, fill=TEXT_COL, font=font)
    except Exception:
        # Fallback: white rectangle as time placeholder
        rx = w // 2 - int(20 * s)
        draw.rectangle([rx, int(8 * s), rx + int(40 * s), int(20 * s)],
                       fill=TEXT_COL)

    # ── Signal bars (left side) ───────────────────────────────────────────
    x0 = int(16 * s)
    cy = bar_h // 2
    for i in range(4):
        bh = int((3 + i * 3) * s)
        bx = x0 + i * int(5 * s)
        draw.rectangle([bx, cy - bh + int(2 * s), bx + int(3 * s), cy + int(2 * s)],
                       fill=TEXT_COL)

    # ── WiFi icon (simple arcs via rectangles) ────────────────────────────
    wx = x0 + int(26 * s)
    for r, op in [(int(8*s), TEXT_COL), (int(5*s), TEXT_COL), (int(2*s), TEXT_COL)]:
        draw.arc([wx - r, cy - r, wx + r, cy + r], start=200, end=340,
                 fill=op, width=max(1, int(1.5 * s)))

    # ── Battery (right side) ─────────────────────────────────────────────
    batt_right = w - int(16 * s)
    batt_w     = int(25 * s)
    batt_h     = int(12 * s)
    batt_top   = cy - batt_h // 2
    nub_w      = int(2 * s)
    nub_h      = int(5 * s)

    # Outer border
    draw.rounded_rectangle(
        [batt_right - batt_w, batt_top,
         batt_right,          batt_top + batt_h],
        radius=int(2 * s), outline=TEXT_COL, width=max(1, int(1 * s))
    )
    # Nub on right
    draw.rectangle(
        [batt_right,          batt_top + (batt_h - nub_h) // 2,
         batt_right + nub_w,  batt_top + (batt_h + nub_h) // 2],
        fill=TEXT_COL
    )
    # Full fill (green battery)
    pad = max(2, int(2 * s))
    draw.rounded_rectangle(
        [batt_right - batt_w + pad, batt_top + pad,
         batt_right - pad,          batt_top + batt_h - pad],
        radius=max(1, int(1 * s)), fill=(80, 220, 100)
    )


def clean(path: str):
    img  = Image.open(path).convert("RGB")
    w, h = img.size

    # Detect scale from width: 1290px = 3×, 390px = 1×
    scale = max(1, round(w / 390))

    # Status bar height: ~44pt on modern iPhones with Dynamic Island
    # At 3× that's 132px, but the visible bar (below Dynamic Island) is ~54pt → ~162px
    # We repaint just the top ~54pt (everything above where the content starts)
    bar_h = int(54 * scale)

    draw = ImageDraw.Draw(img)
    draw_status_bar(draw, w, bar_h, scale)

    out = "clean_" + os.path.basename(path)
    img.save(out, quality=97)
    print(f"  ✓  {out}  ({w}×{h})")


if __name__ == "__main__":
    paths = sys.argv[1:]
    if not paths:
        print("Usage: python3 clean_screenshots.py img1.png img2.png ...")
        sys.exit(1)
    for p in paths:
        clean(p)
    print("\nDone. Upload the clean_*.png files to App Store Connect.")
