"""Generates Sources/Assets.xcassets/AppIcon.appiconset from scratch.

An original shield-and-block mark — deliberately NOT derived from Roblox's
own logo, wordmark, or red/white blockhead branding. RobloxGuard is an
unaffiliated third-party app; an icon that reads as official Roblox branding
would be a trademark problem and an App Store guideline 4.1 ("copycat")
problem. The blocky/voxel motif here nods at "a blocky game world" in the
generic sense, not at Roblox specifically, rendered in the app's own teal/ink
identity (same palette as Theme.swift and the ASC field manual).

Usage: pip install pillow && python3 generate_app_icon.py
Regenerates every PNG + Contents.json in the appiconset in place.
"""

import json
import math
import os

from PIL import Image, ImageDraw

SIZE = 1024
INK = (20, 36, 32)
ACCENT = (27, 111, 104)
PAPER = (245, 247, 244)
CUBE_TOP = (150, 205, 198)
CUBE_LEFT = (27, 111, 104)
CUBE_RIGHT = (16, 30, 27)

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "Sources", "Assets.xcassets", "AppIcon.appiconset")

# (idiom, size_pt, scale, filename)
SPECS = [
    ("iphone", 20, 2, "icon-20@2x.png"),
    ("iphone", 20, 3, "icon-20@3x.png"),
    ("iphone", 29, 2, "icon-29@2x.png"),
    ("iphone", 29, 3, "icon-29@3x.png"),
    ("iphone", 40, 2, "icon-40@2x.png"),
    ("iphone", 40, 3, "icon-40@3x.png"),
    ("iphone", 60, 2, "icon-60@2x.png"),
    ("iphone", 60, 3, "icon-60@3x.png"),
    ("ipad", 20, 1, "icon-20.png"),
    ("ipad", 20, 2, "icon-20-ipad@2x.png"),
    ("ipad", 29, 1, "icon-29.png"),
    ("ipad", 29, 2, "icon-29-ipad@2x.png"),
    ("ipad", 40, 1, "icon-40.png"),
    ("ipad", 40, 2, "icon-40-ipad@2x.png"),
    ("ipad", 76, 1, "icon-76.png"),
    ("ipad", 76, 2, "icon-76@2x.png"),
    ("ipad", 83.5, 2, "icon-83.5@2x.png"),
    ("ios-marketing", 1024, 1, "icon-1024.png"),
]


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def draw_gradient_bg(img):
    px = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            px[x, y] = lerp(INK, ACCENT, (x + y) / (2 * SIZE))


def shield_polygon():
    cx, top_y = SIZE / 2, 230
    return [
        (cx - 190, top_y), (cx + 190, top_y),
        (cx + 262, top_y + 190), (cx + 150, top_y + 470),
        (cx, top_y + 610), (cx - 150, top_y + 470),
        (cx - 262, top_y + 190),
    ]


def iso_cube(draw, cx, cy, edge):
    dx = edge * math.cos(math.radians(30))
    dy = edge * math.sin(math.radians(30))
    top, right, center, left = (cx, cy), (cx + dx, cy + dy), (cx, cy + 2 * dy), (cx - dx, cy + dy)
    right2, center2, left2 = (cx + dx, cy + dy + edge), (cx, cy + 2 * dy + edge), (cx - dx, cy + dy + edge)
    draw.polygon([top, right, center, left], fill=CUBE_TOP)
    draw.polygon([left, center, center2, left2], fill=CUBE_LEFT)
    draw.polygon([center, right, right2, center2], fill=CUBE_RIGHT)


def render_master() -> Image.Image:
    img = Image.new("RGB", (SIZE, SIZE), INK)
    draw_gradient_bg(img)
    draw = ImageDraw.Draw(img)
    draw.polygon(shield_polygon(), fill=PAPER)
    iso_cube(draw, SIZE / 2, 430, 150)
    return img


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    master = render_master()

    images = []
    for idiom, size_pt, scale, filename in SPECS:
        px = round(size_pt * scale)
        master.resize((px, px), Image.LANCZOS).save(os.path.join(OUT_DIR, filename))
        images.append({
            "idiom": idiom,
            "size": f"{size_pt:g}x{size_pt:g}",
            "scale": f"{scale}x",
            "filename": filename,
        })

    with open(os.path.join(OUT_DIR, "Contents.json"), "w") as f:
        json.dump({"images": images, "info": {"version": 1, "author": "xcode"}}, f, indent=2)
        f.write("\n")

    print(f"Wrote {len(images)} icon sizes + Contents.json to {OUT_DIR}")


if __name__ == "__main__":
    main()
