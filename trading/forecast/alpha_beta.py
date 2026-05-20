"""30-minute alpha & beta forecasts.

Beta:
    Rolling OLS of ETF log-returns on WTI (CL=F) log-returns over the last
    `window` 30-min bars. For 2x leveraged HOU we expect beta ~ +2 to crude;
    for 2x inverse HOD we expect beta ~ -2.

Alpha (forward 30-min expected return on the ETF):
    alpha_etf_30m = beta * E[r_crude_30m] + idiosyncratic_drift

    E[r_crude_30m] is built from:
        - sign and conviction of the active strategy ensemble
        - magnitude scaled by recent realized vol on the 30-min bar
        - tempered by a historical hit-rate of the same regime+strategy
          read from the learning journal (no journal yet => prior 0.55)

This is a *model estimate*, not a guarantee. It is the bot's best forward
look used to decide whether a trade is economically worth taking on $180.
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np
import pandas as pd


@dataclass
class AlphaBeta:
    beta: float
    beta_r2: float
    expected_return_30m: float   # decimal, e.g. 0.008 = 0.8%
    expected_vol_30m: float      # 1-sigma move over next 30m, decimal
    crude_expected_30m: float    # expected WTI move feeding the model
    sample_n: int
    note: str


def _log_returns(close: pd.Series) -> pd.Series:
    return np.log(close / close.shift()).dropna()


def rolling_beta(etf_close: pd.Series, underlying_close: pd.Series, window: int = 100) -> tuple[float, float, int]:
    """Beta of ETF on underlying via OLS over the last `window` aligned bars."""
    df = pd.concat({"etf": _log_returns(etf_close), "und": _log_returns(underlying_close)}, axis=1).dropna()
    if len(df) < 20:
        return 0.0, 0.0, len(df)
    df = df.iloc[-window:]
    x = df["und"].values
    y = df["etf"].values
    var_x = x.var()
    if var_x <= 0:
        return 0.0, 0.0, len(df)
    cov_xy = ((x - x.mean()) * (y - y.mean())).mean()
    beta = float(cov_xy / var_x)
    pred = beta * (x - x.mean()) + y.mean()
    ss_res = float(((y - pred) ** 2).sum())
    ss_tot = float(((y - y.mean()) ** 2).sum()) or 1.0
    r2 = 1.0 - ss_res / ss_tot
    return beta, float(r2), len(df)


def forecast(
    etf_close: pd.Series,
    underlying_close: pd.Series,
    strategy_signed_conviction: float,
    crude_vol_30m: float,
    hit_rate: float = 0.55,
    window: int = 100,
) -> AlphaBeta:
    """Produce a 30-minute alpha/beta forecast for an ETF.

    Parameters
    ----------
    strategy_signed_conviction:
        +conviction (0..1) for "expect crude up", -conviction for "expect crude down".
    crude_vol_30m:
        1-sigma 30-min log-return of crude (rolling stdev).
    hit_rate:
        Walk-forward win rate of the active strategy in current regime.
        Used to scale conviction into an expected return.
    """
    beta, r2, n = rolling_beta(etf_close, underlying_close, window)

    # Expected directional move on crude: edge = (2*hit_rate - 1) scales conviction
    edge = max(0.0, 2 * hit_rate - 1.0)
    crude_expected = strategy_signed_conviction * edge * crude_vol_30m

    # ETF expected return = beta * crude expected (idiosyncratic drift ~0 over 30m)
    etf_expected = beta * crude_expected

    # 1-sigma ETF vol = |beta| * crude vol (ignoring residual; conservative)
    etf_vol = abs(beta) * crude_vol_30m

    note = (
        f"beta={beta:+.2f} r2={r2:.2f} n={n} "
        f"crude_E[r]={crude_expected:+.4f} edge={edge:.2f} hit={hit_rate:.2f}"
    )

    return AlphaBeta(
        beta=beta,
        beta_r2=r2,
        expected_return_30m=float(etf_expected),
        expected_vol_30m=float(etf_vol),
        crude_expected_30m=float(crude_expected),
        sample_n=n,
        note=note,
    )
