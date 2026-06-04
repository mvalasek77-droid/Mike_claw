#!/usr/bin/env python3
"""
W-M Tactical Backtester v1
============================
Walks through historical data, generates signals at each bar,
tracks whether target or stop was hit first, and computes win rate.

Outputs learned parameters that the tactical scanner can use.
"""

import sys, json, numpy as np, yfinance as yf
from pathlib import Path
from datetime import datetime, timedelta
from scipy.signal import argrelextrema
from itertools import product

# Import from the tactical scanner
from wm_tactical import (
    detect_letters, find_phase, pattern_confidence, compute_atr,
    compute_rsi, compute_ema, detect_regime, stage_from_pct,
    MIN_AMPLITUDE_PCT, MAX_ASYMMETRY, MIN_CONFIDENCE,
    COMPLETION_PROB, TICKERS
)

STORAGE = Path(__file__).parent / "storage"
STORAGE.mkdir(exist_ok=True)
RESULTS = STORAGE / "backtest_results"

# ═══════════════════════════════════════════════════════
# BACKTEST ENGINE
# ═══════════════════════════════════════════════════════

def backtest_symbol(symbol, tf='1d', period='1y', interval='1d',
                    order_range=(2,5), min_amp_range=(1.0, 2.0, 3.0),
                    lookahead_bars=20):
    """
    Walk through historical bars. At each bar, generate a signal
    using the last N bars. Then look ahead to see if target or stop is hit first.
    
    Returns list of trades: {bar, type, pct, action, target, stop, confidence,
                             outcome('win'/'loss'), bars_to_target, bars_to_stop,
                             pnl_pct, regime}
    """
    df = yf.Ticker(symbol).history(period=period, interval=interval)
    if df.empty or len(df) < 60:
        print(f"  Not enough data for {symbol} ({len(df)} bars)")
        return []
    
    highs = df['High'].values.astype(float)
    lows = df['Low'].values.astype(float)
    closes = df['Close'].values.astype(float)
    opens = df['Open'].values.astype(float)
    
    all_trades = []
    
    for min_amp in min_amp_range:
        for order in range(order_range[0], order_range[1]+1):
            trades = []
            
            # Walk through bars with enough lookback
            lookback = max(30, order * 6)
            
            for i in range(lookback, len(closes) - lookahead_bars):
                # Slice data up to bar i (no future peeking)
                h = highs[:i]
                l = lows[:i]
                c = closes[:i]
                price = float(c[-1])
                
                # Detect pattern
                letters = detect_letters(h, l, c, order=order, min_amp_pct=min_amp)
                if not letters: continue
                
                lt, floor, ceil, pct, action = find_phase(letters, price)
                if lt == 'NONE' or action == 'WAIT': continue
                
                conf = pattern_confidence(letters)
                if conf < MIN_CONFIDENCE: continue
                
                # Regime
                regime = detect_regime(c)
                
                # RSI
                rsi = compute_rsi(c, 14)
                
                # Target/stop: BUY targets UP (ceil), SELL targets DOWN (floor)
                # BUY: win = ceil hit first, loss = floor hit first
                # SELL: win = floor hit first, loss = ceil hit first
                if action == 'BUY':
                    target = ceil  # upside take-profit
                    stop = floor   # downside stop-loss
                else:  # SELL
                    target = floor   # downside take-profit (short)
                    stop = ceil      # upside stop-loss (short)
                
                # Skip if target == price or stop == price
                if target == price or stop == price: continue
                
                # ── Look ahead: did target or stop hit first? ──
                target_hit = None
                stop_hit = None
                
                for j in range(1, lookahead_bars + 1):
                    if i + j >= len(closes):
                        break
                    bar_high = highs[i + j]
                    bar_low = lows[i + j]
                    
                    # For BUY (W near bottom, M near completion):
                    #   target is above, stop is below
                    #   win = price reaches target first
                    #   loss = price reaches stop first
                    if action == 'BUY':
                        if bar_high >= target and target_hit is None:
                            target_hit = j
                        if bar_low <= stop and stop_hit is None:
                            stop_hit = j
                    
                    elif action == 'SELL':
                        if bar_low <= target and target_hit is None:
                            target_hit = j
                        if bar_high >= stop and stop_hit is None:
                            stop_hit = j
                
                # Outcome
                if target_hit is not None and (stop_hit is None or target_hit <= stop_hit):
                    outcome = 'win'
                    pnl_pct = (target - price) / price * 100 if action == 'BUY' else (price - target) / price * 100
                    bars = target_hit
                elif stop_hit is not None:
                    outcome = 'loss'
                    pnl_pct = -(stop - price) / price * 100 if action == 'BUY' else -(price - stop) / price * 100
                    bars = stop_hit
                else:
                    continue  # Neither hit in lookahead window
                
                trades.append({
                    'bar': i, 'type': lt, 'pct': round(pct, 1),
                    'action': action, 'target': round(target, 2),
                    'stop': round(stop, 2), 'confidence': round(conf, 3),
                    'rsi': round(rsi, 1), 'regime': regime,
                    'min_amp': min_amp, 'order': order,
                    'outcome': outcome, 'bars': bars,
                    'pnl_pct': round(pnl_pct, 2),
                    'price': round(price, 2),
                })
            
            all_trades.extend(trades)
    
    return all_trades


