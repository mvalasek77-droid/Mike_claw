"""TestFlight status-poller tests.

We inject a fake `http_get` so the poller never touches Apple. The
fakes dispatch on the URL, because polling is two requests, not one:
`/v1/builds` has no bundle-ID filter, so the bundle ID must first be
resolved to Apple's numeric app id via `/v1/apps`. Scripting responses
blindly by sequence hid that, and the single-request version the tests
used to describe returned an error against the real API — the build
appeared stuck in Processing forever.
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


_APP_PAYLOAD = {"data": [{"id": "6001234567", "type": "apps"}]}


def _route(builds):
    """Answer the apps lookup, then hand `builds` the build queries."""
    async def fake_http(url: str, jwt: str) -> dict[str, Any]:
        if "/apps?" in url:
            return _APP_PAYLOAD
        return builds(url) if callable(builds) else next(builds)
    return fake_http


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

    consumer = asyncio.create_task(collect())
    await asyncio.sleep(0.01)
    result = await watch(config, events, http_get=_route(script))
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

    consumer = asyncio.create_task(collect())
    await asyncio.sleep(0.01)
    await watch(config, events, http_get=_route(script))
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
        if "/apps?" in url:
            return _APP_PAYLOAD
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

    result = await watch(
        config, events, http_get=_route(lambda _url: _build_payload("PROCESSING")),
    )
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


# --------------------------------------------------------------------------- #
# Resolving the app id
# --------------------------------------------------------------------------- #

@pytest.mark.asyncio
async def test_builds_are_queried_by_numeric_app_id(tmp_path):
    """`/v1/builds` has no `filter[app.bundleId]`. Sending one returned
    an error rather than the build, so nothing was ever reported and the
    app looked stuck in Processing."""
    config = _make_config(tmp_path)
    events = EventStream(job_id="j")
    seen: list[str] = []

    async def fake_http(url: str, jwt: str) -> dict[str, Any]:
        seen.append(url)
        if "/apps?" in url:
            return _APP_PAYLOAD
        return _build_payload("VALID")

    result = await watch(config, events, http_get=fake_http)
    assert result["state"] == "VALID"

    apps_url = next(u for u in seen if "/apps?" in u)
    builds_url = next(u for u in seen if "/builds?" in u)
    assert "filter%5BbundleId%5D=com.codegenie.demo" in apps_url
    assert "filter%5Bapp%5D=6001234567" in builds_url
    assert "bundleId" not in builds_url, "builds cannot be filtered by bundle id"


@pytest.mark.asyncio
async def test_missing_app_record_is_named_rather_than_a_generic_error(tmp_path):
    """Creating the App Store Connect record with a different bundle ID
    is a common first-time mistake, and 'POLL_ERROR' does not help
    anyone find it."""
    config = _make_config(tmp_path)
    config.timeout_s = 0.05
    config.poll_interval_s = 0.0
    events = EventStream(job_id="j")
    received: list[dict[str, Any]] = []

    async def collect():
        async for ev in events.subscribe():
            received.append(ev.payload)
            break

    async def fake_http(url: str, jwt: str) -> dict[str, Any]:
        return {"data": []}

    consumer = asyncio.create_task(collect())
    await asyncio.sleep(0.01)
    await watch(config, events, http_get=fake_http)
    await asyncio.wait_for(consumer, timeout=2.0)

    assert received[0]["state"] == "APP_NOT_FOUND"
    assert "com.codegenie.demo" in received[0]["detail"]


@pytest.mark.asyncio
async def test_the_app_id_is_resolved_once_not_every_poll(tmp_path):
    config = _make_config(tmp_path)
    config.timeout_s = 0.05
    config.poll_interval_s = 0.0
    events = EventStream(job_id="j")
    apps_calls = {"n": 0}

    async def fake_http(url: str, jwt: str) -> dict[str, Any]:
        if "/apps?" in url:
            apps_calls["n"] += 1
            return _APP_PAYLOAD
        return _build_payload("PROCESSING")

    await watch(config, events, http_get=fake_http)
    assert apps_calls["n"] == 1


def test_polling_without_a_usable_key_says_so(tmp_path):
    """An unsigned token gets a 401 from Apple, which surfaced as a
    generic POLL_ERROR every thirty seconds."""
    from genie_swarm.testflight_status import signing_available

    config = _make_config(tmp_path)
    config.p8_path = str(tmp_path / "does-not-exist.p8")
    ok, reason = signing_available(config)
    assert not ok
    # Which of the two preconditions failed depends on the host, so
    # assert that it names one of them rather than pinning this to
    # whichever the CI image happens to be missing.
    assert any(word in reason.lower() for word in ("key", "cryptography"))
    assert reason.endswith(".")
