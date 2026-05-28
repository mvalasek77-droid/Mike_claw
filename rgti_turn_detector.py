#!/usr/bin/env python3
"""
RGTI Trend Line Turn Detector
================================
Catches REVERSALS using trend line breaks + momentum divergence + RSI exhaustion.

Strategy from 2-day backstudy:
  TREND LINE BREAKS catch actual turns:
    - Downtrend line break (resistance) → BUY signal (7 pts each)
    - Uptrend line break (support) → SELL signal (7 pts each)

  MOMENTUM DIVERGENCE confirms:
    - Price makes new low but RSI/CMO doesn't → bullish divergence (5 pts)
    - Price makes new high but RSI/CMO doesn't → bearish divergence (5 pts)

  RSI EXHAUSTION confirms:
    - RSI < 20 → oversold (3-5 pts) / RSI > 80 → overbought (3-5 pts)

  SCORING: 7+ = alert-worthy turn, 15+ = high conviction

Usage: python3 rgti_turn_detector.py
Cron: Hermes cron picks up stdout and delivers to Telegram
      Exit 0 = deliver, Exit 1 = suppress (no signal)
"""
import yfinance as yf
import pandas as pd
import numpy as np
import sys
import json
from datetime import datetime
from pathlib import Path

LAST_SIGNAL = Path(__file__).parent / "storage" / "last_rgti_turn_signal.json"


def get_data():
    """Fetch 2 days of 5m bars for trend line + indicator calculation.
    Filters out pre-market bars (before 9:30) to avoid phantom pivots.
    """
    t = yf.Ticker('RGTI')
    h = t.history(period='2d', interval='5m')
    if h.empty:
        return None
    # Filter pre-market bars — only regular trading hours
    h = h.between_time('09:30', '16:00')
    return h


def calc_rsi(series, period=14):
    delta = series.diff()
    gain = delta.clip(lower=0)
    loss = -delta.clip(upper=0)
    avg_gain = gain.rolling(period, min_periods=period).mean()
    avg_loss = loss.rolling(period, min_periods=period).mean()
    rs = avg_gain / avg_loss.replace(0, np.inf)
    return 100 - (100 / (1 + rs))


def calc_cmo(series, period=14):
    """Chande Momentum Oscillator — better at divergence than RSI."""
    diff = series.diff()
    up = diff.clip(lower=0).rolling(period).sum()
    dn = (-diff.clip(upper=0)).rolling(period).sum()
    denom = up + dn
    denom = denom.replace(0, np.inf)
    return 100 * (up - dn) / denom


def find_pivots(high, low, left=5, right=5):
    """Find swing highs and lows (wick pivots).
    
    left=5, right=5 means a pivot needs 5 bars (25min on 5m) on each side.
    This filters out micro-pivots that create unreliable short trend lines.
    """
    pivots_high = []
    pivots_low = []
    n = len(high)

    for i in range(left, n - right):
        window_high = max(high.iloc[i - left:i].max(), high.iloc[i + 1:i + right + 1].max())
        if high.iloc[i] > window_high:
            pivots_high.append((high.index[i], high.iloc[i]))

        window_low = min(low.iloc[i - left:i].min(), low.iloc[i + 1:i + right + 1].min())
        if low.iloc[i] < window_low:
            pivots_low.append((low.index[i], low.iloc[i]))

    return pivots_high, pivots_low


def build_trend_lines(pivots, kind='support', max_age_minutes=90, min_duration_minutes=30):
    """Build trend lines from consecutive pivot points.
    
    max_age_minutes: Don't use pivots older than this for building lines.
    min_duration_minutes: Lines must span at least this many minutes to be valid.
    Prevents short noisy lines from a single pivot wiggle.
    """
    lines = []
    if len(pivots) < 2:
        return lines

    # Filter pivots by age — only use recent ones
    if len(pivots) > 0:
        newest = pivots[-1][0]
        cutoff = newest - pd.Timedelta(minutes=max_age_minutes)
        recent_pivots = [(t, p) for t, p in pivots if t >= cutoff]
    else:
        recent_pivots = list(pivots)
    
    if len(recent_pivots) < 2:
        return lines

    for i in range(len(recent_pivots) - 1):
        t1, p1 = recent_pivots[i]
        t2, p2 = recent_pivots[i + 1]
        td = (t2 - t1).total_seconds() / 60
        if td < min_duration_minutes:  # Was 5, now 30
            continue
        slope = (p2 - p1) / td
        if abs(slope) < 1e-6:
            continue
        lines.append({'t1': t1, 'p1': p1, 't2': t2, 'p2': p2, 'slope': slope, 'kind': kind})

    return lines


