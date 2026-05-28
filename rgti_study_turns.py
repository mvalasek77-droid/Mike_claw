#!/usr/bin/env python3
"""Study RGTI 2-day turns using trend lines."""
import yfinance as yf
import pandas as pd
import numpy as np

t = yf.Ticker('RGTI')
h5m = t.history(period='2d', interval='5m')

close = h5m['Close'].values.astype(float)
high = h5m['High'].values.astype(float)
low = h5m['Low'].values.astype(float)
open_ = h5m['Open'].values.astype(float)
volume = h5m['Volume'].values.astype(float)

# Find swing points (lookback = 5 bars each side)
lookback = 5
swing_highs = []
swing_lows = []

for i in range(lookback, len(high) - lookback):
    is_sh = all(high[i] >= high[i-j] for j in range(1, lookback+1)) and \
            all(high[i] >= high[i+j] for j in range(1, lookback+1))
    if is_sh:
        swing_highs.append({"idx": i, "price": high[i], "time": h5m.index[i].strftime('%m/%d %H:%M'), "vol": volume[i]/1e6})

    is_sl = all(low[i] <= low[i-j] for j in range(1, lookback+1)) and \
            all(low[i] <= low[i+j] for j in range(1, lookback+1))
    if is_sl:
        swing_lows.append({"idx": i, "price": low[i], "time": h5m.index[i].strftime('%m/%d %H:%M'), "vol": volume[i]/1e6})

print("=== SWING HIGHS (turns DOWN) ===")
for s in swing_highs:
    print(f'  {s["time"]} | ${s["price"]:.2f} | Vol: {s["vol"]:.1f}M')

print('\n=== SWING LOWS (turns UP) ===')
for s in swing_lows:
    print(f'  {s["time"]} | ${s["price"]:.2f} | Vol: {s["vol"]:.1f}M')

# Build trend lines and analyze what happened at each touch/break
print(f'\n=== UPTREND LINES (support from swing lows) ===')
for i in range(1, len(swing_lows) - 1):
    s1 = swing_lows[i-1]
    s2 = swing_lows[i]
    s3 = swing_lows[i+1]
    bars_diff = s2["idx"] - s1["idx"]
    if bars_diff <= 0:
        continue
    slope = (s2["price"] - s1["price"]) / bars_diff
    # Extend to s3
    bars_to_s3 = s3["idx"] - s2["idx"]
    trendline_val = s2["price"] + slope * bars_to_s3
    diff = s3["price"] - trendline_val
    status = "HELD" if diff >= -0.10 else "BROKE"
    # Move after s3
    next_hi = max(high[s3["idx"]:min(s3["idx"]+20, len(high))])
    move = next_hi - s3["price"]
    move_pct = move / s3["price"] * 100
    print(f'  L{s1["time"]} ${s1["price"]:.2f} -> L{s2["time"]} ${s2["price"]:.2f} -> TL@{s3["time"]} ${trendline_val:.2f} | Real ${s3["price"]:.2f} ({status} ${diff:+.2f}) | Bounce +${move:.2f} (+{move_pct:.1f}%)')

print(f'\n=== DOWNTREND LINES (resistance from swing highs) ===')
for i in range(1, len(swing_highs) - 1):
    s1 = swing_highs[i-1]
    s2 = swing_highs[i]
    s3 = swing_highs[i+1]
    bars_diff = s2["idx"] - s1["idx"]
    if bars_diff <= 0:
        continue
    slope = (s2["price"] - s1["price"]) / bars_diff
    bars_to_s3 = s3["idx"] - s2["idx"]
    trendline_val = s2["price"] + slope * bars_to_s3
    diff = s3["price"] - trendline_val
    status = "HELD" if diff <= 0.10 else "BROKE"
    next_lo = min(low[s3["idx"]:min(s3["idx"]+20, len(low))])
    move = next_lo - s3["price"]
    move_pct = move / s3["price"] * 100
    print(f'  H{s1["time"]} ${s1["price"]:.2f} -> H{s2["time"]} ${s2["price"]:.2f} -> TL@{s3["time"]} ${trendline_val:.2f} | Real ${s3["price"]:.2f} ({status} ${diff:+.2f}) | Drop ${move:.2f} ({move_pct:.1f}%)')

# The KEY study: at every swing low, what signals were firing?
print(f'\n=== TURN SIGNAL ANALYSIS AT EACH SWING LOW ===')
c = pd.Series(close)
ema5 = c.ewm(span=5).mean()
ema8 = c.ewm(span=8).mean()
ema13 = c.ewm(span=13).mean()
ema21 = c.ewm(span=21).mean()

