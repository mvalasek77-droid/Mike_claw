#!/usr/bin/env python3
"""
W-M Tactical Scanner v4
========================
Intraday-focused: 30m / 1h / 2h tactical briefings.
12:50 PM EOD: after-hours expected move.
Rejects gibberish patterns via quality filters.

Timeframes:
  15m → 30m signal window
  1h  → 1h signal window
  1d  → 2h signal window (macro context)
  1M  → regime filter only (bull/bear bias)

Signal quality:
  - Minimum 2% amplitude (rejects noise)
  - Symmetry check: two tops/bottoms within 5%
  - Only outputs action if confidence ≥ 60%
"""

import sys, json, numpy as np, yfinance as yf
from pathlib import Path
from datetime import datetime, timedelta
from scipy.signal import argrelextrema
from pytz import timezone

STORAGE = Path(__file__).parent / "storage"
STORAGE.mkdir(exist_ok=True)
TICKERS = {
    "WTI":  {"symbol": "CL=F"},
    "RGTI": {"symbol": "RGTI"},
    "QBTX": {"symbol": "QBTX"},
}

ET = timezone('US/Eastern')
PT = timezone('US/Pacific')

# ═══════════════════════════════════════════════════════
# MINIMUM PATTERN QUALITY — NO GIBBERISH
# ═══════════════════════════════════════════════════════

MIN_AMPLITUDE_PCT = 2.0    # pattern must span ≥2% price range
MAX_ASYMMETRY     = 0.08    # two tops/bottoms within 8% of each other
MIN_CONFIDENCE    = 0.55    # reject low-confidence patterns

# Completion probability (Bulkowski 2005)
COMPLETION_PROB = {
    'W': {0: 0.37, 1: 0.52, 2: 0.68, 3: 0.76, 4: 0.89, 5: 1.0},
    'M': {0: 0.35, 1: 0.48, 2: 0.63, 3: 0.72, 4: 0.87, 5: 1.0},
}

def stage_from_pct(pct):
    if pct < 10: return 0
    if pct < 25: return 1
    if pct < 45: return 2
    if pct < 65: return 3
    if pct < 85: return 4
    return 5

# ═══════════════════════════════════════════════════════
# DATA FETCHING
# ═══════════════════════════════════════════════════════

def fetch_multi(symbol):
    """Fetch all timeframes. Returns dict with 15m, 1h, 1d, 1m data."""
    out = {}
    
    # 15m — last 5 trading days (intraday only, 30m signals)
    try:
        df = yf.Ticker(symbol).history(period="5d", interval="15m")
        if not df.empty:
            out['15m'] = {
                'high': df['High'].values.astype(float),
                'low':  df['Low'].values.astype(float),
                'close': df['Close'].values.astype(float),
                'open':  df['Open'].values.astype(float),
                'index': df.index,
            }
    except: pass
    
    # 1h — last 30 days (1h signals)
    try:
        df = yf.Ticker(symbol).history(period="30d", interval="1h")
        if not df.empty:
            out['1h'] = {
                'high': df['High'].values.astype(float),
                'low':  df['Low'].values.astype(float),
                'close': df['Close'].values.astype(float),
                'open':  df['Open'].values.astype(float),
                'index': df.index,
            }
    except: pass
    
    # 1d — 6 months (2h / macro)
    try:
        df = yf.Ticker(symbol).history(period="6mo", interval="1d")
        if not df.empty:
            out['1d'] = {
                'high': df['High'].values.astype(float),
                'low':  df['Low'].values.astype(float),
                'close': df['Close'].values.astype(float),
            }
    except: pass
    
    # 1m — 5 years (regime filter only)
    try:
        df = yf.Ticker(symbol).history(period="5y", interval="1mo")
        if not df.empty:
            out['1m'] = {
                'high': df['High'].values.astype(float),
                'low':  df['Low'].values.astype(float),
                'close': df['Close'].values.astype(float),
            }
    except: pass
    
    return out


# ═══════════════════════════════════════════════════════
# ATR (Average True Range)
# ═══════════════════════════════════════════════════════

def compute_atr(highs, lows, closes, period=14):
    if len(highs) < 2: return 0
    tr = np.maximum(highs[1:] - lows[1:],
                    np.maximum(np.abs(highs[1:] - closes[:-1]),
                               np.abs(lows[1:] - closes[:-1])))
    if len(tr) < period: return float(np.mean(tr))
    return float(np.mean(tr[-period:]))

def compute_rsi(closes, period=14):
    if len(closes) < period + 1: return 50
    deltas = np.diff(closes[-period*3:])
    gains = np.where(deltas > 0, deltas, 0)
    losses = np.where(deltas < 0, -deltas, 0)
    avg_gain = np.mean(gains[-period:])
    avg_loss = np.mean(losses[-period:])
    if avg_loss == 0: return 100
    rs = avg_gain / avg_loss
    return 100 - 100 / (1 + rs)

def compute_vwap(closes, highs, lows, volumes=None):
    """Simple typical price VWAP approximation."""
    tp = (highs + lows + closes) / 3
    if volumes is not None and len(volumes) > 0:
        return float(np.sum(tp * volumes) / np.sum(volumes))
    return float(np.mean(tp[-20:]))

def compute_ema(closes, period=20):
    if len(closes) < period: return float(closes[-1])
    ema = float(closes[0])
    k = 2 / (period + 1)
    for c in closes[1:]:
        ema = c * k + ema * (1 - k)
    return ema


# ═══════════════════════════════════════════════════════
# LETTER DETECTION — QUALITY FILTERED
# ═══════════════════════════════════════════════════════

def detect_letters(highs, lows, closes, order=3, min_amp_pct=MIN_AMPLITUDE_PCT):
    """Detect W/M letters, rejecting gibberish via symmetry + amplitude checks."""
    hi = argrelextrema(highs, np.greater, order=order)[0]
    lo = argrelextrema(lows, np.less, order=order)[0]
    if len(hi) < 2 or len(lo) < 2: return []

    swings = [(int(i), float(highs[i]), 'H') for i in hi] + [(int(i), float(lows[i]), 'L') for i in lo]
    swings.sort()

    # Filter to alternating H/L
    alt = [swings[0]]
    for s in swings[1:]:
        if s[2] == alt[-1][2]:
            if s[2] == 'H' and s[1] > alt[-1][1]: alt[-1] = s
            elif s[2] == 'L' and s[1] < alt[-1][1]: alt[-1] = s
        else:
            alt.append(s)
    if len(alt) < 3: return []

    # ATR-adaptive minimum amplitude
    if closes is not None and len(closes) > 14:
        atr = compute_atr(highs, lows, closes)
        avg_price = float(np.mean(closes[-20:]))
        atr_pct = atr / avg_price * 100 if avg_price > 0 else 2
        # Minimum amplitude = max of MIN_AMPLITUDE_PCT or 0.5× ATR%
        min_amp = max(min_amp_pct, atr_pct * 0.5)
    else:
        min_amp = min_amp_pct

    raw = []
    for i in range(len(alt) - 2):
        _, ap, at = alt[i]
        _, bp, bt = alt[i+1]
        _, cp, ct = alt[i+2]

        if at == 'L' and bt == 'H' and ct == 'L':
            # W pattern: two bottoms (ap, cp) with peak (bp)
            amp_pct = (bp - min(ap, cp)) / min(ap, cp) * 100
            if amp_pct < min_amp: continue
            # Symmetry: two bottoms within MAX_ASYMMETRY
            asymmetry = abs(ap - cp) / max(ap, cp)
            if asymmetry > MAX_ASYMMETRY: continue
            raw.append(('W', ap, bp, cp, round(amp_pct, 2), round(asymmetry, 4)))

        elif at == 'H' and bt == 'L' and ct == 'H':
            # M pattern: two peaks (ap, cp) with dip (bp)
            amp_pct = (max(ap, cp) - bp) / max(ap, cp) * 100
            if amp_pct < min_amp: continue
            asymmetry = abs(ap - cp) / max(ap, cp)
            if asymmetry > MAX_ASYMMETRY: continue
            raw.append(('M', ap, bp, cp, round(amp_pct, 2), round(asymmetry, 4)))

    if not raw: return []

    # Merge consecutive same-type, keep highest amplitude
    letters = [raw[0]]
    for lt in raw[1:]:
        if lt[0] == letters[-1][0]:
            if lt[4] > letters[-1][4]: letters[-1] = lt
        else:
            letters.append(lt)
    return letters


