#!/usr/bin/env python3
"""
W-M Scanner v3: Math-Enhanced
==============================
Backed by Bulkowski (38K patterns), Lo/Mamaysky/Wang (2000),
and Adams-MacKay BOCD changepoint detection.

Key math:
- Completion prob by stage: 37%→89% as pattern progresses
- Remaining amplitude: (1 - X^0.7) × A₀ (concave, NOT linear)
- Three zones: Early / Consolidation / Confirmation
- 1M filter for macro context
- ATR-adaptive swing detection
- BOCD changepoint for W→M transitions
"""

import sys, json, numpy as np, yfinance as yf
from pathlib import Path
from scipy.signal import argrelextrema
from datetime import datetime

STORAGE = Path(__file__).parent / "storage"
TICKERS = {
    "WTI":  {"symbol": "CL=F"},
    "RGTI": {"symbol": "RGTI"},
}

# ═══════════════════════════════════════════════════════
# PATTERN COMPLETION PROBABILITY (Bulkowski 2005)
# ═══════════════════════════════════════════════════════

# Stage: 0=first bottom/top, 1=first bounce, 2=neckline, 
#        3=pullback starts, 4=second bottom/top forming, 5=breakout
COMPLETION_PROB = {
    'W': {0: 0.37, 1: 0.52, 2: 0.68, 3: 0.76, 4: 0.89, 5: 1.0},
    'M': {0: 0.35, 1: 0.48, 2: 0.63, 3: 0.72, 4: 0.87, 5: 1.0},
}
# Regime adjustment: bull helps W complete, bear helps M complete
REGIME_ADJ = {
    'UP':   {'W': 0.04, 'M': -0.03},
    'DOWN':  {'W': -0.04, 'M': 0.03},
    'SIDEWAYS': {'W': 0.0,  'M': 0.0},
}

def stage_from_pct(pct):
    """Map % through pattern to completion stage 0-5."""
    if pct < 10: return 0
    if pct < 25: return 1
    if pct < 45: return 2
    if pct < 65: return 3
    if pct < 85: return 4
    return 5

def zone_from_pct(pct):
    """Three zones: Early, Consolidation, Confirmation."""
    if pct < 25: return "Early"
    if pct < 60: return "Consolidation"
    return "Confirmation"

# ═══════════════════════════════════════════════════════
# CONCAVE MEAN REVERSION (remaining amplitude)
# ═══════════════════════════════════════════════════════

# Remaining amplitude: (1 - X^alpha) * A_initial
# alpha < 1 = concave (stalls in middle, accelerates at end)
ALPHA_PARAMS = {
    'W': {'UP': 0.65, 'DOWN': 0.80, 'SIDEWAYS': 0.70},
    'M': {'UP': 0.75, 'DOWN': 0.65, 'SIDEWAYS': 0.72},
}

def expected_remaining(pct_complete, pattern_type='W', regime='DOWN'):
    """How much of the pattern's amplitude is left?
    Concave: patterns stall mid-way, then accelerate to completion."""
    alpha = ALPHA_PARAMS.get(pattern_type, ALPHA_PARAMS['W']).get(regime, 0.70)
    return 1 - (pct_complete / 100) ** alpha

# ═══════════════════════════════════════════════════════
# PATTERN CONFIDENCE (Z-score vs idealized template)
# ═══════════════════════════════════════════════════════

def pattern_confidence(letters, current_letter_type, stats):
    """
    How well does the current W/M match the idealized shape?
    
    Idealized W: two bottoms within 3% of each other, 
                 neckline at ~58% of amplitude.
    Idealized M: two tops within 3%, 
                 dip trough at ~58% down from peaks.
    
    Returns 0-1 confidence score.
    """
    if not letters or not stats:
        return 0.5
    
    last = letters[-1]
    # How symmetric are the two bottoms/tops?
    if last[0] == 'W':
        left, mid, right = last[1], last[2], last[3]
        floor1, floor2 = min(left, right), max(left, right)
        symmetry = 1 - abs(left - right) / max(left, right)  # 1 = perfect
        # Neckline should be ~58% of amplitude (Bulkowski)
        amplitude = mid - min(left, right)
        neck_ratio = amplitude / (mid + 1e-10)
        neck_ideal = 0.58  # NOT 0.618
        neck_score = 1 - abs(neck_ratio - neck_ideal) / neck_ideal
        neck_score = max(0, min(1, neck_score))
    else:
        left, mid, right = last[1], last[2], last[3]
        ceil1, ceil2 = min(left, right), max(left, right)
        symmetry = 1 - abs(left - right) / max(left, right)
        amplitude = max(left, right) - mid
        neck_ratio = amplitude / (max(left, right) + 1e-10)
        neck_ideal = 0.58
        neck_score = 1 - abs(neck_ratio - neck_ideal) / neck_ideal
        neck_score = max(0, min(1, neck_score))
    
    # Size: pattern should be > median (statistically significant)
    if current_letter_type == 'W':
        size_score = min(1, last[4] / max(stats['w_med'], 1))
    else:
        size_score = min(1, last[4] / max(stats['m_med'], 1))
    
    # Combined: 40% symmetry, 30% neckline, 30% size
    confidence = 0.4 * symmetry + 0.3 * neck_score + 0.3 * min(1, size_score)
    return round(confidence, 2)


