#!/usr/bin/env python3
"""MetaBro daily AI content flow.

Generates a fresh feed of posts every day, seeded on the date so the content
rotates automatically (run on the same cron as the avatars). Output matches the
app's wire format (`FeedPageDTO` / `PostDTO`), with each author/community
carrying its daily avatar URL — so `LiveFeedService` can serve it directly.

  python generate_content.py [--date YYYY-MM-DD] [--count 6]
"""
from __future__ import annotations
import argparse
import datetime as dt
import hashlib
import json
import os
import uuid

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "MetaBro", "Branding", "content")

AVATAR_BASE = ("https://raw.githubusercontent.com/mvalasek77-droid/Mike_claw/"
               "claude/metabro-facebook-reddit-hybrid-it80pk/MetaBro/Branding/avatars/")

USERS = [
    {"handle": "@ironbro", "name": "Marcus", "bro_cred": 4820},
    {"handle": "@coachdave", "name": "Dave", "bro_cred": 9300},
    {"handle": "@newbro", "name": "Sam", "bro_cred": 40},
    {"handle": "@you", "name": "You", "bro_cred": 1280},
]
COMMUNITIES = [
    {"name": "Iron Bro-hood", "slug": "fitness", "members": 182000},
    {"name": "Grill Masters", "slug": "bbq", "members": 96400},
    {"name": "Garage Gearheads", "slug": "cars", "members": 141200},
    {"name": "Dad Mode", "slug": "fatherhood", "members": 58700},
    {"name": "Stoic Bros", "slug": "philosophy", "members": 22300},
]

# Per-community content pools (title, body). Picked deterministically by date.
POOLS = {
    "fitness": [
        ("PSA: warm up your rotator cuffs, bros", "Saved my bench after years of nagging pain. Here's the routine."),
        ("Hit a new deadlift PR today", "405 for a clean triple. Sleep and protein, that's the whole secret."),
        ("Mobility > maxing out", "Ten minutes of hips and shoulders before every session. Game changer."),
        ("Cutting without losing strength", "Higher protein, slower deficit, keep the heavy sets. Worked for me."),
    ],
    "bbq": [
        ("Low and slow brisket — 14 hours", "Wrapped at 165, pulled at 203. Bark was unreal. AMA."),
        ("Reverse sear is the only way", "Smoke to 120, rest, then blast it. Edge to edge pink every time."),
        ("Best cheap smoker under $300?", "Looking to upgrade from the kettle. What are you bros running?"),
    ],
    "cars": [
        ("Finally finished the brake job", "New rotors, pads, fresh fluid. Pedal feel is night and day."),
        ("Manual or auto for a first project car?", "Want something I can wrench on cheaply. Thoughts?"),
        ("Detailing Sunday", "Clay bar, two-stage polish, ceramic. Paint looks wet. Worth it."),
    ],
    "fatherhood": [
        ("First steps today", "Caught it on video. Did not expect to tear up. Worth every sleepless night."),
        ("Tips for a 5am toddler?", "He's up before the sun. How do you bros keep your sanity?"),
        ("Built a treehouse this weekend", "Kid 'helped'. Took twice as long. Best two days of the year."),
    ],
    "philosophy": [
        ("Memento mori — keeps me grounded", "Read a page of Marcus Aurelius every morning. Recommend it."),
        ("The obstacle is the way", "Reframed a brutal week as training. Different game entirely."),
        ("On discipline vs motivation", "Motivation gets you started. Discipline is what shows up at 5am."),
    ],
}
SOCIAL = [
    ("Pickup basketball this Saturday at Riverside. Who's in?", ["strong", "respect", "lol"]),
    ("Grilling at my place Sunday — bring a chair and a story.", ["respect", "strong"]),
    ("Anyone up for a sunrise hike this weekend?", ["strong", "like"]),
    ("Just hit a year sober. Grateful for this crew.", ["respect", "strong", "like"]),
]


def _stream(seed: str):
    i = 0
    while True:
        for byte in hashlib.sha256(f"{seed}:{i}".encode()).digest():
            yield byte
        i += 1


def _det_uuid(seed: str) -> str:
    return str(uuid.UUID(hashlib.md5(seed.encode()).hexdigest()))


def _user_dto(u: dict) -> dict:
    return {"id": _det_uuid("user|" + u["handle"]), "handle": u["handle"],
            "display_name": u["name"], "avatar_url": AVATAR_BASE + u["handle"].lstrip("@") + ".png",
            "bro_cred": u["bro_cred"]}


def _community_dto(c: dict) -> dict:
    return {"id": _det_uuid("comm|" + c["slug"]), "name": c["name"], "slug": c["slug"],
            "member_count": c["members"], "icon_url": AVATAR_BASE + c["slug"] + ".png",
            "is_joined": True}


def build(date: str, count: int) -> dict:
    g = _stream(date)
    posts = []
    now = dt.datetime.fromisoformat(date + "T12:00:00+00:00")
    for n in range(count):
        social = (next(g) % 3 == 0)
        author = USERS[next(g) % len(USERS)]
        created = (now - dt.timedelta(minutes=37 * n + next(g))).isoformat()
        if social:
            body, reacts = SOCIAL[next(g) % len(SOCIAL)]
            reactions = [{"kind": k, "count": 3 + next(g) % 40} for k in reacts]
            post = {"community": None, "title": None, "body": body,
                    "score": 10 + next(g) % 90, "reactions": reactions,
                    "my_reaction": None, "awards": []}
        else:
            comm = COMMUNITIES[next(g) % len(COMMUNITIES)]
            title, bdy = POOLS[comm["slug"]][next(g) % len(POOLS[comm["slug"]])]
            awards = []
            if next(g) % 2 == 0:
                awards = [{"kind": "champ", "count": 1 + next(g) % 3}]
            post = {"community": _community_dto(comm), "title": title, "body": bdy,
                    "score": 50 + next(g) % 1500, "reactions": [],
                    "my_reaction": None, "awards": awards}
        post.update({"id": _det_uuid(f"{date}|post|{n}"), "author": _user_dto(author),
                     "image_url": None, "comment_count": next(g) % 120,
                     "created_at": created, "my_vote": 0})
        posts.append(post)
    return {"generated_for": date, "posts": posts, "next_cursor": None}


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--date", default=dt.date.today().isoformat())
    ap.add_argument("--count", type=int, default=6)
    args = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    page = build(args.date, args.count)
    with open(os.path.join(OUT, "feed-latest.json"), "w") as f:
        json.dump(page, f, indent=2)
    with open(os.path.join(OUT, f"feed-{args.date}.json"), "w") as f:
        json.dump(page, f, indent=2)
    print(f"Generated {len(page['posts'])} posts for {args.date} -> {OUT}")