def find_phase(letters, price):
    """Where is price within the current letter? Returns (type, floor, ceil, pct, action).
    Only returns patterns where price is within range or recently broke out.
    Picks the most recent pattern that price is engaged with."""
    if not letters:
        return 'NONE', 0, 0, 50, 'WAIT'

    # Walk backwards to find the most recent ACTIVE pattern
    # Active = price is within the pattern's range (0-100%, with 5% breakout buffer)
    for last in reversed(letters):
        lt = last[0]
        if lt == 'W':
            floor = min(last[1], last[3])
            ceiling = last[2]
            if ceiling == floor: continue
            raw_pct = (price - floor) / (ceiling - floor) * 100
            if raw_pct < -5 or raw_pct > 105: continue  # skip stale patterns
            pct = max(0, min(100, raw_pct))
            if pct >= 90:
                action = 'SELL'  # W completed → take profit
            elif pct <= 25:
                action = 'BUY'   # Near W bottom → buy
            else:
                action = 'WAIT'
            return 'W', floor, ceiling, pct, action
        else:  # M
            floor = last[2]
            ceiling = max(last[1], last[3])
            if ceiling == floor: continue
            raw_pct = (ceiling - price) / (ceiling - floor) * 100
            if raw_pct < -5 or raw_pct > 105: continue  # skip stale patterns
            pct = max(0, min(100, raw_pct))
            if pct >= 75:
                action = 'SELL'  # Near M top → sell
            elif pct <= 25:
                action = 'BUY'   # M completed → buy the bounce
            else:
                action = 'WAIT'
            return 'M', floor, ceiling, pct, action

    # No active pattern found — price is beyond all of them
    return 'NONE', 0, 0, 50, 'WAIT'


def pattern_confidence(letters):
    """How well does the latest letter match an ideal W/M? 0-1 scale."""
    if not letters: return 0
    last = letters[-1]
    lt = last[0]
    # last = ('W'/'M', price1, price2, price3, amplitude%, asymmetry)
    
    amp = last[4]
    asym = last[5]
    
    # Amplitude score: bigger = more significant
    amp_score = min(1, amp / 10)  # 10%+ amplitude = full score
    
    # Symmetry score: lower asymmetry = better
    sym_score = 1 - min(1, asym / MAX_ASYMMETRY)
    
    # Confidence = weighted
    conf = 0.5 * amp_score + 0.5 * sym_score
    return round(conf, 3)


# ═══════════════════════════════════════════════════════
# DOWN-MOVE DETECTORS (post-crash calibration)
# ═══════════════════════════════════════════════════════

def detect_spike_and_reverse(data_15m, price, tolerance_pct=None):
    """Detect intraday spike-and-reverse pattern (M-top completion → SELL).
    
    Catches patterns like RGTI 6/3:
    - Open $26.56, spike to $28.06 (+5.7%), then crash to $24.61 (-12.3% from peak)
    - The spike IS the second peak of the M, and the reversal confirms it.
    
    Returns dict with spike info or None.
    """
    if data_15m is None or len(data_15m['high']) < 10:
        return None
    
    threshold = tolerance_pct or VELOCITY_THRESHOLDS['spike_reverse_pct']
    
    highs = data_15m['high']
    lows = data_15m['low']
    closes = data_15m['close']
    opens = data_15m['open']
    
    # Find intraday high and check if we're below it significantly
    recent_high = float(np.max(highs[-16:]))  # Last 4 hours
    recent_low = float(np.min(lows[-16:]))
    
    if recent_high <= recent_low:
        return None
    
    # Peak-to-current drawdown
    drawdown_from_peak = (recent_high - price) / recent_high * 100
    
    # Peak-to-trough intraday range
    intraday_range = (recent_high - recent_low) / recent_low * 100
    
    # Is price currently near the low of the range?
    near_low = (price - recent_low) / (recent_high - recent_low) * 100 < 30  # in bottom 30%
    
    # Was the peak reached recently (within last 2 hours)?
    peak_idx = int(np.argmax(highs[-16:]))
    bars_since_peak = 15 - peak_idx  # how many bars ago was the peak
    
    # Spike criteria: big intraday range, price near the lows, peak was recent
    if intraday_range >= threshold and near_low and bars_since_peak <= 8:
        # This is a confirmed spike-and-reverse
        spike_pct = (recent_high - opens[-16]) / opens[-16] * 100  # how much it spiked up
        reverse_pct = drawdown_from_peak  # how much it reversed
        
        return {
            'type': 'SPIKE_REVERSE',
            'peak': round(recent_high, 2),
            'trough': round(recent_low, 2),
            'spike_pct': round(spike_pct, 1),
            'reverse_pct': round(reverse_pct, 1),
            'bars_since_peak': bars_since_peak,
            'action': 'SELL',
            'strength': min(1.0, reverse_pct / 5.0),  # 5%+ reverse = full strength
        }
    
    return None


def detect_dip_and_reverse(data_15m, price, tolerance_pct=None):
    """Detect intraday dip-and-reverse pattern (W-bottom completion → BUY).
    
    Mirror of spike-and-reverse. Catches patterns like WTI bounce from $86.35:
    - Price crashes to $86.35, then snaps back to $92+ (+6.5% from low)
    - The dip IS the second bottom of the W, and the reversal confirms it.
    
    Returns dict with dip info or None.
    """
    if data_15m is None or len(data_15m['low']) < 10:
        return None
    
    threshold = tolerance_pct or VELOCITY_THRESHOLDS['dip_reverse_pct']
    
    highs = data_15m['high']
    lows = data_15m['low']
    closes = data_15m['close']
    opens = data_15m['open']
    
    recent_low = float(np.min(lows[-16:]))   # Last 4 hours
    recent_high = float(np.max(highs[-16:]))
    
    if recent_high <= recent_low:
        return None
    
    # Bounce from dip: current price above the low
    bounce_from_dip = (price - recent_low) / recent_low * 100
    
    # Intraday range
    intraday_range = (recent_high - recent_low) / recent_low * 100
    
    # Is price currently near the high of the range (in top 30%)?
    near_high = (recent_high - price) / (recent_high - recent_low) * 100 < 30
    
    # Was the dip reached recently (within last 2 hours)?
    dip_idx = int(np.argmin(lows[-16:]))
    bars_since_dip = 15 - dip_idx
    
    # Dip criteria: big intraday range, price near highs, dip was recent
    if intraday_range >= threshold and near_high and bars_since_dip <= 8:
        dip_pct = (opens[-16] - recent_low) / opens[-16] * 100  # how much it dipped
        bounce_pct = bounce_from_dip  # how much it bounced
        
        return {
            'type': 'DIP_REVERSE',
            'dip': round(recent_low, 2),
            'peak': round(recent_high, 2),
            'dip_pct': round(dip_pct, 1),
            'bounce_pct': round(bounce_pct, 1),
            'bars_since_dip': bars_since_dip,
            'action': 'BUY',
            'strength': min(1.0, bounce_pct / 5.0),  # 5%+ bounce = full strength
        }
    
    return None


