#!/usr/bin/env python3
"""
Multi-Timeframe Wave Quantifier
=================================
Identifies 1-down/2-up and 1-up/2-down waves across Monthly, Weekly, Daily.

Logic:
  - Monthly sets the REGIME (up or down trend)
  - Weekly confirms the regime and shows wave position
  - Daily shows the active trading wave

  UPTREND:  1-down (pullback) → 2-up (extension)
  DOWNTREND: 1-up (pullback) → 2-down (extension)

  Measures:
  - Pullback amplitude & duration
  - Extension amplitude & duration
  - Ext/Pullback ratio (trend health)
  - Where we are NOW in the current cycle (in pullback? in extension?)
  - Gap analysis: difference between expected vs actual wave sizes

Usage:
    python3 mtf_wave_quantifier.py              # WTI
    python3 mtf_wave_quantifier.py RGTI          # RGTI
"""

import sys
import yfinance as yf
import numpy as np
import json
from pathlib import Path
from dataclasses import dataclass, field
from typing import List, Optional, Tuple
from scipy.signal import argrelextrema
import time

# Simple in-memory cache to avoid double API calls within one process
_mtf_cache: dict = {}
_mtf_cache_ttl: int = 300  # 5 minutes

# ─── Data structures ───

@dataclass
class Wave:
    """One half of a wave cycle (either pullback or extension)."""
    direction: str       # 'pullback' or 'extension'
    start_idx: int
    end_idx: int
    start_price: float
    end_price: float
    amplitude_pct: float
    duration_bars: int
    bars_since_end: int = 0

    @property
    def is_pullback(self):
        return self.direction == 'pullback'

    @property
    def is_extension(self):
        return self.direction == 'extension'


@dataclass
class WaveCycle:
    """One complete cycle: pullback → extension (or vice versa)."""
    pullback: Wave
    extension: Wave
    ratio: float           # ext/pullback amplitude ratio
    pullback_failed: bool  # pullback > 3 bars (unhealthy)

@dataclass
class TimeframeWaves:
    """Wave analysis for one timeframe."""
    timeframe: str
    trend: str             # 'UP' or 'DOWN'
    cycles: List[WaveCycle]
    current_phase: str     # 'pullback' or 'extension' or 'unknown'
    current_wave: Optional[Wave]  # the wave we're in right now
    bars_into_phase: int   # how many bars into current phase
    # Distribution stats
    pb_median: float = 0
    pb_mean: float = 0
    pb_p10: float = 0
    pb_p90: float = 0
    ext_median: float = 0
    ext_mean: float = 0
    ext_p10: float = 0
    ext_p90: float = 0
    ratio_median: float = 0
    ratio_mean: float = 0
    pb_fail_rate: float = 0
    target_3_hit: float = 0  # % of extensions that reach 3%
    target_6_hit: float = 0  # % of extensions that reach 6%


# ─── Trend detection ───

def detect_trend(closes: np.ndarray, window: int = 20) -> str:
    """Detect trend from price vs moving average + slope."""
    if len(closes) < window:
        return "UP" if closes[-1] > closes[0] else "DOWN"
    ma = np.convolve(closes, np.ones(window)/window, mode='valid')
    slope = ma[-1] - ma[-min(10, len(ma))]
    price_vs_ma = closes[-1] - ma[-1]
    score = 0
    if slope > 0: score += 1
    if price_vs_ma > 0: score += 1
    # Higher highs / lower lows
    recent = closes[-min(20, len(closes)):]
    if recent[-1] > recent[0]: score += 1
    return "UP" if score >= 2 else "DOWN"


# ─── Wave detection ───

def find_swings(closes: np.ndarray, order: int = 3) -> Tuple[np.ndarray, np.ndarray]:
    """Find local maxima and minima indices."""
    hi = argrelextrema(closes, np.greater, order=order)[0]
    lo = argrelextrema(closes, np.less, order=order)[0]
    return hi, lo


