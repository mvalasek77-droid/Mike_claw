#!/usr/bin/env python3
"""
Binary Oil Signal — WTI/CL=F only
================================================
Monthly trend lines determine direction.
UPTREND:   BUY the 1-down pullback, SELL after 2-up (3-6%)
DOWNTREND: SELL the 1-up bounce, COVER after 2-down (3-6%)
Double tops/bottoms = trend change warnings.
TA confirms. Just buy or sell oil.
"""
import json, sys, os
from datetime import datetime
from pathlib import Path
import yfinance as yf
import pandas as pd
import numpy as np
from scipy.signal import argrelextrema

LOG = Path(__file__).parent / "storage" / "signal_log.jsonl"
LAST_SIGNAL = Path(__file__).parent / "storage" / "last_oil_signal.json"
OUTCOME_LOG = Path(__file__).parent / "storage" / "signal_outcomes.jsonl"
LOG.parent.mkdir(parents=True, exist_ok=True)

def send_telegram(msg):
    import requests
    url = "https://api.telegram.org/bot8784772860:AAHcL7WpZf8M1QfHfG8h/sendMessage"
    try:
        r = requests.post(url, json={"chat_id": "8355819128", "text": msg, "parse_mode": "Markdown"}, timeout=10)
        return r.status_code == 200
    except:
        return False

def log_signal(data):
    with open(LOG, "a") as f:
        f.write(json.dumps(data) + "\n")

def get_last_signal():
    """Load last signal state for cooldown — only alert on signal CHANGE."""
    try:
        with open(LAST_SIGNAL, "r") as f:
            return json.loads(f.read())
    except:
        return None

def save_last_signal(data):
    with open(LAST_SIGNAL, "w") as f:
        f.write(json.dumps(data))

def log_signal_outcome(signal_data):
    """Schedule a follow-up check: log price 30m and 60m after signal."""
    outcome = {
        "ts": datetime.utcnow().isoformat(),
        "signal_ts": signal_data.get("ts", ""),
        "sym": signal_data.get("sym", "WTI"),
        "signal": signal_data.get("signal", ""),
        "entry_price": signal_data.get("price", 0),
        "stop": signal_data.get("stop", 0),
        "target": signal_data.get("target", 0),
        "status": "pending",
        "pnl_30m": None,
        "pnl_60m": None,
    }
    with open(OUTCOME_LOG, "a") as f:
        f.write(json.dumps(outcome) + "\n")

def ema(series, span):
    return series.ewm(span=span).mean()

def rsi(series, period=14):
    delta = series.diff()
    gain = delta.clip(lower=0).rolling(period).mean()
    loss = (-delta.clip(upper=0)).rolling(period).mean()
    rs = gain / loss.replace(0, np.inf)
    return 100 - (100 / (1 + rs))

def find_doubles(series, mode='top', tolerance=0.015):
    """Find double tops or bottoms within tolerance%"""
    if mode == 'top':
        idxs = argrelextrema(series.values, np.greater, order=3)[0]
    else:
        idxs = argrelextrema(series.values, np.less, order=3)[0]
    if len(idxs) < 2:
        return []
    results = []
    for i in range(len(idxs)-1):
        p1, p2 = idxs[i], idxs[i+1]
        v1, v2 = series.iloc[p1], series.iloc[p2]
        if abs(v1 - v2) / max(v1, v2) < tolerance:
            results.append((p2, round(v2, 2)))
    return results