def detect_momentum_acceleration(data_1h, data_15m=None):
    """Detect accelerating momentum in either direction.
    
    SELL: 3+ consecutive red candles (knife falling)
    BUY:  3+ consecutive green candles (rocket launching)
    
    Returns dict with momentum info or None.
    """
    if data_1h is None or len(data_1h['close']) < 5:
        return None
    
    closes_1h = data_1h['close']
    opens_1h = data_1h['open']
    
    # Count consecutive red 1h candles (close < open)
    consec_red = 0
    for i in range(len(closes_1h) - 1, max(len(closes_1h) - 10, -1), -1):
        if closes_1h[i] < opens_1h[i]:
            consec_red += 1
        else:
            break
    
    # Count consecutive green 1h candles (close > open)
    consec_green = 0
    for i in range(len(closes_1h) - 1, max(len(closes_1h) - 10, -1), -1):
        if closes_1h[i] > opens_1h[i]:
            consec_green += 1
        else:
            break
    
    # ── BEARISH MOMENTUM (red candles) ──
    if consec_red >= 2:
        first_red_idx = len(closes_1h) - consec_red
        total_drop = (opens_1h[first_red_idx] - closes_1h[-1]) / opens_1h[first_red_idx] * 100
        
        # Is the drop accelerating? (each candle bigger than last)
        accelerations = []
        for i in range(max(0, len(closes_1h) - consec_red), len(closes_1h)):
            candle_size = abs(opens_1h[i] - closes_1h[i]) / opens_1h[i] * 100
            accelerations.append(candle_size)
        
        is_accelerating = len(accelerations) >= 3 and all(
            accelerations[i] > accelerations[i-1] * 0.8 
            for i in range(1, len(accelerations))
        )
        
        if consec_red >= VELOCITY_THRESHOLDS['consecutive_red'] or (consec_red >= 2 and total_drop >= 2.0):
            return {
                'type': 'MOMENTUM_SELL',
                'consecutive_red': consec_red,
                'total_drop_pct': round(total_drop, 2),
                'accelerating': is_accelerating,
                'action': 'SELL',
                'strength': min(1.0, consec_red / 5.0),  # 5+ red = full strength
            }
    
    # ── BULLISH MOMENTUM (green candles) ──
    if consec_green >= 2:
        first_green_idx = len(closes_1h) - consec_green
        total_gain = (closes_1h[-1] - opens_1h[first_green_idx]) / opens_1h[first_green_idx] * 100
        
        # Is the rally accelerating?
        accelerations = []
        for i in range(max(0, len(closes_1h) - consec_green), len(closes_1h)):
            candle_size = abs(closes_1h[i] - opens_1h[i]) / opens_1h[i] * 100
            accelerations.append(candle_size)
        
        is_accelerating = len(accelerations) >= 3 and all(
            accelerations[i] > accelerations[i-1] * 0.8 
            for i in range(1, len(accelerations))
        )
        
        if consec_green >= VELOCITY_THRESHOLDS['consecutive_green'] or (consec_green >= 2 and total_gain >= 2.0):
            return {
                'type': 'MOMENTUM_BUY',
                'consecutive_green': consec_green,
                'total_gain_pct': round(total_gain, 2),
                'accelerating': is_accelerating,
                'action': 'BUY',
                'strength': min(1.0, consec_green / 5.0),  # 5+ green = full strength
            }
    
    return None


def detect_macro_override(data_1d, data_15m, price, regime):
    """Detect when macro pattern should override micro pattern.
    
    BEARISH: When macro M overrides micro W (WTI $103→$86 crash)
    - 2h detected W because price bounced from $86.35, but the dominant
      pattern was M (double top) from $109.47. The bounce was just
      the right shoulder of the M.
    
    BULLISH: When macro W overrides micro M 
    - Micro M pattern forming while a larger W (macro double bottom)
      is past 40% completion = the M is just the dip before the launch.
    
    Returns dict with override info or None.
    """
    if data_1d is None or len(data_1d['high']) < 20:
        return None
    
    h = data_1d['high']
    l = data_1d['low']
    c = data_1d['close']
    
    # Detect patterns with order=5 for LARGER macro view
    macro_letters = detect_letters(h, l, c, order=5, min_amp_pct=3.0)
    if not macro_letters:
        return None
    
    min_amp = VELOCITY_THRESHOLDS['macro_amp_min']
    
    # ── BEARISH: Macro M overrides micro W ──
    for lt, p1, p2, p3, amp, asym in macro_letters:
        if lt != 'M':
            continue
        
        ceiling = max(p1, p3)
        floor = p2
        
        if ceiling == floor:
            continue
        
        pct_through = (ceiling - price) / (ceiling - floor) * 100
        
        # Price in bottom 40-100% of an M = bearish override
        if 40 <= pct_through <= 100 and amp >= min_amp:
            return {
                'type': 'MACRO_M_OVERRIDE',
                'ceiling': round(ceiling, 2),
                'floor': round(floor, 2),
                'pct': round(pct_through, 1),
                'amplitude': round(amp, 1),
                'action': 'SELL',
                'strength': min(1.0, amp / 15.0),
            }
    
    # ── BULLISH: Macro W overrides micro M ──
    for lt, p1, p2, p3, amp, asym in macro_letters:
        if lt != 'W':
            continue
        
        floor = min(p1, p3)
        ceiling = p2
        
        if ceiling == floor:
            continue
        
        pct_up = (price - floor) / (ceiling - floor) * 100
        
        # Price in top 40-100% of a W = bullish override
        # (W bouncing up from bottom, micro M is just a pullback)
        if 40 <= pct_up <= 100 and amp >= min_amp:
            return {
                'type': 'MACRO_W_OVERRIDE',
                'floor': round(floor, 2),
                'ceiling': round(ceiling, 2),
                'pct': round(pct_up, 1),
                'amplitude': round(amp, 1),
                'action': 'BUY',
                'strength': min(1.0, amp / 15.0),
            }
    
    return None


# ═══════════════════════════════════════════════════════
# REGIME
# ═══════════════════════════════════════════════════════

def detect_regime(closes):
    if len(closes) < 24: return "SIDEWAYS"
    r, p = closes[-12:], closes[-24:-12]
    rh, rl, ph, pl = np.max(r), np.min(r), np.max(p), np.min(p)
    if rh > ph and rl > pl: return "UP"
    if rh < ph and rl < pl: return "DOWN"
    return "SIDEWAYS"


# ═══════════════════════════════════════════════════════
# INTRADAY DOUBLE BOTTOM/TOP (1h data)
# ═══════════════════════════════════════════════════════

def detect_intraday_doubles(highs, lows, timestamps, tolerance=0.03):
    """Detect double bottom/top on intraday data."""
    hi = argrelextrema(highs, np.greater, order=2)[0]
    lo = argrelextrema(lows, np.less, order=2)[0]
    swings = sorted([(int(i), 'H', float(highs[i])) for i in hi] + [(int(i), 'L', float(lows[i])) for i in lo])
    
    filtered = [swings[0]]
    for s in swings[1:]:
        if filtered and filtered[-1][1] == s[1]:
            if s[1] == 'H' and s[2] > filtered[-1][2]: filtered[-1] = s
            elif s[1] == 'L' and s[2] < filtered[-1][2]: filtered[-1] = s
        else:
            filtered.append(s)
    if len(filtered) < 3: return None

    last3 = filtered[-3:]
    if last3[0][1] == 'L' and last3[1][1] == 'H' and last3[2][1] == 'L':
        low1, high, low2 = last3[0][2], last3[1][2], last3[2][2]
        diff = abs(low1 - low2) / max(low1, low2) * 100
        if diff < tolerance * 100:
            return {
                'type': 'DOUBLE_BOTTOM', 'low1': low1, 'low2': low2,
                'high': high, 'diff_pct': round(diff, 2),
                'amplitude': round((high - min(low1, low2)) / min(low1, low2) * 100, 1),
            }
    if last3[0][1] == 'H' and last3[1][1] == 'L' and last3[2][1] == 'H':
        high1, low, high2 = last3[0][2], last3[1][2], last3[2][2]
        diff = abs(high1 - high2) / max(high1, high2) * 100
        if diff < tolerance * 100:
            return {
                'type': 'DOUBLE_TOP', 'high1': high1, 'high2': high2,
                'low': low, 'diff_pct': round(diff, 2),
                'amplitude': round((max(high1, high2) - low) / low * 100, 1),
            }
    return None