delta = c.diff()
for rsi_p in [2, 5, 8]:
    g = delta.where(delta > 0, 0).rolling(rsi_p).mean()
    l = (-delta.where(delta < 0, 0)).rolling(rsi_p).mean()
    h5m[f'RSI{rsi_p}'] = (100 - (100 / (1 + g / l))).values

macd_line = c.ewm(span=12).mean() - c.ewm(span=26).mean()
macd_sig = macd_line.ewm(span=9).mean()
macd_hist = macd_line - macd_sig
h5m['MACD_hist'] = macd_hist.values

for sl in swing_lows:
    idx = sl["idx"]
    t_str = sl["time"]
    price = sl["price"]

    # Signals at or near this low
    signals = []

    # Candle at the low
    bar_body = abs(close[idx] - open_[idx])
    bar_lower_wick = min(open_[idx], close[idx]) - low[idx]
    bar_upper_wick = high[idx] - max(open_[idx], close[idx])
    is_hammer = bar_lower_wick > bar_body * 2 and bar_lower_wick > bar_upper_wick
    is_green = close[idx] > open_[idx]

    if is_hammer:
        signals.append(f"HAMMER (wick ${bar_lower_wick:.2f})")
    if is_green:
        signals.append("GREEN bar")

    # Was prev bar red?
    if idx > 0 and close[idx-1] < open_[idx-1] and is_green:
        signals.append("RED->GREEN reversal")

    # RSI levels
    for rsi_p in [2, 5, 8]:
        col = f'RSI{rsi_p}'
        val = float(h5m[col].iloc[idx]) if not pd.isna(h5m[col].iloc[idx]) else 50
        prev_val = float(h5m[col].iloc[idx-1]) if idx > 0 and not pd.isna(h5m[col].iloc[idx-1]) else val
        if val < 20:
            signals.append(f"RSI{rsi_p}={val:.0f} EXTREME")
        elif val < 30:
            signals.append(f"RSI{rsi_p}={val:.0f} oversold")
        if val > prev_val and val < 40:
            signals.append(f"RSI{rsi_p} hooking UP ({prev_val:.0f}->{val:.0f})")

    # EMA proximity
    for ema_n, ema_v in [('5', ema5), ('8', ema8), ('13', ema13), ('21', ema21)]:
        ema_val = float(ema_v.iloc[idx])
        dist = abs(price - ema_val)
        if dist / price < 0.005:
            signals.append(f"AT EMA{ema_n} ${ema_val:.2f}")

    # Volume
    vol_avg = float(volume[max(0, idx-20):idx].mean()) if idx > 20 else 1
    vol_now = float(volume[idx])
    vol_r = vol_now / vol_avg if vol_avg > 0 else 0
    if vol_r > 2:
        signals.append(f"VOL SPIKE {vol_r:.1f}x")

    # MACD turn
    mh = float(h5m['MACD_hist'].iloc[idx]) if not pd.isna(h5m['MACD_hist'].iloc[idx]) else 0
    prev_mh = float(h5m['MACD_hist'].iloc[idx-1]) if idx > 0 and not pd.isna(h5m['MACD_hist'].iloc[idx-1]) else mh
    if mh > prev_mh and mh < 0:
        signals.append(f"MACD turning ({prev_mh:.3f}->{mh:.3f})")

    # Next move (the turn we're trying to catch)
    look_fwd = min(idx + 20, len(high))
    next_hi = max(high[idx:look_fwd])
    move_up = next_hi - price
    move_pct = move_up / price * 100

    # Trend line touch? Check if any uptrend line from prior lows is near
    tl_touch = ""
    for j in range(len(swing_lows)):
        sl2 = swing_lows[j]
        if sl2["idx"] >= idx:
            break
        if sl2["idx"] < idx - 60:  # too far back
            continue
        for k in range(j+1, len(swing_lows)):
            sl3 = swing_lows[k]
            if sl3["idx"] >= idx:
                break
            # Line from sl2 to sl3, what's the value at idx?
            bars_diff = sl3["idx"] - sl2["idx"]
            if bars_diff <= 0:
                continue
            slope = (sl3["price"] - sl2["price"]) / bars_diff
            tl_val = sl3["price"] + slope * (idx - sl3["idx"])
            if abs(price - tl_val) < 0.20:
                tl_touch = f"TL TOUCH ${tl_val:.2f} (from L{sl2['time']} ${sl2['price']:.2f}->L{sl3['time']} ${sl3['price']:.2f})"

    signals_str = " | ".join(signals) if signals else "none"
    print(f'\n  {t_str} ${price:.2f} -> +${move_up:.2f} (+{move_pct:.1f}%)')
    print(f'    Signals: {signals_str}')
    if tl_touch:
        print(f'    TREND LINE: {tl_touch}')