def oil_signal():
    t = yf.Ticker('CL=F')
    h = t.history(period='1mo', interval='1d')
    h_5m = t.history(period='2d', interval='5m')
    if len(h) < 20 or len(h_5m) < 50:
        return None

    highs = h['High'].astype(float)
    lows = h['Low'].astype(float)
    opens = h['Open'].astype(float)
    closes = h['Close'].astype(float)
    volumes = h['Volume'].astype(float)
    cur = float(closes.iloc[-1])
    prev_close = float(closes.iloc[-2])

    # ============ 1-MONTH RANGE (TREND LINES) ============
    # Clean bad ticks
    valid = closes > cur * 0.30
    clean_lows = lows[valid]
    clean_highs = highs[valid]
    if len(clean_lows) < 5:
        clean_lows = lows[-5:]
        clean_highs = highs[-5:]
    lookback = min(22, len(clean_highs))
    m_high = float(clean_highs[-lookback:].max())
    m_low = float(clean_lows[-lookback:].min())
    m_range = m_high - m_low
    m_25 = m_low + m_range * 0.25
    m_50 = m_low + m_range * 0.50
    m_75 = m_low + m_range * 0.75
    range_pct = (cur - m_low) / m_range * 100 if m_range > 0 else 50

    # ============ DETERMINE MONTHLY TREND ============
    ema5 = float(ema(closes, 5).iloc[-1])
    ema9 = float(ema(closes, 9).iloc[-1])
    ema21 = float(ema(closes, 21).iloc[-1]) if len(closes) > 21 else ema9

    week_ago = float(closes.iloc[-6]) if len(closes) > 6 else float(closes.iloc[0])
    week_chg = (cur - week_ago) / week_ago * 100
    two_week_ago = float(closes.iloc[-11]) if len(closes) > 11 else float(closes.iloc[0])
    two_week_chg = (cur - two_week_ago) / two_week_ago * 100

    # Trend scoring
    trend_score = 0
    ema_bull = ema5 > ema9 > ema21
    ema_bear = ema5 < ema9 < ema21
    if ema_bull: trend_score += 3
    elif ema5 > ema9: trend_score += 1
    if ema_bear: trend_score -= 3
    elif ema5 < ema9: trend_score -= 1
    if cur > ema9: trend_score += 1
    else: trend_score -= 1
    if cur > ema21: trend_score += 1
    else: trend_score -= 1
    if week_chg > 3: trend_score += 2
    elif week_chg > 0: trend_score += 1
    elif week_chg < -3: trend_score -= 2
    elif week_chg < 0: trend_score -= 1

    if trend_score >= 3:
        trend = "UP"
    elif trend_score <= -3:
        trend = "DOWN"
    else:
        trend = "SIDEWAYS"

    # ============ WHERE ARE WE IN THE PATTERN? ============
    # Current bar: up or down?
    current_up = cur > prev_close
    # Recent 5-bar pattern
    last5 = closes.iloc[-5:].values
    ups = sum(1 for i in range(1, len(last5)) if last5[i] > last5[i-1])
    downs = sum(1 for i in range(1, len(last5)) if last5[i] < last5[i-1])
    # V-shapes (1-down-2-up pullbacks)
    pattern_up = 0
    for i in range(2, len(last5)):
        if last5[i-2] > last5[i-1] and last5[i-1] < last5[i]:
            pattern_up += 1
    # Inverted V (1-up-2-down bounces)
    pattern_down = 0
    for i in range(2, len(last5)):
        if last5[i-2] < last5[i-1] and last5[i-1] > last5[i]:
            pattern_down += 1

    # ============ DOUBLE TOPS / BOTTOMS ============
    warnings = []
    double_tops = find_doubles(highs, 'top')
    double_bottoms = find_doubles(lows, 'bottom')
    if double_tops:
        idx, price = double_tops[-1]
        bars_ago = len(highs) - 1 - idx
        if bars_ago < 10:
            warnings.append(f"Double top ${price:.2f} ({bars_ago}d ago)")
    if double_bottoms:
        idx, price = double_bottoms[-1]
        bars_ago = len(lows) - 1 - idx
        if bars_ago < 10:
            warnings.append(f"Double bottom ${price:.2f} ({bars_ago}d ago)")

    # ============ TA INDICATORS ============
    ta_for = []
    ta_against = []
    ta_score = 0

    if ema_bull:
        ta_for.append("EMA bull stack")
        ta_score += 2
    elif ema_bear:
        ta_against.append("EMA bear stack")
        ta_score -= 2
    elif ema5 > ema9:
        ta_for.append("EMA5>9")
        ta_score += 1
    elif ema5 < ema9:
        ta_against.append("EMA5<9")
        ta_score -= 1

    if cur > ema9:
        ta_for.append(f"above EMA9 ${ema9:.2f}")
        ta_score += 1
    else:
        ta_against.append(f"below EMA9 ${ema9:.2f}")
        ta_score -= 1

    rsi5_val = float(rsi(closes, 5).iloc[-1])
    rsi14_val = float(rsi(closes, 14).iloc[-1])

    if rsi5_val < 25:
        ta_for.append(f"RSI5={rsi5_val:.0f} oversold")
        # In confirmed downtrend, RSI5 oversold is counter-trend — cap influence
        if trend == "DOWN":
            ta_score += 0  # no boost for oversold in downtrend
        else:
            ta_score += 2
    elif rsi5_val > 75:
        ta_against.append(f"RSI5={rsi5_val:.0f} overbought")
        # In confirmed uptrend, RSI5 overbought is counter-trend
        if trend == "UP":
            ta_score -= 0
        else:
            ta_score -= 2

    if rsi14_val < 30:
        ta_for.append(f"RSI14={rsi14_val:.0f} oversold")
        ta_score += 1
    elif rsi14_val > 70:
        ta_against.append(f"RSI14={rsi14_val:.0f} overbought")
        ta_score -= 1

    macd = ema(closes, 12) - ema(closes, 26)
    macd_sig = ema(macd, 9)
    macd_hist = float((macd - macd_sig).iloc[-1])
    macd_prev = float((macd - macd_sig).iloc[-2]) if len(closes) > 2 else 0

    if macd_hist > 0 and macd_prev <= 0:
        ta_for.append("MACD bullish cross")
        ta_score += 2
    elif macd_hist < 0 and macd_prev >= 0:
        ta_against.append("MACD bearish cross")
        ta_score -= 2
    elif macd_hist > 0:
        ta_for.append("MACD bullish")
        ta_score += 1
    elif macd_hist < 0:
        ta_against.append("MACD bearish")
        ta_score -= 1

    # VWAP
    c5 = h_5m['Close'].astype(float)
    h5 = h_5m['High'].astype(float)
    l5 = h_5m['Low'].astype(float)
    v5 = h_5m['Volume'].astype(float)
    typical = (h5 + l5 + c5) / 3
    vwap = float((typical * v5).cumsum().iloc[-1] / v5.cumsum().iloc[-1])

    if cur > vwap:
        ta_for.append(f"above VWAP ${vwap:.2f}")
        ta_score += 1
    else:
        ta_against.append(f"below VWAP ${vwap:.2f}")
        ta_score -= 1

    # Volume
    avg_vol = float(volumes[:-6].mean()) if len(volumes) > 6 else 1
    recent_vol = float(volumes[-3:].mean())
    vol_ratio = recent_vol / avg_vol if avg_vol > 0 else 1

    if vol_ratio > 1.5:
        ta_for.append(f"vol {vol_ratio:.1f}x")
        ta_score += 1
    elif vol_ratio < 0.5:
        ta_against.append("low vol")
        ta_score -= 1

    # ATR for stops
    tr = pd.Series(
        np.maximum(highs - lows,
                   np.maximum(np.abs(highs - closes.shift(1)),
                              np.abs(lows - closes.shift(1)))),
        index=closes.index
    )
    atr14 = float(tr.rolling(14).mean().iloc[-1]) if len(tr) > 14 else float(tr.mean())

    # 3-6% targets
    pct_target = 0.04  # 4% default
    # ATR-based stops: use 1x ATR for stop distance (not flat %)
    atr_stop_dist = atr14  # 1x ATR14
    pct_stop = atr_stop_dist / cur if cur > 0 else 0.015

    # ============ SIGNAL LOGIC ============
    # UPTREND: BUY the 1-down, SELL after 2-up (3-6% target)
    # DOWNTREND: SELL the 1-up, COVER after 2-down (3-6% target)
    # Halfway = PIVOT: uptrend breaks halfway → goes to TOP

    signal = "HOLD"
    entry = cur
    stop = cur
    target = cur
    reason = ""
    conf = 3

    if trend == "UP":
        if not current_up:
            # Current bar is DOWN = this is the "1 down" → BUY the pullback
            signal = "BUY"
            entry = cur
            target = round(cur * (1 + pct_target), 2)   # +4%
            stop = round(cur * (1 - pct_stop), 2)         # -1.5%
            reason = f"UPTREND 1↓ → BUY pullback, sell at +{pct_target*100:.0f}%"
            conf = 7
            if pattern_up >= 1:
                reason = f"UPTREND 1↓ pullback ✓ → BUY, target +{pct_target*100:.0f}%"
                conf = 8
            if range_pct < 50:
                # Pullback to pivot zone → stronger
                reason = f"UPTREND 1↓ at {range_pct:.0f}% range → BUY dip, target ${target}"
                conf = 8
        else:
            # Current bar is UP = "2 up" → SELL (take profit)
            signal = "SELL"
            entry = cur
            target = round(cur * (1 - pct_target), 2)   # expect pullback
            stop = round(cur * (1 + pct_stop), 2)         # stop above
            reason = f"UPTREND 2↑ → SELL/take profit, expect pullback"
            conf = 5
            if range_pct > 75:
                reason = f"UPTREND 2↑ at {range_pct:.0f}% range → overstretched, SELL"
                conf = 7

    elif trend == "DOWN":
        if current_up:
            # Current bar is UP = "1 up" bounce → SELL into strength
            signal = "SELL"
            entry = cur
            target = round(cur * (1 - pct_target), 2)   # -4% to downside
            stop = round(cur * (1 + pct_stop), 2)         # +1.5% stop
            reason = f"DOWNTREND 1↑ bounce → SELL into strength"
            conf = 7
            if pattern_down >= 1:
                reason = f"DOWNTREND 1↑ bounce ✓ → SELL, target -{pct_target*100:.0f}%"
                conf = 8
            if range_pct > 50:
                reason = f"DOWNTREND 1↑ at {range_pct:.0f}% → SELL strength"
                conf = 8
        else:
            # Current bar is DOWN = "2 down" → SELL continuation or wait
            signal = "SELL"
            entry = cur
            target = round(cur * (1 - pct_target), 2)   # -4%
            stop = round(cur * (1 + pct_stop), 2)         # +1.5%
            reason = f"DOWNTREND 2↓ → SELL continuation"
            conf = 5
            if range_pct > 50 and range_pct < 75:
                # Already in downtrend, continuation
                reason = f"DOWNTREND 2↓ at {range_pct:.0f}% → SELL continuation"
                conf = 6
            if range_pct < 25:
                # Capitulation zone → might bounce, BUT only with confirmation
                # Require: RSI14 must be rising, MACD bullish or crossing, volume surge
                rsi14_rising = float(rsi(closes, 14).iloc[-1]) > float(rsi(closes, 14).iloc[-2])
                macd_bullish = macd_hist > 0 or (macd_hist > 0 and macd_prev <= 0)
                vol_surge = vol_ratio > 1.5
                if rsi14_rising and (macd_bullish or vol_surge):
                    signal = "BUY"
                    target = round(cur * (1 + pct_target), 2)
                    stop = round(cur - atr_stop_dist, 2)
                    reason = f"DOWNTREND capitulation zone + RSI↑ + MACD/vol confirm → BUY bounce"
                    conf = 7
                else:
                    signal = "SELL"
                    target = round(cur * (1 - pct_target), 2)
                    stop = round(cur + atr_stop_dist, 2)
                    reason = f"DOWNTREND capitulation zone — NO confirmation (RSI still falling, no vol) → SELL"
                    conf = 6

    else:  # SIDEWAYS
        if range_pct > 75:
            signal = "SELL"
            target = round(cur * (1 - pct_target), 2)
            stop = round(cur * (1 + pct_stop), 2)
            reason = f"Sideways near top → SELL to halfway"
            conf = 4
        elif range_pct < 25:
            signal = "BUY"
            target = round(cur * (1 + pct_target), 2)
            stop = round(cur * (1 - pct_stop), 2)
            reason = f"Sideways near bottom → BUY to halfway"
            conf = 4
        elif range_pct > 50:
            signal = "SELL"
            target = round(cur * (1 - pct_target), 2)
            stop = round(cur * (1 + pct_stop), 2)
            reason = f"Sideways >50% → slight SELL"
            conf = 3
        else:
            signal = "BUY"
            target = round(cur * (1 + pct_target), 2)
            stop = round(cur * (1 - pct_stop), 2)
            reason = f"Sideways <50% → slight BUY"
            conf = 3

    # ============ DOUBLE TOP/BOTTOM ADJUSTMENTS ============
    if double_tops:
        idx, price = double_tops[-1]
        bars_ago = len(highs) - 1 - idx
        if bars_ago < 10:
            if trend == "UP" and signal == "BUY":
                conf = max(1, conf - 2)
                reason += " ⚡DT"

    if double_bottoms:
        idx, price = double_bottoms[-1]
        bars_ago = len(lows) - 1 - idx
        if bars_ago < 10:
            if trend == "DOWN" and signal == "SELL":
                conf = max(1, conf - 2)
                reason += " ⚡DB"

    # ============ TA CONFIDENCE ADJUSTMENT ============
    if signal == "BUY":
        adj = min(ta_score, 3) if ta_score > 0 else max(ta_score, -3)
    else:  # SELL
        adj = min(abs(ta_score), 3) if ta_score < 0 else -min(ta_score, 3)

    conf = max(1, min(10, conf + adj))

    # R:R
    if signal == "BUY":
        risk = abs(entry - stop)
        reward = abs(target - entry)
    else:
        risk = abs(stop - entry)
        reward = abs(entry - target)
    rr = round(reward / risk, 1) if risk > 0 else 0

    # TA string
    ta_str = ""
    if ta_for:
        ta_str = " | " + ", ".join(ta_for[:3])
    if ta_against:
        prefix = " ⚠️" if signal == "BUY" else " ✓"
        ta_str += prefix + ",".join(ta_against[:2])

    # Warnings string
    warn_str = ""
    if warnings:
        warn_str = "\n⚡ " + " | ".join(warnings)

    # Pattern label
    if trend == "UP":
        pattern = "1↓BUY / 2↑SELL" if not current_up else "2↑SELL"
    elif trend == "DOWN":
        pattern = "1↑SELL" if current_up else "2↓SELL"
    else:
        pattern = "—"

    # Which way to trade HOU/HOD
    if signal == "BUY":
        trade = "HOU (long oil)"
    else:
        trade = "HOD (short oil)"

    # Percent targets
    if signal == "BUY":
        pct_r = round((target - entry) / entry * 100, 1)
        pct_s = round((entry - stop) / entry * 100, 1)
    else:
        pct_r = round((entry - target) / entry * 100, 1)
        pct_s = round((stop - entry) / entry * 100, 1)

    return {
        'price': round(cur, 2),
        'trend': trend, 'trend_score': trend_score,
        'signal': signal, 'confidence': conf,
        'entry': round(entry, 2),
        'stop': round(stop, 2),
        'target': round(target, 2),
        'trade': trade,
        'rr': rr,
        'pct_r': pct_r, 'pct_s': pct_s,
        'reason': reason,
        'range_pct': round(range_pct, 0),
        '1m_low': round(m_low, 2), '1m_25': round(m_25, 2),
        '1m_50': round(m_50, 2), '1m_75': round(m_75, 2),
        '1m_high': round(m_high, 2),
        'pattern': pattern,
        'current_bar': '↑' if current_up else '↓',
        'ema9': round(ema9, 2), 'ema21': round(ema21, 2),
        'vwap': round(vwap, 2),
        'rsi5': round(rsi5_val, 0), 'rsi14': round(rsi14_val, 0),
        'macd': round(macd_hist, 3),
        'vol_ratio': round(vol_ratio, 1),
        'atr14': round(atr14, 2),
        'ta_for': ta_for, 'ta_against': ta_against,
        'ta_score': ta_score, 'ta_str': ta_str,
        'week_chg': round(week_chg, 1),
        'warnings': warnings, 'warn_str': warn_str,
    }


