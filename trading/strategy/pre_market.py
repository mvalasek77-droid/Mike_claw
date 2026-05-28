"""Pre-market morning report — fires at 6:20 AM PT (9:20 AM ET) weekdays.

Analyzes everything available before TSX open:
1. Overnight WTI move on CME Globex (what happened while we slept)
2. Yesterday's HOU/HOD close vs today's pre-market gap
3. Daily/weekly/monthly trend regime & wick channels
4. Key support/resistance levels for the day
5. Recommended direction and entry plan
6. Goal progress update

This is the MOST IMPORTANT alert of the day — it sets up every trade.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

import pandas as pd

from ..config import CFG
from ..data.feed import fetch
from ..data.investing import wti_live, wti_change
from ..execution.alerts import Alerter
from ..learning.adaptive import CompoundingSizer, AutoTuner
from ..learning.goal_tracker import GoalProgress
from ..ta.indicators import atr, adx, realized_vol, ema, rsi
from ..ta.regime import classify
from ..ta.wick_channels import detect_wick_channels
from ..ta.trendlines import current_trendlines, break_state
from .overnight import overnight_analysis


@dataclass
class PreMarketReport:
    """Complete pre-market analysis for the day."""
    # WTI
    wti_close_yesterday: float
    wti_price_now: float
    wti_overnight_change: float        # % change overnight
    wti_overnight_direction: str        # "up" / "down" / "flat"
    wti_change_pct_session: float | None  # full session % from Investing.com

    # Regime
    daily_regime: str
    weekly_regime: str
    monthly_regime: str

    # Key levels (WTI)
    daily_support: float | None
    daily_resistance: float | None
    weekly_support: float | None
    weekly_resistance: float | None
    nearest_support: float | None
    nearest_resistance: float | None
    distance_to_support_pct: float
    distance_to_resistance_pct: float

    # Trend
    ema_trend: str                     # "bullish" / "bearish" / "neutral"
    rsi_value: float
    rsi_signal: str                    # "overbought" / "oversold" / "neutral"

    # Gap analysis
    gap_direction: str                  # "gap_up" / "gap_down" / "flat"
    gap_pct: float                     # expected gap size %
    hou_gap_open: float                # projected HOU open price
    hou_gap_pct: float                 # projected HOU gap %
    hod_gap_open: float                # projected HOD open price
    hod_gap_pct: float                 # projected HOD gap %
    # Scenario: if WTI hits support today
    hou_at_support: float              # HOU projected if WTI hits nearest support
    hou_at_support_pct: float          # % change from gap open
    hod_at_support: float              # HOD projected if WTI hits nearest support
    hod_at_support_pct: float
    # Scenario: if WTI hits resistance today
    hou_at_resistance: float           # HOU projected if WTI hits nearest resistance
    hou_at_resistance_pct: float       # % change from gap open
    hod_at_resistance: float           # HOD projected if WTI hits nearest resistance
    hod_at_resistance_pct: float

    # Recommendation
    direction: str                      # "long_hou" / "long_hod"
    confidence: float
    entry_plan: str                     # human-readable trade plan
    key_level: float                    # most important S/R to watch
    stop_level: float                   # suggested stop (WTI)

    # Goal
    goal_progress_pct: float
    goal_ahead_pct: float


def generate_pre_market_report(goal: GoalProgress, sizer: CompoundingSizer, tuner: AutoTuner) -> PreMarketReport:
    """Generate the 6:20 AM pre-market analysis."""

    # ── 1. Overnight WTI move ──
    wti_now = None
    wti_session_change = None
    try:
        wti_now = wti_live()
        chg = wti_change()
        wti_session_change = chg.get("change_pct")
    except Exception:
        pass

    # Fetch daily bars for yesterday's close
    try:
        daily = fetch(CFG.underlying_ticker, "1d", 30)
        wti_close_yesterday = float(daily["close"].iloc[-2]) if len(daily) >= 2 else float(daily["close"].iloc[-1])
    except Exception:
        wti_close_yesterday = 0.0

    if wti_now:
        wti_price_now = wti_now
    elif len(daily) >= 1:
        wti_price_now = float(daily["close"].iloc[-1])
    else:
        wti_price_now = 0.0

    overnight_change = ((wti_price_now - wti_close_yesterday) / wti_close_yesterday * 100) if wti_close_yesterday > 0 else 0.0
    if overnight_change > 0.15:
        wti_overnight_direction = "up"
    elif overnight_change < -0.15:
        wti_overnight_direction = "down"
    else:
        wti_overnight_direction = "flat"

    # ── 2. Multi-timeframe regime ──
    tp = tuner.params

    def _get_regime(interval: str, lookback: int) -> str:
        try:
            df = fetch(CFG.underlying_ticker, interval, lookback)
            if df is not None and len(df) > 20:
                return classify(df, CFG.adx_trend_threshold, CFG.realized_vol_window)
        except Exception:
            pass
        return "unknown"

    daily_regime = _get_regime("1d", 150)
    weekly_regime = _get_regime("1wk", 730)
    monthly_regime = _get_regime("1mo", 3650)

    # ── 3. Key S/R levels from wick channels + trendlines ──
    daily_support = None
    daily_resistance = None
    weekly_support = None
    weekly_resistance = None
    nearest_support = None
    nearest_resistance = None
    distance_to_support_pct = 0.0
    distance_to_resistance_pct = 0.0

    try:
        daily_df = fetch(CFG.underlying_ticker, "1d", 150)
        if daily_df is not None and len(daily_df) > 20:
            atr_val = float(atr(daily_df, 14).iloc[-1] or 0.0)

            # Daily wick channels
            wc = detect_wick_channels(
                daily_df, left=CFG.pivot_left, right=CFG.pivot_right,
                top_n_wicks=tp.top_n_wicks, min_pivots=3,
                lookback_bars=min(tp.lookback_bars, len(daily_df) - 10),
                atr_value=atr_val,
                near_buffer_atr=tp.near_buffer_atr,
                break_buffer_atr=tp.break_buffer_atr,
            )
            if wc and wc.support:
                daily_support = wc.support.value
            if wc and wc.resistance:
                daily_resistance = wc.resistance.value

            # Daily trendlines
            sup, res = current_trendlines(
                daily_df, CFG.pivot_left, CFG.pivot_right,
                CFG.trendline_lookback_pivots, CFG.min_pivots_for_line,
            )
            if sup and (daily_support is None or sup.price > daily_support):
                daily_support = sup.price
            if res and (daily_resistance is None or res.price < daily_resistance):
                daily_resistance = res.price
    except Exception:
        pass

    try:
        weekly_df = fetch(CFG.underlying_ticker, "1wk", 730)
        if weekly_df is not None and len(weekly_df) > 20:
            atr_val_w = float(atr(weekly_df, 14).iloc[-1] or 0.0)
            wc_w = detect_wick_channels(
                weekly_df, left=CFG.pivot_left, right=CFG.pivot_right,
                top_n_wicks=tp.top_n_wicks, min_pivots=3,
                lookback_bars=min(tp.lookback_bars, len(weekly_df) - 10),
                atr_value=atr_val_w,
                near_buffer_atr=tp.near_buffer_atr,
                break_buffer_atr=tp.break_buffer_atr,
            )
            if wc_w and wc_w.support:
                weekly_support = wc_w.support.value
            if wc_w and wc_w.resistance:
                weekly_resistance = wc_w.resistance.value
    except Exception:
        pass

    # Compute nearest S/R from current price
    all_supports = [s for s in [daily_support, weekly_support] if s is not None and s < wti_price_now]
    all_resistances = [r for r in [daily_resistance, weekly_resistance] if r is not None and r > wti_price_now]

    if all_supports:
        nearest_support = max(all_supports)
        distance_to_support_pct = (wti_price_now - nearest_support) / wti_price_now * 100
    if all_resistances:
        nearest_resistance = min(all_resistances)
        distance_to_resistance_pct = (nearest_resistance - wti_price_now) / wti_price_now * 100

    # ── 4. Trend indicators ──
    ema_trend = "neutral"
    rsi_value = 50.0
    rsi_signal = "neutral"

    try:
        if daily_df is not None and len(daily_df) > 50:
            ema9 = ema(daily_df["close"], 9)
            ema21 = ema(daily_df["close"], 21)
            ema50 = ema(daily_df["close"], 50)
            last_ema9 = float(ema9.iloc[-1])
            last_ema21 = float(ema21.iloc[-1])
            last_ema50 = float(ema50.iloc[-1]) if len(ema50.dropna()) > 0 else 0

            if last_ema9 > last_ema21 > last_ema50:
                ema_trend = "bullish"  # aligned above
            elif last_ema9 < last_ema21 < last_ema50:
                ema_trend = "bearish"  # aligned below
            elif last_ema9 > last_ema21:
                ema_trend = "bullish"
            elif last_ema9 < last_ema21:
                ema_trend = "bearish"

            rsi_values = rsi(daily_df["close"], 14)
            rsi_value = float(rsi_values.iloc[-1])
            if rsi_value > 65:
                rsi_signal = "overbought"
            elif rsi_value < 35:
                rsi_signal = "oversold"
    except Exception:
        pass

    # ── 5. Gap analysis ──
    # HOU/HOD gap estimate: overnight WTI move × 2x leverage
    if overnight_change > 0.3:
        gap_direction = "gap_up"
        gap_pct = overnight_change * 2  # 2x leverage
    elif overnight_change < -0.3:
        gap_direction = "gap_down"
        gap_pct = abs(overnight_change) * 2
    else:
        gap_direction = "flat"
        gap_pct = abs(overnight_change) * 2

    # ── 5b. Projected ETF gap & scenario levels ──
    # Current ETF approximate prices (updated dynamically if possible)
    hou_close = 25.88  # HOU.TO approx previous close
    hod_close = 5.45   # HOD.TO approx previous close
    try:
        hou_df = fetch(CFG.longs_ticker, "1d", 5)
        if hou_df is not None and len(hou_df) >= 2:
            hou_close = float(hou_df["close"].iloc[-2])
    except Exception:
        pass
    try:
        hod_df = fetch(CFG.shorts_ticker, "1d", 5)
        if hod_df is not None and len(hod_df) >= 2:
            hod_close = float(hod_df["close"].iloc[-2])
    except Exception:
        pass

    # Gap open: overnight WTI % × 2x = ETF gap %
    hou_gap_pct = overnight_change * 2   # positive = gap up for HOU
    hod_gap_pct = overnight_change * -2   # inverse for HOD
    hou_gap_open = hou_close * (1 + hou_gap_pct / 100)
    hod_gap_open = hod_close * (1 + hod_gap_pct / 100)

    # Scenario: WTI hits nearest support (-distance_to_support_pct from current)
    wti_move_to_support = -distance_to_support_pct if nearest_support else 0.0
    wti_move_to_resistance = distance_to_resistance_pct if nearest_resistance else 0.0

    # From gap open to support/resistance (additive from gap open base)
    # WTI move from current → support = -(distance_to_support_pct)
    # Additional ETF % from gap open = (WTI_move_total - overnight_change) × 2
    # Simplified: ETF at support = gap_open × (1 + wti_move_to_support × 2 / 100 - hou_gap_pct / 100)
    # More intuitive: total WTI move from yesterday close = (support - wti_close_yesterday) / wti_close_yesterday
    if wti_close_yesterday > 0 and nearest_support:
        wti_total_to_support = (nearest_support - wti_close_yesterday) / wti_close_yesterday * 100
        wti_total_to_resistance = (nearest_resistance - wti_close_yesterday) / wti_close_yesterday * 100
    else:
        wti_total_to_support = overnight_change + wti_move_to_support
        wti_total_to_resistance = overnight_change + wti_move_to_resistance

    hou_at_support = hou_close * (1 + wti_total_to_support * 2 / 100)
    hou_at_support_pct = (hou_at_support - hou_gap_open) / hou_gap_open * 100 if hou_gap_open > 0 else 0.0
    hod_at_support = hod_close * (1 + wti_total_to_support * -2 / 100)
    hod_at_support_pct = (hod_at_support - hod_gap_open) / hod_gap_open * 100 if hod_gap_open > 0 else 0.0

    hou_at_resistance = hou_close * (1 + wti_total_to_resistance * 2 / 100)
    hou_at_resistance_pct = (hou_at_resistance - hou_gap_open) / hou_gap_open * 100 if hou_gap_open > 0 else 0.0
    hod_at_resistance = hod_close * (1 + wti_total_to_resistance * -2 / 100)
    hod_at_resistance_pct = (hod_at_resistance - hod_gap_open) / hod_gap_open * 100 if hod_gap_open > 0 else 0.0

    # ── 6. Direction recommendation ──
    # Combine ALL signals: overnight move, regime, channels, RSI, EMAs
    bull_score = 0
    bear_score = 0
    rationale_parts = []

    # Overnight WTI move — weighted by gap SIZE (bigger gaps = more conviction)
    # Scale: small gap (<0.5%) = 1pt, medium (0.5-2%) = 3pt, large (>2%) = 5pt, huge (>5%) = 8pt
    gap_weight = 1
    if abs(overnight_change) > 5:
        gap_weight = 8  # huge gap — dominates everything
    elif abs(overnight_change) > 2:
        gap_weight = 5  # large gap
    elif abs(overnight_change) > 0.5:
        gap_weight = 3  # medium gap

    if wti_overnight_direction == "up":
        bull_score += gap_weight
        rationale_parts.append(f"WTI +{overnight_change:.2f}% overnight → bullish gap (×{gap_weight})")
    elif wti_overnight_direction == "down":
        bear_score += gap_weight
        rationale_parts.append(f"WTI {overnight_change:.2f}% overnight → bearish gap (×{gap_weight})")
    else:
        # Flat overnight — no strong directional signal
        rationale_parts.append(f"WTI flat overnight ({overnight_change:.2f}%)")

    # Regime votes
    for label, regime in [("Daily", daily_regime), ("Weekly", weekly_regime), ("Monthly", monthly_regime)]:
        if regime == "trend":
            # Check which direction the trend is
            try:
                if daily_df is not None and len(daily_df) > 21:
                    last_close = float(daily_df["close"].iloc[-1])
                    ema21_val = float(ema(daily_df["close"], 21).iloc[-1])
                    if last_close > ema21_val:
                        bull_score += 1
                        rationale_parts.append(f"{label}: uptrend")
                    else:
                        bear_score += 1
                        rationale_parts.append(f"{label}: downtrend")
            except Exception:
                pass
        elif regime == "shock":
            rationale_parts.append(f"{label}: shock/volatile")

    # Channel position
    if nearest_support and nearest_resistance:
        if distance_to_support_pct < distance_to_resistance_pct:
            bull_score += 1
            rationale_parts.append(f"Nearer support ({nearest_support:.2f}, +{distance_to_support_pct:.2f}%)")
        else:
            bear_score += 1
            rationale_parts.append(f"Nearer resistance ({nearest_resistance:.2f}, -{distance_to_resistance_pct:.2f}%)")

    # EMA trend
    if ema_trend == "bullish":
        bull_score += 1
        rationale_parts.append("EMA bullish alignment")
    elif ema_trend == "bearish":
        bear_score += 1
        rationale_parts.append("EMA bearish alignment")

    # RSI
    if rsi_signal == "oversold":
        bull_score += 1
        rationale_parts.append(f"RSI {rsi_value:.0f} oversold → bounce")
    elif rsi_signal == "overbought":
        bear_score += 1
        rationale_parts.append(f"RSI {rsi_value:.0f} overbought → pullback")

    # Use overnight analysis for additional signal
    try:
        ovn = overnight_analysis(
            underlying_ticker=CFG.underlying_ticker,
            longs_ticker=CFG.longs_ticker,
            shorts_ticker=CFG.shorts_ticker,
            pivot_left=CFG.pivot_left, pivot_right=CFG.pivot_right,
            top_n_wicks=6, min_pivots=3,
            adx_trend_threshold=CFG.adx_trend_threshold,
            realized_vol_window=CFG.realized_vol_window,
            bar_interval=CFG.bar_interval,
            history_days=CFG.history_days_intraday,
        )
        if ovn.direction == "long_hou":
            bull_score += 2
            rationale_parts.append(f"Overnight analysis: HOU ({ovn.confidence:.0%})")
        elif ovn.direction == "long_hod":
            bear_score += 2
            rationale_parts.append(f"Overnight analysis: HOD ({ovn.confidence:.0%})")
        key_level = ovn.key_level
    except Exception:
        key_level = wti_price_now

    # NEVER FLAT — always pick a side
    if bull_score > bear_score:
        direction = "long_hou"
        confidence = min(0.95, 0.30 + bull_score * 0.10)
    elif bear_score > bull_score:
        direction = "long_hod"
        confidence = min(0.95, 0.30 + bear_score * 0.10)
    else:
        # Tie — use overnight WTI direction as tiebreaker, default bullish
        if wti_overnight_direction == "down":
            direction = "long_hod"
        else:
            direction = "long_hou"
        confidence = 0.25
        rationale_parts.append("[TIE — default directional bias]")

    # Entry plan
    target_name = "HOU" if direction == "long_hou" else "HOD"
    direction_emoji = "🟢" if direction == "long_hou" else "🔴"

    if gap_direction == "gap_up" and direction == "long_hou":
        entry_plan = f"BUY {target_name} AT OPEN — momentum gap up"
    elif gap_direction == "gap_down" and direction == "long_hod":
        entry_plan = f"BUY {target_name} AT OPEN — momentum gap down"
    elif gap_direction == "gap_up" and direction == "long_hod":
        entry_plan = f"BUY {target_name} ON DIP — gap up could fade, wait for pullback to ${nearest_support:.2f}" if nearest_support else f"BUY {target_name} cautiously"
    elif gap_direction == "gap_down" and direction == "long_hou":
        entry_plan = f"BUY {target_name} ON DIP — gap down could reverse at ${nearest_support:.2f}" if nearest_support else f"BUY {target_name} cautiously"
    else:
        entry_plan = f"BUY {target_name} — flat open, enter near ${wti_price_now:.2f}"

    # Stop level
    if direction == "long_hou":
        stop_level = nearest_support if nearest_support else wti_price_now * 0.98
    else:
        stop_level = nearest_resistance if nearest_resistance else wti_price_now * 1.02

    # Goal progress
    goal_progress_pct = goal.progress_pct
    goal_ahead_pct = goal.ahead_pct

    return PreMarketReport(
        wti_close_yesterday=wti_close_yesterday,
        wti_price_now=wti_price_now,
        wti_overnight_change=overnight_change,
        wti_overnight_direction=wti_overnight_direction,
        wti_change_pct_session=wti_session_change,
        daily_regime=daily_regime,
        weekly_regime=weekly_regime,
        monthly_regime=monthly_regime,
        daily_support=daily_support,
        daily_resistance=daily_resistance,
        weekly_support=weekly_support,
        weekly_resistance=weekly_resistance,
        nearest_support=nearest_support,
        nearest_resistance=nearest_resistance,
        distance_to_support_pct=distance_to_support_pct,
        distance_to_resistance_pct=distance_to_resistance_pct,
        ema_trend=ema_trend,
        rsi_value=rsi_value,
        rsi_signal=rsi_signal,
        gap_direction=gap_direction,
        gap_pct=gap_pct,
        hou_gap_open=hou_gap_open,
        hou_gap_pct=hou_gap_pct,
        hod_gap_open=hod_gap_open,
        hod_gap_pct=hod_gap_pct,
        hou_at_support=hou_at_support,
        hou_at_support_pct=hou_at_support_pct,
        hod_at_support=hod_at_support,
        hod_at_support_pct=hod_at_support_pct,
        hou_at_resistance=hou_at_resistance,
        hou_at_resistance_pct=hou_at_resistance_pct,
        hod_at_resistance=hod_at_resistance,
        hod_at_resistance_pct=hod_at_resistance_pct,
        direction=direction,
        confidence=confidence,
        entry_plan=entry_plan,
        key_level=key_level,
        stop_level=stop_level,
        goal_progress_pct=goal_progress_pct,
        goal_ahead_pct=goal_ahead_pct,
    )


def format_pre_market_alert(report: PreMarketReport, goal: GoalProgress, sizer: CompoundingSizer, target_pnl_needed: float) -> tuple[str, str]:
    """Format the pre-market report for Telegram. Returns (title, body)."""

    target_name = "HOU" if report.direction == "long_hou" else "HOD"
    direction_emoji = "🟢" if report.direction == "long_hou" else "🔴"

    # Recover yesterday's ETF closes from gap projections
    hou_close_actual = report.hou_gap_open / (1 + report.hou_gap_pct / 100) if report.hou_gap_pct != 0 else report.hou_gap_open
    hod_close_actual = report.hod_gap_open / (1 + report.hod_gap_pct / 100) if report.hod_gap_pct != 0 else report.hod_gap_open

    # Position sizing based on goal — use actual ETF close from report
    acct = goal.current_capital
    if report.direction == "long_hou":
        etf_price = hou_close_actual  # use dynamically-fetched HOU close
    else:
        etf_price = hod_close_actual  # use dynamically-fetched HOD close
    pos_frac = goal.position_fraction()
    shares = max(1, int(acct * pos_frac / etf_price))
    position_val = shares * etf_price

    # Target P&L: what we need to make TODAY to stay on the 90-day plan
    # Required daily rate ≈ 4.56%, with 2x leverage need ~2.28% WTI move
    from ..learning.goal_tracker import DAILY_RATE
    daily_target_dollar = acct * DAILY_RATE
    wti_move_needed = DAILY_RATE / 2 * 100  # as percentage

    title = f"🌅 PRE-MARKET {direction_emoji} LONG {target_name} ({report.confidence:.0%})"

    lines = [
        f"⏰ TSX OPENS IN 10 MIN — PREPARE NOW",
        f"",
    ]

    # ── Direction & expected move section ──
    # Which ETF wins at open based on overnight move
    direction_label = "🟢 HOU bullish" if report.hou_gap_pct > 0 else "🔴 HOD bearish"
    lines += [
        f"",
        f"📉📈 EXPECTED OPEN  ({direction_label})",
        f"   HOU: ${hou_close_actual:.2f} → ${report.hou_gap_open:.2f} ({report.hou_gap_pct:+.2f}%)",
        f"   HOD: ${hod_close_actual:.2f} → ${report.hod_gap_open:.2f} ({report.hod_gap_pct:+.2f}%)",
    ]

    if report.nearest_support:
        lines += [
            f"",
            f"📊 IF WTI DROPS TO SUPPORT ${report.nearest_support:.2f}:",
            f"   HOU → ${report.hou_at_support:.2f} ({report.hou_at_support_pct:+.2f}%)",
            f"   HOD → ${report.hod_at_support:.2f} ({report.hod_at_support_pct:+.2f}%)",
        ]
    if report.nearest_resistance:
        lines += [
            f"",
            f"📊 IF WTI RALLIES TO RESISTANCE ${report.nearest_resistance:.2f}:",
            f"   HOU → ${report.hou_at_resistance:.2f} ({report.hou_at_resistance_pct:+.2f}%)",
            f"   HOD → ${report.hod_at_resistance:.2f} ({report.hod_at_resistance_pct:+.2f}%)",
        ]

    lines += [
        f"",
        f"🎯 KEY LEVELS (WTI)",
    ]

    level_lines = []
    if report.nearest_support:
        level_lines.append(f"   Support: ${report.nearest_support:.2f} ({report.distance_to_support_pct:.2f}% below)")
    if report.nearest_resistance:
        level_lines.append(f"   Resistance: ${report.nearest_resistance:.2f} ({report.distance_to_resistance_pct:.2f}% above)")
    if not level_lines:
        level_lines.append(f"   Current: ${report.wti_price_now:.2f}")
    lines += level_lines

    # ── 1H / 2H / A/H move projections ──
    import math
    from ..ta.indicators import realized_vol
    try:
        daily_df = None
        from ..data.feed import fetch as _fetch
        daily_df = _fetch("CL=F", "1d", 60)
        if daily_df is not None and len(daily_df) > 20:
            rv_daily = float(realized_vol(daily_df["close"], window=20, ann=1).iloc[-1] or 0.03)
            daily_vol_pct = rv_daily * 100
            vol_1h = daily_vol_pct / math.sqrt(6.5)
            vol_2h = daily_vol_pct / math.sqrt(3.25)
            vol_ah = daily_vol_pct
            
            # TA direction from multi_tf context
            ta_1h = "➡️ neutral"
            ta_2h = "➡️ neutral"
            ta_ah = "➡️ neutral"
            try:
                from ..ta.multi_tf import multi_timeframe_analysis
                from ..config import CFG as _CFG
                dfs = {}
                for k, (iv, lb) in [("15m",("15m",60)),("30m",("30m",60)),("1d",("1d",365)),("1wk",("1wk",730)),("1mo",("1mo",3650))]:
                    try: dfs[k] = _fetch(_CFG.underlying_ticker, iv, lb)
                    except: pass
                if len(dfs) >= 3:
                    mtf = multi_timeframe_analysis(dfs, pivot_left=_CFG.pivot_left, pivot_right=_CFG.pivot_right,
                                                     top_n_wicks=15, min_pivots=3, lookback_bars=200,
                                                     adx_trend_threshold=_CFG.adx_trend_threshold,
                                                     realized_vol_window=_CFG.realized_vol_window)
                    if mtf and hasattr(mtf, 'frames'):
                        # 1H: 15m + 30m
                        shorts = [mtf.frames.get(k) for k in ("15m","30m") if mtf.frames.get(k)]
                        if shorts:
                            bull = sum(1 for f in shorts if getattr(f,'slope_dir','')=='bullish')
                            bear = sum(1 for f in shorts if getattr(f,'slope_dir','')=='bearish')
                            ta_1h = "📈 bullish" if bull > bear else ("📉 bearish" if bear > bull else "➡️ neutral")
                        # 2H: + daily
                        meds = shorts + [mtf.frames.get("1d")] if mtf.frames.get("1d") else shorts
                        if meds:
                            bull = sum(1 for f in meds if getattr(f,'slope_dir','')=='bullish')
                            bear = sum(1 for f in meds if getattr(f,'slope_dir','')=='bearish')
                            ta_2h = "📈 bullish" if bull > bear else ("📉 bearish" if bear > bull else "➡️ neutral")
                        # A/H: + weekly + monthly
                        longs = meds + [mtf.frames.get(k) for k in ("1wk","1mo") if mtf.frames.get(k)]
                        if longs:
                            bull = sum(1 for f in longs if getattr(f,'slope_dir','')=='bullish')
                            bear = sum(1 for f in longs if getattr(f,'slope_dir','')=='bearish')
                            ta_ah = "📈 bullish" if bull > bear else ("📉 bearish" if bear > bull else "➡️ neutral")
            except Exception:
                pass
            
            # TA shifts
            shift_1h = vol_1h * 0.3 * (1 if "bullish" in ta_1h else (-1 if "bearish" in ta_1h else 0))
            shift_2h = vol_2h * 0.3 * (1 if "bullish" in ta_2h else (-1 if "bearish" in ta_2h else 0))
            shift_ah = vol_ah * 0.3 * (1 if "bullish" in ta_ah else (-1 if "bearish" in ta_ah else 0))
            
            wti_now = report.wti_price_now
            up_1h = vol_1h + max(shift_1h, 0)
            dn_1h = -vol_1h + min(shift_1h, 0)
            up_2h = vol_2h + max(shift_2h, 0)
            dn_2h = -vol_2h + min(shift_2h, 0)
            up_ah = vol_ah + max(shift_ah, 0)
            dn_ah = -vol_ah + min(shift_ah, 0)
            
            lines += [
                f"",
                f"🔮 PREDICTED MOVES FROM CURRENT (×2 for ETF)",
                f"TA: 1H {ta_1h} · 2H {ta_2h} · A/H {ta_ah}",
                f"",
                f"⏱ 1H  {ta_1h.split()[0]} ${wti_now*(1+up_1h/100):.2f} / ${wti_now*(1+dn_1h/100):.2f}  ({up_1h:+.1f}% / {dn_1h:+.1f}%)",
                f"⏱ 2H  {ta_2h.split()[0]} ${wti_now*(1+up_2h/100):.2f} / ${wti_now*(1+dn_2h/100):.2f}  ({up_2h:+.1f}% / {dn_2h:+.1f}%)",
                f"🌙 A/H {ta_ah.split()[0]} ${wti_now*(1+up_ah/100):.2f} / ${wti_now*(1+dn_ah/100):.2f}  ({up_ah:+.1f}% / {dn_ah:+.1f}%)",
            ]
    except Exception:
        pass  # non-critical — skip if data unavailable

    lines += [
        f"",
        f"📋 TODAY'S TRADE PLAN",
        f"   {report.entry_plan}",
        f"   Stop: ${report.stop_level:.2f}",
        f"   Key level: ${report.key_level:.2f}",
        f"",
        f"💰 GOAL TRACKER",
        f"   Account: ${acct:.2f} | Sizing: {pos_frac:.0%}",
        f"   Need today: +${daily_target_dollar:.2f} (+{DAILY_RATE*100:.1f}%)",
        f"   WTI move needed: {wti_move_needed:.2f}%",
        f"   {shares} {target_name} @ ${etf_price:.2f} = ${position_val:.0f}",
        f"   💰 Target: +${position_val * DAILY_RATE:.2f}",
        f"   📊 Day {goal.day_number}/90 | {goal.progress_pct:.1f}% → $10K",
        f"   {'🔥 AHEAD' if goal.ahead_pct > 5 else '📈 On track' if goal.ahead_pct > -5 else '⚠️ BEHIND'} ({goal.ahead_pct:+.1f}%)",
    ]

    body = "\n".join(lines)
    return title, body