def project_line_to_now(line, current_time, max_project_minutes=60):
    """Project a trend line to the current time.
    
    max_project_minutes: Cap how far we project beyond the line's second anchor.
    60min allows for RGTI's 1-2hr wave structure. Lines older than 60m past
    their last anchor are too stale for real-time signals.
    Returns None if line is too stale to project.
    """
    # Don't project beyond max_project_minutes past the line's last anchor
    line_end_time = line['t2']
    minutes_past_end = (current_time - line_end_time).total_seconds() / 60
    if minutes_past_end > max_project_minutes:
        return None  # Line is too old to be useful
    
    td = (current_time - line['t1']).total_seconds() / 60
    if td <= 0:
        return line['p1']
    projected = line['p1'] + line['slope'] * td
    # Sanity: projected price must be positive
    if projected <= 0:
        return None
    return projected


def check_trend_lines(df, pivots_high, pivots_low, current_price, current_time):
    """Check for trend line breaks — the #1 reversal signal.
    
    Key fixes:
    - Lines that project too far return None (skipped)
    - Distance must be 0.3% to 5% (beyond 5% = stale/phantom signal)
    """
    buy_signals = []
    sell_signals = []

    # DOWNTREND LINES (from swing highs) → break above = BUY
    resistance_lines = build_trend_lines(pivots_high, kind='resistance')
    for line in resistance_lines[-4:]:
        projected = project_line_to_now(line, current_time)
        if projected is None:
            continue
        dist_pct = ((current_price - projected) / projected) * 100

        # Cap distance: 0.3% to 5% — beyond that it's a stale line, not a fresh break
        if current_price > projected and 0.3 < dist_pct < 5:
            pts = 7 if dist_pct < 2 else 5
            buy_signals.append((
                f"📉 Downtrend TL break: {line['p1']:.2f}→{line['p2']:.2f}, "
                f"line at {projected:.2f}, price {current_price:.2f} (+{dist_pct:.1f}%)",
                pts
            ))
        elif current_price < projected and abs(dist_pct) < 1.5:
            sell_signals.append((
                f"🚧 Resistance TL {projected:.2f} ({line['p1']:.2f}→{line['p2']:.2f})",
                3
            ))

    # UPTREND LINES (from swing lows) → break below = SELL
    support_lines = build_trend_lines(pivots_low, kind='support')
    for line in support_lines[-4:]:
        projected = project_line_to_now(line, current_time)
        if projected is None:
            continue
        dist_pct = ((current_price - projected) / projected) * 100

        # Cap distance: -0.3% to -5% — beyond that it's a stale line
        if current_price < projected and -5 < dist_pct < -0.3:
            pts = 7 if abs(dist_pct) < 2 else 5
            sell_signals.append((
                f"📈 Uptrend TL break: {line['p1']:.2f}→{line['p2']:.2f}, "
                f"line at {projected:.2f}, price {current_price:.2f} ({dist_pct:.1f}%)",
                pts
            ))
        elif current_price > projected and abs(dist_pct) < 1.5:
            buy_signals.append((
                f"📐 Support TL {projected:.2f} ({line['p1']:.2f}→{line['p2']:.2f})",
                5
            ))

    return buy_signals, sell_signals


def check_divergence(df, current_price):
    """Momentum divergence — price makes new extreme but RSI/CMO doesn't."""
    buy_signals = []
    sell_signals = []
    n = len(df)
    if n < 30:
        return buy_signals, sell_signals

    close = df['Close']
    rsi = calc_rsi(close, 5)
    cmo = calc_cmo(close, 14)
    recent = 26

    price_recent = close.iloc[-recent:]
    price_prev = close.iloc[-2*recent:-recent] if n >= 2*recent else close.iloc[:recent]
    rsi_recent_val = rsi.iloc[-recent:]
    rsi_prev_val = rsi.iloc[-2*recent:-recent] if n >= 2*recent else rsi.iloc[:recent]

    if len(price_prev) > 0 and len(price_recent) > 0:
        # Bullish divergence
        if price_recent.min() < price_prev.min() and rsi_recent_val.min() > rsi_prev_val.min() + 5:
            buy_signals.append((
                f"🐂 Bullish div: price {price_recent.min():.2f}<{price_prev.min():.2f} "
                f"RSI {rsi_recent_val.min():.0f}>{rsi_prev_val.min():.0f}",
                5
            ))
        cmo_recent = cmo.iloc[-recent:]
        cmo_prev = cmo.iloc[-2*recent:-recent] if n >= 2*recent else cmo.iloc[:recent]
        if price_recent.min() < price_prev.min() and cmo_recent.min() > cmo_prev.min() + 10:
            buy_signals.append((
                f"🐂 CMO div: CMO {cmo_recent.min():.0f}>{cmo_prev.min():.0f}",
                4
            ))
        # Bearish divergence
        if price_recent.max() > price_prev.max() and rsi_recent_val.max() < rsi_prev_val.max() - 5:
            sell_signals.append((
                f"🐻 Bearish div: price {price_recent.max():.2f}>{price_prev.max():.2f} "
                f"RSI {rsi_recent_val.max():.0f}<{rsi_prev_val.max():.0f}",
                5
            ))

    return buy_signals, sell_signals


