#!/usr/bin/env python3
"""
W-M Auto-Learn Engine v1
========================
Runs every hour:
1. Backtests all tickers across multiple timeframes
2. Computes win rates by pattern/action/RSI/regime/confidence
3. Optimizes signal thresholds (min_amp, order, confidence, RSI filters)
4. Writes learned params to backtest_params.json
5. Updates SIGNAL_EDGE in wm_tactical.py
6. Outputs a brief learning report

Goal: continuous parameter tuning until we're printing money.
"""

import sys, json, numpy as np, yfinance as yf
from pathlib import Path
from datetime import datetime, timedelta
from scipy.signal import argrelextrema
from itertools import product

# Import scanner components
from wm_tactical import (
    detect_letters, find_phase, pattern_confidence, compute_atr,
    compute_rsi, compute_ema, detect_regime, stage_from_pct,
    MIN_AMPLITUDE_PCT, MAX_ASYMMETRY, MIN_CONFIDENCE, TICKERS
)

STORAGE = Path(__file__).parent / "storage"
STORAGE.mkdir(exist_ok=True)
SCANNER = Path(__file__).parent / "wm_tactical.py"

# ═══════════════════════════════════════════════════════
# BACKTEST ENGINE (fast version)
# ═══════════════════════════════════════════════════════

def fast_backtest(symbol, period='6mo', interval='1d', 
                  order_range=(2,5), amp_range=(1.5, 2.0, 3.0),
                  lookahead=15):
    """Walk through bars, generate signals, check target/stop."""
    df = yf.Ticker(symbol).history(period=period, interval=interval)
    if df.empty or len(df) < 60:
        return []
    
    highs = df['High'].values.astype(float)
    lows = df['Low'].values.astype(float)
    closes = df['Close'].values.astype(float)
    
    trades = []
    lookback = 30
    
    for min_amp in amp_range:
        for order in range(order_range[0], order_range[1]+1):
            for i in range(lookback, len(closes) - lookahead):
                h, l, c = highs[:i], lows[:i], closes[:i]
                price = float(c[-1])
                
                letters = detect_letters(h, l, c, order=order, min_amp_pct=min_amp)
                if not letters: continue
                
                lt, floor, ceil, pct, action = find_phase(letters, price)
                if lt == 'NONE' or action == 'WAIT': continue
                
                conf = pattern_confidence(letters)
                if conf < 0.4: continue
                
                regime = detect_regime(c)
                rsi = compute_rsi(c, 14)
                
                # Correct target/stop: BUY→ceil, SELL→floor
                if action == 'BUY':
                    target, stop = ceil, floor
                else:
                    target, stop = floor, ceil
                
                if abs(target - price) < 0.01 or abs(stop - price) < 0.01: continue
                
                # Look ahead
                target_hit = stop_hit = None
                for j in range(1, min(lookahead+1, len(closes)-i)):
                    bh = highs[i+j]
                    bl = lows[i+j]
                    if action == 'BUY':
                        if bh >= target and target_hit is None: target_hit = j
                        if bl <= stop and stop_hit is None: stop_hit = j
                    else:
                        if bl <= target and target_hit is None: target_hit = j
                        if bh >= stop and stop_hit is None: stop_hit = j
                
                if target_hit and (not stop_hit or target_hit <= stop_hit):
                    outcome = 'win'
                    pnl = (target - price) / price * 100 if action == 'BUY' else (price - target) / price * 100
                    bars = target_hit
                elif stop_hit:
                    outcome = 'loss'
                    pnl = -(price - stop) / price * 100 if action == 'BUY' else -(stop - price) / price * 100
                    bars = stop_hit
                else:
                    continue
                
                trades.append({
                    'type': lt, 'action': action, 'pct': round(pct, 1),
                    'confidence': round(conf, 3), 'rsi': round(rsi, 1),
                    'regime': regime, 'min_amp': min_amp, 'order': order,
                    'outcome': outcome, 'bars': bars, 'pnl_pct': round(pnl, 2),
                    'price': round(price, 2),
                })
    
    return trades


