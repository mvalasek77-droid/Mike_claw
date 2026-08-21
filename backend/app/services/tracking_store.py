"""In-memory tracking store. Swap for Postgres when it matters."""
from ..models.schemas import Tracking


class TrackingStore:
    def __init__(self):
        self._data: dict[str, Tracking] = {}

    def get(self, movie_id: str) -> Tracking | None:
        return self._data.get(movie_id)

    def put(self, movie_id: str, tracking: Tracking) -> None:
        self._data[movie_id] = tracking

    def size(self) -> int:
        return len(self._data)
