"""Build the static BoxCall API.

Runs in GitHub Actions, writes plain JSON, and that JSON is served by
GitHub Pages. There is no server, no database, and no bill: Actions is
unmetered on public repositories and Pages serves from a CDN.

Every source is degradable. A title that Bluesky has never heard of, a
Wikipedia article that cannot be resolved, a YouTube key that is absent
— each drops out and leaves its fields null. Null is load-bearing: the
iOS client renormalizes around whatever actually reported, so an absent
source contributes nothing rather than a fabricated zero.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import pathlib
import sys
import time

import httpx

from . import sentiment
from .sources import bluesky, tmdb, wikipedia, youtube

SCHEMA_VERSION = 1
# Bluesky asks public clients to be gentle; a short pause between titles
# keeps us far below any plausible per-IP ceiling.
POLITE_DELAY_SECONDS = 0.4


def iso(moment: dt.datetime) -> str:
    return moment.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def load_seed(path: pathlib.Path) -> list[dict]:
    """Fallback slate used when TMDB is unconfigured or unreachable."""
    if not path.exists():
        return []
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return []


def load_trailer_cache(path: pathlib.Path) -> dict[str, str]:
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text())
        return data if isinstance(data, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def save_trailer_cache(path: pathlib.Path, cache: dict[str, str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(cache, indent=2, sort_keys=True))


def collect_movie_signal(
    client: httpx.Client,
    movie: dict,
    *,
    now: dt.datetime,
    trailer_cache: dict[str, str],
    youtube_key: str,
    search_budget: list[int],
) -> dict:
    """Gather every free signal we can for one film."""
    title = movie["title"]
    release_year = int(movie["releaseDate"][:4]) if movie.get("releaseDate") else None

    # --- Bluesky: mention volume + sentiment -------------------------
    posts = bluesky.search_posts(client, title, limit=100, now=now)
    summary = sentiment.summarize(posts)

    # --- Wikipedia: attention velocity -------------------------------
    article = movie.get("wikipediaArticle")
    if not article:
        article = wikipedia.resolve_article(client, title, release_year)
        if article:
            movie["wikipediaArticle"] = article
    wiki_views, wiki_velocity = (0, 1.0)
    if article:
        wiki_views, wiki_velocity = wikipedia.fetch_velocity(client, article, today=now.date())

    # --- YouTube: trailer reach --------------------------------------
    video_id = trailer_cache.get(movie["id"])
    if youtube_key and not video_id and search_budget[0] > 0:
        video_id = youtube.resolve_trailer_id(client, youtube_key, title)
        search_budget[0] -= 1
        if video_id:
            trailer_cache[movie["id"]] = video_id

    return {
        "id": movie["id"],
        "title": title,
        "capturedAt": iso(now),
        # Bluesky stands in for the old X signal. Null when the search
        # returned nothing at all, so the client can tell "no data" from
        # "nobody is talking about it".
        "socialMentions24h": summary.sample_size or None,
        "socialSentiment": round(summary.score, 4) if not summary.is_empty else None,
        "socialDispersion": round(summary.dispersion, 4) if not summary.is_empty else None,
        "socialPositive": summary.positive,
        "socialNegative": summary.negative,
        "wikipediaArticle": article,
        "wikipediaViews7d": wiki_views or None,
        "wikipediaVelocity": wiki_velocity,
        "_trailerVideoId": video_id,
    }


def attach_youtube_stats(
    client: httpx.Client, signals: list[dict], youtube_key: str, now: dt.datetime
) -> int:
    """Batch-price every resolved trailer. One quota unit per 50 ids."""
    if not youtube_key:
        for signal in signals:
            signal.pop("_trailerVideoId", None)
            signal["youtubeViews7d"] = None
            signal["youtubeEngagementRate"] = None
        return 0

    ids = [s["_trailerVideoId"] for s in signals if s.get("_trailerVideoId")]
    stats = youtube.fetch_stats(client, youtube_key, ids) if ids else {}

    covered = 0
    for signal in signals:
        video_id = signal.pop("_trailerVideoId", None)
        entry = stats.get(video_id) if video_id else None
        views = (entry or {}).get("views")
        likes = (entry or {}).get("likes")
        if not entry or not views:
            signal["youtubeViews7d"] = None
            signal["youtubeEngagementRate"] = None
            continue
        signal["youtubeViews7d"] = youtube.trailing_week_views(
            views, entry.get("published_at"), now=now
        )
        signal["youtubeEngagementRate"] = (
            round(likes / views, 6) if likes is not None and views > 0 else None
        )
        covered += 1
    return covered


def build(
    out_dir: pathlib.Path,
    *,
    seed_path: pathlib.Path,
    cache_path: pathlib.Path,
    tmdb_key: str,
    youtube_key: str,
    max_movies: int,
    youtube_search_budget: int,
    now: dt.datetime | None = None,
) -> dict:
    now = now or dt.datetime.now(dt.timezone.utc)
    out_dir.mkdir(parents=True, exist_ok=True)

    source_status: dict[str, str] = {}
    trailer_cache = load_trailer_cache(cache_path)

    with httpx.Client(
        headers={"User-Agent": wikipedia.USER_AGENT},
        follow_redirects=True,
    ) as client:
        # --- Catalog -------------------------------------------------
        movies = tmdb.fetch_upcoming(client, tmdb_key) if tmdb_key else []
        if movies:
            source_status["tmdb"] = f"ok ({len(movies)} titles)"
        else:
            movies = load_seed(seed_path)
            source_status["tmdb"] = (
                "not configured — using bundled seed"
                if not tmdb_key
                else "failed — using bundled seed"
            )
        movies = movies[:max_movies]

        if not movies:
            raise SystemExit("No movies from TMDB and no seed file; nothing to build.")

        # --- Per-movie signals ---------------------------------------
        budget = [youtube_search_budget]
        signals: list[dict] = []
        for index, movie in enumerate(movies):
            signals.append(
                collect_movie_signal(
                    client,
                    movie,
                    now=now,
                    trailer_cache=trailer_cache,
                    youtube_key=youtube_key,
                    search_budget=budget,
                )
            )
            if index < len(movies) - 1:
                time.sleep(POLITE_DELAY_SECONDS)

        yt_covered = attach_youtube_stats(client, signals, youtube_key, now)

    social_covered = sum(1 for s in signals if s.get("socialMentions24h"))
    wiki_covered = sum(1 for s in signals if s.get("wikipediaViews7d"))
    source_status["bluesky"] = f"ok ({social_covered}/{len(signals)} titles)"
    source_status["wikipedia"] = f"ok ({wiki_covered}/{len(signals)} titles)"
    source_status["youtube"] = (
        f"ok ({yt_covered}/{len(signals)} titles)"
        if youtube_key
        else "not configured"
    )

    save_trailer_cache(cache_path, trailer_cache)

    manifest = {
        "version": SCHEMA_VERSION,
        "generatedAt": iso(now),
        "movieCount": len(movies),
        "sources": source_status,
    }

    write_json(out_dir / "index.json", manifest)
    write_json(
        out_dir / "upcoming.json",
        {"version": SCHEMA_VERSION, "generatedAt": iso(now), "movies": movies},
    )
    write_json(
        out_dir / "signals.json",
        {
            "version": SCHEMA_VERSION,
            "generatedAt": iso(now),
            "signals": {s["id"]: s for s in signals},
        },
    )
    return manifest


def write_json(path: pathlib.Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True, default=str))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Build the static BoxCall API.")
    parser.add_argument("--out", default="site/api/v1", help="Output directory.")
    parser.add_argument("--seed", default="backend/pipeline/seed_movies.json")
    parser.add_argument("--cache", default=".cache/trailer_ids.json")
    parser.add_argument("--max-movies", type=int, default=40)
    parser.add_argument(
        "--youtube-search-budget",
        type=int,
        default=8,
        help="Max search.list calls per run (100 quota units each).",
    )
    args = parser.parse_args(argv)

    manifest = build(
        pathlib.Path(args.out),
        seed_path=pathlib.Path(args.seed),
        cache_path=pathlib.Path(args.cache),
        tmdb_key=os.getenv("TMDB_API_KEY", ""),
        youtube_key=os.getenv("YOUTUBE_API_KEY", ""),
        max_movies=args.max_movies,
        youtube_search_budget=args.youtube_search_budget,
    )
    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
