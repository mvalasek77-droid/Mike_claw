#!/usr/bin/env python3
"""
Real-Time 1H Wave Scanner v2
=============================
Tracks the alternating 1-up/2-down (downtrend) or 1-down/2-up (uptrend) cycle
on 1H candles using swing detection.

DOWNTREND (Monthly=DOWN or active descending):
  1-up (bounce) → 2-down (drop) → 1-up → 2-down → ...
  SELL at 1-up ceiling | BUY at 2-down floor

UPTREND (Monthly=UP or active ascending):
  1-down (pullback) → 2-up (extension) → 1-down → 2-up → ...
  BUY at 1-down floor | SELL at 2-up ceiling

The cycle repeats. We measure each half and know where we are.
"""

import sys
import time
import json
import numpy as np
import yfinance as yf
from pathlib import Path
from dataclasses import dataclass
from typing import Optional, List, Tuple
from scipy.signal import argrelextrema
from datetime import datetime

from mtf_wave_quantifier import get_mtf_regime
from signal_perf import oil_perf_line, rgti_perf_line

STORAGE = Path(__file__).parent / "storage"

TICKERS = {
    "WTI":  {"symbol": "CL=F",  "perf_fn": oil_perf_line},
    "RGTI": {"symbol": "RGTI", "perf_fn": rgti_perf_line},
}

# ─── Data structures ───

@dataclass
class WaveHalf:
    """One half of a wave cycle."""
    label: str          # '1-up', '2-down', '1-down', '2-up'
    direction: str      # 'UP' or 'DOWN'
    start_price: float
    end_price: float
    amplitude_pct: float
    duration_bars: int
    start_bar: int
    end_bar: int

@dataclass
class WaveCycle:
    """Complete cycle: counter-trend half + trend half."""
    half1: WaveHalf     # counter-trend (1-up in downtrend, 1-down in uptrend)
    half2: WaveHalf     # trend continuation (2-down in downtrend, 2-up in uptrend)
    ratio: float       # half2 / half1 amplitude ratio

@dataclass 
class WaveDistribution:
    """Statistical distribution of measured wave halves."""
    n: int
    half1_median: float   # counter-trend median amplitude %
    half1_p90: float
    half2_median: float   # trend continuation median amplitude %
    half2_p90: float
    ratio_median: float   # half2/half1 ratio median
    half1_dur_median: float
    half2_dur_median: float

@dataclass
class CurrentPosition:
    """Where we are right now in the cycle."""
    phase: str           # '1-up', '2-down', '1-down', '2-up'
    bars_in: int
    phase_start_price: float
    current_price: float
    moved_pct: float     # how far moved in this phase
    remaining_pct: float # estimated remaining based on distribution

@dataclass
class ScanResult:
    ticker: str
    price: float
    regime: str
    alignment: str
    regime_pattern: str   # '1↓→2↑' or '1↑→2↓'
    dist: Optional[WaveDistribution]
    pos: CurrentPosition
    last_cycles: List[WaveCycle]
    alert: Optional[str]
    alert_msg: Optional[str]


# ─── Fetch data ───

def fetch_1h(symbol: str, days: int = 30):
    df = yf.Ticker(symbol).history(period=f"{days}d", interval="1h")
    if df.empty:
        return None
    return df['Open'].values, df['High'].values, df['Low'].values, df['Close'].values, df['Volume'].values


# ─── Swing detection ───

def find_swings(highs: np.ndarray, lows: np.ndarray, order: int = None) -> List[Tuple]:
    """Find alternating swing highs and lows."""
    if order is None:
        # Adaptive: tighter for volatile stocks
        order = 2  # tight for 1H
    
    hi_idx = argrelextrema(highs, np.greater, order=order)[0]
    lo_idx = argrelextrema(lows, np.less, order=order)[0]
    
    # Merge and sort
    swings = sorted(
        [(int(i), 'HIGH', float(highs[i])) for i in hi_idx] +
        [(int(i), 'LOW', float(lows[i])) for i in lo_idx]
    )
    
    # Remove adjacent same-type, keep the extreme
    filtered = []
    for s in swings:
        if filtered and filtered[-1][1] == s[1]:
            if s[1] == 'HIGH' and s[2] > filtered[-1][2]:
                filtered[-1] = s
            elif s[1] == 'LOW' and s[2] < filtered[-1][2]:
                filtered[-1] = s
        else:
            filtered.append(s)
    
    return filtered


