#!/usr/bin/env python3
"""RGTI entry alert monitor — pings Telegram when price hits buy zone."""
import yfinance as yf
import pandas as pd
import numpy as np
import json
import requests
import sys
from datetime import datetime

TELEGRAM_BOT_TOKEN = "8784772860:AAH8cO4sKXlC7Z6dF3V5X2Y1Z9aB7dE4fG8h"
TELEGRAM_CHAT_ID = "8355819128"

# Entry zones — buy on dips (tightened for current pullback)
ENTRY_ZONES = [
    {"level": 26.25, "label": "Morning consolidation S / retest zone", "type": "dip_to_consolidation"},
    {"level": 25.90, "label": "VWAP approach ($25.74)", "type": "dip_to_vwap"},
    {"level": 25.74, "label": "VWAP touch — high conviction buy", "type": "dip_to_vwap_exact"},
    {"level": 25.00, "label": "Deep washout / yesterday close", "type": "deep_pullback"},
]

# Breakout above today's high = momentum resume
BREAKOUT_LEVEL = 27.80

ALERT_LOG = "/Users/clawcl/code/Mike_claw/trading/storage/rgti_alerts.jsonl"

def send_telegram(msg):
    url = f"https://api.telegram.org/bot8784772860:AAH8cO4sKXlC7Z6dF3V5X2Y1Z9aB7dE4fG8h/sendMessage"
    payload = {"chat_id": TELEGRAM_CHAT_ID, "text": msg, "parse_mode": "Markdown"}
    try:
        r = requests.post(url, json=payload, timeout=10)
        return r.status_code == 200
    except:
        return False

def load_alerted():
    """Load already-alerted zones so we don't spam."""
    alerted = set()
    try:
        with open(ALERT_LOG, "r") as f:
            for line in f:
                d = json.loads(line.strip())
                alerted.add(d.get("zone", ""))
    except:
        pass
    return alerted

def save_alerted(zone, price):
    try:
        with open(ALERT_LOG, "a") as f:
            f.write(json.dumps({"ts": datetime.utcnow().isoformat(), "zone": zone, "price": price}) + "\n")
    except:
        pass

def analyze_rgti():
    t = yf.Ticker("RGTI")
    hist_5m = t.history(period="1d", interval="5m")
    hist_1d = t.history(period="5d", interval="1d")

    if len(hist_5m) < 5 or len(hist_1d) < 2:
        return None

    # Use raw DataFrame — yfinance returns flat columns for single ticker
    close = hist_5m["Close"].values.astype(float)
    high = hist_5m["High"].values.astype(float)
    low = hist_5m["Low"].values.astype(float)
    volume = hist_5m["Volume"].values.astype(float)

    cur = close[-1]
    day_high = float(hist_1d["High"].iloc[-1])
    day_low = float(hist_1d["Low"].iloc[-1])
    prev_close = float(hist_1d["Close"].iloc[-2])

    c = pd.Series(close)
    # EMAs
    ema5 = float(c.ewm(span=5).mean().iloc[-1])
    ema13 = float(c.ewm(span=13).mean().iloc[-1])
    ema21 = float(c.ewm(span=21).mean().iloc[-1])

    # VWAP
    typical = (pd.Series(high) + pd.Series(low) + c) / 3
    vol_s = pd.Series(volume)
    vwap = float((typical * vol_s).cumsum().iloc[-1] / vol_s.cumsum().iloc[-1])

    # RSI(8)
    delta = c.diff()
    gain = delta.where(delta > 0, 0).rolling(8).mean()
    loss = (-delta.where(delta < 0, 0)).rolling(8).mean()
    rsi8 = float((100 - (100 / (1 + gain / loss))).iloc[-1])

    # MACD
    ema12 = c.ewm(span=12).mean()
    ema26 = c.ewm(span=26).mean()
    macd = ema12 - ema26
    signal = macd.ewm(span=9).mean()
    macd_hist = float((macd - signal).iloc[-1])

    # Volume
    vol_avg = float(volume[:-6].mean()) if len(volume) > 6 else 1
    vol_last = float(volume[-1])
    vol_ratio = vol_last / vol_avg if vol_avg > 0 else 0

    # Trend: last 6 bars
    last6 = close[-6:]
    red_count = sum(1 for i in range(1, len(last6)) if last6[i] < last6[i-1])
    green_count = sum(1 for i in range(1, len(last6)) if last6[i] > last6[i-1])

    # Buy/sell volume (last N bars, up to 20)
    n_obv = min(20, len(close) - 1)
    obv_buy = 0
    obv_sell = 0
    for i in range(-n_obv, 0):
        if close[i] > close[i-1]:
            obv_buy += volume[i]
        elif close[i] < close[i-1]:
            obv_sell += volume[i]
    buy_sell_ratio = obv_buy / obv_sell if obv_sell > 0 else 99

    return {
        "price": round(cur, 2),
        "day_high": round(day_high, 2),
        "day_low": round(day_low, 2),
        "ema5": round(ema5, 2),
        "ema13": round(ema13, 2),
        "ema21": round(ema21, 2),
        "vwap": round(vwap, 2),
        "rsi8": round(rsi8, 1),
        "macd_hist": round(macd_hist, 3),
        "vol_ratio": round(vol_ratio, 2),
        "red_bars": red_count,
        "green_bars": green_count,
        "buy_sell": round(buy_sell_ratio, 2),
        "prev_close": round(prev_close, 2),
    }

