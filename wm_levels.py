#!/usr/bin/env python3
"""
W-M Level Memory v1
====================
Learns key S/R levels from M ceilings and W floors across all history.
Clusters nearby levels into zones, then projects trendlines from the legs
to predict WHERE the next M will top or W will bounce.

Two key insights:
  1. M patterns top out at the same ceiling repeatedly (resistance)
  2. W patterns bounce off the same floor repeatedly (support)
  3. The legs of M and W run in parallel — project the trendline
     forward to call the target BEFORE the pattern completes

Usage:
  python wm_levels.py          # Build level memory for all tickers
  python wm_levels.py WTI      # Build + show levels for WTI
  python wm_levels.py RGTI     # Build + show levels for RGTI

Output:
  storage/levels_{ticker}.json — clustered level zones
  Integrated into wm_tactical.py as KEY_LEVELS dict
"""

import sys, json, numpy as np, yfinance as yf
from pathlib import Path
from datetime import datetime
from scipy.signal import argrelextrema
from collections import defaultdict

# Import pattern detection from tactical scanner
from wm_tactical import (
    detect_letters, find_phase, compute_atr, TICKERS, STORAGE
)

# ═════════════════════════════════════════════════════════
# LEVEL EXTRACTION — Find all M ceilings and W floors
# ═════════════════════════════════════════════════════════

def extract_levels(highs, lows, closes, timestamps=None, order=3, min_amp_pct=2.0):
    """
    Walk through historical data and extract every M ceiling and W floor.
    
    For each M pattern: the two peaks (left peak, right peak) are resistance ceilings
    For each W pattern: the two troughs (left trough, right trough) are support floors
    
    Also extracts the legs (sub-swings) within each pattern for trendline projection.
    
    Returns list of levels: {price, type, pattern, tf, amplitude, timestamp}
    """
    letters = detect_letters(highs, lows, closes, order=order, min_amp_pct=min_amp_pct)
    if not letters:
        return []
    
    levels = []
    
    for lt in letters:
        if lt[0] == 'M':
            # M pattern: (type, left_peak, dip, right_peak, amplitude, asymmetry)
            left_peak = lt[1]
            dip = lt[2]          # the neckline/floor
            right_peak = lt[3]
            ceiling = max(left_peak, right_peak)  # the resistance level
            
            levels.append({
                'price': round(ceiling, 2),
                'type': 'resistance',   # M tops out at resistance
                'pattern': 'M',
                'floor': round(dip, 2),
                'ceiling': round(ceiling, 2),
                'amplitude': lt[4],
                'asymmetry': lt[5],
            })
            # Also record the dip as support (M neckline)
            levels.append({
                'price': round(dip, 2),
                'type': 'support',       # M neckline is support
                'pattern': 'M',
                'floor': round(dip, 2),
                'ceiling': round(ceiling, 2),
                'amplitude': lt[4],
                'asymmetry': lt[5],
            })
            
        elif lt[0] == 'W':
            # W pattern: (type, left_trough, peak, right_trough, amplitude, asymmetry)
            left_trough = lt[1]
            peak = lt[2]             # the neckline/ceiling
            right_trough = lt[3]
            floor = min(left_trough, right_trough)  # the support level
            
            levels.append({
                'price': round(floor, 2),
                'type': 'support',       # W bounces off support
                'pattern': 'W',
                'floor': round(floor, 2),
                'ceiling': round(peak, 2),
                'amplitude': lt[4],
                'asymmetry': lt[5],
            })
            # Also record the peak as resistance (W neckline)
            levels.append({
                'price': round(peak, 2),
                'type': 'resistance',     # W neckline is resistance
                'pattern': 'W',
                'floor': round(floor, 2),
                'ceiling': round(peak, 2),
                'amplitude': lt[4],
                'asymmetry': lt[5],
            })
    
    return levels


def extract_trendlines(highs, lows, closes, timestamps=None, order=3, min_amp_pct=2.0):
    """
    Extract trendlines from the LEGS of W/M patterns.
    
    The legs of an M slope DOWN to the ceiling (two descending peaks connected)
    The legs of a W slope UP to the floor (two ascending troughs connected)
    
    For M: the two peaks define a down-sloping resistance trendline
    For W: the two troughs define an up-sloping support trendline
    
    Returns list of trendlines: {type, slope, intercept, price_now, projected_target}
    """
    letters = detect_letters(highs, lows, closes, order=order, min_amp_pct=min_amp_pct)
    if not letters or timestamps is None:
        return []
    
    trendlines = []
    
    for lt in letters:
        # Find the bar indices for this pattern
        # We need to find which bars correspond to the pattern's pivots
        # The pattern gives us prices; we need time indices
        pass  # We'll compute this differently — see extract_with_indices below
    
    return trendlines