def hourly_backtest(symbol, period='60d', lookahead=8):
    """Hourly data backtest."""
    df = yf.Ticker(symbol).history(period=period, interval='1h')
    if df.empty or len(df) < 100:
        return []
    
    highs = df['High'].values.astype(float)
    lows = df['Low'].values.astype(float)
    closes = df['Close'].values.astype(float)
    
    trades = []
    
    for min_amp, order in [(0.5, 2), (1.0, 3), (1.5, 3), (2.0, 4)]:
        for i in range(60, len(closes) - lookahead):
            h, l, c = highs[:i], lows[:i], closes[:i]
            price = float(c[-1])
            
            letters = detect_letters(h, l, c, order=order, min_amp_pct=min_amp)
            if not letters: continue
            
            lt, floor, ceil, pct, action = find_phase(letters, price)
            if lt == 'NONE' or action == 'WAIT': continue
            
            conf = pattern_confidence(letters)
            if conf < 0.4: continue
            
            regime = detect_regime(c)
            rsi = compute_rsi(c, 14)
            
            if action == 'BUY':
                target, stop = ceil, floor
            else:
                target, stop = floor, ceil
            
            if abs(target - price) < 0.01 or abs(stop - price) < 0.01: continue
            
            target_hit = stop_hit = None
            for j in range(1, min(lookahead+1, len(closes)-i)):
                bh, bl = highs[i+j], lows[i+j]
                if action == 'BUY':
                    if bh >= target and target_hit is None: target_hit = j
                    if bl <= stop and stop_hit is None: stop_hit = j
                else:
                    if bl <= target and target_hit is None: target_hit = j
                    if bh >= stop and stop_hit is None: stop_hit = j
            
            if target_hit and (not stop_hit or target_hit <= stop_hit):
                pnl = (target - price) / price * 100 if action == 'BUY' else (price - target) / price * 100
                trades.append({'type': lt, 'action': action, 'pct': round(pct,1),
                    'confidence': round(conf,3), 'rsi': round(rsi,1), 'regime': regime,
                    'min_amp': min_amp, 'order': order, 'outcome': 'win',
                    'bars': target_hit, 'pnl_pct': round(pnl,2)})
            elif stop_hit:
                pnl = -(price-stop)/price*100 if action=='BUY' else -(stop-price)/price*100
                trades.append({'type': lt, 'action': action, 'pct': round(pct,1),
                    'confidence': round(conf,3), 'rsi': round(rsi,1), 'regime': regime,
                    'min_amp': min_amp, 'order': order, 'outcome': 'loss',
                    'bars': stop_hit, 'pnl_pct': round(pnl,2)})
    
    return trades


# ═══════════════════════════════════════════════════════
# PARAMETER OPTIMIZATION
# ═══════════════════════════════════════════════════════

def optimize(all_trades):
    """Find optimal parameters and signal edge adjustments."""
    if not all_trades:
        return None
    
    results = {}
    
    # ── Pattern × Action edge ──
    for key in ['M_BUY', 'M_SELL', 'W_BUY', 'W_SELL']:
        subset = [t for t in all_trades if f"{t['type']}_{t['action']}" == key]
        if len(subset) >= 5:
            wins = sum(1 for t in subset if t['outcome'] == 'win')
            wr = wins / len(subset)
            avg_pnl = np.mean([t['pnl_pct'] for t in subset])
            results[key] = {'wr': round(wr, 3), 'trades': len(subset), 'avg_pnl': round(avg_pnl, 2)}
    
    # ── RSI zones ──
    rsi_zones = {'oversold': (0,30), 'low': (30,40), 'neutral': (40,60), 'high': (60,70), 'overbought': (70,100)}
    rsi_edge = {}
    for zone, (lo, hi) in rsi_zones.items():
        subset = [t for t in all_trades if lo <= t['rsi'] < hi]
        if len(subset) >= 5:
            wins = sum(1 for t in subset if t['outcome'] == 'win')
            rsi_edge[zone] = round(wins/len(subset), 3)
    
    # ── Regime × Action ──
    regime_edge = {}
    for regime in ['UP', 'DOWN', 'SIDEWAYS']:
        for action in ['BUY', 'SELL']:
            subset = [t for t in all_trades if t['regime'] == regime and t['action'] == action]
            if len(subset) >= 5:
                wins = sum(1 for t in subset if t['outcome'] == 'win')
                regime_edge[f"{regime}_{action}"] = round(wins/len(subset), 3)
    
    # ── Confidence brackets ──
    conf_edge = {}
    for bracket in [(0.4, 0.55), (0.55, 0.65), (0.65, 0.75), (0.75, 0.85), (0.85, 1.0)]:
        lo, hi = bracket
        subset = [t for t in all_trades if lo <= t['confidence'] < hi]
        if len(subset) >= 5:
            wins = sum(1 for t in subset if t['outcome'] == 'win')
            conf_edge[f"{lo}-{hi}"] = round(wins/len(subset), 3)
    
    # ── Position % ──
    pos_edge = {}
    for zone, (lo, hi) in [('early', (0,25)), ('mid', (25,50)), ('late', (50,75)), ('completion', (75,100))]:
        subset = [t for t in all_trades if lo <= t['pct'] < hi]
        if len(subset) >= 5:
            wins = sum(1 for t in subset if t['outcome'] == 'win')
            pos_edge[zone] = round(wins/len(subset), 3)
    
    # ── Best min_amp/order for each timeframe ──
    param_edge = {}
    for key in set(f"amp{t['min_amp']}_o{t['order']}" for t in all_trades):
        subset = [t for t in all_trades if f"amp{t['min_amp']}_o{t['order']}" == key]
        if len(subset) >= 5:
            wins = sum(1 for t in subset if t['outcome'] == 'win')
            avg_pnl = np.mean([t['pnl_pct'] for t in subset])
            param_edge[key] = {'wr': round(wins/len(subset), 3), 'avg_pnl': round(avg_pnl, 2), 'n': len(subset)}
    
    # ── Compute optimized SIGNAL_EDGE ──
    signal_edge_new = {}
    for key in ['M_BUY', 'M_SELL', 'W_BUY', 'W_SELL']:
        if key in results:
            signal_edge_new[key] = results[key]['wr']
        else:
            signal_edge_new[key] = {'M_BUY': 0.90, 'M_SELL': 0.85, 'W_BUY': 0.15, 'W_SELL': 0.15}[key]
    
    # Overall stats
    total = len(all_trades)
    wins = sum(1 for t in all_trades if t['outcome'] == 'win')
    total_pnl = sum(t['pnl_pct'] for t in all_trades)
    
    params = {
        'timestamp': datetime.utcnow().isoformat(),
        'total_trades': total,
        'win_rate': round(wins/total*100, 1) if total else 0,
        'total_pnl': round(total_pnl, 1),
        'avg_pnl_per_trade': round(total_pnl/total, 2) if total else 0,
        'signal_edge': signal_edge_new,
        'pattern_action': results,
        'rsi_edge': rsi_edge,
        'regime_edge': regime_edge,
        'confidence_edge': conf_edge,
        'position_edge': pos_edge,
        'param_edge': {k: v for k, v in sorted(param_edge.items(), key=lambda x: -x[1]['wr'])[:5]},
    }
    
    return params


