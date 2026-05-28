import yfinance as yf
import numpy as np

t = yf.Ticker('RGTI')
hist_5m = t.history(period='1d', interval='5m')

close = hist_5m['Close']
high = hist_5m['High']
low = hist_5m['Low']
volume = hist_5m['Volume']

# 1. Micro EMA trend
ema5 = close.ewm(span=5).mean()
ema13 = close.ewm(span=13).mean()
ema21 = close.ewm(span=21).mean()

# 2. Micro RSI (8-period)
delta = close.diff()
gain = delta.where(delta > 0, 0).rolling(8).mean()
loss = (-delta.where(delta < 0, 0)).rolling(8).mean()
rsi8 = 100 - (100 / (1 + gain/loss))

# 3. VWAP
typical = (high + low + close) / 3
vwap = (typical * volume).cumsum() / volume.cumsum()

# 4. Volume profile
vol_avg = volume.rolling(20).mean()
current_vol_ratio = volume.iloc[-1] / vol_avg.iloc[-1] if vol_avg.iloc[-1] > 0 else 0

# 5. Micro MACD
macd_fast = close.ewm(span=5).mean() - close.ewm(span=13).mean()
macd_signal = macd_fast.ewm(span=5).mean()
macd_hist = macd_fast - macd_signal

# 6. Candle pattern detection (last 10 bars)
print('=== LAST 10 5-MIN BARS WITH SIGNALS ===')
for i in range(-10, 0):
    bar = hist_5m.iloc[i]
    o, h, l, c, v = bar['Open'], bar['High'], bar['Low'], bar['Close'], bar['Volume']
    body = c - o
    upper_wick = h - max(o, c)
    lower_wick = min(o, c) - l
    rng = h - l if h - l > 0 else 0.01
    
    pattern = ''
    if body > 0 and lower_wick > abs(body) * 1.5:
        pattern = 'HAMMER'
    elif body < 0 and upper_wick > abs(body) * 1.5:
        pattern = 'SHOOTING_STAR'
    elif abs(body) < rng * 0.1:
        pattern = 'DOJI'
    elif body > 0 and abs(body) > rng * 0.6:
        pattern = 'BULL_CANDLE'
    elif body < 0 and abs(body) > rng * 0.6:
        pattern = 'BEAR_CANDLE'
    elif body > 0 and upper_wick > abs(body):
        pattern = 'BULL_W_REJECTION'
    elif body < 0 and lower_wick > abs(body):
        pattern = 'BEAR_W_B-support'
    
    vol_r = v / vol_avg.iloc[-1] if vol_avg.iloc[-1] > 0 else 0
    
    ts = hist_5m.index[i].strftime('%H:%M')
    print(f'{ts} | O{o:.2f} H{h:.2f} L{l:.2f} C{c:.2f} | V:{v/1e6:.1f}M ({vol_r:.1f}x) | {pattern}')

print()
print('=== MICRO INDICATORS (current) ===')
print(f'Price:       ${close.iloc[-1]:.2f}')
print(f'EMA5:        ${ema5.iloc[-1]:.2f}')
print(f'EMA13:       ${ema13.iloc[-1]:.2f}')
print(f'EMA21:       ${ema21.iloc[-1]:.2f}')
print(f'VWAP:        ${vwap.iloc[-1]:.2f}')
print(f'RSI(8):      {rsi8.iloc[-1]:.1f}')
print(f'Vol ratio:   {current_vol_ratio:.1f}x avg')
print(f'Micro MACD:  {macd_fast.iloc[-1]:.4f}')
print(f'MACD Signal: {macd_signal.iloc[-1]:.4f}')
print(f'MACD Hist:   {macd_hist.iloc[-1]:.4f}')

# EMA alignment
if ema5.iloc[-1] > ema13.iloc[-1] > ema21.iloc[-1]:
    ema_trend = 'BULLISH ALIGNED (5>13>21)'
elif ema5.iloc[-1] < ema13.iloc[-1] < ema21.iloc[-1]:
    ema_trend = 'BEARISH ALIGNED (5<13<21)'
