#!/usr/bin/env python3
"""
W-M Wave Scanner
================
W and M are the shapes of the 2-1 cycle on the chart.

DOWNTREND: 1-up(bounce)→2-down(drop) repeating
  2-down = W shape = BUY (at the double bottom)
  1-up   = M shape = SELL (at the double top)

UPTREND: 1-down(pullback)→2-up(extension) repeating
  2-up   = M shape = SELL (at the double top)
  1-down = W shape = BUY (at the double bottom)

The letters alternate. W→M→W→M forever.

Usage:
    python3 wm_scanner.py              # WTI
    python3 wm_scanner.py RGTI
"""

import sys, json, numpy as np, yfinance as yf
from pathlib import Path
from scipy.signal import argrelextrema
from datetime import datetime
from dataclasses import dataclass
from typing import List, Optional

from mtf_wave_quantifier import get_mtf_regime
from signal_perf import oil_perf_line, rgti_perf_line

STORAGE = Path(__file__).parent / "storage"
TICKERS = {
    "WTI":  {"symbol": "CL=F",  "perf_fn": oil_perf_line},
    "RGTI": {"symbol": "RGTI", "perf_fn": rgti_perf_line},
}


# ─── Data Structures ───

@dataclass
class Letter:
    """One W or M shape on the chart."""
    letter_type: str   # 'W' or 'M'
    left: float        # first trough (W) or peak (M)
    mid: float         # bounce peak (W) or dip trough (M)
    right: float       # second trough (W) or peak (M)
    left_bar: int
    mid_bar: int
    right_bar: int
    size_pct: float    # amplitude %
    width_bars: int

    @property
    def floor(self):
        """W floor = lower trough. M floor = the dip."""
        return min(self.left, self.right) if self.letter_type == 'W' else self.mid

    @property
    def ceiling(self):
        """M ceiling = higher peak. W ceiling = the bounce."""
        return max(self.left, self.right) if self.letter_type == 'M' else self.mid


@dataclass  
class Stats:
    n: int
    w_med: float; w_p90: float; w_width: float
    m_med: float; m_p90: float; m_width: float


# ─── Fetch & Regime ───

def fetch_1h(symbol, days=30):
    df = yf.Ticker(symbol).history(period=f"{days}d", interval="1h")
    if df.empty: return None
    return (df['High'].values.astype(float),
            df['Low'].values.astype(float),
            df['Close'].values.astype(float))


def detect_regime(closes):
    if len(closes) < 24:
        return "UP" if closes[-1] > closes[0] else "DOWN"
    r, p = closes[-12:], closes[-24:-12]
    rh, rl, ph, pl = np.max(r), np.min(r), np.max(p), np.min(p)
    if rh < ph and rl < pl: return "DOWN"
    if rh > ph and rl > pl: return "UP"
    return "DOWN" if closes[-1] < (rh+rl)/2 else "UP"


# ─── Detect Letters ───

def detect_letters(highs, lows, order=3):
    hi = argrelextrema(highs, np.greater, order=order)[0]
    lo = argrelextrema(lows, np.less, order=order)[0]
    if len(hi) < 2 or len(lo) < 2: return []

    # Merge swings into sorted alternating list
    swings = []
    for i in hi: swings.append((int(i), float(highs[i]), 'H'))
    for i in lo: swings.append((int(i), float(lows[i]), 'L'))
    swings.sort()

    # Collapse consecutive same-type
    alt = [swings[0]]
    for s in swings[1:]:
        if s[2] == alt[-1][2]:
            if s[2] == 'H' and s[1] > alt[-1][1]: alt[-1] = s
            elif s[2] == 'L' and s[1] < alt[-1][1]: alt[-1] = s
        else:
            alt.append(s)
    if len(alt) < 3: return []

    # Form letters from every triple
    raw = []
    for i in range(len(alt) - 2):
        ab, ap, at = alt[i]
        bb, bp, bt = alt[i+1]
        cb, cp, ct = alt[i+2]

        if at == 'L' and bt == 'H' and ct == 'L':
            sz = (bp - min(ap, cp)) / min(ap, cp) * 100
            if sz > 0.3:
                raw.append(Letter('W', ap, bp, cp, ab, bb, cb, round(sz,2), cb-ab))

        elif at == 'H' and bt == 'L' and ct == 'H':
            sz = (max(ap, cp) - bp) / max(ap, cp) * 100
            if sz > 0.3:
                raw.append(Letter('M', ap, bp, cp, ab, bb, cb, round(sz,2), cb-ab))

    # Enforce strict W→M→W→M alternation
    if not raw: return []
    letters = [raw[0]]
    for lt in raw[1:]:
        if lt.letter_type == letters[-1].letter_type:
            if lt.size_pct > letters[-1].size_pct: letters[-1] = lt
        else:
            letters.append(lt)
    return letters


# ─── Stats ───

def compute_stats(letters):
    ws = [l for l in letters if l.letter_type == 'W']
    ms = [l for l in letters if l.letter_type == 'M']
    if not ws and not ms: return None
    wa = [w.size_pct for w in ws]; ww = [w.width_bars for w in ws]
    ma = [m.size_pct for m in ms]; mw = [m.width_bars for m in ms]
    def m(a): return float(np.median(a)) if a else 0
    def p(a): return float(np.percentile(a,90)) if len(a)>=3 else (float(np.max(a)) if a else 0)
    return Stats(len(ws)+len(ms), m(wa), p(wa), m(ww), m(ma), p(ma), m(mw))


# ─── Phase ───

