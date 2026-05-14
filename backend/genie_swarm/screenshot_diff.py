"""Perceptual screenshot diffing.

Used by the UI Tester agent: after the simulator runs the golden
path, every captured frame is hashed and compared to a baseline. If
the hash drifts more than `tolerance`, we flag a `review.finding` with
the visual delta so the user can decide if the change is intentional.

We use a tiny hand-rolled aHash (average-hash) implementation — 64
bits per image — rather than pulling in `imagehash` / `Pillow` /
`numpy`. It misses some real-world edge cases (rotation, heavy
chroma) but it's plenty for catching unintended pixel-level drift in
SwiftUI screenshots that should look identical between runs.

Dependencies: stdlib only (`struct`, `zlib`, no Pillow).
"""
from __future__ import annotations

import io
import struct
import zlib
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class ScreenshotDiff:
    baseline: str
    candidate: str
    bits_different: int        # Hamming distance between the two 64-bit hashes
    tolerance: int
    drift_ratio: float         # bits_different / 64
    same: bool                 # bits_different <= tolerance


def hash_image(path: Path | str) -> int:
    """Compute the 64-bit perceptual aHash of a PNG.

    Pipeline:
      1. Decode the PNG into per-pixel grayscale (luminance Y'601 from
         RGB), downsampled to an 8x8 grid by nearest-neighbour
         sampling.
      2. Compute the mean luminance.
      3. Set bit i (MSB-first) to 1 iff cell i ≥ mean.

    Raises `ValueError` on malformed PNG, `FileNotFoundError` on
    missing path.
    """
    data = Path(path).read_bytes()
    width, height, pixels = _decode_png_rgba(data)
    if width <= 0 or height <= 0:
        raise ValueError(f"invalid image dimensions: {width}x{height}")

    grid_size = 8
    luminances: list[float] = []
    for gy in range(grid_size):
        py = int((gy + 0.5) * height / grid_size)
        py = min(max(py, 0), height - 1)
        for gx in range(grid_size):
            px = int((gx + 0.5) * width / grid_size)
            px = min(max(px, 0), width - 1)
            offset = (py * width + px) * 4
            r, g, b = pixels[offset], pixels[offset + 1], pixels[offset + 2]
            # ITU-R BT.601 luma — same coefficients UIImage uses.
            luminances.append(0.299 * r + 0.587 * g + 0.114 * b)

    mean = sum(luminances) / len(luminances)
    bits = 0
    for i, y in enumerate(luminances):
        if y >= mean:
            bits |= 1 << (63 - i)
    return bits


def diff(
    baseline: Path | str,
    candidate: Path | str,
    *,
    tolerance: int = 8,
) -> ScreenshotDiff:
    """Compute the Hamming distance between two perceptual hashes.

    `tolerance` is the maximum bits-different we treat as "same enough"
    — 8/64 = ~12% of the image flipping. SwiftUI screenshots that
    actually changed (added element, different color) typically blow
    past this; pure animation-frame drift sits well under.
    """
    if not (0 <= tolerance <= 64):
        raise ValueError(f"tolerance must be 0..64, got {tolerance}")
    a = hash_image(baseline)
    b = hash_image(candidate)
    bits = bin(a ^ b).count("1")
    return ScreenshotDiff(
        baseline=str(baseline),
        candidate=str(candidate),
        bits_different=bits,
        tolerance=tolerance,
        drift_ratio=bits / 64.0,
        same=bits <= tolerance,
    )


# ---------------------------------------------------------------------------
# Minimal PNG decoder — just enough to read the IHDR + IDAT chunks
# ---------------------------------------------------------------------------


def _decode_png_rgba(data: bytes) -> tuple[int, int, bytearray]:
    """Decode a PNG into (width, height, rgba bytes). Supports only
    8-bit truecolor (color type 2 or 6); the orchestrator only ever
    feeds us simctl-produced screenshots which match.

    Hand-rolled to avoid pulling Pillow into the runtime. A full
    decoder would handle every PNG variant; this is the narrow subset
    the production pipeline emits.
    """
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG file")

    pos = 8
    width = height = 0
    bit_depth = color_type = 0
    idat = bytearray()
    while pos < len(data):
        if pos + 8 > len(data):
            raise ValueError("truncated PNG")
        chunk_len = struct.unpack(">I", data[pos:pos + 4])[0]
        chunk_type = data[pos + 4:pos + 8]
        chunk_data = data[pos + 8:pos + 8 + chunk_len]
        pos += 8 + chunk_len + 4   # +4 = CRC, skipped

        if chunk_type == b"IHDR":
            width, height, bit_depth, color_type = struct.unpack(
                ">IIBB", chunk_data[:10]
            )
            interlace = chunk_data[12]
            if interlace != 0:
                raise ValueError("interlaced PNGs are not supported")
            if bit_depth != 8 or color_type not in (2, 6):
                raise ValueError(
                    f"unsupported PNG: bit_depth={bit_depth}, color_type={color_type}"
                )
        elif chunk_type == b"IDAT":
            idat.extend(chunk_data)
        elif chunk_type == b"IEND":
            break

    raw = zlib.decompress(bytes(idat))
    stride = width * (4 if color_type == 6 else 3)
    out = bytearray(width * height * 4)
    prev_row = bytearray(stride)
    cursor = 0
    for y in range(height):
        if cursor >= len(raw):
            raise ValueError("PNG IDAT truncated")
        filter_type = raw[cursor]
        cursor += 1
        row = bytearray(raw[cursor:cursor + stride])
        cursor += stride
        _unfilter_row(filter_type, row, prev_row, color_type == 6)
        # Write RGBA out
        for x in range(width):
            si = x * (4 if color_type == 6 else 3)
            di = (y * width + x) * 4
            out[di]     = row[si]
            out[di + 1] = row[si + 1]
            out[di + 2] = row[si + 2]
            out[di + 3] = row[si + 3] if color_type == 6 else 255
        prev_row = row
    return width, height, out


def _unfilter_row(filter_type: int, row: bytearray, prev: bytearray, has_alpha: bool) -> None:
    """Reverse PNG's per-row filter. Only types 0..4 exist; we
    implement them all because simctl emits multiple types in the
    same image."""
    bpp = 4 if has_alpha else 3
    if filter_type == 0:
        return
    if filter_type == 1:  # Sub
        for i in range(bpp, len(row)):
            row[i] = (row[i] + row[i - bpp]) & 0xFF
    elif filter_type == 2:  # Up
        for i in range(len(row)):
            row[i] = (row[i] + prev[i]) & 0xFF
    elif filter_type == 3:  # Average
        for i in range(len(row)):
            left = row[i - bpp] if i >= bpp else 0
            row[i] = (row[i] + (left + prev[i]) // 2) & 0xFF
    elif filter_type == 4:  # Paeth
        for i in range(len(row)):
            a = row[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            p = a + b - c
            pa = abs(p - a); pb = abs(p - b); pc = abs(p - c)
            pred = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
            row[i] = (row[i] + pred) & 0xFF
    else:
        raise ValueError(f"unknown PNG filter type {filter_type}")
