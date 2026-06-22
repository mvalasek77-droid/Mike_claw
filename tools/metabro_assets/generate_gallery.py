#!/usr/bin/env python3
"""Compose preview sheets: today's avatar gallery + a daily-rotation strip."""
from __future__ import annotations
import base64
import datetime as dt
import os
import cairosvg
import generate_avatars as ga

BRAND = os.path.join(ga.ROOT, "MetaBro", "Branding")
OUT = os.path.join(BRAND, "previews")
INK = "#0E1330"


def _data_uri_from_svg(svg: str) -> str:
    png = cairosvg.svg2png(bytestring=svg.encode())
    return "data:image/png;base64," + base64.b64encode(png).decode()


def _tile(x, y, s, svg, caption):
    uri = _data_uri_from_svg(svg)
    return (f'<image x="{x}" y="{y}" width="{s}" height="{s}" href="{uri}"/>'
            f'<text x="{x + s/2}" y="{y + s + 30}" text-anchor="middle" '
            f'font-family="DejaVu Sans" font-size="22" fill="{INK}">{caption}</text>')


def gallery(date: str) -> str:
    cols, s, pad, top = 5, 200, 40, 110
    rows = 2
    w = cols * s + (cols + 1) * pad
    h = top + rows * (s + 60) + pad
    body = (f'<text x="{pad}" y="56" font-family="DejaVu Sans" font-weight="bold" '
            f'font-size="40" fill="{INK}">MetaBro — Users &amp; Bro-hoods</text>'
            f'<text x="{pad}" y="90" font-family="DejaVu Sans" font-size="22" '
            f'fill="#5C8CFF">Generative avatars · seed date {date}</text>')
    names = {"you": "@you", "ironbro": "@ironbro", "coachdave": "@coachdave",
             "newbro": "@newbro", "fitness": "Iron Bro-hood", "bbq": "Grill Masters",
             "cars": "Garage Gearheads", "fatherhood": "Dad Mode", "philosophy": "Stoic Bros"}
    items = ga.USERS + ga.GROUPS
    for i, ident in enumerate(items):
        c, r = i % cols, i // cols
        x = pad + c * (s + pad)
        y = top + r * (s + 60)
        svg = ga.avatar_svg(f"{ident['id']}|{date}", ident["label"], ident["kind"])
        body += _tile(x, y, s, svg, names[ident["id"]])
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
            f'viewBox="0 0 {w} {h}"><rect width="{w}" height="{h}" fill="#F4F6FF"/>'
            f'{body}</svg>')


def rotation_strip(identity: dict, dates: list[str]) -> str:
    s, pad, top = 200, 40, 110
    w = len(dates) * s + (len(dates) + 1) * pad
    h = top + s + 70
    body = (f'<text x="{pad}" y="56" font-family="DejaVu Sans" font-weight="bold" '
            f'font-size="40" fill="{INK}">Daily rotation — {identity["id"]}</text>'
            f'<text x="{pad}" y="90" font-family="DejaVu Sans" font-size="22" '
            f'fill="#33C78C">Same identity, regenerated each day</text>')
    for i, d in enumerate(dates):
        x = pad + i * (s + pad)
        svg = ga.avatar_svg(f"{identity['id']}|{d}", identity["label"], identity["kind"])
        body += _tile(x, top, s, svg, d)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
            f'viewBox="0 0 {w} {h}"><rect width="{w}" height="{h}" fill="#F4F6FF"/>'
            f'{body}</svg>')


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    today = dt.date.today()
    cairosvg.svg2png(bytestring=gallery(today.isoformat()).encode(),
                     write_to=os.path.join(OUT, "gallery.png"), scale=1.0)
    days = [(today + dt.timedelta(days=k)).isoformat() for k in range(4)]
    cairosvg.svg2png(bytestring=rotation_strip(ga.USERS[1], days).encode(),
                     write_to=os.path.join(OUT, "rotation.png"), scale=1.0)
    print("Previews ->", OUT)
