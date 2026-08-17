#!/usr/bin/env python3
"""Render MetaBro app-screen mockups (Feed + Profile) in the Liquid-Glass style,
using the generative avatars. These are design mockups, not live simulator
screenshots."""
from __future__ import annotations
import base64
import datetime as dt
import os
import cairosvg
import generate_avatars as ga

BRAND = os.path.join(ga.ROOT, "MetaBro", "Branding")
OUT = os.path.join(BRAND, "mockups")
INK = "#0E1330"
SUB = "#6B7191"
ACCENT = "#5C8CFF"
GREEN = "#33C78C"
ORANGE = "#FF6B35"
DATE = dt.date.today().isoformat()

W, H = 430, 932  # iPhone-ish canvas


def avatar_uri(ident_id, label, kind):
    svg = ga.avatar_svg(f"{ident_id}|{DATE}", label, kind)
    png = cairosvg.svg2png(bytestring=svg.encode(), output_width=160, output_height=160)
    return "data:image/png;base64," + base64.b64encode(png).decode()


def glass(x, y, w, h, r=26, op=0.72):
    return (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" '
            f'fill="#FFFFFF" fill-opacity="{op}" stroke="#FFFFFF" stroke-opacity="0.9"/>'
            f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" '
            f'fill="none" stroke="#0E1330" stroke-opacity="0.05"/>')


def text(x, y, s, txt, fill=INK, weight="normal", anchor="start", spacing=0):
    return (f'<text x="{x}" y="{y}" font-family="DejaVu Sans, Helvetica, Arial" '
            f'font-size="{s}" font-weight="{weight}" fill="{fill}" '
            f'text-anchor="{anchor}" letter-spacing="{spacing}">{txt}</text>')


def chevron_up(cx, cy, fill):
    return f'<path d="M {cx-9} {cy+5} L {cx} {cy-5} L {cx+9} {cy+5}" fill="none" stroke="{fill}" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/>'


def chevron_down(cx, cy, fill):
    return f'<path d="M {cx-9} {cy-5} L {cx} {cy+5} L {cx+9} {cy-5}" fill="none" stroke="{fill}" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/>'


def frame(content):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#E8EEFF"/><stop offset="0.5" stop-color="#EFEAFB"/>
      <stop offset="1" stop-color="#E6F7F1"/>
    </linearGradient>
    <linearGradient id="ring" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="{ACCENT}"/><stop offset="1" stop-color="{GREEN}"/>
    </linearGradient>
  </defs>
  <rect width="{W}" height="{H}" rx="0" fill="url(#bg)"/>
  {content}
