#!/usr/bin/env python3
"""
RGTI Entry Alert — "When to get in"
=====================================
Fires ONLY when the monthly uptrend pullback shows intraday reversal.

Entry triggers (need 2+ of these):
  1. RSI8 < 30 (oversold on 5m)
  2. Hammer/bullish reversal candle at today's low
  3. Price reclaiming EMA5 (first step back up)
  4. Volume surge (1.5x+ avg) on an up-bar
  5. MACD bullish cross on 5m

Monthly context gate:
  - Only fires BUY if 1mo trend is UP (EMA5>9>21 or EMA5>9)
  - If 1mo is DOWN, suppresses and says "wait"

Cooldown: 15 minutes between alerts (avoids spam)
"""
import yfinance as yf
import pandas as pd
import numpy as np
import json
import sys
from datetime import datetime, timedelta
from pathlib import Path

LOG = Path(__file__).parent / "storage" / "rgti_entry_log.jsonl"
OUTCOME_LOG = Path(__file__).parent / "storage" / "rgti_entry_outcomes.jsonl"
LOG.parent.mkdir(parents=True, exist_ok=True)
COOLDOWN_MINUTES = 60  # Increased from 15 to 60 to reduce spam


def log_event(data):
    with open(LOG, "a") as f:
        f.write(json.dumps(data) + "\n")


def last_alert_time():
    """Return timestamp of last alert, or None."""
    try:
        with open(LOG, "r") as f:
            lines = f.readlines()
            if lines:
                last = json.loads(lines[-1].strip())
                return datetime.fromisoformat(last["ts"])
    except:
        pass
    return None


def can_alert(current_price=None):
    """Check cooldown AND price-level — don't re-alert at higher prices."""
    last = last_alert_time()
    if last is None:
        return True
    elapsed = (datetime.utcnow() - last).total_seconds()
    if elapsed <= COOLDOWN_MINUTES * 60:
        return False
    # Price-level gate: if price is HIGHER than last entry, don't alert
    # (prevents buying near tops — only re-alert if price dropped 2%+ from last)
    if current_price is not None:
        try:
            with open(LOG, "r") as f:
                lines = f.readlines()
                if lines:
                    last_entry = json.loads(lines[-1].strip())
                    last_price = last_entry.get("price", 0)
                    if last_price > 0 and current_price >= last_price:
                        return False  # Don't re-alert at same or higher price
                    if last_price > 0 and (current_price / last_price) > 0.98:
                        return False  # Less than 2% dip from last entry, skip
        except:
            pass
    return True


def calc_rsi(series, period=8):
    delta = series.diff()
    gain = delta.clip(lower=0).rolling(period).mean()
    loss = (-delta.clip(upper=0)).rolling(period).mean()
    rs = gain / loss.replace(0, np.inf)
    return 100 - (100 / (1 + rs))


def count_wave_daily(closes):
    """Quick wave count on daily bars (1mo)."""
    if len(closes) < 5:
        return 'SIDEWAYS', '?', 0
    ema5 = float(closes.ewm(span=5).mean().iloc[-1])
    ema9 = float(closes.ewm(span=9).mean().iloc[-1])
    ema21 = float(closes.ewm(span=21).mean().iloc[-1]) if len(closes) > 21 else ema9

    # Count last wave
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

    if ema5 > ema9 > ema21:
        trend = 'UP'
    elif ema5 > ema9:
        trend = 'UP'
    elif ema5 < ema9 < ema21:
        trend = 'DOWN'
    elif ema5 < ema9:
        trend = 'DOWN'
    else:
        trend = 'SIDEWAYS'

    if not sequences:
        return trend, '?', 0

    recent = sequences[-1]
    prev = sequences[-2] if len(sequences) >= 2 else ('FLAT', 0)

    wave_label = f"{prev[1]}{'↑' if prev[0]=='UP' else '↓'}→{recent[1]}{'↑' if recent[0]=='UP' else '↓'}"

    if trend == 'UP':
        if recent[0] == 'DN':
            bias = 2  # BUY the pullback
        else:
            bias = -1 if recent[1] >= 2 else 0  # overstretched or just 1 up
    elif trend == 'DOWN':
        if recent[0] == 'UP':
            bias = -2  # SELL the bounce
        else:
            bias = -1 if recent[1] < 3 else 1
    else:
        bias = 0

    return trend, wave_label, bias