def analyze_trades(trades, label=""):
    """Analyze backtest results and print summary."""
    if not trades:
        print(f"\n  {label}: No trades generated")
        return {}
    
    wins = [t for t in trades if t['outcome'] == 'win']
    losses = [t for t in trades if t['outcome'] == 'loss']
    
    total = len(trades)
    win_count = len(wins)
    loss_count = len(losses)
    win_rate = win_count / total * 100 if total > 0 else 0
    
    avg_win_pnl = np.mean([t['pnl_pct'] for t in wins]) if wins else 0
    avg_loss_pnl = np.mean([abs(t['pnl_pct']) for t in losses]) if losses else 0
    avg_bars = np.mean([t['bars'] for t in trades])
    
    # Profit factor
    total_wins = sum(t['pnl_pct'] for t in wins) if wins else 0
    total_losses = sum(abs(t['pnl_pct']) for t in losses) if losses else 1
    profit_factor = total_wins / total_losses if total_losses > 0 else float('inf')
    
    # By pattern type
    by_type = {}
    for t in trades:
        key = f"{t['type']}_{t['action']}"
        by_type.setdefault(key, {'wins': 0, 'losses': 0, 'total': 0, 'pnl': 0})
        by_type[key]['total'] += 1
        if t['outcome'] == 'win':
            by_type[key]['wins'] += 1
        else:
            by_type[key]['losses'] += 1
        by_type[key]['pnl'] += t['pnl_pct']
    
    # By regime
    by_regime = {}
    for t in trades:
        r = t['regime']
        by_regime.setdefault(r, {'wins': 0, 'losses': 0, 'total': 0})
        by_regime[r]['total'] += 1
        if t['outcome'] == 'win':
            by_regime[r]['wins'] += 1
        else:
            by_regime[r]['losses'] += 1
    
    # By confidence bracket
    by_conf = {}
    for t in trades:
        bracket = f"{int(t['confidence']*10)/10:.1f}"
        by_conf.setdefault(bracket, {'wins': 0, 'losses': 0, 'total': 0})
        by_conf[bracket]['total'] += 1
        if t['outcome'] == 'win':
            by_conf[bracket]['wins'] += 1
        else:
            by_conf[bracket]['losses'] += 1
    
    # By pct bracket
    by_pct = {}
    for t in trades:
        if t['pct'] < 25:
            bracket = '0-25'
        elif t['pct'] < 50:
            bracket = '25-50'
        elif t['pct'] < 75:
            bracket = '50-75'
        else:
            bracket = '75-100'
        by_pct.setdefault(bracket, {'wins': 0, 'losses': 0, 'total': 0})
        by_pct[bracket]['total'] += 1
        if t['outcome'] == 'win':
            by_pct[bracket]['wins'] += 1
        else:
            by_pct[bracket]['losses'] += 1
    
    # By RSI zone
    by_rsi = {}
    for t in trades:
        if t['rsi'] < 30:
            zone = 'oversold'
        elif t['rsi'] < 40:
            zone = 'low'
        elif t['rsi'] < 60:
            zone = 'neutral'
        elif t['rsi'] < 70:
            zone = 'high'
        else:
            zone = 'overbought'
        by_rsi.setdefault(zone, {'wins': 0, 'losses': 0, 'total': 0})
        by_rsi[zone]['total'] += 1
        if t['outcome'] == 'win':
            by_rsi[zone]['wins'] += 1
        else:
            by_rsi[zone]['losses'] += 1
    
    # Best min_amp and order
    by_params = {}
    for t in trades:
        key = f"amp{t['min_amp']}_o{t['order']}"
        by_params.setdefault(key, {'wins': 0, 'losses': 0, 'total': 0, 'pnl': 0})
        by_params[key]['total'] += 1
        if t['outcome'] == 'win':
            by_params[key]['wins'] += 1
        else:
            by_params[key]['losses'] += 1
        by_params[key]['pnl'] += t['pnl_pct']
    
    # Print summary
    print(f"\n{'='*60}")
    print(f"  {label} BACKTEST RESULTS")
    print(f"{'='*60}")
    print(f"  Total trades: {total}")
    print(f"  Win rate: {win_rate:.1f}% ({win_count}W / {loss_count}L)")
    print(f"  Avg win: +{avg_win_pnl:.2f}% | Avg loss: -{avg_loss_pnl:.2f}%")
    print(f"  Profit factor: {profit_factor:.2f}")
    print(f"  Avg bars to exit: {avg_bars:.1f}")
    
    print(f"\n  ── By Pattern ──")
    for k, v in sorted(by_type.items(), key=lambda x: -x[1]['total']):
        wr = v['wins']/v['total']*100 if v['total'] else 0
        print(f"    {k:12s}: {v['wins']:3d}W/{v['losses']:3d}L ({wr:.0f}%) pnl={v['pnl']:+.1f}%")
    
    print(f"\n  ── By Regime ──")
    for k, v in sorted(by_regime.items(), key=lambda x: -x[1]['total']):
        wr = v['wins']/v['total']*100 if v['total'] else 0
        print(f"    {k:10s}: {v['wins']:3d}W/{v['losses']:3d}L ({wr:.0f}%)")
    
    print(f"\n  ── By Position % ──")
    for bracket in ['0-25', '25-50', '50-75', '75-100']:
        if bracket in by_pct:
            v = by_pct[bracket]
            wr = v['wins']/v['total']*100 if v['total'] else 0
            print(f"    {bracket:8s}: {v['wins']:3d}W/{v['losses']:3d}L ({wr:.0f}%)")
    
    print(f"\n  ── By RSI Zone ──")
    for zone in ['oversold', 'low', 'neutral', 'high', 'overbought']:
        if zone in by_rsi:
            v = by_rsi[zone]
            wr = v['wins']/v['total']*100 if v['total'] else 0
            print(f"    {zone:12s}: {v['wins']:3d}W/{v['losses']:3d}L ({wr:.0f}%)")
    
    print(f"\n  ── By Confidence ──")
    for k in sorted(by_conf.keys()):
        v = by_conf[k]
        wr = v['wins']/v['total']*100 if v['total'] else 0
        print(f"    conf={k}: {v['wins']:3d}W/{v['losses']:3d}L ({wr:.0f}%)")
    
    print(f"\n  ── Best Parameters ──")
    best_params = sorted(by_params.items(), key=lambda x: -x[1]['pnl']/max(x[1]['total'],1))
    for k, v in best_params[:5]:
        wr = v['wins']/v['total']*100 if v['total'] else 0
        avg_pnl = v['pnl']/v['total'] if v['total'] else 0
        print(f"    {k}: {v['wins']:3d}W/{v['losses']:3d}L ({wr:.0f}%) avg={avg_pnl:+.2f}%")
    
    # Key findings
    print(f"\n  ── KEY FINDINGS ──")
    
    # Best action+position combos
    best_combos = []
    for k, v in by_type.items():
        if v['total'] >= 5:
            wr = v['wins']/v['total']*100
            best_combos.append((k, wr, v['total']))
    best_combos.sort(key=lambda x: -x[1])
    if best_combos:
        best = best_combos[0]
        print(f"    Best combo: {best[0]} ({best[1]:.0f}% over {best[2]} trades)")
    
    # RSI edge
    best_rsi = None
    for zone, v in by_rsi.items():
        if v['total'] >= 3:
            wr = v['wins']/v['total']*100
            if best_rsi is None or wr > best_rsi[1]:
                best_rsi = (zone, wr, v['total'])
    if best_rsi:
        print(f"    Best RSI zone: {best_rsi[0]} ({best_rsi[1]:.0f}% over {best_rsi[2]} trades)")
    
    # Regime edge
    best_regime = None
    for regime, v in by_regime.items():
        if v['total'] >= 3:
            wr = v['wins']/v['total']*100
            if best_regime is None or wr > best_regime[1]:
                best_regime = (regime, wr, v['total'])
    if best_regime:
        print(f"    Best regime: {best_regime[0]} ({best_regime[1]:.0f}% over {best_regime[2]} trades)")
    
    return {
        'total': total, 'win_rate': win_rate, 'profit_factor': profit_factor,
        'avg_win': avg_win_pnl, 'avg_loss': avg_loss_pnl,
        'by_type': {k: v for k, v in by_type.items()},
        'by_regime': {k: v for k, v in by_regime.items()},
        'by_pct': {k: v for k, v in by_pct.items()},
        'by_rsi': {k: v for k, v in by_rsi.items()},
        'by_conf': {k: v for k, v in by_conf.items()},
        'by_params': {k: v for k, v in by_params.items()},
    }


