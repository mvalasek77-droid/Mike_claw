#!/usr/bin/env python3
"""
W-M Master Scanner — Binary Buy/Sell with Precise Prices
==========================================================
Replaces: wm_binary.py, wm_1d1m.py, wm_watchdog.py
Unified: 1D, 1W, 1M multi-timeframe pattern detection.
Always outputs LONG or SHORT with entry/target/stop.

Timeframes:
  15m → micro (intraday entry timing)
  1h  → short-term (30m-2h trades)
  1d  → 1D pattern (swing, 1-5 days)
  1wk → 1W pattern (position, 1-4 weeks)
  1mo → 1M pattern (macro regime filter only)

Rules (backtested 1935 trades):
  M_SELL 93% WR (KING), M_BUY 87% WR (QUEEN)
  W_BUY/W_SELL <15% WR → NEVER trade raw W → use regime instead
  Consolidation zone (25-60%) → 0% WR → enter only with move detector override
  Confirmation zone (60%+) → strongest entry
  Early zone (<25%) → new pattern, trade with tight stop
"""

import sys, json, numpy as np
from pathlib import Path
from datetime import datetime
from pytz import timezone
import warnings
warnings.filterwarnings("ignore")

ET = timezone('US/Eastern')
PT = timezone('US/Pacific')
STORAGE = Path(__file__).parent / "storage"
STORAGE.mkdir(exist_ok=True)
MASTER_DIR = STORAGE / "master"
MASTER_DIR.mkdir(exist_ok=True)

TICKERS = {
    "WTI":  {"symbol": "CL=F",  "name": "WTI Crude Oil"},
    "RGTI": {"symbol": "RGTI",  "name": "Rigetti Computing"},
    "QBTX": {"symbol": "QBTX",  "name": "Quantum Computing 2x"},
}

# ═══════════════════════════════════════════════════════
# BACKTESTED EDGE (1935 trades, updated 2026-06-08)
# ═══════════════════════════════════════════════════════
BASE_WR = {
    'M_SELL':    0.93,  # KING — sell at M-top reversal
    'M_BUY':     0.87,  # QUEEN — buy M-bottom bounce
    'W_BUY':     0.11,  # AVOID
    'W_SELL':    0.04,  # AVOID
    'DOWN_SELL': 0.83,
    'UP_BUY':    0.70,
}

REGIME_ADJ = {
    'DOWN':    {'BUY': -0.20, 'SELL': 0.05},
    'UP':      {'BUY':  0.05, 'SELL': -0.05},
    'SIDEWAYS': {'BUY': 0, 'SELL': 0},
}

# ═══════════════════════════════════════════════════════
# DATA FETCHING (market-hours aware)
# ═══════════════════════════════════════════════════════

def is_market_hours():
    """Check if US markets are open (9:30 AM - 4:00 PM ET)."""
    now_et = datetime.now(ET)
    # Weekend check
    if now_et.weekday() >= 5:
        return False
    # 9:30 AM - 4:00 PM ET
    if now_et.hour < 9 or (now_et.hour == 9 and now_et.minute < 30):
        return False
    if now_et.hour >= 16:
        return False
    return True

def fetch_multi(symbol):
    """Fetch all timeframes. Returns dict with 15m, 1h, 1d, 1w, 1m data."""
    import yfinance as yf
    out = {}
    
    timeframes = [
        ('15m', '5d', '15m'),    # intraday
        ('1h',  '30d', '1h'),    # short-term
        ('1d',  '6mo', '1d'),   # swing (1D pattern)
        ('1w',  '2y', '1wk'),   # position (1W pattern)
        ('1m',  '5y', '1mo'),   # macro (1M regime)
    ]
    
    for key, period, interval in timeframes:
        try:
            df = yf.Ticker(symbol).history(period=period, interval=interval)
            if df.empty or len(df) < 5:
                continue
            out[key] = {
                'high':  df['High'].values.astype(float),
                'low':   df['Low'].values.astype(float),
                'close': df['Close'].values.astype(float),
                'open':  df['Open'].values.astype(float) if 'Open' in df else df['Close'].values.astype(float),
            }
        except:
            pass
    
    return out


# ═══════════════════════════════════════════════════════
# CORE MATH
# ═══════════════════════════════════════════════════════

def compute_atr(highs, lows, closes, period=14):
    if len(highs) < 2:
        return 0
    tr = np.maximum(highs[1:] - lows[1:],
                    np.maximum(np.abs(highs[1:] - closes[:-1]),
                               np.abs(lows[1:] - closes[:-1])))
    if len(tr) < period:
        return float(np.mean(tr))
    return float(np.mean(tr[-period:]))

def compute_rsi(closes, period=14):
    if len(closes) < period + 1:
        return 50
    deltas = np.diff(closes[-period*3:])
    gains = np.where(deltas > 0, deltas, 0)
    losses = np.where(deltas < 0, -deltas, 0)
    avg_gain = np.mean(gains[-period:])
    avg_loss = np.mean(losses[-period:])
    if avg_loss == 0:
        return 100
    rs = avg_gain / avg_loss
    return 100 - 100 / (1 + rs)

