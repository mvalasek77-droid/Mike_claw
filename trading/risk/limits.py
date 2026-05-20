"""Hard daily-loss cap and event-blackout gates."""
from __future__ import annotations

from datetime import date, datetime
from zoneinfo import ZoneInfo


class DailyLossCap:
    """Sticky per-calendar-day cap. Trips when cumulative pnl <= -cap_dollars."""

    def __init__(self, pct: float, account_cad: float):
        self.cap = pct * account_cad
        self.day: date | None = None
        self.pnl: float = 0.0

    def _reset(self, today: date) -> None:
        if self.day != today:
            self.day = today
            self.pnl = 0.0

    def add(self, pnl: float, today: date) -> None:
        self._reset(today)
        self.pnl += pnl

    def tripped(self, today: date) -> bool:
        self._reset(today)
        return self.pnl <= -self.cap


def eia_blackout(now: datetime, minutes: int = 20, tz: str = "America/Toronto") -> bool:
    """EIA crude inventory report = Wednesday 10:30 ET. Blackout +/- `minutes`."""
    local = now.astimezone(ZoneInfo(tz)) if now.tzinfo else now.replace(tzinfo=ZoneInfo(tz))
    if local.weekday() != 2:  # Wednesday
        return False
    target_minutes = 10 * 60 + 30
    now_minutes = local.hour * 60 + local.minute
    return abs(now_minutes - target_minutes) <= minutes