def backtest_hourly(symbol, period='60d', lookahead_hours=8):
    """Backtest on 1h data — shorter timeframe, shorter lookahead."""
    df = yf.Ticker(symbol).history(period=period, interval='1h')
    if df.empty or len(df) < 100:
        print(f"  Not enough hourly data for {symbol}")
        return []
    
    highs = df['High'].values.astype(float)
    lows = df['Low'].values.astype(float)
    closes = df['Close'].values.astype(float)
    
    all_trades = []
    
    for min_amp, order in [(0.5, 2), (1.0, 3), (1.5, 3), (2.0, 4)]:
        for i in range(60, len(closes) - lookahead_hours):
            h = highs[:i]
            l = lows[:i]
            c = closes[:i]
            price = float(c[-1])
            
            letters = detect_letters(h, l, c, order=order, min_amp_pct=min_amp)
            if not letters: continue
            
            lt, floor, ceil, pct, action = find_phase(letters, price)
            if lt == 'NONE' or action == 'WAIT': continue
            
            conf = pattern_confidence(letters)
            if conf < MIN_CONFIDENCE: continue
            
            regime = detect_regime(c)
            rsi = compute_rsi(c, 14)
            
            # BUY targets UP (ceil), SELL targets DOWN (floor)
            if action == 'BUY':
                target, stop = ceil, floor
            else:  # SELL
                target, stop = floor, ceil
            
            if target == price or stop == price: continue
            
            # Look ahead
            target_hit = stop_hit = None
            for j in range(1, min(lookahead_hours + 1, len(closes) - i)):
                bar_high = highs[i + j]
                bar_low = lows[i + j]
                if action == 'BUY':
                    if bar_high >= target and target_hit is None: target_hit = j
                    if bar_low <= stop and stop_hit is None: stop_hit = j
                elif action == 'SELL':
                    if bar_low <= target and target_hit is None: target_hit = j
                    if bar_high >= stop and stop_hit is None: stop_hit = j
            
            if target_hit and (not stop_hit or target_hit <= stop_hit):
                outcome = 'win'
                pnl = (target - price) / price * 100 if action == 'BUY' else (price - target) / price * 100
                bars = target_hit
            elif stop_hit:
                outcome = 'loss'
                pnl = -(stop - price) / price * 100 if action == 'BUY' else -(price - stop) / price * 100
                bars = stop_hit
            else:
                continue
            
            all_trades.append({
                'bar': i, 'type': lt, 'pct': round(pct, 1),
                'action': action, 'target': round(target, 2),
                'stop': round(stop, 2), 'confidence': round(conf, 3),
                'rsi': round(rsi, 1), 'regime': regime,
                'min_amp': min_amp, 'order': order,
                'outcome': outcome, 'bars': bars,
                'pnl_pct': round(pnl, 2), 'price': round(price, 2),
            })
    
    return all_trades


