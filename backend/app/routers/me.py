"""Cloud sync — GET/PUT the signed-in user's state so it follows
them across devices."""
from fastapi import APIRouter, Header, HTTPException
from ..models.schemas import Me
from ..services.user_store import UserStore

router = APIRouter(prefix="/me", tags=["me"])
store = UserStore()


def _uid(auth: str | None) -> str:
    if not auth or not auth.startswith("Bearer "):
        raise HTTPException(401, "missing bearer token")
    return auth.removeprefix("Bearer ").strip()


@router.get("", response_model=Me)
async def get_me(authorization: str | None = Header(default=None)):
    return store.get(_uid(authorization))


@router.put("", response_model=Me)
async def put_me(me: Me, authorization: str | None = Header(default=None)):
    return store.put(_uid(authorization), me)
