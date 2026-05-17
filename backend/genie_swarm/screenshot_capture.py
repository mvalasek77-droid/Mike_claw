"""Drive simctl to capture App Store screenshots.

Closes production-blocker #8: ASC step 4 says "Auto-generate
screenshots" but no backend code actually invoked simctl. We had a
perceptual screenshot *differ* (`screenshot_diff.py`) but nothing
that captured them in the first place.

Public surface:
- `SCREENSHOT_DEVICES` — Apple's required sizes for App Store
  submission (6.7" iPhone Pro Max, 6.1" iPhone, 11" iPad Pro).
- `capture_screenshot(...)` async — picks a name, runs
  `xcrun simctl io booted screenshot <path>` via the injected
  runner, returns the path it landed at.
- `capture_app_store_set(...)` async — captures one screenshot per
  required device size and dumps them under
  `<workspace>/Screenshots/<device-id>.png`.
- `ScreenshotCaptureError` raised on any failure so the FastAPI
  layer can translate to a 4xx.

The companion-runner path is exercised by the orchestrator at
runtime; here we keep the public functions pure and runner-agnostic
so unit tests can swap in a `FakeRunner` that just writes a known
PNG to the expected path.
"""
from __future__ import annotations

import asyncio
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol

from .sandbox import Sandbox


class ScreenshotCaptureError(Exception):
    """Surfaced on simctl failure or filesystem trouble."""


@dataclass(frozen=True)
class ScreenshotDevice:
    """One device size in Apple's required App Store screenshot set."""
    id: str
    label: str
    simulator_device: str   # passed to `simctl --device=...` if needed


SCREENSHOT_DEVICES: list[ScreenshotDevice] = [
    ScreenshotDevice(
        id="iphone-67",
        label='6.7" iPhone Pro Max',
        simulator_device="iPhone 16 Pro Max",
    ),
    ScreenshotDevice(
        id="iphone-61",
        label='6.1" iPhone',
        simulator_device="iPhone 16",
    ),
    ScreenshotDevice(
        id="ipad-11",
        label='11" iPad Pro',
        simulator_device='iPad Pro (11-inch) (M4)',
    ),
]


@dataclass(frozen=True)
class CapturedScreenshot:
    device: ScreenshotDevice
    path: Path
    bytes_written: int


class SimctlRunner(Protocol):
    """Minimal slice of `MacRunner` we need here — runs simctl with
    args, no concern about local vs companion. We define the slice
    locally instead of importing `MacRunner` so tests can swap in a
    bare stub without inheriting unused methods."""

    async def simctl(self, *, subcommand: str, args: list[str], sandbox: Sandbox): ...


async def capture_screenshot(
    *,
    runner: SimctlRunner,
    sandbox: Sandbox,
    output_path: Path,
    booted_only: bool = True,
) -> CapturedScreenshot:
    """Capture a single screenshot from the currently-booted simulator.

    Apple's `simctl io booted screenshot <path>` writes a PNG to
    `<path>`. We pass `booted` rather than a UDID so multiple
    simulators don't trip us up — orchestrator boots exactly one at
    a time per build.
    """
    output_path.parent.mkdir(parents=True, exist_ok=True)
    target = "booted" if booted_only else "all"
    result = await runner.simctl(
        subcommand="io",
        args=[target, "screenshot", str(output_path)],
        sandbox=sandbox,
    )
    if not result.ok:
        raise ScreenshotCaptureError(
            f"simctl io screenshot failed (exit={result.exit_code}): "
            f"{result.stdout_tail[-512:]}"
        )
    if not output_path.exists():
        raise ScreenshotCaptureError(
            f"simctl returned ok but {output_path} doesn't exist — "
            "is the simulator booted?"
        )
    size = output_path.stat().st_size
    if size == 0:
        raise ScreenshotCaptureError(f"simctl wrote an empty PNG to {output_path}")
    # `device` is unknown from a single booted capture; populate the
    # placeholder so callers can render it without crashing.
    return CapturedScreenshot(
        device=ScreenshotDevice(id="booted", label="Booted simulator", simulator_device=""),
        path=output_path,
        bytes_written=size,
    )


async def capture_app_store_set(
    *,
    runner: SimctlRunner,
    sandbox: Sandbox,
    workspace: Path,
    devices: list[ScreenshotDevice] | None = None,
) -> list[CapturedScreenshot]:
    """Capture one screenshot per required App Store device size.

    Caller is responsible for booting the right simulator between
    captures — orchestrator drives this from the UI Tester agent.
    The function captures whatever simulator is currently booted for
    each device entry; if you want different sims per device you
    must reboot between calls.
    """
    devices = devices or list(SCREENSHOT_DEVICES)
    screenshots_dir = workspace / "Screenshots"
    captured: list[CapturedScreenshot] = []
    for device in devices:
        target = screenshots_dir / f"{device.id}.png"
        shot = await capture_screenshot(
            runner=runner,
            sandbox=sandbox,
            output_path=target,
        )
        # Replace the placeholder device with the real one.
        captured.append(CapturedScreenshot(
            device=device,
            path=shot.path,
            bytes_written=shot.bytes_written,
        ))
        # Brief breather between captures so animations settle on
        # devices that share the same booted simulator.
        await asyncio.sleep(0.05)
    return captured