def main():
    r = oil_signal()
    if not r:
        print("HOLD — no data")
        sys.exit(1)

    m = r
    emoji = "🟢" if m['signal'] == "BUY" else "🔴" if m['signal'] == "SELL" else "⚪"
    trend_icon = '📈' if m['trend'] == 'UP' else '📉' if m['trend'] == 'DOWN' else '➡️'

    # Full output
    print(f"{emoji} {m['signal']} WTI @ ${m['price']}")
    print(f"   {trend_icon} Trend: {m['trend']} (score {m['trend_score']}) | Bar: {m['current_bar']} | Pattern: {m['pattern']}")
    print(f"   🛑 Stop: ${m['stop']} ({m['pct_s']}%) | 🎯 Target: ${m['target']} ({m['pct_r']}%) | R:R {m['rr']}:1")
    print(f"   📊 Conf: {m['confidence']}/10 | {m['reason']}")
    print(f"   📐 ${m['1m_low']}→${m['1m_25']}→${m['1m_50']}→${m['1m_75']}→${m['1m_high']} ({m['range_pct']:.0f}%)")
    print(f"   🔢 EMA9=${m['ema9']} EMA21=${m['ema21']} VWAP=${m['vwap']} RSI={m['rsi5']}/{m['rsi14']} MACD={m['macd']} ATR=${m['atr14']}{m['ta_str']}")
    print(f"   🔄 Trade: {m['trade']}")
    if m['warnings']:
        print(f"   ⚡ {' | '.join(m['warnings'])}")
    print()

    # Telegram message
    if m['signal'] == "HOLD":
        print("No actionable signal")
        sys.exit(1)

    msg = (
        f"{emoji} **{m['signal']} WTI** @ ${m['price']}\n"
        f"{trend_icon} {m['trend']} | {m['pattern']}\n"
        f"🛑 Stop: ${m['stop']} ({m['pct_s']}%)\n"
        f"🎯 Target: ${m['target']} ({m['pct_r']}%) R:R {m['rr']}:1\n"
        f"📊 Conf: {m['confidence']}/10\n"
        f"💡 {m['reason']}\n"
        f"🔄 Trade: {m['trade']}\n"
        f"📐 ${m['1m_low']}→${m['1m_25']}→${m['1m_50']}→${m['1m_75']}→${m['1m_high']} ({m['range_pct']:.0f}%)\n"
        f"🔢 EMA9=${m['ema9']} VWAP=${m['vwap']} RSI={m['rsi5']}/{m['rsi14']} MACD={m['macd']}{m['ta_str']}"
    )
    if m['warnings']:
        msg += f"\n⚡ {' | '.join(m['warnings'])}"

    print(f"=== TELEGRAM ===\n{msg}")

    if m['confidence'] >= 5:
        signal_data = {
            "ts": datetime.utcnow().isoformat(),
            "sym": "WTI", "signal": m['signal'],
            "price": m['price'], "stop": m['stop'],
            "target": m['target'], "confidence": m['confidence'],
            "trend": m['trend'], "range_pct": m['range_pct'],
            "trade": m['trade'],
        }
        log_signal(signal_data)

        # FIX 1: Signal-change cooldown — only send Telegram if signal CHANGED
        last = get_last_signal()
        should_alert = True
        if last is not None:
            # Same signal + same trend + same confidence band = duplicate, skip
            same_signal = (last.get('signal') == m['signal'] and
                          last.get('trend') == m['trend'] and
                          abs(last.get('confidence', 0) - m['confidence']) <= 1)
            if same_signal:
                should_alert = False
                print(f"[COOLDOWN — same signal as last ({last.get('signal')} conf={last.get('confidence')})]")

        if should_alert:
            send_telegram(msg)
            save_last_signal(signal_data)
            log_signal_outcome(signal_data)


if __name__ == "__main__":
    main()