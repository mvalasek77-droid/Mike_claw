"""Time-series momentum on crude.

Reference: Moskowitz, Ooi & Pedersen, "Time Series Momentum",
*Journal of Financial Economics* 104 (2012), pp.228-250 — the foundational
AQR/Cliff-Asness paper showing 12-month past-return sign predicts next-month
return across dozens of futures markets including WTI.

We use it as a slow-moving regime confirmation, not a 30-minute trigger.
"""
from __future__ import annotations

from .base import Signal, Strategy


class TSMomentum(Strategy):
    name = "tsmom_aqr"

    def __init__(self, lookback_days: int = 252):
        self.lookback_days = lookback_days

    def signal(self, ctx: dict) -> Signal:
        daily = ctx.get("daily_underlying")
        if daily is None or len(daily) < self.lookback_days + 1:
            return Signal("flat", 0.0, "insufficient_daily_history", self.name)
        r = float(daily["close"].iloc[-1] / daily["close"].iloc[-self.lookback_days - 1] - 1)
        if r > 0.02:
            return Signal("long_hou", min(1.0, abs(r) * 4), f"12m_ret={r:+.2%}", self.name)
        if r < -0.02:
            return Signal("long_hod", min(1.0, abs(r) * 4), f"12m_ret={r:+.2%}", self.name)
        return Signal("flat", 0.0, f"12m_ret={r:+.2%}", self.name)
