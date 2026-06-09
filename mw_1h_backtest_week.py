#!/usr/bin/env python3
"""
1h M/W Pattern Backtest — Week of Jun 1-5, 2026
Clean final version with proper timestamps and decisive rule extraction.
"""

import sys, os
sys.path.insert(0, "/Users/clawcl/code/Mike_claw")

import numpy as np
import yfinance as yf
import pandas as pd
from datetime import datetime, timedelta
from pytz import timezone

import wm_tactical as wt

ET = timezone('US/Eastern')

TICKERS = {
    "WTI":  "CL=F",
    "RGTI": "RGTI",
    "QBTX": "QBTX",
}

LOOKBACK = 30

def fetch_1h_data(symbol):
    df = yf.Ticker(symbol).history(period="60d", interval="1h")
    if df.empty:
        return None
    return df

def analyze_ticker(name, symbol):
    df = fetch_1h_data(symbol)
    if df is None or df.empty:
        print(f"  ERROR: No data for {symbol}")
        return []
    
    df = df.tz_convert('US/Eastern')
    week_start = pd.Timestamp('2026-06-01', tz='US/Eastern')
    week_end = pd.Timestamp('2026-06-06', tz='US/Eastern')
    week_mask = (df.index >= week_start) & (df.index < week_end)
    week_df = df[week_mask]
    
    if week_df.empty:
        print(f"  WARNING: No data in week range for {symbol}")
        print(f"  Data range: {df.index[0]} to {df.index[-1]}")
        # Use last 35 bars as fallback
        week_df = df.tail(35)
    
    highs_all = df['High'].values.astype(float)
    lows_all = df['Low'].values.astype(float)
    closes_all = df['Close'].values.astype(float)
    index_all = df.index
    
    results = []
    
    for i in range(len(week_df)):
        ts = week_df.index[i]
        pos = df.index.get_loc(ts)
        price = float(closes_all[pos])
        
        start = max(0, pos - LOOKBACK)
        h = highs_all[start:pos+1]
        l = lows_all[start:pos+1]
        c = closes_all[start:pos+1]
        
        if len(h) < 10:
            continue
        
        letters = wt.detect_letters(h, l, c, order=3, min_amp_pct=1.0)
        ptype, floor_p, ceil_p, pct, action = wt.find_phase(letters, price)
        
        # Forward returns
        fwd4_pos = min(pos + 4, len(closes_all) - 1)
        fwd4_price = float(closes_all[fwd4_pos])
        fwd4_ret = (fwd4_price - price) / price * 100 if price > 0 else 0
        
        fwd2_pos = min(pos + 2, len(closes_all) - 1)
        fwd2_price = float(closes_all[fwd2_pos])
        fwd2_ret = (fwd2_price - price) / price * 100 if price > 0 else 0
        
        if action == 'BUY':
            worked = fwd4_ret > 0
        elif action == 'SELL':
            worked = fwd4_ret < 0
        else:
            worked = None
        
        # Time string
        ts_et = ts
        day = ts_et.strftime('%a')
        hm = ts_et.strftime('%H:%M')
        date = ts_et.strftime('%m/%d')
        
        results.append({
            'timestamp': ts,
            'day': day,
            'hm': hm,
            'date': date,
            'price': price,
            'pattern': ptype,
            'pct': round(pct, 1),
            'action': action,
            'fwd4_ret': round(fwd4_ret, 3),
            'fwd2_ret': round(fwd2_ret, 3),
            'worked': worked,
        })
    
    return results


