#!/usr/bin/env python3
from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "BareClaw" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"
SIZE = 1024


def hex_to_rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) for i in (0, 2, 4))


def blend(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return tuple(round(a[i] * (1 - t) + b[i] * t) for i in range(3))


def radial_gradient(
    size: int,
    center: tuple[float, float],
    inner: str,
    outer: str,
    radius: float,
    opacity: float = 1.0,
) -> Image.Image:
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    pixels = image.load()
    inner_rgb = hex_to_rgb(inner)
    outer_rgb = hex_to_rgb(outer)
    cx, cy = center

    for y in range(size):
        for x in range(size):
            d = math.hypot(x - cx, y - cy) / radius
            t = min(1.0, max(0.0, d))
            rgb = blend(inner_rgb, outer_rgb, t)
            alpha = round(255 * opacity * (1.0 - min(1.0, t * 0.92)))
            pixels[x, y] = (*rgb, alpha)

    return image


def linear_gradient(size: int, top_left: str, bottom_right: str) -> Image.Image:
    image = Image.new("RGB", (size, size), hex_to_rgb(top_left))
    pixels = image.load()
    start = hex_to_rgb(top_left)
    end = hex_to_rgb(bottom_right)

    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            pixels[x, y] = blend(start, end, t)

    return image


def rounded_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def font(size: int, bold: bool = True) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        "/System/Library/Fonts/Supplemental/Avenir Next Condensed.ttc",
        "/System/Library/Fonts/Supplemental/Avenir Next.ttc",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/Library/Fonts/Arial Bold.ttf" if bold else "/Library/Fonts/Arial.ttf",
    ]
    for candidate in candidates:
        try:
            return ImageFont.truetype(candidate, size=size)
        except OSError:
            continue
    return ImageFont.load_default()


def paste_rotated_text(
    base: Image.Image,
    text: str,
    center: tuple[int, int],
    radius: float,
    span_degrees: float,
    center_degrees: float,
    font_size: int,
    fill: tuple[int, int, int, int],
) -> None:
    chars = list(text)
    step = span_degrees / max(1, len(chars) - 1)
    start = center_degrees - span_degrees / 2
    typeface = font(font_size)

    for index, char in enumerate(chars):
        angle = start + step * index
        theta = math.radians(angle)
        x = center[0] + math.cos(theta) * radius
        y = center[1] + math.sin(theta) * radius

        bbox = typeface.getbbox(char)
        tw = bbox[2] - bbox[0]
        th = bbox[3] - bbox[1]
        glyph = Image.new("RGBA", (tw + 40, th + 40), (0, 0, 0, 0))
        glyph_draw = ImageDraw.Draw(glyph)
        glyph_draw.text((20 - bbox[0], 20 - bbox[1]), char, font=typeface, fill=fill)
        rotated = glyph.rotate(angle + 90, expand=True, resample=Image.Resampling.BICUBIC)
        base.alpha_composite(rotated, (round(x - rotated.width / 2), round(y - rotated.height / 2)))


def sparkle_points(cx: float, cy: float, radius: float) -> list[tuple[float, float]]:
    inner = radius * 0.34
    points: list[tuple[float, float]] = []
    for index in range(8):
        angle = math.radians(-90 + index * 45)
        current = radius if index % 2 == 0 else inner
        points.append((cx + math.cos(angle) * current, cy + math.sin(angle) * current))
    return points


def ellipse(draw: ImageDraw.ImageDraw, cx: float, cy: float, rx: float, ry: float, fill, outline=None, width=1) -> None:
    box = (cx - rx, cy - ry, cx + rx, cy + ry)
    draw.ellipse(box, fill=fill, outline=outline, width=width)


def draw_bear(base: Image.Image, bbox: tuple[int, int, int, int]) -> None:
    x0, y0, x1, y1 = bbox
    w = x1 - x0
    h = y1 - y0
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)

    fur_dark = "#6B3F1F"
    fur_mid = "#9B5E2A"
    fur_light = "#C2843E"
    muzzle = "#D4A574"
    nose = "#1A0800"
    cheek = "#E87878"
    ear_pink = "#F5A0B0"

    def px(rx: float) -> float:
        return x0 + rx * w

    def py(ry: float) -> float:
        return y0 + ry * h

    ear_r = w * 0.215
    for ex, ey in [(px(0.215), py(0.185)), (px(0.785), py(0.185))]:
        ellipse(draw, ex, ey, ear_r, ear_r * 0.9, fill=fur_dark)
        ellipse(draw, ex, ey, ear_r * 0.6, ear_r * 0.48, fill=ear_pink)

    face_box = (px(0.085), py(0.095), px(0.915), py(0.895))
    face = Image.new("RGBA", base.size, (0, 0, 0, 0))
    face_mask = Image.new("L", base.size, 0)
    ImageDraw.Draw(face_mask).ellipse(face_box, fill=255)
    gradient = radial_gradient(
        SIZE,
        center=(px(0.46), py(0.37)),
        inner=fur_light,
        outer=fur_dark,
        radius=w * 0.52,
        opacity=1.0,
    )
    face.alpha_composite(gradient)
    face.putalpha(face_mask)
    layer.alpha_composite(face)

    draw = ImageDraw.Draw(layer)
    ellipse(draw, px(0.5), py(0.65), w * 0.158, h * 0.105, fill=muzzle)
    for cx in [px(0.285), px(0.715)]:
        ellipse(draw, cx, py(0.60), w * 0.104, h * 0.063, fill=(*hex_to_rgb(cheek), 102))

    for cx in [px(0.368), px(0.632)]:
        cy = py(0.432)
        er = w * 0.064
        ellipse(draw, cx, cy, er * 1.15, er * 1.26, fill=(255, 255, 255, 255))
        ellipse(draw, cx, cy, er, er, fill="#120600")
        ellipse(draw, cx + er * 0.46, cy - er * 0.36, er * 0.25, er * 0.25, fill=(255, 255, 255, 240))

    ellipse(draw, px(0.5), py(0.625), w * 0.047, h * 0.031, fill=nose)
    smile_y = py(0.705)
    draw.arc((px(0.445), smile_y - h * 0.04, px(0.555), smile_y + h * 0.04), start=12, end=168, fill=nose, width=max(8, round(w * 0.022)))

    base.alpha_composite(layer)