def scan():
    t = yf.Ticker('RGTI')

    # Monthly context
    h_1m = t.history(period='1mo', interval='1d')
    if h_1m is None or len(h_1m) < 10:
        print("No monthly data")
        return None

    c1m = h_1m['Close'].astype(float)
    m_trend, m_wave, m_bias = count_wave_daily(c1m)

    m_hi = float(h_1m['High'].astype(float).max())
    m_lo = float(h_1m['Low'].astype(float).min())
    m_range = m_hi - m_lo
    range_pct = (float(c1m.iloc[-1]) - m_lo) / m_range * 100 if m_range > 0 else 50

    # Weekly context
    h_1w = t.history(period='3mo', interval='1wk')
    w_trend, w_wave, w_bias = 'SIDEWAYS', '?', 0
    if h_1w is not None and len(h_1w) >= 6:
        c1w = h_1w['Close'].astype(float)
        w_trend, w_wave, w_bias = count_wave_daily(c1w)

    # Intraday
    h_5m = t.history(period='2d', interval='5m')
    if h_5m is None or len(h_5m) < 30:
        print("No 5m data")
        return None
    h_5m = h_5m.between_time('09:30', '16:00')

    c = h_5m['Close'].astype(float)
    hi = h_5m['High'].astype(float)
    lo = h_5m['Low'].astype(float)
    v = h_5m['Volume'].astype(float)
    o = h_5m['Open'].astype(float)

    cur = float(c.iloc[-1])
    cur_time = h_5m.index[-1]

    # Today's bars only
    today = h_5m.index[-1].date()
    today_mask = h_5m.index.date == today
    today_bars = h_5m[today_mask]
    day_open = float(today_bars['Open'].iloc[0]) if len(today_bars) > 0 else cur
    day_hi = float(today_bars['High'].max()) if len(today_bars) > 0 else cur
    day_lo = float(today_bars['Low'].min()) if len(today_bars) > 0 else cur
    day_chg = ((cur - day_open) / day_open) * 100

    # Indicators
    ema5 = float(c.ewm(span=5).mean().iloc[-1])
    ema13 = float(c.ewm(span=13).mean().iloc[-1])
    ema21 = float(c.ewm(span=21).mean().iloc[-1])

    typical = (hi + lo + c) / 3
    vol_s = v
    vwap = float((typical * vol_s).cumsum().iloc[-1] / vol_s.cumsum().iloc[-1])

    rsi8 = float(calc_rsi(c, 8).iloc[-1])

    # MACD
    macd = c.ewm(span=12).mean() - c.ewm(span=26).mean()
    sig = macd.ewm(span=9).mean()
    macd_hist = float((macd - sig).iloc[-1])
    macd_prev = float((macd - sig).iloc[-2]) if len(c) > 1 else 0
    macd_cross = "bullish" if macd_hist > 0 and macd_prev <= 0 else "bearish" if macd_hist < 0 and macd_prev >= 0 else "none"

    # Volume
    avg_vol = float(v[:-6].mean()) if len(v) > 6 else 1
    recent_vol_ratio = float(v.tail(6).mean()) / avg_vol if avg_vol > 0 else 1

    # Buy/sell volume last 20 bars
    n = min(20, len(c) - 1)
    buy_vol = sum(float(v.iloc[i]) for i in range(-n, 0) if float(c.iloc[i]) > float(c.iloc[i-1]))
    sell_vol = sum(float(v.iloc[i]) for i in range(-n, 0) if float(c.iloc[i]) < float(c.iloc[i-1]))
    bs_ratio = buy_vol / sell_vol if sell_vol > 0 else 99

    # Last candle pattern
    last_o = float(o.iloc[-1])
    last_c = cur
    last_h = float(hi.iloc[-1])
    last_l = float(lo.iloc[-1])
    body = last_c - last_o
    rng = last_h - last_l if last_h - last_l > 0 else 0.01
    wick_dn = min(last_o, last_c) - last_l
    wick_up = last_h - max(last_o, last_c)
    is_hammer = body > 0 and wick_dn > abs(body) * 1.5
    is_bull_engulf = body > 0 and last_o < float(c.iloc[-2]) and last_c > float(o.iloc[-2]) if len(c) > 1 else False

    # ATR 5m
    atr = float((hi - lo).rolling(14).mean().iloc[-1]) if len(hi) > 14 else 0.5

    # ============ ENTRY SCORING ============
    entry_signals = []
    entry_score = 0

    # 1. RSI oversold
    if rsi8 < 20:
        entry_signals.append(f"RSI8={rsi8:.0f} deeply oversold")
        entry_score += 3
    elif rsi8 < 30:
        entry_signals.append(f"RSI8={rsi8:.0f} oversold")
        entry_score += 2
    elif rsi8 < 40:
        entry_signals.append(f"RSI8={rsi8:.0f} low")
        entry_score += 1

    # 2. Hammer/reversal candle at today's low
    if is_hammer and cur <= day_lo * 1.005:
        entry_signals.append(f"Hammer at day low ${day_lo:.2f}")
        entry_score += 3
    elif is_hammer:
        entry_signals.append(f"Hammer candle")
        entry_score += 2
    if is_bull_engulf:
        entry_signals.append("Bullish engulfing")
        entry_score += 2

    # 3. Price reclaiming EMA5 (key reversal signal)
    if cur > ema5 and float(c.iloc[-2]) < float(c.ewm(span=5).mean().iloc[-2]):
        entry_signals.append(f"Reclaimed EMA5 ${ema5:.2f}")
        entry_score += 3
    elif cur > ema5:
        entry_signals.append(f"Above EMA5 ${ema5:.2f}")
        entry_score += 1

    # 4. Volume surge on up-bar
    last_bar_up = cur > last_o
    if recent_vol_ratio >= 2.0 and last_bar_up:
        entry_signals.append(f"Vol {recent_vol_ratio:.1f}x on up-bar")
        entry_score += 3
    elif recent_vol_ratio >= 1.5 and last_bar_up:
        entry_signals.append(f"Vol {recent_vol_ratio:.1f}x on up-bar")
        entry_score += 2

    # 5. MACD bullish cross
    if macd_cross == "bullish":
        entry_signals.append("MACD bullish cross")
        entry_score += 2

    # 6. Price bouncing off day's low (within 0.5%)
    if cur <= day_lo * 1.005 and cur >= day_lo:
        entry_signals.append(f"At day low ${day_lo:.2f}")
        entry_score += 1

    # 7. Price above VWAP (intraday buyers in control)
    if cur > vwap:
        entry_signals.append(f"Above VWAP ${vwap:.2f}")
        entry_score += 2

    # ============ GATE: Monthly trend ============
    monthly_gate = m_trend == 'UP'
    gate_reason = ""
    if not monthly_gate:
        if m_trend == 'DOWN':
            gate_reason = "Monthly trend is DOWN — wait for trend reversal before entry"
        else:
            gate_reason = "Monthly trend SIDEWAYS — no edge"

    # ============ DETERMINE ACTION ============
    # FIX 5: Require RSI8<40 for ENTRY (mandatory pullback signal)
    # Raise ENTRY threshold from 5 to 7 for quality
    rsi_pullback = rsi8 < 40
    if monthly_gate and entry_score >= 7 and rsi_pullback:
        action = "ENTRY"
        emoji = "🟢"
    elif monthly_gate and entry_score >= 7 and not rsi_pullback:
        action = "WATCH"  # Score high enough but no pullback — just watch
        emoji = "🟡"
    elif monthly_gate and entry_score >= 5:
        action = "WATCH"
        emoji = "🟡"
    elif not monthly_gate:
        action = "HOLD"
        emoji = "🔴"
    else:
        action = "WAIT"
        emoji = "⚪"

    # Stop/target
    stop = round(day_lo - atr * 0.5, 2)
    target1 = round(cur + atr * 2, 2)
    target2 = round(cur + atr * 3, 2)
    risk = abs(cur - stop)
    reward = abs(target2 - cur)
    rr = round(reward / risk, 1) if risk > 0 else 0

    result = {
        'price': cur, 'action': action, 'emoji': emoji,
        'entry_score': entry_score, 'entry_signals': entry_signals,
        'm_trend': m_trend, 'm_wave': m_wave, 'm_bias': m_bias,
        'w_trend': w_trend, 'w_wave': w_wave,
        'rsi8': round(rsi8, 1),
        'ema5': round(ema5, 2), 'ema13': round(ema13, 2),
        'vwap': round(vwap, 2),
        'macd_cross': macd_cross,
        'day_hi': day_hi, 'day_lo': day_lo,
        'day_chg': round(day_chg, 1),
        'bs_ratio': round(bs_ratio, 1),
        'vol_ratio': round(recent_vol_ratio, 1),
        'stop': stop, 'target1': target1, 'target2': target2,
        'rr': rr, 'atr': round(atr, 2),
        'range_pct': round(range_pct, 0),
        'monthly_gate': monthly_gate,
        'gate_reason': gate_reason,
        'timestamp': cur_time,
    }

    return result


