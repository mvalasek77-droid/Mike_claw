from fastapi import APIRouter
from ..models.schemas import ModerationReport
from ..services.moderation_queue import ModerationQueue

router = APIRouter(prefix="/moderate", tags=["moderation"])
queue = ModerationQueue()


@router.post("/report")
async def report(payload: ModerationReport):
    queue.enqueue(payload)
    return {"status": "queued", "queue_size": queue.size()}
