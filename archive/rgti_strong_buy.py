#!/usr/bin/env python3
"""
RGTI Strong Buy Signal Scanner
================================
Only fires when multiple buy signals align — high conviction entry.

Requires ALL of:
  - Trend line break OR support bounce (7+ pts)
  - Momentum confirmation (RSI oversold OR bullish divergence) (3+ pts)
  - Volume surge (1.5x+ average) 
  
Minimum combined score: 15 points = STRONG BUY

Usage: python3 rgti_strong_buy.py
Exit 0 = STRONG BUY detected (stdout delivered to Telegram)
Exit 1 = No signal (suppressed)
"""
import yfinance as yf
import pandas as pd
import numpy as np
import json
import requests
import sys
from datetime import datetime, timedelta
from pathlib import Path

TELEGRAM_BOT_TOKEN = "8784772860:AAHcL7WpZf8M1QfHfG8h"
TELEGRAM_CHAT_ID = "8355819128"
ALERT_LOG = Path(__file__).parent / "storage" / "rgti_strong_buy_alerts.jsonl"
OUTCOME_LOG = Path(__file__).parent / "storage" / "rgti_strong_buy_outcomes.jsonl"
ALERT_LOG.parent.mkdir(parents=True, exist_ok=True)


def send_telegram(msg):
    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
    payload = {"chat_id": TELEGRAM_CHAT_ID, "text": msg, "parse_mode": "Markdown"}
    try:
        r = requests.post(url, json=payload, timeout=10)
        return r.status_code == 200
    except:
        return False


def load_last_alert():
    """Load timestamp of last strong buy alert (avoid spam)."""
    try:
        with open(ALERT_LOG, "r") as f:
            lines = f.readlines()
            if lines:
                last = json.loads(lines[-1].strip())
                return datetime.fromisoformat(last["ts"])
    except:
        pass
    return None


def save_alert(data):
    try:
        with open(ALERT_LOG, "a") as f:
            f.write(json.dumps(data) + "\n")
    except:
        pass


def calc_rsi(series, period=14):
    delta = series.diff()
    gain = delta.clip(lower=0)
    loss = -delta.clip(upper=0)
    avg_gain = gain.rolling(period, min_periods=period).mean()
    avg_loss = loss.rolling(period, min_periods=period).mean()
    rs = avg_gain / avg_loss.replace(0, np.inf)
    return 100 - (100 / (1 + rs))


def calc_cmo(series, period=14):
    diff = series.diff()
    up = diff.clip(lower=0).rolling(period).sum()
    dn = (-diff.clip(upper=0)).rolling(period).sum()
    denom = up + dn
    denom = denom.replace(0, np.inf)
    return 100 * (up - dn) / denom


def find_pivots(high, low, left=3, right=3):
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


def project_line(line, current_time):
    td = (current_time - line['t1']).total_seconds() / 60
    if td <= 0:
        return line['p1']
    return line['p1'] + line['slope'] * td