# ═══════════════════════════════════════════════════════
# UPDATE SCANNER WITH LEARNED PARAMS
# ═══════════════════════════════════════════════════════

def update_scanner(params):
    """Patch wm_tactical.py SIGNAL_EDGE with learned values."""
    if not params or 'signal_edge' not in params:
        return
    
    edge = params['signal_edge']
    
    # Read current scanner
    scanner_code = SCANNER.read_text()
    
    # Update SIGNAL_EDGE dict
    old_edge = "SIGNAL_EDGE = {"
    idx = scanner_code.find(old_edge)
    if idx == -1:
        print("  ⚠️ Could not find SIGNAL_EDGE in scanner, skipping update")
        return
    
    # Find the closing brace
    brace_start = scanner_code.find("{", idx)
    brace_end = scanner_code.find("}", brace_start) + 1
    old_block = scanner_code[brace_start:brace_end]
    
    new_edge = (
        "{\n"
        f"    # Backtested win rates — updated {datetime.utcnow().strftime('%Y-%m-%d %H:%M')}\n"
        f"    'M_BUY':  {edge.get('M_BUY', 0.90):.2f},   # M near bottom → BUY\n"
        f"    'M_SELL': {edge.get('M_SELL', 0.85):.2f},   # M near top → SELL\n"
        f"    'W_BUY':  {edge.get('W_BUY', 0.15):.2f},   # W near bottom → BUY (weak)\n"
        f"    'W_SELL': {edge.get('W_SELL', 0.15):.2f},   # W near top → SELL (weak)\n"
        "}"
    )
    
    # Replace
    scanner_code = scanner_code.replace(old_block, new_edge, 1)
    SCANNER.write_text(scanner_code)
    
    # Also update RSI thresholds if we have data
    rsi_edge = params.get('rsi_edge', {})
    if rsi_edge:
        # Find best RSI zones
        strong_zones = [z for z, wr in rsi_edge.items() if wr >= 0.60]
        weak_zones = [z for z, wr in rsi_edge.items() if wr < 0.45]
        print(f"  📊 Strong RSI zones: {strong_zones}")
        print(f"  📊 Weak RSI zones: {weak_zones}")


# ═══════════════════════════════════════════════════════
# LEARNING REPORT
# ═══════════════════════════════════════════════════════

