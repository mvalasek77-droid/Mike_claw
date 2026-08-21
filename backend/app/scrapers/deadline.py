"""Deadline release calendar + tracking headlines.

Deadline posts nightly headline tracking numbers ('X tracks for
$YM opening weekend'). We only extract calendar entries here;
tracking numbers are extracted in services/deadline_tracker.py.
"""
from ..models.schemas import Movie


async def fetch(window_days: int) -> list[Movie]:
    # TODO: implement Deadline release-calendar scrape once we
    # nail down the DOM. IMDb + The Numbers already cover the
    # calendar; Deadline's value is the tracking numbers, handled
    # in services/deadline_tracker.py.
    return []
