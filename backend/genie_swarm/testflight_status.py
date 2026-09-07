"""TestFlight build-status poller.

After the `testflight_upload` tool finishes, we know Apple has the
binary but they take 5–30 minutes to process it. This module polls
App Store Connect's API until the build is either `READY_FOR_BETA_TESTING`,
`INVALID`, or we hit a timeout. It emits `testflight.status` SwarmEvents
so the iOS transcript can show progress live.

We use App Store Connect's REST API (not `altool`) because it returns
structured state. Auth is JWT signed with the user's `.p8` private
key — same credentials the upload tool already accepts.

API reference:
  https://developer.apple.com/documentation/appstoreconnectapi/builds

The implementation is intentionally minimal — one endpoint, polled on
a backoff. Production deployments should replace the JWT signer with
a battle-tested library; we include a tiny inline version for the
common case (ES256, single-file) so the swarm has zero external
dependencies it must ship.
"""
from __future__ import annotations

import asyncio
import base64
import json
import os
import time
from dataclasses import dataclass
from typing import Any, Optional
from urllib.parse import quote

from .streaming import EventStream


# Apple's processing states. See the `Build.attributes.processingState`
# field on the App Store Connect /v1/builds endpoint.
TERMINAL_STATES = frozenset({
    "VALID",
    "FAILED",
    "INVALID",
    "EXPIRED",
})


@dataclass
class PollerConfig:
    api_key_id: str          # ASC key ID, e.g. "ABCD1234XY"
    issuer_id: str           # ASC issuer (UUID)
    p8_path: str             # filesystem path to the downloaded .p8 key
    bundle_id: str           # app's bundle id, e.g. "com.codegenie.app"
    version: str | None = None
    build_number: str | None = None
    poll_interval_s: float = 30.0
    timeout_s: float = 60 * 60   # one hour cap


async def watch(
    config: PollerConfig,
    events: EventStream,
    *,
    http_get: Optional["HTTPGet"] = None,
) -> dict[str, Any]:
    """Block until the build reaches a terminal processing state. Emits
    a `testflight.status` event on every poll so the UI can show
    intermediate state ("PROCESSING…").

    `http_get` is injected for tests; in production we use the inline
    `_default_http_get` that hits the real ASC API."""
    fetcher = http_get or _default_http_get
    deadline = time.time() + config.timeout_s
    backoff = config.poll_interval_s
    last_state: str | None = None
    app_id: str | None = None

    # Apple answers an unsigned token with a 401, which surfaced as a
    # generic POLL_ERROR every thirty seconds and told nobody anything.
    # Only the built-in transport talks to Apple; a caller that supplies
    # its own fetcher owns its own authentication.
    if http_get is None:
        ok, reason = signing_available(config)
        if not ok:
            await events.emit(
                "testflight.status", state="POLL_UNAVAILABLE", detail=reason,
            )
            return {"state": "POLL_UNAVAILABLE", "raw": None}

    while time.time() < deadline:
        token = mint_jwt(config)

        # Resolve the numeric app id once. Apple keys builds off it, not
        # off the bundle ID.
        if app_id is None:
            try:
                found = await fetcher(_apps_endpoint(config.bundle_id), token)
            except Exception as exc:  # noqa: BLE001
                await events.emit(
                    "testflight.status",
                    state="POLL_ERROR",
                    detail=f"{type(exc).__name__}: {exc}",
                )
                await asyncio.sleep(backoff)
                continue
            app_id = _extract_app_id(found)
            if app_id is None:
                await events.emit(
                    "testflight.status",
                    state="APP_NOT_FOUND",
                    detail=(
                        f"No app in App Store Connect uses the bundle ID "
                        f"{config.bundle_id}. Create the app record first, "
                        f"and check the bundle ID matches exactly."
                    ),
                )
                await asyncio.sleep(backoff)
                continue

        try:
            body = await fetcher(_builds_endpoint(app_id, config), token)
        except Exception as exc:  # noqa: BLE001
            await events.emit(
                "testflight.status",
                state="POLL_ERROR",
                detail=f"{type(exc).__name__}: {exc}",
            )
            await asyncio.sleep(backoff)
            continue

        build = _extract_first_build(body, config)
        if not build:
            await events.emit(
                "testflight.status",
                state="WAITING_FOR_BUILD",
                detail="Apple hasn't surfaced the build yet",
            )
            await asyncio.sleep(backoff)
            continue

        state = build.get("attributes", {}).get("processingState", "UNKNOWN")
        if state != last_state:
            await events.emit(
                "testflight.status",
                state=state,
                build_id=build.get("id"),
                version=build.get("attributes", {}).get("version"),
                build_number=build.get("attributes", {}).get("buildNumber"),
            )
            last_state = state

        if state in TERMINAL_STATES:
            return {"state": state, "build_id": build.get("id"), "raw": build}

        await asyncio.sleep(backoff)

    await events.emit(
        "testflight.status",
        state="TIMEOUT",
        detail=f"no terminal state in {int(config.timeout_s)}s",
    )
    return {"state": "TIMEOUT", "raw": None}


# ---------------------------------------------------------------------------
# HTTP injection point
# ---------------------------------------------------------------------------

HTTPGet = "callable[[str, str], dict[str, Any]]"