else:
    ema_trend = 'MIXED'
print(f'EMA Stack:   {ema_trend}')

# Price vs EMAs
dist_ema5 = ((close.iloc[-1] - ema5.iloc[-1]) / ema5.iloc[-1]) * 100
dist_ema13 = ((close.iloc[-1] - ema13.iloc[-1]) / ema13.iloc[-1]) * 100
print(f'Price vs EMA5:  {dist_ema5:+.2f}%')
print(f'Price vs EMA13: {dist_ema13:+.2f}%')

# 7. Volume flow (last 30 min)
recent_vol = volume.tail(6).sum()
total_vol = volume.sum()
print(f'\nVol last 30min:  {recent_vol/1e6:.1f}M ({recent_vol/total_vol*100:.1f}% of day)')
print(f'Total day vol:   {total_vol/1e6:.1f}M')

# 8. Buying vs selling pressure
up_vol = volume.where(close > close.shift(1), 0).tail(20).sum()
dn_vol = volume.where(close < close.shift(1), 0).tail(20).sum()
print(f'Buy vol (20bar): {up_vol/1e6:.1f}M')
print(f'Sell vol (20bar):{dn_vol/1e6:.1f}M')
if dn_vol > 0:
    print(f'Buy/Sell ratio:  {up_vol/dn_vol:.2f}')

# 9. Intraday phases
print('\n=== INTRADAY PHASES ===')
open_close = close.iloc[0]
spike_high = high.iloc[:6].max()
print(f'Opening spike: ${open_close:.2f} -> ${spike_high:.2f} (+${spike_high-open_close:.2f})')
consol_low = low.iloc[6:30].min()
consol_high = high.iloc[6:30].max()
print(f'Consolidation: ${consol_low:.2f} - ${consol_high:.2f}')

# Micro-trend (last 6 bars)
last6 = close.tail(6)
if last6.iloc[-1] > last6.iloc[0]:
    print(f'Micro trend: UP (${last6.iloc[0]:.2f} -> ${last6.iloc[-1]:.2f})')
elif last6.iloc[-1] < last6.iloc[0]:
    print(f'Micro trend: DOWN (${last6.iloc[0]:.2f} -> ${last6.iloc[-1]:.2f})')
else:
    print('Micro trend: FLAT')

# 10. Volume nodes (S/R)
print('\n=== VOLUME NODES (key S/R) ===')
vhs = hist_5m.tail(40)
vol_by_price = {}
for _, row in vhs.iterrows():
    for price in np.linspace(row['Low'], row['High'], num=10):
        p = round(price, 2)
        vol_by_price[p] = vol_by_price.get(p, 0) + row['Volume']/10

sorted_vp = sorted(vol_by_price.items(), key=lambda x: x[1], reverse=True)
top_vol_nodes = sorted_vp[:5]
for price, vol in sorted(top_vol_nodes, key=lambda x: x[0]):
    print(f'  ${price:.2f} - {vol/1e6:.1f}M shares')

# 11. Micro divergence check
print('\n=== DIVERGENCE CHECK ===')
last10_rsi = rsi8.tail(10).values
last10_close = close.tail(10).values
last10_macd = macd_hist.tail(10).values

# RSI divergence
if last10_close[-1] > last10_close[0] and last10_rsi[-1] < last10_rsi[0]:
    print('BEARISH RSI DIVERGENCE (price up, RSI down)')
elif last10_close[-1] < last10_close[0] and last10_rsi[-1] > last10_rsi[0]:
    print('BULLISH RSI DIVERGENCE (price down, RSI up)')
else:
    print('No RSI divergence detected')

# MACD divergence
if last10_close[-1] > last10_close[0] and last10_macd[-1] < last10_macd[0]:
    print('BEARISH MACD DIVERGENCE')
elif last10_close[-1] < last10_close[0] and last10_macd[-1] > last10_macd[0]:
    print('BULLISH MACD DIVERGENCE')
else:
    print('No MACD divergence')

