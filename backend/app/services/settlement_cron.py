"""Monday settlement job. Scrapes Box Office Mojo, writes results
to the settlement store, and (once APNs is wired) fans out push
notifications to every user with an open position on a settled
movie."""
import asyncio
from ..scrapers.box_office_mojo import fetch_weekend_grosses
from ..routers.settlement import store as settlement_store


def run_monday_settlement():
    asyncio.run(_run())


async def _run():
    rows = await fetch_weekend_grosses()
    for row in rows:
        settlement_store.put(row)
    # TODO: fan out APNs pushes to holders of settled movies.
    print(f"[settlement] wrote {len(rows)} weekend rows")
