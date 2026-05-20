"""Economic viability gate for a small ($180) account.

Decision is YES only if all of:
    1. Expected ETF return over next 30 min exceeds slippage + minimum move.
    2. Position can be sized to >= min_units whole shares.
    3. Expected $ profit (account_size * |expected_return| - slippage_dollars)
       is positive and meaningful (> $0.50 by default — half a dollar of edge
       per click is the floor; lower than that, just wait).
    4. Expected reward / 1-sigma vol >= 0.25 (avoid lottery tickets).
"""
from __future__ import annotations

import math
from dataclasses import dataclass


@dataclass
class ViabilityResult:
    ok: bool
    units: int
    notional: float
    expected_profit_cad: float
    expected_loss_1sigma_cad: float
    reward_to_risk: float
    reason: str


def evaluate(
    account_cad: float,
    etf_price: float,
    expected_return_30m: float,
    expected_vol_30m: float,
    *,
    max_position_fraction: float = 0.95,
    min_units: int = 1,
    slippage_pct: float = 0.002,
    commission: float = 0.0,
    min_expected_move_pct: float = 0.006,
    min_dollar_edge: float = 0.50,
    min_reward_risk: float = 0.25,
) -> ViabilityResult:
    if etf_price <= 0:
        return ViabilityResult(False, 0, 0, 0, 0, 0, "no_price")

    budget = account_cad * max_position_fraction
    units = int(math.floor(budget / etf_price))
    if units < min_units:
        return ViabilityResult(False, units, 0, 0, 0, 0, "insufficient_cash_for_one_share")

    notional = units * etf_price

    # Cost of round-trip
    slippage_dollars = 2 * slippage_pct * notional
    cost = slippage_dollars + 2 * commission

    expected_gross = notional * expected_return_30m  # signed
    expected_profit = expected_gross - cost
    one_sigma_loss = notional * expected_vol_30m

    rr = (expected_profit / one_sigma_loss) if one_sigma_loss > 0 else 0.0

    if abs(expected_return_30m) < min_expected_move_pct:
        return ViabilityResult(False, units, notional, expected_profit, one_sigma_loss, rr,
                               f"expected_move_{expected_return_30m:+.3%}_below_floor_{min_expected_move_pct:.3%}")
    if expected_profit < min_dollar_edge:
        return ViabilityResult(False, units, notional, expected_profit, one_sigma_loss, rr,
                               f"net_edge_${expected_profit:.2f}_below_floor_${min_dollar_edge:.2f}")
    if rr < min_reward_risk:
        return ViabilityResult(False, units, notional, expected_profit, one_sigma_loss, rr,
                               f"reward/risk_{rr:.2f}_below_floor_{min_reward_risk:.2f}")

    return ViabilityResult(True, units, notional, expected_profit, one_sigma_loss, rr,
                           "viable")
