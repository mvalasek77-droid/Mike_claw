"""Per-user cloud state keyed by Apple user id. In-memory today,
swap for Postgres."""
from ..models.schemas import Me


class UserStore:
    def __init__(self):
        self._data: dict[str, Me] = {}

    def get(self, uid: str) -> Me:
        return self._data.get(uid, Me(
            handle="you", reelCoins=1000, xp=0, tier="Rookie",
            membership="free", followers=0, badges=[]))

    def put(self, uid: str, me: Me) -> Me:
        self._data[uid] = me
        return me
