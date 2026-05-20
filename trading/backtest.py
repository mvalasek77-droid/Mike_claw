"""Daily-bar walk-forward backtest of the oil ensemble on HOU/HOD.

Caveats: uses daily bars (intraday history from yfinance is capped at ~60d),
so this validates the regime/strategy logic, not 30-min microstructure. The
real test of the live bot is paper-trading the 30-min loop for 4-8 weeks.
"""
from __future__ import annotations

import argparse

import pandas as pd

from .config import CFG
from .data.feed import fetch
from .risk.sizing import atr_stop_price, vol_target_units
from .strategy.oil_ensemble import OilEnsemble
from .ta.indicators import atr, realized_vol
from .ta.regime import classify
from .ta.trendlines import break_state, current_trendlines


def run(years: int = 2) -> tuple[float, pd.DataFrame]:
    daily_und = fetch(CFG.underlying_ticker, "1d", years * 365)
    hou = fetch(CFG.longs_ticker, "1d", years * 365)
    hod = fetch(CFG.shorts_ticker, "1d", years * 365)

    ens = OilEnsemble(min_confidence=CFG.min_signal_confidence)
    cash = CFG.paper_starting_cash
    pos: dict | None = None
    log: list[dict] = []

    start_i = max(252, CFG.atr_period + CFG.realized_vol_window + 60)
    for i in range(start_i, len(daily_und) - 1):
        upto = daily_und.iloc[: i + 1]
        atr_val = float(atr(upto, CFG.atr_period).iloc[-1] or 0.0)
        sup, res = current_trendlines(
            upto, CFG.pivot_left, CFG.pivot_right,
            CFG.trendline_lookback_pivots, CFG.min_pivots_for_line,
        )
        bstate = break_state(upto, sup, res, atr_val, CFG.break_atr_buffer)
        regime = classify(upto, CFG.adx_trend_threshold, CFG.realized_vol_window)
        ctx = {
            "daily_underlying": upto,
            "intraday_underlying": upto,
            "hou": hou.iloc[: i + 1],
            "hod": hod.iloc[: i + 1],
            "atr": atr_val,
            "support": sup,
            "resistance": res,
            "break_state": bstate,
            "regime": regime,
        }
        sig = ens.signal(ctx)
        nxt = daily_und.index[i + 1]

        if pos is not None:
            etf_df = hou if pos["ticker"] == CFG.longs_ticker else hod
            if nxt in etf_df.index:
                row = etf_df.loc[nxt]
                if float(row["low"]) <= pos["stop"]:
                    pnl = (pos["stop"] - pos["entry"]) * pos["units"]
                    cash += pos["units"] * pos["entry"] + pnl
                    log.append({"ts": str(nxt), "action": "stop", "pnl": pnl,
                                "ticker": pos["ticker"]})
                    pos = None
                elif (i + 1 - pos["entry_idx"]) >= CFG.max_hold_days:
                    pnl = (float(row["close"]) - pos["entry"]) * pos["units"]
                    cash += pos["units"] * pos["entry"] + pnl
                    log.append({"ts": str(nxt), "action": "decay_exit", "pnl": pnl,
                                "ticker": pos["ticker"]})
                    pos = None

        if pos is None and sig.side != "flat":
            target = CFG.longs_ticker if sig.side == "long_hou" else CFG.shorts_ticker
            etf_df = hou if target == CFG.longs_ticker else hod
            if nxt in etf_df.index:
                price = float(etf_df.loc[nxt]["open"])
                rv = float(realized_vol(etf_df["close"].iloc[: i + 1], CFG.realized_vol_window).iloc[-1] or 0.5)
                units = vol_target_units(cash, CFG.target_annual_vol, price, rv,
                                         CFG.max_position_fraction)
                if units > 0:
                    cash -= units * price
                    pos = {
                        "ticker": target,
                        "units": units,
                        "entry": price,
                        "entry_idx": i + 1,
                        "stop": atr_stop_price(
                            price,
                            float(atr(etf_df.iloc[: i + 1], CFG.atr_period).iloc[-1] or 0.0),
                            "long",
                            CFG.atr_stop_mult,
                        ),
                    }
                    log.append({"ts": str(nxt), "action": "buy", "ticker": target,
                                "units": units, "price": price})

    if pos is not None:
        etf_df = hou if pos["ticker"] == CFG.longs_ticker else hod
        cash += pos["units"] * float(etf_df["close"].iloc[-1])

    df = pd.DataFrame(log)
    print(f"Backtest end equity: ${cash:.2f}  (start ${CFG.paper_starting_cash:.2f})")
    print(f"Total trades: {len(df)}")
    if not df.empty and "pnl" in df.columns:
        wins = (df["pnl"] > 0).sum()
        losses = (df["pnl"] <= 0).sum()
        print(f"Closed trades: wins={wins} losses={losses} hit_rate={wins/max(wins+losses,1):.0%}")
    return cash, df


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--years", type=int, default=2)
    args = parser.parse_args()
    run(args.years)
