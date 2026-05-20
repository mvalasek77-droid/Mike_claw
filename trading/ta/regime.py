"""Regime classifier: trend / chop / shock.

Inputs are ADX (trend strength) and realized volatility versus its rolling
median (shock detection). Decay-aware strategies treat 'chop' as a
no-trade regime for leveraged ETFs.
"""
from __future__ import annotations

import pandas as pd

from .indicators import adx, realized_vol


def classify(df: pd.DataFrame, adx_threshold: float = 22.0, vol_window: int = 20) -> str:
    if len(df) < max(60, vol_window + 5):
        return "chop"
    a = float(adx(df).iloc[-1] or 0)
    rv = realized_vol(df["close"], window=vol_window)
    rv_now = float(rv.iloc[-1] or 0)
    rv_med = float(rv.rolling(60).median().iloc[-1] or rv_now)
    if rv_now > 1.5 * rv_med and rv_med > 0:
        return "shock"
    if a >= adx_threshold:
        return "trend"
    return "chop"
