"""Async client for Roblox's public, unauthenticated web APIs.

Design constraints (these are load-bearing for App Store approval and for
staying inside Roblox's Terms of Use):

  * Only public endpoints that work WITHOUT any login, cookie, or API key.
    We never ask for — and this client cannot use — a child's credentials.
  * Private chat content is not accessible and is deliberately out of scope.
  * Calls are spaced out (`request_spacing_seconds`) to stay polite.

Endpoints used:
  POST users.roblox.com/v1/usernames/users      username -> userId
  GET  users.roblox.com/v1/users/{id}           profile (created date, bio)
  GET  friends.roblox.com/v1/users/{id}/friends friend list
  GET  friends.roblox.com/v1/users/{id}/friends/count
  POST presence.roblox.com/v1/presence/users    online status + current place
"""

import asyncio
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Optional

import httpx

USERS_BASE = "https://users.roblox.com"
FRIENDS_BASE = "https://friends.roblox.com"
PRESENCE_BASE = "https://presence.roblox.com"


@dataclass
class RobloxProfile:
    user_id: int
    username: str
    display_name: str
    description: str
    created: datetime
    is_banned: bool = False
    friend_count: Optional[int] = None


@dataclass
class RobloxPresence:
    user_id: int
    # 0 offline, 1 online (website), 2 in game, 3 in studio
    presence_type: int
    last_location: str = ""
    place_id: Optional[int] = None
    universe_id: Optional[int] = None
    observed_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))


def _parse_created(value: str) -> datetime:
    # Roblox returns ISO 8601 with a Z suffix and variable sub-second precision.
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


class RobloxClient:
    def __init__(self, spacing_seconds: float = 0.5, http: Optional[httpx.AsyncClient] = None):
        self._spacing = spacing_seconds
        self._last_request = 0.0
        self._lock = asyncio.Lock()
        self._http = http or httpx.AsyncClient(timeout=15.0, headers={"User-Agent": "RobloxGuard/1.0 (parental safety companion)"})

    async def aclose(self) -> None:
        await self._http.aclose()

    async def _throttle(self) -> None:
        async with self._lock:
            wait = self._spacing - (time.monotonic() - self._last_request)
            if wait > 0:
                await asyncio.sleep(wait)
            self._last_request = time.monotonic()

    async def _request(self, method: str, url: str, payload: Optional[dict] = None,
                       attempts: int = 3) -> dict:
        """Request with retry on rate limits (429), server errors, and
        transport failures — exponential backoff, honoring Retry-After."""
        last_error: Exception = RuntimeError("unreachable")
        for attempt in range(attempts):
            await self._throttle()
            try:
                if method == "GET":
                    resp = await self._http.get(url)
                else:
                    resp = await self._http.post(url, json=payload)
                if resp.status_code == 429 or resp.status_code >= 500:
                    retry_after = float(resp.headers.get("Retry-After", 0) or 0)
                    raise httpx.HTTPStatusError(
                        f"retryable status {resp.status_code}",
                        request=resp.request, response=resp)
                resp.raise_for_status()
                return resp.json()
            except httpx.HTTPStatusError as error:
                if error.response.status_code not in (429,) and error.response.status_code < 500:
                    raise  # 4xx other than 429: not retryable
                last_error = error
                retry_after = float(error.response.headers.get("Retry-After", 0) or 0)
            except httpx.TransportError as error:
                last_error = error
                retry_after = 0.0
            if attempt < attempts - 1:
                await asyncio.sleep(max(retry_after, 2 ** attempt))
        raise last_error

    async def _get(self, url: str) -> dict:
        return await self._request("GET", url)

    async def _post(self, url: str, payload: dict) -> dict:
        return await self._request("POST", url, payload)

    async def resolve_username(self, username: str) -> Optional[int]:
        """Return the userId for an exact username, or None if not found."""
        data = await self._post(
            f"{USERS_BASE}/v1/usernames/users",
            {"usernames": [username], "excludeBannedUsers": False},
        )
        for row in data.get("data", []):
            if row.get("requestedUsername", "").lower() == username.lower():
                return row["id"]
        return None

    async def get_profile(self, user_id: int) -> RobloxProfile:
        data = await self._get(f"{USERS_BASE}/v1/users/{user_id}")
        return RobloxProfile(
            user_id=data["id"],
            username=data.get("name", ""),
            display_name=data.get("displayName", ""),
            description=data.get("description") or "",
            created=_parse_created(data["created"]),
            is_banned=bool(data.get("isBanned", False)),
        )

    async def get_friends(self, user_id: int) -> list[RobloxProfile]:
        """Friend list with per-friend profile details.

        friends.roblox.com returns id/name/displayName inline; description and
        created date require a per-friend profile fetch, which the throttle keeps
        polite. Failures on individual friends degrade to a stub profile rather
        than failing the whole snapshot.
        """
        data = await self._get(f"{FRIENDS_BASE}/v1/users/{user_id}/friends")
        friends: list[RobloxProfile] = []
        for row in data.get("data", []):
            fid = row["id"]
            try:
                profile = await self.get_profile(fid)
            except httpx.HTTPError:
                profile = RobloxProfile(
                    user_id=fid,
                    username=row.get("name", ""),
                    display_name=row.get("displayName", ""),
                    description="",
                    created=datetime.now(timezone.utc),
                )
            try:
                profile.friend_count = await self.get_friend_count(fid)
            except httpx.HTTPError:
                profile.friend_count = None
            friends.append(profile)
        return friends

    async def get_friend_count(self, user_id: int) -> int:
        data = await self._get(f"{FRIENDS_BASE}/v1/users/{user_id}/friends/count")
        return int(data.get("count", 0))

    async def get_presence(self, user_id: int) -> RobloxPresence:
        data = await self._post(f"{PRESENCE_BASE}/v1/presence/users", {"userIds": [user_id]})
        rows = data.get("userPresences", [])
        if not rows:
            return RobloxPresence(user_id=user_id, presence_type=0)
        row = rows[0]
        return RobloxPresence(
            user_id=user_id,
            presence_type=int(row.get("userPresenceType", 0)),
            last_location=row.get("lastLocation") or "",
            place_id=row.get("placeId"),
            universe_id=row.get("universeId"),
        )