def format_msg(r):
    """Format for Telegram."""
    if r is None:
        return "❌ RGTI: No data"

    lines = []

    # Header
    lines.append(f"{r['emoji']} **RGTI {r['action']}** @ ${r['price']:.2f} ({r['day_chg']:+.1f}%)")

    # Monthly context
    m_icon = {'UP': '📈', 'DOWN': '📉', 'SIDEWAYS': '➡️'}[r['m_trend']]
    lines.append(f"{m_icon} 1mo: {r['m_wave']} {r['m_trend']}")
    w_icon = {'UP': '📈', 'DOWN': '📉', 'SIDEWAYS': '➡️'}[r['w_trend']]
    lines.append(f"{w_icon} 1wk: {r['w_wave']} {r['w_trend']}")

    # Entry score
    lines.append(f"⚡ Entry score: {r['entry_score']}/15 (need 5+)")

    if r['entry_signals']:
        lines.append("Signals:")
        for s in r['entry_signals']:
            lines.append(f"  ✓ {s}")

    # Key levels
    lines.append(f"EMA5=${r['ema5']} VWAP=${r['vwap']} RSI8={r['rsi8']:.0f}")
    lines.append(f"Day H=${r['day_hi']:.2f} L=${r['day_lo']:.2f} | BS={r['bs_ratio']:.1f}:1 Vol={r['vol_ratio']:.1f}x")

    if r['action'] == 'ENTRY':
        lines.append(f"")
        lines.append(f"💵 **Entry: ${r['price']:.2f}**")
        lines.append(f"🛑 **Stop: ${r['stop']}** (ATR×0.5)")
        lines.append(f"🎯 **T1: ${r['target1']} | T2: ${r['target2']}** (R:R {r['rr']}:1)")
    elif r['action'] == 'WATCH':
        rsi_status = "RSI cooling off" if r['rsi8'] >= 40 else "RSI pulling back"
        lines.append(f"⏳ Getting close — {rsi_status}, need score≥7 + RSI<40 for ENTRY")
        lines.append(f"🛑 Would stop: ${r['stop']} | 🎯 T2: ${r['target2']}")
    elif r['action'] == 'HOLD':
        lines.append(f"🚫 {r['gate_reason']}")
    else:
        lines.append(f"⏳ No entry signals yet — RSI still neutral, no reversal candles")

    return '\n'.join(lines)