def find_phase(letters, price, regime, stats):
    """
    Which letter is forming NOW?
    
    In W = BUY (the whole W, from floor to ceiling)
    In M = SELL (the whole M, from floor to ceiling)
    
    After W completes (gaps filled at ceiling) → M starts → SELL
    After M completes (gaps filled at floor) → W starts → BUY
    """
    if not letters:
        return None, "WAIT", "No patterns", price, price

    last = letters[-1]

    # ── Current letter is W ──
    if last.letter_type == 'W':
        # W: price dropped from ceiling → bottom → bouncing back
        # Still in W (BUY) until it fills back to the ceiling
        w_ceil = last.ceiling
        w_floor = last.floor

        if price < w_ceil:
            # Still filling the W → gaps not filled yet → BUY
            gap_left = (w_ceil - price) / price * 100
            return last, "BUY", f"W filling: ${price:.2f} → ${w_ceil:.2f} ceiling ({gap_left:.1f}% gap left) → BUY until filled", w_ceil, w_floor * 0.97
        else:
            # W filled (price at or above ceiling) → M starting → SELL
            if stats and stats.m_med > 0:
                m_target = price * (1 + stats.m_med / 100)
                return None, "SELL", f"W filled at ${w_ceil:.2f} → M forming → SELL, target ${m_target:.2f}", m_target, w_ceil
            return None, "SELL", f"W filled at ${w_ceil:.2f} → M starting → SELL", price, w_ceil

    # ── Current letter is M ──
    else:
        # M: price rose from floor → ceiling → dropping back
        # Still in M (SELL) until it fills back to the floor
        m_ceil = last.ceiling
        m_floor = last.floor

        if price > m_floor:
            # Still filling the M → gaps not filled yet → SELL
            gap_left = (price - m_floor) / price * 100
            return last, "SELL", f"M filling: ${price:.2f} → ${m_floor:.2f} floor ({gap_left:.1f}% gap left) → SELL until filled", m_floor, m_ceil * 1.03
        else:
            # M filled (price at or below floor) → W starting → BUY
            if stats and stats.w_med > 0:
                w_target = price * (1 - stats.w_med / 100)
                return None, "BUY", f"M filled at ${m_floor:.2f} → W forming → BUY, target floor ${w_target:.2f}", w_target, m_floor
            return None, "BUY", f"M filled at ${m_floor:.2f} → W starting → BUY", price, m_floor


# ─── Format ───

def format_result(ticker, result):
    lines = []
    ri = "📈" if result.regime == "UP" else "📉"
    s = result.stats
    lines.append(f"{ri} **{ticker} W-M** ${result.price:.2f}")
    lines.append(f"🏔️ {result.regime} | MTF: {result.alignment}")
    
    if result.regime == "DOWN":
        lines.append("🔄 1-up(M→SELL) → 2-down(W→BUY) repeating")
    else:
        lines.append("🔄 1-down(W→BUY) → 2-up(M→SELL) repeating")
    
    lines.append("")
    ai = {"BUY":"🟢","SELL":"🔴"}.get(result.action, "🟡")
    lines.append(f"{ai} **{result.action}**")
    lines.append(f"💡 {result.action_reason}")
    if result.action == "BUY":
        lines.append(f"🎯 Target: ${result.target:.2f}")
        lines.append(f"🛑 Stop: ${result.stop:.2f}")
    elif result.action == "SELL":
        lines.append(f"🎯 Target: ${result.target:.2f}")
        lines.append(f"🛑 Stop: ${result.stop:.2f}")

    if result.letters:
        lines.append("")
        lines.append("📊 Letters:")
        for lt in result.letters[-8:]:
            ic = "🟢W" if lt.letter_type == 'W' else "🔴M"
            lines.append(f"  {ic} ${lt.left:.2f}→${lt.mid:.2f}→${lt.right:.2f} | {lt.size_pct:.1f}%/{lt.width_bars}h")

    if s and s.n >= 2:
        lines.append(f"📐 W: med={s.w_med:.1f}% p90={s.w_p90:.1f}% ({s.w_width:.0f}h) | M: med={s.m_med:.1f}% p90={s.m_p90:.1f}% ({s.m_width:.0f}h)")

    lines.append(TICKERS[ticker]["perf_fn"]())
    return "\n".join(lines)


# ─── Main ───

def run_scan(ticker, send_alerts=True):
    if ticker not in TICKERS: return None

    data = fetch_1h(TICKERS[ticker]["symbol"])
    if data is None: return None
    h, l, c = data
    price = float(c[-1])

    regime = detect_regime(c)
    _, alignment = get_mtf_regime(ticker)

    # Adaptive swing order
    order = 3 if ticker == "RGTI" else 5
    letters = detect_letters(h, l, order=order)
    stats = compute_stats(letters)
    _, action, reason, target, stop = find_phase(letters, price, regime, stats)

    alert = action if action in ("BUY","SELL") else None
    alert_msg = f"{'🟢 BUY' if action=='BUY' else '🔴 SELL'} {ticker} @ ${price:.2f} — {reason}" if alert else None

    result = type('R',(),{
        'ticker':ticker,'price':price,'regime':regime,'alignment':alignment,
        'letters':letters,'stats':stats,'action':action,
        'action_reason':reason,'target':round(target,2),'stop':round(stop,2),
        'alert':alert,'alert_msg':alert_msg
    })()

    formatted = format_result(ticker, result)
    print(formatted)

    if send_alerts and alert:
        try:
            from telegram_bot import send_message
            send_message(formatted)
        except: pass

    try:
        (STORAGE / f"last_wm_{ticker.lower()}.json").write_text(json.dumps({
            'price':price,'regime':regime,'action':action,
            'alert':alert or '','time':datetime.utcnow().isoformat() if alert else ''
        }, indent=2))
    except: pass

    return result


if __name__ == "__main__":
    t = sys.argv[1] if len(sys.argv) > 1 else "WTI"
    run_scan(t, "--no-send" not in sys.argv)