"""Pydantic response shapes. Kept in sync with the iOS Codable models."""
from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime


class Movie(BaseModel):
    id: str
    title: str
    studio: str
    releaseDate: str
    posterEmoji: str
    posterURL: Optional[str] = None
    tagline: str
    consensusOpeningMillions: float
    impliedVolPct: float
    genre: str


class Tracking(BaseModel):
    openingWeekendMillions: float
    impliedVolPct: float


class XSignal(BaseModel):
    mentions24h: int
    sentiment: float = Field(..., ge=-1, le=1)


class SettlementRow(BaseModel):
    movieId: str
    title: str
    actualOpeningMillions: float
    reportedAt: datetime


class ModerationReport(BaseModel):
    kind: str
    targetId: str
    reason: str
    note: Optional[str] = None


class AnalyticsEvent(BaseModel):
    name: str
    ts: str
    signed_in: bool
    membership: str
    props: dict = {}


class Me(BaseModel):
    """Cloud-synced user state."""
    handle: str
    reelCoins: float
    xp: int
    tier: str
    membership: str
    followers: int
    badges: list[str] = []