# ─── Cycle extraction ───

def extract_cycles_downtrend(swings):
    """
    DOWNTREND: LOW→HIGH→LOW sequences = 1-up bounce then 2-down drop.
    """
    cycles = []
    i = 0
    while i < len(swings) - 2:
        if swings[i][1] == 'LOW' and swings[i+1][1] == 'HIGH' and swings[i+2][1] == 'LOW':
            lo1_i, _, lo1_p = swings[i]
            hi_i,  _, hi_p  = swings[i+1]
            lo2_i, _, lo2_p = swings[i+2]
            
            one_up = WaveHalf(
                label='1-up', direction='UP',
                start_price=lo1_p, end_price=hi_p,
                amplitude_pct=(hi_p - lo1_p) / lo1_p * 100,
                duration_bars=max(1, hi_i - lo1_i),
                start_bar=lo1_i, end_bar=hi_i,
            )
            two_down = WaveHalf(
                label='2-down', direction='DOWN',
                start_price=hi_p, end_price=lo2_p,
                amplitude_pct=(hi_p - lo2_p) / hi_p * 100,
                duration_bars=max(1, lo2_i - hi_i),
                start_bar=hi_i, end_bar=lo2_i,
            )
            ratio = two_down.amplitude_pct / one_up.amplitude_pct if one_up.amplitude_pct > 0 else 0
            cycles.append(WaveCycle(half1=one_up, half2=two_down, ratio=ratio))
            i += 2
        else:
            i += 1
    return cycles


def extract_cycles_uptrend(swings):
    """
    UPTREND: HIGH→LOW→HIGH sequences = 1-down pullback then 2-up extension.
    """
    cycles = []
    i = 0
    while i < len(swings) - 2:
        if swings[i][1] == 'HIGH' and swings[i+1][1] == 'LOW' and swings[i+2][1] == 'HIGH':
            hi1_i, _, hi1_p = swings[i]
            lo_i,  _, lo_p  = swings[i+1]
            hi2_i, _, hi2_p = swings[i+2]
            
            one_down = WaveHalf(
                label='1-down', direction='DOWN',
                start_price=hi1_p, end_price=lo_p,
                amplitude_pct=(hi1_p - lo_p) / hi1_p * 100,
                duration_bars=max(1, lo_i - hi1_i),
                start_bar=hi1_i, end_bar=lo_i,
            )
            two_up = WaveHalf(
                label='2-up', direction='UP',
                start_price=lo_p, end_price=hi2_p,
                amplitude_pct=(hi2_p - lo_p) / lo_p * 100,
                duration_bars=max(1, hi2_i - lo_i),
                start_bar=lo_i, end_bar=hi2_i,
            )
            ratio = two_up.amplitude_pct / one_down.amplitude_pct if one_down.amplitude_pct > 0 else 0
            cycles.append(WaveCycle(half1=one_down, half2=two_up, ratio=ratio))
            i += 2
        else:
            i += 1
    return cycles


def compute_distribution(cycles: List[WaveCycle]) -> Optional[WaveDistribution]:
    if not cycles or len(cycles) < 2:
        return None
    
    h1 = [c.half1.amplitude_pct for c in cycles]
    h2 = [c.half2.amplitude_pct for c in cycles]
    ratios = [c.ratio for c in cycles]
    h1_dur = [c.half1.duration_bars for c in cycles]
    h2_dur = [c.half2.duration_bars for c in cycles]
    
    return WaveDistribution(
        n=len(cycles),
        half1_median=float(np.median(h1)),
        half1_p90=float(np.percentile(h1, 90)),
        half2_median=float(np.median(h2)),
        half2_p90=float(np.percentile(h2, 90)),
        ratio_median=float(np.median(ratios)),
        half1_dur_median=float(np.median(h1_dur)),
        half2_dur_median=float(np.median(h2_dur)),
    )