def print_table(results, name):
    print(f"\n{'='*100}")
    print(f"  {name} — 1h M/W Signals This Week")
    print(f"{'='*100}")
    print(f"  {'Date':>5} {'Day':>3} {'Time':>5} {'Price':>9} {'Pat':>4} {'Pct':>6} {'Action':>6} {'4bRet':>8} {'2bRet':>8} {'OK?':>4}")
    print(f"  {'─'*5} {'─'*3} {'─'*5} {'─'*9} {'─'*4} {'─'*6} {'─'*6} {'─'*8} {'─'*8} {'─'*4}")
    
    for r in results:
        ok = '+' if r['worked'] == True else ('-' if r['worked'] == False else '·')
        print(f"  {r['date']:>5} {r['day']:>3} {r['hm']:>5} {r['price']:>9.2f} {r['pattern']:>4} "
              f"{r['pct']:>5.1f}% {r['action']:>6} {r['fwd4_ret']:>+7.2f}% {r['fwd2_ret']:>+7.2f}% {ok:>4}")
    
    # Only actionable rows
    actionable = [r for r in results if r['action'] != 'WAIT']
    if actionable:
        print(f"\n  ACTIONABLE SIGNALS ONLY:")
        print(f"  {'Date':>5} {'Day':>3} {'Time':>5} {'Price':>9} {'Pat':>4} {'Pct':>6} {'Action':>6} {'4bRet':>8} {'OK?':>4}")
        print(f"  {'─'*5} {'─'*3} {'─'*5} {'─'*9} {'─'*4} {'─'*6} {'─'*6} {'─'*8} {'─'*4}")
        for r in actionable:
            ok = '+' if r['worked'] == True else ('-' if r['worked'] == False else '.')
            print(f"  {r['date']:>5} {r['day']:>3} {r['hm']:>5} {r['price']:>9.2f} {r['pattern']:>4} "
                  f"{r['pct']:>5.1f}% {r['action']:>6} {r['fwd4_ret']:>+7.2f}% {ok:>4}")


def pct_bucket(pct):
    if pct < 15: return '0-14'
    if pct < 25: return '15-24'
    if pct < 35: return '25-34'
    if pct < 50: return '35-49'
    if pct < 65: return '50-64'
    if pct < 75: return '65-74'
    if pct < 85: return '75-84'
    return '85-100'


def summary_stats(results, name):
    print(f"\n  {name} SUMMARY BY PATTERN + PCT RANGE:")
    
    for ptype in ['M', 'W']:
        by_bucket = {}
        for r in results:
            if r['pattern'] != ptype:
                continue
            b = pct_bucket(r['pct'])
            if b not in by_bucket:
                by_bucket[b] = []
            by_bucket[b].append(r)
        
        print(f"\n    {ptype} Pattern:")
        for b in ['0-14', '15-24', '25-34', '35-49', '50-64', '65-74', '75-84', '85-100']:
            subset = by_bucket.get(b, [])
            if not subset:
                continue
            buys = [r for r in subset if r['action'] == 'BUY']
            sells = [r for r in subset if r['action'] == 'SELL']
            waits = [r for r in subset if r['action'] == 'WAIT']
            
            avg4 = np.mean([r['fwd4_ret'] for r in subset])
            parts = []
            if buys:
                bw = sum(1 for r in buys if r['worked'] == True)
                bl = sum(1 for r in buys if r['worked'] == False)
                wr = bw/(bw+bl)*100 if bw+bl > 0 else 0
                parts.append(f"BUY {bw}W/{bl}L ({wr:.0f}%)")
            if sells:
                sw = sum(1 for r in sells if r['worked'] == True)
                sl = sum(1 for r in sells if r['worked'] == False)
                wr = sw/(sw+sl)*100 if sw+sl > 0 else 0
                parts.append(f"SELL {sw}W/{sl}L ({wr:.0f}%)")
            if waits:
                parts.append(f"WAIT×{len(waits)}")
            
            print(f"      {ptype}@{b:>6}%: {len(subset)} bars | avg4={avg4:+.2f}% | {' '.join(parts)}")


