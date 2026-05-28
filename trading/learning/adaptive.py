"""Adaptive learning engine — learns from EVERY trade to master 15m timeframes.

Core principles:
    1. RECENCY: Recent trades matter exponentially more than old ones (EMA decay)
    2. SPEED: Weights update after EVERY trade outcome, not every N cycles
    3. REGIME AWARENESS: Different weights per regime (trend/chop/shock)
    4. PARAMETER TUNING: Auto-adjust ATR multipliers, lookbacks, buffers based on PnL
    5. COMPOUNDING: Track account growth and adjust position sizing

This replaces the passive `evaluator.py` approach with an aggressive,
always-learning system designed for a small $180 account targeting $5-10/hr.
"""
from __future__ import annotations

import math
from collections import defaultdict
from dataclasses import dataclass, field
from typing import Any

import numpy as np


# ──────────────────────────────────────────────────────────────────────
# Rolling trade book — matches entries to exits for per-strategy scoring
# ──────────────────────────────────────────────────────────────────────

@dataclass
class OpenTrade:
    """A trade we entered but haven't exited yet."""
    entry_ts: str
    ticker: str
    side: str           # "long_hou" or "long_hod"
    units: int
    entry_price: float
    stop: float
    strategy: str       # which ensemble member(s) voted for this
    regime: str
    confidence: float
    alpha: float         # expected return at entry
    beta: float

@dataclass
class ClosedTrade(OpenTrade):
    """A trade that has been closed with a PnL result."""
    exit_ts: str
    exit_price: float
    pnl_cad: float
    return_pct: float    # pnl / Account at entry
    hold_bars: int       # how many 15m bars held
    exit_reason: str     # "stop", "flip", "decay_exit", "signal_exit"


class TradeBook:
    """Tracks open positions and matches entries to exits.

    When an exit happens, the trade's PnL is attributed to the strategies
    that voted for it, enabling per-strategy recency-weighted scoring.
    """
    def __init__(self):
        self.open: dict[str, OpenTrade] = {}   # ticker -> OpenTrade
        self.closed: list[ClosedTrade] = []

    def open_trade(self, trade: OpenTrade) -> None:
        self.open[trade.ticker] = trade

    def close_trade(self, ticker: str, exit_ts: str, exit_price: float,
                     exit_reason: str, account_at_entry: float) -> ClosedTrade | None:
        t = self.open.pop(ticker, None)
        if t is None:
            return None
        pnl = (exit_price - t.entry_price) * t.units
        if t.side == "long_hod":
            pnl = -pnl  # HOD profits when price drops
        ret = pnl / max(account_at_entry, 1.0)
        closed = ClosedTrade(
            exit_ts=exit_ts, exit_price=exit_price,
            pnl_cad=pnl, return_pct=ret,
            hold_bars=0, exit_reason=exit_reason,
            **{k: getattr(t, k) for k in t.__dataclass_fields__ if k not in ()},
        )
        self.closed.append(closed)
        return closed

    def recent_returns(self, strategy: str | None = None,
                       regime: str | None = None,
                       max_trades: int = 50) -> np.ndarray:
        """Get recent trade returns, optionally filtered."""
        trades = self.closed
        if strategy:
            trades = [t for t in trades if strategy in t.strategy]
        if regime:
            trades = [t for t in trades if t.regime == regime]
        trades = trades[-max_trades:]
        return np.array([t.return_pct for t in trades]) if trades else np.array([])


# ──────────────────────────────────────────────────────────────────────
# Recency-weighted strategy scoring
# ──────────────────────────────────────────────────────────────────────

@dataclass
class StrategyScore:
    strategy: str
    regime: str
    n_trades: int
    hit_rate: float       # % of trades profitable
    avg_return: float     # EMA-smoothed average return
    score: float          # composite 0-1 (higher = more weight)
    last_updated: str = ""