# ═══════════════════════════════════════════════════════
# LEARN: Extract optimal parameters
# ═══════════════════════════════════════════════════════

def learn_parameters(daily_results, hourly_results):
    """
    Analyze backtest results and extract learned parameter adjustments.
    Saves to backtest_params.json for the scanner to pick up.
    """
    all_trades = daily_results + hourly_results
    if not all_trades:
        print("No trades to learn from!")
        return None
    
    # Win rates by key dimensions
    dims = {
        'by_action': {},
        'by_regime_action': {},
        'by_rsi_action': {},
        'by_pct_action': {},
        'by_conf_action': {},
    }
    
    for t in all_trades:
        # By action
        key = f"{t['type']}_{t['action']}"
        dims['by_action'].setdefault(key, {'w': 0, 'l': 0, 'pnl': 0})
        dims['by_action'][key]['w' if t['outcome'] == 'win' else 'l'] += 1
        dims['by_action'][key]['pnl'] += t['pnl_pct']
        
        # Regime × action
        rkey = f"{t['regime']}_{t['type']}_{t['action']}"
        dims['by_regime_action'].setdefault(rkey, {'w': 0, 'l': 0})
        dims['by_regime_action'][rkey]['w' if t['outcome'] == 'win' else 'l'] += 1
        
        # RSI × action
        if t['rsi'] < 30: rsi_zone = 'oversold'
        elif t['rsi'] < 40: rsi_zone = 'low'
        elif t['rsi'] < 60: rsi_zone = 'neutral'
        elif t['rsi'] < 70: rsi_zone = 'high'
        else: rsi_zone = 'overbought'
        rkey2 = f"{rsi_zone}_{t['type']}_{t['action']}"
        dims['by_rsi_action'].setdefault(rkey2, {'w': 0, 'l': 0})
        dims['by_rsi_action'][rkey2]['w' if t['outcome'] == 'win' else 'l'] += 1
        
        # Pct × action
        if t['pct'] < 25: pct_zone = 'early'
        elif t['pct'] < 50: pct_zone = 'mid'
        elif t['pct'] < 75: pct_zone = 'late'
        else: pct_zone = 'completion'
        pkey = f"{pct_zone}_{t['type']}_{t['action']}"
        dims['by_pct_action'].setdefault(pkey, {'w': 0, 'l': 0})
        dims['by_pct_action'][pkey]['w' if t['outcome'] == 'win' else 'l'] += 1
        
        # Confidence × action
        ckey = f"conf{t['confidence']:.1f}_{t['type']}_{t['action']}"
        dims['by_conf_action'].setdefault(ckey, {'w': 0, 'l': 0})
        dims['by_conf_action'][ckey]['w' if t['outcome'] == 'win' else 'l'] += 1
    
    # Extract signal adjustments
    adjustments = {
        'regime_boost': {},
        'rsi_filter': {},
        'position_filter': {},
        'confidence_threshold': {},
        'action_filter': {},
    }
    
    # Which regime+action combos work?
    for key, v in dims['by_regime_action'].items():
        total = v['w'] + v['l']
        if total >= 3:
            wr = v['w'] / total
            adjustments['regime_boost'][key] = round(wr - 0.5, 2)  # Edge vs random
    
    # Which RSI zones work?
    for key, v in dims['by_rsi_action'].items():
        total = v['w'] + v['l']
        if total >= 3:
            wr = v['w'] / total
            adjustments['rsi_filter'][key] = round(wr, 2)
    
    # Which position zones work?
    for key, v in dims['by_pct_action'].items():
        total = v['w'] + v['l']
        if total >= 3:
            wr = v['w'] / total
            adjustments['position_filter'][key] = round(wr, 2)
    
    # Action filter: which combos to avoid?
    for key, v in dims['by_action'].items():
        total = v['w'] + v['l']
        if total >= 5:
            wr = v['w'] / total
            avg_pnl = v['pnl'] / total
            adjustments['action_filter'][key] = {
                'win_rate': round(wr, 2),
                'avg_pnl': round(avg_pnl, 2),
                'trades': total,
            }
    
    # Overall stats
    wins = sum(1 for t in all_trades if t['outcome'] == 'win')
    total = len(all_trades)
    overall_wr = wins / total * 100 if total else 0
    
    params = {
        'timestamp': datetime.utcnow().isoformat(),
        'overall_win_rate': round(overall_wr, 1),
        'total_trades': total,
        'daily_trades': len(daily_results),
        'hourly_trades': len(hourly_results),
        'adjustments': adjustments,
        'top_signal': max(adjustments['action_filter'].items(), 
                         key=lambda x: x[1]['avg_pnl']) if adjustments['action_filter'] else None,
        'worst_signal': min(adjustments['action_filter'].items(), 
                           key=lambda x: x[1]['avg_pnl']) if adjustments['action_filter'] else None,
    }
    
    # Save
    (STORAGE / 'backtest_params.json').write_text(json.dumps(params, indent=2, default=str))
    print(f"\n  📊 Learned parameters saved to storage/backtest_params.json")
    print(f"  Overall win rate: {overall_wr:.1f}% ({total} trades)")
    if params['top_signal']:
        print(f"  Best signal: {params['top_signal'][0]} → avg PnL {params['top_signal'][1]['avg_pnl']:+.2f}% (WR {params['top_signal'][1]['win_rate']*100:.0f}%)")
    if params['worst_signal']:
        print(f"  Worst signal: {params['worst_signal'][0]} → avg PnL {params['worst_signal'][1]['avg_pnl']:+.2f}% (WR {params['worst_signal'][1]['win_rate']*100:.0f}%)")
    
    return params


