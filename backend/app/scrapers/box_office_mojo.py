"""Box Office Mojo weekend results scraper.

Every Monday morning BOM publishes the finalized Friday-Sunday
domestic three-day gross per movie at
https://www.boxofficemojo.com/weekend/ . The Monday settlement
job scrapes this and stamps each movie's actual opening.
"""
import httpx
from bs4 import BeautifulSoup
from datetime import date, timedelta
from ..models.schemas import SettlementRow
from datetime import datetime

URL = "https://www.boxofficemojo.com/weekend/"
UA = "Mozilla/5.0 (BoxCall/1.0 settlement bot)"


async def fetch_weekend_grosses() -> list[SettlementRow]:
    """Latest posted weekend. Returns [] on failure — settlement
    job re-tries later."""
    try:
        async with httpx.AsyncClient(timeout=15, headers={"User-Agent": UA}) as c:
            r = await c.get(URL)
            r.raise_for_status()
    except Exception:
        return []

    soup = BeautifulSoup(r.text, "html.parser")
    out: list[SettlementRow] = []
    for row in soup.select("table.mojo-body-table tr")[1:]:
        cols = row.find_all("td")
        if len(cols) < 4:
            continue
        title = cols[1].text.strip()
        gross_str = cols[3].text.strip().replace("$", "").replace(",", "")
        try:
            gross = float(gross_str) / 1_000_000
        except ValueError:
            continue
        out.append(SettlementRow(
            movieId=_slug(title),   # match by title-slug; the movie table maps to real id
            title=title,
            actualOpeningMillions=gross,
            reportedAt=datetime.utcnow(),
        ))
    return out


def _slug(title: str) -> str:
    return "".join(c.lower() if c.isalnum() else "-" for c in title).strip("-")