def main():
    data = analyze_rgti()
    if not data:
        print("No data")
        return

    print(f"RGTI: ${data['price']} | EMA5=${data['ema5']} EMA13=${data['ema13']} VWAP=${data['vwap']} RSI={data['rsi8']}")

    alerted = load_alerted()
    alerts_sent = []

    # Check dip to entry zones
    for zone in ENTRY_ZONES:
        zone_key = f"{zone['level']}_{zone['label'].replace(' ', '_')}"
        # Alert if price is within 0.5% of the level AND dropping into it
        if data["price"] <= zone["level"] * 1.005 and zone_key not in alerted:
            # Confirm it's a dip (price below or at EMA5, or red bars)
            dipping = data["price"] <= data["ema5"] or data["red_bars"] >= 2
            if dipping:
                # Calculate R:R based on zone
                stop_prices = {
                    "dip_to_consolidation": 25.70,
                    "dip_to_vwap": 25.00,
                    "dip_to_vwap_exact": 25.00,
                    "deep_pullback": 24.00,
                }
                stop = stop_prices.get(zone["type"], zone["level"] - 1.00)
                risk = data["price"] - stop
                target = 27.80
                reward = target - data["price"]
                rr = reward / risk if risk > 0 else 0

                msg = (
                    f"🎯 *RGTI DIP ALERT*\n\n"
                    f"📊 ${data['price']:.2f} — testing *{zone['label']}* (${zone['level']:.2f})\n\n"
                    f"EMA5: ${data['ema5']:.2f} | EMA13: ${data['ema13']:.2f}\n"
                    f"VWAP: ${data['vwap']:.2f} | RSI: {data['rsi8']:.0f}\n"
                    f"Buy/Sell: {data['buy_sell']:.1f}:1\n\n"
                    f"💵 *Buy:* ${data['price']:.2f}\n"
                    f"🛑 *Stop:* ${stop:.2f}\n"
                    f"🎯 *Target:* ${target:.2f}\n"
                    f"📊 *R:R:* {rr:.1f}:1"
                )
                if send_telegram(msg):
                    save_alerted(zone_key, data["price"])
                    alerts_sent.append(zone["label"])
                    print(f"  ALERT SENT: {zone['label']}")

    # Check breakout above today's high (with volume confirmation)
    breakout_key = "breakout_27.80"
    if data["price"] >= BREAKOUT_LEVEL * 0.995 and breakout_key not in alerted:
        if data["vol_ratio"] >= 1.5 and data["buy_sell"] >= 2.0:
            msg = (
                f"🚀 *RGTI BREAKOUT ALERT*\n\n"
                f"📊 ${data['price']:.2f} — breaking above ${BREAKOUT_LEVEL}!\n\n"
                f"Vol spike: {data['vol_ratio']:.1f}x | Buy/Sell: {data['buy_sell']:.1f}:1\n"
                f"RSI: {data['rsi8']:.0f} | MACD hist: {data['macd_hist']}\n\n"
                f"💵 *Buy:* ${data['price']:.2f}\n"
                f"🛑 *Stop:* ${BREAKOUT_LEVEL - 1.00:.2f}\n"
                f"🎯 *Target:* ${BREAKOUT_LEVEL + 2:.2f}"
            )
            if send_telegram(msg):
                save_alerted(breakout_key, data["price"])
                alerts_sent.append("breakout")
                print(f"  ALERT SENT: breakout")

    if not alerts_sent:
        print("  No alerts triggered")

    return data

if __name__ == "__main__":
    main()