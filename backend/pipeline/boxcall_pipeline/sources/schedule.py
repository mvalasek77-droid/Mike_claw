"""Upcoming wide releases from public release calendars (no API key).

Box Office Mojo's release calendar, read in four-week pages out to the
horizon, merged with The Numbers' release schedule. Both list upcoming
films under date headings with the distributor alongside. Only films
from studios that open wide get a market — a single-screen limited release has no opening weekend worth
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
    r"\b(" + "|".join(m[:3] for m in _MONTHS) + r")[a-z]*\.?\s+(\d{1,2})\b(?:,?\s+(\d{4}))?",
    re.IGNORECASE,
)
# Special screenings and re-issues don't have a real opening weekend.
_NOT_A_NEW_RELEASE = re.compile(r"re-?release|anniversary|special engagement|fathom", re.IGNORECASE)
# Placeholder listings ("Untitled Disney Film") have nothing to trade on.
_PLACEHOLDER = re.compile(r"^untitled\b", re.IGNORECASE)
# Imprints that share a big studio's name but release small.
_SMALL_IMPRINTS = ("lionsgate premiere",)
_BLOCK = re.compile(r"<tr[^>]*>.*?</tr>|<h[1-6][^>]*>.*?</h[1-6]>", re.DOTALL | re.IGNORECASE)
_CELL = re.compile(r"<t[hd][^>]*>(.*?)</t[hd]>", re.DOTALL | re.IGNORECASE)
_LINK = re.compile(r'<a[^>]+href="([^"]*(?:/release/|/title/|/movie/)[^"]*)"[^>]*>(.*?)</a>',
                   re.DOTALL | re.IGNORECASE)
_TAG = re.compile(r"<[^>]+>")


def _text(fragment: str) -> str:
    return re.sub(r"\s+", " ", html_lib.unescape(_TAG.sub(" ", fragment))).strip()


def _parse_date(text: str, today: dt.date, floor: dt.date | None = None) -> dt.date | None:
    """A month-day date, with or without a year.

    Calendars often print "September 30" alone; the year is whichever
    puts the date closest ahead of today (a date more than two months
    past means next year). Calendars run in date order, so a year-less
    date that falls well before `floor` (the last date seen above it)
    belongs to a later year: "December 17" after "January 8, 2027" is
    December 2027, not a film opening this winter.
    """
    match = _DATE.search(text)
    if not match:
        return None
    month = next(i for i, m in enumerate(_MONTHS, 1) if m.startswith(match.group(1).lower()[:3]))
    try:
        if match.group(3):
            return dt.date(int(match.group(3)), month, int(match.group(2)))
        candidate = dt.date(today.year, month, int(match.group(2)))
    except ValueError:
        return None
    if candidate < today - dt.timedelta(days=60):
        candidate = candidate.replace(year=today.year + 1)
    while floor and candidate < floor - dt.timedelta(days=7):
        try:
            candidate = candidate.replace(year=candidate.year + 1)
        except ValueError:  # February 29
            return None
    return candidate


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
    latest: dt.date | None = None  # the page runs in date order
    seen: set[str] = set()
    out: list[dict] = []

    for block in _BLOCK.findall(page):
        cells = [_text(c) for c in _CELL.findall(block)] or [_text(block)]
        # The first link with text is the title; a poster link has none.
        titles = [t for t in (_text(label) for _, label in _LINK.findall(block))
                  if t and "company info" not in t.lower()]
        if not titles:
            found = _parse_date(" ".join(cells), today, latest)
            if found:
                current = found
                latest = max(found, latest or found)
            continue
        title = titles[0]

        # A leading cell that isn't the title is the row's date: a real
        # date, blank (same date as above), or vague ("Summer 2026",
        # "3rd quarter") — which must not inherit the previous date.
        lead = cells[0] if cells else ""
        if lead and title not in lead:
            current = _parse_date(lead, today, latest)
            if current:
                latest = max(current, latest or current)
        if current is None or not (today <= current <= horizon):
            continue

        # Everything in the row except the title, so a film called
        # "Neon Nights" isn't mistaken for a Neon release.
        rest = " ".join(cells).replace(title, " ", 1)
        lowered = rest.lower()
        if _NOT_A_NEW_RELEASE.search(rest) or any(i in lowered for i in _SMALL_IMPRINTS):
            continue
        if "limited" in lowered and "wide" not in lowered:
            continue
        studio = distributor_baseline(rest)
        if studio is None:
            continue

        title = re.sub(r"\s*\((?:\d{4}|re-?release)\)\s*$", "", title, flags=re.IGNORECASE).strip()
        key = slug(title)
        if not title or key in seen or _PLACEHOLDER.search(title):
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


def _same_film_listed(film: dict, listed) -> bool:
    """The sites name some films differently ("Ramayana" / "Ramayana Part 1"):
    same date, same studio, and one title extends the other."""
    key = slug(film["title"])
    for other in listed:
        if other["releaseDate"] != film["releaseDate"] or other["distributor"] != film["distributor"]:
            continue
        other_key = slug(other["title"])
        if key.startswith(other_key + "-") or other_key.startswith(key + "-"):
            return True
    return False


# Box Office Mojo is read in four-week pages this far ahead; The Numbers'
# single page covers the rest of the year.
BOM_DAYS = 84


def calendar_pages(today: dt.date, horizon_days: int) -> list[tuple[str, str]]:
    """Every page to read, in priority order.

    Box Office Mojo's calendar shows about four weeks from the date in its
    URL, so it is read in four-week steps. The Numbers lists the whole
    schedule on one page and fills in anything BOM lacks.
    """
    pages = [CALENDAR_SOURCES[0]]
    for offset in range(28, min(horizon_days, BOM_DAYS) + 1, 28):
        day = today + dt.timedelta(days=offset)
        pages.append(("boxofficemojo", f"{CALENDAR_SOURCES[0][1]}{day.isoformat()}/"))
    pages.extend(CALENDAR_SOURCES[1:])
    return pages


def fetch_upcoming(client: httpx.Client, *, today: dt.date | None = None,
                   horizon_days: int = 365) -> tuple[list[dict], str]:
    """(films, status line). Never raises.

    Reads every calendar page and merges them: a film listed by more than
    one page keeps its first (Box Office Mojo) entry, so one site's gaps
    are covered by the other and a single failing page costs little.
    """
    today = today or dt.date.today()
    films: dict[str, dict] = {}
    read: dict[str, int] = {}
    notes: list[str] = []
    for source, url in calendar_pages(today, horizon_days):
        try:
            response = client.get(url, headers={"User-Agent": USER_AGENT}, timeout=20)
        except Exception as error:  # noqa: BLE001 — any transport failure degrades
            notes.append(f"{source}: {type(error).__name__}")
            continue
        if response.status_code != 200:
            notes.append(f"{source}: HTTP {response.status_code}")
            continue
        parsed = parse_calendar(response.text, source=source, today=today, horizon_days=horizon_days)
        read[source] = read.get(source, 0) + 1
        if not parsed:
            # Enough of the page's shape in the log to fix the parser from.
            sample = [_text(b)[:160] for b in _BLOCK.findall(response.text) if _LINK.search(b)][:15]
            print(f"[schedule] {url} parsed nothing; sample rows:", *sample, sep="\n  ")
        for film in parsed:
            if film["id"] not in films and not _same_film_listed(film, films.values()):
                films[film["id"]] = film

    merged = sorted(films.values(), key=lambda f: f["releaseDate"])
    if not merged:
        return [], "; ".join(notes) or "no wide releases parsed"
    pages = ", ".join(f"{s} {n} page{'s' if n > 1 else ''}" for s, n in read.items())
    status = f"ok ({len(merged)} wide releases from {pages})"
    if notes:
        status += "; " + "; ".join(notes)
    return merged, status


# Sequels and franchise entries open well above a studio's typical film.
_SEQUEL = re.compile(r"\b(?:[2-9]|ii|iii|iv|vi|part (?:two|three|four|[2-9]|ii|iii|iv))\b"
                     r"|\b(?:two|three|returns|reloaded|resurrection)\s*$",
                     re.IGNORECASE)


def franchise_factor(title: str) -> float:
    """1.6x for a numbered sequel, 1.3x for a franchise subtitle, else 1."""
    if _SEQUEL.search(title):
        return 1.6
    prefix, colon, _ = title.partition(":")
    # "The Hunger Games: Sunrise on the Reaping", not "Ali G: Who Iz I?".
    if colon and len(prefix.strip()) >= 8:
        return 1.3
    return 1.0


def estimate_opening(baseline: float, wiki_views_7d: int | None, title: str = "") -> float:
    """Distributor baseline, lifted for franchise entries, scaled by
    Wikipedia attention (bounded 0.5x–2.5x)."""
    base = baseline * franchise_factor(title)
    if not wiki_views_7d:
        return round(base, 1)
    # ~40k views a week is a typical wide-release run-up.
    factor = min(2.5, max(0.5, (wiki_views_7d / 40_000) ** 0.5))
    return round(base * factor, 1)
