"""Opening-weekend grosses from free public weekend charts.

Primary: Box Office Mojo's chart for a specific weekend
(`/weekend/2026W39/`), which carries the studios' Sunday estimates and is
replaced by actuals on Monday. Fallback: The Numbers' weekend chart for
the same Friday.

Both pages are HTML tables. Columns are found by their header text rather
than their position, so a reordered or extra column doesn't silently shift
titles and grosses. Only rows in a film's first weekend count as an
opening — a second weekend must never be mistaken for one.
"""
from __future__ import annotations

import datetime as dt
import html as html_lib
import re
from dataclasses import dataclass

import httpx

BOM_WEEKEND_URL = "https://www.boxofficemojo.com/weekend/{year}W{week:02d}/"
THE_NUMBERS_URL = "https://www.the-numbers.com/box-office-chart/weekend/{year}/{month:02d}/{day:02d}"

USER_AGENT = (
    "BoxCallBot/1.0 (https://github.com/mvalasek77-droid/Mike_claw; "
    "movie box-office data for a play-money trading game)"
)


@dataclass
class OpeningResult:
    title: str
    gross_millions: float
    is_opening_weekend: bool
    source: str
    weekend_of: str = ""        # ISO date of the Friday
    is_estimate: bool = False


# --------------------------------------------------------------------
# Weekend arithmetic
# --------------------------------------------------------------------

def weekend_friday(today: dt.date) -> dt.date:
    """The Friday that starts the most recent weekend on or before `today`."""
    return today - dt.timedelta(days=(today.weekday() - 4) % 7)


def weekends_to_check(today: dt.date) -> list[dt.date]:
    """This weekend's Friday (once Sunday estimates can exist) and the one before.

    Friday and Saturday have no weekend chart yet, so the latest weekend
    worth asking about starts the previous Friday. The prior weekend is
    re-read so Monday's corrections and any missed run are still caught.
    """
    friday = weekend_friday(today)
    if today.weekday() in (4, 5):        # Fri, Sat
        friday -= dt.timedelta(days=7)
    return [friday, friday - dt.timedelta(days=7)]


# --------------------------------------------------------------------
# Fetching
# --------------------------------------------------------------------

def fetch_actuals(client: httpx.Client, *, today: dt.date | None = None) -> list[OpeningResult]:
    """Opening weekends from the latest two weekends. Never raises."""
    today = today or dt.date.today()
    results: list[OpeningResult] = []
    for friday in weekends_to_check(today):
        chart = _fetch_bom(client, friday) or _fetch_the_numbers(client, friday)
        results.extend(chart)
    return results


def _get(client: httpx.Client, url: str) -> str | None:
    try:
        response = client.get(url, headers={"User-Agent": USER_AGENT}, timeout=20)
    except Exception:
        return None
    if response.status_code != 200:
        return None
    return response.text


def _fetch_bom(client: httpx.Client, friday: dt.date) -> list[OpeningResult]:
    year, week, _ = friday.isocalendar()
    page = _get(client, BOM_WEEKEND_URL.format(year=year, week=week))
    return parse_chart(page, source="boxofficemojo", friday=friday) if page else []


def _fetch_the_numbers(client: httpx.Client, friday: dt.date) -> list[OpeningResult]:
    page = _get(client, THE_NUMBERS_URL.format(year=friday.year, month=friday.month, day=friday.day))
    return parse_chart(page, source="the-numbers", friday=friday) if page else []


# --------------------------------------------------------------------
# Parsing
# --------------------------------------------------------------------

_ROW = re.compile(r"<tr[^>]*>(.*?)</tr>", re.DOTALL | re.IGNORECASE)
_CELL = re.compile(r"<t([hd])[^>]*>(.*?)</t[hd]>", re.DOTALL | re.IGNORECASE)
_TAG = re.compile(r"<[^>]+>")


def _text(cell_html: str) -> str:
    return re.sub(r"\s+", " ", html_lib.unescape(_TAG.sub(" ", cell_html))).strip()


def _find(headers: list[str], *names: str, exclude: tuple[str, ...] = ()) -> int | None:
    for i, header in enumerate(headers):
        h = header.lower()
        if any(n in h for n in names) and not any(x in h for x in exclude):
            return i
    return None


def parse_chart(page: str, *, source: str, friday: dt.date | None = None) -> list[OpeningResult]:
    """Rows of one weekend chart, located by header names."""
    rows = [[(kind.lower(), _text(body)) for kind, body in _CELL.findall(row)]
            for row in _ROW.findall(page)]

    header_index = next((i for i, cells in enumerate(rows)
                         if cells and any(kind == "h" for kind, _ in cells)), None)
    if header_index is None:
        return []
    headers = [text for _, text in rows[header_index]]

    title_col = _find(headers, "release", "movie", "title")
    gross_col = _find(headers, "gross", exclude=("total", "to date"))
    days_col = _find(headers, "days")
    weeks_col = _find(headers, "weeks", "week", exclude=("change", "new this"))
    estimate_col = _find(headers, "estimated")
    if title_col is None or gross_col is None:
        return []

    weekend_of = friday.isoformat() if friday else ""
    results: list[OpeningResult] = []
    for cells in rows[header_index + 1:]:
        values = [text for _, text in cells]
        if len(values) <= max(title_col, gross_col):
            continue
        title = values[title_col]
        gross = _parse_gross(values[gross_col])
        if not title or gross is None or gross <= 0:
            continue

        def column(index: int | None) -> int | None:
            return _parse_int(values[index]) if index is not None and index < len(values) else None

        weeks, days = column(weeks_col), column(days_col)
        if weeks is not None:
            is_opening = weeks == 1
        elif days is not None:
            is_opening = days <= 5           # Fri–Sun, or a Wed/Thu holiday opening
        else:
            is_opening = bool(re.search(r"\bnew\b", " ".join(values).lower()))

        is_estimate = False
        if estimate_col is not None and estimate_col < len(values):
            is_estimate = values[estimate_col].strip().lower() in ("true", "yes", "estimated", "e")

        results.append(OpeningResult(
            title=title,
            gross_millions=round(gross / 1_000_000, 2),
            is_opening_weekend=is_opening,
            source=source,
            weekend_of=weekend_of,
            is_estimate=is_estimate,
        ))
    return results


def _parse_gross(text: str) -> float | None:
    cleaned = re.sub(r"[^0-9.]", "", text)
    if not cleaned:
        return None
    try:
        return float(cleaned)
    except ValueError:
        return None


def _parse_int(text: str) -> int | None:
    match = re.search(r"\d+", text or "")
    return int(match.group()) if match else None
