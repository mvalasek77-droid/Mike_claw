"""Trendline-channel mean reversion (chop regime only).

Buy near rising support, fade near falling resistance — but only when the
regime classifier says 'chop' (ADX < threshold), because mean reversion
loses badly in trending markets. This mirrors the standard short-horizon
stat-arb playbook used at firms like Renaissance and D.E. Shaw, though the
public versions are far simpler than what they actually trade.
"""
from __future__ import annotations

from .base import Signal, Strategy


class TrendlineMeanRevert(Strategy):
    name = "channel_mean_revert"

    def signal(self, ctx: dict) -> Signal:
        bs = ctx.get("break_state") or {}
        regime = ctx.get("regime", "chop")
        if regime != "chop":
            return Signal("flat", 0.0, f"regime={regime}_skip", self.name)
        if bs.get("near_support") and not bs.get("break_down"):
            return Signal("long_hou", 0.55, "bounce_off_rising_support", self.name)
        if bs.get("near_resistance") and not bs.get("break_up"):
            return Signal("long_hod", 0.55, "fade_falling_resistance", self.name)
        return Signal("flat", 0.0, "no_edge_in_channel", self.name)
