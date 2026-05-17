from __future__ import annotations

import base64
import json
import struct
import zlib
from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from genie_swarm.api import router, state
from genie_swarm.icon_gen import (
    IconGenError,
    _strip_alpha_if_possible,
    generate_app_icon,
)
from genie_swarm.models import AppSpec, BuildJob
from genie_swarm.release_readiness import run_release_readiness


def _png_1024_rgb_bytes() -> bytes:
    """Build a minimal valid 1024×1024 PNG (single colour, no alpha)
    so the tests don't depend on Pillow being installed and we can
    verify the bytes round-trip end-to-end."""
    width = height = 1024
    raw = b""
    for _ in range(height):
        raw += b"\x00" + (b"\xff\x80\x40" * width)
    compressed = zlib.compress(raw, 9)

    def chunk(kind: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + kind
            + data
            + struct.pack(">I", zlib.crc32(kind + data))
        )

    signature = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return (
        signature
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", compressed)
        + chunk(b"IEND", b"")
    )


class _StubImagesClient:
    """Injectable fake so tests don't hit OpenAI. Returns whatever
    bytes the test sets up, b64-encoded as the real client would."""

    def __init__(self, png_bytes: bytes) -> None:
        self.png_bytes = png_bytes
        self.last_prompt: str | None = None

    async def generate_png_b64(self, *, prompt: str, size: str = "1024x1024") -> str:
        self.last_prompt = prompt
        return base64.b64encode(self.png_bytes).decode("ascii")


@pytest.mark.asyncio
async def test_generate_app_icon_writes_to_appiconset(tmp_path: Path):
    """Happy path: a stub client returns a known PNG, we land it
    at workspace/Assets.xcassets/AppIcon.appiconset/icon-1024.png."""
    png = _png_1024_rgb_bytes()
    client = _StubImagesClient(png)

    result = await generate_app_icon(
        title="TideRider",
        description="A surfing tide tracker.",
        workspace=tmp_path,
        client=client,
    )

    expected_path = tmp_path / "Assets.xcassets" / "AppIcon.appiconset" / "icon-1024.png"
    assert expected_path.exists()
    assert result.path == expected_path
    assert result.bytes_written > 0
    assert "TideRider" in (client.last_prompt or "")
    assert "no rounded corners" in (client.last_prompt or "")


@pytest.mark.asyncio
async def test_generate_app_icon_requires_title(tmp_path: Path):
    """Title is a hard requirement — without it the OpenAI prompt
    would be useless and we'd waste a paid image generation call."""
    client = _StubImagesClient(_png_1024_rgb_bytes())
    with pytest.raises(IconGenError):
        await generate_app_icon(
            title="   ",
            description="anything",
            workspace=tmp_path,
            client=client,
        )


@pytest.mark.asyncio
async def test_generate_app_icon_uses_prompt_override(tmp_path: Path):
    """Power users can hand in a fully-formed prompt and bypass the
    default template (e.g. for brand-specific style guidance)."""
    client = _StubImagesClient(_png_1024_rgb_bytes())
    override = "An abstract glass triangle on cobalt, no text"

    result = await generate_app_icon(
        title="GlassPrism",
        description="",
        workspace=tmp_path,
        client=client,
        prompt_override=override,
    )

    assert client.last_prompt == override
    assert result.prompt_used == override


def test_strip_alpha_passthrough_when_pillow_missing(monkeypatch):
    """If Pillow isn't installed we return the original bytes and a
    `False` alpha_stripped flag — the user still has an icon, just
    one Apple may reject at upload time. Graceful degrade."""
    import sys
    import builtins

    real_import = builtins.__import__

    def _fail_on_pil(name, *args, **kwargs):
        if name == "PIL" or name.startswith("PIL."):
            raise ImportError("Pillow not installed in this env")
        return real_import(name, *args, **kwargs)

    monkeypatch.setattr(builtins, "__import__", _fail_on_pil)
    # Drop any cached PIL modules so the import inside the function
    # actually re-fails.
    for mod in list(sys.modules):
        if mod == "PIL" or mod.startswith("PIL."):
            sys.modules.pop(mod, None)

    raw = _png_1024_rgb_bytes()
    out, stripped = _strip_alpha_if_possible(raw)
    assert out == raw
    assert stripped is False


def test_icon_route_records_path_and_release_readiness_picks_it_up(
    tmp_path: Path, monkeypatch
):
    """POST /icon/generate writes the icon and release_readiness's
    new `app_icon` gate flips from needs_setup to automated."""
    app = FastAPI()
    app.include_router(router)
    original_config = state.config
    original_jobs = dict(state.jobs)
    state.config = state.config.__class__(workspace_root=tmp_path)
    state.jobs.clear()

    job = BuildJob(id="job_icon", spec=AppSpec(title="TideRider", prompt="surf"))
    state.jobs[job.id] = job

    # Inject the stub client into the module so the route doesn't
    # call OpenAI. We monkey-patch the OpenAIImagesClient constructor
    # to return the stub regardless of api_key state.
    from genie_swarm import icon_gen
    stub = _StubImagesClient(_png_1024_rgb_bytes())
    monkeypatch.setattr(icon_gen, "OpenAIImagesClient", lambda api_key=None: stub)

    try:
        client = TestClient(app)
        response = client.post(
            f"/api/coding/swarm/{job.id}/icon/generate",
            json={"title": "TideRider", "description": "Surf tide tracker"},
        )
        assert response.status_code == 200, response.text
        body = response.json()
        assert body["ok"] is True
        assert body["path"].endswith("icon-1024.png")
        assert "TideRider" in body["prompt_used"]

        # release_readiness should now see the icon and flip the gate.
        readiness = run_release_readiness(
            spec=job.spec,
            workspace=tmp_path / job.id,
        )
        icon_item = next(i for i in readiness["items"] if i["key"] == "app_icon")
        assert icon_item["status"] == "automated"
        assert "1024" in icon_item["detail"] or "icon" in icon_item["detail"].lower()
    finally:
        state.config = original_config
        state.jobs.clear()
        state.jobs.update(original_jobs)


def test_icon_route_returns_404_for_unknown_job(tmp_path: Path):
    """Surfaces a clean 404 if the user POSTs to a job that doesn't
    exist — prevents a bare KeyError from leaking."""
    app = FastAPI()
    app.include_router(router)
    original_config = state.config
    state.config = state.config.__class__(workspace_root=tmp_path)
    state.jobs.clear()

    try:
        client = TestClient(app)
        response = client.post(
            "/api/coding/swarm/does-not-exist/icon/generate",
            json={"title": "Anything", "description": "nope"},
        )
        assert response.status_code == 404
    finally:
        state.config = original_config
