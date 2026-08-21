"""Aggregate upcoming-releases from IMDb Coming Soon, The Numbers
release calendar, and Deadline. Returns a deduped list matching the
iOS Movie schema."""
from fastapi import APIRouter, Query
from ..models.schemas import Movie
from ..scrapers import imdb_coming_soon, the_numbers, deadline

router = APIRouter(prefix="/upcoming", tags=["upcoming"])


@router.get("", response_model=list[Movie])
async def upcoming(window_days: int = Query(60, ge=1, le=180)):
    """Merge upcoming releases from every scraper we've enabled."""
    batches = [
        await imdb_coming_soon.fetch(window_days),
        await the_numbers.fetch(window_days),
        await deadline.fetch(window_days),
    ]
    seen: dict[str, Movie] = {}
    for batch in batches:
        for m in batch:
            key = f"{m.title.lower()}|{m.releaseDate}"
            seen[key] = m   # later source wins
    return sorted(seen.values(), key=lambda m: m.releaseDate)
