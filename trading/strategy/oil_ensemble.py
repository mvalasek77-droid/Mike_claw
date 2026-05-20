"""Ensemble blend of six public hedge-fund / quant / retail strategies.

Members and attribution:
    1. AQR Time-Series Momentum  -- Moskowitz, Ooi, Pedersen (2012).
    2. Donchian/Turtle Breakout  -- Dennis & Eckhardt (1983) via Curtis Faith.
    3. Trendline Mean-Reversion  -- classical Edwards-Magee, chop regime only.
    4. Trendline Breakout        -- classical Edwards-Magee, trend regime only.
    5. Connors RSI(2)            -- Connors & Alvarez (2009) short-term reversion.
    6. Session VWAP + EMA bias   -- common 30-min intraday structural filter.

Weighting (risk-parity flavour, Bridgewater school):
    Default = equal-weight. Learned weights = inverse-variance of each
    sub-strategy's realised PnL from `learning/evaluator.py`, so noisier
    strategies automatically shrink. The ensemble emits a *hard* decision
    (BUY_HOU / BUY_HOD / STAY_OUT) once it has tallied member convictions.
"""
from __future__ import annotations

from .base import Signal, Strategy
from .breakout import DonchianBreakout
from .connors_rsi2 import ConnorsRSI2
from .mean_revert import TrendlineMeanRevert
from .trend_follow import TSMomentum
from .trendline_break import TrendlineBreakout
from .vwap_bias import VWAPBias


class OilEnsemble(Strategy):
    name = "oil_ensemble"

    def __init__(self, weights: dict | None = None, min_confidence: float = 0.30):
        self.strategies = [
            TSMomentum(),
            DonchianBreakout(),
            TrendlineMeanRevert(),
            TrendlineBreakout(),
            ConnorsRSI2(),
            VWAPBias(),
        ]
        if weights is None:
            self.weights = {s.name: 1.0 / len(self.strategies) for s in self.strategies}
        else:
            self.weights = dict(weights)
        self.min_confidence = min_confidence
        self.last_member_signals: list[Signal] = []

    def signal(self, ctx: dict) -> Signal:
        score = {"long_hou": 0.0, "long_hod": 0.0}
        rationale_parts: list[str] = []
        self.last_member_signals = []
        for s in self.strategies:
            sig = s.signal(ctx)
            self.last_member_signals.append(sig)
            w = self.weights.get(s.name, 0.0)
            if sig.side in score:
                score[sig.side] += w * sig.confidence
            rationale_parts.append(f"{s.name}:{sig.side}({sig.confidence:.2f})")

        if score["long_hou"] >= score["long_hod"]:
            side = "long_hou"
            conf = score["long_hou"] - score["long_hod"]
        else:
            side = "long_hod"
            conf = score["long_hod"] - score["long_hou"]

        conf = max(0.0, min(1.0, conf))

        if conf < self.min_confidence:
            return Signal("flat", conf, " | ".join(rationale_parts), self.name)

        return Signal(side, conf, " | ".join(rationale_parts), self.name)