# ─── Current position ───

def find_current_position(swings, price, total_bars, dist, regime):
    """
    From the last swing, determine which phase we're in.
    
    DOWNTREND:
      Last swing = LOW → we are in 1-up (bounce)
      Last swing = HIGH → we are in 2-down (drop)
    
    UPTREND:
      Last swing = HIGH → we are in 1-down (pullback)
      Last swing = LOW → we are in 2-up (extension)
    """
    if not swings:
        return CurrentPosition('unknown', 0, price, price, 0, 0, 'unknown')
    
    last = swings[-1]
    bars_since = total_bars - 1 - last[0]
    
    if regime == "DOWN":
        if last[1] == 'LOW':
            phase = '1-up'
            moved = (price - last[2]) / last[2] * 100
            remaining = max(0, dist.half1_median - moved) if dist else 0
        else:
            phase = '2-down'
            moved = (last[2] - price) / last[2] * 100
            remaining = max(0, dist.half2_median - moved) if dist else 0
    else:  # UP
        if last[1] == 'HIGH':
            phase = '1-down'
            moved = (last[2] - price) / last[2] * 100
            remaining = max(0, dist.half1_median - moved) if dist else 0
        else:
            phase = '2-up'
            moved = (price - last[2]) / last[2] * 100
            remaining = max(0, dist.half2_median - moved) if dist else 0
    
    return CurrentPosition(
        phase=phase,
        bars_in=max(0, bars_since),
        phase_start_price=last[2],
        current_price=price,
        moved_pct=round(moved, 2),
        remaining_pct=round(remaining, 2),
    )


# ─── Alert logic ───

def check_alert(pos, dist, price, regime, last_scan):
    """Generate alert if we're at a key level."""
    if not dist:
        return None, None
    
    alert = None
    msg = None
    
    # In 1-up (downtrend bounce): SELL if bounce is exhausted
    if pos.phase == '1-up' and regime == 'DOWN':
        if pos.moved_pct >= dist.half1_median:
            alert = '1-UP CEILING'
            msg = f"🔴 SELL ZONE — 1-up bounce exhausted (+{pos.moved_pct:.1f}% ≥ median {dist.half1_median:.1f}%) — 2-down incoming"
    
    # In 2-down (downtrend drop): BUY if drop is exhausted
    elif pos.phase == '2-down' and regime == 'DOWN':
        if pos.moved_pct >= dist.half2_median:
            alert = '2-DOWN FLOOR'
            msg = f"🟢 BUY ZONE — 2-down drop exhausted (-{pos.moved_pct:.1f}% ≥ median {dist.half2_median:.1f}%) — 1-up bounce incoming"
    
    # In 1-down (uptrend pullback): BUY if pullback exhausted
    elif pos.phase == '1-down' and regime == 'UP':
        if pos.moved_pct >= dist.half1_median:
            alert = '1-DOWN FLOOR'
            msg = f"🟢 BUY ZONE — 1-down pullback exhausted (-{pos.moved_pct:.1f}% ≥ median {dist.half1_median:.1f}%) — 2-up extension incoming"
    
    # In 2-up (uptrend extension): SELL if extension exhausted
    elif pos.phase == '2-up' and regime == 'UP':
        if pos.moved_pct >= dist.half2_median:
            alert = '2-UP CEILING'
            msg = f"🔴 SELL ZONE — 2-up extension exhausted (+{pos.moved_pct:.1f}% ≥ median {dist.half2_median:.1f}%) — 1-down pullback incoming"
    
    # Dedup: 30 min cooldown
    if alert and last_scan:
        last_alert = last_scan.get('last_alert')
        last_time = last_scan.get('last_alert_time', '')
        if last_alert == alert and last_time:
            try:
                elapsed = (datetime.utcnow() - datetime.fromisoformat(last_time)).total_seconds()
                if elapsed < 1800:
                    return None, None
            except:
                pass
    
    return alert, msg


