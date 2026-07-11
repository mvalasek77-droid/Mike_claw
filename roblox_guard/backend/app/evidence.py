"""Evidence vault.

Three kinds of evidence, all timestamped and SHA-256 fingerprinted at capture
time so a parent can hand investigators files whose integrity is checkable:

  profile_screenshot  Headless-browser capture of the PUBLIC Roblox profile
                      page of an account involved in an alert. Public page,
                      no login — the same thing anyone could see in a browser.
  data_snapshot       Machine-readable JSON of exactly what the monitor
                      observed when an alert fired (facts, ids, timestamps).
  parent_upload       A screenshot the parent took on the child's device
                      (e.g. a chat) and imported into the vault.

Hard rule surfaced everywhere evidence is handled: sexual imagery of a minor
must never be saved or uploaded here — that is illegal even with protective
intent. The upload UI and the reports both carry this warning; suspected CSAM
gets described to investigators, never copied.
"""

import hashlib
import json
import logging
import os
from datetime import datetime, timezone
from typing import Optional

log = logging.getLogger("roblox_guard.evidence")

PROFILE_URL = "https://www.roblox.com/users/{user_id}/profile"

# The bundled Chromium in some environments lives outside Playwright's default
# discovery path; allow an explicit override.
CHROMIUM_ENV = "RG_CHROMIUM_PATH"


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


class EvidenceVault:
    def __init__(self, db, directory: str):
        self.db = db
        self.directory = directory
        os.makedirs(directory, exist_ok=True)

    def _new_path(self, prefix: str, ext: str) -> str:
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
        return os.path.join(self.directory, f"{prefix}_{stamp}.{ext}")

    # -- data snapshots ------------------------------------------------------

    def record_data_snapshot(self, child_id: int, alert_id: Optional[int],
                             payload: dict, note: str = "") -> int:
        path = self._new_path(f"snapshot_c{child_id}", "json")
        payload = dict(payload)
        payload["_captured_at"] = datetime.now(timezone.utc).isoformat()
        with open(path, "w") as f:
            json.dump(payload, f, indent=2, default=str)
        return self.db.add_evidence(
            child_id=child_id, alert_id=alert_id, kind="data_snapshot",
            path=path, sha256=sha256_file(path), note=note,
        )

    # -- parent uploads ------------------------------------------------------

    def store_parent_upload(self, child_id: int, filename: str,
                            content: bytes, note: str = "") -> int:
        ext = (os.path.splitext(filename)[1].lstrip(".") or "png").lower()
        if ext not in {"png", "jpg", "jpeg", "heic", "webp"}:
            raise ValueError("Only image files can be stored as evidence.")
        path = self._new_path(f"upload_c{child_id}", ext)
        with open(path, "wb") as f:
            f.write(content)
        return self.db.add_evidence(
            child_id=child_id, alert_id=None, kind="parent_upload",
            path=path, sha256=sha256_file(path), note=note,
        )

    # -- public-profile screenshots -------------------------------------------

    async def capture_profile_screenshot(self, child_id: int, alert_id: Optional[int],
                                         subject_user_id: int,
                                         subject_username: str = "",
                                         url: Optional[str] = None) -> Optional[int]:
        """Screenshot the subject's public profile page.

        Returns the evidence id, or None if capture isn't possible in this
        environment (Playwright missing, browser unavailable, page unreachable).
        Failure is non-fatal by design: the data_snapshot still records the
        observation, so alerts never depend on the browser working.
        """
        target = url or PROFILE_URL.format(user_id=subject_user_id)
        path = self._new_path(f"profile_c{child_id}_u{subject_user_id}", "png")
        try:
            from playwright.async_api import async_playwright
        except ImportError:
            log.info("playwright not installed; skipping profile screenshot")
            return None
        # Candidate executables: explicit override, Playwright's own discovery,
        # then the system-bundled Chromium some environments ship.
        candidates = [os.environ.get(CHROMIUM_ENV), None, "/opt/pw-browsers/chromium"]
        try:
            async with async_playwright() as pw:
                browser = None
                last_error: Optional[Exception] = None
                for exe in candidates:
                    if exe == "" or (exe and not os.path.exists(exe)):
                        continue
                    try:
                        kwargs = {"headless": True}
                        if exe:
                            kwargs["executable_path"] = exe
                        browser = await pw.chromium.launch(**kwargs)
                        break
                    except Exception as error:
                        last_error = error
                if browser is None:
                    raise last_error or RuntimeError("no usable Chromium found")
                try:
                    page = await browser.new_page(viewport={"width": 1280, "height": 1600})
                    await page.goto(target, wait_until="networkidle", timeout=30000)
                    await page.screenshot(path=path, full_page=True)
                finally:
                    await browser.close()
        except Exception:
            log.exception("profile screenshot failed for %s", target)
            return None
        note = f"Public profile page of @{subject_username or subject_user_id} ({target})"
        return self.db.add_evidence(
            child_id=child_id, alert_id=alert_id, kind="profile_screenshot",
            path=path, sha256=sha256_file(path), note=note,
        )
