#!/usr/bin/env python3
"""mw_1h.py — M/W position tracker across 2h/1h/30m/5m.

Always knows where we are in M or W on every timeframe.
Rules from this week's backtest:
  M 0-25%  → BUY   (early M, trend still strong — 88% WR)
  M 25-75% → HOLD  (mid-zone, no edge)
  M 75-100%→ SELL  (M completing, breakdown ahead — 71% WR)
  W 0-25%  → WAIT  (W bounce trap — 20% WR, don't buy)
  W 25-75% → HOLD  (mid-zone)
  W 75-100%→ BUY   (W completing, reversal coming)
  NONE     → HOLD
"""
import sys, json, numpy as np
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
import wm_tactical as wt
import yfinance as yf

TICKERS = {
    'WTI':  {'symbol': 'CL=F',  'name': 'WTI Crude'},
    'RGTI': {'symbol': 'RGTI',  'name': 'Rigetti'},
    'QBTX': {'symbol': 'QBTX',  'name': 'Quantum 2x'},
}

TF_CONFIG = {
    '2h':  {'yf_interval': '1h', 'period': '10d', 'resample': 2},
    '1h':  {'yf_interval': '1h', 'period': '5d',  'resample': 1},
    '30m': {'yf_interval': '30m','period': '5d',  'resample': 1},
    '5m':  {'yf_interval': '5m', 'period': '5d',  'resample': 1},
}

STORAGE = ROOT / 'storage'
STORAGE.mkdir(exist_ok=True)


def mw_action(pattern, pct):
    if pattern == 'M':
        if pct <= 25:  return 'BUY'
        if pct <= 75:  return 'HOLD'
        return 'SELL'
    elif pattern == 'W':
        if pct <= 25:  return 'WAIT'
        if pct <= 75:  return 'HOLD'
        return 'BUY'
    return 'HOLD'


def position_text(pat, pct):
    if pat == 'M':
        if pct <= 25:   return "top → early drop, momentum up"
        elif pct <= 75: return "mid-drop, hold"
        else:          return "near bottom, sell breakdown"
    elif pat == 'W':
        if pct <= 25:   return "top → early bounce, trap"
        elif pct <= 75: return "mid-bounce, hold"
        else:           return "near bottom, buy reversal"
    return "no pattern"


def fetch_tf(symbol, tf_name):
    """Fetch OHLC for a given timeframe. Resample if needed."""
    cfg = TF_CONFIG[tf_name]
    try:
        df = yf.download(symbol, period=cfg['period'], interval=cfg['yf_interval'], progress=False)
    except Exception:
        return None
    if len(df) < 10:
        return None

    closes = df['Close'].values.flatten().astype(float)
    highs = df['High'].values.flatten().astype(float)
    lows = df['Low'].values.flatten().astype(float)

    # Resample 1h→2h by taking every Nth bar
    r = cfg['resample']
    if r > 1:
        # Group into chunks of r bars, take high/low/close
        n = len(closes) // r * r
        closes = closes[:n].reshape(-1, r)
        highs_arr = highs[:n].reshape(-1, r)
        lows_arr = lows[:n].reshape(-1, r)
        closes = closes[:, -1]       # close = last bar of group
        highs = highs_arr.max(axis=1)
        lows = lows_arr.min(axis=1)

    return {'close': closes, 'high': highs, 'low': lows}


def detect_phase(tf_data, price):
    """Run detect_letters + find_phase. Always returns an answer if any M/W exists.
    Bypasses find_phase's 5% breakout filter — if price broke past the pattern,
    we want to know (M@100% = breakdown, W@0% = breakdown, etc)."""
    closes = tf_data['close']
    highs = tf_data['high']
    lows = tf_data['low']
    n = len(closes)
    if n < 10:
        return None

    for window in [30, min(60, n), n]:
        if window < 10:
            continue
        letters = wt.detect_letters(
            highs[-window:], lows[-window:], closes[-window:],
            order=2, min_amp_pct=0.5
        )
        if not letters:
            continue

        # Try wt.find_phase first (respects range, returns nice format)
        phase = wt.find_phase(letters, price)
        if phase and phase[0] in ('M', 'W'):
            return phase

        # Fallback: compute phase manually from last letter (no breakout filter)
        # This catches cases where price broke past the pattern range
        last = letters[-1]
        lt = last[0]
        if lt == 'M':
            ceiling = max(float(last[1]), float(last[3]))
            floor = float(last[2])
            if ceiling != floor:
                raw_pct = (ceiling - price) / (ceiling - floor) * 100
                pct = max(0, min(100, raw_pct))
                return ('M', floor, ceiling, pct, 'SELL' if pct >= 75 else 'BUY')
        elif lt == 'W':
            floor = min(float(last[1]), float(last[3]))
            ceiling = float(last[2])
            if ceiling != floor:
                raw_pct = (price - floor) / (ceiling - floor) * 100
                pct = max(0, min(100, raw_pct))
                return ('W', floor, ceiling, pct, 'BUY' if pct >= 75 else 'WAIT')

    return None


