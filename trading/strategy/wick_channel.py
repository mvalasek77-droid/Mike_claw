"""Wick-Channel strategy with multi-timeframe analysis.

Hierarchy (Mike's spec):
    1 MONTH → main trend (BULL/BEAR/CHOP) — THE GATE
    1 WEEK  → intermediate trend alignment
    1 DAY   → daily structure & key levels
    30 MIN  → primary signal timeframe
    15 MIN  → micro-timing / confirmation

Core rules:
    - Monthly bias is the GATE: if bearish, only shorts; if bullish, only longs
    - 30m breakout in monthly direction = HIGH conviction (0.7-0.9)
    - 15m confirmation adds +0.1 conviction
    - Range trades (bounce/fade) only in chop regime, moderate conviction
    - COUNTER-MONTHLY trades: only if 30m has a major breakout AND conviction is low
    - Narrow channels (coiled spring) boost breakout conviction ×1.3

All five timeframes use wick-based trendlines through the LONGEST wicks.
"""
from __future__ import annotations

from .base import Signal, Strategy


class WickChannel(Strategy):
    name = "wick_channel"

    def signal(self, ctx: dict) -> Signal:
        mtf = ctx.get("multi_tf")       # MultiTFResult
        chan_30m = ctx.get("wick_channel")  # WickChannel for 30m
        regime = ctx.get("regime", "chop")

        # ---- MULTI-TIMEFRAME PATH (preferred) ----
        if mtf is not None:
            return self._signal_mtf(mtf, chan_30m, regime)

        # ---- FALLBACK: single-frame wick channel ----
        if chan_30m is not None:
            return self._signal_single(chan_30m, regime)

        return Signal("flat", 0.0, "no_channel_data", self.name)

    def _signal_mtf(self, mtf, chan_30m, regime: str) -> Signal:
        """Multi-timeframe signal with monthly bias as gate."""
        parts = []
        monthly_bias = mtf.monthly_bias
        alignment = mtf.alignment_score

        parts.append(f"monthly={monthly_bias}")
        parts.append(f"align={alignment:.0%}")

        # ---- 30m BREAKOUT aligned with monthly ----
        if chan_30m is not None:
            if monthly_bias == "bull" and chan_30m.break_up:
                conf = self._breakout_confidence(chan_30m, regime, alignment)
                parts.append("30m_break_up↑aligned")
                if chan_30m.is_narrow:
                    conf = min(1.0, conf * 1.3)
                    parts.append("narrow_spring")
                # 15m confirmation
                tf_15m = mtf.frames.get("15m")
                if tf_15m and (tf_15m.channel.break_up or tf_15m.channel.near_support):
                    conf = min(1.0, conf + 0.1)
                    parts.append("15m_confirmed")
                return Signal("long_hou", conf, " | ".join(parts), self.name)

            if monthly_bias == "bear" and chan_30m.break_down:
                conf = self._breakout_confidence(chan_30m, regime, alignment)
                parts.append("30m_break_down↓aligned")
                if chan_30m.is_narrow:
                    conf = min(1.0, conf * 1.3)
                    parts.append("narrow_spring")
                tf_15m = mtf.frames.get("15m")
                if tf_15m and (tf_15m.channel.break_down or tf_15m.channel.near_resistance):
                    conf = min(1.0, conf + 0.1)
                    parts.append("15m_confirmed")
                return Signal("long_hod", conf, " | ".join(parts), self.name)

            # ---- RANGE TRADE (chop monthly or inside 30m channel) ----
            if regime in ("chop", "shock") or monthly_bias == "chop":
                if chan_30m.near_support and chan_30m.between_lines:
                    conf = self._range_confidence(chan_30m)
                    # In chop, allow both sides
                    parts.append("bounce_support")
                    if monthly_bias in ("bull", "chop"):
                        conf = min(1.0, conf + 0.08)
                        parts.append("monthly_bull_boost" if monthly_bias == "bull" else "monthly_chop_ok")
                    return Signal("long_hou", conf, " | ".join(parts), self.name)

                if chan_30m.near_resistance and chan_30m.between_lines:
                    conf = self._range_confidence(chan_30m)
                    parts.append("fade_resistance")
                    if monthly_bias in ("bear", "chop"):
                        conf = min(1.0, conf + 0.08)
                        parts.append("monthly_bear_boost" if monthly_bias == "bear" else "monthly_chop_ok")
                    return Signal("long_hod", conf, " | ".join(parts), self.name)

            # ---- DIP BUY even in chop if near support with good channel ----
            if monthly_bias == "chop" and chan_30m.near_support and chan_30m.between_lines:
                conf = 0.35 + (alignment * 0.10)
                parts.append("chop_dip_buy")
                return Signal("long_hou", conf, " | ".join(parts), self.name)

            # ---- FADE RALLY even in chop if near resistance ----
            if monthly_bias == "chop" and chan_30m.near_resistance and chan_30m.between_lines:
                conf = 0.35 + (alignment * 0.10)
                parts.append("chop_fade_rally")
                return Signal("long_hod", conf, " | ".join(parts), self.name)

            # ---- 30m breakout AGAINST monthly (low conviction) ----
            if monthly_bias == "bull" and chan_30m.break_down:
                conf = 0.25  # skeptical
                parts.append("30m_break_down↕vs_monthly")
                return Signal("long_hod", conf, " | ".join(parts), self.name)

            if monthly_bias == "bear" and chan_30m.break_up:
                conf = 0.25
                parts.append("30m_break_up↕vs_monthly")
                return Signal("long_hou", conf, " | ".join(parts), self.name)

            # ---- DIP BUY in bull monthly ----
            if monthly_bias == "bull" and chan_30m.near_support:
                conf = 0.40 + (alignment * 0.15)
                parts.append("dip_buy_bull_monthly")
                return Signal("long_hou", conf, " | ".join(parts), self.name)

            # ---- FADE RALLY in bear monthly ----
            if monthly_bias == "bear" and chan_30m.near_resistance:
                conf = 0.40 + (alignment * 0.15)
                parts.append("fade_rally_bear_monthly")
                return Signal("long_hod", conf, " | ".join(parts), self.name)

        # Use multi-TF result directly if no 30m channel detail
        if mtf.trade_direction != "flat" and mtf.conviction >= 0.25:
            return Signal(mtf.trade_direction, mtf.conviction, " | ".join(parts), self.name)

        return Signal("flat", 0.0, f"no_edge({('|'.join(parts)) if parts else 'no_data'})", self.name)

    def _signal_single(self, chan, regime: str) -> Signal:
        """Single-timeframe fallback (original logic)."""
        # Breakout — any regime
        if chan.break_up:
            conf = self._breakout_confidence(chan, regime, 0.5)
            if chan.is_narrow:
                conf = min(1.0, conf * 1.3)
            return Signal("long_hou", conf, "break_resistance", self.name)
        if chan.break_down:
            conf = self._breakout_confidence(chan, regime, 0.5)
            if chan.is_narrow:
                conf = min(1.0, conf * 1.3)
            return Signal("long_hod", conf, "break_support", self.name)

        # Range trade — chop only
        if regime in ("chop", "shock"):
            if chan.near_support and chan.between_lines:
                conf = self._range_confidence(chan)
                return Signal("long_hou", conf, "bounce_support", self.name)
            if chan.near_resistance and chan.between_lines:
                conf = self._range_confidence(chan)
                return Signal("long_hod", conf, "fade_resistance", self.name)

        # Trend dip buy
        if regime in ("trend", "trend_up") and chan.near_support and not chan.break_down:
            return Signal("long_hou", 0.45, "dip_near_support_trend", self.name)

        return Signal("flat", 0.0, f"no_edge({chan.summary()})", self.name)

    def _breakout_confidence(self, chan, regime: str, alignment: float) -> float:
        """Scale breakout confidence: channel quality × alignment."""
        base = 0.60 + (alignment * 0.15)  # 0.60-0.75 base

        # R² bonus — well-fitted lines break more meaningfully
        if chan.resistance and chan.resistance.r2 > 0.6:
            base += 0.06
        if chan.support and chan.support.r2 > 0.6:
            base += 0.06

        # Wick score — longer wick pivots = more significant
        if chan.resistance and chan.resistance.wick_score > 1.5:
            base += 0.04
        if chan.support and chan.support.wick_score > 1.5:
            base += 0.04

        # Touch count — 4+ touches = validated
        if chan.resistance and chan.resistance.touches >= 4:
            base += 0.04
        if chan.support and chan.support.touches >= 4:
            base += 0.04

        # Trend regime boost
        if regime in ("trend", "trend_up", "trend_down"):
            base += 0.05

        return min(1.0, base)

    def _range_confidence(self, chan) -> float:
        """Scale range-trade confidence based on channel quality."""
        base = 0.45

        # Tight channel = more predictable bounces
        if chan.channel_pct < 0.02:
            base += 0.08
        elif chan.channel_pct < 0.04:
            base += 0.04

        # R² bonus
        if chan.support and chan.support.r2 > 0.6:
            base += 0.05
        if chan.resistance and chan.resistance.r2 > 0.6:
            base += 0.05

        return min(1.0, base)