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
import time
from dataclasses import dataclass
from typing import Any, Optional

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

    # Fail fast on credentials that can NEVER work — without this the
    # poller spent a full hour emitting raw POLL_ERROR spam (Apple 401s
    # an unsigned token on every poll) and the user was never told the
    # actual problem or what to do about it.
    problem = credentials_problem(config)
    if problem:
        await events.emit("testflight.status", state="CREDENTIALS_ERROR", detail=problem)
        return {"state": "CREDENTIALS_ERROR", "raw": None}

    deadline = time.time() + config.timeout_s
    backoff = config.poll_interval_s
    last_state: str | None = None
    app_id: str | None = None

    while time.time() < deadline:
        token = mint_jwt(config)
        try:
            # ASC's /v1/builds endpoint can't filter by bundle id directly —
            # resolve the numeric app id once via /v1/apps, then poll builds.
            if app_id is None:
                apps_body = await fetcher(_apps_endpoint(config), token)
                app_id = _extract_app_id(apps_body)
                if app_id is None:
                    await events.emit(
                        "testflight.status",
                        state="WAITING_FOR_BUILD",
                        detail=(
                            f"No App Store Connect app record found for {config.bundle_id}. "
                            "If you haven't created the app record yet, do it in App Store "
                            "Connect → Apps → '+' (the poll picks it up automatically once it exists)."
                        ),
                    )
                    await asyncio.sleep(backoff)
                    continue
            body = await fetcher(_build_endpoint(config, app_id), token)
        except Exception as exc:  # noqa: BLE001
            status_code = getattr(exc, "code", None) \
                or getattr(getattr(exc, "response", None), "status_code", None)
            if status_code in (401, 403):
                await events.emit(
                    "testflight.status",
                    state="AUTH_ERROR",
                    detail=(
                        f"Apple rejected the API credentials (HTTP {status_code}). "
                        "Re-check the Key ID, Issuer ID and .p8 file in Settings → Apple "
                        "credentials, and confirm the key's access role is App Manager or higher."
                    ),
                )
                return {"state": "AUTH_ERROR", "raw": None}
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
        detail=(
            f"Stopped watching after {int(config.timeout_s)}s without a terminal state. "
            "Apple occasionally takes hours — check App Store Connect → TestFlight "
            "directly; the build will appear there when processing finishes."
        ),
    )
    return {"state": "TIMEOUT", "raw": None}


def credentials_problem(config: PollerConfig) -> str | None:
    """A definite, user-fixable reason JWT signing can't work — or None.

    Run BEFORE polling: an unloadable key means every poll would 401
    for the whole timeout window. The returned string is shown to a
    non-developer, so it says exactly what to do."""
    try:
        from cryptography.hazmat.primitives import serialization
    except BaseException:  # noqa: BLE001 — PyO3 PanicException is BaseException
        return (
            "The backend can't sign App Store Connect tokens because the "
            "'cryptography' package isn't installed. On the Mac running the "
            "backend: pip install cryptography, then retry."
        )
    try:
        with open(config.p8_path, "rb") as f:
            serialization.load_pem_private_key(f.read(), password=None)
    except FileNotFoundError:
        return (
            f"The App Store Connect key file wasn't found at {config.p8_path}. "
            "Re-add the .p8 key in Settings → Apple credentials."
        )
    except Exception as exc:  # noqa: BLE001
        return (
            f"The App Store Connect key at {config.p8_path} couldn't be read "
            f"({type(exc).__name__}). Download a fresh .p8 from App Store Connect → "
            "Users and Access → Integrations and re-add it in Settings."
        )
    return None


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


def _apps_endpoint(config: PollerConfig) -> str:
    return (
        "https://api.appstoreconnect.apple.com/v1/apps"
        f"?filter[bundleId]={config.bundle_id}&limit=1"
    )


def _extract_app_id(body: dict[str, Any]) -> str | None:
    data = body.get("data") if isinstance(body, dict) else None
    if not isinstance(data, list) or not data:
        return None
    app_id = data[0].get("id")
    return str(app_id) if app_id else None


def _build_endpoint(config: PollerConfig, app_id: str) -> str:
    # ASC's /v1/builds has no bundle-id filter (the old
    # `filter[app.bundleId]` placeholder 400'd in production, which made
    # every poll fail) — filter by the numeric app id resolved above.
    params = [
        f"filter[app]={app_id}",
        "limit=10",
        "sort=-uploadedDate",
    ]
    if config.version:
        params.append(f"filter[preReleaseVersion.version]={config.version}")
    if config.build_number:
        params.append(f"filter[version]={config.build_number}")
    return "https://api.appstoreconnect.apple.com/v1/builds?" + "&".join(params)


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
