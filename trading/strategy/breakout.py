"""Donchian/Turtle channel breakout.

Reference: Richard Dennis & William Eckhardt, "Turtle Traders" rules
(1983-1988), publicly documented by Curtis Faith in *The Way of the
Turtle* (McGraw-Hill, 2007). Original System 1 was a 20-day breakout with
10-day opposite-channel exit and ATR-based position sizing.

We apply it to the underlying (WTI), not the leveraged ETF directly, so
that ETF decay does not contaminate the signal.
"""
from __future__ import annotations

from .base import Signal, Strategy


class DonchianBreakout(Strategy):
    name = "donchian_turtle"

    def __init__(self, entry: int = 20, exit_: int = 10):
        self.entry = entry
        self.exit_ = exit_

    def signal(self, ctx: dict) -> Signal:
        daily = ctx.get("daily_underlying")
        if daily is None or len(daily) < self.entry + 1:
            return Signal("flat", 0.0, "insufficient_history", self.name)
        high_n = float(daily["high"].iloc[-self.entry - 1:-1].max())
        low_n = float(daily["low"].iloc[-self.entry - 1:-1].min())
        last = float(daily["close"].iloc[-1])
        if last > high_n:
            return Signal("long_hou", 0.7, f"close>{self.entry}d_high({high_n:.2f})", self.name)
        if last < low_n:
            return Signal("long_hod", 0.7, f"close<{self.entry}d_low({low_n:.2f})", self.name)
        return Signal("flat", 0.0, "inside_channel", self.name)