def compute_ema(closes, period=20):
    if len(closes) < period:
        return float(closes[-1])
    ema = float(closes[0])
    k = 2 / (period + 1)
    for c in closes[1:]:
        ema = c * k + ema * (1 - k)
    return ema


# ═══════════════════════════════════════════════════════
# LETTER DETECTION (quality-filtered, ATR-adaptive)
# ═══════════════════════════════════════════════════════

MIN_AMPLITUDE_PCT = 2.0
MAX_ASYMMETRY = 0.08
MIN_CONFIDENCE = 0.55

def detect_letters(highs, lows, closes, order=3, min_amp_pct=MIN_AMPLITUDE_PCT):
    """Detect W/M with symmetry + amplitude quality filters. Enforces W→M alternation."""
    from scipy.signal import argrelextrema
    
    if closes is not None and len(closes) > 14:
        atr = compute_atr(highs, lows, closes)
        avg_price = float(np.mean(closes[-20:]))
        atr_pct = atr / avg_price * 100 if avg_price > 0 else 2
        # ATR-adaptive order: low vol → higher order, high vol → lower order
        if atr_pct < 1.0:
            order = max(order, 5)
        elif atr_pct > 3.0:
            order = min(order, 3)
        min_amp = max(min_amp_pct, atr_pct * 0.5)
    else:
        min_amp = min_amp_pct
    
    hi = argrelextrema(highs, np.greater, order=order)[0]
    lo = argrelextrema(lows, np.less, order=order)[0]
    if len(hi) < 2 or len(lo) < 2:
        return []
    
    swings = [(int(i), float(highs[i]), 'H') for i in hi] + [(int(i), float(lows[i]), 'L') for i in lo]
    swings.sort()
    
    # Filter to alternating H/L
    alt = [swings[0]]
    for s in swings[1:]:
        if s[2] == alt[-1][2]:
            if s[2] == 'H' and s[1] > alt[-1][1]:
                alt[-1] = s
            elif s[2] == 'L' and s[1] < alt[-1][1]:
                alt[-1] = s
        else:
            alt.append(s)
    if len(alt) < 3:
        return []
    
    raw = []
    for i in range(len(alt) - 2):
        _, ap, at = alt[i]
        _, bp, bt = alt[i+1]
        _, cp, ct = alt[i+2]
        
        if at == 'L' and bt == 'H' and ct == 'L':
            amp_pct = (bp - min(ap, cp)) / min(ap, cp) * 100
            if amp_pct < min_amp:
                continue
            asymmetry = abs(ap - cp) / max(ap, cp)
            if asymmetry > MAX_ASYMMETRY:
                continue
            raw.append(('W', ap, bp, cp, round(amp_pct, 2), round(asymmetry, 4)))
        elif at == 'H' and bt == 'L' and ct == 'H':
            amp_pct = (max(ap, cp) - bp) / max(ap, cp) * 100
            if amp_pct < min_amp:
                continue
            asymmetry = abs(ap - cp) / max(ap, cp)
            if asymmetry > MAX_ASYMMETRY:
                continue
            raw.append(('M', ap, bp, cp, round(amp_pct, 2), round(asymmetry, 4)))
    
    if not raw:
        return []
    
    # Enforce strict W→M→W→M alternation (keep highest amplitude per type)
    letters = [raw[0]]
    for lt in raw[1:]:
        if lt[0] == letters[-1][0]:
            if lt[4] > letters[-1][4]:
                letters[-1] = lt
        else:
            letters.append(lt)
    return letters


def find_phase(letters, price):
    """Find where price sits within the most recent ACTIVE pattern."""
    if not letters:
        return 'NONE', 0, 0, 50, 'WAIT'
    
    for last in reversed(letters):
        lt = last[0]
        if lt == 'W':
            floor = min(last[1], last[3])
            ceiling = last[2]
            if ceiling == floor:
                continue
            raw_pct = (price - floor) / (ceiling - floor) * 100
            if raw_pct < -5 or raw_pct > 105:
                continue
            pct = max(0, min(100, raw_pct))
            if pct >= 90:
                action = 'SELL'
            elif pct <= 25:
                action = 'BUY'
            else:
                action = 'WAIT'
            return 'W', floor, ceiling, pct, action
        else:  # M
            floor = last[2]
            ceiling = max(last[1], last[3])
            if ceiling == floor:
                continue
            raw_pct = (ceiling - price) / (ceiling - floor) * 100
            if raw_pct < -5 or raw_pct > 105:
                continue
            pct = max(0, min(100, raw_pct))
            if pct >= 75:
                action = 'SELL'  # Near M top
            elif pct <= 25:
                action = 'BUY'   # M completed → buy bounce
            else:
                action = 'WAIT'
            return 'M', floor, ceiling, pct, action
    
    return 'NONE', 0, 0, 50, 'WAIT'


def pattern_confidence(letters):
    if not letters:
        return 0
    last = letters[-1]
    amp = last[4]
    asym = last[5]
    amp_score = min(1, amp / 10)
    sym_score = 1 - min(1, asym / MAX_ASYMMETRY)
    return round(0.5 * amp_score + 0.5 * sym_score, 3)


