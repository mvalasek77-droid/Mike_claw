"""Paper broker -- mirrors the alert stream so we can keep score honestly."""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional


@dataclass
class Position:
    ticker: str
    units: int
    entry_price: float
    entry_time: datetime
    stop: float


@dataclass
class PaperBroker:
    cash: float
    position: Optional[Position] = None
    fills: list[dict] = field(default_factory=list)

    def buy(self, ticker: str, units: int, price: float, stop: float, when: datetime) -> bool:
        cost = units * price
        if units <= 0 or cost > self.cash:
            return False
        self.cash -= cost
        self.position = Position(ticker, units, price, when, stop)
        self.fills.append({"side": "buy", "ticker": ticker, "units": units,
                           "price": price, "time": when.isoformat()})
        return True

    def sell(self, price: float, when: datetime, reason: str = "") -> float:
        if not self.position:
            return 0.0
        proceeds = self.position.units * price
        pnl = proceeds - self.position.units * self.position.entry_price
        self.cash += proceeds
        self.fills.append({"side": "sell", "ticker": self.position.ticker,
                           "units": self.position.units, "price": price,
                           "time": when.isoformat(), "pnl": pnl, "reason": reason})
        self.position = None
        return pnl

    def equity(self, last_price: float) -> float:
        if not self.position:
            return self.cash
        return self.cash + self.position.units * last_price
