"""Bluesky public search — the free replacement for the X API.

X discontinued its free tier in February 2026 and now bills per post
read, so the original `/x-signal` design could never be free. Bluesky's
AT Protocol exposes `app.bsky.feed.searchPosts` on a public, cached
endpoint that needs no account, no key, and no approval, and it costs
nothing at any volume we will reach.

The HTTP call and the parsing are deliberately separate so the parsing
can be tested against recorded fixtures with no network.
"""
from __future__ import annotations

import collections
import datetime as dt
import re
import urllib.parse

import httpx

# Bluesky asks that "public web" clients use the cached host.
PUBLIC_HOST = "https://public.api.bsky.app"
SEARCH_PATH = "/xrpc/app.bsky.feed.searchPosts"
# Signed-in requests go through the account's host, which proxies search.
AUTH_HOST = "https://bsky.social"
SESSION_PATH = "/xrpc/com.atproto.server.createSession"


def login(client: httpx.Client, handle: str, app_password: str) -> str | None:
    """An access token for a free account's app password, or None.

    Bluesky has restricted anonymous post search on the public host, so
    a signed-in request is the dependable way to read mentions.
    """
    if not handle or not app_password:
        return None
    try:
        response = client.post(f"{AUTH_HOST}{SESSION_PATH}",
                               json={"identifier": handle, "password": app_password},
                               timeout=15)
        if response.status_code != 200:
            return None
        return response.json().get("accessJwt")
    except (httpx.HTTPError, ValueError):
        return None


def describe(stats: collections.Counter, covered: int, total: int, signed_in: bool) -> str:
    """One status line for the feed manifest, naming why there is no data."""
    if covered or not stats or set(stats) == {200}:
        return f"ok ({covered}/{total} titles{', signed in' if signed_in else ''})"
    failures = ", ".join(f"{k} x{v}" for k, v in stats.most_common() if k != 200)
    hint = "" if signed_in else "; set BLUESKY_HANDLE and BLUESKY_APP_PASSWORD secrets"
    return f"no data ({failures}){hint}"

# Titles carry punctuation that confuses the query parser and subtitles
# that suppress recall ("Dune: Part Three" vs how people actually type it).
_PUNCT_RE = re.compile(r"[^\w\s'-]")


def build_query(title: str, year: int | None = None) -> str:
    """Turn a movie title into a search query.

    Quoted so the words stay adjacent — an unquoted multi-word title
    matches any post containing any of the words, which for a title like
    "Wicked" or "Him" returns almost entirely unrelated chatter.
    """
    cleaned = _PUNCT_RE.sub(" ", title)
    cleaned = " ".join(cleaned.split())
    if not cleaned:
        return ""
    return f'"{cleaned}"'


def parse_search_response(payload: dict, *, since: dt.datetime) -> list[dict]:
    """Extract the posts we care about from a searchPosts response.

    Returns dicts of ``text``, ``likes``, ``reposts``, ``created_at``.
    Posts older than ``since`` are dropped, because the signal we are
    building is explicitly a 24-hour mention count and Bluesky's search
    happily returns older material.
    """
    out: list[dict] = []
    for post in payload.get("posts") or []:
        record = post.get("record") or {}
        text = record.get("text")
        if not text:
            continue

        created = _parse_timestamp(record.get("createdAt") or post.get("indexedAt"))
        if created is not None and created < since:
            continue

        out.append(
            {
                "text": text,
                "likes": int(post.get("likeCount") or 0),
                "reposts": int(post.get("repostCount") or 0),
                "replies": int(post.get("replyCount") or 0),
                "created_at": created.isoformat() if created else None,
            }
        )
    return out


def _parse_timestamp(value: str | None) -> dt.datetime | None:
    if not value:
        return None
    try:
        # AT Protocol emits RFC 3339; Python needs the Z spelled out.
        return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except (ValueError, AttributeError):
        return None


def search_posts(
    client: httpx.Client,
    title: str,
    *,
    limit: int = 100,
    window_hours: int = 24,
    now: dt.datetime | None = None,
    token: str | None = None,
    stats: collections.Counter | None = None,
) -> list[dict]:
    """Fetch recent public posts mentioning a movie.

    Returns an empty list on any failure. A social source that raises
    would take the whole nightly build down over one unlucky title.
    Each response's HTTP status (or error name) is counted in `stats`,
    so a source that fails every time is reported rather than silent.
    """
    query = build_query(title)
    if not query:
        return []

    now = now or dt.datetime.now(dt.timezone.utc)
    since = now - dt.timedelta(hours=window_hours)

    host = AUTH_HOST if token else PUBLIC_HOST
    url = f"{host}{SEARCH_PATH}?" + urllib.parse.urlencode(
        {"q": query, "limit": min(100, max(1, limit)), "sort": "latest"}
    )
    headers = {"Authorization": f"Bearer {token}"} if token else None
    try:
        response = client.get(url, headers=headers, timeout=15)
        if stats is not None:
            stats[response.status_code] += 1
        if response.status_code != 200:
            return []
        return parse_search_response(response.json(), since=since)
    except (httpx.HTTPError, ValueError) as error:
        if stats is not None:
            stats[type(error).__name__] += 1
        return []