def scan_ticker(ticker):
    config = TICKERS.get(ticker)
    if not config:
        return None

    sym = config['symbol']
    # Get current price + ATR from 1d
    try:
        df_1d = yf.download(sym, period='10d', interval='1d', progress=False)
        if len(df_1d) < 5:
            return None
        d_close = df_1d['Close'].values.flatten().astype(float)
        d_high = df_1d['High'].values.flatten().astype(float)
        d_low = df_1d['Low'].values.flatten().astype(float)
        price = float(d_close[-1])
        atr = wt.compute_atr(d_high, d_low, d_close)
    except Exception:
        return None

    # Scan every timeframe
    tf_results = {}
    for tf in ['2h', '1h', '30m', '5m']:
        tf_data = fetch_tf(sym, tf)
        if tf_data is None or len(tf_data['close']) < 10:
            continue
        phase = detect_phase(tf_data, price)
        if phase:
            pat, floor, ceil, pct, _ = phase
            pct = max(0, min(100, pct))
            action = mw_action(pat, pct)
            tf_results[tf] = {
                'pattern': pat, 'pct': round(pct, 1), 'action': action,
                'floor': round(float(floor), 2), 'ceil': round(float(ceil), 2),
            }
        else:
            tf_results[tf] = {'pattern': 'NONE', 'pct': 50, 'action': 'HOLD', 'floor': 0, 'ceil': 0}

    # Primary signal: longest TF with BUY/SELL wins (1h/2h > 30m > 5m)
    primary_action = 'HOLD'
    primary_tf = '1h'
    primary_pat = 'NONE'
    primary_pct = 50
    for tf in ['2h', '1h', '30m', '5m']:
        r = tf_results.get(tf)
        if not r:
            continue
        if r['action'] in ('BUY', 'SELL'):
            primary_action = r['action']
            primary_tf = tf
            primary_pat = r['pattern']
            primary_pct = r['pct']
            break  # first (longest) TF with action wins

    # Entry/target/stop
    entry = price
    target = stop = 0
    if primary_action == 'BUY':
        target = round(price + atr * 2, 2)
        stop = round(price - atr, 2)
    elif primary_action == 'SELL':
        target = round(price - atr * 2, 2)
        stop = round(price + atr, 2)

    # Format
    arrow = {'BUY': '🟢', 'SELL': '🔴', 'HOLD': '🟡', 'WAIT': '⚪'}[primary_action]
    icon = {'M': '⬇️', 'W': '⬆️'}.get(primary_pat, '➡️')
    pos = position_text(primary_pat, primary_pct)

    lines = [f"{arrow} **{ticker}** ${price:.2f}  **{primary_action}**  {icon}{primary_pat}@{primary_pct:.0f}% ({primary_tf})  _{pos}_"]
    if primary_action in ('BUY', 'SELL'):
        lines.append(f"   Entry ${entry:.2f} → Target ${target:.2f} | Stop ${stop:.2f}")

    # Each TF
    for tf in ['2h', '1h', '30m', '5m']:
        r = tf_results.get(tf)
        if not r:
            continue
        pat, pct, act = r['pattern'], r['pct'], r['action']
        a2 = {'BUY': '🟢', 'SELL': '🔴', 'HOLD': '🟡', 'WAIT': '⚪'}[act]
        i2 = {'M': '⬇️', 'W': '⬆️'}.get(pat, '➡️')
        rng = ""
        if r['floor'] and r['ceil']:
            rng = f" ${r['floor']:.0f}–${r['ceil']:.0f}"
        lines.append(f"   {tf:>3}: {a2} {act:<4} {i2}{pat}@{pct:.0f}%{rng}")

    # Save
    state = {
        'ticker': ticker, 'price': price, 'primary_action': primary_action,
        'primary_tf': primary_tf, 'atr': round(atr, 2),
        'entry': entry, 'target': target, 'stop': stop,
        'timeframes': tf_results,
    }
    (STORAGE / f"mw_1h_{ticker.lower()}.json").write_text(json.dumps(state, indent=2))

    return '\n'.join(lines)


if __name__ == '__main__':
    tickers = [t for t in sys.argv[1:] if t in TICKERS] or list(TICKERS.keys())
    for t in tickers:
        r = scan_ticker(t)
        if r:
            print(r)
            print()