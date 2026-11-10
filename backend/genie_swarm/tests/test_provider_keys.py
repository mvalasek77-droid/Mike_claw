"""A user's own API key: used for their request, kept nowhere."""
from __future__ import annotations

import json
import logging
from pathlib import Path

import pytest
from fastapi import FastAPI
from starlette.requests import Request
from starlette.testclient import TestClient

from genie_swarm import api
from genie_swarm.llm import AnthropicClient, LLMResponse, OpenAIClient, RoutingLLMClient
from genie_swarm.middleware import register_middleware, rate_limiter

SECRET = "sk-ant-test-DO-NOT-LEAK-1234567890"


def _request(headers: dict[str, str]) -> Request:
    raw = [(k.lower().encode(), v.encode()) for k, v in headers.items()]
    return Request({"type": "http", "headers": raw, "method": "POST", "path": "/"})


def test_no_key_is_refused_unless_the_operator_opted_in(monkeypatch):
    from fastapi import HTTPException
    monkeypatch.delenv("CODEGENIE_ALLOW_SERVER_KEY", raising=False)
    with pytest.raises(HTTPException) as refused:
        api._llm_for(_request({}))
    assert refused.value.status_code == 401
    with pytest.raises(HTTPException):
        api._llm_for(_request({"X-Anthropic-Key": "   "}))


def test_operator_can_opt_in_to_paying_for_callers(monkeypatch):
    monkeypatch.setenv("CODEGENIE_ALLOW_SERVER_KEY", "1")
    assert api._llm_for(_request({})) is api.state.llm


def test_a_users_key_gets_its_own_client():
    client = api._llm_for(_request({"X-Anthropic-Key": SECRET}))
    assert client is not api.state.llm
    assert isinstance(client, RoutingLLMClient)
    assert isinstance(client.anthropic, AnthropicClient)
    assert client.anthropic.api_key == SECRET
    # The shared client is untouched, so the next request starts clean.
    assert getattr(getattr(api.state.llm, "anthropic", None), "api_key", "") != SECRET


def test_each_vendor_key_goes_to_its_own_vendor():
    client = api._llm_for(_request({"X-Anthropic-Key": "a-key", "X-OpenAI-Key": "o-key"}))
    assert client.anthropic.api_key == "a-key"
    assert isinstance(client.openai, OpenAIClient)
    assert client.openai.api_key == "o-key"


class _Spy:
    def __init__(self):
        self.calls = 0

    async def complete(self, **kwargs):
        self.calls += 1
        return LLMResponse(text="Click Apps, then the + button.")


@pytest.fixture
def client(tmp_path: Path, monkeypatch):
    rate_limiter.reset()
    monkeypatch.delenv("CODEGENIE_API_TOKEN", raising=False)
    monkeypatch.setattr(api.state.config, "workspace_root", tmp_path / "ws")
    app = FastAPI()
    register_middleware(app)
    app.include_router(api.router)
    yield TestClient(app)
    rate_limiter.reset()


def test_coach_uses_the_callers_key_and_never_echoes_it(client, monkeypatch, caplog):
    used: list[Request] = []
    spy = _Spy()

    def fake_llm_for(request):
        used.append(request)
        return spy

    monkeypatch.setattr(api, "_llm_for", fake_llm_for)
    with caplog.at_level(logging.DEBUG):
        resp = client.post(
            "/api/coding/swarm/asc/coach",
            json={"question": "Where is the + button?", "step_number": 2},
            headers={"X-Anthropic-Key": SECRET},
        )
    assert resp.status_code == 200
    assert spy.calls == 1
    assert used[0].headers["x-anthropic-key"] == SECRET
    assert SECRET not in resp.text
    assert SECRET not in json.dumps(dict(resp.headers))
    assert SECRET not in caplog.text


def test_coach_failure_does_not_leak_provider_error_text(client, monkeypatch):
    class _Boom:
        async def complete(self, **kwargs):
            raise RuntimeError(f"401 invalid x-api-key {SECRET}")

    monkeypatch.setattr(api, "_llm_for", lambda request: _Boom())
    resp = client.post("/api/coding/swarm/asc/coach", json={"question": "hi"})
    assert resp.status_code == 503
    assert SECRET not in resp.text


def test_a_build_started_with_a_key_leaves_no_trace_of_it_on_disk(client, monkeypatch, tmp_path):
    spy = _Spy()
    monkeypatch.setattr(api, "_llm_for", lambda request: spy)
    resp = client.post(
        "/api/coding/swarm/build",
        json={"spec": {"title": "Tide Times", "prompt": "tides"}, "skip_tests": True},
        headers={"X-Anthropic-Key": SECRET},
    )
    assert resp.status_code == 200
    job_id = resp.json()["job_id"]
    # Let the background build run to completion.
    for _ in range(200):
        if client.get(f"/api/coding/swarm/{job_id}/status").json()["state"] in ("succeeded", "failed", "cancelled"):
            break
    assert spy.calls >= 1
    written = [p for p in (tmp_path / "ws").rglob("*") if p.is_file()]
    assert written, "the build should have written a session"
    for path in written:
        assert SECRET.encode() not in path.read_bytes(), f"key found in {path}"
