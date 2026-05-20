"""Linear-regression trendlines through recent wick pivots, with break detection.

Reference: classical technical analysis (Edwards & Magee, *Technical Analysis
of Stock Trends*). The wick-anchored variant follows the rule that the high
of the bar's range, not the close, marks where a trend was rejected — which
matches what is drawn on investing.com candle charts by default.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

import numpy as np
import pandas as pd

from .pivots import swing_pivots


@dataclass
class Trendline:
    kind: str          # "support" or "resistance"
    slope: float       # price units per bar
    intercept: float   # price at bar index 0
    anchor_idx: int    # first pivot bar index used in fit
    touches: int       # number of pivots in fit
    r2: float

    def at(self, bar_index: int) -> float:
        return self.intercept + self.slope * bar_index


def _fit(xs: list[float], ys: list[float]) -> Optional[tuple[float, float, float]]:
    if len(xs) < 2:
        return None
    x = np.asarray(xs, dtype=float)
    y = np.asarray(ys, dtype=float)
    slope, intercept = np.polyfit(x, y, 1)
    pred = slope * x + intercept
    ss_res = ((y - pred) ** 2).sum()
    ss_tot = ((y - y.mean()) ** 2).sum() or 1.0
    r2 = 1.0 - ss_res / ss_tot
    return float(slope), float(intercept), float(r2)


def current_trendlines(
    df: pd.DataFrame,
    left: int = 3,
    right: int = 3,
    lookback_pivots: int = 8,
    min_pivots: int = 3,
) -> tuple[Optional[Trendline], Optional[Trendline]]:
    """Return (support, resistance) trendlines for the visible window."""
    ph, pl = swing_pivots(df, left, right)
    idx = np.arange(len(df))
    high_pivots = [(int(i), float(df["high"].iloc[int(i)])) for i in idx[ph.values]][-lookback_pivots:]
    low_pivots  = [(int(i), float(df["low"].iloc[int(i)]))  for i in idx[pl.values]][-lookback_pivots:]

    resistance: Optional[Trendline] = None
    support: Optional[Trendline] = None

    if len(high_pivots) >= min_pivots:
        xs = [p[0] for p in high_pivots]
        ys = [p[1] for p in high_pivots]
        fit = _fit(xs, ys)
        if fit is not None:
            slope, intercept, r2 = fit
            resistance = Trendline("resistance", slope, intercept, xs[0], len(xs), r2)

    if len(low_pivots) >= min_pivots:
        xs = [p[0] for p in low_pivots]
        ys = [p[1] for p in low_pivots]
        fit = _fit(xs, ys)
        if fit is not None:
            slope, intercept, r2 = fit
            support = Trendline("support", slope, intercept, xs[0], len(xs), r2)

    return support, resistance


def break_state(
    df: pd.DataFrame,
    support: Optional[Trendline],
    resistance: Optional[Trendline],
    atr_value: float,
    buffer_mult: float = 0.5,
) -> dict:
    """Classify the latest bar relative to current trendlines."""
    if len(df) < 2:
        return {k: False for k in ("break_up", "break_down", "above_resistance",
                                   "below_support", "near_resistance", "near_support")}
    last_i = len(df) - 1
    close_now = float(df["close"].iloc[-1])
    close_prev = float(df["close"].iloc[-2])
    buf = buffer_mult * float(atr_value or 0.0)

    out = {"break_up": False, "break_down": False, "above_resistance": False,
           "below_support": False, "near_resistance": False, "near_support": False}

    if resistance is not None:
        line = resistance.at(last_i)
        prev_line = resistance.at(last_i - 1)
        out["above_resistance"] = close_now > line + buf
        out["near_resistance"] = abs(close_now - line) <= buf
        out["break_up"] = close_now > line + buf and close_prev <= prev_line + buf
    if support is not None:
        line = support.at(last_i)
        prev_line = support.at(last_i - 1)
        out["below_support"] = close_now < line - buf
        out["near_support"] = abs(close_now - line) <= buf
        out["break_down"] = close_now < line - buf and close_prev >= prev_line - buf
    return out
