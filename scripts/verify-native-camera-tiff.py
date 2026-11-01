#!/usr/bin/env python3
"""Verify a diagnostic RGB16 TIFF against the full-size Cyna PPM preview."""

import argparse
import hashlib
import json
import struct
import subprocess
from pathlib import Path


def tiff_identity(path: Path, expected_profile: bytes) -> tuple[int, int, str]:
    with path.open("rb") as source:
        header = source.read(8)
        if len(header) != 8 or header[:4] != b"II*\0":
            raise ValueError("expected little-endian Classic TIFF")
        ifd_offset = struct.unpack_from("<I", header, 4)[0]
        source.seek(ifd_offset)
        count = struct.unpack("<H", source.read(2))[0]
        entries = source.read(count * 12)
        if len(entries) != count * 12:
            raise ValueError("truncated TIFF directory")
        tags = {tag: (kind, length, value) for tag, kind, length, value in struct.iter_unpack("<HHII", entries)}

        def scalar(tag: int) -> int:
            kind, length, value = tags[tag]
            if length != 1 or kind not in (3, 4):
                raise ValueError(f"unexpected TIFF tag {tag} shape")
            return value if kind == 4 else value & 0xFFFF

        width, height = scalar(256), scalar(257)
        if scalar(259) != 1 or scalar(262) != 2 or scalar(277) != 3:
            raise ValueError("expected uncompressed RGB TIFF")
        if scalar(274) != 1:
            raise ValueError("expected top-left output orientation")
        for tag in (315, 306, 271, 272, 33432, 34665, 34853):
            if tag in tags:
                raise ValueError(f"source metadata tag {tag} is outside export metadata policy v1")
        kind, length, offset = tags[258]
        if kind != 3 or length != 3:
            raise ValueError("expected three BitsPerSample values")
        source.seek(offset)
        if struct.unpack("<HHH", source.read(6)) != (16, 16, 16):
            raise ValueError("expected RGB16 TIFF")
        kind, length, offset = tags[34675]
        if kind != 1 or length != len(expected_profile):
            raise ValueError("missing or incorrect ICC tag")
        source.seek(offset)
        profile = source.read(length)
        if profile != expected_profile:
            raise ValueError("embedded ICC differs from the pinned profile")
    return width, height, hashlib.sha256(profile).hexdigest()


def ppm_raster(ppm: bytes, width: int, height: int) -> bytes:
    parts = ppm.split(b"\n", 3)
    if parts[:3] != [b"P6", f"{width} {height}".encode(), b"255"]:
        raise ValueError("unexpected PPM header")
    raster = parts[3]
    if len(raster) != width * height * 3:
        raise ValueError("unexpected PPM raster length")
    return raster


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tiff", type=Path)
    parser.add_argument("full_size_ppm", type=Path)
    parser.add_argument("icc_profile", type=Path)
    args = parser.parse_args()
    width, height, profile_sha256 = tiff_identity(args.tiff, args.icc_profile.read_bytes())
    decoded = subprocess.run(
        ["magick", str(args.tiff), "-depth", "8", "PPM:-"],
        check=True,
        capture_output=True,
    ).stdout
    reference = ppm_raster(args.full_size_ppm.read_bytes(), width, height)
    actual = ppm_raster(decoded, width, height)
    mismatches = sum(a != b for a, b in zip(actual, reference))
    print(json.dumps({"dimensions": [width, height], "channels": len(reference), "mismatches": mismatches, "icc_sha256": profile_sha256}))
    if mismatches:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