# ─── Format output ───

def format_scan(ticker, result):
    lines = []
    
    regime_icon = "📈" if result.regime == "UP" else "📉"
    pos = result.pos
    
    # Phase icons
    phase_icons = {
        '1-up': '⏫', '2-down': '⏬',
        '1-down': '⏬', '2-up': '⏫',
    }
    phase_icon = phase_icons.get(pos.phase, '⚪')
    
    # Action from phase
    if pos.phase == '1-up' and result.regime == 'DOWN':
        action = '🔴 WAIT TO SELL at ceiling'
    elif pos.phase == '2-down' and result.regime == 'DOWN':
        action = '🟢 WAIT TO BUY at floor'
    elif pos.phase == '1-down' and result.regime == 'UP':
        action = '🟢 WAIT TO BUY at floor'
    elif pos.phase == '2-up' and result.regime == 'UP':
        action = '🔴 WAIT TO SELL at ceiling'
    else:
        action = '⚪ OBSERVE'
    
    lines.append(f"{regime_icon} **{ticker} 1H Wave** ${result.price:.2f}")
    lines.append(f"🏔️ Regime: {result.regime} | Pattern: {result.regime_pattern}")
    lines.append(f"📍 Now: {phase_icon} **{pos.phase}** ({pos.bars_in}h in | moved {pos.moved_pct:.1f}%)")
    lines.append(f"🎯 Action: {action}")
    
    # Targets
    if result.dist and result.dist.n >= 2:
        if pos.phase in ('1-up', '2-up') and pos.remaining_pct > 0:
            target_dir = 'UP'
            target_price = pos.current_price * (1 + pos.remaining_pct / 100) if pos.remaining_pct > 0 else pos.current_price
            lines.append(f"🎯 Target: ${target_price:.2f} (+{pos.remaining_pct:.1f}% remaining)")
        elif pos.phase in ('2-down', '1-down') and pos.remaining_pct > 0:
            target_dir = 'DOWN'
            target_price = pos.current_price * (1 - pos.remaining_pct / 100) if pos.remaining_pct > 0 else pos.current_price
            lines.append(f"🎯 Target: ${target_price:.2f} (-{pos.remaining_pct:.1f}% remaining)")
        
        # Next phase preview
        if pos.phase == '1-up' and result.regime == 'DOWN':
            next_target = pos.current_price * (1 - result.dist.half2_median / 100)
            lines.append(f"⏭️ After ceiling: 2-down to ${next_target:.2f} (-{result.dist.half2_median:.1f}%)")
        elif pos.phase == '2-down' and result.regime == 'DOWN':
            next_target = pos.current_price * (1 + result.dist.half1_median / 100)
            lines.append(f"⏭️ After floor: 1-up to ${next_target:.2f} (+{result.dist.half1_median:.1f}%)")
        elif pos.phase == '1-down' and result.regime == 'UP':
            next_target = pos.current_price * (1 + result.dist.half2_median / 100)
            lines.append(f"⏭️ After floor: 2-up to ${next_target:.2f} (+{result.dist.half2_median:.1f}%)")
        elif pos.phase == '2-up' and result.regime == 'UP':
            next_target = pos.current_price * (1 - result.dist.half1_median / 100)
            lines.append(f"⏭️ After ceiling: 1-down to ${next_target:.2f} (-{result.dist.half1_median:.1f}%)")
    
    # Last 3 cycles
    if result.last_cycles:
        lines.append(f"📊 Last 3 cycles:")
        for cy in result.last_cycles[-3:]:
            h1 = cy.half1
            h2 = cy.half2
            lines.append(f"  {h1.label} {h1.amplitude_pct:.1f}%/{h1.duration_bars}h → {h2.label} {h2.amplitude_pct:.1f}%/{h2.duration_bars}h (ratio {cy.ratio:.1f}x)")
    
    # Distribution
    if result.dist and result.dist.n >= 2:
        d = result.dist
        lines.append(f"📐 Dist (N={d.n}): {result.regime_pattern.split('→')[0].strip()} med={d.half1_median:.1f}% | {result.regime_pattern.split('→')[1].strip()} med={d.half2_median:.1f}%")
    
    # Alert
    if result.alert_msg:
        lines.append(f"")
        lines.append(result.alert_msg)
    
    # Performance
    perf_fn = TICKERS[ticker]["perf_fn"]
    lines.append(perf_fn())
    
    return "\n".join(lines)