# ═══════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════

if __name__ == "__main__":
    tickers = sys.argv[1:] if len(sys.argv) > 1 else ['WTI', 'RGTI']
    
    all_daily = []
    all_hourly = []
    
    for ticker in tickers:
        if ticker not in TICKERS:
            print(f"Unknown ticker: {ticker}")
            continue
        
        sym = TICKERS[ticker]['symbol']
        print(f"\n{'#'*60}")
        print(f"# {ticker} ({sym}) — DAILY BACKTEST")
        print(f"{'#'*60}")
        
        daily_trades = backtest_symbol(
            sym, tf='1d', period='2y', interval='1d',
            order_range=(2, 5), min_amp_range=(1.5, 2.0, 3.0),
            lookahead_bars=20
        )
        daily_results = analyze_trades(daily_trades, label=f"{ticker} Daily")
        all_daily.extend(daily_trades)
        
        print(f"\n{'#'*60}")
        print(f"# {ticker} ({sym}) — HOURLY BACKTEST")
        print(f"{'#'*60}")
        
        hourly_trades = backtest_hourly(sym, period='60d', lookahead_hours=8)
        hourly_results = analyze_trades(hourly_trades, label=f"{ticker} Hourly")
        all_hourly.extend(hourly_trades)
    
    # Learn
    print(f"\n{'='*60}")
    print(f"COMBINED LEARNING — {len(all_daily)} daily + {len(all_hourly)} hourly trades")
    print(f"{'='*60}")
    
    params = learn_parameters(all_daily, all_hourly)