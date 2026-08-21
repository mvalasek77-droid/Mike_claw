"""BoxCall API — the server the iOS app talks to.

Endpoints match the client-side stubs verbatim so the iOS app's
existing composite-source fall-through starts hitting real data
the moment this is deployed under api.boxcall.com.
"""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from apscheduler.schedulers.background import BackgroundScheduler
from contextlib import asynccontextmanager

from .routers import upcoming, tracking, x_signal, moderation, analytics, me, settlement
from .services.settlement_cron import run_monday_settlement


scheduler = BackgroundScheduler()


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Monday 09:15 UTC — after Box Office Mojo publishes final Fri-Sun.
    scheduler.add_job(run_monday_settlement, "cron", day_of_week="mon", hour=9, minute=15)
    scheduler.start()
    yield
    scheduler.shutdown()


app = FastAPI(
    title="BoxCall API",
    version="0.1.0",
    lifespan=lifespan,
    description="Aggregates upcoming releases, tracking numbers, social signals, "
                "moderation, analytics, and Monday settlement for BoxCall iOS."
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(upcoming.router)
app.include_router(tracking.router)
app.include_router(x_signal.router)
app.include_router(moderation.router)
app.include_router(analytics.router)
app.include_router(me.router)
app.include_router(settlement.router)


@app.get("/", include_in_schema=False)
def health():
    return {"status": "ok", "service": "boxcall-api"}