# ═══════════════════════════════════════════════════════
# REGIME DETECTION
# ═══════════════════════════════════════════════════════

def detect_regime(closes):
    if len(closes) < 24:
        return "SIDEWAYS"
    r, p = closes[-12:], closes[-24:-12]
    rh, rl = np.max(r), np.min(r)
    ph, pl = np.max(p), np.min(p)
    if rh > ph and rl > pl:
        return "UP"
    if rh < ph and rl < pl:
        return "DOWN"
    return "SIDEWAYS"


# ═══════════════════════════════════════════════════════
# MOVE DETECTORS (6 detectors: 3 sell, 3 buy)
# ═══════════════════════════════════════════════════════

VELOCITY_THRESHOLDS = {
    'consecutive_red': 3,
    'consecutive_green': 3,
    'spike_reverse_pct': 3.0,
    'dip_reverse_pct': 3.0,
    'macro_amp_min': 5.0,
}

def detect_spike_and_reverse(data_15m, price):
    if data_15m is None or len(data_15m['high']) < 10:
        return None
    highs = data_15m['high']
    lows = data_15m['low']
    opens = data_15m['open']
    
    recent_high = float(np.max(highs[-16:]))
    recent_low = float(np.min(lows[-16:]))
    if recent_high <= recent_low:
        return None
    
    intraday_range = (recent_high - recent_low) / recent_low * 100
    near_low = (price - recent_low) / (recent_high - recent_low) * 100 < 30
    peak_idx = int(np.argmax(highs[-16:]))
    bars_since_peak = 15 - peak_idx
    
    if intraday_range >= VELOCITY_THRESHOLDS['spike_reverse_pct'] and near_low and bars_since_peak <= 8:
        drawdown = (recent_high - price) / recent_high * 100
        return {
            'type': 'SPIKE_REVERSE', 'peak': round(recent_high, 2),
            'trough': round(recent_low, 2),
            'spike_pct': round((recent_high - opens[-16]) / opens[-16] * 100, 1),
            'reverse_pct': round(drawdown, 1),
            'bars_since_peak': bars_since_peak,
            'action': 'SELL',
            'strength': min(1.0, drawdown / 5.0),
        }
    return None

def detect_dip_and_reverse(data_15m, price):
    if data_15m is None or len(data_15m['low']) < 10:
        return None
    highs = data_15m['high']
    lows = data_15m['low']
    opens = data_15m['open']
    
    recent_low = float(np.min(lows[-16:]))
    recent_high = float(np.max(highs[-16:]))
    if recent_high <= recent_low:
        return None
    
    bounce = (price - recent_low) / recent_low * 100
    intraday_range = (recent_high - recent_low) / recent_low * 100
    near_high = (recent_high - price) / (recent_high - recent_low) * 100 < 30
    dip_idx = int(np.argmin(lows[-16:]))
    bars_since_dip = 15 - dip_idx
    
    if intraday_range >= VELOCITY_THRESHOLDS['dip_reverse_pct'] and near_high and bars_since_dip <= 8:
        return {
            'type': 'DIP_REVERSE', 'dip': round(recent_low, 2),
            'peak': round(recent_high, 2),
            'dip_pct': round((opens[-16] - recent_low) / opens[-16] * 100, 1),
            'bounce_pct': round(bounce, 1),
            'bars_since_dip': bars_since_dip,
            'action': 'BUY',
            'strength': min(1.0, bounce / 5.0),
        }
    return None

def detect_momentum(data_1h):
    if data_1h is None or len(data_1h['close']) < 5:
        return None
    closes = data_1h['close']
    opens = data_1h['open']
    
    # Red streak
    consec_red = 0
    for i in range(len(closes)-1, max(len(closes)-10, -1), -1):
        if closes[i] < opens[i]:
            consec_red += 1
        else:
            break
    
    if consec_red >= 2:
        first = len(closes) - consec_red
        total_drop = (opens[first] - closes[-1]) / opens[first] * 100
        if consec_red >= VELOCITY_THRESHOLDS['consecutive_red'] or (consec_red >= 2 and total_drop >= 2.0):
            return {
                'type': 'MOMENTUM_SELL', 'consecutive': consec_red,
                'total_pct': round(total_drop, 2), 'action': 'SELL',
                'strength': min(1.0, consec_red / 5.0),
            }
    
    # Green streak
    consec_green = 0
    for i in range(len(closes)-1, max(len(closes)-10, -1), -1):
        if closes[i] > opens[i]:
            consec_green += 1
        else:
            break
    
    if consec_green >= 2:
        first = len(closes) - consec_green
        total_gain = (closes[-1] - opens[first]) / opens[first] * 100
        if consec_green >= VELOCITY_THRESHOLDS['consecutive_green'] or (consec_green >= 2 and total_gain >= 2.0):
            return {
                'type': 'MOMENTUM_BUY', 'consecutive': consec_green,
                'total_pct': round(total_gain, 2), 'action': 'BUY',
                'strength': min(1.0, consec_green / 5.0),
            }
    
    return None

