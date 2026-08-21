"""Moderation queue. Reports land here for a human reviewer.
Swap for a real queue (SQS, Cloud Tasks) in production."""
from ..models.schemas import ModerationReport


class ModerationQueue:
    def __init__(self):
        self._items: list[ModerationReport] = []

    def enqueue(self, r: ModerationReport) -> None:
        self._items.append(r)

    def size(self) -> int:
        return len(self._items)

    def next_batch(self, n: int = 20) -> list[ModerationReport]:
        batch, self._items = self._items[:n], self._items[n:]
        return batch
