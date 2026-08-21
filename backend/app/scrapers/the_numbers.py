"""The Numbers upcoming release calendar scraper.

https://www.the-numbers.com/movies/schedule maintains a wide-vs-
limited flagged weekend calendar. We only surface wide releases
here.
"""
import httpx
from bs4 import BeautifulSoup
from datetime import date, timedelta
from ..models.schemas import Movie

URL = "https://www.the-numbers.com/movies/schedule"
UA = "Mozilla/5.0 (BoxCall/1.0 aggregation bot)"


async def fetch(window_days: int) -> list[Movie]:
    try:
        async with httpx.AsyncClient(timeout=15, headers={"User-Agent": UA}) as c:
            r = await c.get(URL)
            r.raise_for_status()
    except Exception:
        return []

    soup = BeautifulSoup(r.text, "html.parser")
    horizon = date.today() + timedelta(days=window_days)
    out: list[Movie] = []
    # Each release row has date + title + distributor + release type columns.
    for row in soup.select("table.mainTable tr"):
        cols = row.find_all("td")
        if len(cols) < 4:
            continue
        rel = _parse_date(cols[0].text.strip())
        if rel is None or rel > horizon:
            continue
        release_type = cols[3].text.strip().lower()
        if "wide" not in release_type:
            continue
        title = cols[1].text.strip()
        studio = cols[2].text.strip()
        if not title:
            continue
        out.append(Movie(
            id=f"tn_{_slug(title)}_{rel.isoformat()}",
            title=title,
            studio=studio or "—",
            releaseDate=rel.isoformat(),
            posterEmoji="🎬",
            tagline="",
            consensusOpeningMillions=0,
            impliedVolPct=45,
            genre="—",
        ))
    return out


def _parse_date(s: str) -> date | None:
    from datetime import datetime
    for fmt in ("%b %d, %Y", "%B %d, %Y", "%Y-%m-%d"):
        try:
            return datetime.strptime(s, fmt).date()
        except ValueError:
            continue
    return None


def _slug(title: str) -> str:
    return "".join(c.lower() if c.isalnum() else "-" for c in title).strip("-")
