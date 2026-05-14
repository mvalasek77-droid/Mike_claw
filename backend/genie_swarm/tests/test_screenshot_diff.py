"""Tests for the perceptual screenshot diff.

We synthesise PNGs in-memory (no Pillow dependency, no on-disk
fixtures) so the test suite stays hermetic.
"""
from __future__ import annotations

import struct
import zlib
from pathlib import Path

import pytest

from genie_swarm.screenshot_diff import (
    ScreenshotDiff,
    diff,
    hash_image,
)


def _make_png(width: int, height: int, pixel_fn) -> bytes:
    """Build a minimal RGB (color_type=2) PNG. `pixel_fn(x, y)` -> (r,g,b)."""
    sig = b"\x89PNG\r\n\x1a\n"
    ihdr_data = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    ihdr = _chunk(b"IHDR", ihdr_data)

    raw = bytearray()
    for y in range(height):
        raw.append(0)  # filter: None
        for x in range(width):
            r, g, b = pixel_fn(x, y)
            raw.append(r); raw.append(g); raw.append(b)
    idat = _chunk(b"IDAT", zlib.compress(bytes(raw)))
    iend = _chunk(b"IEND", b"")
    return sig + ihdr + idat + iend


def _chunk(name: bytes, data: bytes) -> bytes:
    crc = zlib.crc32(name + data) & 0xFFFFFFFF
    return struct.pack(">I", len(data)) + name + data + struct.pack(">I", crc)


# --------------------------------------------------------------------------- #
# hash_image
# --------------------------------------------------------------------------- #

def test_hash_image_is_deterministic(tmp_path: Path):
    png = _make_png(64, 64, lambda x, y: (x * 4, 0, y * 4))
    path = tmp_path / "img.png"
    path.write_bytes(png)
    assert hash_image(path) == hash_image(path)


def test_hash_image_differs_between_distinct_images(tmp_path: Path):
    light = tmp_path / "light.png"
    dark = tmp_path / "dark.png"
    light.write_bytes(_make_png(32, 32, lambda x, y: (240, 240, 240)))
    dark.write_bytes(_make_png(32, 32, lambda x, y: (10, 10, 10)))
    # Solid images both end up with bits ≥ mean === bit=1 across all
    # cells, so the hashes are equal — not a useful test on their own.
    # The interesting case is a gradient vs. its inversion: same total
    # luminance but flipped spatial pattern → many bits differ.
    pattern_a = tmp_path / "a.png"
    pattern_b = tmp_path / "b.png"
    pattern_a.write_bytes(_make_png(32, 32, lambda x, y: (255 if x < 16 else 0, 0, 0)))
    pattern_b.write_bytes(_make_png(32, 32, lambda x, y: (0 if x < 16 else 255, 0, 0)))
    assert hash_image(pattern_a) != hash_image(pattern_b)


def test_hash_image_rejects_non_png(tmp_path: Path):
    junk = tmp_path / "junk.png"
    junk.write_bytes(b"this is not a png file at all")
    with pytest.raises(ValueError):
        hash_image(junk)


# --------------------------------------------------------------------------- #
# diff
# --------------------------------------------------------------------------- #

def test_diff_identical_images_are_same(tmp_path: Path):
    png = _make_png(32, 32, lambda x, y: (x * 8, y * 8, 128))
    a = tmp_path / "a.png"; b = tmp_path / "b.png"
    a.write_bytes(png); b.write_bytes(png)
    result = diff(a, b, tolerance=0)
    assert result.same
    assert result.bits_different == 0
    assert result.drift_ratio == 0.0


def test_diff_inverted_pattern_flags_drift(tmp_path: Path):
    """Half-and-half horizontal split vs. its inversion: 4 of 8
    columns flip per row, so the 8×8 hash flips half its bits."""
    a = tmp_path / "a.png"; b = tmp_path / "b.png"
    a.write_bytes(_make_png(32, 32, lambda x, y: (255 if x < 16 else 0, 0, 0)))
    b.write_bytes(_make_png(32, 32, lambda x, y: (0 if x < 16 else 255, 0, 0)))
    result = diff(a, b, tolerance=8)
    assert not result.same
    assert result.bits_different > 8
    assert 0 < result.drift_ratio <= 1.0


def test_diff_tolerance_clamped(tmp_path: Path):
    png = _make_png(8, 8, lambda x, y: (x * 30, y * 30, 0))
    a = tmp_path / "a.png"; b = tmp_path / "b.png"
    a.write_bytes(png); b.write_bytes(png)
    with pytest.raises(ValueError):
        diff(a, b, tolerance=-1)
    with pytest.raises(ValueError):
        diff(a, b, tolerance=65)


def test_diff_returns_structured_result(tmp_path: Path):
    png = _make_png(16, 16, lambda x, y: (x * 16, y * 16, 0))
    a = tmp_path / "a.png"; b = tmp_path / "b.png"
    a.write_bytes(png); b.write_bytes(png)
    result = diff(a, b)
    assert isinstance(result, ScreenshotDiff)
    assert result.baseline == str(a)
    assert result.candidate == str(b)
    assert result.tolerance == 8     # default
