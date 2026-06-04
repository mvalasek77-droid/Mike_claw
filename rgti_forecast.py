#!/usr/bin/env python3
"""RGTI next-hour forecast — run from current intraday data."""
import yfinance as yf
import pandas as pd
import numpy as np

t = yf.Ticker('RGTI')
h = t.history(period='2d', interval='5m')
h = h.between_time('09:30', '16:00')
c = h['Close'].astype(float)
v = h['Volume'].astype(float)

cur = float(c.iloc[-1])

# Recent bars
print("=== LAST 10 BARS ===")
for i in range(-10, 0):
    bar = h.iloc[i]
    t_str = h.index[i].strftime('%H:%M')
    chg = ((float(bar['Close']) - float(bar['Open'])) / float(bar['Open'])) * 100
    arrow = '🟢' if chg > 0 else '🔴'
    vol = int(bar['Volume'])
    print(f"{t_str} ${float(bar['Close']):.2f} {arrow} {chg:+.1f}% vol={vol:,}")

print(f"\nCurrent: ${cur:.2f}")

# RSI
delta = c.diff()
gain = delta.clip(lower=0).rolling(5).mean()
loss = (-delta.clip(upper=0)).rolling(5).mean()
rs = gain / loss.replace(0, np.inf)
rsi5 = float((100 - (100 / (1 + rs))).iloc[-1])

gain14 = delta.clip(lower=0).rolling(14).mean()
loss14 = (-delta.clip(upper=0)).rolling(14).mean()
rs14 = gain14 / loss14.replace(0, np.inf)
rsi14 = float((100 - (100 / (1 + rs14))).iloc[-1])

# EMAs
ema5 = float(c.ewm(span=5).mean().iloc[-1])
ema9 = float(c.ewm(span=9).mean().iloc[-1])
ema21 = float(c.ewm(span=21).mean().iloc[-1])

# VWAP
typical = (h['High'].astype(float) + h['Low'].astype(float) + c) / 3
vwap = float((typical * v).cumsum().iloc[-1] / v.cumsum().iloc[-1])

# MACD
macd = c.ewm(span=12).mean() - c.ewm(span=26).mean()
macd_sig = macd.ewm(span=9).mean()
macd_hist = float((macd - macd_sig).iloc[-1])
macd_prev = float((macd - macd_sig).iloc[-2])

# Volume
avg_vol = float(v[:-20].mean()) if len(v) > 20 else float(v.mean())
recent_vol = float(v[-6:].mean())
vol_ratio = recent_vol / avg_vol if avg_vol > 0 else 1

# Day levels
today_mask = [d.date() == h.index[-1].date() for d in h.index]
today_bars = h[today_mask]
day_high = float(today_bars['High'].max())
day_low = float(today_bars['Low'].min())

print(f"\n=== INDICATORS ===")
print(f"RSI5={rsi5:.0f} RSI14={rsi14:.0f}")
print(f"EMA5=${ema5:.2f} EMA9=${ema9:.2f} EMA21=${ema21:.2f}")
print(f"VWAP=${vwap:.2f}")
cross = ""
if macd_hist > 0 and macd_prev <= 0:
    cross = "bullish cross"
elif macd_hist < 0 and macd_prev >= 0:
    cross = "bearish cross"
else:
    cross = "continuing"
print(f"MACD hist={macd_hist:.3f} prev={macd_prev:.3f} {cross}")
print(f"Vol ratio={vol_ratio:.1f}x")
print(f"Day H=${day_high:.2f} L=${day_low:.2f} range=${day_high-day_low:.2f}")

# Next hour bias
bull_pts = 0
bear_pts = 0
if cur > ema5: bull_pts += 1
else: bear_pts += 1
if cur > ema9: bull_pts += 1
else: bear_pts += 1
if cur > vwap: bull_pts += 1
else: bear_pts += 1
if macd_hist > 0: bull_pts += 1
else: bear_pts += 1
if rsi5 > 50: bull_pts += 1
else: bear_pts += 1
if vol_ratio > 1.3: bull_pts += 1

# Near support/resistance
recent2h = h.iloc[-24:]
resistance = float(recent2h['High'].max())
support = float(recent2h['Low'].min())

print(f"\n=== NEXT HOUR BIAS ===")
print(f"Bull: {bull_pts} | Bear: {bear_pts}")
if bull_pts > bear_pts + 1:
    bias = "BULLISH — indicators stacked for continuation up"
elif bear_pts > bull_pts + 1:
    bias = "BEARISH — indicators stacked for continuation down"
else:
    bias = "NEUTRAL — mixed, likely chop"
print(f"→ {bias}")
print(f"Near support: ${support:.2f} | Near resistance: ${resistance:.2f}")

# Consecutive bar pattern
last3 = c.iloc[-3:]
ups = sum(1 for i in range(1, len(last3)) if float(last3.iloc[i]) > float(last3.iloc[i-1]))
print(f"\nLast 3 bars: {ups} up / {3-ups} down")
if ups == 3:
    print("→ 3 consecutive up — exhaustion risk, watch for reversal")
elif ups == 0:
    print("→ 3 consecutive down — capitulation risk, watch for bounce")