def extract_with_indices(highs, lows, closes, order=3, min_amp_pct=2.0):
    """
    Extract W/M patterns WITH bar indices so we can compute trendline slopes.
    
    Returns list of: {type, i1, p1, i2, p2, i3, p3, floor, ceil, amplitude, asymmetry}
    """
    hi = argrelextrema(highs, np.greater, order=order)[0]
    lo = argrelextrema(lows, np.less, order=order)[0]
    if len(hi) < 2 or len(lo) < 2:
        return []
    
    swings = [(int(i), float(highs[i]), 'H') for i in hi] + \
             [(int(i), float(lows[i]), 'L') for i in lo]
    swings.sort()
    
    # Filter to alternating H/L
    alt = [swings[0]]
    for s in swings[1:]:
        if s[2] == alt[-1][2]:
            if s[2] == 'H' and s[1] > alt[-1][1]:
                alt[-1] = s
            elif s[2] == 'L' and s[1] < alt[-1][1]:
                alt[-1] = s
        else:
            alt.append(s)
    
    if len(alt) < 3:
        return []
    
    # ATR-adaptive minimum amplitude
    if closes is not None and len(closes) > 14:
        atr = compute_atr(highs, lows, closes)
        avg_price = float(np.mean(closes[-20:]))
        atr_pct = atr / avg_price * 100 if avg_price > 0 else 2
        min_amp = max(min_amp_pct, atr_pct * 0.5)
    else:
        min_amp = min_amp_pct
    
    patterns = []
    raw = []
    for i in range(len(alt) - 2):
        i1, p1, t1 = alt[i]
        i2, p2, t2 = alt[i+1]
        i3, p3, t3 = alt[i+2]
        
        if t1 == 'L' and t2 == 'H' and t3 == 'L':
            # W pattern: two bottoms with peak
            amp_pct = (p2 - min(p1, p3)) / min(p1, p3) * 100
            if amp_pct < min_amp:
                continue
            asymmetry = abs(p1 - p3) / max(p1, p3)
            if asymmetry > 0.08:
                continue
            floor = min(p1, p3)
            ceiling = p2
            raw.append(('W', i1, p1, i2, p2, i3, p3, floor, ceiling, amp_pct, asymmetry))
            
        elif t1 == 'H' and t2 == 'L' and t3 == 'H':
            # M pattern: two peaks with dip
            amp_pct = (max(p1, p3) - p2) / max(p1, p3) * 100
            if amp_pct < min_amp:
                continue
            asymmetry = abs(p1 - p3) / max(p1, p3)
            if asymmetry > 0.08:
                continue
            floor = p2
            ceiling = max(p1, p3)
            raw.append(('M', i1, p1, i2, p2, i3, p3, floor, ceiling, amp_pct, asymmetry))
    
    # Merge consecutive same-type
    patterns = [raw[0]] if raw else []
    for lt in raw[1:]:
        if lt[0] == patterns[-1][0]:
            if lt[9] > patterns[-1][9]:  # higher amplitude
                patterns[-1] = lt
        else:
            patterns.append(lt)
    
    return patterns


# ═════════════════════════════════════════════════════════
# LEVEL CLUSTERING — Merge nearby levels into zones
# ═════════════════════════════════════════════════════════