# 12. Order block detection
print('\n=== ORDER BLOCKS ===')
# Look for strong moves (large body, large volume)
for i in range(-5, 0):
    bar = hist_5m.iloc[i]
    body = abs(bar['Close'] - bar['Open'])
    rng = bar['High'] - bar['Low'] if bar['High'] - bar['Low'] > 0 else 0.01
    vol_r = bar['Volume'] / vol_avg.iloc[-1] if vol_avg.iloc[-1] > 0 else 0
    if body/rng > 0.7 and vol_r > 1.5:
        direction = 'BULL' if bar['Close'] > bar['Open'] else 'BEAR'
        print(f'  {hist_5m.index[i].strftime("%H:%M")} {direction} OB at ${min(bar["Open"], bar["Close"]):.2f}-${max(bar["Open"], bar["Close"]):.2f} (Vol {vol_r:.1f}x)')

# 13. Next hour prediction
print('\n=== NEXT HOUR PREDICTION ===')
c = close.iloc[-1]
vwap_val = vwap.iloc[-1]
ema5_val = ema5.iloc[-1]
ema13_val = ema13.iloc[-1]
rsi_val = rsi8.iloc[-1]
macd_val = macd_hist.iloc[-1]

bull_score = 0
bear_score = 0
signals = []

# EMA stack
if ema5_val > ema13_val > ema21.iloc[-1]:
    bull_score += 2
    signals.append('EMA stack bullish')
elif ema5_val < ema13_val < ema21.iloc[-1]:
    bear_score += 2
    signals.append('EMA stack bearish')

# Price vs VWAP
if c > vwap_val:
    bull_score += 1
    signals.append(f'Price above VWAP (${vwap_val:.2f})')
else:
    bear_score += 1
    signals.append(f'Price below VWAP (${vwap_val:.2f})')

# RSI
if rsi_val > 80:
    bear_score += 2
    signals.append(f'RSI overbought ({rsi_val:.0f})')
elif rsi_val > 60:
    bull_score += 1
    signals.append(f'RSI bullish ({rsi_val:.0f})')
elif rsi_val < 20:
    bull_score += 2
    signals.append(f'RSI oversold ({rsi_val:.0f})')
elif rsi_val < 40:
    bear_score += 1
    signals.append(f'RSI bearish ({rsi_val:.0f})')

# MACD histogram
if macd_val > 0 and macd_val > macd_hist.iloc[-2]:
    bull_score += 1
    signals.append('MACD expanding bull')
elif macd_val < 0:
    bear_score += 1
    signals.append('MACD bearish')

# Volume trend
if current_vol_ratio > 1.5:
    bull_score += 1
    signals.append(f'High vol ({current_vol_ratio:.1f}x)')

# Micro trend
if last6.iloc[-1] > last6.iloc[0]:
    bull_score += 1
    signals.append('Micro trend UP')
else:
    bear_score += 1
    signals.append('Micro trend DOWN')

print(f'Bull Score: {bull_score}')
print(f'Bear Score: {bear_score}')
print(f'Signals: {", ".join(signals)}')

if bull_score >= bear_score + 3:
    bias = 'STRONG BULLISH'
elif bull_score > bear_score:
    bias = 'LEAN BULLISH'
elif bear_score >= bull_score + 3:
    bias = 'STRONG BEARISH'
elif bear_score > bull_score:
    bias = 'LEAN BEARISH'
else:
    bias = 'NEUTRAL / CHOPPY'

print(f'Bias: {bias}')

# Target calc
atr_5m = (high - low).rolling(14).mean().iloc[-1]
if bull_score > bear_score:
    t1 = c + atr_5m
    t2 = c + 2 * atr_5m
    s1 = c - atr_5m * 0.5
    s2 = c - atr_5m
else:
    t1 = c + atr_5m * 0.5
    t2 = c + atr_5m
    s1 = c - atr_5m * 0.5
    s2 = c - 2 * atr_5m

print(f'\n5min ATR: ${atr_5m:.2f}')
print(f'Target 1: ${t1:.2f}')
print(f'Target 2: ${t2:.2f}')
print(f'Support 1: ${s1:.2f}')
print(f'Support 2: ${s2:.2f}')