# ─── Main scan ───

def run_scan(ticker, send_alerts=True):
    if ticker not in TICKERS:
        print(f"Unknown: {ticker}")
        return None
    
    sym = TICKERS[ticker]["perf_fn"].__module__.replace('signal_perf', ticker)  # hacky but works
    
    # Fetch
    data = fetch_1h(TICKERS[ticker]["symbol"], 30)
    if data is None:
        return None
    o, h, l, c, v = data
    c = c.astype(float); h = h.astype(float); l = l.astype(float)
    price = float(c[-1])
    
    # MTF regime
    regime, alignment = get_mtf_regime(ticker)
    
    # Determine the ACTIVE 1H pattern from regime
    # BUT: if daily price action is clearly descending on 1H, use that
    # Check: last 12 bars — are they making lower highs?
    recent = c[-12:]
    first_high = float(np.max(recent[:6]))
    second_high = float(np.max(recent[6:]))
    first_low = float(np.min(recent[:6]))
    second_low = float(np.min(recent[6:]))
    
    descending = second_high < first_high and second_low < first_low
    ascending = second_high > first_high and second_low > first_low
    
    # Determine pattern: follow regime UNLESS 1H structure clearly disagrees
    if descending and not ascending:
        pattern = '1↑→2↓'
        active_regime = 'DOWN'
    elif ascending and not descending:
        pattern = '1↓→2↑'
        active_regime = 'UP'
    else:
        # Use regime
        if regime == 'UP':
            pattern = '1↓→2↑'
            active_regime = 'UP'
        else:
            pattern = '1↑→2↓'
            active_regime = 'DOWN'
    
    # Swings
    swings = find_swings(h, l)
    
    # Extract cycles based on active pattern
    if active_regime == 'DOWN':
        cycles = extract_cycles_downtrend(swings)
    else:
        cycles = extract_cycles_uptrend(swings)
    
    dist = compute_distribution(cycles)
    
    # Current position
    pos = find_current_position(swings, price, len(c), dist, active_regime)
    
    # Load last scan for dedup
    scan_file = STORAGE / f"last_1h_scan_{ticker.lower()}.json"
    last_scan = None
    if scan_file.exists():
        try:
            last_scan = json.loads(scan_file.read_text())
        except:
            pass
    
    # Alert
    alert, alert_msg = check_alert(pos, dist, price, active_regime, last_scan)
    
    result = ScanResult(
        ticker=ticker, price=price,
        regime=active_regime, alignment=alignment,
        regime_pattern=pattern,
        dist=dist, pos=pos,
        last_cycles=cycles,
        alert=alert, alert_msg=alert_msg,
    )
    
    # Save state
    save = {
        'price': price, 'phase': pos.phase, 'bars_in': pos.bars_in,
        'moved_pct': pos.moved_pct, 'regime': active_regime,
        'last_alert': alert,
        'last_alert_time': datetime.utcnow().isoformat() if alert else (last_scan or {}).get('last_alert_time', ''),
    }
    try:
        scan_file.write_text(json.dumps(save, indent=2))
    except:
        pass
    
    # Format and print
    formatted = format_scan(ticker, result)
    print(formatted)
    
    # Send telegram on alert
    if send_alerts and alert:
        try:
            from telegram_bot import send_message
            send_message(formatted)
        except:
            pass
    
    return result


if __name__ == "__main__":
    ticker = sys.argv[1] if len(sys.argv) > 1 else "WTI"
    send = "--no-send" not in sys.argv
    run_scan(ticker, send_alerts=send)