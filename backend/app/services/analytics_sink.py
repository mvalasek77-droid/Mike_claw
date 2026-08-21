"""Analytics warehouse writer. Swap for BigQuery / Redshift / Snowflake
in production; NDJSON to disk is fine for a v1 that we backfill later."""
import json, os
from datetime import datetime
from ..models.schemas import AnalyticsEvent


class AnalyticsWarehouse:
    def __init__(self, path: str | None = None):
        self.path = path or os.getenv("ANALYTICS_PATH", "/tmp/boxcall_events.ndjson")

    def write(self, event: AnalyticsEvent) -> None:
        payload = event.model_dump()
        payload["received_at"] = datetime.utcnow().isoformat()
        with open(self.path, "a", encoding="utf-8") as f:
            f.write(json.dumps(payload) + "\n")
