"""Main 30-minute loop. Pulls data, computes signals, sends hard buy/sell alerts.

Operates in *signal-only* mode: every cycle, the bot decides BUY HOU,
BUY HOD, SELL (close current position), HOLD, or STAY OUT, and pushes the
alert through the configured channel. The paper broker mirrors what a
human would do so we can score the bot honestly while you trade manually
on Mogo.
"""
from __future__ import annotations

import time
import traceback
from datetime import datetime, time as dtime, date
from zoneinfo import ZoneInfo

from .config import CFG
from .data.feed import fetch
from .execution.alerts import Alerter
from .execution.paper import PaperBroker
from .forecast.alpha_beta import forecast as ab_forecast
from .forecast.viability import evaluate as viability
from .learning.evaluator import inverse_variance_weights, per_strategy_returns, regime_hit_rate
from .learning.tracker import Journal
from .risk.limits import DailyLossCap, eia_blackout
from .risk.sizing import atr_stop_price, vol_target_units
from .strategy.oil_ensemble import OilEnsemble
from .ta.indicators import atr, realized_vol
from .ta.regime import classify
from .ta.trendlines import break_state, current_trendlines

TZ = ZoneInfo(CFG.timezone)


def market_open(now: datetime | None = None) -> bool:
    now = now or datetime.now(TZ)
    if now.weekday() >= 5:
        return False
    o = dtime.fromisoformat(CFG.tsx_open)
    c = dtime.fromisoformat(CFG.tsx_close)
    return o <= now.time() <= c


def build_context() -> dict:
    daily_und = fetch(CFG.underlying_ticker, CFG.daily_interval, CFG.history_days_daily)
    intra_und = fetch(CFG.underlying_ticker, CFG.bar_interval, CFG.history_days_intraday)
    hou = fetch(CFG.longs_ticker, CFG.bar_interval, CFG.history_days_intraday)
    hod = fetch(CFG.shorts_ticker, CFG.bar_interval, CFG.history_days_intraday)

    atr_val = float(atr(intra_und, CFG.atr_period).iloc[-1] or 0.0)
    sup, res = current_trendlines(
        intra_und, CFG.pivot_left, CFG.pivot_right,
        CFG.trendline_lookback_pivots, CFG.min_pivots_for_line,
    )
    bstate = break_state(intra_und, sup, res, atr_val, CFG.break_atr_buffer)
    regime = classify(intra_und, CFG.adx_trend_threshold, CFG.realized_vol_window)

    return {
        "daily_underlying": daily_und,
        "intraday_underlying": intra_und,
        "hou": hou,
        "hod": hod,
        "atr": atr_val,
        "support": sup,
        "resistance": res,
        "break_state": bstate,
        "regime": regime,
    }


