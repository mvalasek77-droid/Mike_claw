#!/usr/bin/env python3
"""
Signal Outcome Tracker
======================
Checks pending signal outcomes and records actual P&L at 30m and 60m marks.
Run every 5min via cron. Only sends Telegram when an outcome is finalized.

Usage: python3 outcome_tracker.py
Exit: 0 = outcome closed (delivers to Telegram), 1 = nothing to report
"""
import json, sys
from datetime import datetime, timedelta
from pathlib import Path

import yfinance as yf

STORAGE = Path(__file__).parent / "storage"
OUTCOME_LOG = STORAGE / "signal_outcomes.jsonl"
LAST_SIGNAL = STORAGE / "last_oil_signal.json"

BOT_TOKEN = "8784772860:AAHcL7WpZf8M1QfHfG8h"
CHAT_ID = "8355819128"


def send_telegram(msg):
    import requests
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
    try:
        r = requests.post(url, json={"chat_id": CHAT_ID, "text": msg, "parse_mode": "Markdown"}, timeout=10)
        return r.status_code == 200
    except:
        return False


def get_current_price(sym):
    """Get current price for symbol."""
    ticker_map = {"WTI": "CL=F", "RGTI": "RGTI"}
    yf_sym = ticker_map.get(sym, sym)
    try:
        t = yf.Ticker(yf_sym)
        h = t.history(period="1d", interval="1m")
        if not h.empty:
            return float(h['Close'].iloc[-1])
    except:
        pass
    return None


def calc_pnl(signal, entry, current):
    """Calculate P&L percentage based on signal direction."""
    if signal == "BUY":
        return round((current - entry) / entry * 100, 2)
    else:  # SELL
        return round((entry - current) / entry * 100, 2)


def check_outcomes():
    """Check all pending outcomes and update with actual P&L."""
    if not OUTCOME_LOG.exists():
        print("No outcome log found")
        return

    lines = OUTCOME_LOG.read_text().strip().split('\n')
    updated_lines = []
    closed_reports = []

    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            o = json.loads(line)
        except:
            updated_lines.append(line)
            continue

        if o.get("status") != "pending":
            updated_lines.append(line)
            continue

        signal_ts = datetime.fromisoformat(o["signal_ts"])
        now = datetime.utcnow()
        age_minutes = (now - signal_ts).total_seconds() / 60

        # Get current price
        cur_price = get_current_price(o.get("sym", "WTI"))
        if cur_price is None:
            updated_lines.append(line)
            continue

        entry = o.get("entry_price", 0)
        signal = o.get("signal", "")
        stop = o.get("stop", 0)
        target = o.get("target", 0)

        pnl = calc_pnl(signal, entry, cur_price)

        # Check stop/target hits
        if signal == "BUY":
            hit_stop = cur_price <= stop
            hit_target = cur_price >= target
        else:  # SELL: price dropping = good
            hit_stop = cur_price >= stop
            hit_target = cur_price <= target

        # Update 30m P&L
        if age_minutes >= 30 and o.get("pnl_30m") is None:
            o["pnl_30m"] = pnl
            o["price_30m"] = cur_price

        # Update 60m P&L
        if age_minutes >= 60 and o.get("pnl_60m") is None:
            o["pnl_60m"] = pnl
            o["price_60m"] = cur_price

        # Close conditions: hit stop, hit target, or 60m elapsed
        closed = False
        close_reason = ""

        if hit_stop:
            o["status"] = "closed_stop"
            o["close_pnl"] = pnl
            o["close_ts"] = now.isoformat()
            close_reason = f"🛑 Hit stop @ ${stop}"
            closed = True
        elif hit_target:
            o["status"] = "closed_target"
            o["close_pnl"] = calc_pnl(signal, entry, target)
            o["close_ts"] = now.isoformat()
            close_reason = f"🎯 Hit target @ ${target}"
            closed = True
        elif age_minutes >= 60:
            o["status"] = "closed_60m"
            o["close_pnl"] = pnl
            o["close_ts"] = now.isoformat()
            close_reason = "⏰ 60m elapsed"
            closed = True

        if closed:
            emoji = "✅" if o["close_pnl"] > 0 else "❌"
            sym = o.get("sym", "WTI")
            report = (
                f"{emoji} **{sym} {signal} CLOSED**\n"
                f"Entry: ${entry} → Now: ${cur_price}\n"
                f"{close_reason}\n"
                f"P&L: **{o['close_pnl']:+.2f}%**\n"
                f"30m: {o.get('pnl_30m', 'N/A')}% | 60m: {o.get('pnl_60m', 'N/A')}%"
            )
            closed_reports.append(report)

        updated_lines.append(json.dumps(o))

    # Rewrite log
    OUTCOME_LOG.write_text('\n'.join(updated_lines) + '\n')

    # Send reports
    if closed_reports:
        msg = '\n\n'.join(closed_reports)
        send_telegram(msg)
        print(msg)
        sys.exit(0)
    else:
        print("No outcomes to close")
        sys.exit(1)


if __name__ == "__main__":
    check_outcomes()