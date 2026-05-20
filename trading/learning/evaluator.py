"""Walk-forward per-strategy evaluation and inverse-variance weighting.

Reads the journal and:
    - groups outcome records by strategy
    - computes per-strategy mean return, vol, Sharpe, hit-rate
    - returns inverse-variance weights so noisier members shrink
"""
from __future__ import annotations

from collections import defaultdict

import numpy as np


def per_strategy_returns(records: list[dict]) -> dict[str, np.ndarray]:
    by: dict[str, list[float]] = defaultdict(list)
    for r in records:
        if r.get("kind") == "outcome" and "strategy" in r and "return_pct" in r:
            try:
                by[r["strategy"]].append(float(r["return_pct"]))
            except (TypeError, ValueError):
                continue
    return {k: np.asarray(v, dtype=float) for k, v in by.items()}


def stats(returns: np.ndarray) -> dict[str, float]:
    if len(returns) == 0:
        return {"n": 0, "mean": 0.0, "vol": 0.0, "sharpe": 0.0, "hit_rate": 0.5}
    mu = float(returns.mean())
    sd = float(returns.std() or 0.0)
    sharpe = float(mu / sd * np.sqrt(252)) if sd > 0 else 0.0
    hit = float((returns > 0).mean()) if len(returns) > 0 else 0.5
    return {"n": int(len(returns)), "mean": mu, "vol": sd, "sharpe": sharpe, "hit_rate": hit}


def inverse_variance_weights(returns_by_strategy: dict[str, np.ndarray]) -> dict[str, float]:
    if not returns_by_strategy:
        return {}
    invs: dict[str, float] = {}
    for k, v in returns_by_strategy.items():
        sd = float(v.std() or 0.0)
        invs[k] = 1.0 / (sd * sd) if sd > 0 else 0.0
    s = sum(invs.values())
    if s <= 0:
        n = len(returns_by_strategy)
        return {k: 1.0 / n for k in returns_by_strategy}
    return {k: v / s for k, v in invs.items()}


def regime_hit_rate(records: list[dict], regime: str, prior: float = 0.55) -> float:
    """Hit rate of any winning outcome in `regime`. Used by the alpha forecaster."""
    wins = 0
    n = 0
    for r in records:
        if r.get("kind") == "outcome" and r.get("regime") == regime and "return_pct" in r:
            try:
                n += 1
                if float(r["return_pct"]) > 0:
                    wins += 1
            except (TypeError, ValueError):
                continue
    if n < 10:
        return prior
    return wins / n