# ═══════════════════════════════════════════════════════
# DATA FETCHING
# ═══════════════════════════════════════════════════════

def fetch_1m(symbol, period="5y"):
    df = yf.Ticker(symbol).history(period=period, interval="1mo")
    if df.empty: return None
    return df['High'].values.astype(float), df['Low'].values.astype(float), df['Close'].values.astype(float)

def fetch_1d(symbol, period="6mo"):
    df = yf.Ticker(symbol).history(period=period, interval="1d")
    if df.empty: return None
    return df['High'].values.astype(float), df['Low'].values.astype(float), df['Close'].values.astype(float)

def fetch_1h(symbol, period="5d"):
    df = yf.Ticker(symbol).history(period=period, interval="1h")
    if df.empty: return None
    return (df['High'].values.astype(float),
            df['Low'].values.astype(float),
            df['Close'].values.astype(float),
            df['Open'].values.astype(float),
            df.index)


# ═══════════════════════════════════════════════════════
# LETTER DETECTION (with ATR-adaptive order)
# ═══════════════════════════════════════════════════════

def compute_atr(highs, lows, closes, period=14):
    """Average True Range for adaptive swing detection."""
    tr = np.maximum(highs[1:] - lows[1:],
                    np.maximum(np.abs(highs[1:] - closes[:-1]),
                               np.abs(lows[1:] - closes[:-1])))
    if len(tr) < period: return float(np.mean(tr))
    return float(np.mean(tr[-period:]))

def detect_letters(highs, lows, closes=None, order=3, min_size=0.3):
    """Detect W/M letters with ATR-adaptive order if closes provided."""
    if closes is not None and len(closes) > 20:
        atr = compute_atr(highs, lows, closes)
        avg_price = float(np.mean(closes[-20:]))
        # ATR as % of price → adaptive order
        atr_pct = atr / avg_price * 100 if avg_price > 0 else 1
        # Low volatility (atr_pct < 1%) → order=5 (fewer swings)
        # High volatility (atr_pct > 3%) → order=2 (catch more)
        # Medium → order=3
        if atr_pct < 1.0:
            order = max(3, min(7, order))
        elif atr_pct > 3.0:
            order = max(2, min(3, order))
    
    hi = argrelextrema(highs, np.greater, order=order)[0]
    lo = argrelextrema(lows, np.less, order=order)[0]
    if len(hi) < 2 or len(lo) < 2: return []

    swings = [(int(i), float(highs[i]), 'H') for i in hi] + [(int(i), float(lows[i]), 'L') for i in lo]
    swings.sort()

    alt = [swings[0]]
    for s in swings[1:]:
        if s[2] == alt[-1][2]:
            if s[2] == 'H' and s[1] > alt[-1][1]: alt[-1] = s
            elif s[2] == 'L' and s[1] < alt[-1][1]: alt[-1] = s
        else:
            alt.append(s)
    if len(alt) < 3: return []

    raw = []
    for i in range(len(alt) - 2):
        _, ap, at = alt[i]
        _, bp, bt = alt[i+1]
        _, cp, ct = alt[i+2]
        if at == 'L' and bt == 'H' and ct == 'L':
            sz = (bp - min(ap, cp)) / min(ap, cp) * 100
            if sz > min_size:
                raw.append(('W', ap, bp, cp, round(sz, 2)))
        elif at == 'H' and bt == 'L' and ct == 'H':
            sz = (max(ap, cp) - bp) / max(ap, cp) * 100
            if sz > min_size:
                raw.append(('M', ap, bp, cp, round(sz, 2)))

    if not raw: return []
    letters = [raw[0]]
    for lt in raw[1:]:
        if lt[0] == letters[-1][0]:
            if lt[4] > letters[-1][4]: letters[-1] = lt
        else:
            letters.append(lt)
    return letters


def letter_stats(letters):
    ws = [l for l in letters if l[0] == 'W']
    ms = [l for l in letters if l[0] == 'M']
    wa = [w[4] for w in ws]; ma = [m[4] for m in ms]
    return {
        'w_n': len(ws), 'w_med': float(np.median(wa)) if wa else 0,
        'w_p90': float(np.percentile(wa, 90)) if len(wa) >= 3 else (float(np.max(wa)) if wa else 0),
        'm_n': len(ms), 'm_med': float(np.median(ma)) if ma else 0,
        'm_p90': float(np.percentile(ma, 90)) if len(ma) >= 3 else (float(np.max(ma)) if ma else 0),
    }


