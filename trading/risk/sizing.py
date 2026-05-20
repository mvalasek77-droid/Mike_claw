"""Position sizing and stop placement.

Vol-targeted sizing (Bridgewater / risk-parity) sets dollar notional
proportional to the inverse of the asset's realised vol; ATR stops
size the loss tolerance to recent noise rather than a fixed percent.
"""
from __future__ import annotations

import math


def vol_target_units(
    account_cad: float,
    target_annual_vol: float,
    etf_price: float,
    etf_realized_vol_annual: float,
    max_fraction: float = 0.95,
) -> int:
    """Whole shares such that account's annualized vol meets target_annual_vol."""
    if etf_realized_vol_annual <= 0 or etf_price <= 0:
        return 0
    notional = account_cad * target_annual_vol / etf_realized_vol_annual
    notional = min(notional, account_cad * max_fraction)
    return max(0, int(math.floor(notional / etf_price)))


def atr_stop_price(entry_price: float, atr_value: float, side: str, mult: float = 1.5) -> float:
    if side.startswith("long"):
        return entry_price - mult * atr_value
    return entry_price + mult * atr_value
