"""Production middleware: auth, rate-limiting, request tracing, structured logging.

Wire into any FastAPI app with::

    from genie_swarm.middleware import register_middleware
    register_middleware(app)
"""
from __future__ import annotations

import json
import logging
import os
import time
import uuid
from collections import defaultdict, deque
from typing import Any, Callable

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse, Response


# ---------------------------------------------------------------------------
# Structured JSON logger
# ---------------------------------------------------------------------------

class _JSONFormatter(logging.Formatter):
    """Emit one JSON object per log line for structured log aggregation."""

    def format(self, record: logging.LogRecord) -> str:
        entry: dict[str, Any] = {
            "timestamp": self.formatTime(record, self.datefmt),
            "level": record.levelname,
            "message": record.getMessage(),
        }
        for key in (
            "method", "path", "status_code", "duration_ms",
            "request_id", "client_ip",
        ):
            val = getattr(record, key, None)
            if val is not None:
                entry[key] = val
        return json.dumps(entry, default=str)


def _get_logger() -> logging.Logger:
    logger = logging.getLogger("genie_swarm.http")
    if not logger.handlers:
        handler = logging.StreamHandler()
        handler.setFormatter(_JSONFormatter())
        logger.addHandler(handler)
        logger.setLevel(logging.INFO)
        logger.propagate = False
    return logger


_log = _get_logger()


# ---------------------------------------------------------------------------
# In-memory sliding-window rate limiter
# ---------------------------------------------------------------------------

# Paths exempt from rate limiting (checked with and without the router prefix).
_RATE_LIMIT_SKIP: set[str] = {"/health", "/api/coding/swarm/health"}

# Paths exempt from authentication.
_AUTH_SKIP: set[str] = {
    "/health", "/docs", "/openapi.json",
    "/api/coding/swarm/health",
}


class SlidingWindowRateLimiter:
    """Per-IP sliding-window counter.  No Redis required."""

    def __init__(
        self,
        requests_per_minute: int = 60,
        max_sse_per_ip: int = 5,
        window_seconds: float = 60.0,
    ) -> None:
        self.max_requests = requests_per_minute
        self.max_sse = max_sse_per_ip
        self.window = window_seconds
        # ip -> deque of monotonic timestamps
        self._hits: dict[str, deque[float]] = defaultdict(deque)
        # ip -> count of currently open SSE connections
        self._sse_active: dict[str, int] = defaultdict(int)

    # -- public API ----------------------------------------------------------

    def is_allowed(self, ip: str, *, _now: float | None = None) -> tuple[bool, float]:
        """Check (and record) a regular request.

        Returns ``(allowed, retry_after_seconds)``.
        """
        now = _now if _now is not None else time.monotonic()
        window = self._hits[ip]
        cutoff = now - self.window
        while window and window[0] <= cutoff:
            window.popleft()
        if len(window) >= self.max_requests:
            retry_after = (self.window - (now - window[0])) if window else self.window
            return False, max(retry_after, 1.0)
        window.append(now)
        return True, 0.0

    def sse_allowed(self, ip: str) -> bool:
        """Return True if another SSE connection is allowed for *ip*."""
        if self._sse_active[ip] >= self.max_sse:
            return False
        self._sse_active[ip] += 1
        return True

    def sse_disconnect(self, ip: str) -> None:
        self._sse_active[ip] = max(0, self._sse_active[ip] - 1)

    def reset(self) -> None:
        """Wipe all state (useful in tests)."""
        self._hits.clear()
        self._sse_active.clear()


# Module-level singleton so tests can swap / reset it.
rate_limiter = SlidingWindowRateLimiter()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _client_ip(request: Request) -> str:
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


# ---------------------------------------------------------------------------
# Combined middleware
# ---------------------------------------------------------------------------

class RequestMiddleware(BaseHTTPMiddleware):
    """Single middleware layer that adds:

    * **X-Request-ID** header on every response (uuid4)
    * **Bearer-token auth** validated against ``CODEGENIE_API_TOKEN``
    * **Per-IP sliding-window rate limiting** (REST + SSE)
    * **Structured JSON request logging** at INFO / WARNING / ERROR
    """

    async def dispatch(
        self, request: Request, call_next: Callable[..., Any],
    ) -> Response:
        request_id = str(uuid.uuid4())
        client_ip = _client_ip(request)
        start = time.monotonic()
        path = request.url.path

        # ---- auth ----------------------------------------------------------
        api_token = os.environ.get("CODEGENIE_API_TOKEN")
        if api_token and path not in _AUTH_SKIP:
            auth_header = request.headers.get("authorization", "")
            if not auth_header.startswith("Bearer "):
                return JSONResponse(
                    status_code=401,
                    content={
                        "detail": (
                            "Missing or malformed Authorization header. "
                            "Expected: Bearer <token>"
                        ),
                    },
                    headers={"X-Request-ID": request_id},
                )
            if auth_header[7:] != api_token:
                return JSONResponse(
                    status_code=401,
                    content={"detail": "Invalid API token"},
                    headers={"X-Request-ID": request_id},
                )

        # ---- rate limiting -------------------------------------------------
        if path not in _RATE_LIMIT_SKIP:
            is_sse = path.endswith("/stream")
            if is_sse and not rate_limiter.sse_allowed(client_ip):
                return JSONResponse(
                    status_code=429,
                    content={"detail": "Too many SSE connections"},
                    headers={"X-Request-ID": request_id, "Retry-After": "60"},
                )

            allowed, retry_after = rate_limiter.is_allowed(client_ip)
            if not allowed:
                return JSONResponse(
                    status_code=429,
                    content={"detail": "Rate limit exceeded"},
                    headers={
                        "X-Request-ID": request_id,
                        "Retry-After": str(int(retry_after)),
                    },
                )

        # ---- downstream ----------------------------------------------------
        try:
            response = await call_next(request)
        except Exception:
            self._log_request(request, 500, start, request_id, client_ip)
            raise

        response.headers["X-Request-ID"] = request_id

        # ---- logging -------------------------------------------------------
        self._log_request(
            request, response.status_code, start, request_id, client_ip,
        )
        return response

    # -- internal helpers ----------------------------------------------------

    @staticmethod
    def _log_request(
        request: Request,
        status: int,
        start: float,
        request_id: str,
        client_ip: str,
    ) -> None:
        duration_ms = round((time.monotonic() - start) * 1000, 2)
        if status < 400:
            level = logging.INFO
        elif status < 500:
            level = logging.WARNING
        else:
            level = logging.ERROR

        _log.log(
            level,
            "%s %s %d %.1fms",
            request.method,
            request.url.path,
            status,
            duration_ms,
            extra={
                "method": request.method,
                "path": request.url.path,
                "status_code": status,
                "duration_ms": duration_ms,
                "request_id": request_id,
                "client_ip": client_ip,
            },
        )


# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------

def register_middleware(app: Any) -> None:
    """Attach all production middleware to *app* (a FastAPI instance)."""
    app.add_middleware(RequestMiddleware)