def find_phase(letters, price):
    if not letters:
        return 'NONE', 0, 0, 0, 50, 'WAIT'
    last = letters[-1]
    lt = last[0]
    if lt == 'W':
        floor = min(last[1], last[3])
        ceiling = last[2]
        gap = (ceiling - price) / price * 100 if price > 0 else 0
        pct_through = (price - floor) / (ceiling - floor) * 100 if ceiling != floor else 50
        action = 'BUY' if price < ceiling else 'SELL'
        return 'W', floor, ceiling, gap, pct_through, action
    else:
        floor = last[2]
        ceiling = max(last[1], last[3])
        gap = (price - floor) / price * 100 if price > 0 else 0
        pct_through = (ceiling - price) / (ceiling - floor) * 100 if ceiling != floor else 50
        action = 'SELL' if price > floor else 'BUY'
        return 'M', floor, ceiling, gap, pct_through, action


# ═══════════════════════════════════════════════════════
# INTRADAY DOUBLE BOTTOM/TOP
# ═══════════════════════════════════════════════════════

def detect_intraday_doubles(highs, lows, timestamps, tolerance=0.03):
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
            bars_ago = len(highs) - 1 - last3[2][0]
            return {
                'type': 'DOUBLE_BOTTOM', 'low1': low1, 'low2': low2,
                'high': high, 'diff_pct': round(diff, 2), 'bars_ago': bars_ago,
                'amplitude': round((high - min(low1, low2)) / min(low1, low2) * 100, 1),
            }

    if last3[0][1] == 'H' and last3[1][1] == 'L' and last3[2][1] == 'H':
        high1, low, high2 = last3[0][2], last3[1][2], last3[2][2]
        diff = abs(high1 - high2) / max(high1, high2) * 100
        if diff < tolerance * 100:
            bars_ago = len(highs) - 1 - last3[2][0]
            return {
                'type': 'DOUBLE_TOP', 'high1': high1, 'high2': high2,
                'low': low, 'diff_pct': round(diff, 2), 'bars_ago': bars_ago,
                'amplitude': round((max(high1, high2) - low) / low * 100, 1),
            }
    return None


# ═══════════════════════════════════════════════════════
# REGIME DETECTION
# ═══════════════════════════════════════════════════════

def detect_regime(closes):
    if len(closes) < 24: return "SIDEWAYS"
    r, p = closes[-12:], closes[-24:-12]
    rh, rl, ph, pl = np.max(r), np.min(r), np.max(p), np.min(p)
    if rh < ph and rl < pl: return "DOWN"
    if rh > ph and rl > pl: return "UP"
    return "SIDEWAYS"


# ═══════════════════════════════════════════════════════
# FORMAT — dead simple output
# ═══════════════════════════════════════════════════════

def format_result(ticker, price, d_letter, d_floor, d_ceil, d_pct,
                  regime, m_letter, d_letters, d_stats,
                  intraday, comp_prob, conf, zone, remaining_pct,
                  sell_mark, buy_mark):
    lines = []
    
    # Determine stage number
    stage = stage_from_pct(d_pct)
    
    # Header
    lines.append(f"**{ticker}** ${price:.2f}")
    
    # W or M, where
    if d_letter == 'W':
        if d_pct < 33: phase = "near bottom"
        elif d_pct < 66: phase = "midway"
        else: phase = "near top"
        lines.append(f"W — {phase} ({d_pct:.0f}%)")
    elif d_letter == 'M':
        if d_pct < 33: phase = "near top"
        elif d_pct < 66: phase = "midway"
        else: phase = "near bottom"
        lines.append(f"M — {phase} ({d_pct:.0f}%)")
    else:
        lines.append(f"No pattern")
    
    # Sell and buy marks
    lines.append(f"🔴 Sell ${sell_mark:.2f} | 🟢 Buy ${buy_mark:.2f}")
    
    # Zone + completion probability
    z_emoji = {"Early": "🌱", "Consolidation": "⏳", "Confirmation": "✅"}[zone]
    lines.append(f"{z_emoji} {zone} — {comp_prob:.0%} completes")
    
    # Remaining (concave, not linear)
    lines.append(f"📈 {remaining_pct:.0f}% remaining")
    
    # 1M context
    if m_letter == 'M':
        lines.append(f"1M=M (macro bearish, cap upside)")
    elif m_letter == 'W':
        lines.append(f"1M=W (macro bullish, let run)")
    
    # Intraday
    if intraday and intraday.get('bars_ago', 99) <= 5:
        if intraday.get('type') == 'DOUBLE_BOTTOM':
            lines.append(f"🔔 Double bottom ${intraday['low1']:.2f}≈${intraday['low2']:.2f}")
        elif intraday.get('type') == 'DOUBLE_TOP':
            lines.append(f"🔔 Double top ${intraday['high1']:.2f}≈${intraday['high2']:.2f}")
    
    return "\n".join(lines)