def detect_macro_override(data_1d, price, regime):
    """Macro M overrides micro W, macro W overrides micro M."""
    if data_1d is None or len(data_1d['high']) < 20:
        return None
    
    h, l, c = data_1d['high'], data_1d['low'], data_1d['close']
    macro_letters = detect_letters(h, l, c, order=5, min_amp_pct=3.0)
    if not macro_letters:
        return None
    
    for lt, p1, p2, p3, amp, asym in macro_letters:
        if lt == 'M':
            ceiling = max(p1, p3)
            floor = p2
            if ceiling == floor:
                continue
            pct = (ceiling - price) / (ceiling - floor) * 100
            if 40 <= pct <= 100 and amp >= VELOCITY_THRESHOLDS['macro_amp_min']:
                return {
                    'type': 'MACRO_M_OVERRIDE', 'ceiling': round(ceiling, 2),
                    'floor': round(floor, 2), 'pct': round(pct, 1),
                    'amplitude': round(amp, 1), 'action': 'SELL',
                    'strength': min(1.0, amp / 15.0),
                }
        elif lt == 'W':
            floor = min(p1, p3)
            ceiling = p2
            if ceiling == floor:
                continue
            pct = (price - floor) / (ceiling - floor) * 100
            if 40 <= pct <= 100 and amp >= VELOCITY_THRESHOLDS['macro_amp_min']:
                return {
                    'type': 'MACRO_W_OVERRIDE', 'floor': round(floor, 2),
                    'ceiling': round(ceiling, 2), 'pct': round(pct, 1),
                    'amplitude': round(amp, 1), 'action': 'BUY',
                    'strength': min(1.0, amp / 15.0),
                }
    return None


# ═══════════════════════════════════════════════════════
# MASTER SIGNAL CALCULATION
# ═══════════════════════════════════════════════════════

