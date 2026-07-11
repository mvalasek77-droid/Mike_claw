import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import pytest

from app.roblox_client import RobloxPresence, RobloxProfile


def make_profile(user_id=1000, username="kid_friend", display_name="KidFriend",
                 description="", age_years=0.5, friend_count=20) -> RobloxProfile:
    created = datetime.now(timezone.utc) - timedelta(days=age_years * 365.25)
    return RobloxProfile(
        user_id=user_id, username=username, display_name=display_name,
        description=description, created=created, friend_count=friend_count,
    )


class FakeRobloxClient:
    """In-memory stand-in for the public Roblox API."""

    def __init__(self):
        self.users: dict[str, RobloxProfile] = {}
        self.friends: dict[int, list[RobloxProfile]] = {}
        self.presence: dict[int, RobloxPresence] = {}

    def add_user(self, profile: RobloxProfile):
        self.users[profile.username.lower()] = profile

    async def resolve_username(self, username: str):
        p = self.users.get(username.lower())
        return p.user_id if p else None

    async def get_profile(self, user_id: int) -> RobloxProfile:
        for p in self.users.values():
            if p.user_id == user_id:
                return p
        raise KeyError(user_id)

    async def get_friends(self, user_id: int):
        return list(self.friends.get(user_id, []))

    async def get_friend_count(self, user_id: int) -> int:
        return len(self.friends.get(user_id, []))

    async def get_presence(self, user_id: int) -> RobloxPresence:
        return self.presence.get(user_id, RobloxPresence(user_id=user_id, presence_type=0))

    async def aclose(self):
        pass


@pytest.fixture
def fake_client():
    return FakeRobloxClient()