# ═══════════════════════════════════════════════════════
# BACKTEST-LEARNED SIGNAL FILTERS
# ═══════════════════════════════════════════════════════
# From 3,781 trades across WTI + RGTI (2y daily + 60d hourly):
#
# M-pattern trades: 86-94% win rate (KING TRADE)
# W-pattern trades: 5-28% win rate (AVOID)
# RSI > 60: 65-82% win rate (strong confirmation)
# RSI < 40: 3-50% win rate (AVOID)
# UP regime: 65-85% win rate (best environment)
# DOWN regime: 42-56% (weaker, avoid BUY signals)
# Confidence 0.6-0.7: sweet spot
# Confidence 0.5 or 0.9: unreliable

SIGNAL_EDGE = {
    # Backtested win rates — updated 2026-06-04 19:32
    'M_BUY':  0.91,   # M near bottom → BUY
    'M_SELL': 0.88,   # M near top → SELL
    'W_BUY':  0.09,   # W near bottom → BUY (weak)
    'W_SELL': 0.09,   # W near top → SELL (weak)
}

# ═══════════════════════════════════════════════════════
# MOVE DETECTORS (post-crash calibration, v5: up+down)
# ═══════════════════════════════════════════════════════
# Missed WTI down ($103→$86.35) and RGTI spike-reverse ($28→$24.6)
# Now also catches up-moves: RGTI quantum pump $16→$27, WTI bounce $86→$97
#
# Three detector PAIRS (down + up mirror):
# 1. Spike/Dip-and-Reverse: intraday peak/trough + reversal
# 2. Momentum Acceleration: 3+ consecutive red/green candles
# 3. Macro Override: M/W pattern on higher timeframe overriding micro signal

VELOCITY_THRESHOLDS = {
    'consecutive_red': 3,       # 3+ red 1h = accelerating sell
    'consecutive_green': 3,     # 3+ green 1h = accelerating buy
    'spike_reverse_pct': 3.0,  # intraday high-to-low > 3% = spike reverse (SELL)
    'dip_reverse_pct': 3.0,    # intraday low-to-high > 3% = dip reverse (BUY)
    'macro_amp_min': 5.0,       # macro pattern min amplitude for override
}

# ═══ LEVEL MEMORY (auto-updated by wm_levels.py) ═══
KEY_LEVELS = {
    "WTI": {
        "resistance": {
            "price": 95.98,
            "hits": 53,
            "patterns": [
                "W",
                "M"
            ]
        },
        "support": {
            "price": 91.8,
            "hits": 26,
            "patterns": [
                "W",
                "M"
            ]
        },
        "resistance_zones": [
            {
                "price": 95.98,
                "hits": 53,
                "str": 16.73
            },
            {
                "price": 103.25,
                "hits": 21,
                "str": 10.17
            },
            {
                "price": 117.63,
                "hits": 2,
                "str": 7.75
            }
        ],
        "support_zones": [
            {
                "price": 89.89,
                "hits": 37,
                "str": 13.73
            },
            {
                "price": 94.66,
                "hits": 42,
                "str": 9.82
            },
            {
                "price": 99.34,
                "hits": 20,
                "str": 9.47
            }
        ],
        "projections": [
            {
                "type": "W_floor",
                "tf": "2h",
                "projected": 73.36,
                "direction": "falling",
                "slope": -0.2117,
                "floor": 80.56,
                "ceiling": 117.63
            },
            {
                "type": "M_ceil",
                "tf": "2h",
                "projected": 101.08,
                "direction": "falling",
                "slope": -0.3941,
                "floor": 80.56,
                "ceiling": 117.63
            },
            {
                "type": "W_floor",
                "tf": "2h",
                "projected": 85.63,
                "direction": "falling",
                "slope": -0.1444,
                "floor": 86.35,
                "ceiling": 109.47
            },
            {
                "type": "M_ceil",
                "tf": "1h",
                "projected": 101.49,
                "direction": "rising",
                "slope": 0.1359,
                "floor": 90.12,
                "ceiling": 97.0
            }
        ]
    },
    "RGTI": {
        "resistance": {
            "price": 24.64,
            "hits": 6,
            "patterns": [
                "W",
                "M"
            ]
        },
        "support": {
            "price": 23.93,
            "hits": 11,
            "patterns": [
                "W",
                "M"
            ]
        },
        "resistance_zones": [
            {
                "price": 27.37,
                "hits": 8,
                "str": 10.27
            },
            {
                "price": 21.02,
                "hits": 4,
                "str": 9.62
            },
            {
                "price": 19.95,
                "hits": 5,
                "str": 6.76
            }
        ],
        "support_zones": [
            {
                "price": 23.93,
                "hits": 11,
                "str": 9.18
            },
            {
                "price": 15.34,
                "hits": 4,
                "str": 8.17
            },
            {
                "price": 21.53,
                "hits": 2,
                "str": 5.07
            }
        ],
        "projections": [
            {
                "type": "M_ceil",
                "tf": "2h",
                "projected": 21.87,
                "direction": "rising",
                "slope": 0.05,
                "floor": 15.3,
                "ceiling": 21.02
            },
            {
                "type": "W_floor",
                "tf": "2h",
                "projected": 15.6,
                "direction": "rising",
                "slope": 0.0114,
                "floor": 15.3,
                "ceiling": 21.02
            },
            {
                "type": "W_floor",
                "tf": "1h",
                "projected": 24.62,
                "direction": "rising",
                "slope": 0.0205,
                "floor": 23.62,
                "ceiling": 27.48
            },
            {
                "type": "M_ceil",
                "tf": "1h",
                "projected": 28.43,
                "direction": "rising",
                "slope": 0.0264,
                "floor": 24.05,
                "ceiling": 28.06
            }
        ]
    },
    "QBTX": {
        "resistance": {
            "price": 22.87,
            "hits": 4,
            "patterns": [
                "W",
                "M"
            ]
        },
        "support": {
            "price": 22.41,
            "hits": 3,
            "patterns": [
                "W",
                "M"
            ]
        },
        "resistance_zones": [
            {
                "price": 20.15,
                "hits": 3,
                "str": 17.02
            },
            {
                "price": 19.37,
                "hits": 3,
                "str": 13.14
            },
            {
                "price": 52.19,
                "hits": 2,
                "str": 12.25
            }
        ],
        "support_zones": [
            {
                "price": 10.03,
                "hits": 2,
                "str": 11.91
            },
            {
                "price": 13.99,
                "hits": 3,
                "str": 9.75
            },
            {
                "price": 12.37,
                "hits": 2,
                "str": 9.36
            }
        ],
        "projections": [
            {
                "type": "W_floor",
                "tf": "2h",
                "projected": 10.14,
                "direction": "rising",
                "slope": 0.0057,
                "floor": 9.99,
                "ceiling": 20.15
            },
            {
                "type": "M_ceil",
                "tf": "1h",
                "projected": 22.14,
                "direction": "falling",
                "slope": -0.109,
                "floor": 19.2,
                "ceiling": 28.79
            },
            {
                "type": "W_floor",
                "tf": "30m",
                "projected": 18.04,
                "direction": "falling",
                "slope": -0.0913,
                "floor": 20.23,
                "ceiling": 22.7
            },
            {
                "type": "M_ceil",
                "tf": "30m",
                "projected": 23.3,
                "direction": "rising",
                "slope": 0.0192,
                "floor": 20.23,
                "ceiling": 22.95
            }
        ]
    }
}