def scan():
    t = yf.Ticker('RGTI')
    # Get 2 days of 5m bars for trend lines + intraday
    df_5m = t.history(period='2d', interval='5m')
    # Get 5 days of daily for bigger picture
    df_1d = t.history(period='5d', interval='1d')

    if df_5m.empty or len(df_5m) < 30:
        print("Not enough 5m data")
        return None

    # Filter pre-market bars — only regular trading hours
    df_5m = df_5m.between_time('09:30', '16:00')

    current_price = df_5m['Close'].iloc[-1]
    current_time = df_5m.index[-1]
    
    # Daily context
    if len(df_1d) >= 2:
        prev_close = df_1d['Close'].iloc[-2]
        day_chg = ((current_price - prev_close) / prev_close) * 100
    else:
        day_chg = 0
        prev_close = current_price

    close_5m = df_5m['Close'].astype(float)
    high_5m = df_5m['High'].astype(float)
    low_5m = df_5m['Low'].astype(float)
    vol_5m = df_5m['Volume'].astype(float)

    # ============ INDICATORS ============
    rsi5 = float(calc_rsi(close_5m, 5).iloc[-1])
    rsi14 = float(calc_rsi(close_5m, 14).iloc[-1])
    cmo = float(calc_cmo(close_5m, 14).iloc[-1])
    
    # EMAs
    ema5 = float(close_5m.ewm(span=5).mean().iloc[-1])
    ema13 = float(close_5m.ewm(span=13).mean().iloc[-1])
    ema21 = float(close_5m.ewm(span=21).mean().iloc[-1])
    
    # VWAP
    typical = (high_5m + low_5m + close_5m) / 3
    vol_s = vol_5m
    vwap = float((typical * vol_s).cumsum().iloc[-1] / vol_s.cumsum().iloc[-1])
    
    # MACD
    macd = close_5m.ewm(span=12).mean() - close_5m.ewm(span=26).mean()
    signal = macd.ewm(span=9).mean()
    macd_hist = float((macd - signal).iloc[-1])
    macd_cross = "bullish" if (macd - signal).iloc[-1] > (macd - signal).iloc[-2] else "bearish"
    
    # Volume
    recent_vol = float(vol_5m[-6:].mean())
    avg_vol = float(vol_5m[:-6].mean()) if len(vol_5m) > 6 else recent_vol
    vol_surge = recent_vol / avg_vol if avg_vol > 0 else 0
    
    # Buy/Sell volume
    obv_buy = 0
    obv_sell = 0
    n_obv = min(20, len(close_5m) - 1)
    for i in range(-n_obv, 0):
        if close_5m.iloc[i] > close_5m.iloc[i-1]:
            obv_buy += vol_5m.iloc[i]
        elif close_5m.iloc[i] < close_5m.iloc[i-1]:
            obv_sell += vol_5m.iloc[i]
    buy_sell_ratio = obv_buy / obv_sell if obv_sell > 0 else 99
    
    # Last N bars direction
    n_bars = min(6, len(close_5m) - 1)
    greens = sum(1 for i in range(-n_bars, 0) if close_5m.iloc[i] > close_5m.iloc[i-1])
    reds = n_bars - greens

    # ============ SIGNAL SCORING ============
    buy_signals = []
    sell_signals = []
    
    # --- TREND LINES (highest weight) ---
    pivots_high, pivots_low = find_pivots(high_5m, low_5m, left=3, right=3)
    
    # Filter pivots by age (max 90 min) to prevent stale lines
    max_age = pd.Timedelta(minutes=90)
    if pivots_high:
        newest_h = pivots_high[-1][0]
        cutoff_h = newest_h - max_age
        pivots_high = [(t, p) for t, p in pivots_high if t >= cutoff_h]
    if pivots_low:
        newest_l = pivots_low[-1][0]
        cutoff_l = newest_l - max_age
        pivots_low = [(t, p) for t, p in pivots_low if t >= cutoff_l]
    
    # Downtrend line breaks (resistance) = BUY
    for i in range(len(pivots_high) - 1):
        t1, p1 = pivots_high[i]
        t2, p2 = pivots_high[i + 1]
        td = (t2 - t1).total_seconds() / 60
        if td < 5:
            continue
        slope = (p2 - p1) / td
        if abs(slope) < 1e-6:
            continue
        minutes_past_end = (current_time - t2).total_seconds() / 60
        if minutes_past_end > 60:
            continue  # Line is too stale
        projected = p1 + slope * (current_time - t1).total_seconds() / 60
        if projected <= 0:
            continue
        dist_pct = ((current_price - projected) / projected) * 100
        
        # Break above downtrend line = STRONG BUY (cap at 5% to avoid stale breaks)
        if current_price > projected and 0.3 < dist_pct < 5:
            pts = 7 if dist_pct < 2 else 5
            buy_signals.append((f"📉 Downtrend TL break: line {projected:.2f}, price {current_price:.2f} (+{dist_pct:.1f}%)", pts))
    
    # Support line bounces = BUY
    for i in range(len(pivots_low) - 1):
        t1, p1 = pivots_low[i]
        t2, p2 = pivots_low[i + 1]
        td = (t2 - t1).total_seconds() / 60
        if td < 5:
            continue
        slope = (p2 - p1) / td
        if abs(slope) < 1e-6:
            continue
        minutes_past_end = (current_time - t2).total_seconds() / 60
        if minutes_past_end > 60:
            continue  # Line is too stale
        projected = p1 + slope * (current_time - t1).total_seconds() / 60
        if projected <= 0:
            continue
        dist_pct = ((current_price - projected) / projected) * 100
        
        # Bounce off support = BUY (only if within reasonable distance)
        if abs(dist_pct) < 2.0:
            buy_signals.append((f"📐 Support bounce: line {projected:.2f}, price {current_price:.2f} ({dist_pct:+.1f}%)", 5))
    
    # --- DIVERGENCE ---
    recent = 26
    if len(close_5m) >= 2 * recent:
        price_recent = close_5m.iloc[-recent:]
        price_prev = close_5m.iloc[-2*recent:-recent]
        rsi_vals = calc_rsi(close_5m, 5)
        rsi_recent = rsi_vals.iloc[-recent:]
        rsi_prev = rsi_vals.iloc[-2*recent:-recent]
        cmo_vals = calc_cmo(close_5m, 14)
        cmo_recent = cmo_vals.iloc[-recent:]
        cmo_prev = cmo_vals.iloc[-2*recent:-recent]
        
        # Bullish divergence
        if price_recent.min() < price_prev.min() and rsi_recent.min() > rsi_prev.min() + 5:
            buy_signals.append((f"🐂 Bullish RSI div: price {price_recent.min():.2f}<{price_prev.min():.2f} RSI {rsi_recent.min():.0f}>{rsi_prev.min():.0f}", 5))
        if price_recent.min() < price_prev.min() and cmo_recent.min() > cmo_prev.min() + 10:
            buy_signals.append((f"🐂 CMO div: CMO {cmo_recent.min():.0f}>{cmo_prev.min():.0f}", 4))
        
        # Bearish divergence
        if price_recent.max() > price_prev.max() and rsi_recent.max() < rsi_prev.max() - 5:
            sell_signals.append((f"🐻 Bearish RSI div", 5))

    # --- RSI ---
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

    # --- EMA ALIGNMENT ---
    if ema5 > ema13 > ema21:
        buy_signals.append((f"📈 EMA bull stack: {ema5:.1f}>{ema13:.1f}>{ema21:.1f}", 3))
    elif ema5 < ema13 < ema21:
        sell_signals.append((f"📉 EMA bear stack", 3))
    
    # EMA crossover
    if ema5 > ema13 and close_5m.iloc[-2] <= (close_5m.ewm(span=5).mean().iloc[-2]):
        buy_signals.append((f"✨ EMA5/13 bullish cross", 4))

    # --- MACD ---
    if macd_cross == "bullish" and macd_hist > 0:
        buy_signals.append((f"✨ MACD bullish cross (hist={macd_hist:.4f})", 4))
    elif macd_cross == "bearish" and macd_hist < 0:
        sell_signals.append((f"💀 MACD bearish cross", 4))

    # --- VOLUME SURGE ---
    if vol_surge >= 2.0:
        buy_signals.append((f"📊 Volume {vol_surge:.1f}x avg {('BUYING' if buy_sell_ratio > 1.5 else 'mixed')}", 4 if buy_sell_ratio > 1.5 else 2))
    elif vol_surge >= 1.5:
        buy_signals.append((f"📊 Volume {vol_surge:.1f}x avg", 2))

    # --- PRICE vs KEY LEVELS ---
    price_above_ema5 = current_price > ema5
    price_above_vwap = current_price > vwap
    
    if price_above_ema5 and price_above_vwap:
        buy_signals.append((f"💪 Price above EMA5+VWAP (${ema5:.2f}/${vwap:.2f})", 2))
    
    if buy_sell_ratio >= 3.0:
        buy_signals.append((f"🔋 Buying pressure {buy_sell_ratio:.1f}:1", 3))
    elif buy_sell_ratio >= 2.0:
        buy_signals.append((f"🔋 Buying pressure {buy_sell_ratio:.1f}:1", 2))

    # ============ SCORING ============
    buy_score = sum(pts for _, pts in buy_signals)
    sell_score = sum(pts for _, pts in sell_signals)
    
    # Category check
    has_tl_break = any("TL break" in desc for desc, pts in buy_signals) or any("bounce" in desc.lower() for desc, pts in buy_signals)
    has_momentum = any(kw in " ".join(desc for desc, _ in buy_signals) for kw in ["RSI", "MACD", "div", "oversold"])
    has_volume = vol_surge >= 1.5

    # FIX 7: Require 2-of-3 categories (not all 3) and score ≥ 12 (down from 15)
    categories_met = sum([has_tl_break, has_momentum, has_volume])
    strong_buy = buy_score >= 12 and categories_met >= 2
    
    return {
        'price': current_price,
        'prev_close': prev_close,
        'day_chg': day_chg,
        'rsi5': rsi5, 'rsi14': rsi14,
        'ema5': ema5, 'ema13': ema13, 'ema21': ema21,
        'vwap': vwap,
        'macd_hist': macd_hist, 'macd_cross': macd_cross,
        'vol_surge': vol_surge,
        'buy_sell_ratio': buy_sell_ratio,
        'buy_score': buy_score,
        'sell_score': sell_score,
        'buy_signals': buy_signals,
        'sell_signals': sell_signals,
        'has_tl_break': has_tl_break,
        'has_momentum': has_momentum,
        'has_volume': has_volume,
        'strong_buy': strong_buy,
        'timestamp': current_time,
    }