class RecencyScorer:
    """EMA-decay weighted scoring: recent outcomes dominate.

    Formula per strategy per regime:
        hit_rate_ema = α * is_win + (1-α) * prev_hit_rate
        return_ema  = α * return_pct + (1-α) * prev_avg_return
        score = hit_rate_ema * (1 + max(0, return_ema * 10))  # bonus for profitable

    α (ema_alpha) controls how fast we forget: 0.3 = very fast, 0.1 = slower
    """
    def __init__(self, ema_alpha: float = 0.25, min_trades: int = 3):
        self.ema_alpha = ema_alpha
        self.min_trades = min_trades
        # Nested dict: scores[strategy][regime] -> StrategyScore
        self.scores: dict[str, dict[str, StrategyScore]] = defaultdict(dict)
        # Count of trades per strategy/regime
        self.counts: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))

    def update(self, strategy_name: str, regime: str, return_pct: float) -> StrategyScore:
        """Update a strategy's score after a trade outcome."""
        self.counts[strategy_name][regime] += 1
        is_win = 1.0 if return_pct > 0 else 0.0
        existing = self.scores.get(strategy_name, {}).get(regime)

        if existing is None:
            # First trade for this strategy+regime
            score = StrategyScore(
                strategy=strategy_name, regime=regime,
                n_trades=1, hit_rate=is_win,
                avg_return=return_pct,
                score=0.5,  # neutral until we have data
            )
        else:
            # EMA update
            α = self.ema_alpha
            new_hit = α * is_win + (1 - α) * existing.hit_rate
            new_ret = α * return_pct + (1 - α) * existing.avg_return
            n = self.counts[strategy_name][regime]
            # Score: hit rate weighted heavily, with return bonus
            base = new_hit
            return_bonus = max(0.0, new_ret * 10)  # 10x amplify small returns
            score_val = min(1.0, base + return_bonus)
            # Penalty for too few trades — don't trust early results
            if n < self.min_trades:
                score_val = score_val * (n / self.min_trades) * 0.5 + 0.5 * (1 - n / self.min_trades)
            score = StrategyScore(
                strategy=strategy_name, regime=regime,
                n_trades=n, hit_rate=new_hit,
                avg_return=new_ret, score=score_val,
            )
        self.scores[strategy_name][regime] = score
        return score

    def get_weights(self, strategy_names: list[str], regime: str) -> dict[str, float]:
        """Compute recency-weighted strategy weights for a given regime.

        Falls back to equal weight if no data. Boosts the primary (wick_channel)
        by 2x before normalizing.
        """
        base_mult = {"wick_channel": 2.0}  # always boost primary
        raw: dict[str, float] = {}

        for name in strategy_names:
            sc = self.scores.get(name, {}).get(regime)
            mult = base_mult.get(name, 1.0)
            if sc and sc.n_trades >= self.min_trades:
                raw[name] = sc.score * mult
            else:
                raw[name] = 0.5 * mult  # neutral prior

        total = sum(raw.values())
        if total <= 0:
            n = len(strategy_names)
            return {k: 1.0 / n for k in strategy_names}
        return {k: v / total for k, v in raw.items()}

    def hit_rate_for_forecast(self, regime: str, prior: float = 0.55) -> float:
        """Regime hit rate for the alpha forecaster — across all strategies."""
        all_returns = []
        for strat_scores in self.scores.values():
            sc = strat_scores.get(regime)
            if sc and sc.n_trades >= self.min_trades:
                all_returns.append(sc.hit_rate)
        if not all_returns:
            return prior
        return float(np.mean(all_returns))


# ──────────────────────────────────────────────────────────────────────
# Parameter auto-tuner — adjusts detection thresholds based on outcomes
# ──────────────────────────────────────────────────────────────────────

@dataclass
class TunableParams:
    """Parameters that the auto-tuner can adjust.

    Ranges define the min/max — tuner searches within bounds.
    """
    # Wick channel detection
    near_buffer_atr: float = 0.3      # min 0.1, max 0.8
    break_buffer_atr: float = 0.5     # min 0.2, max 1.0
    top_n_wicks: int = 6              # min 3, max 10
    lookback_bars: int = 200          # min 40, max 400

    # Strategy thresholds
    min_confidence: float = 0.15     # min 0.05, max 0.40
    atr_stop_mult: float = 1.5       # min 0.5, max 3.0
    channel_narrow_pct: float = 0.5  # fraction of ATR, min 0.2, max 1.0

    # Risk
    daily_loss_cap_pct: float = 0.05 # min 0.02, max 0.10


# Ranges for each parameter (min, max, step)
PARAM_RANGES = {
    "near_buffer_atr": (0.1, 0.8, 0.05),
    "break_buffer_atr": (0.2, 1.0, 0.05),
    "top_n_wicks": (3, 10, 1),
    "lookback_bars": (40, 400, 20),
    "min_confidence": (0.05, 0.40, 0.05),
    "atr_stop_mult": (0.5, 3.0, 0.25),
    "channel_narrow_pct": (0.2, 1.0, 0.1),
    "daily_loss_cap_pct": (0.02, 0.10, 0.01),
}


