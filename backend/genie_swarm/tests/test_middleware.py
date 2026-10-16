"""Tests for auth, rate-limiting, request-ID, and structured logging middleware."""
from __future__ import annotations

import os
from unittest import mock

import pytest
from fastapi import FastAPI
from starlette.testclient import TestClient

from genie_swarm.api import router
from genie_swarm.middleware import register_middleware, rate_limiter


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_app() -> FastAPI:
    """Fresh FastAPI app with middleware and the swarm router."""
    app = FastAPI()
    register_middleware(app)
    app.include_router(router)
    return app


@pytest.fixture(autouse=True)
def _clean_rate_limiter():
    """Reset the rate limiter between every test."""
    rate_limiter.reset()
    yield
    rate_limiter.reset()


@pytest.fixture(autouse=True)
def _clear_auth_env():
    """Ensure CODEGENIE_API_TOKEN is unset unless a test sets it."""
    with mock.patch.dict(os.environ, {}, clear=False):
        os.environ.pop("CODEGENIE_API_TOKEN", None)
        yield


# ---------------------------------------------------------------------------
# Request-ID
# ---------------------------------------------------------------------------

class TestRequestID:
    def test_response_contains_request_id(self):
        client = TestClient(_make_app())
        resp = client.get("/api/coding/swarm/health")
        assert "x-request-id" in resp.headers
        # Must look like a uuid4 (36 chars, 4 hyphens)
        rid = resp.headers["x-request-id"]
        assert len(rid) == 36
        assert rid.count("-") == 4

    def test_each_request_gets_unique_id(self):
        client = TestClient(_make_app())
        ids = {
            client.get("/api/coding/swarm/health").headers["x-request-id"]
            for _ in range(5)
        }
        assert len(ids) == 5


# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------

class TestAuth:
    def test_skips_auth_when_env_unset(self):
        """Development mode: no token required."""
        client = TestClient(_make_app())
        resp = client.get("/api/coding/swarm/health")
        assert resp.status_code == 200

    def test_rejects_missing_token(self):
        with mock.patch.dict(os.environ, {"CODEGENIE_API_TOKEN": "secret-tok"}):
            client = TestClient(_make_app())
            # A non-skip endpoint without a token should 401.
            resp = client.get("/api/coding/swarm/nonexistent")
            assert resp.status_code == 401
            body = resp.json()
            assert "Authorization" in body["detail"]

    def test_rejects_bad_token(self):
        with mock.patch.dict(os.environ, {"CODEGENIE_API_TOKEN": "secret-tok"}):
            client = TestClient(_make_app())
            resp = client.get(
                "/api/coding/swarm/nonexistent",
                headers={"Authorization": "Bearer wrong-token"},
            )
            assert resp.status_code == 401
            assert resp.json()["detail"] == "Invalid API token"

    def test_accepts_valid_token(self):
        with mock.patch.dict(os.environ, {"CODEGENIE_API_TOKEN": "secret-tok"}):
            client = TestClient(_make_app())
            resp = client.get(
                "/api/coding/swarm/health",
                headers={"Authorization": "Bearer secret-tok"},
            )
            assert resp.status_code == 200

    def test_health_bypasses_auth(self):
        with mock.patch.dict(os.environ, {"CODEGENIE_API_TOKEN": "secret-tok"}):
            client = TestClient(_make_app())
            resp = client.get("/api/coding/swarm/health")
            assert resp.status_code == 200

    def test_valid_token_reaches_route(self):
        """With a valid token a real endpoint returns its normal response,
        not an auth error."""
        with mock.patch.dict(os.environ, {"CODEGENIE_API_TOKEN": "real-key"}):
            client = TestClient(_make_app())
            resp = client.get(
                "/api/coding/swarm/health",
                headers={"Authorization": "Bearer real-key"},
            )
            assert resp.status_code == 200
            assert resp.json()["ok"] is True


# ---------------------------------------------------------------------------
# Rate limiting
# ---------------------------------------------------------------------------

class TestRateLimiting:
    def test_returns_429_after_exceeding_limit(self):
        # Lower the limit for a fast test.
        rate_limiter.max_requests = 3
        rate_limiter.window = 60.0
        client = TestClient(_make_app())

        for _ in range(3):
            r = client.get("/api/coding/swarm/nonexistent-job/status")
            # 404 is fine -- the point is it was NOT 429 yet.
            assert r.status_code != 429

        # The 4th request should be rate-limited.
        r = client.get("/api/coding/swarm/nonexistent-job/status")
        assert r.status_code == 429
        assert "Retry-After" in r.headers
        assert int(r.headers["Retry-After"]) > 0
        assert r.json()["detail"] == "Rate limit exceeded"

    def test_health_bypasses_rate_limiting(self):
        rate_limiter.max_requests = 1
        client = TestClient(_make_app())

        # First request consumes the limit on any non-skip path.
        client.get("/api/coding/swarm/nonexistent-job/status")

        # Health should still succeed despite the limit being exhausted.
        for _ in range(5):
            r = client.get("/api/coding/swarm/health")
            assert r.status_code == 200

    def test_sse_limit(self):
        rate_limiter.max_sse = 1
        # Exhaust the SSE slot manually.
        assert rate_limiter.sse_allowed("testclient") is True
        assert rate_limiter.sse_allowed("testclient") is False
        rate_limiter.sse_disconnect("testclient")
        assert rate_limiter.sse_allowed("testclient") is True

    def test_429_includes_request_id(self):
        rate_limiter.max_requests = 0  # block everything
        client = TestClient(_make_app())
        r = client.get("/api/coding/swarm/nonexistent-job/status")
        assert r.status_code == 429
        assert "x-request-id" in r.headers
