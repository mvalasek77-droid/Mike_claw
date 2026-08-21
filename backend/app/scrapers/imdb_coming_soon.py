"""IMDb Coming Soon scraper.

IMDb has no free API for coming-soon calendars, so we scrape
https://www.imdb.com/calendar/?region=US&type=MOVIE

Kept intentionally isolated so we can swap for an official feed if
one appears, or replace with a paid dataset (Cinemagoer, TMDB).
"""
import httpx
from bs4 import BeautifulSoup
from datetime import date, timedelta
from ..models.schemas import Movie

URL = "https://www.imdb.com/calendar/"
UA = "Mozilla/5.0 (BoxCall/1.0 aggregation bot; +https://boxcall.com/bot)"


async def fetch(window_days: int) -> list[Movie]:
    """Return upcoming movies within the window. Empty list on failure."""
    try:
        async with httpx.AsyncClient(timeout=15, headers={"User-Agent": UA}) as c:
            r = await c.get(URL, params={"region": "US", "type": "MOVIE"})
            r.raise_for_status()
    except Exception:
        return []

    soup = BeautifulSoup(r.text, "html.parser")
    horizon = date.today() + timedelta(days=window_days)

    out: list[Movie] = []
    # IMDb ships this as a list of <li> under date-grouped articles.
    for article in soup.select("article.sc-9c5f5efd-0"):
        date_hdr = article.select_one("h3")
        if not date_hdr:
            continue
        release = _parse_imdb_date(date_hdr.text.strip())
        if release is None or release > horizon:
            continue
        for li in article.select("li"):
            a = li.select_one("a")
            if not a:
                continue
            title = a.text.strip()
            if not title:
                continue
            out.append(Movie(
                id=f"imdb_{_slug(title)}_{release.isoformat()}",
                title=title,
                studio="—",
                releaseDate=release.isoformat(),
                posterEmoji="🎞️",
                posterURL=None,
                tagline="",
                consensusOpeningMillions=0,   # tracking router fills this
                impliedVolPct=50,
                genre="—",
            ))
    return out


def _parse_imdb_date(s: str) -> date | None:
    """IMDb prints headers like 'Friday, April 24, 2026'."""
    from datetime import datetime
    try:
        return datetime.strptime(s.strip(), "%A, %B %d, %Y").date()
    except ValueError:
        return None


def _slug(title: str) -> str:
    return "".join(c.lower() if c.isalnum() else "-" for c in title).strip("-")
