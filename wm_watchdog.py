#!/usr/bin/env python3
"""
wm_watchdog.py — Rapid volatility watchdog for W-M scanner
Runs every 10 minutes during market hours to catch intraday moves
that the 30-minute scanner misses.

Key insight from 6/3 miss:
- QBTX crashed -17% in 2 hours ($25.99 → $21.58)
- RGTI crashed -15% ($28.06 → $23.82)
- 30m scanner caught the spike-and-reverse AFTER the move was done
- We needed detection DURING the move formation

This lightweight script:
1. Fetches only 15m + 1h data (fast, ~2 API calls)
2. Runs spike/dip/momentum detectors
3. Only alerts when a NEW move detector fires (saves last state)
4. Sends Telegram alert immediately
"""

import sys
import json
import numpy as np
from pathlib import Path
from datetime import datetime
from pytz import timezone

# Import detectors from wm_tactical
sys.path.insert(0, str(Path(__file__).parent))
from wm_tactical import (
    TICKERS, fetch_multi, detect_regime, compute_atr,
    detect_spike_and_reverse, detect_dip_and_reverse,
    detect_momentum_acceleration, detect_macro_override,
    detect_letters, find_phase, pattern_confidence,
    VELOCITY_THRESHOLDS, ET, STORAGE
)

WATCHDOG_DIR = STORAGE / "watchdog"
WATCHDOG_DIR.mkdir(exist_ok=True)

def run_watchdog(ticker, send_alerts=True):
    """Lightweight rapid check — only move detectors, no full pattern scan."""
    if ticker not in TICKERS:
        print(f"Unknown ticker: {ticker}")
        return None

    sym = TICKERS[ticker]["symbol"]
    now_et = datetime.now(ET)

    # Only fetch 15m and 1h (fast)
    data = {}
    try:
        import yfinance as yf
        data['15m'] = yf.download(sym, period='1d', interval='15m', progress=False)
        data['1h'] = yf.download(sym, period='5d', interval='1h', progress=False)
        data['1d'] = yf.download(sym, period='3mo', interval='1d', progress=False)
    except Exception as e:
        print(f"Data fetch error for {ticker}: {e}")
        return None

    # Validate data
    for tf in ['15m', '1h', '1d']:
        if tf in data and len(data[tf]) > 5:
            d = data[tf]
            data[tf] = {
                'open': d['Open'].values.flatten().astype(float),
                'high': d['High'].values.flatten().astype(float),
                'low': d['Low'].values.flatten().astype(float),
                'close': d['Close'].values.flatten().astype(float),
                'volume': d['Volume'].values.flatten().astype(float) if 'Volume' in d else None,
            }
        else:
            data[tf] = None

    if data['1d'] is None:
        print(f"No data for {ticker}")
        return None

    price = float(data['1d']['close'][-1])
    regime = detect_regime(data['1d']['close'])

    # ── RUN MOVE DETECTORS ──
    move_alerts = []

    spike = detect_spike_and_reverse(data['15m'], price)
    if spike:
        move_alerts.append(('spike', spike))

    dip = detect_dip_and_reverse(data['15m'], price)
    if dip:
        move_alerts.append(('dip', dip))

    momentum = detect_momentum_acceleration(data['1h'])
    if momentum:
        move_alerts.append(('momentum', momentum))

    macro = detect_macro_override(data['1d'], data['15m'], price, regime)
    if macro:
        move_alerts.append(('macro', macro))

    # ── CHECK LAST STATE (avoid duplicate alerts) ──
    state_file = WATCHDOG_DIR / f"watchdog_{ticker.lower()}.json"
    last_state = {}
    if state_file.exists():
        try:
            last_state = json.loads(state_file.read_text())
        except:
            pass

    # Build current state fingerprint
    current_state = {}
    for alert_type, alert_data in move_alerts:
        # Key = type + action + rounded price level
        if 'peak' in alert_data:
            key = f"{alert_type}_{alert_data['action']}_{alert_data.get('peak', alert_data.get('dip', '')):.0f}"
        elif 'total_drop_pct' in alert_data:
            key = f"{alert_type}_{alert_data['action']}_{alert_data['total_drop_pct']:.0f}"
        elif 'total_gain_pct' in alert_data:
            key = f"{alert_type}_{alert_data['action']}_{alert_data['total_gain_pct']:.0f}"
        elif 'ceiling' in alert_data:
            key = f"{alert_type}_{alert_data['action']}_{alert_data['ceiling']:.0f}"
        elif 'floor' in alert_data:
            key = f"{alert_type}_{alert_data['action']}_{alert_data['floor']:.0f}"
        else:
            key = f"{alert_type}_{alert_data['action']}"
        current_state[key] = alert_data

    # Find NEW alerts (not in last state)
    new_alerts = []
    for key, alert_data in current_state.items():
        if key not in last_state:
            new_alerts.append((key, alert_data))

    # ── FORMAT WATCHDOG ALERT ──
    if new_alerts or move_alerts or True:  # always report status
        # Build brief status
        lines = []
        lines.append(f"⚡ **{ticker}** ${price:.2f} {now_et.strftime('%H:%M')}")

        if move_alerts:
            for alert_type, alert in move_alerts:
                if alert['type'] == 'SPIKE_REVERSE':
                    lines.append(f"🔴 SPIKE&REV Peak ${alert['peak']} → Now ${price:.2f} (−{alert['reverse_pct']:.1f}%)")
                elif alert['type'] == 'DIP_REVERSE':
                    lines.append(f"🟢 DIP&REV Low ${alert['dip']} → Now ${price:.2f} (+{alert['bounce_pct']:.1f}%)")
                elif alert['type'] == 'MOMENTUM_SELL':
                    lines.append(f"🔴 MOM SELL {alert['consecutive_red']} red 1h (−{alert['total_drop_pct']:.1f}%)")
                elif alert['type'] == 'MOMENTUM_BUY':
                    lines.append(f"🟢 MOM BUY {alert['consecutive_green']} green 1h (+{alert['total_gain_pct']:.1f}%)")
                elif alert['type'] == 'MACRO_M_OVERRIDE':
                    lines.append(f"⚠️ MACRO M ${alert['ceiling']}→${alert['floor']} ({alert['pct']:.0f}%)")
                elif alert['type'] == 'MACRO_W_OVERRIDE':
                    lines.append(f"✅ MACRO W ${alert['floor']}→${alert['ceiling']} ({alert['pct']:.0f}%)")
        else:
            lines.append("— No active move alerts")

        # Show new alerts specifically
        if new_alerts:
            lines.append("🆕 **NEW:**")
            for key, alert in new_alerts:
                lines.append(f"  → {key}")

        output = "\n".join(lines)
        print(output)

        # Send alert for NEW detectors only
        if send_alerts and new_alerts:
            try:
                from telegram_bot import send_message
                send_message(output)
            except:
                pass

    # Save state
    try:
        state_file.write_text(json.dumps(current_state, indent=2, default=str))
    except:
        pass

    return move_alerts


if __name__ == "__main__":
    t = sys.argv[1] if len(sys.argv) > 1 else "WTI"
    send = "--no-send" not in sys.argv
    result = run_watchdog(t, send_alerts=send)