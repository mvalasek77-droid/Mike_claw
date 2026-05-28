"""Micro trendline detection on 1-minute and sub-minute bars.

Builds real-time up/down trendlines from micro pivot highs/lows,
then signals:
  - LONG when price bounces off micro UPTREND line (support)
  - SHORT when price bounces off micro DOWNTREND line (resistance)
  - BREAKOUT when price breaks through the trendline

These are the fastest signals — used by micro_scalp strategy
to catch 30-second to 5-minute moves.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import List, Optional, Tuple

import numpy as np
import pandas as pd

from ..data.feed import fetch
from ..ta.indicators import atr


@dataclass
class MicroTrendLine:
    """A single micro trendline."""
    slope: float            # $/bar
    intercept: float        # price at origin bar
    direction: str          # "up" or "down"
    start_bar: int          # index of first pivot
    end_bar: int            # index of second pivot (or last bar)
    touches: int            # number of pivot touches forming this line
    strength: float         # 0-1, based on touches + time alive

    def value_at(self, bar_index: int) -> float:
        """Price level of trendline at a given bar."""
        return self.intercept + self.slope * (bar_index - self.start_bar)

    def distance_pct(self, price: float, bar_index: int) -> float:
        """How far price is from trendline, as % of price."""
        line_val = self.value_at(bar_index)
        return (price - line_val) / price * 100


@dataclass
class MicroTrendResult:
    """Result of micro trendline analysis."""
    uptrend_lines: List[MicroTrendLine] = field(default_factory=list)
    downtrend_lines: List[MicroTrendLine] = field(default_factory=list)
    nearest_support: Optional[float] = None   # price level
    nearest_resistance: Optional[float] = None
    price: float = 0.0
    position: str = "mid"      # "above_all", "below_all", "between", "at_support", "at_resistance", "approaching_support", "approaching_resistance"
    breakout: Optional[str] = None  # "bullish_break" or "bearish_break"
    bounce: Optional[str] = None   # "support_bounce" or "resistance_reject"
    trend: str = "flat"         # "up", "down", or "flat" — based on channel slope


def _find_micro_pivots(
    highs: np.ndarray,
    lows: np.ndarray,
    left: int = 2,
    right: int = 2,
) -> Tuple[List[int], List[int]]:
    """Find micro pivot highs and lows using rolling window.

    A pivot high = bar where high[i] > all highs in [i-left, i+right]
    A pivot low  = bar where low[i]  < all lows  in [i-left, i+right]
    """
    n = len(highs)
    pivot_highs = []
    pivot_lows = []

    for i in range(left, n - right):
        # Check pivot high
        is_high = True
        for j in range(i - left, i + right + 1):
            if j != i and highs[j] >= highs[i]:
                is_high = False
                break
        if is_high:
            pivot_highs.append(i)

        # Check pivot low
        is_low = True
        for j in range(i - left, i + right + 1):
            if j != i and lows[j] <= lows[i]:
                is_low = False
                break
        if is_low:
            pivot_lows.append(i)

    return pivot_highs, pivot_lows


def _fit_trendline(
    pivot_indices: List[int],
    prices: np.ndarray,
    direction: str,
    max_bars_back: int = 60,
) -> List[MicroTrendLine]:
    """Fit trendlines through consecutive pivot points.

    For uptrend: connect pivot lows (rising support)
    For downtrend: connect pivot highs (falling resistance)
    """
    if len(pivot_indices) < 2:
        return []

    lines = []
    n = len(prices)

    # Only use recent pivots
    recent = [i for i in pivot_indices if i >= n - max_bars_back]
    if len(recent) < 2:
        return []

    # Fit lines from pairs of pivots
    # Try consecutive pairs and also skip pairs (for stronger lines)
    for start_idx in range(len(recent)):
        for end_idx in range(start_idx + 1, min(start_idx + 4, len(recent))):
            i1 = recent[start_idx]
            i2 = recent[end_idx]
            p1 = prices[i1]
            p2 = prices[i2]

            # Calculate slope
            dx = i2 - i1
            if dx == 0:
                continue
            slope = (p2 - p1) / dx

            # Validate direction
            if direction == "up" and slope <= 0:
                continue
            if direction == "down" and slope >= 0:
                continue

            # Count how many other pivots touch this line (within tolerance)
            intercept = p1
            touches = 2  # the two endpoints
            tolerance = abs(slope) * 2 + 0.02  # $0.02 base + slope-based

            for k in recent:
                if k == i1 or k == i2:
                    continue
                line_val = intercept + slope * (k - i1)
                if abs(prices[k] - line_val) < tolerance:
                    touches += 1

            # Strength based on touches and recency
            bars_alive = n - i1
            recency_bonus = max(0, 1.0 - bars_alive / max_bars_back)
            strength = min(1.0, (touches / 5) * 0.6 + recency_bonus * 0.4)

            lines.append(MicroTrendLine(
                slope=slope,
                intercept=intercept,
                direction=direction,
                start_bar=i1,
                end_bar=i2,
                touches=touches,
                strength=strength,
            ))

    # Sort by strength, return best ones
    lines.sort(key=lambda l: l.strength, reverse=True)
    return lines[:5]


def detect_micro_trendlines(
    ticker: str = "CL=F",
    bar_interval: str = "1m",
    days_back: int = 1,
    pivot_left: int = 2,
    pivot_right: int = 2,
    touch_threshold_pct: float = 0.08,  # 0.08% = ~$0.08 on $100 oil
) -> MicroTrendResult:
    """Detect micro trendlines on 1-minute bars.

    Returns uptrend lines (support) and downtrend lines (resistance),
    plus nearest levels and current position vs trendlines.
    """
    try:
        df = fetch(ticker, bar_interval, days_back)
    except Exception as e:
        return MicroTrendResult(price=0.0, position="no_data")

    if len(df) < 30:
        return MicroTrendResult(price=0.0, position="no_data")

    highs = df["high"].values
    lows = df["low"].values
    closes = df["close"].values
    n = len(df)
    p = float(closes[-1])

    # Detect pivots
    pivot_highs, pivot_lows = _find_micro_pivots(highs, lows, pivot_left, pivot_right)

    # Build downtrend lines from pivot HIGHS (resistance)
    down_lines = _fit_trendline(pivot_highs, highs, "down", max_bars_back=60)

    # Build uptrend lines from pivot LOWS (support)
    up_lines = _fit_trendline(pivot_lows, lows, "up", max_bars_back=60)

    result = MicroTrendResult(
        uptrend_lines=up_lines,
        downtrend_lines=down_lines,
        price=p,
    )

    # Find nearest support (highest uptrend line below price)
    # Also find broken downtrend lines above price (support after breakout)
    support_levels = []
    for line in up_lines:
        val = line.value_at(n - 1)
        if val <= p:
            support_levels.append((val, line, "uptrend"))
    # Downtrend lines that price broke above = new support
    for line in down_lines:
        val = line.value_at(n - 1)
        if val <= p:
            support_levels.append((val, line, "broken_downtrend"))

    if support_levels:
        support_levels.sort(key=lambda x: x[0], reverse=True)  # closest to price first
        result.nearest_support = support_levels[0][0]

    # Find nearest resistance (lowest downtrend line above price)
    # Also find broken uptrend lines below price (resistance after breakdown)
    resist_levels = []
    for line in down_lines:
        val = line.value_at(n - 1)
        if val >= p:
            resist_levels.append((val, line, "downtrend"))
    # Uptrend lines that price broke below = new resistance
    for line in up_lines:
        val = line.value_at(n - 1)
        if val >= p:
            resist_levels.append((val, line, "broken_uptrend"))

    if resist_levels:
        resist_levels.sort(key=lambda x: x[0])  # closest to price first
        result.nearest_resistance = resist_levels[0][0]

    # Determine position
    at_sup = result.nearest_support and abs(p - result.nearest_support) / p < touch_threshold_pct / 100
    at_res = result.nearest_resistance and abs(p - result.nearest_resistance) / p < touch_threshold_pct / 100

    if at_sup:
        result.position = "at_support"
        # Bounce = price at support + last bar closed up OR has rejection wick
        if n >= 2:
            body = abs(closes[-1] - df["open"].values[-1])
            lower_wick = min(closes[-1], df["open"].values[-1]) - lows[-1]
            # Bounce if: green candle, or hammer wick at support
            if closes[-1] > df["open"].values[-1]:  # green bar
                result.bounce = "support_bounce"
            elif lower_wick > body * 1.5 and body > 0:  # lower wick rejection
                result.bounce = "support_bounce"
            elif n >= 3 and lows[-2] <= result.nearest_support + 0.05 and closes[-1] > closes[-2]:
                # Prior bar tested support, current bar bouncing
                result.bounce = "support_bounce"
    elif at_res:
        result.position = "at_resistance"
        if n >= 2:
            body = abs(closes[-1] - df["open"].values[-1])
            upper_wick = highs[-1] - max(closes[-1], df["open"].values[-1])
            if closes[-1] < df["open"].values[-1]:  # red bar at resistance
                result.bounce = "resistance_reject"
            elif upper_wick > body * 1.5 and body > 0:  # upper wick rejection
                result.bounce = "resistance_reject"
            elif n >= 3 and highs[-2] >= result.nearest_resistance - 0.05 and closes[-1] < closes[-2]:
                result.bounce = "resistance_reject"
    elif result.nearest_support and result.nearest_resistance:
        dist_sup = abs(p - result.nearest_support) / p * 100
        dist_res = abs(p - result.nearest_resistance) / p * 100
        if dist_sup < touch_threshold_pct * 3 and not at_sup:
            result.position = "approaching_support"
        elif dist_res < touch_threshold_pct * 3 and not at_res:
            result.position = "approaching_resistance"
        else:
            result.position = "between"
    elif not result.nearest_support:
        result.position = "below_all"
    else:
        result.position = "above_all"

    # Breakout detection: price just crossed above resistance or below support
    if n >= 3:
        prev_close = closes[-2]
        if result.nearest_resistance:
            res_val = result.nearest_resistance
            if prev_close < res_val and p > res_val:
                result.breakout = "bullish_break"
        if result.nearest_support:
            sup_val = result.nearest_support
            if prev_close > sup_val and p < sup_val:
                result.breakout = "bearish_break"

    # ── Compute channel slope / trend direction ──
    # If both support and resistance are rising → uptrend
    # If both falling → downtrend
    # Otherwise → flat
    if result.uptrend_lines and result.downtrend_lines:
        # Best uptrend and downtrend slopes
        best_up_slope = result.uptrend_lines[0].slope if result.uptrend_lines else 0
        best_down_slope = result.downtrend_lines[0].slope if result.downtrend_lines else 0

        # Channel slope = average of support rise + resistance rise
        # Support slope = uptrend line slope (positive = rising)
        # Downtrend slope = negative (lines go down), but resistance level rising means downtrend slope is LESS negative
        net_slope = best_up_slope + best_down_slope  # both + means uptrend widening up

        # If support is rising AND resistance is rising or flat → uptrend
        if best_up_slope > 0.005 and best_down_slope > -0.005:
            result.trend = "up"
        elif best_down_slope < -0.01 and best_up_slope < 0.005:
            result.trend = "down"
        else:
            result.trend = "flat"
    elif result.uptrend_lines:
        best_up_slope = result.uptrend_lines[0].slope
        result.trend = "up" if best_up_slope > 0.005 else "flat"
    elif result.downtrend_lines:
        best_down_slope = result.downtrend_lines[0].slope
        result.trend = "down" if best_down_slope < -0.01 else "flat"

    return result


def format_micro_trendlines(result: MicroTrendResult) -> str:
    """Human-readable summary of micro trendline state."""
    lines = [f"📊 WTI ${result.price:.2f} | Position: {result.position}"]

    if result.nearest_support:
        dist = (result.price - result.nearest_support) / result.price * 100
        lines.append(f"🟢 Support: ${result.nearest_support:.2f} ({dist:.2f}% below)")

    if result.nearest_resistance:
        dist = (result.nearest_resistance - result.price) / result.price * 100
        lines.append(f"🔴 Resistance: ${result.nearest_resistance:.2f} ({dist:.2f}% above)")

    if result.bounce:
        lines.append(f"⚡ BOUNCE: {result.bounce}")

    if result.breakout:
        lines.append(f"💥 BREAKOUT: {result.breakout}")

    # Show trendline details
    for tl in result.uptrend_lines[:2]:
        val = tl.value_at(len(result.uptrend_lines))  # approximate
        lines.append(f"  ↑ trend: slope=${tl.slope:.4f}/bar, {tl.touches} touches, str={tl.strength:.0%}")

    for tl in result.downtrend_lines[:2]:
        lines.append(f"  ↓ trend: slope=${tl.slope:.4f}/bar, {tl.touches} touches, str={tl.strength:.0%}")

    return "\n".join(lines)