</svg>'''


def status_bar(title):
    s = text(W/2, 64, 26, title, weight="bold", anchor="middle")
    s += text(30, 30, 15, "9:41", weight="bold")
    s += text(W-34, 30, 14, "5G", anchor="end", fill=SUB)
    return s


def tab_bar(active=0):
    labels = ["Home", "Bro-hoods", "Post", "Messages", "You"]
    out = glass(14, H-92, W-28, 70, r=28, op=0.8)
    n = len(labels)
    for i, lb in enumerate(labels):
        cx = 14 + (W-28) * (i + 0.5) / n
        col = ACCENT if i == active else SUB
        out += f'<circle cx="{cx}" cy="{H-66}" r="5" fill="{col}"/>'
        out += text(cx, H-40, 12, lb, fill=col, anchor="middle",
                    weight="bold" if i == active else "normal")
    return out


def story(cx, cy, uri, name, seen=False):
    ring = "#C8CEE6" if seen else "url(#ring)"
    return (f'<circle cx="{cx}" cy="{cy}" r="32" fill="none" stroke="{ring}" stroke-width="3.5"/>'
            f'<clipPath id="s{cx}"><circle cx="{cx}" cy="{cy}" r="27"/></clipPath>'
            f'<image x="{cx-27}" y="{cy-27}" width="54" height="54" href="{uri}" clip-path="url(#s{cx})"/>'
            + text(cx, cy+50, 12, name, anchor="middle", fill=SUB))


def vote_pill(x, y, score):
    out = glass(x, y, 118, 40, r=20, op=0.85)
    out += chevron_up(x+26, y+20, ORANGE)
    out += text(x+59, y+26, 17, str(score), weight="bold", anchor="middle")
    out += chevron_down(x+92, y+20, SUB)
    return out


def reaction_pill(x, y):
    out = glass(x, y, 132, 40, r=20, op=0.85)
    out += f'<circle cx="{x+24}" cy="{y+20}" r="9" fill="{GREEN}"/>'
    out += text(x+40, y+26, 15, "Respect", weight="bold", fill=GREEN)
    # mini reaction stack + count
    for i, c in enumerate([GREEN, ORANGE, "#FFB703"]):
        out += f'<circle cx="{x+150+i*14}" cy="{y+20}" r="8" fill="{c}" stroke="#fff" stroke-width="2"/>'
    return out


def award_chips(x, y):
    out = ""
    for i, (lab, col) in enumerate([("C 1", "#FFB703"), ("B 2", ACCENT)]):
        out += glass(x + i*64, y, 56, 28, r=14, op=0.85)
        out += text(x + i*64 + 28, y+19, 13, lab, weight="bold", anchor="middle")
    return out


def feed():
    av_fit = avatar_uri("fitness", "IB", "group")
    av_iron = avatar_uri("ironbro", "M", "user")
    av_dave = avatar_uri("coachdave", "D", "user")
    av_you = avatar_uri("you", "Y", "user")
    c = status_bar("MetaBro")
    # stories
    c += glass(14, 84, W-28, 120, r=26, op=0.6)
    c += story(54, 130, av_you, "Your story")
    c += story(132, 130, av_iron, "Marcus")
    c += story(210, 130, av_dave, "Dave")
    c += story(288, 130, av_fit, "Iron B.", seen=True)

    # community post card
    cy = 224
    c += glass(14, cy, W-28, 250)
    c += f'<image x="30" y="{cy+18}" width="44" height="44" href="{av_fit}"/>'
    c += text(86, cy+36, 16, "Iron Bro-hood", weight="bold")
    c += text(86, cy+56, 13, "@ironbro · 1h", fill=SUB)
    c += glass(W-118, cy+18, 86, 30, r=15, op=0.85)
    c += text(W-75, cy+38, 12, "Bro-hood", anchor="middle", weight="bold", fill=ACCENT)
    c += text(30, cy+96, 17, "PSA: warm up your rotator cuffs, bros", weight="bold")
    c += text(30, cy+124, 14, "Saved my bench after years of nagging pain.", fill="#2A2F4A")
    c += text(30, cy+144, 14, "Here's the routine.", fill="#2A2F4A")
    c += award_chips(30, cy+162)
    c += vote_pill(30, cy+200, 1240)
    c += text(170, cy+225, 14, "86 comments", fill=SUB)

    # social post card
    sy = 492
    c += glass(14, sy, W-28, 196)
    c += f'<clipPath id="pa"><circle cx="52" cy="{sy+40}" r="22"/></clipPath>'
    c += f'<image x="30" y="{sy+18}" width="44" height="44" href="{av_iron}" clip-path="url(#pa)"/>'
    c += text(86, sy+36, 16, "Marcus", weight="bold")
    c += text(86, sy+56, 13, "2h", fill=SUB)
    c += text(30, sy+96, 14, "Pickup basketball this Saturday at", fill="#2A2F4A")
    c += text(30, sy+116, 14, "Riverside. Who's in?", fill="#2A2F4A")
    c += reaction_pill(30, sy+140)
    c += text(W-150, sy+165, 14, "12 comments", fill=SUB)

    c += tab_bar(0)
    return frame(c)


def profile():
    av_you = avatar_uri("you", "Y", "user")
    av_fit = avatar_uri("fitness", "IB", "group")
    av_dad = avatar_uri("fatherhood", "DM", "group")
    c = status_bar("You")
    # header card
    hy = 96
    c += glass(14, hy, W-28, 250)
    c += f'<image x="{W/2-46}" y="{hy+26}" width="92" height="92" href="{av_you}"/>'
    c += text(W/2, hy+148, 24, "You", weight="bold", anchor="middle")
    c += text(W/2, hy+172, 14, "@you", fill=SUB, anchor="middle")
    stats = [("1.9k", "Bro Cred"), ("1.3k", "Post"), ("642", "Comment")]
    for i, (v, l) in enumerate(stats):
        sx = W/2 + (i-1)*110
        c += text(sx, hy+212, 22, v, weight="bold", anchor="middle")
        c += text(sx, hy+234, 13, l, fill=SUB, anchor="middle")
    # bro-hoods strip
    by = 366
    c += text(30, by, 17, "Your Bro-hoods", weight="bold")
    c += glass(14, by+14, W-28, 70, r=22, op=0.6)
    c += f'<image x="30" y="{by+26}" width="46" height="46" href="{av_fit}"/>'
    c += text(86, by+47, 14, "Iron Bro-hood", weight="bold")
    c += text(86, by+65, 12, "182k bros", fill=SUB)
    c += f'<image x="244" y="{by+26}" width="46" height="46" href="{av_dad}"/>'
    c += text(300, by+47, 14, "Dad Mode", weight="bold")
    c += text(300, by+65, 12, "58.7k bros", fill=SUB)
    # your posts
    py = 470
    c += text(30, py, 17, "Your posts", weight="bold")
    c += glass(14, py+14, W-28, 150)
    c += f'<image x="30" y="{py+30}" width="40" height="40" href="{av_fit}"/>'
    c += text(82, py+46, 14, "Iron Bro-hood", weight="bold")
    c += text(82, py+64, 12, "@you · 3h", fill=SUB)
    c += text(30, py+98, 15, "First 1000lb total — thanks for the", weight="bold")
    c += text(30, py+118, 15, "form checks, bros", weight="bold")
    c += vote_pill(30, py+134, 318)
    c += tab_bar(4)
    return frame(c)


def render(svg, name):
    cairosvg.svg2png(bytestring=svg.encode(), write_to=os.path.join(OUT, name), scale=2.0)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    render(feed(), "feed.png")
    render(profile(), "profile.png")
    print("Mockups ->", OUT)
