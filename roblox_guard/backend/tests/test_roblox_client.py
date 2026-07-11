import httpx
import pytest

from app.roblox_client import RobloxClient


def make_client(handler) -> RobloxClient:
    transport = httpx.MockTransport(handler)
    http = httpx.AsyncClient(transport=transport, timeout=5.0)
    return RobloxClient(spacing_seconds=0.0, http=http)


@pytest.mark.asyncio
async def test_retries_on_429_then_succeeds(monkeypatch):
    calls = {"n": 0}

    def handler(request):
        calls["n"] += 1
        if calls["n"] < 3:
            return httpx.Response(429, headers={"Retry-After": "0"})
        return httpx.Response(200, json={"id": 1, "name": "Roblox",
                                         "displayName": "Roblox",
                                         "description": "",
                                         "created": "2006-02-27T21:06:40.3Z"})

    async def no_sleep(_):
        pass
    monkeypatch.setattr("app.roblox_client.asyncio.sleep", no_sleep)

    client = make_client(handler)
    profile = await client.get_profile(1)
    assert profile.username == "Roblox"
    assert calls["n"] == 3
    await client.aclose()


@pytest.mark.asyncio
async def test_gives_up_after_max_attempts(monkeypatch):
    def handler(request):
        return httpx.Response(503)

    async def no_sleep(_):
        pass
    monkeypatch.setattr("app.roblox_client.asyncio.sleep", no_sleep)

    client = make_client(handler)
    with pytest.raises(httpx.HTTPStatusError):
        await client.get_profile(1)
    await client.aclose()


@pytest.mark.asyncio
async def test_404_not_retried():
    calls = {"n": 0}

    def handler(request):
        calls["n"] += 1
        return httpx.Response(404)

    client = make_client(handler)
    with pytest.raises(httpx.HTTPStatusError):
        await client.get_profile(1)
    assert calls["n"] == 1
    await client.aclose()