def check_rsi_exhaustion(df):
    """RSI at extremes = reversal likely."""
    buy_signals = []
    sell_signals = []
    rsi5 = calc_rsi(df['Close'], 5).iloc[-1]
    rsi14 = calc_rsi(df['Close'], 14).iloc[-1]

    if rsi5 < 15:
        buy_signals.append((f"📉 RSI5={rsi5:.0f} deeply oversold", 4))
    elif rsi5 < 25:
        buy_signals.append((f"📉 RSI5={rsi5:.0f} oversold", 3))
    elif rsi5 > 85:
        sell_signals.append((f"📈 RSI5={rsi5:.0f} deeply overbought", 4))
    elif rsi5 > 75:
        sell_signals.append((f"📈 RSI5={rsi5:.0f} overbought", 3))

    if rsi14 < 20:
        buy_signals.append((f"📉 RSI14={rsi14:.0f} extremely oversold", 5))
    elif rsi14 < 30:
        buy_signals.append((f"📉 RSI14={rsi14:.0f} oversold", 3))
    elif rsi14 > 80:
        sell_signals.append((f"📈 RSI14={rsi14:.0f} extremely overbought", 5))
    elif rsi14 > 70:
        sell_signals.append((f"📈 RSI14={rsi14:.0f} overbought", 3))

    return buy_signals, sell_signals


def count_wave(closes):
    """Count the wave pattern: consecutive up/down bars from the end.
    
    Returns dict with:
      - sequences: list of (direction, count) from most recent backward
      - current_wave: '1↓' / '2↑' / '1↑' / '2↓' etc. — where we are NOW
      - wave_signal: 'BUY' (1 down in uptrend), 'SELL' (2 up in uptrend), etc.
      - net_bias: +N bullish, -N bearish based on wave position
    
    Logic (same as oil binary_signal):
      UPTREND:  1↓ = BUY the pullback, 2↑ = SELL (take profit)
      DOWNTREND: 1↑ = SELL into strength, 2↓ = COVER or wait
    """
    if len(closes) < 3:
        return None
    
    # Build sequences of consecutive direction
    sequences = []
    cur_dir = None
    cur_count = 0
    for i in range(1, len(closes)):
        up = float(closes.iloc[i]) > float(closes.iloc[i-1])
        d = 'UP' if up else 'DN'
        if d == cur_dir:
            cur_count += 1
        else:
            if cur_dir is not None:
                sequences.append((cur_dir, cur_count))
            cur_dir = d
            cur_count = 1
    if cur_dir is not None:
        sequences.append((cur_dir, cur_count))
    
    if not sequences:
        return None
    
    # Determine overall trend from EMA alignment + recent waves
    ema5 = float(closes.ewm(span=5).mean().iloc[-1])
    ema9 = float(closes.ewm(span=9).mean().iloc[-1])
    ema21 = float(closes.ewm(span=21).mean().iloc[-1]) if len(closes) > 21 else ema9
    
    if ema5 > ema9 > ema21:
        trend = 'UP'
    elif ema5 < ema9 < ema21:
        trend = 'DOWN'
    elif ema5 > ema9:
        trend = 'UP'  # mild
    elif ema5 < ema9:
        trend = 'DOWN'  # mild
    else:
        trend = 'SIDEWAYS'
    
    # Where are we in the wave?
    recent = sequences[-1]  # (direction, count)
    prev = sequences[-2] if len(sequences) >= 2 else ('FLAT', 0)
    
    if trend == 'UP':
        if recent[0] == 'DN':
            current_wave = f"{recent[1]}↓"
            # 1 down in uptrend = BUY the pullback
            wave_signal = 'BUY'
            net_bias = 2 if recent[1] == 1 else 1  # 1 down stronger than multi-down
        else:
            current_wave = f"{recent[1]}↑"
            # 2+ up in uptrend = overstretched, SELL
            wave_signal = 'SELL' if recent[1] >= 2 else 'HOLD'
            net_bias = -1 if recent[1] >= 2 else 0
    elif trend == 'DOWN':
        if recent[0] == 'UP':
            current_wave = f"{recent[1]}↑"
            # 1 up bounce in downtrend = SELL into strength
            wave_signal = 'SELL'
            net_bias = -2 if recent[1] == 1 else -1
        else:
            current_wave = f"{recent[1]}↓"
            # Multi-down in downtrend: 1↓ continuation, 2+↓ watch for capitulation
            if recent[1] >= 3:
                wave_signal = 'BUY'  # capitulation bounce possible
                net_bias = 1
            else:
                wave_signal = 'SELL'  # continuation
                net_bias = -1
    else:  # SIDEWAYS
        current_wave = f"{recent[1]}{'↑' if recent[0]=='UP' else '↓'}"
        wave_signal = 'HOLD'
        net_bias = 0
    
    # Previous wave context (was it 1-down before this 2-up, etc.)
    wave_context = ""
    if len(sequences) >= 2:
        wave_context = f"{prev[1]}{'↑' if prev[0]=='UP' else '↓'}→{current_wave}"
    else:
        wave_context = current_wave
    
    return {
        'sequences': sequences[-4:],  # last 4 waves
        'trend': trend,
        'current_wave': current_wave,
        'wave_signal': wave_signal,
        'wave_context': wave_context,
        'net_bias': net_bias,
        'ema5': round(ema5, 2),
        'ema9': round(ema9, 2),
        'ema21': round(ema21, 2),
    }


