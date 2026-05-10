"""TestFlight status-poller tests.

We inject a fake `http_get` so the poller never touches Apple. The
fake returns a scripted sequence of API responses simulating Apple's
processing pipeline: WAITING_FOR_BUILD → PROCESSING → VALID.
"""
from __future__ import annotations

import asyncio
from typing import Any

import pytest

from genie_swarm.streaming import EventStream
from genie_swarm.testflight_status import (
    PollerConfig,
    TERMINAL_STATES,
    mint_jwt,
    watch,
)


def _make_config(tmp_path) -> PollerConfig:
    fake_p8 = tmp_path / "fake.p8"
    fake_p8.write_text("(not a real key)\n")
    return PollerConfig(
        api_key_id="ABCDEFGH12",
        issuer_id="0000-0000-0000-0000",
        p8_path=str(fake_p8),
        bundle_id="com.codegenie.demo",
        version="1.0",
        build_number="42",
        poll_interval_s=0.0,   # tests want immediate iterations
        timeout_s=2.0,
    )


def _build_payload(state: str, build_number: str = "42") -> dict[str, Any]:
    return {
        "data": [
            {
                "id": "BUILD123",
                "attributes": {
                    "processingState": state,
                    "version": "1.0",
                    "buildNumber": build_number,
                },
            }
        ]
    }


# --------------------------------------------------------------------------- #
# Happy path
# --------------------------------------------------------------------------- #

@pytest.mark.asyncio
async def test_poller_emits_each_state_change(tmp_path):
    """Three scripted responses → three state events + a terminal return."""
    config = _make_config(tmp_path)
    events = EventStream(job_id="j")
    received: list[dict[str, Any]] = []

    async def collect():
        async for ev in events.subscribe():
            received.append({"type": ev.type, "state": ev.payload.get("state")})
            if ev.payload.get("state") in TERMINAL_STATES:
                break

    script = iter([
        _build_payload("PROCESSING"),
        _build_payload("PROCESSING"),       # de-duped — no new event
        _build_payload("VALID"),
    ])

    async def fake_http(url: str, jwt: str) -> dict[str, Any]:
        return next(script)

    consumer = asyncio.create_task(collect())
    await asyncio.sleep(0.01)
    result = await watch(config, events, http_get=fake_http)
    await asyncio.wait_for(consumer, timeout=2.0)

    assert result["state"] == "VALID"
    # First two payloads were identical PROCESSING, so we should only
    # see one PROCESSING event then VALID.
    states = [r["state"] for r in received]
    assert states == ["PROCESSING", "VALID"]


@pytest.mark.asyncio
async def test_poller_emits_waiting_when_no_build_yet(tmp_path):
    config = _make_config(tmp_path)
    events = EventStream(job_id="j")
    received: list[str] = []

    async def collect():
        async for ev in events.subscribe():
            received.append(ev.payload.get("state") or "")
            if ev.payload.get("state") in TERMINAL_STATES:
                break

    script = iter([
        {"data": []},                         # Apple doesn't see it yet
        _build_payload("PROCESSING"),
        _build_payload("VALID"),
    ])

    async def fake_http(url: str, jwt: str) -> dict[str, Any]:
        return next(script)

    consumer = asyncio.create_task(collect())
    await asyncio.sleep(0.01)
    await watch(config, events, http_get=fake_http)
    await asyncio.wait_for(consumer, timeout=2.0)
    assert "WAITING_FOR_BUILD" in received
    assert received[-1] == "VALID"


@pytest.mark.asyncio
async def test_poller_handles_http_errors_then_recovers(tmp_path):
    """HTTP failures emit POLL_ERROR but the poller keeps trying."""
    config = _make_config(tmp_path)
    events = EventStream(job_id="j")
    received: list[str] = []

    async def collect():
        async for ev in events.subscribe():
            received.append(ev.payload.get("state") or "")
            if ev.payload.get("state") in TERMINAL_STATES:
                break

    calls = {"n": 0}
    payloads = iter([_build_payload("INVALID")])  # terminal on the recovery

    async def flaky(url: str, jwt: str) -> dict[str, Any]:
        calls["n"] += 1
        if calls["n"] == 1:
            raise TimeoutError("network blip")
        return next(payloads)

    consumer = asyncio.create_task(collect())
    await asyncio.sleep(0.01)
    result = await watch(config, events, http_get=flaky)
    await asyncio.wait_for(consumer, timeout=2.0)
    assert result["state"] == "INVALID"
    assert "POLL_ERROR" in received


@pytest.mark.asyncio
async def test_poller_times_out_when_apple_never_finishes(tmp_path):
    config = _make_config(tmp_path)
    config.timeout_s = 0.05  # very small; we tick a few times then time out
    config.poll_interval_s = 0.0
    events = EventStream(job_id="j")

    async def fake_http(url: str, jwt: str) -> dict[str, Any]:
        return _build_payload("PROCESSING")

    result = await watch(config, events, http_get=fake_http)
    assert result["state"] == "TIMEOUT"


# --------------------------------------------------------------------------- #
# JWT signer
# --------------------------------------------------------------------------- #

def test_mint_jwt_produces_three_dot_segments(tmp_path):
    config = _make_config(tmp_path)
    token = mint_jwt(config)
    assert token.count(".") == 2
    header_b64, payload_b64, _ = token.split(".")
    # Both segments must be base64url-decodable.
    import base64
    def _decode(s: str) -> bytes:
        return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))
    import json
    header = json.loads(_decode(header_b64))
    payload = json.loads(_decode(payload_b64))
    assert header == {"alg": "ES256", "kid": config.api_key_id, "typ": "JWT"}
    assert payload["iss"] == config.issuer_id
    assert payload["aud"] == "appstoreconnect-v1"
    assert payload["exp"] - payload["iat"] == 60 * 20