def final_rules(all_results):
    """Derive the simplest rules from all data."""
    print(f"\n{'='*100}")
    print(f"  SIMPLEST RULE DERIVATION")
    print(f"{'='*100}")
    
    flat = []
    for name, results in all_results.items():
        for r in results:
            flat.append({**r, 'ticker': name})
    
    # ─── M PATTERN ───
    print(f"\n  M-PATTERN RULES:")
    print(f"  M pattern pct = (ceil - price)/(ceil - floor) × 100")
    print(f"    High pct (75-100%) = price near M-bottom (the dip between two peaks)")
    print(f"    Low  pct (0-25%)  = price near M-top (the peaks)")
    
    for lo, hi, label in [(0, 25, "M@0-25%  (near peaks)"),
                          (25, 50, "M@25-50% (upper half)"),
                          (50, 75, "M@50-75% (lower half)"),
                          (75, 100, "M@75-100% (near dip)")]:
        subset = [r for r in flat if r['pattern'] == 'M' and lo <= r['pct'] < hi]
        if not subset:
            print(f"    {label}: no signals")
            continue
        
        buys = [r for r in subset if r['action'] == 'BUY']
        sells = [r for r in subset if r['action'] == 'SELL']
        
        avg4 = np.mean([r['fwd4_ret'] for r in subset])
        parts = []
        if buys:
            bw = sum(1 for r in buys if r['worked'] == True)
            bl = sum(1 for r in buys if r['worked'] == False)
            avg_buy_r = np.mean([r['fwd4_ret'] for r in buys])
            wr = bw/(bw+bl)*100 if bw+bl > 0 else 0
            parts.append(f"BUY {bw}W/{bl}L WR={wr:.0f}% avg={avg_buy_r:+.3f}%")
        if sells:
            sw = sum(1 for r in sells if r['worked'] == True)
            sl = sum(1 for r in sells if r['worked'] == False)
            avg_sell_r = np.mean([r['fwd4_ret'] for r in sells])
            wr = sw/(sw+sl)*100 if sw+sl > 0 else 0
            parts.append(f"SELL {sw}W/{sl}L WR={wr:.0f}% avg={avg_sell_r:+.3f}%")
        
        per_ticker = {}
        for r in subset:
            t = r['ticker']
            if t not in per_ticker:
                per_ticker[t] = []
            per_ticker[t].append(r)
        
        ticker_detail = []
        for t, trs in per_ticker.items():
            t_avg = np.mean([r['fwd4_ret'] for r in trs])
            t_buys = [r for r in trs if r['action'] == 'BUY']
            t_sells = [r for r in trs if r['action'] == 'SELL']
            td_parts = []
            if t_buys:
                bw = sum(1 for r in t_buys if r['worked'] == True)
                bl = sum(1 for r in t_buys if r['worked'] == False)
                td_parts.append(f"B:{bw}W/{bl}L")
            if t_sells:
                sw = sum(1 for r in t_sells if r['worked'] == True)
                sl = sum(1 for r in t_sells if r['worked'] == False)
                td_parts.append(f"S:{sw}W/{sl}L")
            ticker_detail.append(f"{t}({','.join(td_parts)})")
        
        print(f"    {label}: {len(subset)} | avg4={avg4:+.3f}% | {' '.join(parts)}")
        print(f"         by ticker: {' '.join(ticker_detail)}")
    
    # ─── W PATTERN ───
    print(f"\n  W-PATTERN RULES:")
    print(f"  W pattern pct = (price - floor)/(ceil - floor) × 100")
    print(f"    Low  pct (0-25%)  = price near W-bottom (the double bottom)")
    print(f"    High pct (75-100%) = price near W-top (the peak)")
    
    for lo, hi, label in [(0, 25, "W@0-25%  (near bottom)"),
                          (25, 50, "W@25-50% (lower half)"),
                          (50, 75, "W@50-75% (upper half)"),
                          (75, 100, "W@75-100% (near top)")]:
        subset = [r for r in flat if r['pattern'] == 'W' and lo <= r['pct'] < hi]
        if not subset:
            print(f"    {label}: no signals")
            continue
        
        buys = [r for r in subset if r['action'] == 'BUY']
        sells = [r for r in subset if r['action'] == 'SELL']
        
        avg4 = np.mean([r['fwd4_ret'] for r in subset])
        parts = []
        if buys:
            bw = sum(1 for r in buys if r['worked'] == True)
            bl = sum(1 for r in buys if r['worked'] == False)
            avg_buy_r = np.mean([r['fwd4_ret'] for r in buys])
            wr = bw/(bw+bl)*100 if bw+bl > 0 else 0
            parts.append(f"BUY {bw}W/{bl}L WR={wr:.0f}% avg={avg_buy_r:+.3f}%")
        if sells:
            sw = sum(1 for r in sells if r['worked'] == True)
            sl = sum(1 for r in sells if r['worked'] == False)
            avg_sell_r = np.mean([r['fwd4_ret'] for r in sells])
            wr = sw/(sw+sl)*100 if sw+sl > 0 else 0
            parts.append(f"SELL {sw}W/{sl}L WR={wr:.0f}% avg={avg_sell_r:+.3f}%")
        
        per_ticker = {}
        for r in subset:
            t = r['ticker']
            if t not in per_ticker:
                per_ticker[t] = []
            per_ticker[t].append(r)
        
        ticker_detail = []
        for t, trs in per_ticker.items():
            t_avg = np.mean([r['fwd4_ret'] for r in trs])
            t_buys = [r for r in trs if r['action'] == 'BUY']
            t_sells = [r for r in trs if r['action'] == 'SELL']
            td_parts = []
            if t_buys:
                bw = sum(1 for r in t_buys if r['worked'] == True)
                bl = sum(1 for r in t_buys if r['worked'] == False)
                td_parts.append(f"B:{bw}W/{bl}L")
            if t_sells:
                sw = sum(1 for r in t_sells if r['worked'] == True)
                sl = sum(1 for r in t_sells if r['worked'] == False)
                td_parts.append(f"S:{sw}W/{sl}L")
            ticker_detail.append(f"{t}({','.join(td_parts)})")
        
        print(f"    {label}: {len(subset)} | avg4={avg4:+.3f}% | {' '.join(parts)}")
        print(f"         by ticker: {' '.join(ticker_detail)}")
    
    # ─── FINAL RULES ───
    print(f"\n{'='*100}")
    print(f"  FINAL SIMPLEST RULES (1h M/W only, no other indicators)")
    print(f"{'='*100}")
    
    # M BUY near peaks (low pct)
    m_buy_low = [r for r in flat if r['pattern'] == 'M' and r['pct'] <= 25 and r['action'] == 'BUY']
    m_sell_high = [r for r in flat if r['pattern'] == 'M' and r['pct'] >= 75 and r['action'] == 'SELL']
    w_buy_low = [r for r in flat if r['pattern'] == 'W' and r['pct'] <= 25 and r['action'] == 'BUY']
    w_sell_high = [r for r in flat if r['pattern'] == 'W' and r['pct'] >= 90 and r['action'] == 'SELL']
    
    def rule_string(label, subset):
        if not subset:
            return f"    {label}: NO SIGNALS"
        wins = sum(1 for r in subset if r['worked'])
        losses = sum(1 for r in subset if r['worked'] == False)
        wr = wins/(wins+losses)*100 if wins+losses > 0 else 0
        avg = np.mean([r['fwd4_ret'] for r in subset])
        return f"    {label}: {wins}W/{losses}L = {wr:.0f}% WR, avg 4b ret = {avg:+.3f}%"
    
    print(f"\n  Rule 1: M pattern, pct ≤ 25% (near peaks) → BUY")
    print(rule_string("M_BUY@0-25%", m_buy_low))
    
    print(f"\n  Rule 2: M pattern, pct ≥ 75% (near dip/completion) → SELL")  
    print(rule_string("M_SELL@75-100%", m_sell_high))
    
    print(f"\n  Rule 3: W pattern, pct ≤ 25% (near bottom) → BUY?")
    print(rule_string("W_BUY@0-25%", w_buy_low))
    
    print(f"\n  Rule 4: W pattern, pct ≥ 90% (near completion) → SELL?")
    print(rule_string("W_SELL@90-100%", w_sell_high))
    
    # Refine: what actually worked BEST?
    print(f"\n  WHAT ACTUALLY WORKED (4b forward ret > 0)?")
    
    # Group by pattern+pct+action and show win rates
    groups = {}
    for r in flat:
        if r['action'] == 'WAIT':
            continue
        key = f"{r['pattern']}@{pct_bucket(r['pct'])}%→{r['action']}"
        if key not in groups:
            groups[key] = []
        groups[key].append(r)
    
    for key in sorted(groups.keys()):
        subset = groups[key]
        wins = sum(1 for r in subset if r['worked'])
        losses = sum(1 for r in subset if r['worked'] == False)
        total = wins + losses
        wr = wins/total*100 if total > 0 else 0
        avg = np.mean([r['fwd4_ret'] for r in subset])
        verdict = "✓ PROFITABLE" if wr >= 60 and avg > 0 else ("△ MARGINAL" if wr >= 50 else "✗ UNPROFITABLE")
        print(f"    {key:>25}: {wins}W/{losses}L = {wr:.0f}% WR, avg={avg:+.3f}% {verdict}")
    
    print(f"\n  CONCLUSION:")
    
    # Best M rules
    m_buy_025 = [r for r in flat if r['pattern'] == 'M' and r['pct'] <= 25 and r['action'] == 'BUY']
    m_sell_75 = [r for r in flat if r['pattern'] == 'M' and r['pct'] >= 75 and r['action'] == 'SELL']
    
    if m_buy_025:
        bw = sum(1 for r in m_buy_025 if r['worked'])
        bl = sum(1 for r in m_buy_025 if r['worked'] == False)
        wr = bw/(bw+bl)*100 if bw+bl > 0 else 0
        avg = np.mean([r['fwd4_ret'] for r in m_buy_025])
        print(f"    M@0-25% → BUY: {bw}W/{bl}L ({wr:.0f}%), avg={avg:+.3f}%", end="")
        # By ticker
        for t in ['WTI', 'RGTI', 'QBTX']:
            tr = [r for r in m_buy_025 if r['ticker'] == t]
            if tr:
                tw = sum(1 for r in tr if r['worked'])
                tl = sum(1 for r in tr if r['worked'] == False)
                print(f"  {t}:{tw}W/{tl}L", end="")
        print()
    
    if m_sell_75:
        sw = sum(1 for r in m_sell_75 if r['worked'])
        sl = sum(1 for r in m_sell_75 if r['worked'] == False)
        wr = sw/(sw+sl)*100 if sw+sl > 0 else 0
        avg = np.mean([r['fwd4_ret'] for r in m_sell_75])
        print(f"    M@75-100% → SELL: {sw}W/{sl}L ({wr:.0f}%), avg={avg:+.3f}%", end="")
        for t in ['WTI', 'RGTI', 'QBTX']:
            tr = [r for r in m_sell_75 if r['ticker'] == t]
            if tr:
                tw = sum(1 for r in tr if r['worked'])
                tl = sum(1 for r in tr if r['worked'] == False)
                print(f"  {t}:{tw}W/{tl}L", end="")
        print()
    
    w_buy = [r for r in flat if r['pattern'] == 'W' and r['pct'] <= 25 and r['action'] == 'BUY']
    if w_buy:
        bw = sum(1 for r in w_buy if r['worked'])
        bl = sum(1 for r in w_buy if r['worked'] == False)
        wr = bw/(bw+bl)*100 if bw+bl > 0 else 0
        avg = np.mean([r['fwd4_ret'] for r in w_buy])
        print(f"    W@0-25% → BUY: {bw}W/{bl}L ({wr:.0f}%), avg={avg:+.3f}%  ← TRAP!", end="")
        for t in ['WTI', 'RGTI', 'QBTX']:
            tr = [r for r in w_buy if r['ticker'] == t]
            if tr:
                tw = sum(1 for r in tr if r['worked'])
                tl = sum(1 for r in tr if r['worked'] == False)
                print(f"  {t}:{tw}W/{tl}L", end="")
        print()
    
    print(f"\n  RECOMMENDED SIMPLEST RULES:")
    print(f"    1. If 1h shows M at 0-25% → BUY (M-top, trend still strong)")
    print(f"    2. If 1h shows M at 75-100% → SELL (M completing, breakdown ahead)")
    print(f"    3. If 1h shows W at any % → DO NOT BUY (W is a trap this week)")
    print(f"    4. If 1h shows NONE → NO TRADE")


