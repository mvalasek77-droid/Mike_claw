from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import pytest

from genie_swarm.screenshot_capture import (
    SCREENSHOT_DEVICES,
    ScreenshotCaptureError,
    capture_app_store_set,
    capture_screenshot,
)


@dataclass
class _RunnerResult:
    ok: bool
    exit_code: int
    stdout_tail: str = ""
    duration_ms: int = 0
    strategy: str = "stub"


class _FakeRunner:
    """Pretends to be a MacRunner. Each `simctl` call optionally
    writes a PNG to the output path the test passes us — that's how
    we simulate simctl's "write file to disk" behaviour without
    needing a real simulator.
    """

    def __init__(self, *, write_png: bool = True, exit_code: int = 0) -> None:
        self.write_png = write_png
        self.exit_code = exit_code
        self.calls: list[tuple[str, list[str]]] = []

    async def simctl(self, *, subcommand: str, args: list[str], sandbox):
        self.calls.append((subcommand, args))
        if self.write_png and subcommand == "io" and len(args) >= 3 and args[1] == "screenshot":
            target = Path(args[2])
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(b"\x89PNG\r\n\x1a\nfakeimagebytes")
        return _RunnerResult(
            ok=self.exit_code == 0,
            exit_code=self.exit_code,
            stdout_tail="ok" if self.exit_code == 0 else "boom",
        )


@pytest.mark.asyncio
async def test_capture_screenshot_happy_path(tmp_path: Path):
    """Single capture: simctl is invoked with `io booted screenshot
    <path>`, the file lands on disk, and we report the size."""
    runner = _FakeRunner()
    out = tmp_path / "shot.png"
    captured = await capture_screenshot(
        runner=runner,
        sandbox=None,  # FakeRunner doesn't care
        output_path=out,
    )
    assert out.exists()
    assert captured.path == out
    assert captured.bytes_written > 0
    sub, args = runner.calls[0]
    assert sub == "io"
    assert args[:2] == ["booted", "screenshot"]


@pytest.mark.asyncio
async def test_capture_screenshot_raises_when_simctl_fails(tmp_path: Path):
    """Non-zero exit from simctl surfaces as ScreenshotCaptureError,
    not a bare exit-code leak."""
    runner = _FakeRunner(write_png=False, exit_code=2)
    with pytest.raises(ScreenshotCaptureError) as ctx:
        await capture_screenshot(
            runner=runner,
            sandbox=None,
            output_path=tmp_path / "nope.png",
        )
    assert "exit=2" in str(ctx.value)


@pytest.mark.asyncio
async def test_capture_screenshot_raises_on_missing_file(tmp_path: Path):
    """simctl can return ok=True but still leave no file (e.g. when
    no simulator is booted). We catch that case and surface a clear
    error instead of silently succeeding."""
    runner = _FakeRunner(write_png=False, exit_code=0)
    with pytest.raises(ScreenshotCaptureError) as ctx:
        await capture_screenshot(
            runner=runner,
            sandbox=None,
            output_path=tmp_path / "missing.png",
        )
    assert "doesn't exist" in str(ctx.value)


@pytest.mark.asyncio
async def test_capture_app_store_set_writes_one_per_device(tmp_path: Path):
    """Default set: one PNG per required App Store device size,
    landing under <workspace>/Screenshots/<device-id>.png."""
    runner = _FakeRunner()
    captured = await capture_app_store_set(
        runner=runner,
        sandbox=None,
        workspace=tmp_path,
    )
    assert len(captured) == len(SCREENSHOT_DEVICES)
    for shot in captured:
        assert shot.path.exists()
        assert shot.path.name.endswith(".png")
        assert shot.path.parent == tmp_path / "Screenshots"
        assert shot.bytes_written > 0
    # Each device id should appear exactly once.
    ids = {shot.device.id for shot in captured}
    assert ids == {d.id for d in SCREENSHOT_DEVICES}


@pytest.mark.asyncio
async def test_capture_app_store_set_respects_custom_device_list(tmp_path: Path):
    """Caller can pass a subset of devices (e.g. just iPhone-67 if
    the user disabled the iPad target)."""
    runner = _FakeRunner()
    only = [SCREENSHOT_DEVICES[0]]
    captured = await capture_app_store_set(
        runner=runner,
        sandbox=None,
        workspace=tmp_path,
        devices=only,
    )
    assert len(captured) == 1
    assert captured[0].device.id == SCREENSHOT_DEVICES[0].id
