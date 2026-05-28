"""Multi-timeframe wick-channel analysis.

Top-down approach:
    1 MONTH → main trend bias (bull/bear/chop)
    1 WEEK  → intermediate trend alignment
    1 DAY   → daily structure & key levels
    30 MIN  → signal timeframe (entry)
    15 MIN  → micro-timing (confirmation)

Rule: If monthly says BULL, only look for longs on 15/30m.
      If monthly says BEAR, only look for shorts.
      If monthly is CHOP, trade both sides but with less size.

The monthly bias acts as a GATE — don't fight the big picture.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Optional

import numpy as np
import pandas as pd

from .wick_channels import WickChannel, detect_wick_channels
from .regime import classify
from .indicators import atr


# yfinance interval mapping
INTERVAL_MAP = {
    "15m":  {"interval": "15m", "lookback_days": 60,   "label": "15MIN"},
    "30m":  {"interval": "30m", "lookback_days": 60,   "label": "30MIN"},
    "1d":   {"interval": "1d",  "lookback_days": 365,  "label": "DAILY"},
    "1wk":  {"interval": "1wk", "lookback_days": 730,  "label": "WEEKLY"},
    "1mo":  {"interval": "1mo", "lookback_days": 3650, "label": "MONTHLY"},
}


@dataclass
class TimeframeChannel:
    """Wick channel result for one timeframe."""
    label: str
    channel: WickChannel
    regime: str           # chop / trend_up / trend_down
    close: float
    ema9: float
    ema21: float
    slope_dir: str        # bullish / bearish / flat (based on resistance/support slope)

    @property
    def bias(self) -> str:
        """Overall directional bias for this timeframe."""
        if self.regime in ("trend", "trend_up"):
            if self.slope_dir == "bullish":
                return "bull"
            elif self.slope_dir == "bearish":
                return "bear"
        if self.regime in ("chop", "shock"):
            return "chop"
        # fallback
        if self.close > self.ema21:
            return "bull"
        elif self.close < self.ema21:
            return "bear"
        return "chop"

    def summary(self) -> str:
        return f"{self.label}: {self.bias.upper()} regime={self.regime} ch={self.channel.summary()}"


@dataclass
class MultiTFResult:
    """Complete multi-timeframe analysis."""
    frames: dict[str, TimeframeChannel] = field(default_factory=dict)
    monthly_bias: str = "chop"     # THE key: bull / bear / chop
    alignment_score: float = 0.0  # how aligned are all timeframes? 0-1
    trade_direction: str = "flat" # long_hou / long_hod / flat
    conviction: float = 0.0

    def summary(self) -> str:
        lines = []
        for tf in ["1mo", "1wk", "1d", "30m", "15m"]:
            if tf in self.frames:
                lines.append(self.frames[tf].summary())
        lines.append(f"MONTHLY BIAS: {self.monthly_bias.upper()}")
        lines.append(f"ALIGNMENT: {self.alignment_score:.0%}")
        lines.append(f"TRADE: {self.trade_direction} @ {self.conviction:.2f}")
        return "\n".join(lines)


def _calc_ema(series: pd.Series, period: int) -> pd.Series:
    return series.ewm(span=period, adjust=False).mean()


def _slope_direction(line) -> str:
    """Classify a WickLine slope as bullish/bearish/flat."""
    if line is None:
        return "flat"
    # slope > 0 = rising = bullish, < 0 = falling = bearish
    # Normalize: is slope meaningful relative to price?
    if abs(line.slope) < 1e-6:
        return "flat"
    return "bullish" if line.slope > 0 else "bearish"


def analyze_timeframe(
    df: pd.DataFrame,
    label: str,
    pivot_left: int = 3,
    pivot_right: int = 3,
    top_n_wicks: int = 6,
    min_pivots: int = 3,
    lookback_bars: int = 200,
    adx_trend_threshold: float = 25.0,
    realized_vol_window: int = 20,
) -> TimeframeChannel:
    """Run wick channel + regime analysis on a single timeframe's data."""
    n = len(df)
    if n < 20:
        # Not enough data — return neutral
        return TimeframeChannel(
            label=label,
            channel=WickChannel(),
            regime="chop",
            close=0.0,
            ema9=0.0,
            ema21=0.0,
            slope_dir="flat",
        )

    close_now = float(df["close"].iloc[-1])
    ema9 = float(_calc_ema(df["close"], 9).iloc[-1])
    ema21 = float(_calc_ema(df["close"], 21).iloc[-1])

    # ATR
    atr_vals = atr(df, 14)
    atr_val = float(atr_vals.iloc[-1]) if len(atr_vals) > 0 else 0.0

    # Adjust lookback for higher timeframes
    if label in ("MONTHLY", "WEEKLY"):
        effective_lookback = min(lookback_bars, n - 10)
    elif label == "DAILY":
        effective_lookback = min(120, n - 10)
    else:
        # Intraday (15m, 30m): shorter lookback for recent channel
        effective_lookback = min(50, n - 10)

    # Detect wick channels
    channel = detect_wick_channels(
        df,
        left=pivot_left,
        right=pivot_right,
        top_n_wicks=top_n_wicks,
        min_pivots=min_pivots,
        lookback_bars=effective_lookback,
        atr_value=atr_val,
    )

    # Regime classification
    regime_raw = classify(df, adx_trend_threshold, realized_vol_window)
    # Normalize regime names
    if regime_raw == "trend":
        # Determine up or down from EMA position
        if close_now > ema21:
            regime = "trend_up"
        else:
            regime = "trend_down"
    else:
        regime = regime_raw  # chop or shock

    # Slope direction from resistance line (dominant trendline)
    # If no resistance, use support slope
    if channel.resistance is not None:
        slope_dir = _slope_direction(channel.resistance)
    elif channel.support is not None:
        slope_dir = _slope_direction(channel.support)
    else:
        slope_dir = "flat"

    return TimeframeChannel(
        label=label,
        channel=channel,
        regime=regime,
        close=close_now,
        ema9=ema9,
        ema21=ema21,
        slope_dir=slope_dir,
    )