def extract_waves(closes: np.ndarray, trend: str, hi: np.ndarray, lo: np.ndarray) -> List[WaveCycle]:
    """
    From swing highs/lows, extract pullback → extension cycles.
    
    UPTREND:  swing high → dip (1-down pullback) → new high (2-up extension)
    DOWNTREND: swing low → bounce (1-up pullback) → new low (2-down extension)
    """
    cycles = []
    
    if trend == "UP":
        # UPTREND: pullback = hi→lo (1-down), extension = lo→hi (2-up)
        # Interleave: hi0, lo0, hi1, lo1, ...
        points = sorted(
            [(int(i), 'hi', float(closes[i])) for i in hi] +
            [(int(i), 'lo', float(closes[i])) for i in lo]
        )
        # Filter: for uptrend, we want hi→lo→hi→lo sequences
        i = 0
        while i < len(points) - 2:
            if points[i][1] == 'hi' and points[i+1][1] == 'lo' and points[i+2][1] == 'hi':
                pb_start = points[i]  # hi
                pb_end = points[i+1]  # lo
                ext_end = points[i+2]  # next hi
                
                pb_amp = (pb_start[2] - pb_end[2]) / pb_start[2] * 100
                ext_amp = (ext_end[2] - pb_end[2]) / pb_end[2] * 100
                pb_dur = pb_end[0] - pb_start[0]
                ext_dur = ext_end[0] - pb_end[0]
                
                if pb_amp > 0.1 and ext_amp > 0.1:  # filter noise
                    pullback = Wave(
                        direction='pullback',
                        start_idx=pb_start[0], end_idx=pb_end[0],
                        start_price=pb_start[2], end_price=pb_end[2],
                        amplitude_pct=pb_amp, duration_bars=max(1, pb_dur)
                    )
                    extension = Wave(
                        direction='extension',
                        start_idx=pb_end[0], end_idx=ext_end[0],
                        start_price=pb_end[2], end_price=ext_end[2],
                        amplitude_pct=ext_amp, duration_bars=max(1, ext_dur)
                    )
                    ratio = ext_amp / pb_amp if pb_amp > 0 else 0
                    cycles.append(WaveCycle(
                        pullback=pullback, extension=extension,
                        ratio=ratio, pullback_failed=pb_dur > 3
                    ))
                i += 2
            else:
                i += 1
    else:
        # DOWNTREND: pullback = lo→hi (1-up), extension = hi→lo (2-down)
        points = sorted(
            [(int(i), 'hi', float(closes[i])) for i in hi] +
            [(int(i), 'lo', float(closes[i])) for i in lo]
        )
        i = 0
        while i < len(points) - 2:
            if points[i][1] == 'lo' and points[i+1][1] == 'hi' and points[i+2][1] == 'lo':
                pb_start = points[i]  # lo
                pb_end = points[i+1]  # hi (bounce)
                ext_end = points[i+2]  # next lo
                
                pb_amp = (pb_end[2] - pb_start[2]) / pb_start[2] * 100
                ext_amp = (pb_start[2] - ext_end[2]) / ext_end[2] * 100 if ext_end[2] > 0 else 0
                # For downtrend ext: hi→lo drop
                ext_amp = (pb_end[2] - ext_end[2]) / pb_end[2] * 100
                pb_dur = pb_end[0] - pb_start[0]
                ext_dur = ext_end[0] - pb_end[0]
                
                if pb_amp > 0.1 and ext_amp > 0.1:
                    pullback = Wave(
                        direction='pullback',
                        start_idx=pb_start[0], end_idx=pb_end[0],
                        start_price=pb_start[2], end_price=pb_end[2],
                        amplitude_pct=pb_amp, duration_bars=max(1, pb_dur)
                    )
                    extension = Wave(
                        direction='extension',
                        start_idx=pb_end[0], end_idx=ext_end[0],
                        start_price=pb_end[2], end_price=ext_end[2],
                        amplitude_pct=ext_amp, duration_bars=max(1, ext_dur)
                    )
                    ratio = ext_amp / pb_amp if pb_amp > 0 else 0
                    cycles.append(WaveCycle(
                        pullback=pullback, extension=extension,
                        ratio=ratio, pullback_failed=pb_dur > 3
                    ))
                i += 2
            else:
                i += 1
    
    return cycles


