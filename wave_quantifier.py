#!/usr/bin/env python3
"""
Wave Quantifier
===============
Measures 1-down/2-up and 1-up/2-down wave patterns with full statistics.
Replaces hardcoded targets with measured distributions.

Usage:
  python3 wave_quantifier.py          # prints current stats
  python3 wave_quantifier.py --sym WTI
  python3 wave_quantifier.py --sym RGTI --interval 5m
  python3 wave_quantifier.py --backtest   # scan 6 months and dump all cycles
"""
import json, sys
from dataclasses import dataclass, asdict
from datetime import datetime
from pathlib import Path
from typing import Optional

import yfinance as yf
import pandas as pd
import numpy as np

STORAGE = Path(__file__).parent / "storage"
WAVE_LEGS_LOG = STORAGE / "wave_legs.jsonl"
WAVE_CYCLES_LOG = STORAGE / "wave_cycles.jsonl"
TREND_STATS_FILE = STORAGE / "wave_stats.json"

SYMBOLS = {
    "WTI": {"ticker": "CL=F", "interval": "1d", "period": "6mo"},
    "RGTI": {"ticker": "RGTI", "interval": "1d", "period": "6mo"},
    "RGTI_5M": {"ticker": "RGTI", "interval": "5m", "period": "2d"},
}


# ─── Data Classes ────────────────────────────────────────────

@dataclass
class WaveLeg:
    """One directional run in the wave sequence."""
    leg_id: int
    direction: str          # 'UP' or 'DN'
    trend: str              # prevailing trend
    start_idx: int
    end_idx: int
    duration_bars: int
    start_price: float
    end_price: float
    extreme_price: float    # highest high (UP) or lowest low (DN)
    amplitude_pct: float    # signed % move
    max_excursion_pct: float  # unsigned worst-case %
    avg_vol_ratio: float    # volume vs 20-bar avg
    wave_position: str      # '1DOWN', '2UP', etc.
    range_pct_at_start: float


@dataclass
class WaveCycle:
    """Paired pullback + extension — the atomic unit of the strategy."""
    cycle_id: int
    symbol: str
    trend: str              # 'UP' or 'DOWN'

    # Pullback (counter-trend leg)
    pullback_dir: str       # 'DN' (uptrend) or 'UP' (downtrend)
    pullback_bars: int
    pullback_pct: float     # always positive
    pullback_vol_ratio: float

    # Extension (trend-direction leg)
    extension_dir: str      # 'UP' (uptrend) or 'DN' (downtrend)
    extension_bars: int
    extension_pct: float     # always positive
    extension_vol_ratio: float

    # Cycle metrics
    ratio_ext_to_pb: float  # extension / pullback
    pullback_failed: bool   # did "1-down" extend beyond 1 bar? (became multi-bar selloff)
    target_3pct_hit: bool   # did extension reach 3%?
    target_6pct_hit: bool   # did extension reach 6%?
    range_pct_at_entry: float
    rsi14_at_entry: float
    ts: str                 # timestamp of cycle start


@dataclass
class TrendWaveStats:
    """Aggregated stats for a trend regime — used by signal scripts."""
    symbol: str
    trend: str
    sample_cycles: int
    updated: str

    # Pullback distribution
    pb_mean: float
    pb_median: float
    pb_std: float
    pb_p10: float
    pb_p90: float

    # Extension distribution
    ext_mean: float
    ext_median: float
    ext_std: float
    ext_p10: float
    ext_p90: float

    # Ratio distribution
    ratio_mean: float
    ratio_median: float

    # Failure rates
    pb_failure_rate: float     # % of pullbacks that extended (didn't bounce at 1)
    target_3_hit_rate: float   # % of extensions reaching +3%
    target_6_hit_rate: float   # % of extensions reaching +6%

    # Duration
    pb_bars_mean: float
    ext_bars_mean: float

    # Trend health
    amplitude_trend_slope: float  # regression of successive ext amplitudes
    last_3_ratios: list          # recent ext/pb ratios


# ─── Wave Identifier ────────────────────────────────────────