def signal_grade(pattern_type, action, rsi, regime, confidence):
    """Grade signal quality based on backtested edge. Returns (grade, emoji, notes)."""
    key = f"{pattern_type}_{action}"
    edge = SIGNAL_EDGE.get(key, 0.50)
    # Support both float (auto-learn) and tuple (manual) formats
    if isinstance(edge, tuple):
        base_wr = edge[0]
        emoji = edge[1]
    else:
        base_wr = edge
        emoji = "🎯"
    
    notes = []
    adj_wr = base_wr
    
    # RSI filter
    if rsi is not None:
        if rsi >= 70:
            adj_wr += 0.10
            notes.append("RSI OB+")
        elif rsi >= 60:
            adj_wr += 0.05
        elif rsi < 30:
            adj_wr -= 0.25
            notes.append("RSI⚠️")
        elif rsi < 40:
            adj_wr -= 0.15
            notes.append("RSI weak")
    
    # Regime filter
    if regime == 'UP':
        if action == 'BUY':
            adj_wr += 0.05  # UP regime confirms BUY signals
        elif action == 'SELL':
            adj_wr -= 0.05  # UP regime contradicts SELL signals
    elif regime == 'DOWN':
        if action == 'BUY':
            adj_wr -= 0.10
            notes.append("DOWN←BUY")
        elif action == 'SELL':
            adj_wr += 0.05  # DOWN regime confirms SELL signals
    
    # Confidence filter — backtest shows 0.65-0.75 is sweet spot (63.6%)
    # <0.55 is noisy, >0.85 is unreliable (33.6%) EXCEPT M-patterns (93% edge)
    if confidence < 0.55:
        adj_wr -= 0.10
        notes.append("conf⚠️")
    elif confidence > 0.85 and key.startswith('M_'):
        adj_wr += 0.03  # M-patterns: high confidence is actually good
        notes.append("conf✓")
    
    # Grade
    if adj_wr >= 0.75:
        grade = "A"
    elif adj_wr >= 0.60:
        grade = "B"
    elif adj_wr >= 0.45:
        grade = "C"
    else:
        grade = "D"
    
    # W-pattern always at least C (avoid)
    if key in ('W_BUY', 'W_SELL'):
        grade = "D"
        if not notes:
            notes.append("W-pattern: low edge")
    
    return grade, emoji, " | ".join(notes) if notes else "", round(adj_wr, 2)
# ═══════════════════════════════════════════════════════

