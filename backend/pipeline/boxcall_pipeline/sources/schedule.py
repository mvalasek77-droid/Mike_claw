"""Upcoming wide releases from public release calendars (no API key).

Primary: Box Office Mojo's release calendar. Fallback: The Numbers'
release schedule. Both list upcoming films under date headings with the
distributor alongside. Only films from studios that open wide get a
market — a single-screen limited release has no opening weekend worth
predicting.

Each film gets a cold-start opening estimate from its distributor's
typical wide opening, nudged by how much Wikipedia attention it has.
The app labels this as BoxCall's own estimate; trading moves it from
there.
"""
from __future__ import annotations

import datetime as dt
import html as html_lib
import re

import httpx

CALENDAR_SOURCES = [
    ("boxofficemojo", "https://www.boxofficemojo.com/calendar/"),
    ("the-numbers", "https://www.the-numbers.com/movies/release-schedule"),
]

USER_AGENT = (
    "BoxCallBot/1.0 (https://github.com/mvalasek77-droid/Mike_claw; "
    "movie box-office data for a play-money trading game)"
)

# Distributors that routinely open films wide, with a typical opening
# (US$ millions) used only as a starting point for the market.
WIDE_DISTRIBUTORS: list[tuple[tuple[str, ...], float]] = [
    (("walt disney", "disney", "buena vista", "pixar", "marvel"), 45.0),
    (("warner", "new line"), 28.0),
    (("universal", "dreamworks", "illumination"), 28.0),
    (("sony", "columbia", "screen gems", "tristar"), 22.0),
    (("paramount",), 22.0),
    (("20th century", "twentieth century"), 22.0),
    (("lionsgate", "summit"), 14.0),
    (("amazon", "mgm", "united artists"), 14.0),
    (("focus features", "searchlight"), 8.0),
    (("a24",), 9.0),
    (("neon",), 6.0),
    (("angel studios",), 8.0),
    (("blumhouse",), 12.0),
]

_MONTHS = ("january february march april may june july august september "
           "october november december").split()
_DATE = re.compile(
    r"\b(" + "|".join(m[:3] for m in _MONTHS) + r")[a-z]*\.?\s+(\d{1,2}),?\s+(\d{4})\b",
    re.IGNORECASE,
)
_BLOCK = re.compile(r"<tr[^>]*>.*?</tr>|<h[1-6][^>]*>.*?</h[1-6]>", re.DOTALL | re.IGNORECASE)
_CELL = re.compile(r"<t[hd][^>]*>(.*?)</t[hd]>", re.DOTALL | re.IGNORECASE)
_LINK = re.compile(r'<a[^>]+href="([^"]*(?:/release/|/title/|/movie/)[^"]*)"[^>]*>(.*?)</a>',
                   re.DOTALL | re.IGNORECASE)
_TAG = re.compile(r"<[^>]+>")


def _text(fragment: str) -> str:
    return re.sub(r"\s+", " ", html_lib.unescape(_TAG.sub(" ", fragment))).strip()


def _parse_date(text: str) -> dt.date | None:
    match = _DATE.search(text)
    if not match:
        return None
    month = next(i for i, m in enumerate(_MONTHS, 1) if m.startswith(match.group(1).lower()[:3]))
    try:
        return dt.date(int(match.group(3)), month, int(match.group(2)))
    except ValueError:
        return None


def distributor_baseline(text: str) -> tuple[str, float] | None:
    """The first wide-release distributor named in `text`, with its baseline."""
    lowered = text.lower()
    for names, baseline in WIDE_DISTRIBUTORS:
        for name in names:
            if re.search(r"\b" + re.escape(name) + r"\b", lowered):
                return name.title(), baseline
    return None


def slug(title: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")


def parse_calendar(page: str, *, source: str, today: dt.date, horizon_days: int) -> list[dict]:
    """Wide releases between today and the horizon, in page order.

    The page is walked top to bottom: a heading or row that carries a
    date and no film link sets the current date; a row with a film link
    is a release on that date (or on a date in its own first cell).
    """
    horizon = today + dt.timedelta(days=horizon_days)
    current: dt.date | None = None
    seen: set[str] = set()
    out: list[dict] = []

    for block in _BLOCK.findall(page):
        links = _LINK.findall(block)
        cells = [_text(c) for c in _CELL.findall(block)] or [_text(block)]
        if not links:
            found = _parse_date(" ".join(cells))
            if found:
                current = found
            continue

        own_date = _parse_date(cells[0]) if cells else None
        if own_date:
            current = own_date
        if current is None or not (today <= current <= horizon):
            continue

        title = _text(links[0][1])
        # Everything in the row except the title, so a film called
        # "Neon Nights" isn't mistaken for a Neon release.
        rest = " ".join(c for c in cells if c != title and title not in c)
        if "limited" in rest.lower() and "wide" not in rest.lower():
            continue
        studio = distributor_baseline(rest)
        if studio is None:
            continue

        title = re.sub(r"\s*\((?:\d{4}|re-?release)\)\s*$", "", title, flags=re.IGNORECASE).strip()
        key = slug(title)
        if not title or key in seen:
            continue
        seen.add(key)
        out.append({
            "id": f"sched_{key}",
            "title": title,
            "releaseDate": current.isoformat(),
            "distributor": studio[0],
            "baselineOpeningMillions": studio[1],
            "genre": None,
            "posterURL": None,
            "source": source,
        })
    return out


def fetch_upcoming(client: httpx.Client, *, today: dt.date | None = None,
                   horizon_days: int = 90) -> tuple[list[dict], str]:
    """(films, status line). Never raises; falls through sources in order."""
    today = today or dt.date.today()
    notes: list[str] = []
    for source, url in CALENDAR_SOURCES:
        try:
            response = client.get(url, headers={"User-Agent": USER_AGENT}, timeout=20)
        except Exception as error:  # noqa: BLE001 — any transport failure degrades
            notes.append(f"{source}: {type(error).__name__}")
            continue
        if response.status_code != 200:
            notes.append(f"{source}: HTTP {response.status_code}")
            continue
        films = parse_calendar(response.text, source=source, today=today, horizon_days=horizon_days)
        if films:
            return films, f"ok ({len(films)} wide releases from {source})"
        notes.append(f"{source}: no wide releases parsed")
        # Enough of the page's shape in the log to fix the parser from.
        sample = [_text(b)[:160] for b in _BLOCK.findall(response.text) if _LINK.search(b)][:15]
        print(f"[schedule] {source} parsed nothing; sample rows:", *sample, sep="\n  ")
    return [], "; ".join(notes) or "no sources"


def estimate_opening(baseline: float, wiki_views_7d: int | None) -> float:
    """Distributor baseline scaled by Wikipedia attention (bounded 0.5x–2.5x)."""
    if not wiki_views_7d:
        return round(baseline, 1)
    # ~40k views a week is a typical wide-release run-up.
    factor = min(2.5, max(0.5, (wiki_views_7d / 40_000) ** 0.5))
    return round(baseline * factor, 1)