def cluster_levels(levels, tolerance_pct=1.5):
    """
    Cluster nearby price levels into S/R zones.
    
    tolerance_pct: levels within this % of each other merge into one zone.
                   For a $60 asset, 1.5% = $0.90 tolerance.
    
    Returns list of zones: {price, type, hits, patterns, min, max, strength}
    """
    if not levels:
        return []
    
    # Separate resistance and support
    resistance = [l for l in levels if l['type'] == 'resistance']
    support = [l for l in levels if l['type'] == 'support']
    
    zones = []
    
    for level_type, group in [('resistance', resistance), ('support', support)]:
        if not group:
            continue
        
        # Sort by price
        group.sort(key=lambda x: x['price'])
        
        # Cluster nearby levels
        clusters = []
        current_cluster = [group[0]]
        
        for level in group[1:]:
            cluster_avg = np.mean([l['price'] for l in current_cluster])
            if abs(level['price'] - cluster_avg) / cluster_avg * 100 < tolerance_pct:
                current_cluster.append(level)
            else:
                clusters.append(current_cluster)
                current_cluster = [level]
        clusters.append(current_cluster)
        
        # Build zones from clusters
        for cluster in clusters:
            prices = [l['price'] for l in cluster]
            patterns = list(set(l['pattern'] for l in cluster))
            avg_price = float(np.mean(prices))
            min_price = min(prices)
            max_price = max(prices)
            
            # Strength = number of times hit (more hits = stronger level)
            strength = len(cluster)
            
            # Weight by amplitude (bigger patterns = more significant levels)
            avg_amplitude = float(np.mean([l['amplitude'] for l in cluster]))
            
            zones.append({
                'price': round(avg_price, 2),
                'type': level_type,
                'hits': strength,
                'patterns': patterns,
                'min': round(min_price, 2),
                'max': round(max_price, 2),
                'strength': round(strength * avg_amplitude / 10, 2),  # hits × amp
                'amplitude': round(avg_amplitude, 2),
            })
    
    # Sort by strength (strongest first)
    zones.sort(key=lambda z: z['strength'], reverse=True)
    
    return zones


# ═════════════════════════════════════════════════════════
# TRENDLINE PROJECTION — Project legs forward
# ═════════════════════════════════════════════════════════

def project_trendlines(patterns, current_bar, current_price):
    """
    From each pattern's two pivot points, project the trendline forward.
    
    M pattern with two peaks at (i1, p1) and (i3, p3):
      - If p1 > p3: descending peaks → ceiling slopes DOWN → resistance falling
      - If p1 < p3: ascending peaks → ceiling slopes UP → resistance rising
      - Slope = (p3 - p1) / (i3 - i1) per bar
      - Projected ceiling = p3 + slope × (current_bar - i3)
    
    W pattern with two troughs at (i1, p1) and (i3, p3):
      - If p1 < p3: ascending troughs → floor slopes UP → support rising
      - If p1 > p3: descending troughs → floor slopes DOWN → support falling
      - Slope = (p3 - p1) / (i3 - i1) per bar
      - Projected floor = p3 + slope × (current_bar - i3)
    
    Returns list of projections: {type, slope, projected, from_price, direction}
    """
    projections = []
    
    for pat in patterns:
        ptype = pat[0]
        i1, p1 = pat[1], pat[2]
        i2, p2 = pat[3], pat[4]  # dip/peak
        i3, p3 = pat[5], pat[6]
        floor, ceiling = pat[7], pat[8]
        
        bars_ahead = current_bar - i3
        
        # Only project if pattern is recent (within 2× its width)
        pattern_width = i3 - i1
        if bars_ahead > pattern_width * 2:
            continue
        
        if ptype == 'M':
            # Two peaks define the ceiling trendline
            if i3 == i1:
                continue
            slope = (p3 - p1) / (i3 - i1)
            projected_ceil = p3 + slope * bars_ahead
            projected_floor = p2  # dip doesn't move (neckline)
            
            direction = "falling" if slope < 0 else "rising" if slope > 0 else "flat"
            
            projections.append({
                'type': 'M_ceil',
                'slope_per_bar': round(slope, 4),
                'projected_price': round(projected_ceil, 2),
                'original_price': round(ceiling, 2),
                'direction': direction,
                'bars_ahead': bars_ahead,
                'floor': round(floor, 2),
                'ceiling': round(ceiling, 2),
            })
            
        elif ptype == 'W':
            # Two troughs define the floor trendline
            if i3 == i1:
                continue
            slope = (p3 - p1) / (i3 - i1)
            projected_floor = p3 + slope * bars_ahead
            projected_ceil = p2  # peak doesn't move (neckline)
            
            direction = "rising" if slope > 0 else "falling" if slope < 0 else "flat"
            
            projections.append({
                'type': 'W_floor',
                'slope_per_bar': round(slope, 4),
                'projected_price': round(projected_floor, 2),
                'original_price': round(floor, 2),
                'direction': direction,
                'bars_ahead': bars_ahead,
                'floor': round(floor, 2),
                'ceiling': round(ceiling, 2),
            })
    
    return projections