def tactical_signal(data_15m, data_1h, data_1d, price, regime, atr_price):
    """
    Generate tactical signal tiers:
    - 30m: based on 15m pattern
    - 1h:  based on 1h pattern
    - 2h:  based on 1d pattern
    Returns dict of timeframe → signal info.
    """
    signals = {}
    
    # ── 30m signal (15m data) ──
    if data_15m is not None and len(data_15m['close']) > 20:
        h, l, c = data_15m['high'], data_15m['low'], data_15m['close']
        letters = detect_letters(h, l, c, order=2, min_amp_pct=0.5)
        if letters:
            lt, floor, ceil, pct, action = find_phase(letters, price)
            conf = pattern_confidence(letters)
            if conf >= MIN_CONFIDENCE and lt in ('W', 'M'):
            # Target/stop: BUY always targets UP, SELL always targets DOWN
                # BUY near bottom of W or M → target ceiling (upside), stop floor (downside)
                # SELL near top of W or M → target floor (downside), stop ceiling (upside)
                if action == 'BUY':
                    target = ceil  # upside where we take profit
                    stop = floor    # downside where we cut loss
                else:  # SELL
                    target = floor   # downside where we take profit
                    stop = ceil      # upside where we cut loss
                rsi = compute_rsi(c, 14)
                signals['30m'] = {
                    'type': lt, 'pct': pct, 'action': action,
                    'target': round(target, 2), 'stop': round(stop, 2),
                    'confidence': conf, 'rsi': round(rsi, 1),
                    'amplitude': letters[-1][4],
                }
    
    # ── 1h signal (1h data) ──
    if data_1h is not None and len(data_1h['close']) > 20:
        h, l, c = data_1h['high'], data_1h['low'], data_1h['close']
        letters = detect_letters(h, l, c, order=3, min_amp_pct=1.0)
        if letters:
            lt, floor, ceil, pct, action = find_phase(letters, price)
            conf = pattern_confidence(letters)
            if conf >= MIN_CONFIDENCE and lt in ('W', 'M'):
                # BUY always targets UP (ceil), SELL always targets DOWN (floor)
                if action == 'BUY':
                    target, stop = ceil, floor
                else:
                    target, stop = floor, ceil
                rsi = compute_rsi(c, 14)
                ema20 = compute_ema(c, 20)
                trend = "↑" if price > ema20 else "↓"
                signals['1h'] = {
                    'type': lt, 'pct': pct, 'action': action,
                    'target': round(target, 2), 'stop': round(stop, 2),
                    'confidence': conf, 'rsi': round(rsi, 1),
                    'amplitude': letters[-1][4], 'trend': trend,
                }
        # Also check intraday doubles
        doubles = detect_intraday_doubles(h, l, data_1h.get('index', range(len(h))), tolerance=0.03)
        if doubles:
            dtype = doubles['type']
            d_action = 'BUY' if dtype == 'DOUBLE_BOTTOM' else 'SELL'
            signals['1h_double'] = {
                'type': dtype, 'action': d_action,
                'level': round(doubles['low1'] if 'low1' in doubles else doubles.get('high1', 0), 2),
                'amplitude': doubles['amplitude'],
            }
    
    # ── 2h signal (1d data) ──
    if data_1d is not None and len(data_1d['close']) > 20:
        h, l, c = data_1d['high'], data_1d['low'], data_1d['close']
        letters = detect_letters(h, l, c, order=3, min_amp_pct=2.0)
        if letters:
            lt, floor, ceil, pct, action = find_phase(letters, price)
            conf = pattern_confidence(letters)
            if conf >= MIN_CONFIDENCE and lt in ('W', 'M'):
                # BUY always targets UP (ceil), SELL always targets DOWN (floor)
                if action == 'BUY':
                    target, stop = ceil, floor
                else:
                    target, stop = floor, ceil
                rsi = compute_rsi(c, 14)
                ema50 = compute_ema(c, 50)
                trend = "↑" if price > ema50 else "↓"
                # Completion probability
                stage = stage_from_pct(pct)
                comp_prob = COMPLETION_PROB.get(lt, COMPLETION_PROB['W']).get(stage, 0.5)
                # 1M regime adjustment
                regime_adj = {'UP': {'W': 0.04, 'M': -0.03}, 'DOWN': {'W': -0.04, 'M': 0.03}, 'SIDEWAYS': {'W': 0, 'M': 0}}
                comp_prob += regime_adj.get(regime, {'W': 0, 'M': 0}).get(lt, 0)
                comp_prob = max(0, min(1, comp_prob))
                signals['2h'] = {
                    'type': lt, 'pct': pct, 'action': action,
                    'target': round(target, 2), 'stop': round(stop, 2),
                    'confidence': conf, 'rsi': round(rsi, 1),
                    'amplitude': letters[-1][4], 'trend': trend,
                    'comp_prob': round(comp_prob, 2),
                    'floor': round(floor, 2), 'ceil': round(ceil, 2),
                }
    
    # ── 2 UP 1 DOWN (short-term 1h trading pattern) ──
    # Classic pattern: 2 green bars then 1 red = buy the dip
    #                  2 red bars then 1 green = sell the pop
    # Plus: double top/bottom on 1h confirms reversal
    if data_1h is not None and len(data_1h['close']) >= 8:
        o1h = data_1h['open']
        c1h = data_1h['close']
        h1h = data_1h['high']
        l1h = data_1h['low']
        
        # Analyze last 7 bars for 2U1D patterns
        recent_bars = []
        for i in range(max(0, len(c1h) - 7), len(c1h)):
            bar_color = 'G' if c1h[i] > o1h[i] else 'R'
            body_pct = abs(c1h[i] - o1h[i]) / o1h[i] * 100
            wick_up = (h1h[i] - max(c1h[i], o1h[i])) / o1h[i] * 100
            wick_down = (min(c1h[i], o1h[i]) - l1h[i]) / o1h[i] * 100
            recent_bars.append({
                'color': bar_color,
                'body': round(body_pct, 2),
                'wick_up': round(wick_up, 2),
                'wick_down': round(wick_down, 2),
                'high': round(float(h1h[i]), 2),
                'low': round(float(l1h[i]), 2),
                'close': round(float(c1h[i]), 2),
                'open': round(float(o1h[i]), 2),
            })
        
        # Detect 2U1D patterns ending at current bar
        # Pattern: G G R → BUY (2 up, 1 down pullback = entry)
        # Pattern: R R G → SELL (2 down, 1 up bounce = exit)
        patterns_2u1d = []
        
        if len(recent_bars) >= 3:
            last3 = [b['color'] for b in recent_bars[-3:]]
            b = recent_bars[-1]  # current bar
            
            # 2 UP 1 DOWN: G G R → BUY the pullback
            if last3 == ['G', 'G', 'R']:
                g1, g2, r1 = recent_bars[-3], recent_bars[-2], recent_bars[-1]
                avg_up = (g1['body'] + g2['body']) / 2
                pullback_pct = r1['body']
                # Good setup: strong up bars, small pullback (< 50% of avg up)
                if pullback_pct < avg_up * 0.7:  # pullback less than 70% of up move
                    strength = min(1.0, avg_up / 3.0)  # 3%+ avg up = full strength
                    patterns_2u1d.append({
                        'type': '2U1D_BUY',
                        'action': 'BUY',
                        'avg_up_pct': round(avg_up, 2),
                        'pullback_pct': pullback_pct,
                        'pullback_ratio': round(pullback_pct / max(avg_up, 0.01), 2),
                        'entry': r1['low'],
                        'target': round(float(max(g1['high'], g2['high'])), 2),
                        'stop': round(r1['low'], 2),
                        'strength': round(strength, 2),
                        'bars': f"{g1['body']:.1f}%↑ {g2['body']:.1f}%↑ {r1['body']:.1f}%↓",
                    })
            
            # 2 DOWN 1 UP: R R G → SELL the bounce
            elif last3 == ['R', 'R', 'G']:
                r1, r2, g1 = recent_bars[-3], recent_bars[-2], recent_bars[-1]
                avg_down = (r1['body'] + r2['body']) / 2
                bounce_pct = g1['body']
                # Good setup: strong down bars, small bounce (< 50% of avg down)
                if bounce_pct < avg_down * 0.7:
                    strength = min(1.0, avg_down / 3.0)
                    patterns_2u1d.append({
                        'type': '2D1U_SELL',
                        'action': 'SELL',
                        'avg_down_pct': round(avg_down, 2),
                        'bounce_pct': bounce_pct,
                        'bounce_ratio': round(bounce_pct / max(avg_down, 0.01), 2),
                        'entry': g1['high'],
                        'target': round(float(min(r1['low'], r2['low'])), 2),
                        'stop': round(g1['high'], 2),
                        'strength': round(strength, 2),
                        'bars': f"{r1['body']:.1f}%↓ {r2['body']:.1f}%↓ {g1['body']:.1f}%↑",
                    })
            
            # Extended patterns (4-5 bars)
            # G G R G → BUY with pullback already bounced (stronger)
            if len(recent_bars) >= 4:
                last4 = [b['color'] for b in recent_bars[-4:]]
                if last4 == ['G', 'G', 'R', 'G']:
                    g1, g2, r1, g3 = recent_bars[-4:]
                    total_up = g1['body'] + g2['body']
                    pullback = r1['body']
                    bounce = g3['body']
                    if bounce > pullback * 0.5:  # bounce recovering more than half the pullback
                        patterns_2u1d.append({
                            'type': '2U1D_BUYSIG',
                            'action': 'BUY',
                            'avg_up_pct': round(total_up / 2, 2),
                            'pullback_pct': pullback,
                            'bounce_pct': bounce,
                            'entry': recent_bars[-1]['close'],
                            'target': round(float(max(g1['high'], g2['high'], g3.get('high', 0))), 2),
                            'stop': round(float(r1['low']), 2),
                            'strength': round(min(1.0, (total_up / 2) / 3.0), 2),
                            'bars': f"↑{g1['body']:.1f}% ↑{g2['body']:.1f}% ↓{r1['body']:.1f}% ↑{g3['body']:.1f}%",
                        })
                
                # R R G R → SELL with bounce already failed (stronger)
                if last4 == ['R', 'R', 'G', 'R']:
                    r1, r2, g1, r3 = recent_bars[-4:]
                    total_down = r1['body'] + r2['body']
                    bounce = g1['body']
                    continuation = r3['body']
                    if continuation > bounce * 0.5:  # selling continuing stronger than bounce
                        patterns_2u1d.append({
                            'type': '2D1U_SELLSIG',
                            'action': 'SELL',
                            'avg_down_pct': round(total_down / 2, 2),
                            'bounce_pct': bounce,
                            'continuation_pct': continuation,
                            'entry': recent_bars[-1]['close'],
                            'target': round(float(min(r1['low'], r2['low'], r3['low'])), 2),
                            'stop': round(float(g1['high']), 2),
                            'strength': round(min(1.0, (total_down / 2) / 3.0), 2),
                            'bars': f"↓{r1['body']:.1f}% ↓{r2['body']:.1f}% ↑{g1['body']:.1f}% ↓{r3['body']:.1f}%",
                        })
        
        # Check for double top/bottom on 1h (confirms reversal)
        if '1h_double' not in signals and data_1h is not None and len(data_1h['close']) > 20:
            h1h_arr = data_1h['high']
            l1h_arr = data_1h['low']
            idx_arr = data_1h.get('index', range(len(h1h_arr)))
            doubles = detect_intraday_doubles(h1h_arr, l1h_arr, idx_arr, tolerance=0.03)
            # Only add if within last 5 bars (fresh)
            if doubles:
                db_type = doubles['type']
                signals['1h_double'] = {
                    'type': db_type,
                    'action': 'BUY' if db_type == 'DOUBLE_BOTTOM' else 'SELL',
                    'level': round(doubles.get('low1', doubles.get('high1', 0)), 2),
                    'amplitude': doubles['amplitude'],
                }
        
        if patterns_2u1d:
            signals['2u1d'] = patterns_2u1d[-1]  # most recent pattern
            if len(patterns_2u1d) > 1:
                signals['2u1d_extended'] = patterns_2u1d[0]  # extended pattern if exists
    
    # ── MOVE DETECTORS (down + up, v5) ──
    # These override pattern-based signals when momentum is clearly directional
    
    # 1) Spike-and-reverse (intraday M-top → SELL)
    spike = detect_spike_and_reverse(data_15m, price)
    if spike:
        if '30m' not in signals or signals['30m']['action'] != 'SELL' or spike['strength'] > 0.7:
            signals['spike'] = spike
    
    # 1b) Dip-and-reverse (intraday W-bottom → BUY)
    dip = detect_dip_and_reverse(data_15m, price)
    if dip:
        if '30m' not in signals or signals['30m']['action'] != 'BUY' or dip['strength'] > 0.7:
            signals['dip'] = dip
    
    # 2) Momentum acceleration (consecutive candles, either direction)
    momentum = detect_momentum_acceleration(data_1h, data_15m)
    if momentum:
        signals['momentum'] = momentum
    
    # 3) Macro M override (dominant M on higher TF → SELL)
    macro = detect_macro_override(data_1d, data_15m, price, regime)
    if macro:
        signals['macro'] = macro
        if macro['type'] == 'MACRO_M_OVERRIDE' and '2h' in signals and signals['2h']['type'] == 'W':
            signals['2h']['_macro_override'] = True
            signals['2h']['_macro_note'] = f"⚠️ Macro M ${macro['ceiling']}→${macro['floor']} overrides W"
        elif macro['type'] == 'MACRO_W_OVERRIDE' and '2h' in signals and signals['2h']['type'] == 'M':
            signals['2h']['_macro_override'] = True
            signals['2h']['_macro_note'] = f"🟢 Macro W ${macro['floor']}→${macro['ceiling']} overrides M"

    return signals


# ═══════════════════════════════════════════════════════
# AFTER-HOURS EXPECTED MOVE (12:50 PM EOD)
# ═══════════════════════════════════════════════════════