def identify_waves(closes, highs, lows, volumes, trend, range_series=None):
    """Build WaveLeg records from a close series.

    Returns list of WaveLeg objects.
    """
    legs = []
    if len(closes) < 3:
        return legs

    # Compute rolling range_pct if not provided
    if range_series is None:
        range_series = pd.Series(50, index=closes.index)

    # Compute rolling avg volume
    avg_vol = volumes.rolling(20, min_periods=5).mean()

    # Build sequences of consecutive direction
    cur_dir = None
    cur_start = 0
    cur_start_price = float(closes.iloc[0])

    for i in range(1, len(closes)):
        up = float(closes.iloc[i]) > float(closes.iloc[i - 1])
        d = 'UP' if up else 'DN'

        if d != cur_dir:
            if cur_dir is not None:
                # Close the previous leg
                end_idx = i - 1
                end_price = float(closes.iloc[end_idx])
                start_price = cur_start_price
                duration = end_idx - cur_start + 1

                amp = (end_price - start_price) / start_price * 100 if start_price > 0 else 0

                if cur_dir == 'UP':
                    extreme = float(highs.iloc[cur_start:end_idx + 1].max())
                else:
                    extreme = float(lows.iloc[cur_start:end_idx + 1].min())

                max_exc = abs((extreme - start_price) / start_price * 100) if start_price > 0 else 0

                avg_v = float(volumes.iloc[cur_start:end_idx + 1].mean())
                ref_v = float(avg_vol.iloc[end_idx]) if not pd.isna(avg_vol.iloc[end_idx]) else 1
                vol_ratio = avg_v / ref_v if ref_v > 0 else 1

                rp = float(range_series.iloc[cur_start]) if cur_start < len(range_series) else 50

                # Wave position label
                if trend == 'UP':
                    if cur_dir == 'DN':
                        pos = f"{duration}DOWN"
                    else:
                        pos = f"{duration}UP"
                elif trend == 'DOWN':
                    if cur_dir == 'UP':
                        pos = f"{duration}UP"
                    else:
                        pos = f"{duration}DOWN"
                else:
                    pos = f"{duration}{'UP' if cur_dir == 'UP' else 'DN'}"

                legs.append(WaveLeg(
                    leg_id=len(legs),
                    direction=cur_dir,
                    trend=trend,
                    start_idx=cur_start,
                    end_idx=end_idx,
                    duration_bars=duration,
                    start_price=round(start_price, 2),
                    end_price=round(end_price, 2),
                    extreme_price=round(extreme, 2),
                    amplitude_pct=round(amp, 2),
                    max_excursion_pct=round(max_exc, 2),
                    avg_vol_ratio=round(vol_ratio, 2),
                    wave_position=pos,
                    range_pct_at_start=round(rp, 0),
                ))

            cur_dir = d
            cur_start = i - 1
            cur_start_price = float(closes.iloc[cur_start])

    # Close the last leg
    if cur_dir is not None:
        end_idx = len(closes) - 1
        end_price = float(closes.iloc[end_idx])
        start_price = cur_start_price
        duration = end_idx - cur_start + 1
        amp = (end_price - start_price) / start_price * 100 if start_price > 0 else 0

        if cur_dir == 'UP':
            extreme = float(highs.iloc[cur_start:end_idx + 1].max())
        else:
            extreme = float(lows.iloc[cur_start:end_idx + 1].min())

        max_exc = abs((extreme - start_price) / start_price * 100) if start_price > 0 else 0
        avg_v = float(volumes.iloc[cur_start:end_idx + 1].mean())
        ref_v = float(avg_vol.iloc[end_idx]) if not pd.isna(avg_vol.iloc[end_idx]) else 1
        vol_ratio = avg_v / ref_v if ref_v > 0 else 1
        rp = float(range_series.iloc[cur_start]) if cur_start < len(range_series) else 50

        if trend == 'UP':
            pos = f"{duration}{'DOWN' if cur_dir == 'DN' else 'UP'}"
        elif trend == 'DOWN':
            pos = f"{duration}{'UP' if cur_dir == 'UP' else 'DOWN'}"
        else:
            pos = f"{duration}{'UP' if cur_dir == 'UP' else 'DN'}"

        legs.append(WaveLeg(
            leg_id=len(legs),
            direction=cur_dir,
            trend=trend,
            start_idx=cur_start,
            end_idx=end_idx,
            duration_bars=duration,
            start_price=round(start_price, 2),
            end_price=round(end_price, 2),
            extreme_price=round(extreme, 2),
            amplitude_pct=round(amp, 2),
            max_excursion_pct=round(max_exc, 2),
            avg_vol_ratio=round(vol_ratio, 2),
            wave_position=pos,
            range_pct_at_start=round(rp, 0),
        ))

    return legs


