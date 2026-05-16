"""Cost tracking + per-build USD cap.

The orchestrator instantiates one `CostMeter` per job. After every
agent finishes, we add its `(input_tokens, output_tokens)` against the
model that ran and convert to USD using a static price map. If the
running total crosses `cap_usd`, the meter raises `BudgetExceeded` so
the orchestrator can short-circuit cleanly and emit a `cost.cap_hit`
SwarmEvent. The iOS UI surfaces both the live spend and the cap.

Prices are per million tokens, USD, mirrored from the iOS-side
`ModelCatalogue` so the two stay coherent. Update this dict whenever a
vendor changes their rate card.
"""
from __future__ import annotations

from dataclasses import dataclass


# Per-million-token prices. Falls back to a conservative flagship rate
# when the model is unknown (better to over-estimate than to silently
# let costs balloon past the cap).
DEFAULT_PRICES: dict[str, tuple[float, float]] = {
    # Anthropic
    "claude-opus-4-7":     (5.0,  25.0),
    "claude-sonnet-4-6":   (3.0,  15.0),
    "claude-haiku-4-5":    (1.0,  5.0),
    # OpenAI
    "gpt-5.5":             (5.0,  30.0),
    "gpt-5.4":             (2.5,  15.0),
    "gpt-5.4-mini":        (0.75, 4.5),
    # Legacy aliases kept so older jobs/tests still estimate safely.
    "gpt-5":               (2.5,  15.0),
    "gpt-5-mini":          (0.75, 4.5),
}
_FALLBACK_PRICE = (15.0, 75.0)


class BudgetExceeded(Exception):
    """Raised when the running USD spend crosses `cap_usd`."""
    def __init__(self, *, spent: float, cap: float):
        super().__init__(f"build budget exceeded: ${spent:.4f} > ${cap:.4f}")
        self.spent = spent
        self.cap = cap


@dataclass
class CostMeter:
    cap_usd: float | None = None
    prices: dict[str, tuple[float, float]] | None = None

    input_tokens: int = 0
    output_tokens: int = 0
    spend_usd: float = 0.0

    def record(self, *, model: str, input_tokens: int, output_tokens: int) -> None:
        """Add an agent run's usage. Raises `BudgetExceeded` if the
        running total now exceeds the cap — callers should handle that
        and emit a `cost.cap_hit` event before re-raising or stopping."""
        prices = self.prices or DEFAULT_PRICES
        ip, op = prices.get(model, _FALLBACK_PRICE)
        delta = (input_tokens / 1_000_000.0) * ip + (output_tokens / 1_000_000.0) * op

        self.input_tokens += max(0, input_tokens)
        self.output_tokens += max(0, output_tokens)
        self.spend_usd += max(0.0, delta)

        if self.cap_usd is not None and self.spend_usd > self.cap_usd:
            raise BudgetExceeded(spent=self.spend_usd, cap=self.cap_usd)

    def snapshot(self) -> dict:
        """Plain-JSON view of the current totals, suitable for emitting
        as a `cost.update` SwarmEvent payload."""
        return {
            "input_tokens": self.input_tokens,
            "output_tokens": self.output_tokens,
            "spend_usd": round(self.spend_usd, 5),
            "cap_usd": self.cap_usd,
        }