def analyze_multi_timeframe(current_price):
    """Analyze 1-month, 1-week, and 1-day timeframes for wave position + RSI + trend lines.
    
    Wave counting across TFs:
      - Monthly (daily bars): Are we 1↓ or 2↑ in the big picture?
      - Weekly (weekly bars): Are we 1↑ bounce or 2↓ continuation?
      - Daily (5m bars): Where exactly in the intraday wave?
    
    Returns combined wave position + RSI + TL context.
    """
    t = yf.Ticker('RGTI')
    
    results = {}
    
    # ============ MONTHLY (1mo daily bars) ============
    h_1m = t.history(period='1mo', interval='1d')
    if h_1m is not None and len(h_1m) >= 10:
        c1m = h_1m['Close'].astype(float)
        hi1m = h_1m['High'].astype(float)
        lo1m = h_1m['Low'].astype(float)
        
        wave_m = count_wave(c1m)
        
        # RSI(14) on daily
        delta = c1m.diff()
        gain = delta.clip(lower=0).rolling(14).mean()
        loss_s = (-delta.clip(upper=0)).rolling(14).mean()
        rs = gain / loss_s.replace(0, np.inf)
        rsi14_m = float((100 - (100 / (1 + rs))).iloc[-1])
        rsi5_m = float((100 - (100 / (1 + (delta.clip(lower=0).rolling(5).mean()) / (-delta.clip(upper=0)).rolling(5).mean().replace(0, np.inf)))).iloc[-1])
        
        # Range
        m_hi = float(hi1m.max())
        m_lo = float(lo1m.min())
        m_range = m_hi - m_lo
        range_pct = (current_price - m_lo) / m_range * 100 if m_range > 0 else 50
        
        # Monthly trend lines from swing pivots
        left, right = 2, 2
        pivot_highs = []
        pivot_lows = []
        for i in range(left, len(hi1m) - right):
            w_hi = max(hi1m.iloc[i-left:i].max(), hi1m.iloc[i+1:i+right+1].max())
            if hi1m.iloc[i] > w_hi:
                pivot_highs.append((h_1m.index[i], float(hi1m.iloc[i])))
            w_lo = min(lo1m.iloc[i-left:i].min(), lo1m.iloc[i+1:i+right+1].min())
            if lo1m.iloc[i] < w_lo:
                pivot_lows.append((h_1m.index[i], float(lo1m.iloc[i])))
        
        now = h_1m.index[-1]
        support_level = None
        resistance_level = None
        
        for i in range(len(pivot_highs) - 1):
            t1, p1 = pivot_highs[i]; t2, p2 = pivot_highs[i + 1]
            td = (t2 - t1).total_seconds() / 86400
            if td < 1: continue
            projected = p1 + (p2 - p1) / td * (now - t1).total_seconds() / 86400
            if projected <= 0: continue
            dist = ((current_price - projected) / projected) * 100
            if dist > 1: continue  # broken
            if resistance_level is None or projected < resistance_level:
                resistance_level = round(projected, 2)
        
        for i in range(len(pivot_lows) - 1):
            t1, p1 = pivot_lows[i]; t2, p2 = pivot_lows[i + 1]
            td = (t2 - t1).total_seconds() / 86400
            if td < 1: continue
            projected = p1 + (p2 - p1) / td * (now - t1).total_seconds() / 86400
            if projected <= 0: continue
            dist = ((current_price - projected) / projected) * 100
            if dist < -1: continue  # broken
            if support_level is None or projected > support_level:
                support_level = round(projected, 2)
        
        wk5_chg = round((current_price - float(c1m.iloc[-5])) / float(c1m.iloc[-5]) * 100, 1) if len(c1m) >= 5 else 0
        
        results['monthly'] = {
            'wave': wave_m,
            'rsi5': round(rsi5_m, 0), 'rsi14': round(rsi14_m, 1),
            'range_pct': round(range_pct, 0),
            'range': f"${m_lo:.2f}→${m_hi:.2f}",
            'm_25': round(m_lo + m_range * 0.25, 2),
            'm_50': round(m_lo + m_range * 0.50, 2),
            'm_75': round(m_lo + m_range * 0.75, 2),
            'support': support_level, 'resistance': resistance_level,
            'wk5_chg': wk5_chg,
        }
    
    # ============ WEEKLY (3mo weekly bars) ============
    h_1w = t.history(period='3mo', interval='1wk')
    if h_1w is not None and len(h_1w) >= 6:
        c1w = h_1w['Close'].astype(float)
        wave_w = count_wave(c1w)
        
        delta = c1w.diff()
        gain = delta.clip(lower=0).rolling(14).mean()
        loss_s = (-delta.clip(upper=0)).rolling(14).mean()
        rs = gain / loss_s.replace(0, np.inf)
        rsi14_w = float((100 - (100 / (1 + rs))).iloc[-1]) if len(c1w) >= 15 else 50
        
        results['weekly'] = {
            'wave': wave_w,
            'rsi14': round(rsi14_w, 1),
        }
    
    # ============ DAILY (5m bars, intraday wave) ============
    h_5m = t.history(period='2d', interval='5m')
    if h_5m is not None and len(h_5m) >= 30:
        h_5m = h_5m.between_time('09:30', '16:00')
        c5m = h_5m['Close'].astype(float)
        wave_d = count_wave(c5m)
        
        delta = c5m.diff()
        gain = delta.clip(lower=0).rolling(14).mean()
        loss_s = (-delta.clip(upper=0)).rolling(14).mean()
        rs = gain / loss_s.replace(0, np.inf)
        rsi14_d = float((100 - (100 / (1 + rs))).iloc[-1]) if len(c5m) >= 15 else 50
        rsi5_d = float((100 - (100 / (1 + (delta.clip(lower=0).rolling(5).mean()) / (-delta.clip(upper=0)).rolling(5).mean().replace(0, np.inf)))).iloc[-1])
        
        results['daily'] = {
            'wave': wave_d,
            'rsi5': round(rsi5_d, 0), 'rsi14': round(rsi14_d, 1),
        }
    
    # ============ MULTI-TF CONFLUENCE ============
    # Combine wave positions across timeframes
    buy_pts = 0
    sell_pts = 0
    confluence_lines = []
    
    for tf_name, tf_key in [('1mo', 'monthly'), ('1wk', 'weekly'), ('1d', 'daily')]:
        tf = results.get(tf_key)
        if not tf or not tf.get('wave'):
            continue
        w = tf['wave']
        weight = {'1mo': 3, '1wk': 2, '1d': 1}[tf_name]
        
        if w['wave_signal'] == 'BUY':
            buy_pts += weight * abs(w['net_bias'])
            confluence_lines.append(f"  {tf_name}: {w['wave_context']} {w['trend']} → BUY {w['wave_signal']} (×{weight})")
        elif w['wave_signal'] == 'SELL':
            sell_pts += weight * abs(w['net_bias'])
            confluence_lines.append(f"  {tf_name}: {w['wave_context']} {w['trend']} → SELL {w['wave_signal']} (×{weight})")
        else:
            confluence_lines.append(f"  {tf_name}: {w['wave_context']} {w['trend']} → HOLD")
    
    if buy_pts > sell_pts:
        mtf_signal = 'BUY'
    elif sell_pts > buy_pts:
        mtf_signal = 'SELL'
    else:
        mtf_signal = 'HOLD'
    
    results['confluence'] = {
        'mtf_signal': mtf_signal,
        'buy_pts': buy_pts,
        'sell_pts': sell_pts,
        'lines': confluence_lines,
    }
    
    return results


