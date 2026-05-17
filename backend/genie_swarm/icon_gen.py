"""App icon generation via OpenAI's image API.

Closes one of the production blockers called out in
`docs/PRODUCTION_BLOCKERS.md`: previously the iOS app's onboarding
slide 6 promised "Icon forged with ChatGPT" but no backend code
actually called an image API.

Public surface:
- `generate_app_icon(...)` async — calls OpenAI's images endpoint,
  saves the PNG into the workspace's `AppIcon.appiconset`, strips
  alpha (Apple rejects RGBA in App Store icons), returns the path.
- `IconGenError` raised on any failure so the FastAPI layer can
  convert to a 4xx with a useful message.

We deliberately keep the OpenAI client import lazy so the test
suite can pass without `openai` being installed, and so a Pillow
absence degrades gracefully (we keep the raw PNG and log a warning
rather than crashing — Apple will reject it later, but the user
still has SOMETHING in the asset catalogue).
"""
from __future__ import annotations

import base64
import io
import logging
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol

logger = logging.getLogger(__name__)


class IconGenError(Exception):
    """Surfaced by `generate_app_icon` on any failure path."""


@dataclass(frozen=True)
class IconResult:
    """Returned to the FastAPI layer + persisted in memory so we can
    show the user the image they paid for without re-running the call."""
    path: Path
    bytes_written: int
    alpha_stripped: bool
    prompt_used: str


class _ImagesClient(Protocol):
    """Just enough surface to let tests inject a fake."""
    async def generate_png_b64(self, *, prompt: str, size: str = "1024x1024") -> str: ...


class OpenAIImagesClient:
    """Real client. Lazy-imports the OpenAI SDK so the rest of the
    backend (and tests) don't pay the import cost or require the
    dependency unless icon generation is actually invoked.
    """
    def __init__(self, api_key: str | None = None) -> None:
        import os
        self.api_key = api_key or os.environ.get("OPENAI_API_KEY", "")

    async def generate_png_b64(self, *, prompt: str, size: str = "1024x1024") -> str:
        if not self.api_key:
            raise IconGenError("OPENAI_API_KEY is not set; cannot generate icon")
        try:
            from openai import AsyncOpenAI  # type: ignore[import-not-found]
        except ImportError as e:
            raise IconGenError("install `openai` to generate icons") from e

        client = AsyncOpenAI(api_key=self.api_key)
        try:
            result = await client.images.generate(
                model="gpt-image-1",
                prompt=prompt,
                size=size,
                n=1,
            )
        except Exception as e:
            raise IconGenError(f"image API failed: {e}") from e

        if not result.data or not getattr(result.data[0], "b64_json", None):
            raise IconGenError("image API returned no data")
        return result.data[0].b64_json  # type: ignore[return-value]


_DEFAULT_PROMPT_TEMPLATE = (
    "An iOS app icon for an app called \"{title}\". {description} "
    "Style: bold, simple, instantly recognizable at 60px; flat or soft "
    "gradient; centered subject; no text; no transparent background; "
    "no rounded corners (Apple applies the squircle mask)."
)


async def generate_app_icon(
    *,
    title: str,
    description: str,
    workspace: Path,
    client: _ImagesClient | None = None,
    prompt_override: str | None = None,
) -> IconResult:
    """Generate a 1024×1024 PNG and write it into the workspace's
    `Assets.xcassets/AppIcon.appiconset/icon-1024.png`. Creates the
    directory if needed; overwrites any existing file. Strips alpha
    if Pillow is available so the result passes App Store validation.

    Raises `IconGenError` on any failure; callers translate to a
    FastAPI HTTPException.
    """
    title = (title or "").strip()
    description = (description or "").strip()
    if not title:
        raise IconGenError("title is required")

    prompt = prompt_override or _DEFAULT_PROMPT_TEMPLATE.format(
        title=title,
        description=description or f"A native iOS app called {title}.",
    )
    used_client = client or OpenAIImagesClient()
    b64 = await used_client.generate_png_b64(prompt=prompt, size="1024x1024")
    try:
        raw = base64.b64decode(b64, validate=True)
    except Exception as e:
        raise IconGenError(f"image API returned non-base64 payload: {e}") from e

    icon_bytes, alpha_stripped = _strip_alpha_if_possible(raw)

    appiconset = workspace / "Assets.xcassets" / "AppIcon.appiconset"
    appiconset.mkdir(parents=True, exist_ok=True)
    icon_path = appiconset / "icon-1024.png"
    icon_path.write_bytes(icon_bytes)

    return IconResult(
        path=icon_path,
        bytes_written=len(icon_bytes),
        alpha_stripped=alpha_stripped,
        prompt_used=prompt,
    )


def _strip_alpha_if_possible(raw: bytes) -> tuple[bytes, bool]:
    """Use Pillow to flatten alpha onto white if available. If Pillow
    isn't installed, return the original bytes and let the user know
    via the IconResult — Apple will reject an RGBA icon at upload
    time, but the user at least has SOMETHING in the catalogue and
    can deal with it from a non-failed state.
    """
    try:
        from PIL import Image  # type: ignore[import-not-found]
    except ImportError:
        logger.warning("Pillow not installed; returning icon unmodified")
        return raw, False

    image = Image.open(io.BytesIO(raw))
    if image.mode in ("RGBA", "LA") or (image.mode == "P" and "transparency" in image.info):
        # Flatten transparency onto white. Apple's icon mask is the
        # squircle, so the background colour only shows briefly during
        # the icon render — white is a safe neutral default.
        rgba = image.convert("RGBA")
        flat = Image.new("RGB", rgba.size, (255, 255, 255))
        flat.paste(rgba, mask=rgba.split()[3])
        out = io.BytesIO()
        flat.save(out, format="PNG", optimize=True)
        return out.getvalue(), True

    # Already opaque — re-save as PNG so we control the encoding.
    if image.mode != "RGB":
        image = image.convert("RGB")
    out = io.BytesIO()
    image.save(out, format="PNG", optimize=True)
    return out.getvalue(), False
