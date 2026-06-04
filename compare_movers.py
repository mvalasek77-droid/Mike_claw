#!/usr/bin/env python3
"""Compare WTI vs RGTI next-hour move potential."""
import numpy as np
import yfinance as yf
import json
from mtf_wave_quantifier import get_mtf_regime

def analyze(ticker, symbol):
    df = yf.Ticker(symbol).history(period="30d", interval="1h")
    if df.empty:
        return None
    c = df['Close'].values
    h = df['High'].values
    l = df['Low'].values
    v = df['Volume'].values
    price = float(c[-1])
    
    # 1H volatility
    recent = c[-50:] if len(c) >= 50 else c
    rets = np.diff(recent) / recent[:-1] * 100
    avg_hr = float(np.mean(np.abs(rets)))
    
    # Volume
    vol_recent = float(v[-6:].mean())
    vol_avg = float(v[-48:].mean()) if len(v) >= 48 else float(v.mean())
    vol_ratio = vol_recent / vol_avg if vol_avg > 0 else 1
    
    # RSI
    delta = np.diff(c[-20:])
    gain = np.where(delta > 0, delta, 0)
    loss = np.where(delta < 0, -delta, 0)
    avg_g = float(np.mean(gain))
    avg_l = max(float(np.mean(loss)), 0.01)
    rsi = 100 - 100/(1 + avg_g/avg_l)
    
    # ATR
    tr = np.maximum(h[1:]-l[1:], np.maximum(np.abs(h[1:]-c[:-1]), np.abs(l[1:]-c[:-1])))
    atr = float(np.mean(tr[-14:])) if len(tr) >= 14 else float(np.mean(tr))
    atr_pct = atr / price * 100
    
    # Trend + regime
    from realtime_wave_scanner import detect_1h_trend, detect_1h_waves, compute_1h_distribution, compute_floor_ceiling, find_wave_position
    trend = detect_1h_trend(c)
    cycles = detect_1h_waves(c, h, l, trend)
    dist = compute_1h_distribution(cycles)
    fc = compute_floor_ceiling(price, trend, dist, float(np.max(h[-48:])), float(np.min(l[-48:])))
    wp = find_wave_position(c, trend, cycles)
    regime, align = get_mtf_regime(ticker)
    
    # Momentum (last 3h move)
    if len(c) >= 4:
        mom_3h = (c[-1] - c[-4]) / c[-4] * 100
    else:
        mom_3h = 0
    
    # Near boundary bonus
    nearest = min(fc.floor_pct, fc.ceiling_pct)
    
    # Move potential score (0-10)
    score = 0
    # Volatility base
    score += min(3, avg_hr)  # up to 3 pts for volatility
    # Volume confirms
    if vol_ratio > 1.5: score += 1
    elif vol_ratio > 1.0: score += 0.5
    # Near floor/ceiling = imminent move
    if nearest < 1: score += 2
    elif nearest < 3: score += 1
    elif nearest < 5: score += 0.5
    # RSI extreme = move incoming
    if rsi > 70 or rsi < 30: score += 1.5
    elif rsi > 60 or rsi < 40: score += 0.5
    # Momentum accelerating
    if abs(mom_3h) > avg_hr * 2: score += 1
    # In pullback phase (about to reverse into extension)
    if wp.phase == 'pullback' and wp.bars_in > 2: score += 0.5
    
    return {
        'ticker': ticker, 'price': round(price, 2),
        'trend_1h': trend, 'regime': regime, 'align': align,
        'phase': wp.phase, 'bars_in': wp.bars_in, 'moved_pct': wp.current_amplitude_pct,
        'floor': fc.floor, 'ceiling': fc.ceiling,
        'floor_pct': fc.floor_pct, 'ceiling_pct': fc.ceiling_pct,
        'nearest': round(nearest, 2), 'nearest_lbl': 'FLOOR' if fc.floor_pct < fc.ceiling_pct else 'CEILING',
        'avg_hr_move': round(avg_hr, 2), 'atr_pct': round(atr_pct, 2),
        'vol_ratio': round(vol_ratio, 2), 'rsi_1h': round(rsi, 1),
        'mom_3h': round(mom_3h, 2), 'n_cycles': dist.get('n', 0),
        'move_score': round(score, 1),
        'expected_move_1h': round(avg_hr * (1 + (1.5 if nearest < 2 else 0.5 if nearest < 5 else 0)), 2),
    }

w = analyze('WTI', 'CL=F')
r = analyze('RGTI', 'RGTI')

print("=" * 50)
for label, d in [("WTI", w), ("RGTI", r)]:
    print(f"\n{label} ${d['price']}")
    print(f"  1H: {d['trend_1h']} | Regime: {d['regime']} {d['align']}")
    print(f"  Phase: {d['phase']} ({d['bars_in']}h) | moved {d['moved_pct']}%")
    print(f"  Floor: ${d['floor']} ({d['floor_pct']}%) | Ceiling: ${d['ceiling']} ({d['ceiling_pct']}%)")
    print(f"  Nearest: {d['nearest']}% to {d['nearest_lbl']}")
    print(f"  Avg 1H move: {d['avg_hr_move']}% | ATR: {d['atr_pct']}% | Vol: {d['vol_ratio']}x")
    print(f"  RSI: {d['rsi_1h']} | Momentum 3h: {d['mom_3h']}%")
    print(f"  ⚡ MOVE SCORE: {d['move_score']}/10 | Expected 1H: ±{d['expected_move_1h']}%")

winner = "WTI" if w['move_score'] > r['move_score'] else "RGTI"
margin = abs(w['move_score'] - r['move_score'])
print(f"\n🏆 **{winner}** moves more next hour (score +{margin:.1f})")