def compute_stats(cycles: List[WaveCycle]) -> dict:
    """Compute distribution stats from wave cycles."""
    if not cycles:
        return {}
    
    pbs = [c.pullback.amplitude_pct for c in cycles]
    exts = [c.extension.amplitude_pct for c in cycles]
    ratios = [c.ratio for c in cycles]
    pb_fails = sum(1 for c in cycles if c.pullback_failed) / len(cycles) * 100
    hit3 = sum(1 for e in exts if e >= 3) / len(exts) * 100
    hit6 = sum(1 for e in exts if e >= 6) / len(exts) * 100
    
    return {
        'pb_median': np.median(pbs), 'pb_mean': np.mean(pbs),
        'pb_p10': np.percentile(pbs, 10), 'pb_p90': np.percentile(pbs, 90),
        'ext_median': np.median(exts), 'ext_mean': np.mean(exts),
        'ext_p10': np.percentile(exts, 10), 'ext_p90': np.percentile(exts, 90),
        'ratio_median': np.median(ratios), 'ratio_mean': np.mean(ratios),
        'pb_fail_rate': pb_fails,
        'target_3_hit': hit3, 'target_6_hit': hit6,
        'n_cycles': len(cycles),
    }


def find_current_phase(closes: np.ndarray, trend: str, last_cycle: Optional[WaveCycle], total_bars: int) -> Tuple[str, Optional[Wave], int]:
    """
    Determine where we are NOW in the current wave cycle.
    
    Returns: (phase, current_wave, bars_into_phase)
    """
    if last_cycle is None:
        return "unknown", None, 0
    
    ext_end = last_cycle.extension.end_idx
    bars_since_ext = total_bars - 1 - ext_end
    
    # If we're past the last extension end, we might be in a new pullback
    if trend == "UP":
        # After last extension high, are prices falling? → in pullback
        if closes[-1] < closes[ext_end]:
            return "pullback", None, bars_since_ext
        else:
            return "extension", None, bars_since_ext
    else:
        # DOWNTREND: after last extension low, are prices rising? → in pullback
        if closes[-1] > closes[ext_end]:
            return "pullback", None, bars_since_ext
        else:
            return "extension", None, bars_since_ext


# ─── Main analysis ───

TICKERS = {
    "WTI": {"symbol": "CL=F", "name": "WTI Crude Oil"},
    "RGTI": {"symbol": "RGTI", "name": "Rigetti Computing"},
}

TIMEFRAMES = {
    "Monthly": {"period": "5y", "interval": "1mo", "order": 2},
    "Weekly":  {"period": "2y", "interval": "1wk", "order": 3},
    "Daily":   {"period": "6mo", "interval": "1d", "order": 5},
}