if __name__ == '__main__':
    r = scan()
    if r is None:
        print("❌ RGTI entry scan: no data")
        sys.exit(1)

    msg = format_msg(r)
    print(msg)

    # Exit 0 = deliver to Telegram (action is ENTRY or WATCH)
    # Exit 1 = suppress (no actionable signal)
    if r['action'] in ('ENTRY',):
        if can_alert(r['price']):
            log_event({"ts": datetime.utcnow().isoformat(), "action": r['action'], "price": r['price'], "score": r['entry_score']})
            # Log outcome tracking
            with open(OUTCOME_LOG, "a") as f:
                f.write(json.dumps({
                    "ts": datetime.utcnow().isoformat(), "sym": "RGTI", "action": "ENTRY",
                    "entry_price": r['price'], "stop": r['stop'], "target1": r['target1'],
                    "target2": r['target2'], "score": r['entry_score'],
                    "status": "pending", "pnl_30m": None, "pnl_60m": None
                }) + "\n")
            sys.exit(0)
        else:
            print(f"\n[COOLDOWN — {COOLDOWN_MINUTES}min or price not lower than last entry]")
            sys.exit(1)
    elif r['action'] == 'WATCH':
        # Only deliver WATCH every 60 min
        last = last_alert_time()
        if last is None or (datetime.utcnow() - last).total_seconds() > 60 * 60:
            log_event({"ts": datetime.utcnow().isoformat(), "action": r['action'], "price": r['price'], "score": r['entry_score']})
            sys.exit(0)
        sys.exit(1)
    else:
        sys.exit(1)