"""Monday settlement — clients GET the reported opening-weekend
gross for a movie once it has been scraped from Box Office Mojo.
"""
from fastapi import APIRouter, HTTPException
from ..models.schemas import SettlementRow
from ..services.settlement_store import SettlementStore

router = APIRouter(prefix="/settlement", tags=["settlement"])
store = SettlementStore()


@router.get("/{movie_id}", response_model=SettlementRow)
async def settlement(movie_id: str):
    row = store.get(movie_id)
    if row is None:
        raise HTTPException(404, "not settled yet")
    return row


@router.get("", response_model=list[SettlementRow])
async def all_settled(limit: int = 50):
    return store.list(limit=limit)