async def _default_http_get(url: str, jwt: str) -> dict[str, Any]:
    """Real HTTP using stdlib. Kept minimal to avoid pulling httpx into
    the runtime when most installs already have aiohttp from FastAPI."""
    import urllib.error
    import urllib.request

    req = urllib.request.Request(
        url,
        headers={"Authorization": f"Bearer {jwt}", "Accept": "application/json"},
    )

    def _do_request() -> dict[str, Any]:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read().decode("utf-8"))

    return await asyncio.get_event_loop().run_in_executor(None, _do_request)


_API = "https://api.appstoreconnect.apple.com/v1"


def _apps_endpoint(bundle_id: str) -> str:
    """Resolve a bundle ID to the numeric app id.

    `/v1/builds` has no `filter[app.bundleId]`; it only accepts
    `filter[app]` with the numeric id. Filtering builds by bundle ID
    directly returned an error rather than the build, so polling never
    reported anything — the app looked stuck in Processing forever.
    """
    return f"{_API}/apps?filter%5BbundleId%5D={quote(bundle_id, safe='')}&limit=1"


def _builds_endpoint(app_id: str, config: PollerConfig) -> str:
    params = [
        f"filter%5Bapp%5D={quote(app_id, safe='')}",
        "limit=10",
        "sort=-uploadedDate",
    ]
    if config.version:
        params.append(
            f"filter%5BpreReleaseVersion.version%5D={quote(config.version, safe='')}"
        )
    if config.build_number:
        params.append(f"filter%5Bversion%5D={quote(config.build_number, safe='')}")
    return f"{_API}/builds?" + "&".join(params)


def _extract_app_id(body: dict[str, Any]) -> str | None:
    data = body.get("data") if isinstance(body, dict) else None
    if not isinstance(data, list) or not data:
        return None
    app_id = data[0].get("id")
    return app_id if isinstance(app_id, str) and app_id else None


def _extract_first_build(body: dict[str, Any], config: PollerConfig) -> dict[str, Any] | None:
    data = body.get("data") if isinstance(body, dict) else None
    if not isinstance(data, list) or not data:
        return None
    # If a specific build_number was requested, prefer the matching row.
    if config.build_number:
        for entry in data:
            if entry.get("attributes", {}).get("buildNumber") == config.build_number:
                return entry
    return data[0]


# ---------------------------------------------------------------------------
# Inline JWT signer (ES256, no external deps)
# ---------------------------------------------------------------------------

def signing_available(config: PollerConfig) -> tuple[bool, str]:
    """Can we actually sign a token Apple will accept?

    `mint_jwt` falls back to an unsigned placeholder so the rest of the
    system stays testable, but Apple answers those with a 401. Without
    this check that surfaced as a generic POLL_ERROR every thirty
    seconds, which reads like a network problem rather than a missing
    key or a missing library.
    """
    try:
        from cryptography.hazmat.primitives import serialization  # noqa: F401
    except BaseException:  # noqa: BLE001 — PyO3 panics aren't Exceptions
        return False, (
            "This server can't sign App Store Connect requests: the "
            "cryptography library isn't installed."
        )
    if not config.p8_path or not os.path.exists(config.p8_path):
        return False, (
            "Checking your build's status needs your App Store Connect "
            "key, which isn't on this server."
        )
    try:
        from cryptography.hazmat.primitives import serialization as ser
        with open(config.p8_path, "rb") as f:
            ser.load_pem_private_key(f.read(), password=None)
    except BaseException as exc:  # noqa: BLE001
        return False, f"Your App Store Connect key couldn't be read: {exc}"
    return True, ""


def mint_jwt(config: PollerConfig) -> str:
    """Sign a minimal App Store Connect API token.

    Apple wants ES256-signed JWT with 20-minute TTL. We try
    `cryptography` for the real signature; if it isn't importable
    (missing C backend in a sandbox, etc.) we return an unsigned
    placeholder so the rest of the system stays testable. Production
    deployments must have `cryptography` installed and importable —
    Apple rejects unsigned tokens."""
    header = _b64url(json.dumps({"alg": "ES256", "kid": config.api_key_id, "typ": "JWT"}).encode())
    now = int(time.time())
    payload = _b64url(json.dumps({
        "iss": config.issuer_id,
        "iat": now,
        "exp": now + 60 * 20,
        "aud": "appstoreconnect-v1",
    }).encode())
    signing_input = f"{header}.{payload}"

    # We catch BaseException because PyO3 raises PanicException (which
    # inherits BaseException, not Exception) when cryptography's Rust
    # backend can't load its C bindings — a real failure mode in some
    # sandboxes. Falling back to an unsigned token keeps the rest of
    # the orchestration testable; production must have a working
    # cryptography install.
    try:
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import ec
        from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
    except BaseException:  # noqa: BLE001
        return signing_input + "." + _b64url(b"unsigned")

    try:
        with open(config.p8_path, "rb") as f:
            private_key = serialization.load_pem_private_key(f.read(), password=None)
        der_signature = private_key.sign(signing_input.encode(), ec.ECDSA(hashes.SHA256()))
        r, s = decode_dss_signature(der_signature)
        raw = r.to_bytes(32, "big") + s.to_bytes(32, "big")
        return signing_input + "." + _b64url(raw)
    except BaseException:  # noqa: BLE001
        return signing_input + "." + _b64url(b"unsigned")


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")