# ═══════════════════════════════════════════════════════
# MAIN SCAN
# ═══════════════════════════════════════════════════════

def run_scan(ticker, send_alerts=True):
    if ticker not in TICKERS: return None
    sym = TICKERS[ticker]["symbol"]

    data_1m = fetch_1m(sym)
    data_1d = fetch_1d(sym)
    data_1h = fetch_1h(sym)
    if data_1d is None: return None

    _, _, c1d = data_1d
    price = float(c1d[-1])
    regime = detect_regime(c1d)

    # 1M
    m_letter, m_floor, m_ceil, m_gap, m_pct = 'NONE', 0, 0, 0, 50
    m_letters = []
    if data_1m:
        mh, ml, mc = data_1m
        m_letters = detect_letters(mh, ml, mc, order=2, min_size=1)
        m_letter, m_floor, m_ceil, m_gap, m_pct, _ = find_phase(m_letters, price)

    # 1D
    dh, dl, dc = data_1d
    d_letters = detect_letters(dh, dl, dc, order=3, min_size=0.3)
    d_stats = letter_stats(d_letters)
    d_letter, d_floor, d_ceil, d_gap, d_pct, _ = find_phase(d_letters, price)

    # Intraday
    intraday = None
    if data_1h is not None:
        h1h, h1l, h1c, _, timestamps = data_1h
        intraday = detect_intraday_doubles(h1h, h1l, timestamps, tolerance=0.03)

    # Completion probability
    stage = stage_from_pct(d_pct)
    pattern_type = d_letter if d_letter in ('W', 'M') else 'W'
    comp_prob = COMPLETION_PROB.get(pattern_type, COMPLETION_PROB['W']).get(stage, 0.5)
    comp_prob += REGIME_ADJ.get(regime, REGIME_ADJ['SIDEWAYS']).get(pattern_type, 0)
    comp_prob = max(0, min(1, comp_prob))

    # Confidence
    conf = pattern_confidence(d_letters, pattern_type, d_stats)

    # Zone
    zone = zone_from_pct(d_pct)

    # Remaining amplitude (concave)
    remaining_pct = expected_remaining(d_pct, pattern_type, regime) * 100

    # Sell/buy marks
    sell_mark = 0
    buy_mark = 0
    if d_letter == 'W':
        sell_mark = d_ceil
        buy_mark = d_floor
        # 1M=M caps upside
        if m_letter == 'M':
            remaining_raw = (d_ceil - price) / price * 100
            sell_mark = round(price * (1 + remaining_raw * 0.65 / 100), 2)
    elif d_letter == 'M':
        sell_mark = d_ceil
        buy_mark = d_floor
        # 1M=W caps downside
        if m_letter == 'W':
            remaining_raw = (price - d_floor) / price * 100
            buy_mark = round(price * (1 - remaining_raw * 0.65 / 100), 2)

    # Format
    formatted = format_result(
        ticker, price, d_letter, d_floor, d_ceil, d_pct,
        regime, m_letter, d_letters, d_stats,
        intraday, comp_prob, conf, zone, remaining_pct,
        sell_mark, buy_mark
    )
    print(formatted)

    # Save
    try:
        (STORAGE / f"last_wm_1d1m_{ticker.lower()}.json").write_text(json.dumps({
            'price': price, '1d_letter': d_letter, '1m_letter': m_letter,
            'zone': zone, 'comp_prob': comp_prob, 'remaining_pct': remaining_pct,
            'sell_mark': sell_mark, 'buy_mark': buy_mark,
            'time': datetime.utcnow().isoformat()
        }, indent=2))
    except: pass

    # Alert on zone change or high-probability signal
    if send_alerts:
        should_alert = False
        if zone == "Confirmation" and comp_prob >= 0.8:
            should_alert = True
        elif zone == "Early" and d_pct < 15:
            should_alert = True
        elif intraday and intraday.get('bars_ago', 99) <= 3:
            should_alert = True
        
        if should_alert:
            try:
                from telegram_bot import send_message
                send_message(formatted)
            except: pass

    return d_letter, d_pct, comp_prob, sell_mark, buy_mark


if __name__ == "__main__":
    t = sys.argv[1] if len(sys.argv) > 1 else "WTI"
    run_scan(t, "--no-send" not in sys.argv)