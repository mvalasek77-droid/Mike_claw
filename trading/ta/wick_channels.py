"""Wick-based channel detection and breakout scoring.

Core idea (from Mike): draw trendlines through the LONGEST candle wicks
(swing pivot highs/lows), trade the RANGE between support and resistance,
and trade BREAKOUTS when price punches through a line.

This is the primary short-term signal engine for the oil bot. It combines:
1. Range trade — buy near support, fade near resistance (chop regime)
2. Breakout trade — enter in the break direction (trend regime)
3. Channel width — narrow channels = coiled spring, wider = range-bound

Wick selection: pivots are ranked by wick length (high - low of the pivot
bar), and only the top-N most prominent are used for trendline fitting.
This mirrors how traders draw lines — they connect the longest wicks, not
random noise.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Optional

import numpy as np
import pandas as pd

from .pivots import swing_pivots


@dataclass
class WickChannel:
    """A pair of support/resistance trendlines drawn from wick pivots."""
    support: Optional["WickLine"] = None
    resistance: Optional["WickLine"] = None
    channel_width: float = 0.0        # resistance - support at last bar
    channel_pct: float = 0.0         # channel_width / mid_price
    is_narrow: bool = False           # < 0.5 * ATR channel = coiled
    price_vs_support: float = 0.0    # distance from support (positive = above)
    price_vs_resistance: float = 0.0 # distance from resistance (negative = below)
    between_lines: bool = False       # price is inside the channel
    near_support: bool = False
    near_resistance: bool = False
    break_up: bool = False
    break_down: bool = False

    def summary(self) -> str:
        s = f"Ch={self.channel_pct:.2%}"
        if self.is_narrow:
            s += " NARROW"
        if self.between_lines:
            s += f" IN-CHAN sup={self.price_vs_support:+.2f} res={self.price_vs_resistance:+.2f}"
        if self.break_up:
            s += " ▲BREAK_UP"
        if self.break_down:
            s += " ▼BREAK_DN"
        if self.near_support:
            s += " ~SUP"
        if self.near_resistance:
            s += " ~RES"
        return s


@dataclass
class WickLine:
    """A single trendline fitted through wick pivots."""
    kind: str            # "support" or "resistance"
    slope: float         # price units per bar
    intercept: float     # price at bar index 0
    anchor_idx: int      # first pivot bar index
    touches: int         # number of pivots in the fit
    r2: float            # goodness of fit
    wick_score: float    # avg wick length of pivots used (higher = stronger)

    def at(self, bar_index: int) -> float:
        """Project the trendline to a given bar index."""
        return self.intercept + self.slope * bar_index


def _fit_line(xs: list[float], ys: list[float]) -> Optional[tuple[float, float, float]]:
    """Linear regression fit. Returns (slope, intercept, r2) or None."""
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


def detect_wick_channels(
    df: pd.DataFrame,
    left: int = 3,
    right: int = 3,
    top_n_wicks: int = 6,       # use top-N longest wick pivots
    min_pivots: int = 3,        # minimum pivots to draw a line
    lookback_bars: int = 200,   # how many recent bars to scan
    atr_value: float = 0.0,
    near_buffer_atr: float = 0.3,  # "near" = within this * ATR
    break_buffer_atr: float = 0.5, # "break" = beyond this * ATR
) -> WickChannel:
    """Detect wick-based support/resistance channels from the longest wick pivots.

    This is the core detection engine. It:
    1. Finds swing pivots (long wicks)
    2. Ranks them by wick length (body = |high - low|)
    3. Fits support through top-N low pivots, resistance through top-N high pivots
    4. Classifies current price vs the channel
    """
    n = len(df)
    if n < left + right + 1:
        return WickChannel()

    # Only look at recent bars
    start = max(0, n - lookback_bars)
    recent = df.iloc[start:].copy()
    recent_idx_offset = start

    # Detect pivots
    ph, pl = swing_pivots(recent, left, right)
    idx_arr = np.arange(len(recent))

    # Collect pivot highs with wick length ranking
    high_pivots = []
    for i in idx_arr[ph.values]:
        g_i = int(i) + recent_idx_offset
        wick_len = float(recent["high"].iloc[int(i)]) - float(recent["low"].iloc[int(i)])
        high_pivots.append((g_i, float(recent["high"].iloc[int(i)]), wick_len))

    low_pivots = []
    for i in idx_arr[pl.values]:
        g_i = int(i) + recent_idx_offset
        wick_len = float(recent["high"].iloc[int(i)]) - float(recent["low"].iloc[int(i)])
        low_pivots.append((g_i, float(recent["low"].iloc[int(i)]), wick_len))

    # Sort by wick length (longest wick = most significant pivot)
    high_pivots.sort(key=lambda p: p[2], reverse=True)
    low_pivots.sort(key=lambda p: p[2], reverse=True)

    # Take top-N with longest wicks
    high_pivots_top = high_pivots[:top_n_wicks]
    low_pivots_top = low_pivots[:top_n_wicks]

    channel = WickChannel()
    last_i = n - 1
    close_now = float(df["close"].iloc[-1])
    close_prev = float(df["close"].iloc[-2]) if n > 1 else close_now
    buf_near = near_buffer_atr * atr_value
    buf_break = break_buffer_atr * atr_value

    # Fit resistance line from top wick pivots
    if len(high_pivots_top) >= min_pivots:
        # Re-sort by index for proper fitting
        high_pivots_top.sort(key=lambda p: p[0])
        xs = [float(p[0]) for p in high_pivots_top]
        ys = [float(p[1]) for p in high_pivots_top]
        fit = _fit_line(xs, ys)
        if fit is not None:
            slope, intercept, r2 = fit
            avg_wick = np.mean([p[2] for p in high_pivots_top])
            channel.resistance = WickLine(
                "resistance", slope, intercept, int(xs[0]),
                len(xs), r2, float(avg_wick),
            )

    # Fit support line from top wick pivots
    if len(low_pivots_top) >= min_pivots:
        low_pivots_top.sort(key=lambda p: p[0])
        xs = [float(p[0]) for p in low_pivots_top]
        ys = [float(p[1]) for p in low_pivots_top]
        fit = _fit_line(xs, ys)
        if fit is not None:
            slope, intercept, r2 = fit
            avg_wick = np.mean([p[2] for p in low_pivots_top])
            channel.support = WickLine(
                "support", slope, intercept, int(xs[0]),
                len(xs), r2, float(avg_wick),
            )

    # Channel metrics
    res_val = channel.resistance.at(last_i) if channel.resistance else None
    sup_val = channel.support.at(last_i) if channel.support else None

    if res_val is not None and sup_val is not None:
        channel.channel_width = res_val - sup_val
        mid = (res_val + sup_val) / 2
        channel.channel_pct = channel.channel_width / mid if mid > 0 else 0
        channel.is_narrow = channel.channel_width < 0.5 * atr_value if atr_value > 0 else False

    # Price vs lines
    if sup_val is not None:
        channel.price_vs_support = close_now - sup_val
        channel.near_support = abs(channel.price_vs_support) <= buf_near
        # Break down: close is below support minus buffer
        channel.break_down = close_now < sup_val - buf_break

    if res_val is not None:
        channel.price_vs_resistance = close_now - res_val
        channel.near_resistance = abs(channel.price_vs_resistance) <= buf_near
        # Break up: close is above resistance plus buffer
        channel.break_up = close_now > res_val + buf_break

    # Between lines check
    if sup_val is not None and res_val is not None:
        channel.between_lines = sup_val <= close_now <= res_val

    return channel