# ═════════════════════════════════════════════════════════
# MULTI-TIMEFRAME LEVEL BUILDING
# ═════════════════════════════════════════════════════════

def build_level_memory(ticker):
    """
    Build complete level memory for a ticker across all timeframes.
    
    1. Fetch 15m, 1h, 1d data
    2. Extract M ceilings / W floors from each TF
    3. Cluster into key S/R zones
    4. Project trendlines from recent pattern legs
    5. Save to storage/levels_{ticker}.json
    
    Returns (levels, zones, projections)
    """
    if ticker not in TICKERS:
        print(f"Unknown ticker: {ticker}")
        return None, None, None
    
    sym = TICKERS[ticker]["symbol"]
    print(f"\n{'='*50}")
    print(f"Building level memory for {ticker} ({sym})")
    print(f"{'='*50}")
    
    all_levels = []
    all_patterns = []
    
    # ── 1D levels (2h macro) ──
    df = yf.Ticker(sym).history(period="6mo", interval="1d")
    if not df.empty and len(df) > 60:
        h, l, c = df['High'].values.astype(float), df['Low'].values.astype(float), df['Close'].values.astype(float)
        
        # Extract levels
        levels_1d = extract_levels(h, l, c, order=3, min_amp_pct=2.0)
        for lv in levels_1d:
            lv['tf'] = '2h'
        all_levels.extend(levels_1d)
        
        # Extract patterns with indices (for trendline projection)
        pats_1d = extract_with_indices(h, l, c, order=3, min_amp_pct=2.0)
        for p in pats_1d:
            # Convert absolute bar index to position from end
            p = list(p)
            all_patterns.append(('2h', len(c)) + tuple(p))
        
        current_price = float(c[-1])
        current_bar = len(c)
        
        # Trendline projections from 1D
        projs_1d = project_trendlines(pats_1d, current_bar, current_price)
        for proj in projs_1d:
            proj['tf'] = '2h'
        
        print(f"\n1D (2h macro): {len(levels_1d)} levels, {len(pats_1d)} patterns, {len(projs_1d)} projections")
    else:
        projs_1d = []
        current_price = 0
        current_bar = 0
    
    # ── 1H levels ──
    df = yf.Ticker(sym).history(period="30d", interval="1h")
    if not df.empty and len(df) > 60:
        h, l, c = df['High'].values.astype(float), df['Low'].values.astype(float), df['Close'].values.astype(float)
        
        levels_1h = extract_levels(h, l, c, order=3, min_amp_pct=1.0)
        for lv in levels_1h:
            lv['tf'] = '1h'
        all_levels.extend(levels_1h)
        
        pats_1h = extract_with_indices(h, l, c, order=3, min_amp_pct=1.0)
        for p in pats_1h:
            p = list(p)
        
        price_1h = float(c[-1])
        
        # Trendline projections from 1H
        projs_1h = project_trendlines(pats_1h, len(c), price_1h)
        for proj in projs_1h:
            proj['tf'] = '1h'
        
        if current_price == 0:
            current_price = price_1h
        
        print(f"1H:            {len(levels_1h)} levels, {len(pats_1h)} patterns, {len(projs_1h)} projections")
    else:
        projs_1h = []
    
    # ── 15M levels ──
    df = yf.Ticker(sym).history(period="5d", interval="15m")
    if not df.empty and len(df) > 60:
        h, l, c = df['High'].values.astype(float), df['Low'].values.astype(float), df['Close'].values.astype(float)
        
        levels_15m = extract_levels(h, l, c, order=2, min_amp_pct=0.5)
        for lv in levels_15m:
            lv['tf'] = '30m'
        all_levels.extend(levels_15m)
        
        pats_15m = extract_with_indices(h, l, c, order=2, min_amp_pct=0.5)
        
        price_15m = float(c[-1])
        projs_15m = project_trendlines(pats_15m, len(c), price_15m)
        for proj in projs_15m:
            proj['tf'] = '30m'
        
        if current_price == 0:
            current_price = price_15m
        
        print(f"15M (30m):     {len(levels_15m)} levels, {len(pats_15m)} patterns, {len(projs_15m)} projections")
    else:
        projs_15m = []
    
    # ── Cluster levels into zones ──
    zones = cluster_levels(all_levels, tolerance_pct=1.5)
    
    # ── Merge projections (keep most recent per TF) ──
    all_projections = projs_1d + projs_1h + projs_15m
    
    # ── Find nearest levels to current price ──
    nearest_resistance = None
    nearest_support = None
    if current_price > 0:
        resistance_levels = sorted([z for z in zones if z['type'] == 'resistance' and z['price'] > current_price],
                                    key=lambda z: z['price'])
        support_levels = sorted([z for z in zones if z['type'] == 'support' and z['price'] < current_price],
                                 key=lambda z: z['price'], reverse=True)
        
        if resistance_levels:
            nearest_resistance = resistance_levels[0]
        if support_levels:
            nearest_support = support_levels[0]
    
    # ── Save level memory ──
    result = {
        'ticker': ticker,
        'symbol': TICKERS[ticker]['symbol'],
        'price': round(current_price, 2),
        'timestamp': datetime.now().isoformat(),
        'total_levels': len(all_levels),
        'total_zones': len(zones),
        'zones': [{
            'price': z['price'],
            'type': z['type'],
            'hits': z['hits'],
            'patterns': z['patterns'],
            'min': z['min'],
            'max': z['max'],
            'strength': z['strength'],
            'amplitude': z['amplitude'],
            'tf': list(set(l['tf'] for l in all_levels if abs(l['price'] - z['price']) < z['price'] * 0.02)),
        } for z in zones],
        'nearest_resistance': nearest_resistance,
        'nearest_support': nearest_support,
        'projections': [{
            'type': p['type'],
            'tf': p['tf'],
            'projected': p['projected_price'],
            'original': p['original_price'],
            'direction': p['direction'],
            'slope': p['slope_per_bar'],
            'floor': p['floor'],
            'ceiling': p['ceiling'],
        } for p in all_projections],
    }
    
    (STORAGE / f"levels_{ticker.lower()}.json").write_text(
        json.dumps(result, indent=2, default=str)
    )
    
    # ── Print summary ──
    print(f"\n{'='*50}")
    print(f"Level Memory: {ticker} @ ${current_price:.2f}")
    print(f"{'='*50}")
    print(f"Extracted {len(all_levels)} raw levels → {len(zones)} clustered zones")
    print(f"Trendline projections: {len(all_projections)}")
    
    if nearest_resistance:
        dist_r = ((nearest_resistance['price'] - current_price) / current_price * 100)
        print(f"\n🟥 Nearest Resistance: ${nearest_resistance['price']} ({dist_r:+.1f}%) — {nearest_resistance['hits']} hits, {', '.join(nearest_resistance['patterns'])}")
    if nearest_support:
        dist_s = ((nearest_support['price'] - current_price) / current_price * 100)
        print(f"🟩 Nearest Support:    ${nearest_support['price']} ({dist_s:+.1f}%) — {nearest_support['hits']} hits, {', '.join(nearest_support['patterns'])}")
    
    # Top 5 resistance zones
    print(f"\n📊 Top Resistance Zones:")
    for z in [z for z in zones if z['type'] == 'resistance'][:5]:
        print(f"   ${z['price']:.2f} ({z['hits']} hits, {', '.join(z['patterns'])}, amp={z['amplitude']:.1f}%, str={z['strength']:.1f})")
    
    # Top 5 support zones
    print(f"\n📊 Top Support Zones:")
    for z in [z for z in zones if z['type'] == 'support'][:5]:
        print(f"   ${z['price']:.2f} ({z['hits']} hits, {', '.join(z['patterns'])}, amp={z['amplitude']:.1f}%, str={z['strength']:.1f})")
    
    # Trendline projections
    if all_projections:
        print(f"\n📈 Trendline Projections (legs running parallel):")
        for p in all_projections[:6]:
            arrow = "↑" if p['direction'] == 'rising' else ("↓" if p['direction'] == 'falling' else "→")
            tf = p['tf']
            if p['type'] == 'M_ceil':
                print(f"   {tf} M-ceiling {arrow} ${p['projected_price']} (from ${p['original_price']}, slope {p['slope_per_bar']}/bar)")
            else:
                print(f"   {tf} W-floor {arrow} ${p['projected_price']} (from ${p['original_price']}, slope {p['slope_per_bar']}/bar)")
    
    return result, zones, all_projections