def draw_icon() -> Image.Image:
    background = linear_gradient(SIZE, "#1E3932", "#0C1E18").convert("RGBA")
    background.alpha_composite(
        radial_gradient(SIZE, (SIZE * 0.50, SIZE * 0.46), "#CBA258", "#0C1E18", SIZE * 0.55, opacity=0.24)
    )

    vignette = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    vignette_draw = ImageDraw.Draw(vignette)
    vignette_draw.rectangle((0, 0, SIZE, SIZE), fill=(0, 0, 0, 0))
    edge = radial_gradient(SIZE, (SIZE * 0.5, SIZE * 0.48), "#000000", "#000000", SIZE * 0.78, opacity=0.0)
    edge_alpha = Image.new("L", (SIZE, SIZE), 0)
    edge_pixels = edge_alpha.load()
    for y in range(SIZE):
        for x in range(SIZE):
            d = math.hypot(x - SIZE * 0.5, y - SIZE * 0.48) / (SIZE * 0.74)
            edge_pixels[x, y] = round(150 * max(0, min(1, d - 0.55)) / 0.45)
    vignette.putalpha(edge_alpha)
    background.alpha_composite(vignette)

    icon = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 255))
    icon.alpha_composite(background)
    draw = ImageDraw.Draw(icon)

    center = (SIZE // 2, SIZE // 2 + 8)
    badge_radius = 392

    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.ellipse(
        (
            center[0] - badge_radius,
            center[1] - badge_radius + 26,
            center[0] + badge_radius,
            center[1] + badge_radius + 26,
        ),
        fill=(0, 0, 0, 92),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(34))
    icon.alpha_composite(shadow)

    draw.ellipse(
        (
            center[0] - badge_radius,
            center[1] - badge_radius,
            center[0] + badge_radius,
            center[1] + badge_radius,
        ),
        fill="#1E3932",
        outline="#CBA258",
        width=23,
    )
    draw.ellipse(
        (
            center[0] - badge_radius + 76,
            center[1] - badge_radius + 76,
            center[0] + badge_radius - 76,
            center[1] + badge_radius - 76,
        ),
        outline=(203, 162, 88, 80),
        width=10,
    )

    highlight = radial_gradient(SIZE, (center[0] - 86, center[1] - 132), "#2A5248", "#1E3932", badge_radius * 1.18, opacity=0.92)
    badge_mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(badge_mask).ellipse(
        (
            center[0] - badge_radius + 13,
            center[1] - badge_radius + 13,
            center[0] + badge_radius - 13,
            center[1] + badge_radius - 13,
        ),
        fill=255,
    )
    highlight.putalpha(badge_mask)
    icon.alpha_composite(highlight)

    paste_rotated_text(
        icon,
        "BARECLAW",
        center=center,
        radius=282,
        span_degrees=146,
        center_degrees=-90,
        font_size=72,
        fill=(203, 162, 88, 255),
    )

    for sx in [-1, 1]:
        draw.polygon(sparkle_points(center[0] + sx * 250, center[1] - 270, 31), fill=(203, 162, 88, 194))
        draw.polygon(sparkle_points(center[0] + sx * 250, center[1] - 270, 15), fill=(246, 220, 156, 215))

    draw_bear(icon, (center[0] - 238, center[1] - 158, center[0] + 238, center[1] + 318))

    for offset in [-46, 0, 46]:
        draw.ellipse(
            (
                center[0] + offset - 13,
                center[1] + 300 - 13,
                center[0] + offset + 13,
                center[1] + 300 + 13,
            ),
            fill=(203, 162, 88, 153),
        )

    return icon.convert("RGB")


def main() -> None:
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    draw_icon().save(OUTPUT, "PNG")
    print(OUTPUT)


if __name__ == "__main__":
    main()
