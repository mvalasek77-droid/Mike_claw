"""Settled opening-weekend grosses per movie."""
from ..models.schemas import SettlementRow


class SettlementStore:
    def __init__(self):
        self._data: dict[str, SettlementRow] = {}

    def get(self, movie_id: str) -> SettlementRow | None:
        return self._data.get(movie_id)

    def put(self, row: SettlementRow) -> None:
        self._data[row.movieId] = row

    def list(self, limit: int = 50) -> list[SettlementRow]:
        rows = sorted(self._data.values(), key=lambda r: r.reportedAt, reverse=True)
        return rows[:limit]