def detect_turns():
    """Main detection — TREND LINE FIRST architecture.
    
    Logic:
      1. Draw trend lines from proper pivots (left=5, right=5)
      2. Check for TL breaks (7-10pts) — these are THE signal
      3. RSI/divergence/MTF are CONFIRMATIONS only (capped at 3pts each)
      4. If no TL break, no signal — prevents RSI-only noise
      5. A TL break + at least 1 confirmation = HIGH CONVICTION
    """
    df = get_data()
    if df is None or df.empty:
        return None

    current_price = float(df['Close'].iloc[-1])
    current_time = df.index[-1]
    rsi5 = float(calc_rsi(df['Close'], 5).iloc[-1])
    rsi14 = float(calc_rsi(df['Close'], 14).iloc[-1])

    today = df.index[-1].date()
    today_mask = [d.date() == today for d in df.index]
    today_bars = df[today_mask]
    day_open = float(today_bars['Open'].iloc[0]) if len(today_bars) > 0 else float(df['Open'].iloc[0])
    day_chg = ((current_price - day_open) / day_open) * 100

    # === STEP 1: TREND LINES (primary signal) ===
    pivots_high, pivots_low = find_pivots(df['High'], df['Low'], left=5, right=5)
    buy_tl, sell_tl = check_trend_lines(df, pivots_high, pivots_low, current_price, current_time)
    
    # TL breaks are 7pts each — track them as the PRIMARY signal
    tl_buy_score = sum(pts for _, pts in buy_tl)
    tl_sell_score = sum(pts for _, pts in sell_tl)
    has_tl_buy = tl_buy_score > 0
    has_tl_sell = tl_sell_score > 0

    # === STEP 2: CONFIRMATIONS (secondary, capped low) ===
    buy_div, sell_div = check_divergence(df, current_price)
    buy_rsi, sell_rsi = check_rsi_exhaustion(df)

    # Cap confirmation signals at 3pts each — they SUPPORT the TL, not replace it
    buy_div = [(desc, min(pts, 3)) for desc, pts in buy_div]
    sell_div = [(desc, min(pts, 3)) for desc, pts in sell_div]
    buy_rsi = [(desc, min(pts, 3)) for desc, pts in buy_rsi]
    sell_rsi = [(desc, min(pts, 3)) for desc, pts in sell_rsi]

    # Multi-timeframe context — informational, but only adds confirmation pts if TL exists
    mtf = analyze_multi_timeframe(current_price)
    mtf_buy_pts = 0
    mtf_sell_pts = 0
    conf = mtf.get('confluence', {}) if mtf else {}
    if conf:
        mtf_signal = conf.get('mtf_signal', 'HOLD')
        mtf_buy = conf.get('buy_pts', 0)
        mtf_sell = conf.get('sell_pts', 0)
        # MTF only contributes if there's already a TL signal in same direction
        if has_tl_buy and mtf_signal == 'BUY' and mtf_buy > mtf_sell:
            mtf_pts = min(mtf_buy, 3)
            buy_rsi.append((f"📅 MTF confirms: BUY (1mo+1wk+1d={mtf_buy}:{mtf_sell})", mtf_pts))
            mtf_buy_pts = mtf_pts
        elif has_tl_sell and mtf_signal == 'SELL' and mtf_sell > mtf_buy:
            mtf_pts = min(mtf_sell, 3)
            sell_rsi.append((f"📅 MTF confirms: SELL (1mo+1wk+1d={mtf_sell}:{mtf_buy})", mtf_pts))
            mtf_sell_pts = mtf_pts
        # Counter-TL MTF → adds a WARNING (0 pts, just label)
        elif has_tl_buy and mtf_signal == 'SELL':
            buy_rsi.append(("⚠️ MTF disagrees: SELL — weaker signal", 0))
        elif has_tl_sell and mtf_signal == 'BUY':
            sell_rsi.append(("⚠️ MTF disagrees: BUY — weaker signal", 0))

    # === STEP 3: COMBINE WITH TL DOMINANCE ===
    all_buy = buy_tl + buy_div + buy_rsi
    all_sell = sell_tl + sell_div + sell_rsi
    buy_score = sum(pts for _, pts in all_buy)
    sell_score = sum(pts for _, pts in all_sell)

    # === STEP 4: SIGNAL LOGIC ===
    # No TL break → no signal, period. Confirmations alone don't generate alerts.
    # TL break alone (7pts) → SIGNAL
    # TL break + any confirmation (7+3=10+) → HIGH CONVICTION
    # TL break + MTF disagreement → still signals but flagged weaker
    
    if buy_score > sell_score and has_tl_buy:
        direction = '🟢'
    elif sell_score > buy_score and has_tl_sell:
        direction = '🔴'
    else:
        direction = '⚪'

    # Count confirmations (non-TL signals with pts > 0)
    buy_confirmations = sum(1 for desc, pts in all_buy if pts > 0 and not desc.startswith(('📉 D', '📈 U', '📐 S', '📉 D'))
                                ) if has_tl_buy else 0
    sell_confirmations = sum(1 for desc, pts in all_sell if pts > 0 and not desc.startswith(('📉 D', '📈 U', '📐 S', '📉 D'))
                                 ) if has_tl_sell else 0

    return {
        'price': current_price, 'rsi5': rsi5, 'rsi14': rsi14,
        'day_chg': day_chg, 'direction': direction,
        'buy_score': buy_score, 'sell_score': sell_score,
        'tl_buy_score': tl_buy_score, 'tl_sell_score': tl_sell_score,
        'buy_confirmations': buy_confirmations, 'sell_confirmations': sell_confirmations,
        'has_tl_buy': has_tl_buy, 'has_tl_sell': has_tl_sell,
        'buy_signals': all_buy, 'sell_signals': all_sell,
        'pivots_high_count': len(pivots_high),
        'pivots_low_count': len(pivots_low),
        'timestamp': current_time,
        'mtf': mtf,
    }


