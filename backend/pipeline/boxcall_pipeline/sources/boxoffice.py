"""Fetch actual domestic opening-weekend grosses from free public sources.

Primary: Box Office Mojo's weekly chart page (no API key required).
Fallback: The Numbers' weekend chart.

Both are HTML pages that expose the data in a table. We parse the
relevant columns and return a dict of {title: gross_millions}.
"""
from __future__ import annotations

import re
from dataclasses import dataclass

import httpx

BOM_WEEKEND_URL = "https://www.boxofficemojo.com/weekend/"
THE_NUMBERS_URL = "https://www.the-numbers.com/box-office-chart-weekend"

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


def fetch_actuals(client: httpx.Client) -> list[OpeningResult]:
    """Try BOM first, fall back to The Numbers."""
    results = _fetch_bom(client)
    if results:
        return results
    return _fetch_the_numbers(client)


def _fetch_bom(client: httpx.Client) -> list[OpeningResult]:
    try:
        resp = client.get(
            BOM_WEEKEND_URL,
            headers={"User-Agent": USER_AGENT},
            timeout=15,
        )
        if resp.status_code != 200:
            return []
        return _parse_bom(resp.text)
    except (httpx.HTTPError, Exception):
        return []


def _parse_bom(html: str) -> list[OpeningResult]:
    """Extract opening weekends from BOM's weekend chart HTML.

    BOM uses a table with columns: Rank, Release, Gross, Change, Theaters, etc.
    We look for rows with "new" or week 1 indicators.
    """
    results: list[OpeningResult] = []

    rows = re.findall(
        r'<tr[^>]*>(.*?)</tr>',
        html,
        re.DOTALL | re.IGNORECASE,
    )

    for row in rows:
        cells = re.findall(r'<td[^>]*>(.*?)</td>', row, re.DOTALL | re.IGNORECASE)
        if len(cells) < 5:
            continue

        title_match = re.search(r'>([^<]+)<', cells[1])
        if not title_match:
            continue
        title = title_match.group(1).strip()
        if not title or title.lower() in ("release", "title"):
            continue

        gross_text = re.sub(r'[<][^>]+[>]', '', cells[2]).strip()
        gross = _parse_gross(gross_text)
        if gross is None or gross <= 0:
            continue

        is_opening = bool(
            re.search(r'\bnew\b|week\s*1\b|wk\s*1\b|opening', row, re.IGNORECASE)
        )

        results.append(OpeningResult(
            title=title,
            gross_millions=round(gross / 1_000_000, 2),
            is_opening_weekend=is_opening,
            source="boxofficemojo",
        ))

    return results


def _fetch_the_numbers(client: httpx.Client) -> list[OpeningResult]:
    try:
        resp = client.get(
            THE_NUMBERS_URL,
            headers={"User-Agent": USER_AGENT},
            timeout=15,
        )
        if resp.status_code != 200:
            return []
        return _parse_the_numbers(resp.text)
    except (httpx.HTTPError, Exception):
        return []


def _parse_the_numbers(html: str) -> list[OpeningResult]:
    results: list[OpeningResult] = []

    rows = re.findall(
        r'<tr[^>]*>(.*?)</tr>',
        html,
        re.DOTALL | re.IGNORECASE,
    )

    for row in rows:
        cells = re.findall(r'<td[^>]*>(.*?)</td>', row, re.DOTALL | re.IGNORECASE)
        if len(cells) < 4:
            continue

        title_match = re.search(r'>([^<]+)<', cells[1])
        if not title_match:
            continue
        title = title_match.group(1).strip()
        if not title or title.lower() in ("movie", "title"):
            continue

        gross_text = re.sub(r'[<][^>]+[>]', '', cells[2]).strip()
        gross = _parse_gross(gross_text)
        if gross is None or gross <= 0:
            continue

        is_opening = bool(
            re.search(r'\bnew\b|week\s*1\b|opening|n/a', row, re.IGNORECASE)
        )

        results.append(OpeningResult(
            title=title,
            gross_millions=round(gross / 1_000_000, 2),
            is_opening_weekend=is_opening,
            source="the-numbers",
        ))

    return results


def _parse_gross(text: str) -> float | None:
    cleaned = re.sub(r'[^0-9.]', '', text)
    if not cleaned:
        return None
    try:
        return float(cleaned)
    except ValueError:
        return None
