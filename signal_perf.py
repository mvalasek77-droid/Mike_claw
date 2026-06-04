#!/usr/bin/env python3
"""
Signal Performance Tracker
============================
Shared module — imported by binary_signal.py and rgti_turn_detector.py.

Reads signal_outcomes.jsonl, computes win/loss/pending stats,
and formats a compact performance line for every alert.

Rules:
  - Only closed outcomes count (closed_stop, closed_target, closed_60m)
  - Win = close_pnl > 0, Loss = close_pnl <= 0
  - Pending = not yet closed
  - Performance line: "🏆 W3 L1 (75%) | 2 pending | avg +2.1%"
"""
import json
from pathlib import Path
from datetime import datetime

STORAGE = Path(__file__).parent / "storage"
OUTCOME_LOG = STORAGE / "signal_outcomes.jsonl"


def load_outcomes(sym=None):
    """Load all outcomes, optionally filtered by symbol."""
    outcomes = []
    if not OUTCOME_LOG.exists():
        return outcomes
    for line in OUTCOME_LOG.read_text().strip().split('\n'):
        line = line.strip()
        if not line:
            continue
        try:
            o = json.loads(line)
            if sym and o.get("sym") != sym:
                continue
            outcomes.append(o)
        except:
            continue
    return outcomes


def compute_stats(sym=None, lookback_days=30):
    """Compute win/loss/pending stats from closed outcomes."""
    outcomes = load_outcomes(sym)
    now = datetime.utcnow()
    cutoff = now.timestamp() - (lookback_days * 86400)

    wins = 0
    losses = 0
    pending = 0
    pnl_list = []

    for o in outcomes:
        ts = o.get("signal_ts", o.get("ts", ""))
        try:
            t = datetime.fromisoformat(ts).timestamp()
            if t < cutoff:
                continue
        except:
            pass

        status = o.get("status", "")
        if status == "pending":
            pending += 1
            continue

        pnl = o.get("close_pnl")
        if pnl is None:
            # Try 60m then 30m
            pnl = o.get("pnl_60m") or o.get("pnl_30m")

        if status.startswith("closed") and pnl is not None:
            if pnl > 0:
                wins += 1
            else:
                losses += 1
            pnl_list.append(pnl)

    total = wins + losses
    win_pct = round(wins / total * 100) if total > 0 else 0
    avg_pnl = round(sum(pnl_list) / len(pnl_list), 1) if pnl_list else 0

    return {
        "wins": wins,
        "losses": losses,
        "total": total,
        "win_pct": win_pct,
        "pending": pending,
        "avg_pnl": avg_pnl,
    }


def perf_line(sym=None, lookback_days=30):
    """Format compact performance line for Telegram alerts.

    Examples:
      🏆 W3 L1 (75%) | 2 open | avg +2.1%
      🏆 0 trades | 3 open
    """
    s = compute_stats(sym, lookback_days)
    if s["total"] == 0 and s["pending"] == 0:
        return "🏆 No track record yet"

    parts = []
    if s["total"] > 0:
        parts.append(f"W{s['wins']} L{s['losses']} ({s['win_pct']}%)")
    else:
        parts.append("0 trades")

    if s["pending"] > 0:
        parts.append(f"{s['pending']} open")

    if s["total"] > 0:
        sign = "+" if s["avg_pnl"] > 0 else ""
        parts.append(f"avg {sign}{s['avg_pnl']}%")

    return "🏆 " + " | ".join(parts)


def oil_perf_line(lookback_days=30):
    return perf_line("WTI", lookback_days)


def rgti_perf_line(lookback_days=30):
    return perf_line("RGTI", lookback_days)


if __name__ == "__main__":
    print("Oil:", oil_perf_line())
    print("RGTI:", rgti_perf_line())
    print("All:", perf_line())