def after_hours_move(data_1d, data_1h, price, regime, atr_price):
    """
    Expected after-hours move based on:
    - Recent daily range (ATR)
    - 1h closing momentum
    - Regime bias
    - Pattern direction bias
    """
    if data_1d is None or len(data_1d['close']) < 20:
        return None
    
    c = data_1d['close']
    h = data_1d['high']
    l = data_1d['low']
    
    # ATR
    atr = compute_atr(h, l, c, period=14)
    
    # Recent daily ranges (last 5 days)
    ranges = h[-5:] - l[-5:]
    avg_range = float(np.mean(ranges))
    
    # Gap stats (last 10 days)
    opens = data_1d.get('open', c[:-1])
    gaps = []
    for i in range(max(1, len(c)-10), len(c)):
        if i > 0:
            gap = (c[i-1] - opens[i-1]) / c[i-1] * 100 if len(opens) > i else 0
            gaps.append(abs(gap))
    avg_gap_pct = float(np.mean(gaps)) if gaps else 0.5
    
    # 1h momentum (last 4 candles)
    if data_1h is not None and len(data_1h['close']) > 4:
        h1c = data_1h['close']
        momentum = (h1c[-1] - h1c[-4]) / h1c[-4] * 100
    else:
        momentum = 0
    
    # Direction bias from regime
    regime_bias = {"UP": 0.3, "DOWN": -0.3, "SIDEWAYS": 0}[regime]
    
    # Expected move: ATR-based, biased by regime + momentum
    expected_up = atr * (0.5 + max(0, momentum/2 + regime_bias) * 0.5)
    expected_down = atr * (0.5 + max(0, -momentum/2 - regime_bias) * 0.5)
    
    # If 1D pattern exists, bias further
    letters_1d = detect_letters(h, l, c, order=3, min_amp_pct=2.0)
    if letters_1d:
        lt, floor, ceil, pct, _ = find_phase(letters_1d, price)
        if lt == 'W' and pct > 50:
            expected_up *= 1.3  # W breaking up
            expected_down *= 0.7
        elif lt == 'M' and pct > 50:
            expected_down *= 1.3  # M breaking down
            expected_up *= 0.7
    
    return {
        'expected_up': round(price + expected_up, 2),
        'expected_down': round(price - expected_down, 2),
        'atr': round(atr, 2),
        'avg_daily_range': round(avg_range, 2),
        'avg_gap_pct': round(avg_gap_pct, 2),
        'momentum_4h': round(momentum, 2),
        'direction': 'BULL' if momentum + regime_bias > 0 else 'BEAR',
    }


# ═══════════════════════════════════════════════════════
#FORMAT — TACTICAL BRIEFING
# ═══════════════════════════════════════════════════════

def format_tactical(ticker, price, signals, after_hours, regime, now_et, level_info=None):
    """Format tactical briefing output with backtested signal grades + level memory."""
    lines = []
    lines.append(f"**{ticker}** ${price:.2f} | Regime: {regime}")
    lines.append("━━━━━━━━━━━━━━━━━")
    
    # Key levels line (if available)
    if level_info:
        res = level_info.get('nearest_resistance')
        sup = level_info.get('nearest_support')
        level_parts = []
        if res:
            dist = (res['price'] - price) / price * 100
            level_parts.append(f"🟥 ${res['price']} ({dist:+.1f}%)")
        if sup:
            dist = (sup['price'] - price) / price * 100
            level_parts.append(f"🟩 ${sup['price']} ({dist:+.1f}%)")
        if level_parts:
            lines.append("Levels: " + " | ".join(level_parts))
    
    # 30m signal
    if '30m' in signals:
        s = signals['30m']
        grade, emoji, notes, wr = signal_grade(s['type'], s['action'], s.get('rsi'), regime, s.get('confidence', 0.5))
        action_emoji = "🟢" if s['action'] == 'BUY' else ("🔴" if s['action'] == 'SELL' else "⚪")
        lines.append(f"⚡ **30m** [{grade}]: {s['type']} {s['pct']:.0f}% — {emoji} {action_emoji} {s['action']} ({wr:.0%})")
        lines.append(f"   Target ${s['target']} | Stop ${s['stop']} | RSI {s['rsi']}")
        # Add level-confirmed target/stop if available
        if level_info:
            level_notes = level_confirm(s, level_info, price)
            if level_notes:
                lines.append(f"   📍 {level_notes}")
        if notes: lines.append(f"   _{notes}_")
    else:
        lines.append(f"⚡ **30m**: No pattern")
    
    # 1h signal
    if '1h' in signals:
        s = signals['1h']
        grade, emoji, notes, wr = signal_grade(s['type'], s['action'], s.get('rsi'), regime, s.get('confidence', 0.5))
        action_emoji = "🟢" if s['action'] == 'BUY' else ("🔴" if s['action'] == 'SELL' else "⚪")
        trend = s.get('trend', '')
        lines.append(f"🕐 **1h** [{grade}]: {s['type']} {s['pct']:.0f}% {trend} — {emoji} {action_emoji} {s['action']} ({wr:.0%})")
        lines.append(f"   Target ${s['target']} | Stop ${s['stop']} | RSI {s['rsi']}")
        if level_info:
            level_notes = level_confirm(s, level_info, price)
            if level_notes:
                lines.append(f"   📍 {level_notes}")
        if notes: lines.append(f"   _{notes}_")
    else:
        lines.append(f"🕐 **1h**: No pattern")
    
    # 1h double
    if '1h_double' in signals:
        d = signals['1h_double']
        lines.append(f"   🔔 {d['type'].replace('_', ' ').title()} @ ${d['level']} ({d['amplitude']:.1f}%)")
    
    # 2 UP 1 DOWN (short-term trading pattern)
    if '2u1d' in signals:
        p = signals['2u1d']
        if p['type'].startswith('2U1D'):
            action_emoji = "🟢"
            lines.append(f"📈 **2U1D** [{p['action']}] — {p['bars']} → BUY pullback")
            if 'pullback_ratio' in p:
                lines.append(f"   Entry ${p.get('entry', '?')} | Target ${p['target']} | Stop ${p['stop']} | Pullback {p['pullback_ratio']:.0%} of move")
            elif 'bounce_pct' in p:
                lines.append(f"   Entry ${p.get('entry', '?')} | Target ${p['target']} | Stop ${p['stop']} | Bounce {p['bounce_pct']:.1f}% recovering pullback")
        elif p['type'].startswith('2D1U'):
            action_emoji = "🔴"
            lines.append(f"📉 **2D1U** [{p['action']}] — {p['bars']} → SELL bounce")
            if 'bounce_ratio' in p:
                lines.append(f"   Entry ${p.get('entry', '?')} | Target ${p['target']} | Stop ${p['stop']} | Bounce {p['bounce_ratio']:.0%} of drop")
            elif 'continuation_pct' in p:
                lines.append(f"   Entry ${p.get('entry', '?')} | Target ${p['target']} | Stop ${p['stop']} | Selling continues {p['continuation_pct']:.1f}%")
        # Extended pattern (stronger signal)
        if '2u1d_extended' in signals:
            pe = signals['2u1d_extended']
            if pe['type'].endswith('SIG'):
                lines.append(f"   ⚡ **Extended** {pe['type'][:4]} confirmed — {pe['bars']}")
    # 2h signal
    if '2h' in signals:
        s = signals['2h']
        grade, emoji, notes, wr = signal_grade(s['type'], s['action'], s.get('rsi'), regime, s.get('confidence', 0.5))
        action_emoji = "🟢" if s['action'] == 'BUY' else ("🔴" if s['action'] == 'SELL' else "⚪")
        trend = s.get('trend', '')
        lines.append(f"📊 **2h** [{grade}]: {s['type']} {s['pct']:.0f}% {trend} — {emoji} {action_emoji} {s['action']} ({wr:.0%})")
        lines.append(f"   Target ${s['target']} | Stop ${s['stop']} | {s['comp_prob']:.0%} completes")
        if level_info:
            level_notes = level_confirm(s, level_info, price)
            if level_notes:
                lines.append(f"   📍 {level_notes}")
        if notes: lines.append(f"   _{notes}_")
    else:
        lines.append(f"📊 **2h**: No pattern")
    
    # Move detectors (down + up, v5)
    move_signals = []
    
    # Spike-and-reverse (SELL)
    if 'spike' in signals:
        sp = signals['spike']
        move_signals.append(f"⚡️ **SPIKE & REVERSE** Peak ${sp['peak']} → Now ${price:.2f} (−{sp['reverse_pct']:.1f}%)")
        move_signals.append(f"   🔴 SELL — {sp['spike_pct']:.1f}% spike reversed, {sp['bars_since_peak']} bars from peak")
    
    # Dip-and-reverse (BUY)
    if 'dip' in signals:
        dp = signals['dip']
        move_signals.append(f"⤴️ **DIP & REVERSE** Low ${dp['dip']} → Now ${price:.2f} (+{dp['bounce_pct']:.1f}%)")
        move_signals.append(f"   🟢 BUY — {dp['dip_pct']:.1f}% dip bounced, {dp['bars_since_dip']} bars from low")
    
    # Momentum acceleration (SELL or BUY)
    if 'momentum' in signals:
        mo = signals['momentum']
        accel_note = " ⚡ ACCELERATING" if mo['accelerating'] else ""
        if mo['action'] == 'SELL':
            move_signals.append(f"🔴 **MOMENTUM SELL** — {mo['consecutive_red']} red 1h bars ({mo['total_drop_pct']:.1f}% drop){accel_note}")
        else:
            move_signals.append(f"🟢 **MOMENTUM BUY** — {mo['consecutive_green']} green 1h bars ({mo['total_gain_pct']:.1f}% gain){accel_note}")
    
    # Macro override (M→SELL or W→BUY)
    if 'macro' in signals:
        ma = signals['macro']
        if ma['type'] == 'MACRO_M_OVERRIDE':
            move_signals.append(f"⚠️ **MACRO M OVERRIDE** — M ${ma['ceiling']}→${ma['floor']} ({ma['pct']:.0f}% through, {ma['amplitude']:.1f}% amp)")
            move_signals.append(f"   🔴 SELL bias — macro M overrides any micro W pattern")
        else:  # MACRO_W_OVERRIDE
            move_signals.append(f"✅ **MACRO W OVERRIDE** — W ${ma['floor']}→${ma['ceiling']} ({ma['pct']:.0f}% through, {ma['amplitude']:.1f}% amp)")
            move_signals.append(f"   🟢 BUY bias — macro W overrides any micro M pattern")
    
    # If 2h has macro override note, add it
    if '2h' in signals and signals['2h'].get('_macro_override'):
        lines.append(f"   _{signals['2h']['_macro_note']}_")
    
    if move_signals:
        lines.append("━━━━━━━━━━━━━━━━━")
        lines.append("⚡ **MOVE ALERTS:**")
        lines.extend(move_signals)
    
    # Trendline projections (from level memory)
    if level_info and level_info.get('projections'):
        lines.append("━━━━━━━━━━━━━━━━━")
        lines.append("📐 **Trendlines (legs projections):**")
        for proj in level_info['projections'][:4]:
            arrow = "↑" if proj.get('direction') == 'rising' else ("↓" if proj.get('direction') == 'falling' else "→")
            if proj['type'] == 'M_ceil':
                lines.append(f"   M-ceil {arrow} ${proj.get('projected', '?')} (from ${proj.get('ceiling', '?')})")
            else:
                lines.append(f"   W-floor {arrow} ${proj.get('projected', '?')} (from ${proj.get('floor', '?')})")
    
    # After-hours (only if near EOD)
    hour_et = now_et.hour
    if after_hours and hour_et >= 12:  # After noon ET
        ah = after_hours
        lines.append("━━━━━━━━━━━━━━━━━")
        lines.append(f"🌙 **EOD Move**: {ah['direction']}")
        lines.append(f"   ↑ ${ah['expected_up']} | ↓ ${ah['expected_down']}")
        lines.append(f"   ATR ${ah['atr']} | Range ${ah['avg_daily_range']} | Mom {ah['momentum_4h']:+.2f}%")
    
    return "\n".join(lines)


