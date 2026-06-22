#!/usr/bin/env python3
"""Generate MetaBro brand assets: app icon + logo lockup.

Produces SVG (source of truth) and rendered PNGs. The mark is a Liquid-Glass
rounded square with a bold monogram "M" whose center forms an upward chevron —
reading as both the letter M and an upvote / growth arrow (the Reddit half),
seated in a soft chat-bubble glow (the Facebook half).
"""
from __future__ import annotations
import os
import cairosvg

OUT = os.path.dirname(os.path.abspath(__file__))
BRAND = os.path.normpath(os.path.join(OUT, "..", "..", "MetaBro", "Branding"))
os.makedirs(BRAND, exist_ok=True)

# Brand palette (matches the app's design tokens)
BLUE = "#5C8CFF"
INDIGO = "#3A41C6"
GREEN = "#33C78C"
INK = "#0E1330"


def monogram(stroke="#FFFFFF", w=104):
    """Bold 'M' with an upward center peak. Drawn on a 1024 canvas."""
    return f'''
    <path d="M 296 712 L 330 322 L 512 512 L 694 322 L 728 712"
          fill="none" stroke="{stroke}" stroke-width="{w}"
          stroke-linecap="round" stroke-linejoin="round"/>
    <!-- upvote chevron tucked into the M's peak -->
    <path d="M 430 470 L 512 388 L 594 470"
          fill="none" stroke="{GREEN}" stroke-width="34"
          stroke-linecap="round" stroke-linejoin="round"/>'''


def gradient_defs(idp):
    return f'''
      <linearGradient id="bg{idp}" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" stop-color="{BLUE}"/>
        <stop offset="0.55" stop-color="{INDIGO}"/>
        <stop offset="1" stop-color="#2A2E8F"/>
      </linearGradient>
      <radialGradient id="glow{idp}" cx="0.32" cy="0.26" r="0.8">
        <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.35"/>
        <stop offset="0.5" stop-color="#FFFFFF" stop-opacity="0.06"/>
        <stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
      </radialGradient>'''


def icon_svg(rounded: bool) -> str:
    """1024x1024 app icon. rounded=True bakes a squircle + transparency
    (for marketing); rounded=False is full-bleed square (for the iOS asset,
    which the system masks itself)."""
    clip = ('<rect x="0" y="0" width="1024" height="1024" rx="224" ry="224"/>'
            if rounded else
            '<rect x="0" y="0" width="1024" height="1024"/>')
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    {gradient_defs("i")}
    <clipPath id="clip">{clip}</clipPath>
  </defs>
  <g clip-path="url(#clip)">
    <rect x="0" y="0" width="1024" height="1024" fill="url(#bgi)"/>
    <!-- Liquid-glass specular highlight -->
    <ellipse cx="330" cy="250" rx="620" ry="430" fill="url(#glowi)"/>
    <!-- soft inner ring -->
    <rect x="78" y="78" width="868" height="868" rx="190" ry="190"
          fill="none" stroke="#FFFFFF" stroke-opacity="0.10" stroke-width="6"/>
    {monogram()}
  </g>
</svg>'''


def logo_svg() -> str:
    """Horizontal lockup: rounded icon mark + wordmark + slogan."""
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1520" height="460" viewBox="0 0 1520 460">
  <defs>
    {gradient_defs("l")}
  </defs>
  <!-- icon mark (scaled 0.4 of 1024 = ~410) -->
  <g transform="translate(40,30) scale(0.40)">
    <clipPath id="lclip"><rect x="0" y="0" width="1024" height="1024" rx="224" ry="224"/></clipPath>
    <g clip-path="url(#lclip)">
      <rect width="1024" height="1024" fill="url(#bgl)"/>
      <ellipse cx="330" cy="250" rx="620" ry="430" fill="url(#glowl)"/>
      {monogram()}
    </g>
  </g>
  <!-- wordmark -->
  <text x="500" y="232" font-family="DejaVu Sans, Helvetica, Arial, sans-serif"
        font-size="150" font-weight="bold" fill="{INK}" letter-spacing="-3">Meta<tspan fill="{INDIGO}">Bro</tspan></text>
  <!-- slogan -->
  <text x="506" y="300" font-family="DejaVu Sans, Helvetica, Arial, sans-serif"
        font-size="40" font-weight="bold" fill="{GREEN}" letter-spacing="2.5">THE MAN CAVE OF THE INTERNET</text>
</svg>'''


def write(name, svg):
    path = os.path.join(BRAND, name)
    with open(path, "w") as f:
        f.write(svg)
    return path


def render(svg_name, png_name, scale=1.0, bg=None):
    cairosvg.svg2png(url=os.path.join(BRAND, svg_name),
                     write_to=os.path.join(BRAND, png_name),
                     scale=scale, background_color=bg)


if __name__ == "__main__":
    write("icon.svg", icon_svg(rounded=True))
    write("icon_square.svg", icon_svg(rounded=False))
    write("logo.svg", logo_svg())

    # App-store style rounded icon + iOS square asset + logo.
    render("icon.svg", "icon-1024.png")
    render("icon_square.svg", "AppIcon-1024.png", bg="#3A41C6")  # opaque, no alpha
    render("icon.svg", "icon-180.png", scale=180/1024)
    render("logo.svg", "logo.png")
    render("logo.svg", "logo-on-white.png", bg="#FFFFFF")
    print("Brand assets written to", BRAND)
