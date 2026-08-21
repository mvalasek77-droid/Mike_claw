"""X mention velocity + sentiment. Server holds the paid X API key
so the iOS client never sees it."""
from fastapi import APIRouter, HTTPException
from ..models.schemas import XSignal
from ..services.x_client import fetch_x_signal

router = APIRouter(prefix="/x-signal", tags=["signals"])


@router.get("", response_model=XSignal)
async def x_signal(title: str):
    sig = await fetch_x_signal(title)
    if sig is None:
        raise HTTPException(503, "x api unavailable")
    return sig
