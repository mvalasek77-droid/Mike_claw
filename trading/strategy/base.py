"""Strategy interface. Each sub-strategy emits a signed conviction on crude.

Convention:
    side ∈ {"long_hou", "long_hod", "flat"}
    confidence ∈ [0, 1]
    A long_hou signal means: model expects crude UP, so buy 2x bull HOU.
    A long_hod signal means: model expects crude DOWN, so buy 2x bear HOD.
"""
from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass


@dataclass
class Signal:
    side: str
    confidence: float
    rationale: str
    source: str

    @property
    def signed(self) -> float:
        """+confidence if bullish crude, -confidence if bearish, 0 if flat."""
        if self.side == "long_hou":
            return self.confidence
        if self.side == "long_hod":
            return -self.confidence
        return 0.0


class Strategy(ABC):
    name: str = "base"

    @abstractmethod
    def signal(self, ctx: dict) -> Signal: ...
