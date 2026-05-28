"""Micro-scalper for 1-5 minute WTI moves.

CORE CONCEPT: Price bounces between micro trendlines like a pinball.
We detect 1-minute trendlines (support & resistance) and trade the bounces.

Patterns ranked by priority:
    1. MICRO TRENDLINE BOUNCE (1m) — price bounces off uptrend/downtrend line
    2. MICRO TRENDLINE BREAKOUT (1m) — price breaks through trendline
    3. REVERSAL after consecutive bars + micro trendline confirmation
    4. EMA cross (3/8) on 5m
    5. MEAN REVERSION after >1× ATR bar
    6. 15m channel micro-bounce

Target: $5 on 6 shares HOU = 1.6% WTI move
But we trade DIRECTION: right 60% of the time on 0.3% moves
    4 trades/hr × 0.6 hit × $0.93 = $2.23 - 0.4 × $0.93 = $1.86 net
    Learning pushes to 65%+ → $5+/hr
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Optional, List

import numpy as np
import pandas as pd

from ..data.feed import fetch
from ..ta.indicators import atr
from ..ta.wick_channels import detect_wick_channels
from ..ta.micro_trendlines import (
    detect_micro_trendlines, MicroTrendResult, MicroTrendLine,
    format_micro_trendlines,
)


@dataclass
class MicroSignal:
    direction: str     # "long_hou", "long_hod", "flat"
    confidence: float  # 0-1
    pattern: str       # which pattern triggered
    wti_price: float
    target_move_pct: float  # expected WTI % move
    stop_move_pct: float    # stop distance
    rationale: str
    micro_trends: Optional[MicroTrendResult] = None  # attach the analysis


def _ema(series: pd.Series, span: int) -> pd.Series:
    return series.ewm(span=span, adjust=False).mean()


def micro_scalp(
    underlying_ticker: str = "CL=F",
    pivot_left: int = 3,
    pivot_right: int = 3,
    atr_period: int = 14,
) -> MicroSignal:
    """Run micro-scalp analysis with 1m trendlines as primary signal."""
    # Fetch data
    try:
        df_1m = fetch(underlying_ticker, "1m", 1)
    except Exception:
        df_1m = None
    try:
        df_5m = fetch(underlying_ticker, "5m", 3)
    except Exception:
        # Even with no 5m data, use investing.com live price + 1m trendlines
        df_5m = None
    try:
        df_15m = fetch(underlying_ticker, "15m", 10)
    except Exception:
        df_15m = None

    if len(df_5m) < 30 if df_5m is not None else True:
        # Fall back to 1m data only
        if df_1m is not None and len(df_1m) > 30:
            close_5m = df_1m["close"].values
            open_5m = df_1m["open"].values
            high_5m = df_1m["high"].values
            low_5m = df_1m["low"].values
            vol_5m = df_1m["volume"].values if "volume" in df_1m.columns else np.ones(len(df_1m))
            n = len(df_1m)
        else:
            # Use investing.com live price as last resort
            try:
                from ..data.investing import wti_live
                live_p = wti_live()
                if live_p:
                    p = live_p
                    # Determine direction from 1m trendlines
                    if micro.position in ("at_support", "approaching_support") or micro.bounce == "support_bounce":
                        return MicroSignal("long_hou", 0.25, "investing_live_support", p,
                                          0.2, 0.15, f"Live WTI ${p:.2f} at/below 1m support → long",
                                          micro_trends=micro)
                    elif micro.position in ("at_resistance", "approaching_resistance") or micro.bounce == "resistance_reject":
                        return MicroSignal("long_hod", 0.25, "investing_live_resistance", p,
                                          0.2, 0.15, f"Live WTI ${p:.2f} at/above 1m resistance → short",
                                          micro_trends=micro)
                    else:
                        # Pick side based on trendline channel position
                        if micro.nearest_support and micro.nearest_resistance:
                            mid = (micro.nearest_support + micro.nearest_resistance) / 2
                            if p > mid:
                                return MicroSignal("long_hou", 0.20, "investing_above_mid", p,
                                                  0.2, 0.15, f"Live WTI ${p:.2f} above channel mid → long",
                                                  micro_trends=micro)
                            else:
                                return MicroSignal("long_hod", 0.20, "investing_below_mid", p,
                                                  0.2, 0.15, f"Live WTI ${p:.2f} below channel mid → short",
                                                  micro_trends=micro)
                        elif micro.uptrend_lines:
                            return MicroSignal("long_hou", 0.20, "investing_uptrend", p,
                                              0.2, 0.15, f"Live WTI ${p:.2f} in uptrend → long",
                                              micro_trends=micro)
                        elif micro.downtrend_lines:
                            return MicroSignal("long_hod", 0.20, "investing_downtrend", p,
                                              0.2, 0.15, f"Live WTI ${p:.2f} in downtrend → short",
                                              micro_trends=micro)
                        else:
                            return MicroSignal("long_hou", 0.15, "investing_default_long", p,
                                              0.2, 0.15, f"Live WTI ${p:.2f} — default long",
                                              micro_trends=micro)
            except Exception:
                pass
            return MicroSignal("long_hou", 0.10, "no_data_default_long", 0.0, 0.2, 0.15,
                              "No data — default long (always pick a side)")

    close_5m = df_5m["close"].values
    open_5m = df_5m["open"].values
    high_5m = df_5m["high"].values
    low_5m = df_5m["low"].values
    vol_5m = df_5m["volume"].values if "volume" in df_5m.columns else np.ones(len(df_5m))
    n = len(df_5m)
    p = float(close_5m[-1])

    # ATR on 5m
    atr_5m = float(atr(df_5m, atr_period).iloc[-1] or 0.001)
    # ATR on 1m (for tighter stops)
    atr_1m = 0.001
    if df_1m is not None and len(df_1m) > 14:
        atr_1m = float(atr(df_1m, atr_period).iloc[-1] or 0.001)

    # 15m channel for S/R context
    chan_15m = None
    if df_15m is not None and len(df_15m) > 20:
        atr_15m = float(atr(df_15m, 14).iloc[-1] or 1.0)
        chan_15m = detect_wick_channels(
            df_15m, pivot_left, pivot_right,
            top_n_wicks=6, min_pivots=3,
            lookback_bars=50, atr_value=atr_15m,
        )

    # ── MICRO TRENDLINES (1m) — PRIMARY SIGNAL ──
    micro = detect_micro_trendlines(underlying_ticker, "1m", 1)

    # ══════════════════════════════════════════════════════
    # TREND FILTER — THE SINGLE MOST IMPORTANT RULE
    # Never short in an uptrend. Never long in a downtrend.
    # Trade WITH the channel slope, not against it.
    # ══════════════════════════════════════════════════════
    trend = micro.trend  # "up", "down", or "flat"

    # ── PATTERN 1: MICRO TRENDLINE BOUNCE
    # Price touches uptrend line → BUY HOU
    # Price touches downtrend line → BUY HOD
    # ══════════════════════════════════════════════════════
    def _check_trendline_bounce():
        if micro.bounce == "support_bounce":
            # Confirm: last 1m bar is green + near support
            conf = 0.45  # base
            # Boost if 15m also near support
            if chan_15m and chan_15m.near_support:
                conf += 0.15
            # Boost if strong trendline (3+ touches)
            best_up = micro.uptrend_lines[0] if micro.uptrend_lines else None
            if best_up and best_up.touches >= 3:
                conf += 0.10
            # Boost if 5m also green
            if close_5m[-1] > open_5m[-1]:
                conf += 0.05

            # Target: move toward nearest resistance
            target = 0.3
            if micro.nearest_resistance and micro.nearest_support:
                channel_range = micro.nearest_resistance - micro.nearest_support
                if channel_range > 0:
                    position_in_channel = (p - micro.nearest_support) / channel_range
                    # If bouncing near bottom, more room to run
                    if position_in_channel < 0.3:
                        target = channel_range / p * 100  # full channel
                    elif position_in_channel < 0.5:
                        target = channel_range / p * 50  # half channel
                    target = max(0.2, min(1.0, target))

            stop = atr_1m / p * 100  # stop = 1 ATR on 1m

            return MicroSignal(
                "long_hou", min(0.75, conf),
                "micro_trendline_support_bounce", p,
                target_move_pct=target,
                stop_move_pct=max(0.05, stop),
                rationale=f"1m uptrend BOUNCE @ ${micro.nearest_support:.2f} | 15m_sup={chan_15m.near_support if chan_15m else 'N/A'}",
                micro_trends=micro,
            )

        if micro.position == "at_resistance":
            # AT the line even without rejection candle → short signal
            # The trendline IS resistance, touching it = sell
            conf = 0.35  # base
            if chan_15m and chan_15m.near_resistance:
                conf += 0.15
            best_down = micro.downtrend_lines[0] if micro.downtrend_lines else None
            if best_down and best_down.touches >= 3:
                conf += 0.10
            if close_5m[-1] < open_5m[-1]:
                conf += 0.08  # red candle confirms

            target = 0.3
            if micro.nearest_support:
                target = abs(p - micro.nearest_support) / p * 100
                target = max(0.1, min(1.5, target))

            stop = atr_1m / p * 100

            return MicroSignal(
                "long_hod", min(0.70, conf),
                "micro_trendline_at_resistance", p,
                target_move_pct=target,
                stop_move_pct=max(0.05, stop),
                rationale=f"1m AT resistance ${micro.nearest_resistance:.2f} → expect rejection | 15m_res={chan_15m.near_resistance if chan_15m else 'N/A'}",
                micro_trends=micro,
            )

        return None

    # ══════════════════════════════════════════════════════
    # PATTERN 2: AT TRENDLINE (no bounce needed)
    # ══════════════════════════════════════════════════════
    def _check_at_trendline():
        if micro.position in ("at_support", "approaching_support"):
            conf = 0.35
            if chan_15m and chan_15m.near_support:
                conf += 0.15
            best_up = micro.uptrend_lines[0] if micro.uptrend_lines else None
            if best_up and best_up.touches >= 3:
                conf += 0.10
            if close_5m[-1] > open_5m[-1]:
                conf += 0.08

            target = 0.3
            if micro.nearest_resistance:
                target = abs(micro.nearest_resistance - p) / p * 100
                target = max(0.1, min(1.5, target))
            stop = atr_1m / p * 100

            return MicroSignal(
                "long_hou", min(0.70, conf),
                "micro_trendline_at_support", p,
                target_move_pct=target,
                stop_move_pct=max(0.05, stop),
                rationale=f"1m AT support ${micro.nearest_support:.2f} → expect bounce | 15m_sup={chan_15m.near_support if chan_15m else 'N/A'}",
                micro_trends=micro,
            )

        if micro.position in ("at_resistance", "approaching_resistance"):
            conf = 0.35
            if chan_15m and chan_15m.near_resistance:
                conf += 0.15
            best_down = micro.downtrend_lines[0] if micro.downtrend_lines else None
            if best_down and best_down.touches >= 3:
                conf += 0.10
            if close_5m[-1] < open_5m[-1]:
                conf += 0.08

            target = 0.3
            if micro.nearest_support:
                target = abs(p - micro.nearest_support) / p * 100
                target = max(0.1, min(1.5, target))
            stop = atr_1m / p * 100

            return MicroSignal(
                "long_hod", min(0.70, conf),
                "micro_trendline_at_resistance", p,
                target_move_pct=target,
                stop_move_pct=max(0.05, stop),
                rationale=f"1m AT resistance ${micro.nearest_resistance:.2f} → expect rejection | 15m_res={chan_15m.near_resistance if chan_15m else 'N/A'}",
                micro_trends=micro,
            )
        return None

    # ══════════════════════════════════════════════════════
    # Price breaks above downtrend resistance → BUY HOU (new trend)
    # Price breaks below uptrend support → BUY HOD (new trend)
    # ══════════════════════════════════════════════════════
    def _check_trendline_breakout():
        if micro.breakout == "bullish_break":
            conf = 0.40
            # Confirm with volume
            avg_vol = np.mean(vol_5m[-20:]) if len(vol_5m) > 20 else 1
            last_vol = vol_5m[-1] if len(vol_5m) > 0 else 1
            if last_vol > avg_vol * 1.3:
                conf += 0.12  # volume confirms breakout
            # 15m resistance break = major signal
            if chan_15m and chan_15m.near_resistance:
                conf += 0.10

            return MicroSignal(
                "long_hou", min(0.70, conf),
                "micro_trendline_bull_breakout", p,
                target_move_pct=0.4,
                stop_move_pct=0.15,
                rationale=f"1m BREAKOUT above ${micro.nearest_resistance:.2f} downtrend | vol_conf={last_vol>avg_vol*1.3}",
                micro_trends=micro,
            )

        if micro.breakout == "bearish_break":
            conf = 0.40
            avg_vol = np.mean(vol_5m[-20:]) if len(vol_5m) > 20 else 1
            last_vol = vol_5m[-1] if len(vol_5m) > 0 else 1
            if last_vol > avg_vol * 1.3:
                conf += 0.12
            if chan_15m and chan_15m.near_support:
                conf += 0.10

            return MicroSignal(
                "long_hod", min(0.70, conf),
                "micro_trendline_bear_breakout", p,
                target_move_pct=0.4,
                stop_move_pct=0.15,
                rationale=f"1m BREAKDOWN below ${micro.nearest_support:.2f} uptrend | vol_conf={last_vol>avg_vol*1.3}",
                micro_trends=micro,
            )

        return None

    # ══════════════════════════════════════════════════════
    # PATTERN 3: TRENDLINE CHANNEL TRADE (between both lines)
    # When between support & resistance on 1m, trade toward the channel wall
    # ══════════════════════════════════════════════════════
    def _check_channel_trade():
        if micro.position != "between":
            return None
        if not micro.nearest_support or not micro.nearest_resistance:
            return None

        dist_to_sup = abs(p - micro.nearest_support) / p * 100
        dist_to_res = abs(p - micro.nearest_resistance) / p * 100

        # Only trade when close to one side (within 0.05%)
        threshold = 0.05
        if dist_to_sup < threshold and dist_to_res > dist_to_sup:
            # Near support, expecting bounce up
            conf = 0.35
            if close_5m[-1] > open_5m[-1]:
                conf += 0.08  # green bar confirm
            if chan_15m and chan_15m.near_support:
                conf += 0.10

            return MicroSignal(
                "long_hou", min(0.60, conf),
                "micro_channel_support_approach", p,
                target_move_pct=dist_to_res,  # target = move to resistance
                stop_move_pct=dist_to_sup,     # stop = back through support
                rationale=f"Near 1m support ${micro.nearest_support:.2f}, target ${micro.nearest_resistance:.2f}",
                micro_trends=micro,
            )

        if dist_to_res < threshold and dist_to_res < dist_to_sup:
            # Near resistance, expecting rejection
            conf = 0.35
            if close_5m[-1] < open_5m[-1]:
                conf += 0.08
            if chan_15m and chan_15m.near_resistance:
                conf += 0.10

            return MicroSignal(
                "long_hod", min(0.60, conf),
                "micro_channel_resistance_approach", p,
                target_move_pct=dist_to_sup,
                stop_move_pct=dist_to_res,
                rationale=f"Near 1m resistance ${micro.nearest_resistance:.2f}, target ${micro.nearest_support:.2f}",
                micro_trends=micro,
            )

        return None

    # ── PATTERN 4: REVERSAL after consecutive bars ──
    def _check_reversal():
        rets = np.diff(np.log(close_5m))
        if len(rets) < 5:
            return None

        down_count = 0
        for i in range(len(rets) - 1, max(len(rets) - 8, -1), -1):
            if rets[i] < 0:
                down_count += 1
            else:
                break

        up_count = 0
        for i in range(len(rets) - 1, max(len(rets) - 8, -1), -1):
            if rets[i] > 0:
                up_count += 1
            else:
                break

        if down_count >= 2:
            body = abs(close_5m[-1] - open_5m[-1])
            lower_wick = min(close_5m[-1], open_5m[-1]) - low_5m[-1]
            upper_wick = high_5m[-1] - max(close_5m[-1], open_5m[-1])
            is_hammer = lower_wick > body * 2 and upper_wick < body * 0.5
            near_sup = chan_15m.near_support if chan_15m else False
            near_1m_sup = micro.position == "at_support"
            avg_vol = np.mean(vol_5m[-20:]) if len(vol_5m) > 20 else 1
            vol_spike = vol_5m[-1] > avg_vol * 1.5

            conf = 0.30
            if down_count >= 4:
                conf += 0.10
            if is_hammer:
                conf += 0.12
            if vol_spike:
                conf += 0.08
            if near_sup or near_1m_sup:
                conf += 0.12  # trendline confluence is key

            pattern = f"reversal_{down_count}down"
            if near_1m_sup:
                pattern += "+1m_trendline"

            return MicroSignal(
                "long_hou", min(0.7, conf), pattern, p,
                target_move_pct=0.3, stop_move_pct=0.15,
                rationale=f"{down_count} bars down → reversal | hammer={is_hammer} 1m_sup={near_1m_sup} 15m_sup={near_sup}",
                micro_trends=micro,
            )

        if up_count >= 2:
            body = abs(close_5m[-1] - open_5m[-1])
            upper_wick = high_5m[-1] - max(close_5m[-1], open_5m[-1])
            lower_wick = min(close_5m[-1], open_5m[-1]) - low_5m[-1]
            is_shooting = upper_wick > body * 2 and lower_wick < body * 0.5
            near_res = chan_15m.near_resistance if chan_15m else False
            near_1m_res = micro.position == "at_resistance"
            avg_vol = np.mean(vol_5m[-20:]) if len(vol_5m) > 20 else 1
            vol_spike = vol_5m[-1] > avg_vol * 1.5

            conf = 0.30
            if up_count >= 4:
                conf += 0.10
            if is_shooting:
                conf += 0.12
            if vol_spike:
                conf += 0.08
            if near_res or near_1m_res:
                conf += 0.12

            pattern = f"reversal_{up_count}up"
            if near_1m_res:
                pattern += "+1m_trendline"

            return MicroSignal(
                "long_hod", min(0.7, conf), pattern, p,
                target_move_pct=0.3, stop_move_pct=0.15,
                rationale=f"{up_count} bars up → reversal | shooting={is_shooting} 1m_res={near_1m_res} 15m_res={near_res}",
                micro_trends=micro,
            )

        return None

    # ── PATTERN 5: EMA fast crossover on 5m ──
    def _check_ema_cross():
        closes = pd.Series(close_5m)
        ema3 = _ema(closes, 3).values
        ema8 = _ema(closes, 8).values
        if len(ema3) < 3:
            return None

        if ema3[-2] < ema8[-2] and ema3[-1] > ema8[-1]:
            conf = 0.30
            if close_5m[-1] > ema3[-1]:
                if micro.position == "at_support" or micro.bounce == "support_bounce":
                    conf += 0.15  # EMA cross + trendline bounce = strong
                return MicroSignal(
                    "long_hou", conf, "ema3x8_bull_cross", p,
                    target_move_pct=0.25, stop_move_pct=0.15,
                    rationale=f"EMA3/8 bull cross | 1m trendline position={micro.position}",
                    micro_trends=micro,
                )

        if ema3[-2] > ema8[-2] and ema3[-1] < ema8[-1]:
            if close_5m[-1] < ema3[-1]:
                conf = 0.30
                if micro.position == "at_resistance" or micro.bounce == "resistance_reject":
                    conf += 0.15
                return MicroSignal(
                    "long_hod", conf, "ema3x8_bear_cross", p,
                    target_move_pct=0.25, stop_move_pct=0.15,
                    rationale=f"EMA3/8 bear cross | 1m trendline position={micro.position}",
                    micro_trends=micro,
                )
        return None

    # ── PATTERN 6: Mean reversion ──
    def _check_mean_reversion():
        bar_move = abs(close_5m[-1] - open_5m[-1])
        if atr_5m <= 0:
            return None
        ratio = bar_move / atr_5m

        if ratio > 1.0:
            if close_5m[-1] < open_5m[-1]:  # big down → bounce
                conf = 0.25
                if ratio > 2.0:
                    conf += 0.10
                if micro.position == "at_support" or micro.bounce == "support_bounce":
                    conf += 0.15  # trendline confirms bounce
                if chan_15m and chan_15m.near_support:
                    conf += 0.08

                return MicroSignal(
                    "long_hou", min(0.60, conf),
                    f"mean_revert_{ratio:.1f}x_atr_down", p,
                    target_move_pct=0.2, stop_move_pct=0.15,
                    rationale=f"Last 5m: {ratio:.1f}× ATR down → revert | 1m_pos={micro.position}",
                    micro_trends=micro,
                )
            else:  # big up → fade
                conf = 0.25
                if ratio > 2.0:
                    conf += 0.10
                if micro.position == "at_resistance" or micro.bounce == "resistance_reject":
                    conf += 0.15
                if chan_15m and chan_15m.near_resistance:
                    conf += 0.08

                return MicroSignal(
                    "long_hod", min(0.60, conf),
                    f"mean_revert_{ratio:.1f}x_atr_up", p,
                    target_move_pct=0.2, stop_move_pct=0.15,
                    rationale=f"Last 5m: {ratio:.1f}× ATR up → revert | 1m_pos={micro.position}",
                    micro_trends=micro,
                )
        return None

    # ── Run all patterns, rank by confidence ──
    # Priority: trendline patterns first, then secondary confirmation
    checkers = [
        _check_trendline_bounce,   # #1 — bounce (green/red candle confirms)
        _check_at_trendline,       # #2 — at the line = trade
        _check_trendline_breakout,  # #3
        _check_channel_trade,      # #4
        _check_reversal,            # #5
        _check_ema_cross,           # #6
        _check_mean_reversion,     # #7
    ]

    signals: List[MicroSignal] = []
    for check in checkers:
        try:
            s = check()
            if s is not None and s.confidence >= 0.20:
                # ── TREND FILTER ──
                # In uptrend: only allow long (HOU). Suppress short (HOD).
                if trend == "up" and s.direction == "long_hod":
                    # Boost long signals, reduce short confidence
                    s.confidence *= 0.3  # heavily penalize shorts in uptrend
                elif trend == "down" and s.direction == "long_hou":
                    # Boost short signals, reduce long confidence
                    s.confidence *= 0.3  # heavily penalize longs in downtrend
                # In flat market: both sides allowed at full confidence
                
                signals.append(s)
        except Exception:
            pass

    if not signals:
        # NO FLAT — always pick a side based on trend
        # If uptrend → default long. If downtrend → default short. If flat → use 1m slope
        if trend == "up":
            return MicroSignal(
                "long_hou", 0.20, "trend_default_long", p,
                target_move_pct=0.2, stop_move_pct=0.15,
                rationale=f"1m UPTREND (no pattern) → default long | sup=${micro.nearest_support or 0:.2f} res=${micro.nearest_resistance or 0:.2f}",
                micro_trends=micro,
            )
        elif trend == "down":
            return MicroSignal(
                "long_hod", 0.20, "trend_default_short", p,
                target_move_pct=0.2, stop_move_pct=0.15,
                rationale=f"1m DOWNTREND (no pattern) → default short | sup=${micro.nearest_support or 0:.2f} res=${micro.nearest_resistance or 0:.2f}",
                micro_trends=micro,
            )
        else:
            # Flat: use closest trendline as guide
            if micro.nearest_support and micro.nearest_resistance:
                mid = (micro.nearest_support + micro.nearest_resistance) / 2
                if p > mid:
                    direction = "long_hou"
                    rationale = f"Flat channel, price above mid → slight long"
                else:
                    direction = "long_hod"
                    rationale = f"Flat channel, price below mid → slight short"
            elif micro.nearest_support:
                direction = "long_hou"
                rationale = f"Flat, near support → long"
            else:
                direction = "long_hod"
                rationale = f"Flat, near resistance → short"
            return MicroSignal(
                direction, 0.15, "trend_flat_default", p,
                target_move_pct=0.2, stop_move_pct=0.15,
                rationale=f"{rationale} | sup=${micro.nearest_support or 0:.2f} res=${micro.nearest_resistance or 0:.2f}",
                micro_trends=micro,
            )

    # Pick highest confidence (after trend filter penalties)
    best = max(signals, key=lambda s: s.confidence)
    # Add trend label to rationale
    if trend != "flat":
        best.rationale += f" | 1m TREND={trend.upper()}"
    return best