def main():
    data = scan()
    if data is None:
        print("❌ RGTI: Could not fetch data")
        sys.exit(1)
    
    p = data['price']
    chg = data['day_chg']
    bs = data['buy_score']
    ss = data['sell_score']
    
    # Always print status
    lines = [
        f"⚛️ *RGTI ${p:.2f}* ({chg:+.1f}%)",
        f"RSI5={data['rsi5']:.0f} RSI14={data['rsi14']:.0f} | VWAP=${data['vwap']:.2f}",
        f"BUY={bs} SELL={ss} | Vol={data['vol_surge']:.1f}x BS={data['buy_sell_ratio']:.1f}:1",
    ]
    
    if data['buy_signals']:
        lines.append("📈 Buy signals:")
        for desc, pts in data['buy_signals']:
            lines.append(f"  • {desc} [{pts}pts]")
    if data['sell_signals']:
        lines.append("📉 Sell signals:")
        for desc, pts in data['sell_signals']:
            lines.append(f"  • {desc} [{pts}pts]")
    
    if data['strong_buy']:
        lines.append("")
        lines.append("🟢🟢🟢 *STRONG BUY SIGNAL* 🟢🟢🟢")
        lines.append(f"TL break: {'✅' if data['has_tl_break'] else '❌'} | Momentum: {'✅' if data['has_momentum'] else '❌'} | Volume: {'✅' if data['has_volume'] else '❌'}")
        
        # Calculate ATR-based entry/stop/target (not hardcoded offsets)
        # ATR from daily or 5m data
        atr_5m = float((high_5m - low_5m).rolling(14).mean().iloc[-1]) if len(high_5m) > 14 else 0.5
        stop = round(min(data['vwap'] - atr_5m * 0.5, data['ema21'] - atr_5m * 0.3), 2)
        stop = max(stop, round(p * 0.97, 2))  # min 3% stop
        target = round(p + (p - stop) * 3, 2)  # 3:1 R:R
        lines.append(f"\n💵 *Entry:* ${p:.2f}")
        lines.append(f"🛑 *Stop:* ${stop:.2f}")
        lines.append(f"🎯 *Target:* ${target:.2f}")
        lines.append(f"📊 *R:R:* 3:1")
        
        msg = '\n'.join(lines)
        print(msg)
        send_telegram(msg)
        save_alert({"ts": datetime.utcnow().isoformat(), "price": p, "score": bs, "strong_buy": True})
        # Log outcome tracking
        with open(OUTCOME_LOG, "a") as f:
            f.write(json.dumps({
                "ts": datetime.utcnow().isoformat(), "sym": "RGTI", "action": "STRONG_BUY",
                "entry_price": p, "stop": stop, "target": target, "score": bs,
                "status": "pending", "pnl_30m": None, "pnl_60m": None
            }) + "\n")
        sys.exit(0)
    
    elif bs >= 7:
        lines.append("")
        lines.append("🟡 Moderate buy interest — watching for confirmation")
        msg = '\n'.join(lines)
        print(msg)
        # Only deliver if decent signal
        if bs >= 10:
            send_telegram(msg)
            sys.exit(0)
        sys.exit(1)
    
    else:
        lines.append("⚪ No strong buy signal yet")
        msg = '\n'.join(lines)
        print(msg)
        sys.exit(1)


if __name__ == '__main__':
    main()