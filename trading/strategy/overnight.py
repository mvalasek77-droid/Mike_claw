"""Overnight / after-hours directional signal engine.

WTI trades ~23hrs/day on CME Globex (6:00 PM - 5:00 PM ET next day).
TSX-listed HOU/HOD only trade 9:30-16:00 ET, but they GAP OPEN based
on what crude did overnight.

This module:
  1. Runs every 16 hours during after-hours (16:00-9:30 ET)
  2. Uses daily + weekly + monthly wick channels (macro structure)
  3. Tracks WTI price vs daily/weekly support & resistance
  4. Emits a single directional signal: "BUY HOU AT OPEN" or
     "BUY HOD AT OPEN" with confidence and key levels

The insight: most of the BIG money on leveraged ETFs comes from
overnight gaps. If crude breaks weekly resistance at 10 PM,
HOU will gap up 2x at 9:30 AM TSX open. You need to be ready.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

import numpy as np
import pandas as pd

from ..data.feed import fetch
from ..ta.indicators import atr, realized_vol
from ..ta.multi_tf import (
    INTERVAL_MAP, MultiTFResult, TimeframeChannel,
    analyze_timeframe, multi_timeframe_analysis,
)
from ..ta.wick_channels import WickChannel, detect_wick_channels


@dataclass
class OvernightSignal:
    """Directional signal for after-hours / pre-open positioning."""
    direction: str           # "long_hou", "long_hod", "flat"
    confidence: float         # 0-1
    wti_price: float
    wti_vs_daily_support: float    # distance (positive = above)
    wti_vs_daily_resistance: float  # distance (negative = below)
    wti_vs_weekly_support: float
    wti_vs_weekly_resistance: float
    daily_bias: str
    weekly_bias: str
    monthly_bias: str
    gap_expectation: str     # "gap_up", "gap_down", "no_gap"
    key_level: float         # most important S/R level to watch
    rationale: str

    def summary(self) -> str:
        return (
            f"{self.direction.upper()} @ {self.confidence:.0%} | "
            f"WTI ${self.wti_price:.2f} | "
            f"Daily: {self.daily_bias} Weekly: {self.weekly_bias} Monthly: {self.monthly_bias} | "
            f"Key: ${self.key_level:.2f}"
        )


def overnight_analysis(
    underlying_ticker: str = "CL=F",
    longs_ticker: str = "HOU.TO",
    shorts_ticker: str = "HOD.TO",
    pivot_left: int = 3,
    pivot_right: int = 3,
    top_n_wicks: int = 6,
    min_pivots: int = 3,
    adx_trend_threshold: float = 25.0,
    realized_vol_window: int = 20,
    bar_interval: str = "15m",
    history_days: int = 60,
) -> OvernightSignal:
    """Compute after-hours directional signal using macro timeframes.

    Uses daily, weekly, monthly channels only (no intraday noise).
    Current WTI price vs these channels → gap-up or gap-down prediction.
    """
    # Fetch macro timeframes
    dfs = {}
    for tf in ("1mo", "1wk", "1d"):
        cfg = INTERVAL_MAP.get(tf, {})
        interval = cfg.get("interval", tf)
        lookback = cfg.get("lookback_days", 365)
        try:
            dfs[tf] = fetch(underlying_ticker, interval, lookback)
        except Exception:
            pass

    # Also fetch current WTI (1m or 5m for current price)
    try:
        wti_5m = fetch(underlying_ticker, "5m", 5)  # just 5 days for recent price
    except Exception:
        wti_5m = dfs.get("1d")

    wti_price = 0.0
    if wti_5m is not None and len(wti_5m) > 0:
        wti_price = float(wti_5m["close"].iloc[-1])
    elif dfs.get("1d") is not None and len(dfs["1d"]) > 0:
        wti_price = float(dfs["1d"]["close"].iloc[-1])

    # Analyze each macro timeframe
    frames = {}
    for tf, df in dfs.items():
        cfg = INTERVAL_MAP.get(tf, {})
        label = cfg.get("label", tf.upper())
        frames[tf] = analyze_timeframe(
            df, label, pivot_left, pivot_right,
            top_n_wicks, min_pivots, 200,
            adx_trend_threshold, realized_vol_window,
        )

    monthly = frames.get("1mo")
    weekly = frames.get("1wk")
    daily = frames.get("1d")

    monthly_bias = monthly.bias if monthly else "chop"
    weekly_bias = weekly.bias if weekly else "chop"
    daily_bias = daily.bias if daily else "chop"

    # ── Key levels from wick channels ──
    def _line_at_end(channel: WickChannel) -> tuple[Optional[float], Optional[float]]:
        """Get support and resistance price at the last bar."""
        sup = channel.support.at(channel.support.anchor_idx + len(channel.support.__dataclass_fields__)) if channel.support else None
        # Simpler: use the last close vs channel position
        return (
            wti_price - channel.price_vs_support if channel.support else None,
            wti_price - channel.price_vs_resistance if channel.resistance else None,
        )

    # Distances from current price to channel lines
    d_sup_dist = daily.channel.price_vs_support if daily and daily.channel.support else 0.0
    d_res_dist = daily.channel.price_vs_resistance if daily and daily.channel.resistance else 0.0
    w_sup_dist = weekly.channel.price_vs_support if weekly and weekly.channel.support else 0.0
    w_res_dist = weekly.channel.price_vs_resistance if weekly and weekly.channel.resistance else 0.0

    # Calculate actual S/R prices
    # price_vs_support = close - support_value, so support = close - price_vs_support
    d_sup = wti_price - d_sup_dist if daily and daily.channel.support else None
    d_res = wti_price - d_res_dist if daily and daily.channel.resistance else None
    w_sup = wti_price - w_sup_dist if weekly and weekly.channel.support else None
    w_res = wti_price - w_res_dist if weekly and weekly.channel.resistance else None

    # ── Signal logic ──
    parts = []
    direction = "flat"
    confidence = 0.0
    gap_expectation = "no_gap"
    key_level = wti_price

    # Count bullish/bearish votes from macro timeframes
    bull_votes = sum(1 for b in [monthly_bias, weekly_bias, daily_bias] if b == "bull")
    bear_votes = sum(1 for b in [monthly_bias, weekly_bias, daily_bias] if b == "bear")
    parts.append(f"votes: {bull_votes}B/{bear_votes}S")

    # ATR for context
    atr_daily = 0.0
    if dfs.get("1d") is not None and len(dfs["1d"]) > 20:
        atr_daily = float(atr(dfs["1d"], 14).iloc[-1] or 0.0)

    # ── BREAKOUT DETECTION (after-hours) ──
    daily_breakout_up = daily and daily.channel.break_up
    daily_breakout_dn = daily and daily.channel.break_down
    weekly_breakout_up = weekly and weekly.channel.break_up
    weekly_breakout_dn = weekly and weekly.channel.break_down

    # Daily breakout above resistance + bull macro = GAP UP
    if daily_breakout_up and bull_votes >= 2:
        direction = "long_hou"
        confidence = 0.70 + (0.10 * bull_votes)
        gap_expectation = "gap_up"
        key_level = d_res if d_res else wti_price
        parts.append(f"daily_break_up+{bull_votes}bull=STRONG_GAP_UP")

    # Daily breakout below support + bear macro = GAP DOWN
    elif daily_breakout_dn and bear_votes >= 2:
        direction = "long_hod"
        confidence = 0.70 + (0.10 * bear_votes)
        gap_expectation = "gap_down"
        key_level = d_sup if d_sup else wti_price
        parts.append(f"daily_break_dn+{bear_votes}bear=STRONG_GAP_DOWN")

    # Weekly breakout (mega signal)
    elif weekly_breakout_up and bull_votes >= 1:
        direction = "long_hou"
        confidence = 0.80
        gap_expectation = "gap_up"
        key_level = w_res if w_res else wti_price
        parts.append("weekly_break_up=MAJOR_GAP_UP")

    elif weekly_breakout_dn and bear_votes >= 1:
        direction = "long_hod"
        confidence = 0.80
        gap_expectation = "gap_down"
        key_level = w_sup if w_sup else wti_price
        parts.append("weekly_break_dn=MAJOR_GAP_DOWN")

    # ── APPROACHING LEVELS (moderate confidence) ──
    elif daily and daily.channel.near_resistance and daily.channel.between_lines:
        if bull_votes >= 2:
            # Near resistance + bull bias → likely break
            direction = "long_hou"
            confidence = 0.45 + (0.08 * bull_votes)
            key_level = d_res if d_res else wti_price
            parts.append("near_daily_res+bull=likely_break")
        else:
            # Near resistance + mixed/bear → fade
            direction = "long_hod"
            confidence = 0.35
            key_level = d_res if d_res else wti_price
            parts.append("near_daily_res+bearish=fade")

    elif daily and daily.channel.near_support and daily.channel.between_lines:
        if bear_votes >= 2:
            direction = "long_hod"
            confidence = 0.45 + (0.08 * bear_votes)
            key_level = d_sup if d_sup else wti_price
            parts.append("near_daily_sup+resist_bear=likely_break")
        else:
            direction = "long_hou"
            confidence = 0.35
            key_level = d_sup if d_sup else wti_price
            parts.append("near_daily_sup+other=bounce")

    # ── MACRO TREND (no channel edge, but clear direction) ──
    elif bull_votes >= 2:
        direction = "long_hou"
        confidence = 0.25
        parts.append("macro_bull_no_channel_edge")
    elif bear_votes >= 2:
        direction = "long_hod"
        confidence = 0.25
        parts.append("macro_bear_no_channel_edge")

    # ── CHOP / no edge ──
    else:
        direction = "flat"
        confidence = 0.0
        parts.append("no_overnight_edge")

    # Gap expectation refinement
    if direction != "flat" and atr_daily > 0:
        # If price is > 0.5*ATR from nearest S/R, expect smaller gap
        min_dist = min(abs(d_sup_dist), abs(d_res_dist))
        if abs(min_dist) > atr_daily * 1.5 and gap_expectation == "no_gap":
            gap_expectation = "small_gap"

    return OvernightSignal(
        direction=direction,
        confidence=min(1.0, confidence),
        wti_price=wti_price,
        wti_vs_daily_support=d_sup_dist,
        wti_vs_daily_resistance=d_res_dist,
        wti_vs_weekly_support=w_sup_dist,
        wti_vs_weekly_resistance=w_res_dist,
        daily_bias=daily_bias,
        weekly_bias=weekly_bias,
        monthly_bias=monthly_bias,
        gap_expectation=gap_expectation,
        key_level=key_level,
        rationale=" | ".join(parts),
    )