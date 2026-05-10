"""Async event bus for fan-out streaming.

Every `BuildJob` gets one `EventStream` that all the swarm agents push to.
HTTP/SSE consumers (and the WebSocket bridge for the iOS client) subscribe
to that stream and receive events in real-time.

The bus is unbounded per-subscriber by design — slow consumers don't block
producers, but they pay in memory. The API layer enforces a sane queue cap
per connection.
"""
from __future__ import annotations

import asyncio
from collections.abc import AsyncIterator
from typing import Any

from .models import SwarmEvent


class EventStream:
    """Single-job pub/sub.

    Producers call ``publish(event)`` from anywhere in the swarm. Each
    subscriber gets its own ``asyncio.Queue`` so they decode independently.
    """

    def __init__(self, job_id: str, *, max_per_subscriber: int = 1024) -> None:
        self.job_id = job_id
        self._subscribers: list[asyncio.Queue[SwarmEvent | None]] = []
        self._closed = False
        self._lock = asyncio.Lock()
        self._max = max_per_subscriber

    async def publish(self, event: SwarmEvent) -> None:
        async with self._lock:
            for q in self._subscribers:
                if q.qsize() >= self._max:
                    # Drop the oldest event rather than block — viewers
                    # missing log spam is preferable to wedged producers.
                    try:
                        q.get_nowait()
                    except asyncio.QueueEmpty:
                        pass
                await q.put(event)

    async def emit(
        self,
        type_: str,
        *,
        agent: str | None = None,
        **payload: Any,
    ) -> None:
        await self.publish(
            SwarmEvent(type=type_, job_id=self.job_id, agent=agent, payload=payload)
        )

    async def close(self) -> None:
        async with self._lock:
            self._closed = True
            for q in self._subscribers:
                await q.put(None)

    async def subscribe(self) -> AsyncIterator[SwarmEvent]:
        q: asyncio.Queue[SwarmEvent | None] = asyncio.Queue()
        async with self._lock:
            if self._closed:
                return
            self._subscribers.append(q)
        try:
            while True:
                ev = await q.get()
                if ev is None:
                    break
                yield ev
        finally:
            async with self._lock:
                if q in self._subscribers:
                    self._subscribers.remove(q)


class EventBus:
    """Map of job_id → EventStream. Streams are torn down 5 minutes after
    a job ends so reconnects within that window can replay state."""

    def __init__(self) -> None:
        self._streams: dict[str, EventStream] = {}
        self._lock = asyncio.Lock()

    async def stream_for(self, job_id: str) -> EventStream:
        async with self._lock:
            stream = self._streams.get(job_id)
            if stream is None:
                stream = EventStream(job_id)
                self._streams[job_id] = stream
            return stream

    async def close(self, job_id: str) -> None:
        async with self._lock:
            stream = self._streams.pop(job_id, None)
        if stream:
            await stream.close()
