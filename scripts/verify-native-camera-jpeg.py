#!/usr/bin/env python3
"""Verify a diagnostic camera JPEG's structure and decoded error against Cyna PPM."""

import argparse
import hashlib
import json
import subprocess
from pathlib import Path


def jpeg_identity(path: Path, expected_profile: bytes) -> tuple[int, int, str]:
    data = path.read_bytes()
    if not data.startswith(b"\xff\xd8"):
        raise ValueError("expected JPEG SOI")
    offset = 2
    profile_parts: dict[int, bytes] = {}
    profile_count = None
    dimensions = None
    sampling = None
    while offset < len(data):
        if data[offset] != 0xFF:
            raise ValueError("unexpected JPEG marker position")
        while offset < len(data) and data[offset] == 0xFF:
            offset += 1
        marker = data[offset]
        offset += 1
        if marker == 0xDA:
            break
        if marker in (0xD8, 0xD9) or 0xD0 <= marker <= 0xD7:
            continue
        if offset + 2 > len(data):
            raise ValueError("truncated JPEG segment")
        length = int.from_bytes(data[offset:offset + 2], "big")
        if length < 2 or offset + length > len(data):
            raise ValueError("invalid JPEG segment length")
        segment = data[offset + 2:offset + length]
        offset += length
        if marker == 0xE2 and segment.startswith(b"ICC_PROFILE\0"):
            sequence, count = segment[12:14]
            if not sequence or not count or (profile_count is not None and profile_count != count) or sequence in profile_parts:
                raise ValueError("invalid ICC segment sequence")
            profile_count = count
            profile_parts[sequence] = segment[14:]
        if marker == 0xE1:
            raise ValueError("APP1 source metadata is outside export metadata policy v1")
        if marker == 0xC0:
            if len(segment) < 15 or segment[0] != 8 or segment[5] != 3:
                raise ValueError("expected 8-bit three-component baseline JPEG")
            dimensions = (int.from_bytes(segment[3:5], "big"), int.from_bytes(segment[1:3], "big"))
            sampling = [segment[7 + index * 3] for index in range(3)]
    if dimensions is None or sampling != [0x11] * 3:
        raise ValueError("missing baseline dimensions or 4:4:4 sampling")
    if profile_count is None or set(profile_parts) != set(range(1, profile_count + 1)):
        raise ValueError("incomplete ICC profile")
    profile = b"".join(profile_parts[index] for index in range(1, profile_count + 1))
    if profile != expected_profile:
        raise ValueError("embedded ICC differs from pinned profile")
    return *dimensions, hashlib.sha256(profile).hexdigest()


def ppm_raster(ppm: bytes, width: int, height: int) -> bytes:
    parts = ppm.split(b"\n", 3)
    if parts[:3] != [b"P6", f"{width} {height}".encode(), b"255"] or len(parts) != 4:
        raise ValueError("unexpected PPM header")
    if len(parts[3]) != width * height * 3:
        raise ValueError("unexpected PPM raster length")
    return parts[3]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("jpeg", type=Path)
    parser.add_argument("full_size_ppm", type=Path)
    parser.add_argument("icc_profile", type=Path)
    args = parser.parse_args()
    width, height, profile_sha256 = jpeg_identity(args.jpeg, args.icc_profile.read_bytes())
    decoded = subprocess.run(["magick", str(args.jpeg), "-depth", "8", "PPM:-"], check=True, capture_output=True).stdout
    actual = ppm_raster(decoded, width, height)
    reference = ppm_raster(args.full_size_ppm.read_bytes(), width, height)
    histogram = [0] * 256
    for a, b in zip(actual, reference):
        histogram[abs(a - b)] += 1
    total = len(reference)
    limit = (total * 99 + 99) // 100
    cumulative = 0
    p99 = 0
    for difference, count in enumerate(histogram):
        cumulative += count
        if cumulative >= limit:
            p99 = difference
            break
    result = {
        "dimensions": [width, height],
        "channels": total,
        "mean_absolute_error": sum(d * n for d, n in enumerate(histogram)) / total,
        "p99_absolute_error": p99,
        "maximum_absolute_error": max(i for i, n in enumerate(histogram) if n),
        "exact_channels": histogram[0],
        "icc_sha256": profile_sha256,
        "sampling": "4:4:4",
    }
    print(json.dumps(result))


if __name__ == "__main__":
    main()
