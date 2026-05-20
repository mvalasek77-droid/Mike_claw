"""Session VWAP + EMA bias on 30-min crude bars.

Common discretionary day-trader heuristic: above session VWAP with a
rising 50-bar EMA is a long bias; below VWAP with a falling EMA is a
short bias. No academic edge claimed — used as a sentiment/structural
filter that complements the breakout and mean-reversion strategies.
"""
from __future__ import annotations

import numpy as np
import pandas as pd

from ..ta.indicators import ema
from .base import Signal, Strategy


def session_vwap(df: pd.DataFrame) -> pd.Series:
    """Approximate VWAP: reset each calendar day, cumulative typical-price * volume."""
    typical = (df["high"] + df["low"] + df["close"]) / 3.0
    pv = typical * df["volume"]
    day = pd.Series(df.index.date, index=df.index)
    cum_pv = pv.groupby(day).cumsum()
    cum_v = df["volume"].groupby(day).cumsum().replace(0, np.nan)
    return (cum_pv / cum_v).rename("vwap")


class VWAPBias(Strategy):
    name = "vwap_bias"

    def signal(self, ctx: dict) -> Signal:
        intra = ctx.get("intraday_underlying")
        if intra is None or len(intra) < 60 or "volume" not in intra.columns:
            return Signal("flat", 0.0, "insufficient_intraday", self.name)
        vwap = session_vwap(intra)
        e50 = ema(intra["close"], 50)
        close = float(intra["close"].iloc[-1])
        vw = float(vwap.iloc[-1] or close)
        slope = float(e50.iloc[-1] - e50.iloc[-5])
        above = close > vw
        if above and slope > 0:
            return Signal("long_hou", 0.5, f"close>{vw:.2f}_vwap_ema_up", self.name)
        if (not above) and slope < 0:
            return Signal("long_hod", 0.5, f"close<{vw:.2f}_vwap_ema_dn", self.name)
        return Signal("flat", 0.0, "vwap_ema_mixed", self.name)
