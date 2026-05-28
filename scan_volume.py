#!/usr/bin/env python3
"""High-volume momentum scanner - find 3% daily upside candidates."""
import yfinance as yf
import pandas as pd
import numpy as np

tickers = [
    'RGTI', 'QBTS', 'IONQ', 'SMCI', 'SOUN', 'BBAI', 'RKLB', 'LUNR', 'ASTS', 'RDW',
    'NVDA', 'AMD', 'PLTR', 'MARA', 'RIOT', 'COIN', 'MSTR', 'HOOD', 'SOFI', 'RIVN',
    'VKTX', 'RXRX', 'PTNX',
    'BABA', 'PDD', 'NIO', 'XPEV', 'LI', 'BILI',
    'TSLA', 'INTC', 'LCID', 'NKLA', 'DJT', 'GME', 'AMC',
    'QMCO', 'DQT',
    'KULR', 'SAP', 'CRM',
    'CLSK', 'CLWR', 'BTBT',
]

tickers = list(set(tickers))
print(f'Scanning {len(tickers)} tickers...\n')

results = []
for ticker in tickers:
    try:
        t = yf.Ticker(ticker)
        hist = t.history(period='5d', interval='1d')
        if len(hist) < 2:
            continue
        info = t.info
        cur = float(hist['Close'].iloc[-1])
        prev = float(hist['Close'].iloc[-2])
        day_change = (cur - prev) / prev * 100
        vol = float(hist['Volume'].iloc[-1])
        avg_vol = info.get('averageVolume', 0)
        if avg_vol == 0:
            avg_vol = float(hist['Volume'].mean())
        vol_ratio = vol / avg_vol if avg_vol > 0 else 1
        close_5d_ago = float(hist['Close'].iloc[0])
        five_day = (cur - close_5d_ago) / close_5d_ago * 100
        day_high = float(hist['High'].iloc[-1])
        day_low = float(hist['Low'].iloc[-1])
        range_pct = (day_high - day_low) / day_low * 100
        upside_to_high = (day_high - cur) / cur * 100
        mcap = info.get('marketCap', 0)
        flt = info.get('floatShares', 0)
        short_r = info.get('shortRatio', 0) or 0
        closes = hist['Close']
        delta = closes.diff()
        gain = delta.where(delta > 0, 0).rolling(14).mean()
        loss = (-delta.where(delta < 0, 0)).rolling(14).mean()
        rsi14 = 100 - (100 / (1 + gain / loss))
        rsi_val = float(rsi14.iloc[-1]) if not rsi14.isna().iloc[-1] else 50
        results.append({
            'ticker': ticker, 'price': cur, 'day_chg': day_change,
            'vol': vol / 1e6, 'vol_ratio': vol_ratio, '5d_chg': five_day,
            'range': range_pct, 'upside_high': upside_to_high,
            'mcap_b': mcap / 1e9 if mcap else 0, 'float_m': flt / 1e6 if flt else 0,
            'short_ratio': short_r, 'day_high': day_high, 'day_low': day_low,
            'rsi14': rsi_val,
        })
    except Exception as e:
        pass

if not results:
    print('No results returned!')
    exit(1)

df = pd.DataFrame(results).sort_values('vol', ascending=False)

print('=== TOP 25 BY VOLUME ===')
hdr = f'{"Ticker":<8} {"Price":>7} {"Day%":>7} {"Vol(M)":>8} {"VolR":>5} {"5D%":>7} {"Range":>6} {"UpHi":>6} {"RSI":>5} {"Short":>5}'
print(hdr)
print('-' * 85)
for _, r in df.head(25).iterrows():
    print(f'{r["ticker"]:<8} {r["price"]:>7.2f} {r["day_chg"]:>+6.1f}% {r["vol"]:>7.1f}M {r["vol_ratio"]:>4.1f}x {r["5d_chg"]:>+6.1f}% {r["range"]:>5.1f}% {r["upside_high"]:>+5.1f}% {r["rsi14"]:>4.0f} {r["short_ratio"]:>4.1f}')

print()
print('=== 3%+ UPSIDE CANDIDATES ===')
print('(high volume + abnormal activity + room to today\'s high)\n')
filtered = df[(df['vol'] > 5) & (df['vol_ratio'] > 1.2) & (df['upside_high'] >= 2)].sort_values('upside_high', ascending=False)
if len(filtered) == 0:
    print('Relaxing filters: vol > 3M, upside >= 1%...')
    filtered = df[(df['vol'] > 3) & (df['upside_high'] >= 1)].sort_values('upside_high', ascending=False)

for _, r in filtered.iterrows():
    score = r['vol_ratio'] * 0.3 + r['upside_high'] * 0.4 + max(0, r['5d_chg']) * 0.1 + r['range'] * 0.2
    print(f'{r["ticker"]:<8} ${r["price"]:.2f} | Day {r["day_chg"]:+.1f}% | Vol {r["vol"]:.0f}M ({r["vol_ratio"]:.1f}x) | Room to high +{r["upside_high"]:.1f}% | 5D {r["5d_chg"]:+.1f}% | RSI {r["rsi14"]:.0f} | Score {score:.1f}')

print('\n=== BEST 5 FOR 3% DAY PLAY ===')
top = filtered.head(5) if len(filtered) > 0 else df.head(5)
for _, r in top.iterrows():
    target_3pct = r['price'] * 1.03
    stop = r['price'] * 0.985
    print(f'  {r["ticker"]}: ${r["price"]:.2f} -> target ${target_3pct:.2f} (+3%) | Stop: ${stop:.2f} (-1.5%) | R:R 2:1')