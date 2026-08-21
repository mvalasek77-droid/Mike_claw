# BoxCall API

FastAPI backend that serves the iOS app under `api.boxcall.com`.

## Endpoints

| Route | Purpose |
|---|---|
| `GET  /upcoming?window_days=60` | Aggregated upcoming releases from IMDb Coming Soon + The Numbers + Deadline (scrapers under `app/scrapers/`). Deduped by title + release date. |
| `GET  /tracking?movie_id=…` | Pre-release consensus opening + IV per movie. Written into the tracking store by nightly Deadline / NRG scrapers. |
| `GET  /x-signal?title=…` | X (Twitter) mention velocity + sentiment. Paid X API key held server-side; iOS never sees it. |
| `POST /moderate/report` | User-submitted content report. Lands in `ModerationQueue` for human review. |
| `POST /analytics/events` | Anonymous product event stream. Writes NDJSON today; swap for BigQuery. |
| `GET / PUT  /me` | Cloud-synced user state (positions, XP, badges). Bearer-authenticated with the Apple user id. |
| `GET  /settlement/{movie_id}` | Final domestic opening-weekend gross once the Monday scraper has picked it up. |
| `GET  /settlement` | Recent settled rows. |

## Monday settlement cron

Runs at Monday 09:15 UTC via APScheduler. Scrapes `boxofficemojo.com/weekend/`, writes results into `SettlementStore`, and (once APNs is wired) fans out push notifications to everyone with an open position on a settled movie.

## Running locally

```bash
cd backend
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload
# open http://127.0.0.1:8000/docs
```

## Docker

```bash
docker build -t boxcall-api ./backend
docker run -p 8080:8080 -e X_BEARER_TOKEN=... boxcall-api
```

## Environment

| Var | Purpose |
|---|---|
| `X_BEARER_TOKEN` | X API v2 bearer token (paid tier). Empty → `/x-signal` returns 503 and iOS falls through to YouTube-only signal. |
| `ANALYTICS_PATH` | Where the event NDJSON goes. Default `/tmp/boxcall_events.ndjson`. |

## What's stubbed vs live

Every route responds today with real code paths — scrapers really scrape when the target DOM matches, stores really persist across the process lifetime — but nothing is production-hardened. Before shipping publicly:

- Swap in-memory stores (Tracking, User, Settlement, Moderation) for Postgres
- Replace NDJSON analytics sink with BigQuery / Snowflake / etc
- Add APNs push fanout in `settlement_cron`
- Verify Apple ID tokens server-side (`python-jose` is already in `requirements.txt`)
- Rate-limit `/x-signal` and `/upcoming` to protect the scrapers
- Move the DOM selectors into config so a site redesign doesn't require a redeploy