def build_cycles(legs, symbol, trend):
    """Pair pullback + extension legs into WaveCycle records.

    In UPTREND: pullback = DN leg, extension = UP leg
    In DOWNTREND: pullback = UP leg, extension = DN leg
    """
    pb_dir = 'DN' if trend == 'UP' else 'UP'
    ext_dir = 'UP' if trend == 'UP' else 'DN'

    cycles = []
    i = 0
    while i < len(legs) - 1:
        # Find a pullback leg
        if legs[i].direction != pb_dir:
            i += 1
            continue

        pb = legs[i]

        # Find the next extension leg
        ext = None
        for j in range(i + 1, min(i + 3, len(legs))):
            if legs[j].direction == ext_dir:
                ext = legs[j]
                break

        if ext is None:
            i += 1
            continue

        # Build cycle
        pb_pct = abs(pb.amplitude_pct)
        ext_pct = abs(ext.amplitude_pct)
        ratio = ext_pct / pb_pct if pb_pct > 0 else 0

        # Did the pullback "fail"?
        # A "1-down" that extends beyond 3 bars = trend is in trouble
        # (normal pullback in a healthy trend is 1-3 bars)
        # For daily bars, >3 bars is a real failure signal
        pb_failed = pb.duration_bars > 3

        # RSI at entry (approximate from data — placeholder, real calc would need separate computation)
        rsi14 = 50  # Would need the actual RSI at that bar

        cycle = WaveCycle(
            cycle_id=len(cycles),
            symbol=symbol,
            trend=trend,
            pullback_dir=pb.direction,
            pullback_bars=pb.duration_bars,
            pullback_pct=round(pb_pct, 2),
            pullback_vol_ratio=pb.avg_vol_ratio,
            extension_dir=ext.direction,
            extension_bars=ext.duration_bars,
            extension_pct=round(ext_pct, 2),
            extension_vol_ratio=ext.avg_vol_ratio,
            ratio_ext_to_pb=round(ratio, 2),
            pullback_failed=pb_failed,
            target_3pct_hit=ext_pct >= 3.0,
            target_6pct_hit=ext_pct >= 6.0,
            range_pct_at_entry=pb.range_pct_at_start,
            rsi14_at_entry=rsi14,
            ts=datetime.utcnow().isoformat(),
        )
        cycles.append(cycle)
        i = j  # skip to after extension

    return cycles


