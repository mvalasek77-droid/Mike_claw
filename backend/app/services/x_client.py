"""X (Twitter) API v2 recent-tweet-counts + sentiment. Paid tier
required; the API key lives in an env var so it never leaves the
server."""
import os, httpx
from ..models.schemas import XSignal

X_BEARER = os.getenv("X_BEARER_TOKEN", "")
COUNTS_URL = "https://api.twitter.com/2/tweets/counts/recent"


async def fetch_x_signal(title: str) -> XSignal | None:
    if not X_BEARER:
        return None
    headers = {"Authorization": f"Bearer {X_BEARER}"}
    q = f'"{title}" -is:retweet lang:en'
    params = {"query": q, "granularity": "hour"}
    try:
        async with httpx.AsyncClient(timeout=10, headers=headers) as c:
            r = await c.get(COUNTS_URL, params=params)
            r.raise_for_status()
            j = r.json()
    except Exception:
        return None

    total = int(j.get("meta", {}).get("total_tweet_count", 0))
    # Sentiment: real impl runs each tweet through a small classifier.
    # Stubbed here to +0.15 baseline (mildly positive).
    return XSignal(mentions24h=total, sentiment=0.15)