# Same for swing highs (for short entries)
print(f'\n=== TURN SIGNAL ANALYSIS AT EACH SWING HIGH ===')
for sh in swing_highs:
    idx = sh["idx"]
    t_str = sh["time"]
    price = sh["price"]

    signals = []
    bar_body = abs(close[idx] - open_[idx])
    bar_upper_wick = high[idx] - max(open_[idx], close[idx])
    bar_lower_wick = min(open_[idx], close[idx]) - low[idx]
    is_shooting = bar_upper_wick > bar_body * 2 and bar_upper_wick > bar_lower_wick
    is_red = close[idx] < open_[idx]

    if is_shooting:
        signals.append(f"SHOOTING STAR (wick ${bar_upper_wick:.2f})")
    if is_red:
        signals.append("RED bar")

    if idx > 0 and close[idx-1] > open_[idx-1] and is_red:
        signals.append("GREEN->RED reversal")

    for rsi_p in [2, 5, 8]:
        col = f'RSI{rsi_p}'
        val = float(h5m[col].iloc[idx]) if not pd.isna(h5m[col].iloc[idx]) else 50
        prev_val = float(h5m[col].iloc[idx-1]) if idx > 0 and not pd.isna(h5m[col].iloc[idx-1]) else val
        if val > 80:
            signals.append(f"RSI{rsi_p}={val:.0f} EXTREME")
        elif val > 70:
            signals.append(f"RSI{rsi_p}={val:.0f} overbought")
        if val < prev_val and val > 60:
            signals.append(f"RSI{rsi_p} hooking DOWN ({prev_val:.0f}->{val:.0f})")

    for ema_n, ema_v in [('5', ema5), ('8', ema8), ('13', ema13), ('21', ema21)]:
        ema_val = float(ema_v.iloc[idx])
        dist = abs(price - ema_val)
        if dist / price < 0.005:
            signals.append(f"AT EMA{ema_n} ${ema_val:.2f}")

    vol_avg = float(volume[max(0, idx-20):idx].mean()) if idx > 20 else 1
    vol_now = float(volume[idx])
    vol_r = vol_now / vol_avg if vol_avg > 0 else 0
    if vol_r > 2:
        signals.append(f"VOL SPIKE {vol_r:.1f}x")

    mh = float(h5m['MACD_hist'].iloc[idx]) if not pd.isna(h5m['MACD_hist'].iloc[idx]) else 0
    prev_mh = float(h5m['MACD_hist'].iloc[idx-1]) if idx > 0 and not pd.isna(h5m['MACD_hist'].iloc[idx-1]) else mh
    if mh < prev_mh and mh > 0:
        signals.append(f"MACD turning down ({prev_mh:.3f}->{mh:.3f})")

    look_fwd = min(idx + 20, len(low))
    next_lo = min(low[idx:look_fwd])
    move_dn = next_lo - price
    move_pct = move_dn / price * 100

    tl_touch = ""
    for j in range(len(swing_highs)):
        sh2 = swing_highs[j]
        if sh2["idx"] >= idx:
            break
        if sh2["idx"] < idx - 60:
            continue
        for k in range(j+1, len(swing_highs)):
            sh3 = swing_highs[k]
            if sh3["idx"] >= idx:
                break
            bars_diff = sh3["idx"] - sh2["idx"]
            if bars_diff <= 0:
                continue
            slope = (sh3["price"] - sh2["price"]) / bars_diff
            tl_val = sh3["price"] + slope * (idx - sh3["idx"])
            if abs(price - tl_val) < 0.20:
                tl_touch = f"TL TOUCH ${tl_val:.2f} (from H{sh2['time']} ${sh2['price']:.2f}->H{sh3['time']} ${sh3['price']:.2f})"

    signals_str = " | ".join(signals) if signals else "none"
    print(f'\n  {t_str} ${price:.2f} -> ${move_dn:.2f} ({move_pct:.1f}%)')
    print(f'    Signals: {signals_str}')
    if tl_touch:
        print(f'    TREND LINE: {tl_touch}')