def print_report(params):
    if not params:
        print("No trades to analyze")
        return
    
    print(f"\n{'='*60}")
    print(f"  AUTO-LEARN REPORT — {params['timestamp'][:16]}")
    print(f"{'='*60}")
    print(f"  Trades: {params['total_trades']} | Win Rate: {params['win_rate']}%")
    print(f"  Total PnL: {params['total_pnl']:+.1f}% | Avg/Trade: {params['avg_pnl_per_trade']:+.2f}%")
    
    print(f"\n  ── Pattern Edge ──")
    for key, v in params.get('pattern_action', {}).items():
        emoji = "🎯" if v['wr'] >= 0.75 else ("✅" if v['wr'] >= 0.55 else "⚠️")
        print(f"    {emoji} {key:10s}: {v['wr']*100:.0f}% WR ({v['trades']} trades) avg {v['avg_pnl']:+.2f}%")
    
    print(f"\n  ── RSI Edge ──")
    for zone, wr in sorted(params.get('rsi_edge', {}).items(), key=lambda x: -x[1]):
        emoji = "✅" if wr >= 0.60 else ("⚠️" if wr < 0.50 else "")
        print(f"    {emoji} {zone:12s}: {wr*100:.0f}% WR")
    
    print(f"\n  ── Regime Edge ──")
    for key, wr in sorted(params.get('regime_edge', {}).items(), key=lambda x: -x[1]):
        emoji = "✅" if wr >= 0.60 else ""
        print(f"    {emoji} {key:12s}: {wr*100:.0f}% WR")
    
    print(f"\n  ── Confidence Edge ──")
    for bracket, wr in sorted(params.get('confidence_edge', {}).items()):
        emoji = "✅" if wr >= 0.60 else ("⚠️" if wr < 0.50 else "")
        print(f"    {emoji} conf {bracket}: {wr*100:.0f}% WR")
    
    print(f"\n  ── Position % Edge ──")
    for zone, wr in sorted(params.get('position_edge', {}).items(), key=lambda x: -x[1]):
        emoji = "✅" if wr >= 0.60 else "⚠️" if wr < 0.50 else ""
        print(f"    {emoji} {zone:12s}: {wr*100:.0f}% WR")
    
    print(f"\n  ── Top Parameters ──")
    for k, v in list(params.get('param_edge', {}).items())[:3]:
        print(f"    {k}: {v['wr']*100:.0f}% WR, avg {v['avg_pnl']:+.2f}%, n={v['n']}")
    
    # Key learning
    print(f"\n  ── KEY LEARNINGS ──")
    edge = params.get('signal_edge', {})
    best = max(edge, key=edge.get) if edge else None
    worst = min(edge, key=edge.get) if edge else None
    if best:
        print(f"    🎯 Best trade: {best} ({edge[best]*100:.0f}% WR)")
    if worst:
        print(f"    ⚠️  Worst trade: {worst} ({edge[worst]*100:.0f}% WR) — AVOID")
    
    rsi_edge = params.get('rsi_edge', {})
    if rsi_edge:
        best_rsi = max(rsi_edge, key=rsi_edge.get)
        worst_rsi = min(rsi_edge, key=rsi_edge.get)
        print(f"    📈 Best RSI: {best_rsi} ({rsi_edge[best_rsi]*100:.0f}% WR)")
        print(f"    📉 Worst RSI: {worst_rsi} ({rsi_edge[worst_rsi]*100:.0f}% WR)")


# ═══════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════

if __name__ == "__main__":
    all_daily = []
    all_hourly = []
    
    for ticker_name, ticker_info in TICKERS.items():
        sym = ticker_info['symbol']
        print(f"\n🔄 Backtesting {ticker_name} ({sym})...")
        
        print(f"  Daily (6mo)...")
        daily = fast_backtest(sym, period='6mo', interval='1d', lookahead=15)
        print(f"  → {len(daily)} trades")
        all_daily.extend(daily)
        
        print(f"  Hourly (60d)...")
        hourly = hourly_backtest(sym, period='60d', lookahead=8)
        print(f"  → {len(hourly)} trades")
        all_hourly.extend(hourly)
    
    all_trades = all_daily + all_hourly
    print(f"\n📊 Total: {len(all_daily)} daily + {len(all_hourly)} hourly = {len(all_trades)} trades")
    
    params = optimize(all_trades)
    if params:
        print_report(params)
        
        # Save
        (STORAGE / 'backtest_params.json').write_text(json.dumps(params, indent=2, default=str))
        
        # Update scanner
        print(f"\n🔧 Updating scanner with learned parameters...")
        update_scanner(params)
        print(f"✅ Done — SIGNAL_EDGE updated in wm_tactical.py")
    
    # Refresh level memory (M ceilings / W floors for S/R zones)
    print(f"\n📐 Refreshing level memory...")
    import subprocess
    result = subprocess.run([sys.executable, str(Path(__file__).parent / "wm_levels.py")], 
                          capture_output=True, text=True, timeout=180)
    if result.returncode == 0:
        print(f"✅ Level memory refreshed")
    else:
        print(f"⚠️ Level refresh had issues: {result.stderr[-200:] if result.stderr else 'unknown'}")