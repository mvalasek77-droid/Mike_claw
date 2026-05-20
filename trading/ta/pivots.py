"""Swing-pivot detection from candle wick extremes.

A pivot high is a bar whose `high` is strictly greater than the `high` of
the `left` bars before it and the `right` bars after it (mirror for lows).
This is the long-wick definition: the wick must dominate its neighborhood.
"""
from __future__ import annotations

import pandas as pd


def swing_pivots(df: pd.DataFrame, left: int = 3, right: int = 3) -> tuple[pd.Series, pd.Series]:
    highs = df["high"].values
    lows = df["low"].values
    n = len(df)
    ph = [False] * n
    pl = [False] * n
    for i in range(left, n - right):
        window_h = highs[i - left:i + right + 1]
        window_l = lows[i - left:i + right + 1]
        if highs[i] == window_h.max() and (window_h == highs[i]).sum() == 1:
            ph[i] = True
        if lows[i] == window_l.min() and (window_l == lows[i]).sum() == 1:
            pl[i] = True
    return pd.Series(ph, index=df.index, name="pivot_high"), pd.Series(pl, index=df.index, name="pivot_low")