def format_alert(data):
    """Format for Telegram delivery — TL-first layout."""
    if data is None:
        return "❌ RGTI: No data"
    p = data['price']
    d = data['direction']
    chg = data['day_chg']
    rsi5 = data['rsi5']
    rsi14 = data['rsi14']
    buy = data['buy_score']
    sell = data['sell_score']
    has_tl_buy = data.get('has_tl_buy', False)
    has_tl_sell = data.get('has_tl_sell', False)
    tl_buy = data.get('tl_buy_score', 0)
    tl_sell = data.get('tl_sell_score', 0)
    buy_conf = data.get('buy_confirmations', 0)
    sell_conf = data.get('sell_confirmations', 0)

    lines = [f"RGTI ${p:.2f} {d} | Day {chg:+.1f}%"]
    lines.append(f"TL BUY={tl_buy} SELL={tl_sell} | Confirmations: {buy_conf}↑ {sell_conf}↓")
    lines.append(f"RSI5={rsi5:.0f} RSI14={rsi14:.0f}")

    # Multi-timeframe wave context
    mtf = data.get('mtf')
    if mtf:
        conf = mtf.get('confluence', {})
        m = mtf.get('monthly', {})
        w = mtf.get('weekly', {})
        d_tf = mtf.get('daily', {})
        
        # Wave position per timeframe
        if m and m.get('wave'):
            mw = m['wave']
            trend_icon = {'UP': '📈', 'DOWN': '📉', 'SIDEWAYS': '➡️'}[mw['trend']]
            lines.append(f"{trend_icon} 1mo: {mw['wave_context']} {mw['trend']} → {mw['wave_signal']} | RSI5={m.get('rsi5','-')} RSI14={m.get('rsi14','-')}")
            lines.append(f"📐 ${m.get('m_25','-')}→${m.get('m_50','-')}→${m.get('m_75','-')} ({m.get('range_pct','-')}%) | 5d {m.get('wk5_chg',0):+}%")
            if m.get('support'):
                lines.append(f"🟢 Support: ${m['support']}")
            if m.get('resistance'):
                lines.append(f"🔴 Resistance: ${m['resistance']}")
        if w and w.get('wave'):
            ww = w['wave']
            trend_icon = {'UP': '📈', 'DOWN': '📉', 'SIDEWAYS': '➡️'}[ww['trend']]
            lines.append(f"{trend_icon} 1wk: {ww['wave_context']} {ww['trend']} → {ww['wave_signal']} | RSI14={w.get('rsi14','-')}")
        if d_tf and d_tf.get('wave'):
            dw = d_tf['wave']
            trend_icon = {'UP': '📈', 'DOWN': '📉', 'SIDEWAYS': '➡️'}[dw['trend']]
            lines.append(f"{trend_icon} 1d: {dw['wave_context']} {dw['trend']} → {dw['wave_signal']} | RSI5={d_tf.get('rsi5','-')} RSI14={d_tf.get('rsi14','-')}")
        
        # Confluence
        if conf:
            mtf_emoji = {'BUY': '🟢', 'SELL': '🔴', 'HOLD': '⚪'}.get(conf.get('mtf_signal', 'HOLD'), '⚪')
            lines.append(f"{mtf_emoji} MTF: {conf.get('mtf_signal','?')} BUY={conf.get('buy_pts',0)} SELL={conf.get('sell_pts',0)}")

    # === TREND LINE SIGNALS (always show first) ===
    if data.get('buy_signals'):
        tl_buys = [(desc, pts) for desc, pts in data['buy_signals'] if pts >= 5]
        conf_buys = [(desc, pts) for desc, pts in data['buy_signals'] if 0 < pts < 5]
        warn_buys = [(desc, pts) for desc, pts in data['buy_signals'] if pts == 0]
        if tl_buys:
            lines.append("📏 TL BUY signals:")
            for desc, pts in tl_buys:
                lines.append(f"  • {desc} [{pts}pts]")
        if conf_buys:
            lines.append("✅ Confirmations:")
            for desc, pts in conf_buys:
                lines.append(f"  • {desc} [{pts}pts]")
        if warn_buys:
            for desc, pts in warn_buys:
                lines.append(f"  {desc}")

    if data.get('sell_signals'):
        tl_sells = [(desc, pts) for desc, pts in data['sell_signals'] if pts >= 5]
        conf_sells = [(desc, pts) for desc, pts in data['sell_signals'] if 0 < pts < 5]
        warn_sells = [(desc, pts) for desc, pts in data['sell_signals'] if pts == 0]
        if tl_sells:
            lines.append("📏 TL SELL signals:")
            for desc, pts in tl_sells:
                lines.append(f"  • {desc} [{pts}pts]")
        if conf_sells:
            lines.append("✅ Confirmations:")
            for desc, pts in conf_sells:
                lines.append(f"  • {desc} [{pts}pts]")
        if warn_sells:
            for desc, pts in warn_sells:
                lines.append(f"  {desc}")

    # === CONVICTION LEVELS ===
    if has_tl_buy and buy_conf >= 2:
        lines.append("🟢🟢 HIGH CONVICTION BUY — TL break + multi-confirmation")
    elif has_tl_buy and buy_conf >= 1:
        lines.append("🟢 TL BUY — 1 confirmation")
    elif has_tl_buy:
        lines.append("🟢 TL break — watch for confirmation entry")
    elif has_tl_sell and sell_conf >= 2:
        lines.append("🔴🔴 HIGH CONVICTION SELL — TL break + multi-confirmation")
    elif has_tl_sell and sell_conf >= 1:
        lines.append("🔴 TL SELL — 1 confirmation")
    elif has_tl_sell:
        lines.append("🔴 TL break — watch for confirmation exit")
    else:
        lines.append("⚪ No trend line break — no signal")

    return '\n'.join(lines)


