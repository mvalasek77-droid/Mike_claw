#!/usr/bin/env python3
"""WTI bounce signal checker for HOU trade."""
import yfinance as yf
import pandas as pd
import numpy as np
import json

print("Fetching 5-min data...")
wti = yf.download('CL=F', period='1d', interval='5m', progress=False)
hou = yf.download('HOU.TO', period='1d', interval='5m', progress=False)

print(f"WTI rows: {len(wti)}")
print(f"HOU rows: {len(hou)}")

# Extract close prices
wti_close = wti['Close']
hou_close = hou['Close']

if isinstance(wti_close.iloc[-1], pd.Series):
    wti_close = wti_close.iloc[:, 0]
    hou_close = hou_close.iloc[:, 0]

wti_last = float(wti_close.iloc[-1])
hou_last = float(hou_close.iloc[-1])

print(f"WTI last: {wti_last:.2f}")
print(f"HOU last: {hou_last:.2f}")

# RSI(8) calculation
closes = pd.Series(wti_close.values, dtype=float)
delta = closes.diff()
gain = delta.where(delta > 0, 0.0)
loss = (-delta).where(delta < 0, 0.0)
avg_gain = gain.rolling(window=8).mean()
avg_loss = loss.rolling(window=8).mean()
rs = avg_gain / avg_loss
rsi = 100 - (100 / (1 + rs))

rsi_val = float(rsi.iloc[-1])
rsi_prev = float(rsi.iloc[-2]) if len(rsi) > 1 else rsi_val
print(f"RSI(8) current: {rsi_val:.1f}")
print(f"RSI(8) previous: {rsi_prev:.1f}")

# EMA9
ema9 = closes.ewm(span=9).mean()
ema9_last = float(ema9.iloc[-1])
print(f"EMA9: {ema9_last:.2f}")
print(f"Price vs EMA9: {'above' if wti_last > ema9_last else 'below'}")

# Last 5 bars direction
last5 = list(closes.iloc[-6:])
bar_colors = []
for i in range(1, len(last5)):
    if last5[i] > last5[i-1]:
        bar_colors.append('green')
    elif last5[i] < last5[i-1]:
        bar_colors.append('red')
    else:
        bar_colors.append('flat')
print(f"Last 5 bar colors: {bar_colors}")

consecutive_green = 0
for c in reversed(bar_colors):
    if c == 'green':
        consecutive_green += 1
    else:
        break
print(f"Consecutive green bars: {consecutive_green}")

# Volume ratio
vol = wti['Volume']
if isinstance(vol.iloc[-1], pd.Series):
    vol = vol.iloc[:, 0]
vol_vals = vol.values.astype(float)
if len(vol_vals) > 5 and vol_vals[-6:-1].mean() > 0:
    vol_ratio = vol_vals[-1] / vol_vals[-6:-1].mean()
else:
    vol_ratio = 0
print(f"Volume ratio: {vol_ratio:.2f}")

# WTI vs baseline
base = 97.21
wti_vs_base = ((wti_last - base) / base) * 100
print(f"WTI vs $97.21 baseline: {wti_vs_base:+.2f}%")

# Session low
recent_closes = closes.iloc[-12:] if len(closes) >= 12 else closes
session_low = float(recent_closes.min())
bounce_from_low = ((wti_last - session_low) / session_low) * 100
print(f"Session low: {session_low:.2f}")
print(f"Bounce from low: {bounce_from_low:.2f}%")

# Signal detection
bounce_signal = False
signal_reason = ""

if consecutive_green >= 2 and rsi_val < 10 and rsi_val > rsi_prev:
    bounce_signal = True
    signal_reason = f"{consecutive_green} green bars, RSI rising from {rsi_val:.1f}"

if not bounce_signal and wti_last > 98 and rsi_val > 10:
    bounce_signal = True
    signal_reason = f"WTI>${{98}} (${wti_last:.2f}), RSI={rsi_val:.1f}"

if not bounce_signal and bounce_from_low >= 0.5 and vol_ratio > 1.0:
    bounce_signal = True
    signal_reason = f"Bounce +{bounce_from_low:.1f}% from low, vol ratio {vol_ratio:.2f}"

print(f"\nBounce signal: {bounce_signal}")
print(f"Reason: {signal_reason}")

result = {
    "wti": round(wti_last, 2),
    "hou": round(hou_last, 2),
    "rsi": round(rsi_val, 1),
    "rsi_prev": round(rsi_prev, 1),
    "ema9": round(ema9_last, 2),
    "consecutive_green": consecutive_green,
    "vol_ratio": round(vol_ratio, 2),
    "wti_vs_base": round(wti_vs_base, 2),
    "bounce_from_low": round(bounce_from_low, 2),
    "signal": bounce_signal,
    "reason": signal_reason
}
print(f"\nFINAL_DATA={json.dumps(result)}")