# ═════════════════════════════════════════════════════════
# UPDATE SCANNER — Inject learned levels into wm_tactical.py
# ═════════════════════════════════════════════════════════

def update_scanner_with_levels(levels_data):
    """
    Update wm_tactical.py with KEY_LEVELS dict derived from level memory.
    Also adds trendline projections as predictive targets.
    """
    scanner_path = Path(__file__).parent / "wm_tactical.py"
    scanner_text = scanner_path.read_text()
    
    # Build KEY_LEVELS dict
    key_levels = {}
    for ticker in TICKERS:
        lf = STORAGE / f"levels_{ticker.lower()}.json"
        if lf.exists():
            data = json.loads(lf.read_text())
            ticker_levels = {}
            
            # Nearest resistance and support
            if data.get('nearest_resistance'):
                r = data['nearest_resistance']
                ticker_levels['resistance'] = {
                    'price': r['price'],
                    'hits': r['hits'],
                    'patterns': r['patterns'],
                }
            if data.get('nearest_support'):
                s = data['nearest_support']
                ticker_levels['support'] = {
                    'price': s['price'],
                    'hits': s['hits'],
                    'patterns': s['patterns'],
                }
            
            # Top 3 resistance and support zones (sorted by strength)
            resistance_zones = sorted(
                [z for z in data.get('zones', []) if z['type'] == 'resistance'],
                key=lambda z: z.get('strength', 0), reverse=True
            )[:3]
            support_zones = sorted(
                [z for z in data.get('zones', []) if z['type'] == 'support'],
                key=lambda z: z.get('strength', 0), reverse=True
            )[:3]
            
            ticker_levels['resistance_zones'] = [{
                'price': z['price'], 'hits': z['hits'], 'str': z.get('strength', 0)
            } for z in resistance_zones]
            ticker_levels['support_zones'] = [{
                'price': z['price'], 'hits': z['hits'], 'str': z.get('strength', 0)
            } for z in support_zones]
            
            # Trendline projections
            projections = data.get('projections', [])
            ticker_levels['projections'] = [{
                'type': p['type'], 'tf': p['tf'],
                'projected': p.get('projected', p.get('projected_price', 0)),
                'direction': p.get('direction', 'flat'),
                'slope': p.get('slope', p.get('slope_per_bar', 0)),
                'floor': p.get('floor', 0), 'ceiling': p.get('ceiling', 0),
            } for p in projections[:4]]  # top 4 projections
            
            key_levels[ticker] = ticker_levels
    
    # Format as Python dict
    levels_str = json.dumps(key_levels, indent=4)
    
    # Replace KEY_LEVELS in scanner
    import re
    pattern = r'KEY_LEVELS\s*=\s*\{[^}]+\}(?:\s*\})?'
    # Find the KEY_LEVELS block — from "KEY_LEVELS = {" to the closing "}"
    start_marker = "# ═══ LEVEL MEMORY (auto-updated)"
    end_marker = "# ═══════════════════════════════════════════════════════"
    
    # Simpler: find KEY_LEVELS = { ... } and replace
    match = re.search(r'KEY_LEVELS\s*=\s*\{.*?\n\}', scanner_text, re.DOTALL)
    if match:
        new_block = f"KEY_LEVELS = {levels_str}\n"
        scanner_text = scanner_text[:match.start()] + new_block + scanner_text[match.end():]
    else:
        # Insert after SIGNAL_EDGE block
        signal_edge_end = scanner_text.find("signal_grade(")
        if signal_edge_end > 0:
            # Find the function definition line before signal_grade
            insert_point = scanner_text.rfind('\n\n', 0, signal_edge_end)
            new_block = f"\n\n# ═══ LEVEL MEMORY (auto-updated by wm_levels.py) ═══\nKEY_LEVELS = {levels_str}\n\n"
            scanner_text = scanner_text[:insert_point] + new_block + scanner_text[insert_point:]
    
    scanner_path.write_text(scanner_text)
    print(f"\n✅ Updated wm_tactical.py with KEY_LEVELS for {list(key_levels.keys())}")


# ═════════════════════════════════════════════════════════
# MAIN
# ═════════════════════════════════════════════════════════

if __name__ == "__main__":
    tickers = sys.argv[1:] if len(sys.argv) > 1 else list(TICKERS.keys())
    
    for ticker in tickers:
        if ticker not in TICKERS:
            print(f"Unknown ticker: {ticker}")
            continue
        result, zones, projections = build_level_memory(ticker)
    
    # Update scanner with learned levels
    if result:
        update_scanner_with_levels(result)