class AutoTuner:
    """Gradient-free parameter optimization using recent trade outcomes.

    Every N trades (tune_every), evaluates whether to nudge each parameter
    up or down by one step. Uses the last `window` trades' Sharpe-like score
    as the objective.

    Simple 1D coordinate descent: for each param, try +step and -step,
    pick whichever improves the objective.
    """
    def __init__(self, params: TunableParams | None = None,
                 tune_every: int = 5, window: int = 20):
        self.params = params or TunableParams()
        self.tune_every = tune_every
        self.window = window
        self.trade_count = 0
        self.recent_pnls: list[float] = []
        self.tune_log: list[dict] = []

    def record_trade(self, pnl_cad: float) -> None:
        self.trade_count += 1
        self.recent_pnls.append(pnl_cad)
        if len(self.recent_pnls) > self.window * 2:
            self.recent_pnls = self.recent_pnls[-self.window * 2:]

    def should_tune(self) -> bool:
        return (self.trade_count >= self.tune_every and
                self.trade_count % self.tune_every == 0 and
                len(self.recent_pnls) >= 5)

    def _objective(self, pnls: list[float] | None = None) -> float:
        """Sharpe-like score: mean / std of recent PnLs. Higher = better."""
        data = np.array(pnls or self.recent_pnls[-self.window:])
        if len(data) < 3:
            return 0.0
        mu = float(data.mean())
        sd = float(data.std()) or 0.001
        return mu / sd

    def tune(self) -> dict[str, Any]:
        """Run one round of parameter tuning. Returns changes made."""
        if not self.should_tune():
            return {}

        current_score = self._objective()
        changes: dict[str, Any] = {}

        for param_name, (lo, hi, step) in PARAM_RANGES.items():
            current_val = getattr(self.params, param_name)

            # Try +step
            up_val = min(hi, current_val + step)
            down_val = max(lo, current_val - step)

            # Simulate: just check if we'd have filtered differently
            # For now, nudge toward the direction that would have taken MORE trades
            # (since we're on $180 and need volume to hit $5-10/hr)
            # This heuristic: if hit rate > 50%, widen/nudge to take more trades;
            # if hit rate < 40%, tighten/nudge to take fewer
            recent_win_rate = float(np.mean([1 if p > 0 else 0 for p in self.recent_pnls[-self.window:]]))

            if param_name in ("near_buffer_atr", "break_buffer_atr", "channel_narrow_pct"):
                # Wider = more signals. Tighter = fewer.
                if recent_win_rate > 0.55 and current_val < hi:
                    new_val = up_val
                elif recent_win_rate < 0.40 and current_val > lo:
                    new_val = down_val
                else:
                    continue
            elif param_name in ("min_confidence", "atr_stop_mult", "daily_loss_cap_pct"):
                # Lower min_confidence = more trades. Lower stop = tighter risk.
                if recent_win_rate > 0.55 and current_val > lo:
                    new_val = down_val  # loosen to take more
                elif recent_win_rate < 0.40 and current_val < hi:
                    new_val = up_val   # tighten to take fewer
                else:
                    continue
            elif param_name in ("lookback_bars", "top_n_wicks"):
                # Lookback: shorter = more reactive. top_n: more = more pivots
                if recent_win_rate > 0.55 and current_val > lo and isinstance(step, int):
                    new_val = max(lo, current_val - step) if param_name == "lookback_bars" else up_val
                elif recent_win_rate < 0.40 and current_val < hi and isinstance(step, int):
                    new_val = min(hi, current_val + step) if param_name == "lookback_bars" else down_val
                else:
                    continue
            else:
                continue

            if new_val != current_val:
                setattr(self.params, param_name, new_val)
                changes[param_name] = {"from": current_val, "to": new_val}

        self.tune_log.append({
            "trade_count": self.trade_count,
            "score": current_score,
            "win_rate": float(np.mean([1 if p > 0 else 0 for p in self.recent_pnls[-self.window:]])),
            "changes": changes,
        })
        return changes


# ──────────────────────────────────────────────────────────────────────
# Compounding position sizer
# ──────────────────────────────────────────────────────────────────────

class CompoundingSizer:
    """Aggressive position sizing for a $180 account targeting $5-10/hr.

    Rules:
    - Base: 95% of account in one position (tiny account, no diversification)
    - After N consecutive wins: bump to 98% for next trade (ride the streak)
    - After a loss: drop to 90% (protect capital)
    - After 2+ consecutive losses: drop to 85% (protect harder)
    - Account grows via compounding as PnL accumulates
    """
    def __init__(self, base_fraction: float = 0.95):
        self.base = base_fraction
        self.consecutive_wins = 0
        self.consecutive_losses = 0
        self.current_account: float = 0.0

    def update_account(self, account_cad: float) -> None:
        self.current_account = account_cad

    def record_outcome(self, pnl: float) -> None:
        if pnl > 0:
            self.consecutive_wins += 1
            self.consecutive_losses = 0
        elif pnl < 0:
            self.consecutive_losses += 1
            self.consecutive_wins = 0

    def position_fraction(self) -> float:
        if self.consecutive_losses >= 2:
            return 0.85
        if self.consecutive_losses >= 1:
            return 0.90
        if self.consecutive_wins >= 3:
            return 0.98
        if self.consecutive_wins >= 1:
            return 0.96
        return self.base

    def units(self, price: float) -> int:
        frac = self.position_fraction()
        budget = self.current_account * frac
        return max(1, int(budget / price))

    def summary(self) -> str:
        return (f"acct=${self.current_account:.0f} frac={self.position_fraction():.0%} "
                f"streak=W{self.consecutive_wins}/L{self.consecutive_losses}")