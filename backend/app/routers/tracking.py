"""Pre-release tracking (consensus opening + IV) aggregated from
Deadline headline numbers + The Numbers historical model.
"""
from fastapi import APIRouter, HTTPException
from ..models.schemas import Tracking
from ..services.tracking_store import TrackingStore

router = APIRouter(prefix="/tracking", tags=["tracking"])
store = TrackingStore()


@router.get("", response_model=Tracking)
async def tracking(movie_id: str):
    t = store.get(movie_id)
    if t is None:
        raise HTTPException(404, "no tracking for that movie yet")
    return t