def analyze_mtf(ticker_key: str) -> dict:
    """Run MTF wave analysis. Returns dict of timeframe → TimeframeWaves. Cached 5 min."""
    # Check cache
    now = time.time()
    if ticker_key in _mtf_cache:
        cached_time, cached_result = _mtf_cache[ticker_key]
        if now - cached_time < _mtf_cache_ttl:
            print(f"  [MTF cache hit for {ticker_key}]")
            return cached_result
    
    sym = TICKERS[ticker_key]["symbol"]
    result = {}
    
    for tf_name, cfg in TIMEFRAMES.items():
        print(f"  Fetching {tf_name} {cfg['period']} {cfg['interval']}...")
        df = yf.Ticker(sym).history(period=cfg['period'], interval=cfg['interval'])
        if df.empty or len(df) < 10:
            print(f"  ⚠️ {tf_name}: insufficient data ({len(df)} bars)")
            continue
        
        closes = df['Close'].values
        trend = detect_trend(closes, window=min(20, len(closes)//3))
        
        order = min(cfg['order'], max(1, len(closes)//10))
        hi, lo = find_swings(closes, order=order)
        
        cycles = extract_waves(closes, trend, hi, lo)
        stats = compute_stats(cycles)
        
        # Current phase
        last_cycle = cycles[-1] if cycles else None
        phase, current_wave, bars_in = find_current_phase(
            closes, trend, last_cycle, len(closes)
        )
        
        # Bars into current phase — more precise
        if last_cycle:
            ext_end = last_cycle.extension.end_idx
            bars_since = len(closes) - 1 - ext_end
        else:
            bars_since = 0
        
        tw = TimeframeWaves(
            timeframe=tf_name, trend=trend, cycles=cycles,
            current_phase=phase, current_wave=current_wave,
            bars_into_phase=bars_since
        )
        
        if stats:
            tw.pb_median = stats['pb_median']
            tw.pb_mean = stats['pb_mean']
            tw.pb_p10 = stats['pb_p10']
            tw.pb_p90 = stats['pb_p90']
            tw.ext_median = stats['ext_median']
            tw.ext_mean = stats['ext_mean']
            tw.ext_p10 = stats['ext_p10']
            tw.ext_p90 = stats['ext_p90']
            tw.ratio_median = stats['ratio_median']
            tw.ratio_mean = stats['ratio_mean']
            tw.pb_fail_rate = stats['pb_fail_rate']
            tw.target_3_hit = stats['target_3_hit']
            tw.target_6_hit = stats['target_6_hit']
        
        result[tf_name] = tw
    
    # Cache the result
    _mtf_cache[ticker_key] = (time.time(), result)
    return result


# ─── Formatting ───

def format_mtf_report(ticker_key: str, result: dict) -> str:
    """Format MTF wave analysis as Telegram-ready report."""
    lines = []
    ticker_info = TICKERS[ticker_key]
    
    # Determine regime from monthly
    monthly = result.get("Monthly")
    weekly = result.get("Weekly")
    daily = result.get("Daily")
    
    regime = monthly.trend if monthly else "???"
    regime_icon = "📈" if regime == "UP" else "📉"
    
    lines.append(f"{regime_icon} **{ticker_key} MTF Wave Analysis**")
    lines.append(f"🏔️ Regime: **{regime}** (Monthly)")
    lines.append("")
    
    for tf_name in ["Monthly", "Weekly", "Daily"]:
        tw = result.get(tf_name)
        if not tw:
            continue
        
        trend_icon = "📈" if tw.trend == "UP" else "📉"
        trend_word = tw.trend
        
        # In uptrend: 1-down/2-up
        # In downtrend: 1-up/2-down
        if tw.trend == "UP":
            pattern = "1↓→2↑"
            pb_label = "1-down"
            ext_label = "2-up"
        else:
            pattern = "1↑→2↓"
            pb_label = "1-up"
            ext_label = "2-down"
        
        phase_icon = "⏬" if tw.current_phase == "pullback" else "⏫"
        phase_name = "PULLBACK" if tw.current_phase == "pullback" else "EXTENSION"
        
        # Health from ratio and failure rate
        if tw.ratio_median >= 1.0 and tw.pb_fail_rate < 30:
            health = "✅HEALTHY"
        elif tw.ratio_median >= 0.5 and tw.pb_fail_rate < 50:
            health = "⚠️WEAKENING"
        else:
            health = "🔴BREAKING"
        
        n = len(tw.cycles)
        lines.append(f"**{tf_name}** {trend_icon} {trend_word} | {pattern} | {health} | N={n}")
        
        if n > 0:
            lines.append(f"  {pb_label}: med={tw.pb_median:.1f}% p90={tw.pb_p90:.1f}% fail={tw.pb_fail_rate:.0f}%")
            lines.append(f"  {ext_label}: med={tw.ext_median:.1f}% p90={tw.ext_p90:.1f}% hit3={tw.target_3_hit:.0f}% hit6={tw.target_6_hit:.0f}%")
            lines.append(f"  Ratio: median={tw.ratio_median:.2f}x")
        
        # Current position
        if tw.current_phase == "pullback":
            lines.append(f"  → **NOW: in {pb_label}** ({tw.bars_into_phase} bars in) {phase_icon} BUY ZONE")
        else:
            lines.append(f"  → **NOW: in {ext_label}** ({tw.bars_into_phase} bars in) {phase_icon} RUN IN PROGRESS")
        
        # Gap analysis: last 3 cycles
        if n >= 3:
            recent = tw.cycles[-3:]
            gaps = []
            for c in recent:
                ratio_str = f"{c.ratio:.1f}x"
                gap = c.extension.amplitude_pct - c.pullback.amplitude_pct
                if gap < 0:
                    # Extension smaller than pullback = weakening trend
                    gaps.append(f"ext SHORT {abs(gap):.1f}% ({ratio_str})")
                else:
                    gaps.append(f"ext +{gap:.1f}% ({ratio_str})")
            lines.append(f"  Recent gaps: {' | '.join(gaps)}")
        
        lines.append("")
    
    # Synthesis
    lines.append("── **SYNTHESIS** ──")
    # Alignment check across timeframes
    trends = []
    for tf_name in ["Monthly", "Weekly", "Daily"]:
        tw = result.get(tf_name)
        if tw:
            trends.append(tw.trend)
    
    if len(set(trends)) == 1:
        lines.append(f"🎯 All timeframes aligned: **{trends[0]}** — high conviction")
    elif len(trends) == 3 and trends[0] == trends[1] != trends[2]:
        lines.append(f"⚠️ M+W aligned **{trends[0]}**, D diverges **{trends[2]}** — daily pullback opportunity")
    elif len(trends) == 3 and trends[0] != trends[1]:
        lines.append(f"🔴 Monthly/Weekly DISAGREE — regime uncertain, small size only")
    
    # Position summary
    positions = []
    for tf_name in ["Monthly", "Weekly", "Daily"]:
        tw = result.get(tf_name)
        if tw:
            positions.append(f"{tf_name[0]}:{tw.current_phase[:3]}")
    lines.append(f"📍 Position: {' → '.join(positions)}")
    
    # Measured targets — use daily stats (most relevant for entries)
    if daily and len(daily.cycles) >= 5:
        ext_target = min(daily.ext_median, daily.ext_p90)
        # Stop: use the TIGHTER of [p90, median*2, p75 if available]
        pb_stops = [daily.pb_p90, daily.pb_median * 2]
        # Add p75 if we have enough data
        if len(daily.cycles) >= 8:
            pb_p75 = np.percentile([c.pullback.amplitude_pct for c in daily.cycles], 75)
            pb_stops.append(pb_p75)
        pb_stop = min(pb_stops)
        if regime == "UP":
            lines.append(f"🎯 Entry target: +{ext_target:.1f}% (ext median)")
            lines.append(f"🛑 Stop distance: -{pb_stop:.1f}% (daily pb cap)")
        else:
            lines.append(f"🎯 Entry target: -{ext_target:.1f}% (ext median)")
            lines.append(f"🛑 Stop distance: +{pb_stop:.1f}% (daily pb cap)")
    
    return "\n".join(lines)


# ─── API for signal scripts ───

def get_mtf_wave_data(ticker_key: str) -> Optional[dict]:
    """Convenience function for signal scripts to get MTF wave data."""
    if ticker_key not in TICKERS:
        return None
    try:
        result = analyze_mtf(ticker_key)
        return result
    except Exception as e:
        print(f"[MTF wave error: {e}]")
        return None


def get_mtf_regime(ticker_key: str) -> Tuple[str, str]:
    """Returns (regime, alignment) for a ticker.
    regime = Monthly trend (UP/DOWN)
    alignment = 'aligned' | 'm+w_only' | 'divergent'
    """
    result = get_mtf_wave_data(ticker_key)
    if not result:
        return "UP", "unknown"
    
    monthly = result.get("Monthly")
    weekly = result.get("Weekly")
    daily = result.get("Daily")
    
    regime = monthly.trend if monthly else "UP"
    
    m_trend = monthly.trend if monthly else None
    w_trend = weekly.trend if weekly else None
    d_trend = daily.trend if daily else None
    
    if m_trend and w_trend and d_trend and m_trend == w_trend == d_trend:
        alignment = "aligned"
    elif m_trend and w_trend and m_trend == w_trend:
        alignment = "m+w_only"
    else:
        alignment = "divergent"
    
    return regime, alignment


if __name__ == "__main__":
    ticker = sys.argv[1] if len(sys.argv) > 1 else "WTI"
    if ticker not in TICKERS:
        print(f"Unknown ticker: {ticker}. Use: {', '.join(TICKERS.keys())}")
        sys.exit(1)
    
    print(f"Analyzing {ticker}...")
    result = analyze_mtf(ticker)
    report = format_mtf_report(ticker, result)
    print(report)