def compute_stats(cycles, symbol, trend):
    """Aggregate cycles into TrendWaveStats."""
    if len(cycles) < 3:
        return None

    pb_amplitudes = [c.pullback_pct for c in cycles]
    ext_amplitudes = [c.extension_pct for c in cycles]
    ratios = [c.ratio_ext_to_pb for c in cycles if c.pullback_pct > 0.1]
    pb_durations = [c.pullback_bars for c in cycles]
    ext_durations = [c.extension_bars for c in cycles]

    # Amplitude trend (regression slope of successive extensions)
    if len(ext_amplitudes) >= 4:
        x = np.arange(len(ext_amplitudes))
        slope = float(np.polyfit(x, ext_amplitudes, 1)[0])
    else:
        slope = 0.0

    # Failure rate
    pb_failed = sum(1 for c in cycles if c.pullback_failed)
    pb_failure_rate = round(pb_failed / len(cycles) * 100, 1)

    target_3 = sum(1 for c in cycles if c.target_3pct_hit)
    target_6 = sum(1 for c in cycles if c.target_6pct_hit)

    def pct(data, p):
        if not data:
            return 0
        return round(float(np.percentile(data, p)), 2)

    stats = TrendWaveStats(
        symbol=symbol,
        trend=trend,
        sample_cycles=len(cycles),
        updated=datetime.utcnow().isoformat(),
        pb_mean=round(float(np.mean(pb_amplitudes)), 2),
        pb_median=round(float(np.median(pb_amplitudes)), 2),
        pb_std=round(float(np.std(pb_amplitudes)), 2),
        pb_p10=pct(pb_amplitudes, 10),
        pb_p90=pct(pb_amplitudes, 90),
        ext_mean=round(float(np.mean(ext_amplitudes)), 2),
        ext_median=round(float(np.median(ext_amplitudes)), 2),
        ext_std=round(float(np.std(ext_amplitudes)), 2),
        ext_p10=pct(ext_amplitudes, 10),
        ext_p90=pct(ext_amplitudes, 90),
        ratio_mean=round(float(np.mean(ratios)), 2) if ratios else 0,
        ratio_median=round(float(np.median(ratios)), 2) if ratios else 0,
        pb_failure_rate=pb_failure_rate,
        target_3_hit_rate=round(target_3 / len(cycles) * 100, 1),
        target_6_hit_rate=round(target_6 / len(cycles) * 100, 1),
        pb_bars_mean=round(float(np.mean(pb_durations)), 1),
        ext_bars_mean=round(float(np.mean(ext_durations)), 1),
        amplitude_trend_slope=round(slope, 3),
        last_3_ratios=[round(r, 2) for r in ratios[-3:]] if len(ratios) >= 3 else [],
    )
    return stats


# ─── Fetch + Analyze ────────────────────────────────────────

def determine_trend(closes):
    """EMA-based trend determination."""
    ema5 = closes.ewm(span=5).mean()
    ema9 = closes.ewm(span=9).mean()
    ema21 = closes.ewm(span=21).mean() if len(closes) > 21 else ema9

    e5 = float(ema5.iloc[-1])
    e9 = float(ema9.iloc[-1])
    e21 = float(ema21.iloc[-1])

    if e5 > e9 > e21:
        return 'UP'
    elif e5 < e9 < e21:
        return 'DOWN'
    elif e5 > e9:
        return 'UP'
    elif e5 < e9:
        return 'DOWN'
    return 'SIDEWAYS'


def compute_range_pct(highs, lows, closes, lookback=22):
    """Rolling range position."""
    h = highs.rolling(lookback, min_periods=5).max()
    l = lows.rolling(lookback, min_periods=5).min()
    rng = h - l
    return ((closes - l) / rng * 100).replace([np.inf, -np.inf], 50).fillna(50)


def analyze_symbol(sym_key, period=None, interval=None):
    """Full analysis pipeline for one symbol."""
    cfg = SYMBOLS.get(sym_key, {})
    ticker = cfg.get('ticker', sym_key)
    if period is None:
        period = cfg.get('period', '6mo')
    if interval is None:
        interval = cfg.get('interval', '1d')

    t = yf.Ticker(ticker)
    h = t.history(period=period, interval=interval)
    if h.empty or len(h) < 10:
        print(f"No data for {sym_key}")
        return None, None, None

    # Filter pre-market for intraday
    if interval in ('5m', '1m', '15m'):
        h = h.between_time('09:30', '16:00')

    closes = h['Close'].astype(float)
    highs = h['High'].astype(float)
    lows = h['Low'].astype(float)
    volumes = h['Volume'].astype(float)

    trend = determine_trend(closes)
    range_pct = compute_range_pct(highs, lows, closes)

    legs = identify_waves(closes, highs, lows, volumes, trend, range_pct)
    cycles = build_cycles(legs, sym_key, trend)
    stats = compute_stats(cycles, sym_key, trend)

    return legs, cycles, stats