def level_confirm(signal, level_info, price):
    """Check if signal target/stop aligns with learned key levels.
    Returns a string note like 'Target near 🟥$94.61 (10 hits)' or ''."""
    if not level_info:
        return ""
    
    notes = []
    target = signal.get('target', 0)
    stop = signal.get('stop', 0)
    action = signal.get('action', '')
    
    tolerance_pct = 2.0  # within 2% of a level = "near"
    
    # Check if target aligns with resistance (for BUY) or support (for SELL)
    for zone in level_info.get('resistance_zones', []):
        zprice = zone['price']
        if abs(target - zprice) / zprice * 100 < tolerance_pct:
            notes.append(f"Target ≈ 🟥${zprice} ({zone['hits']}x)")
            break
    
    for zone in level_info.get('support_zones', []):
        zprice = zone['price']
        if abs(stop - zprice) / zprice * 100 < tolerance_pct:
            notes.append(f"Stop ≈ 🟩${zprice} ({zone['hits']}x)")
            break
    
    return " | ".join(notes)


# ═══════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════

def run_scan(ticker, send_alerts=True):
    if ticker not in TICKERS: 
        print(f"Unknown ticker: {ticker}")
        return None

    sym = TICKERS[ticker]["symbol"]
    now_et = datetime.now(ET)

    # Fetch all timeframes
    data = fetch_multi(sym)
    
    # Current price
    if '1d' not in data or len(data['1d']['close']) < 5:
        print(f"No data for {ticker}")
        return None
    
    closes_1d = data['1d']['close']
    price = float(closes_1d[-1])
    
    # Regime from 1M or 1D
    regime = detect_regime(closes_1d)
    if '1m' in data:
        regime_1m = detect_regime(data['1m']['close'])
        # 1M regime overrides if strong
        if regime != regime_1m and regime_1m != "SIDEWAYS":
            regime = regime_1m
    
    # ATR for context
    atr_price = compute_atr(data['1d']['high'], data['1d']['low'], closes_1d)
    
    # Generate signals
    signals = tactical_signal(
        data.get('15m'), data.get('1h'), data.get('1d'),
        price, regime, atr_price
    )
    
    # After-hours move (always compute, only show near EOD)
    after_hours = after_hours_move(data.get('1d'), data.get('1h'), price, regime, atr_price)
    
    # Load level memory (key S/R zones + trendline projections)
    level_info = None
    level_file = STORAGE / f"levels_{ticker.lower()}.json"
    if level_file.exists():
        try:
            import json as _json
            ldata = _json.loads(level_file.read_text())
            # Only use if recent (within 2 hours)
            ltime = ldata.get('timestamp', '')
            from datetime import timezone as _tz
            try:
                lt = datetime.fromisoformat(ltime)
                if (datetime.now(_tz.utc) - lt).total_seconds() < 7200:
                    level_info = ldata
            except:
                level_info = ldata  # use even if timestamp parse fails
        except:
            pass
    
    # Format
    output = format_tactical(ticker, price, signals, after_hours, regime, now_et, level_info)
    print(output)
    
    # Save
    try:
        (STORAGE / f"last_wm_tactical_{ticker.lower()}.json").write_text(json.dumps({
            'ticker': ticker, 'price': price, 'regime': regime,
            'signals': {k: {kk: str(vv) for kk, vv in v.items()} for k, v in signals.items()},
            'after_hours': after_hours,
            'time': now_et.isoformat()
        }, indent=2, default=str))
    except: pass
    
    # Alert logic — now includes down-move detectors
    if send_alerts:
        should_alert = False
        for tf, sig in signals.items():
            if sig.get('confidence', 0) >= 0.8 and sig.get('action') in ('BUY', 'SELL'):
                should_alert = True
            if tf == '1h_double':
                should_alert = True
        # Move detectors always alert (down + up)
            if tf in ('spike', 'dip', 'momentum', 'macro', '2u1d', '2u1d_extended'):
                should_alert = True
        if should_alert:
            try:
                from telegram_bot import send_message
                send_message(output)
            except: pass

    return signals, after_hours


if __name__ == "__main__":
    t = sys.argv[1] if len(sys.argv) > 1 else "WTI"
    send = "--no-send" not in sys.argv
    result = run_scan(t, send_alerts=send)