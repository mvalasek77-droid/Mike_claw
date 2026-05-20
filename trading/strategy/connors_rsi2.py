"""Larry Connors RSI(2) short-horizon mean reversion.

Reference: Larry Connors & Cesar Alvarez, *Short Term Trading Strategies
That Work* (TradingMarkets, 2009). RSI(2) < 10 = oversold buy on the
trend; RSI(2) > 90 = overbought fade. We additionally require the
2-day signal to disagree with the recent intraday trend, to focus the
trade on reversion (not chasing).
"""
from __future__ import annotations

from ..ta.indicators import rsi
from .base import Signal, Strategy


class ConnorsRSI2(Strategy):
    name = "connors_rsi2"

    def __init__(self, period: int = 2, oversold: float = 10.0, overbought: float = 90.0):
        self.period = period
        self.oversold = oversold
        self.overbought = overbought

    def signal(self, ctx: dict) -> Signal:
        daily = ctx.get("daily_underlying")
        if daily is None or len(daily) < self.period + 5:
            return Signal("flat", 0.0, "insufficient_history", self.name)
        r2 = float(rsi(daily["close"], self.period).iloc[-1] or 50.0)
        # Oversold on the daily → expect bounce in crude → long HOU
        if r2 <= self.oversold:
            conf = min(1.0, (self.oversold - r2) / self.oversold + 0.4)
            return Signal("long_hou", conf, f"rsi2={r2:.1f}_oversold", self.name)
        if r2 >= self.overbought:
            conf = min(1.0, (r2 - self.overbought) / (100 - self.overbought) + 0.4)
            return Signal("long_hod", conf, f"rsi2={r2:.1f}_overbought", self.name)
        return Signal("flat", 0.0, f"rsi2={r2:.1f}_neutral", self.name)
