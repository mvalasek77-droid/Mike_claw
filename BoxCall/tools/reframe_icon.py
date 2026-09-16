#!/usr/bin/env python3
"""Reframe the BoxCall marquee artwork for the iOS and watchOS icon slots.

The source art is drawn with a wide dark border, so the marquee fills
only ~77% of the canvas height. iOS then masks it to a squircle on top
of that, which leaves the mark looking like a small badge floating in a
dark square — and it is a large part of why the icon turns to mud at
home-screen sizes.

This crops in to the artwork's real bounds and rescales, so the mark
fills the frame. The watch slot needs the opposite treatment: its mask
is a circle, and the marquee's diagonal does not fit inside one at full
size, so there the art is inset instead.

    pip install Pillow && python3 tools/reframe_icon.py
"""

import os
from PIL import Image, ImageStat

SIZE = 1024
SRC = "tools/BoxCallAppIcon-source.png"

# How much of the frame the artwork should occupy. 0.89 on iOS keeps the
# marquee's bulb frame clear of the squircle's corners; the watch value
# is set by geometry, not taste — see below.
IOS_FILL = 0.89
WATCH_DIAGONAL_FILL = 0.93


def content_bounds(img, thresh=18, step=8):
    """Bounding box of the artwork, ignoring the near-black surround."""
    g = img.convert("L")
    w, h = g.size
    rows = [ImageStat.Stat(g.crop((0, y, w, y + step))).mean[0]
            for y in range(0, h, step)]
    cols = [ImageStat.Stat(g.crop((x, 0, x + step, h))).mean[0]
            for x in range(0, w, step)]

    def span(v):
        lit = [i for i, m in enumerate(v) if m > thresh]
        return lit[0] * step, lit[-1] * step + step

    top, bottom = span(rows)
    left, right = span(cols)
    return left, top, right, bottom


def edge_color(img, pad=6):
    """The surround colour, so any padding we add is invisible."""
    w, h = img.size
    px = img.convert("RGB").load()
    samples = [px[x, y] for x, y in
               ((pad, pad), (w - pad, pad), (pad, h - pad), (w - pad, h - pad))]
    return tuple(sum(c[i] for c in samples) // len(samples) for i in range(3))


def reframe(img, fill):
    """Centre the artwork in a square that it fills to `fill`, then scale."""
    l, t, r, b = content_bounds(img)
    cw, ch = r - l, b - t
    cx, cy = (l + r) / 2, (t + b) / 2
    side = max(cw, ch) / fill

    box = (round(cx - side / 2), round(cy - side / 2),
           round(cx + side / 2), round(cy + side / 2))

    # The crop may reach past the source when we are insetting rather
    # than zooming, so lay it onto a padded canvas first.
    ground = edge_color(img)
    pad = max(0, -min(box[0], box[1]),
              max(box[2] - img.width, box[3] - img.height, 0))
    if pad:
        canvas = Image.new("RGB", (img.width + 2 * pad, img.height + 2 * pad), ground)
        canvas.paste(img.convert("RGB"), (pad, pad))
        box = tuple(v + pad for v in box)
        img = canvas

    return img.convert("RGB").crop(box).resize((SIZE, SIZE), Image.LANCZOS)


def watch(img):
    """The watch mask is a circle, so the artwork's *diagonal* is what has
    to fit, not its width. That is a tighter constraint than iOS."""
    l, t, r, b = content_bounds(img)
    diag = ((r - l) ** 2 + (b - t) ** 2) ** 0.5
    # Solve for the fill that puts the diagonal inside the circle.
    fill = max(r - l, b - t) / (diag / WATCH_DIAGONAL_FILL)
    return reframe(img, fill)


CONTENTS = """{
  "images" : [
    {
      "filename" : "AppIcon.png",
      "idiom" : "universal",
      "platform" : "%s",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""


def write(path, img, platform):
    os.makedirs(path, exist_ok=True)
    # No alpha channel: App Store Connect rejects an icon that has one.
    img.convert("RGB").save(os.path.join(path, "AppIcon.png"), "PNG")
    with open(os.path.join(path, "Contents.json"), "w") as f:
        f.write(CONTENTS % platform)
    print("wrote", path)


if __name__ == "__main__":
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(root)
    src = Image.open(SRC)
    write("BoxCall/Assets.xcassets/AppIcon.appiconset", reframe(src, IOS_FILL), "ios")
    write("BoxCallWatch/Assets.xcassets/AppIcon.appiconset", watch(src), "watchos")
