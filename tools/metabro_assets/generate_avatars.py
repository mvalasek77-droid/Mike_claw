#!/usr/bin/env python3
"""MetaBro generative avatar + community-icon flow.

Every user and Bro-hood gets a unique, deterministic, generative avatar. The
seed mixes the identity handle/slug with the *current date*, so the whole
gallery subtly regenerates **once per day** (run on a cron — see
.github/workflows/avatars-daily.yml).

Two backends:
  • "procedural" (default) — layered Liquid-Glass generative art rendered
    locally with cairosvg. No API key, so CI is hermetic and free.
  • "api" — POST the per-identity prompt to an image model and save the result.
    Enable with METABRO_IMAGE_API_URL (+ METABRO_IMAGE_API_KEY). This is the
    hook for a real diffusion model; the procedural backend is the fallback.

Usage:
  python generate_avatars.py                  # today's gallery
  python generate_avatars.py --date 2026-07-01
"""
from __future__ import annotations
import argparse
import datetime as dt
import hashlib
import os
import cairosvg

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "MetaBro", "Branding", "avatars")

# Curated, on-brand gradient palettes (each: two stops).
PALETTES = [
    ("#5C8CFF", "#3A41C6"), ("#33C78C", "#1F7A6B"), ("#FF6B35", "#B5179E"),
    ("#7B61FF", "#3A41C6"), ("#00B4D8", "#0077B6"), ("#F72585", "#7209B7"),
    ("#FFB703", "#FB8500"), ("#2EC4B6", "#3A41C6"), ("#EF476F", "#B5179E"),
]


def _ints(seed: str, n: int) -> list[int]:
    """Deterministic stream of ints from a seed."""
    out, i = [], 0
    while len(out) < n:
        d = hashlib.sha256(f"{seed}:{i}".encode()).digest()
        out.extend(d)
        i += 1
    return out[:n]


def _prompt(label: str, kind: str) -> str:
    """The text prompt the 'api' backend would send to an image model."""
    subject = "abstract emblem for a men's community" if kind == "group" else "abstract avatar"
    return (f"MetaBro {subject}, liquid glass, soft volumetric gradient, "
            f"premium iOS app style, monogram '{label}', no text, centered")


def avatar_svg(seed: str, label: str, kind: str = "user", size: int = 512) -> str:
    b = _ints(seed, 32)
    c1, c2 = PALETTES[b[0] % len(PALETTES)]
    rot = b[1] % 360
    # decorative liquid-glass blobs
    blobs = ""
    for k in range(4):
        cx = 80 + (b[2 + k] % (size - 160))
        cy = 80 + (b[8 + k] % (size - 160))
        r = 70 + (b[14 + k] % 140)
        op = 0.10 + (b[20 + k] % 18) / 100.0
        blobs += (f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="#FFFFFF" '
                  f'fill-opacity="{op:.2f}"/>')
    # frosted center plate holding the monogram
    if kind == "group":
        plate = (f'<rect x="{size*0.24:.0f}" y="{size*0.24:.0f}" '
                 f'width="{size*0.52:.0f}" height="{size*0.52:.0f}" rx="{size*0.16:.0f}" '
                 f'fill="#FFFFFF" fill-opacity="0.16" stroke="#FFFFFF" stroke-opacity="0.35"/>')
    else:
        plate = (f'<circle cx="{size/2:.0f}" cy="{size/2:.0f}" r="{size*0.27:.0f}" '
                 f'fill="#FFFFFF" fill-opacity="0.16" stroke="#FFFFFF" stroke-opacity="0.35"/>')
    fs = int(size * 0.30)
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}">
  <defs>
    <linearGradient id="g" x1="0" y1="0" x2="1" y2="1" gradientTransform="rotate({rot} 0.5 0.5)">
      <stop offset="0" stop-color="{c1}"/><stop offset="1" stop-color="{c2}"/>
    </linearGradient>
    <clipPath id="c"><rect width="{size}" height="{size}" rx="{size*0.22:.0f}"/></clipPath>
  </defs>
  <g clip-path="url(#c)">
    <rect width="{size}" height="{size}" fill="url(#g)"/>
    {blobs}
    <ellipse cx="{size*0.32:.0f}" cy="{size*0.24:.0f}" rx="{size*0.6:.0f}" ry="{size*0.42:.0f}"
             fill="#FFFFFF" fill-opacity="0.12"/>
    {plate}
    <text x="50%" y="50%" dy="{int(fs*0.35)}" text-anchor="middle"
          font-family="DejaVu Sans, Helvetica, Arial, sans-serif" font-weight="bold"
          font-size="{fs}" fill="#FFFFFF">{label}</text>
  </g>
</svg>'''


def generate(identities: list[dict], date: str) -> list[str]:
    os.makedirs(OUT, exist_ok=True)
    api = os.environ.get("METABRO_IMAGE_API_URL")
    written = []
    for ident in identities:
        seed = f"{ident['id']}|{date}"
        svg = avatar_svg(seed, ident["label"], ident["kind"])
        stem = ident["id"]
        svg_path = os.path.join(OUT, f"{stem}.svg")
        png_path = os.path.join(OUT, f"{stem}.png")
        with open(svg_path, "w") as f:
            f.write(svg)
        if api:
            _render_via_api(api, _prompt(ident["label"], ident["kind"]), png_path)
        else:
            cairosvg.svg2png(bytestring=svg.encode(), write_to=png_path)
        written.append(png_path)
    return written


def _render_via_api(url: str, prompt: str, out_path: str) -> None:
    """Send the prompt to an image model and save the PNG. Falls back to the
    procedural render on any error so the daily job never hard-fails."""
    import json
    import urllib.request
    key = os.environ.get("METABRO_IMAGE_API_KEY", "")
    req = urllib.request.Request(
        url, method="POST",
        data=json.dumps({"prompt": prompt, "size": "512x512"}).encode(),
        headers={"Content-Type": "application/json",
                 "Authorization": f"Bearer {key}"})
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            with open(out_path, "wb") as f:
                f.write(resp.read())
    except Exception as e:  # pragma: no cover - network dependent
        print(f"  ! API render failed ({e}); keeping procedural PNG")


# The seed roster (mirrors the app's mock services).
USERS = [
    {"id": "you", "label": "Y", "kind": "user"},
    {"id": "ironbro", "label": "M", "kind": "user"},
    {"id": "coachdave", "label": "D", "kind": "user"},
    {"id": "newbro", "label": "S", "kind": "user"},
    {"id": "theoknows", "label": "T", "kind": "user"},
    {"id": "rajlifts", "label": "R", "kind": "user"},
    {"id": "leobuilds", "label": "L", "kind": "user"},
    {"id": "coachmike", "label": "CM", "kind": "user"},
    {"id": "gainz_bot", "label": "G", "kind": "user"},
    {"id": "hotmic", "label": "H", "kind": "user"},
]
GROUPS = [
    {"id": "fitness", "label": "IB", "kind": "group"},      # Iron Bro-hood
    {"id": "bbq", "label": "GM", "kind": "group"},          # Grill Masters
    {"id": "cars", "label": "GG", "kind": "group"},         # Garage Gearheads
    {"id": "fatherhood", "label": "DM", "kind": "group"},   # Dad Mode
    {"id": "philosophy", "label": "SB", "kind": "group"},   # Stoic Bros
]


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--date", default=dt.date.today().isoformat(),
                    help="YYYY-MM-DD seed date (defaults to today)")
    args = ap.parse_args()
    files = generate(USERS + GROUPS, args.date)
    print(f"Generated {len(files)} avatars for {args.date} -> {OUT}")