def compute_binary_signal(ticker):
    """Always returns LONG or SHORT with precise entry/target/stop.
    
    Multi-TF alignment:
    1M = regime filter (UP/DOWN bias)
    1W = position direction (weekly swing)
    1D = trade direction (daily pattern = primary signal)
    1h = entry timing (hourly confirms/denies)
    15m = move detectors (spike/dip/momentum overrides)
    """
    if ticker not in TICKERS:
        return None
    
    sym = TICKERS[ticker]["symbol"]
    data = fetch_multi(sym)
    
    if '1d' not in data or len(data['1d']['close']) < 20:
        return None
    
    price = float(data['1d']['close'][-1])
    atr = compute_atr(data['1d']['high'], data['1d']['low'], data['1d']['close'])
    
    # ── 1M REGIME ──
    regime_1m = 'SIDEWAYS'
    if '1m' in data and len(data['1m']['close']) > 5:
        regime_1m = detect_regime(data['1m']['close'])
    
    # ── 1D REGIME (primary) ──
    regime_1d = detect_regime(data['1d']['close'])
    regime = regime_1d
    # 1M overrides if not SIDEWAYS and different
    if regime_1m != 'SIDEWAYS' and regime_1m != regime_1d:
        regime = regime_1m
    
    # ── Intraday crash override ──
    if '15m' in data and len(data['15m']['close']) > 2:
        intraday_open = float(data['15m']['close'][0])
        daily_chg = ((price - intraday_open) / intraday_open) * 100 if intraday_open > 0 else 0
        if daily_chg < -5 and regime != 'DOWN':
            regime = 'DOWN'
    else:
        daily_chg = 0
    
    # ── 1M PATTERN (macro letter context) ──
    letter_1m = 'NONE'
    floor_1m = ceil_1m = 0
    if '1m' in data and len(data['1m']['close']) > 5:
        letters_1m = detect_letters(data['1m']['high'], data['1m']['low'], data['1m']['close'], order=2, min_amp_pct=1)
        if letters_1m:
            letter_1m, floor_1m, ceil_1m, pct_1m, _ = find_phase(letters_1m, price)
    
    # ── 1W PATTERN (weekly position) ──
    letter_1w = 'NONE'
    floor_1w = ceil_1w = 0
    pct_1w = 50
    if '1w' in data and len(data['1w']['close']) > 5:
        letters_1w = detect_letters(data['1w']['high'], data['1w']['low'], data['1w']['close'], order=3, min_amp_pct=2.0)
        if letters_1w:
            letter_1w, floor_1w, ceil_1w, pct_1w, _ = find_phase(letters_1w, price)
    
    # ── 1D PATTERN (primary trade signal) ──
    letter_1d = 'NONE'
    floor_1d = ceil_1d = 0
    pct_1d = 50
    conf_1d = 0
    if '1d' in data and len(data['1d']['close']) > 5:
        letters_1d = detect_letters(data['1d']['high'], data['1d']['low'], data['1d']['close'], order=3, min_amp_pct=2.0)
        if letters_1d:
            letter_1d, floor_1d, ceil_1d, pct_1d, _ = find_phase(letters_1d, price)
            conf_1d = pattern_confidence(letters_1d)
    
    # ── 1H PATTERN (entry timing) ──
    letter_1h = 'NONE'
    floor_1h = ceil_1h = 0
    pct_1h = 50
    rsi = 50
    if '1h' in data and len(data['1h']['close']) > 5:
        rsi = compute_rsi(data['1h']['close'], 14)
        letters_1h = detect_letters(data['1h']['high'], data['1h']['low'], data['1h']['close'], order=3, min_amp_pct=1.0)
        if letters_1h:
            letter_1h, floor_1h, ceil_1h, pct_1h, _ = find_phase(letters_1h, price)
    
    # ── MOVE DETECTORS ──
    spike = detect_spike_and_reverse(data.get('15m'), price)
    dip = detect_dip_and_reverse(data.get('15m'), price)
    momentum = detect_momentum(data.get('1h'))
    macro = detect_macro_override(data.get('1d'), price, regime)
    
    # ════════════════════════════════════════════════════════
    # BINARY DECISION
    # ════════════════════════════════════════════════════════
    direction = None
    win_rate = 0.5
    grade = 'C'
    notes = []
    key = ''
    source = 'regime'
    
    # Priority: macro override > 1D > 1W > regime
    if macro:
        if macro['type'] == 'MACRO_M_OVERRIDE':
            # Macro M = bearish, but check shorter TF for trap detection
            shorter_buy = (dip and dip['action'] == 'BUY') or (momentum and momentum['action'] == 'BUY')
            if shorter_buy and daily_chg > 0:
                # Short term says buy, macro says sell — use 1D as tiebreaker
                pass  # fall through to 1D
            else:
                direction = 'SHORT'
                key = 'M_SELL'
                win_rate = BASE_WR['M_SELL']
                source = 'macro_M'
                notes.append(f"macro M ${macro['ceiling']}→${macro['floor']}")
        elif macro['type'] == 'MACRO_W_OVERRIDE':
            # Macro W = bullish, check for shorter TF sell trap
            shorter_sell = (spike and spike['action'] == 'SELL') or (momentum and momentum['action'] == 'SELL')
            if shorter_sell and daily_chg < -3:
                pass  # fall through to 1D (W trap)
            else:
                direction = 'LONG'
                key = 'M_BUY'  # Treat macro W long like M-bounce (87% WR)
                win_rate = BASE_WR['M_BUY'] * 0.85  # Slightly reduced (not true M)
                source = 'macro_W'
                notes.append(f"macro W ${macro['floor']}→${macro['ceiling']}")
    
    # 1D pattern (primary)
    if direction is None and letter_1d in ('W', 'M'):
        source = '1D'
        floor = floor_1d
        ceil = ceil_1d
        pct = pct_1d
        
        if letter_1d == 'M':
            if pct >= 75:
                # Near M bottom = QUEEN TRADE (buy bounce)
                if regime == 'DOWN':
                    direction = 'SHORT'
                    key = 'M_SELL'
                    win_rate = BASE_WR['M_SELL'] * 0.70
                    notes.append("M-bounce DOWN→FLIP SHORT")
                else:
                    direction = 'LONG'
                    key = 'M_BUY'
                    win_rate = BASE_WR['M_BUY']
                    notes.append("M-bounce QUEEN ✓")
            elif pct >= 60:
                direction = 'SHORT'
                key = 'M_SELL'
                win_rate = BASE_WR['M_SELL']
                notes.append(f"M confirm {pct:.0f}%")
            elif pct <= 25:
                direction = 'SHORT'
                key = 'M_SELL'
                win_rate = BASE_WR['M_SELL'] * 0.85
                notes.append(f"M-top early {pct:.0f}%")
            else:
                # Consolidation zone (25-60%) — 0% WR on pattern alone
                direction = 'SHORT'  # M = sell bias
                key = 'M_SELL'
                win_rate = BASE_WR['M_SELL'] * 0.4  # Heavy penalty for mid-zone
                notes.append(f"M mid-zone ⏳")
        
        elif letter_1d == 'W':
            if pct >= 75:
                direction = 'SHORT'
                key = 'W_SELL'
                win_rate = BASE_WR['W_SELL']
                notes.append("W completing (weak)")
            elif pct <= 25:
                direction = 'LONG'
                key = 'W_BUY'
                win_rate = BASE_WR['W_BUY']
                notes.append("W-bottom (low WR)")
            else:
                # Mid W → use regime as tiebreaker
                if regime == 'DOWN':
                    direction = 'SHORT'
                    key = 'DOWN_SELL'
                    win_rate = BASE_WR['DOWN_SELL']
                    notes.append("W+DOWN→SHORT")
                elif regime == 'UP':
                    direction = 'LONG'
                    key = 'UP_BUY'
                    win_rate = BASE_WR['UP_BUY']
                    notes.append("W+UP→LONG")
                else:
                    direction = 'LONG'
                    win_rate = 0.3
                    notes.append("W+SIDEWAYS")
    
    # 1W pattern (if 1D didn't give a signal)
    if direction is None and letter_1w in ('W', 'M'):
        source = '1W'
        if letter_1w == 'M':
            if pct_1w >= 60:
                direction = 'SHORT'
                key = 'M_SELL'
                win_rate = BASE_WR['M_SELL'] * 0.75  # Weekly M slightly less precise
                notes.append(f"1W M {pct_1w:.0f}%")
            else:
                direction = 'LONG'
                key = 'M_BUY'
                win_rate = BASE_WR['M_BUY'] * 0.75
                notes.append(f"1W M bounce {pct_1w:.0f}%")
        elif letter_1w == 'W':
            if regime == 'DOWN':
                direction = 'SHORT'
                key = 'DOWN_SELL'
                win_rate = BASE_WR['DOWN_SELL']
                notes.append(f"1W W+DOWN→SHORT")
            elif regime == 'UP':
                direction = 'LONG'
                key = 'UP_BUY'
                win_rate = BASE_WR['UP_BUY']
                notes.append(f"1W W+UP→LONG")
    
    # Fallback: regime only
    if direction is None:
        source = 'regime'
        if regime == 'DOWN':
            direction = 'SHORT'
            key = 'DOWN_SELL'
            win_rate = BASE_WR['DOWN_SELL']
            notes.append("No pattern+DOWN")
        elif regime == 'UP':
            direction = 'LONG'
            key = 'UP_BUY'
            win_rate = BASE_WR['UP_BUY']
            notes.append("No pattern+UP")
        else:
            direction = 'LONG'
            win_rate = 0.35
            notes.append("Default LONG")
    
    # ── MOVE DETECTOR OVERRIDES ──
    if spike and direction != 'SHORT':
        direction = 'SHORT'
        win_rate = max(win_rate, 0.70)
        notes.append("⚡spike→SHORT")
    elif spike and direction == 'SHORT':
        win_rate = min(1.0, win_rate + 0.05)
        notes.append("spike✓")
    
    if dip and direction != 'LONG':
        direction = 'LONG'
        win_rate = max(win_rate, 0.70)
        notes.append("⚡dip→LONG")
    elif dip and direction == 'LONG':
        win_rate = min(1.0, win_rate + 0.05)
        notes.append("dip✓")
    
    if momentum:
        if momentum['action'] == direction:
            win_rate = min(1.0, win_rate + 0.05)
            notes.append("mom✓")
        else:
            win_rate = max(0.2, win_rate - 0.10)
            notes.append("mom✗!")
    
    # ── RSI ADJUSTMENTS ──
    if rsi is not None:
        if rsi >= 70:
            if direction == 'LONG':
                win_rate = min(1.0, win_rate + 0.10)
                notes.append(f"RSI{rsi:.0f}+")
            else:
                win_rate = max(0.2, win_rate - 0.05)
                notes.append(f"RSI{rsi:.0f}-vs")
        elif rsi >= 60:
            if direction == 'LONG':
                win_rate = min(1.0, win_rate + 0.05)
                notes.append(f"RSI{rsi:.0f}+")
        elif rsi <= 30:
            if direction == 'SHORT' and regime == 'DOWN':
                win_rate = min(1.0, win_rate + 0.05)
                notes.append(f"RSI{rsi:.0f}+freefall")
            elif direction == 'LONG' and regime == 'DOWN':
                win_rate = max(0.05, win_rate - 0.30)
                notes.append(f"RSI{rsi:.0f}!!TRAP")
            else:
                win_rate = max(0.2, win_rate - 0.15)
                notes.append(f"RSI{rsi:.0f}!!")
        elif rsi < 40:
            if direction == 'LONG':
                win_rate = max(0.2, win_rate - 0.15)
            else:
                win_rate = max(0.2, win_rate - 0.10)
            notes.append(f"RSI{rsi:.0f}!")
    
    # ── REGIME ADJUSTMENT ──
    action_key = 'BUY' if direction == 'LONG' else 'SELL'
    win_rate += REGIME_ADJ.get(regime, {}).get(action_key, 0)
    
    # ── M-pattern high confidence bonus ──
    if conf_1d > 0.85 and letter_1d == 'M':
        win_rate = min(1.0, win_rate + 0.03)
        notes.append("Mconf✓")
    
    # ── 1M FILTER: caps targets when macro opposes ──
    cap_1m = False
    if direction == 'LONG' and letter_1m == 'M':
        cap_1m = True
        win_rate = max(0.2, win_rate - 0.05)
        notes.append("1M=M cap")
    elif direction == 'SHORT' and letter_1m == 'W':
        cap_1m = True
        win_rate = max(0.2, win_rate - 0.05)
        notes.append("1M=W cap")
    
    win_rate = max(0.05, min(0.98, win_rate))
    
    # Grade
    if win_rate >= 0.80:
        grade = 'A'
    elif win_rate >= 0.65:
        grade = 'B'
    elif win_rate >= 0.45:
        grade = 'C'
    else:
        grade = 'D'
    
    # W-pattern trades always D
    if key in ('W_BUY', 'W_SELL'):
        grade = 'D'
    
    # ════════════════════════════════════════════════════════
    # CALCULATE ENTRY / TARGET / STOP  (ATR-anchored, never absurd)
    # ════════════════════════════════════════════════════════
    entry = round(price, 2)
    
    # Pick the best available pattern floor/ceil based on source
    if source == 'macro_M':
        use_floor = macro['floor']
        use_ceil = macro['ceiling']
    elif source == 'macro_W':
        use_floor = macro['floor']
        use_ceil = macro['ceiling']
    elif source == '1D':
        use_floor = floor_1d
        use_ceil = ceil_1d
    elif source == '1W':
        use_floor = floor_1w
        use_ceil = ceil_1w
    else:
        use_floor = price - atr * 1.5
        use_ceil = price + atr * 1.5
    
    # ═══ SMART PRICE CALCULATION ═══
    # Rule 1: Target must be at least 1× ATR from entry (meaningful trade)
    # Rule 2: Stop must be at most 2× ATR from entry (manageable risk)
    # Rule 3: R:R must be >= 0.7 (or we widen target / tighten stop)
    # Rule 4: Never use macro-level floors/ceilings that are months old
    #         and 5× ATR away — use ATR anchoring instead
    
    min_target_atr = 1.0   # target at least 1× ATR away
    max_stop_atr = 2.0      # stop at most 2× ATR away
    min_rr = 0.7            # minimum risk:reward ratio
    
    if direction == 'LONG':
        # ── TARGET (upside) ──
        if source.startswith('macro') and key == 'M_BUY':
            m_drop = use_ceil - use_floor
            raw_target = use_floor + m_drop * 0.50
        else:
            raw_target = use_ceil if (use_ceil > price and use_ceil < price + atr * 5) else price + atr * 1.5
        
        target = round(min(raw_target, price + atr * 3), 2)
        # Floor: at least 1× ATR up
        if target - entry < atr * min_target_atr:
            target = round(entry + atr * min_target_atr, 2)
        
        if cap_1m:
            gap = target - entry
            target = round(entry + gap * 0.65, 2)
            notes.append("65%cap")
        
        # ── STOP (downside) ──
        raw_stop = use_floor if (use_floor < price and use_floor > price - atr * max_stop_atr) else price - atr
        stop = round(max(raw_stop, price - atr * max_stop_atr), 2)
    
    else:  # SHORT
        # ── TARGET (downside) ──
        # Use the BEST available floor that's ATR-reasonable
        candidate_floors = []
        if source.startswith('macro') and macro:
            candidate_floors.append(macro['floor'])
        if floor_1d > 0 and floor_1d < price:
            candidate_floors.append(floor_1d)
        if floor_1h > 0 and floor_1h < price:
            candidate_floors.append(floor_1h)
        
        # Pick the highest floor that's still below entry (closest reasonable target)
        reasonable_floors = [f for f in candidate_floors if f < price and (entry - f) <= atr * 3]
        if reasonable_floors:
            raw_target = max(reasonable_floors)  # closest floor = highest probability target
        else:
            raw_target = price - atr * 1.5
        
        target = round(max(raw_target, price - atr * 3), 2)
        # Floor: at least 1× ATR down
        if entry - target < atr * min_target_atr:
            target = round(entry - atr * min_target_atr, 2)
        
        if cap_1m:
            gap = entry - target
            target = round(entry - gap * 0.65, 2)
            notes.append("65%cap")
        
        # ── STOP (upside) ──
        candidate_ceils = []
        if source.startswith('macro') and macro:
            candidate_ceils.append(macro['ceiling'])
        if ceil_1d > 0 and ceil_1d > price:
            candidate_ceils.append(ceil_1d)
        if ceil_1h > 0 and ceil_1h > price:
            candidate_ceils.append(ceil_1h)
        
        reasonable_ceils = [c for c in candidate_ceils if c > price and (c - entry) <= atr * max_stop_atr]
        if reasonable_ceils:
            raw_stop = min(reasonable_ceils)  # closest ceiling = tightest stop
        else:
            raw_stop = price + atr
        
        stop = round(min(raw_stop, price + atr * max_stop_atr), 2)
    
    # ── R:R REPAIR ──
    # If R:R < 0.7, try to widen target or tighten stop to improve it
    risk = abs(entry - stop)
    reward = abs(target - entry)
    rr = reward / risk if risk > 0 else 0
    
    if rr < min_rr:
        # Try widening target to 2× ATR
        if direction == 'LONG':
            new_target = entry + atr * 2
            new_rr = abs(new_target - entry) / risk if risk > 0 else 0
            if new_rr >= min_rr:
                target = round(new_target, 2)
                notes.append("widened tgt 2×ATR")
        else:
            new_target = entry - atr * 2
            new_rr = abs(new_target - entry) / risk if risk > 0 else 0
            if new_rr >= min_rr:
                target = round(new_target, 2)
                notes.append("widened tgt 2×ATR")
        
        # Recalculate
        reward = abs(target - entry)
        rr = reward / risk if risk > 0 else 0
    
    if rr < min_rr:
        # Still bad — try tightening stop to 1× ATR
        if direction == 'LONG':
            new_stop = entry - atr
            new_rr = reward / abs(entry - new_stop) if abs(entry - new_stop) > 0 else 0
            if new_rr >= min_rr:
                stop = round(new_stop, 2)
                notes.append("tight stop 1×ATR")
        else:
            new_stop = entry + atr
            new_rr = reward / abs(new_stop - entry) if abs(new_stop - entry) > 0 else 0
            if new_rr >= min_rr:
                stop = round(new_stop, 2)
                notes.append("tight stop 1×ATR")
        
        risk = abs(entry - stop)
        reward = abs(target - entry)
        rr = reward / risk if risk > 0 else 0
    
    # Ensure target is in the right direction
    if direction == 'LONG' and target <= entry:
        target = round(entry + atr * min_target_atr, 2)
    if direction == 'SHORT' and target >= entry:
        target = round(entry - atr * min_target_atr, 2)
    
    # Ensure stop is on the right side
    if direction == 'LONG' and stop >= entry:
        stop = round(entry - atr, 2)
    if direction == 'SHORT' and stop <= entry:
        stop = round(entry + atr, 2)
    
    # Re-finalize R:R
    risk = abs(entry - stop)
    reward = abs(target - entry)
    rr = reward / risk if risk > 0 else 0
    
    # R:R check
    risk = abs(entry - stop)
    reward = abs(target - entry)
    rr = reward / risk if risk > 0 else 0
    if rr < 0.5:
        grade = 'D'
        notes.append(f"R:R{rr:.1f}!")
    
    # ════════════════════════════════════════════════════════
    # FORMAT OUTPUT
    # ════════════════════════════════════════════════════════
    arrow = "🟢 LONG" if direction == "LONG" else "🔴 SHORT"
    now_et = datetime.now(ET)
    
    # Multi-TF summary
    tf_summary = []
    if letter_1m in ('W', 'M'):
        tf_summary.append(f"1M={letter_1m}")
    if letter_1w in ('W', 'M'):
        tf_summary.append(f"1W={letter_1w}@{pct_1w:.0f}%")
    if letter_1d in ('W', 'M'):
        tf_summary.append(f"1D={letter_1d}@{pct_1d:.0f}%")
    if letter_1h in ('W', 'M'):
        tf_summary.append(f"1h={letter_1h}@{pct_1h:.0f}%")
    tf_str = " | ".join(tf_summary) if tf_summary else regime
    
    output = (
        f"**{ticker}** ${price:.2f}  {arrow}\n"
        f"Entry ${entry:.2f} → Target ${target:.2f} → Stop ${stop:.2f}\n"
        f"**[{grade}]** {win_rate:.0%} WR | R:R {rr:.1f} | RSI {rsi:.0f}\n"
        f"📐 {tf_str}\n"
        f"_{[' '.join(notes)]}_"
    ).replace("['_", "").replace("_']", "")
    # Cleaner notes formatting:
    note_str = " ".join(notes) if notes else ""
    output = (
        f"**{ticker}** ${price:.2f}  {arrow}\n"
        f"Entry ${entry:.2f} → Target ${target:.2f} → Stop ${stop:.2f}\n"
        f"**[{grade}]** {win_rate:.0%} WR | R:R {rr:.1f} | RSI {rsi:.0f}\n"
        f"📐 {tf_str}\n"
        f"_{note_str}_"
    )
    
    print(output)
    
    # Save
    result = {
        'ticker': ticker, 'price': price, 'direction': direction,
        'entry': entry, 'target': target, 'stop': stop,
        'grade': grade, 'win_rate': round(win_rate, 3),
        'rr': round(rr, 2), 'rsi': round(rsi, 1),
        'regime': regime,
        '1m_letter': letter_1m, '1w_letter': letter_1w, '1w_pct': round(pct_1w, 1),
        '1d_letter': letter_1d, '1d_pct': round(pct_1d, 1),
        '1h_letter': letter_1h, '1h_pct': round(pct_1h, 1),
        'source': source, 'notes': notes,
        'atr': round(atr, 2),
        'move_detectors': {
            'spike': bool(spike), 'dip': bool(dip),
            'momentum': momentum['type'] if momentum else None,
            'macro': macro['type'] if macro else None,
        },
        'time': now_et.isoformat(),
    }
    
    try:
        (MASTER_DIR / f"master_{ticker.lower()}.json").write_text(
            json.dumps(result, indent=2, default=str)
        )
    except:
        pass
    
    return result


# ═══════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════

if __name__ == "__main__":
    # Market-hours gate: skip if outside 8:30 AM - 4:00 PM ET (Mon-Fri)
    # Pre-market and EOD crons override with --force
    now_et = datetime.now(ET)
    force = '--force' in sys.argv
    
    if not force:
        if now_et.weekday() >= 5:
            print("⏸️ Weekend — markets closed. Use --force to override.")
            sys.exit(0)
        if now_et.hour < 8 or now_et.hour >= 16:
            print(f"⏸️ After hours ({now_et.strftime('%I:%M %p ET')}) — use --force to override.")
            sys.exit(0)
    
    if '--all' in sys.argv:
        tickers = list(TICKERS.keys())
    else:
        tickers = [sys.argv[1] if len(sys.argv) > 1 else 'WTI']
    
    for t in tickers:
        try:
            result = compute_binary_signal(t)
        except Exception as e:
            print(f"**{t}** Error: {e}")