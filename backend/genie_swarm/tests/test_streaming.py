"""EventStream / EventBus pub-sub tests."""
from __future__ import annotations

import asyncio

import pytest

from genie_swarm.streaming import EventBus, EventStream


@pytest.mark.asyncio
async def test_subscribe_receives_published_events():
    stream = EventStream(job_id="j")

    received: list[str] = []

    async def consume():
        async for event in stream.subscribe():
            received.append(event.type)
            if event.type == "done":
                break

    consumer = asyncio.create_task(consume())
    # Give the consumer a tick to register itself.
    await asyncio.sleep(0.05)
    await stream.emit("agent.started")
    await stream.emit("done")

    await asyncio.wait_for(consumer, timeout=2.0)
    assert "agent.started" in received
    assert received[-1] == "done"


@pytest.mark.asyncio
async def test_close_terminates_subscribers():
    stream = EventStream(job_id="j")
    received: list[str] = []

    async def consume():
        async for event in stream.subscribe():
            received.append(event.type)

    consumer = asyncio.create_task(consume())
    await asyncio.sleep(0.01)
    await stream.emit("log")
    await stream.close()
    await asyncio.wait_for(consumer, timeout=2.0)
    assert received == ["log"]


@pytest.mark.asyncio
async def test_bus_creates_one_stream_per_job():
    bus = EventBus()
    a = await bus.stream_for("alpha")
    b = await bus.stream_for("alpha")
    c = await bus.stream_for("beta")
    assert a is b
    assert a is not c
