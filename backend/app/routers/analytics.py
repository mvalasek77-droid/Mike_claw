from fastapi import APIRouter
from ..models.schemas import AnalyticsEvent
from ..services.analytics_sink import AnalyticsWarehouse

router = APIRouter(prefix="/analytics", tags=["analytics"])
warehouse = AnalyticsWarehouse()


@router.post("/events")
async def record(event: AnalyticsEvent):
    warehouse.write(event)
    return {"status": "recorded"}
