"""Trendline-break continuation (trend regime only).

Classical Edwards-Magee trendline trading: when price closes through an
established support/resistance line with conviction (here: > 0.5 * ATR
beyond the line), enter in the break direction. Only fires when ADX
already confirms a directional regime so we don't chase false breaks.
"""
from __future__ import annotations

from .base import Signal, Strategy


class TrendlineBreakout(Strategy):
    name = "trendline_break"

    def signal(self, ctx: dict) -> Signal:
        bs = ctx.get("break_state") or {}
        regime = ctx.get("regime", "chop")
        if regime == "chop":
            return Signal("flat", 0.0, "no_trend_for_break", self.name)
        if bs.get("break_up"):
            return Signal("long_hou", 0.8, "broke_resistance_in_trend", self.name)
        if bs.get("break_down"):
            return Signal("long_hod", 0.8, "broke_support_in_trend", self.name)
        return Signal("flat", 0.0, "no_break", self.name)