def multi_timeframe_analysis(
    dataframes: dict[str, pd.DataFrame],
    pivot_left: int = 3,
    pivot_right: int = 3,
    top_n_wicks: int = 6,
    min_pivots: int = 3,
    lookback_bars: int = 200,
    adx_trend_threshold: float = 25.0,
    realized_vol_window: int = 20,
) -> MultiTFResult:
    """Run top-down multi-timeframe analysis.

    `dataframes` maps timeframe label → OHLCV DataFrame.
    Required keys: "1mo", "1wk", "1d", "30m", "15m"
    """
    result = MultiTFResult()

    # Analyze each timeframe
    for tf_label, df in dataframes.items():
        cfg = INTERVAL_MAP.get(tf_label, {})
        label = cfg.get("label", tf_label)
        result.frames[tf_label] = analyze_timeframe(
            df, label, pivot_left, pivot_right,
            top_n_wicks, min_pivots, lookback_bars,
            adx_trend_threshold, realized_vol_window,
        )

    # ---- MONTHLY BIAS (the anchor) ----
    monthly = result.frames.get("1mo")
    if monthly is not None:
        result.monthly_bias = monthly.bias
    else:
        # Fallback: use weekly
        weekly = result.frames.get("1wk")
        if weekly is not None:
            result.monthly_bias = weekly.bias

    # ---- ALIGNMENT SCORE ----
    # How many timeframes agree with the monthly bias?
    biases = []
    for tf in ["1mo", "1wk", "1d", "30m", "15m"]:
        f = result.frames.get(tf)
        if f is not None:
            biases.append(f.bias)

    if biases and result.monthly_bias != "chop":
        agreeing = sum(1 for b in biases if b == result.monthly_bias)
        result.alignment_score = agreeing / len(biases)
    else:
        # Choppy monthly — no strong alignment
        result.alignment_score = 0.0

    # ---- TRADE DIRECTION ----
    # Simple rule: follow monthly bias, boosted by alignment
    if result.monthly_bias == "bull":
        result.trade_direction = "long_hou"
        result.conviction = 0.3 + (result.alignment_score * 0.5)
    elif result.monthly_bias == "bear":
        result.trade_direction = "long_hod"
        result.conviction = 0.3 + (result.alignment_score * 0.5)
    else:
        result.trade_direction = "flat"
        result.conviction = 0.1

    # Boost conviction if 30m has a breakout aligned with monthly
    tf_30m = result.frames.get("30m")
    tf_15m = result.frames.get("15m")

    if tf_30m and result.trade_direction != "flat":
        ch30 = tf_30m.channel
        if result.trade_direction == "long_hou" and ch30.break_up:
            result.conviction = min(1.0, result.conviction + 0.2)
        if result.trade_direction == "long_hod" and ch30.break_down:
            result.conviction = min(1.0, result.conviction + 0.2)

    # 15m confirmation
    if tf_15m and result.trade_direction != "flat":
        ch15 = tf_15m.channel
        if result.trade_direction == "long_hou" and (ch15.break_up or ch15.near_support):
            result.conviction = min(1.0, result.conviction + 0.1)
        if result.trade_direction == "long_hod" and (ch15.break_down or ch15.near_resistance):
            result.conviction = min(1.0, result.conviction + 0.1)

    return result