def format_stats(stats):
    """Human-readable stats summary for Telegram."""
    if stats is None:
        return "Not enough wave data yet (need 3+ cycles)"

    slope_icon = '📈' if stats.amplitude_trend_slope > 0 else '📉' if stats.amplitude_trend_slope < 0 else '➡️'
    health = 'HEALTHY' if stats.pb_failure_rate < 30 else 'WEAKENING' if stats.pb_failure_rate < 50 else 'BREAKING'

    lines = [
        f"📊 **{stats.symbol} Wave Stats** ({stats.trend}) | N={stats.sample_cycles}",
        f"",
        f"**Pullbacks (1-down/1-up)**",
        f"  Median: {stats.pb_median}% | Mean: {stats.pb_mean}% | p10={stats.pb_p10}% p90={stats.pb_p90}%",
        f"  Duration: {stats.pb_bars_mean} bars | Failure: {stats.pb_failure_rate}%",
        f"",
        f"**Extensions (2-up/2-down)**",
        f"  Median: {stats.ext_median}% | Mean: {stats.ext_mean}% | p10={stats.ext_p10}% p90={stats.ext_p90}%",
        f"  Duration: {stats.ext_bars_mean} bars | Hit 3%: {stats.target_3_hit_rate}% | Hit 6%: {stats.target_6_hit_rate}%",
        f"",
        f"**Ext/Pullback Ratio**",
        f"  Median: {stats.ratio_median}x | Mean: {stats.ratio_mean}x | Last 3: {stats.last_3_ratios}",
        f"",
        f"{slope_icon} Amplitude trend: {stats.amplitude_trend_slope:+.3f}/cycle | Health: {health}",
    ]
    return '\n'.join(lines)


def save_stats(stats):
    """Save stats to JSON file (overwrites with latest)."""
    STORAGE.mkdir(parents=True, exist_ok=True)
    if stats:
        TREND_STATS_FILE.write_text(json.dumps(asdict(stats), indent=2))


def load_stats():
    """Load latest stats from file."""
    if TREND_STATS_FILE.exists():
        try:
            d = json.loads(TREND_STATS_FILE.read_text())
            return TrendWaveStats(**d)
        except:
            pass
    return None


# ─── For Import by Signal Scripts ────────────────────────────

def get_wave_stats(symbol):
    """Get wave stats for use by binary_signal.py or rgti_turn_detector.py."""
    stats = load_stats()
    if stats and stats.symbol == symbol:
        return stats
    # Refresh
    _, _, stats = analyze_symbol(symbol)
    if stats:
        save_stats(stats)
    return stats


# ─── CLI ─────────────────────────────────────────────────────

if __name__ == '__main__':
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument('--sym', default=None, help='Symbol key: WTI, RGTI, RGTI_5M')
    p.add_argument('--backtest', action='store_true', help='Dump all cycles to log')
    args = p.parse_args()

    if args.sym:
        keys = [args.sym]
    else:
        keys = ['WTI', 'RGTI']

    for key in keys:
        print(f"\n{'='*50}")
        print(f"Analyzing {key}...")
        legs, cycles, stats = analyze_symbol(key)

        if stats:
            save_stats(stats)
            print(format_stats(stats))

            if args.backtest and cycles:
                STORAGE.mkdir(parents=True, exist_ok=True)
                with open(WAVE_CYCLES_LOG, 'a') as f:
                    for c in cycles:
                        f.write(json.dumps(asdict(c)) + '\n')
                print(f"  → Saved {len(cycles)} cycles to {WAVE_CYCLES_LOG}")
        else:
            print(f"  Not enough data for {key}")

        # Show last 5 cycles
        if cycles:
            print(f"\n  Last 5 cycles:")
            for c in cycles[-5:]:
                pb_label = "⚠️ FAILED" if c.pullback_failed else f"{c.pullback_pct}%/{c.pullback_bars}b"
                ext_label = f"{c.extension_pct}%/{c.extension_bars}b"
                t3 = "✅" if c.target_3pct_hit else "❌"
                t6 = "✅" if c.target_6pct_hit else "❌"
                print(f"    PB: {pb_label} → EXT: {ext_label} (ratio {c.ratio_ext_to_pb}x) 3%{t3} 6%{t6} | range={c.range_pct_at_entry}%")