if __name__ == '__main__':
    data = detect_turns()
    if data is None:
        print("❌ RGTI: Could not fetch data")
        sys.exit(1)
    msg = format_alert(data)
    print(msg)
    buy = data['buy_score']
    sell = data['sell_score']
    has_tl_buy = data.get('has_tl_buy', False)
    has_tl_sell = data.get('has_tl_sell', False)
    
    # Only alert on TL breaks, not RSI-only noise
    if has_tl_buy or has_tl_sell:
        # Signal-change cooldown: only alert if different from last signal
        should_alert = True
        try:
            if LAST_SIGNAL.exists():
                last = json.loads(LAST_SIGNAL.read_text())
                last_dir = last.get('direction', '')
                last_buy = last.get('buy_score', 0)
                last_sell = last.get('sell_score', 0)
                last_tl_buy = last.get('has_tl_buy', False)
                last_tl_sell = last.get('has_tl_sell', False)
                cur_dir = 'BUY' if buy > sell else 'SELL'
                # Same direction, same TL type, similar score = duplicate
                if last_dir == cur_dir and last_tl_buy == has_tl_buy and last_tl_sell == has_tl_sell and abs(last_buy - buy) <= 3 and abs(last_sell - sell) <= 3:
                    should_alert = False
                    print(f"[COOLDOWN — same TL signal as last]")
        except:
            pass
        if should_alert:
            # Save current signal state
            LAST_SIGNAL.parent.mkdir(parents=True, exist_ok=True)
            LAST_SIGNAL.write_text(json.dumps({
                'direction': 'BUY' if buy > sell else 'SELL',
                'buy_score': buy, 'sell_score': sell,
                'has_tl_buy': has_tl_buy, 'has_tl_sell': has_tl_sell,
                'ts': datetime.utcnow().isoformat()
            }))
        sys.exit(0 if should_alert else 1)
    else:
        sys.exit(1)
