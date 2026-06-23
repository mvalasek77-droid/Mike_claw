#!/usr/bin/env python3
"""Generate Screenshot Studio's 1024x1024 App Store icon.

Pure-Pillow, deterministic, and committed so the icon can be regenerated
without design tooling. Renders the brand mark — a phone screen framed by a
crop reticle — over the Aurora gradient used throughout the app.

Usage:  python3 Scripts/generate_app_icon.py
"""
from __future__ import annotations
import math
import os
from PIL import Image, ImageDraw

SIZE = 1024
OUT = os.path.join(
    os.path.dirname(__file__), "..",
    "ScreenshotStudio", "Resources", "Assets.xcassets",
    "AppIcon.appiconset", "icon-1024.png",
)

# Brand palette (matches LiquidGlass.accent / .accentSecondary).
INDIGO = (97, 87, 255)
MAGENTA = (238, 73, 253)


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def diagonal_gradient(size, c0, c1):
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            px[x, y] = lerp(c0, c1, t)
    return img


def rounded_rect(draw, box, radius, **kw):
    draw.rounded_rectangle(box, radius=radius, **kw)


def main():
    # Supersample 2x for crisp anti-aliased edges, then downscale.
    s = SIZE * 2
    img = diagonal_gradient(s, INDIGO, MAGENTA)
    draw = ImageDraw.Draw(img, "RGBA")

    # Soft top-left sheen for depth.
    sheen = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sheen)
    sd.ellipse([-s * 0.3, -s * 0.4, s * 0.7, s * 0.5], fill=(255, 255, 255, 38))
    img.paste(Image.alpha_composite(img.convert("RGBA"), sheen).convert("RGB"), (0, 0))
    draw = ImageDraw.Draw(img, "RGBA")

    # Phone screen panel (dark glass).
    pw, ph = s * 0.40, s * 0.52
    cx, cy = s / 2, s / 2
    box = [cx - pw / 2, cy - ph / 2, cx + pw / 2, cy + ph / 2]
    rounded_rect(draw, box, radius=s * 0.07, fill=(8, 10, 22, 235))
    rounded_rect(draw, box, radius=s * 0.07, outline=(255, 255, 255, 90), width=int(s * 0.006))

    # Crop reticle inside the screen.
    inset = s * 0.055
    rb = [box[0] + inset, box[1] + inset, box[2] - inset, box[3] - inset]
    arm = (rb[2] - rb[0]) * 0.26
    lw = int(s * 0.018)
    white = (255, 255, 255, 255)

    def corner(p, dx, dy):
        draw.line([p[0], p[1] + dy * arm, p[0], p[1]], fill=white, width=lw)
        draw.line([p[0], p[1], p[0] + dx * arm, p[1]], fill=white, width=lw)

    corner((rb[0], rb[1]), 1, 1)
    corner((rb[2], rb[1]), -1, 1)
    corner((rb[2], rb[3]), -1, -1)
    corner((rb[0], rb[3]), 1, -1)

    # Center focus dot.
    r = s * 0.018
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=white)

    img = img.resize((SIZE, SIZE), Image.LANCZOS)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    img.save(OUT, "PNG")
    print(f"wrote {OUT} ({img.size[0]}x{img.size[1]})")


if __name__ == "__main__":
    main()