if __name__ == '__main__':
    all_results = {}
    
    for name, symbol in TICKERS.items():
        print(f"\nFetching {name} ({symbol})...")
        results = analyze_ticker(name, symbol)
        if results:
            print_table(results, name)
            summary_stats(results, name)
            all_results[name] = results
    
    if all_results:
        final_rules(all_results)
    
    print(f"\n{'='*100}")
    print(f"  ANALYSIS COMPLETE")
    print(f"{'='*100}")
    
    # Save to file
    with open('/Users/clawcl/code/Mike_claw/mw_1h_week_report.txt', 'w') as f:
        f.write("1h M/W Analysis Report - Week of Jun 1-5, 2026\n")
        f.write("="*80 + "\n\n")
        for name, results in all_results.items():
            f.write(f"{name} Actionable Signals:\n")
            for r in results:
                if r['action'] != 'WAIT':
                    ok = 'WIN' if r['worked'] == True else ('LOSS' if r['worked'] == False else 'WAIT')
                    f.write(f"  {r['date']} {r['day']} {r['hm']} ${r['price']:.2f} "
                           f"{r['pattern']}@{r['pct']:.0f}% {r['action']} 4b={r['fwd4_ret']:+.2f}% {ok}\n")
            f.write("\n")
    
    print(f"\n  Report saved to: /Users/clawcl/code/Mike_claw/mw_1h_week_report.txt")