def _decide_and_alert(
    broker: PaperBroker,
    ensemble: OilEnsemble,
    alerter: Alerter,
    journal: Journal,
    cap: DailyLossCap,
) -> None:
    now = datetime.now(TZ)
    today: date = now.date()

    if eia_blackout(now, CFG.eia_blackout_minutes, CFG.timezone):
        alerter.send("STAY OUT — EIA blackout", "Crude inventories printing; bot is paused +/- 20 min.")
        return

    ctx = build_context()
    sig = ensemble.signal(ctx)

    journal.append({"kind": "signal", "side": sig.side, "conf": sig.confidence,
                    "rationale": sig.rationale, "regime": ctx["regime"]})

    # Manage open position first
    if broker.position:
        is_long_hou = broker.position.ticker == CFG.longs_ticker
        etf_df = ctx["hou"] if is_long_hou else ctx["hod"]
        last_price = float(etf_df["close"].iloc[-1])
        stop_hit = last_price <= broker.position.stop
        wrong_side = (
            (is_long_hou and sig.side == "long_hod") or
            ((not is_long_hou) and sig.side == "long_hou")
        )
        held_days = (now.date() - broker.position.entry_time.date()).days
        decay_exit = held_days >= CFG.max_hold_days

        if stop_hit or wrong_side or decay_exit:
            reason = "stop" if stop_hit else ("flip" if wrong_side else "decay_exit")
            held_ticker = broker.position.ticker
            pnl = broker.sell(last_price, now, reason=reason)
            cap.add(pnl, today)
            journal.append({"kind": "outcome", "ticker": held_ticker,
                            "return_pct": pnl / max(CFG.account_size_cad, 1.0),
                            "strategy": ensemble.name,
                            "regime": ctx["regime"], "reason": reason,
                            "pnl_cad": pnl})
            alerter.send(
                f"SELL {held_ticker} ({reason})",
                f"Mogo action: SELL all your {held_ticker} now.\n"
                f"Price: {last_price:.2f}  Realised P&L: ${pnl:+.2f}",
            )
            return

    if cap.tripped(today):
        alerter.send("STAY OUT — daily loss cap tripped",
                     f"Cumulative pnl today: ${cap.pnl:+.2f} (cap ${-cap.cap:.2f}). No new trades.")
        return

    if sig.side == "flat":
        alerter.send(
            "STAY OUT — no edge",
            f"Regime: {ctx['regime']}\nMembers: {sig.rationale}",
        )
        return

    # Forecast alpha/beta for the candidate ETF
    target_ticker = CFG.longs_ticker if sig.side == "long_hou" else CFG.shorts_ticker
    etf_df = ctx["hou"] if sig.side == "long_hou" else ctx["hod"]
    und_df = ctx["intraday_underlying"]
    price = float(etf_df["close"].iloc[-1])

    crude_vol_30m = float(realized_vol(und_df["close"], window=20, ann=1).iloc[-1] or 0.01)
    hit_rate = regime_hit_rate(journal.load(), ctx["regime"], prior=0.55)
    forecast_ab = ab_forecast(
        etf_close=etf_df["close"],
        underlying_close=und_df["close"],
        strategy_signed_conviction=sig.signed,
        crude_vol_30m=crude_vol_30m,
        hit_rate=hit_rate,
        window=CFG.beta_window_bars,
    )

    if broker.position and broker.position.ticker == target_ticker:
        alerter.send(
            f"HOLD {target_ticker}",
            f"Already long {target_ticker} ({broker.position.units} sh @ "
            f"{broker.position.entry_price:.2f}, stop {broker.position.stop:.2f}).\n"
            f"Forecast next 30m: alpha={forecast_ab.expected_return_30m:+.3%} "
            f"beta={forecast_ab.beta:+.2f} 1σ={forecast_ab.expected_vol_30m:.3%}\n"
            f"Rationale: {sig.rationale}",
        )
        return

    v = viability(
        account_cad=CFG.account_size_cad,
        etf_price=price,
        expected_return_30m=forecast_ab.expected_return_30m,
        expected_vol_30m=forecast_ab.expected_vol_30m,
        max_position_fraction=CFG.max_position_fraction,
        min_units=CFG.min_units,
        slippage_pct=CFG.slippage_pct,
        commission=CFG.mogo_commission,
        min_expected_move_pct=CFG.min_expected_move_pct,
    )

    open_now = market_open(now)
    decision_word = "BUY" if v.ok and open_now else ("STAY OUT" if not v.ok else "WAIT FOR OPEN")

    if v.ok and open_now:
        atr_etf = float(atr(etf_df, CFG.atr_period).iloc[-1] or 0.0)
        stop = atr_stop_price(price, atr_etf, "long", CFG.atr_stop_mult)
        units = min(v.units, vol_target_units(
            CFG.account_size_cad, CFG.target_annual_vol, price,
            float(realized_vol(etf_df["close"], CFG.realized_vol_window).iloc[-1] or 0.5),
            CFG.max_position_fraction,
        ) or v.units)
        units = max(units, CFG.min_units)
        broker.buy(target_ticker, units, price, stop, now)
        journal.append({"kind": "entry", "ticker": target_ticker, "units": units,
                        "price": price, "stop": stop, "conf": sig.confidence,
                        "regime": ctx["regime"], "alpha": forecast_ab.expected_return_30m,
                        "beta": forecast_ab.beta})

    title = (
        f"{decision_word} {target_ticker}"
        f"  alpha={forecast_ab.expected_return_30m:+.3%}"
        f"  beta={forecast_ab.beta:+.2f}"
    )
    body_lines = [
        f"Account: ${CFG.account_size_cad:.0f}  Price: ${price:.2f}",
        f"Suggested units: {v.units}  Notional: ${v.notional:.2f}",
        f"Expected $ profit next 30m: ${v.expected_profit_cad:+.2f}",
        f"1σ downside next 30m: ${v.expected_loss_1sigma_cad:.2f}",
        f"Reward/risk: {v.reward_to_risk:.2f}",
        f"Regime: {ctx['regime']}  Hit-rate prior: {hit_rate:.0%}",
        f"Forecast detail: {forecast_ab.note}",
        f"Ensemble: {sig.rationale}",
        f"Viability: {v.reason}",
        f"Market open: {open_now}",
        f"Mogo action: {decision_word} {target_ticker} ({v.units} sh) — tap manually.",
    ]
    alerter.send(title, "\n".join(body_lines))


def _update_weights(ensemble: OilEnsemble, journal: Journal) -> None:
    recs = journal.load()
    rets = per_strategy_returns(recs)
    if not rets:
        return
    w = inverse_variance_weights(rets)
    if w:
        ensemble.weights.update(w)
        journal.append({"kind": "weights_updated", "weights": ensemble.weights})


def main(poll_seconds: int | None = None, learn_every: int = 20) -> None:
    CFG.data_dir.mkdir(parents=True, exist_ok=True)
    CFG.journal_dir.mkdir(parents=True, exist_ok=True)
    poll = poll_seconds or CFG.poll_seconds

    broker = PaperBroker(cash=CFG.paper_starting_cash)
    ensemble = OilEnsemble(min_confidence=CFG.min_signal_confidence)
    alerter = Alerter(
        channel=CFG.alert_channel,
        webhook_url=CFG.alert_webhook_url,
        log_path=CFG.journal_dir / "alerts.log",
    )
    journal = Journal(CFG.journal_dir / "signals.jsonl")
    cap = DailyLossCap(CFG.daily_loss_cap_pct, CFG.account_size_cad)

    alerter.send(
        "Oil bot started",
        f"Universe: {CFG.longs_ticker} / {CFG.shorts_ticker}; underlying {CFG.underlying_ticker}.\n"
        f"30-min loop, ${CFG.account_size_cad:.0f} account, signal-only (Mogo manual).",
    )

    i = 0
    while True:
        try:
            _decide_and_alert(broker, ensemble, alerter, journal, cap)
            i += 1
            if i % learn_every == 0:
                _update_weights(ensemble, journal)
        except Exception as e:
            alerter.send("Bot error", f"{e}\n{traceback.format_exc()}")
        time.sleep(poll)


if __name__ == "__main__":
    main()
