"""Push notifications via Apple Push Notification service (APNs).

Token-based (JWT/ES256) auth rather than certificates — one key, signed with
your Apple Developer "Keys" private key, works for both the sandbox and
production APNs hosts and never expires or needs renewing. See README
"Push notifications" for how to generate the key in App Store Connect.

Unconfigured (no RG_APNS_KEY_P8/RG_APNS_KEY_PATH) is a deliberate no-op, the
same pattern as mailer.py for SMTP — the rest of the app works without it.
"""

import logging
import time
from typing import Optional

import httpx
import jwt

from .config import Settings
from .db import Database

log = logging.getLogger("roblox_guard.push")

PROD_HOST = "https://api.push.apple.com"
SANDBOX_HOST = "https://api.sandbox.push.apple.com"

# APNs auth tokens are valid up to 1 hour; refresh a bit early to be safe.
TOKEN_LIFETIME_SECONDS = 45 * 60


class APNsService:
    def __init__(self, settings: Settings):
        self.settings = settings
        self._token: Optional[str] = None
        self._token_issued_at: float = 0.0

    @property
    def configured(self) -> bool:
        s = self.settings
        return bool((s.apns_key_p8 or s.apns_key_path) and s.apns_key_id and s.apns_team_id)

    def _private_key(self) -> str:
        if self.settings.apns_key_p8:
            return self.settings.apns_key_p8
        with open(self.settings.apns_key_path) as f:
            return f.read()

    def _auth_token(self) -> str:
        now = time.time()
        if self._token and (now - self._token_issued_at) < TOKEN_LIFETIME_SECONDS:
            return self._token
        self._token = jwt.encode(
            {"iss": self.settings.apns_team_id, "iat": int(now)},
            self._private_key(),
            algorithm="ES256",
            headers={"kid": self.settings.apns_key_id},
        )
        self._token_issued_at = now
        return self._token

    async def send(self, device_token: str, title: str, body: str, badge: int = 0) -> bool:
        """Sends one push. Returns False (and logs) on any failure — best-effort."""
        ok, _gone = await self._send(device_token, title, body, badge)
        return ok

    async def _send(self, device_token: str, title: str, body: str,
                    badge: int) -> tuple[bool, bool]:
        """Returns (delivered, apple_says_token_is_dead) — the second value
        drives pruning in send_to_all(); a lone send() discards it."""
        if not self.configured:
            return False, False
        host = SANDBOX_HOST if self.settings.apns_use_sandbox else PROD_HOST
        payload = {"aps": {"alert": {"title": title, "body": body},
                          "sound": "default", "badge": badge}}
        headers = {
            "authorization": f"bearer {self._auth_token()}",
            "apns-topic": self.settings.apns_bundle_id,
            "apns-push-type": "alert",
            "apns-priority": "10",
        }
        try:
            async with httpx.AsyncClient(http2=True, timeout=10.0) as client:
                resp = await client.post(
                    f"{host}/3/device/{device_token}", json=payload, headers=headers)
        except httpx.TransportError as error:
            log.warning("APNs request failed for %s...: %s", device_token[:8], error)
            return False, False

        if resp.status_code == 200:
            return True, False
        gone = resp.status_code == 410 or "BadDeviceToken" in resp.text
        log.warning("APNs rejected push to %s...: %s %s",
                   device_token[:8], resp.status_code, resp.text[:200])
        return False, gone

    async def send_to_all(self, db: Database, title: str, body: str,
                          client_id: Optional[str] = None) -> dict:
        """Pushes only to the requested installation's registered devices."""
        if not self.configured:
            return {"sent": 0, "failed": 0, "pruned": 0, "configured": False}
        tokens = db.list_device_tokens(client_id)
        badge = db.total_unacknowledged_alerts(client_id)
        sent = failed = pruned = 0
        for token in tokens:
            ok, gone = await self._send(token, title, body, badge)
            if ok:
                sent += 1
            else:
                failed += 1
                if gone:
                    db.remove_device_token(token, client_id)
                    pruned += 1
        return {"sent": sent, "failed": failed, "pruned": pruned, "configured": True}
