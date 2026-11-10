#!/usr/bin/env python3
"""Match v4 HSL fitted preview, TIFF, and source-detail worker pixels."""

import hashlib
import json
from pathlib import Path
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "ui/neiv/build"
SOURCE = ROOT / "target/native-source-corpus/Ricoh-GR-IIIx.DNG"
ICC = ROOT / "src/engine/assets/sRGB2014.icc"
OUTPUT = ROOT / "target/geometry-export-check/hsl-v4"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def request(path: Path, values: list[int]) -> None:
    path.write_bytes(struct.pack(f"<{len(values)}i", *values))


def tiff_rgb(path: Path, width: int, height: int) -> bytes:
    data = path.read_bytes()
    if data[:4] != b"II*\0":
        raise ValueError("invalid TIFF header")
    offset = struct.unpack_from("<I", data, 78)[0]
    pixels = data[offset:]
    if len(pixels) != width * height * 6:
        raise ValueError("invalid TIFF extent")
    return pixels


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    before = digest(SOURCE)
    controls = [0] * 12
    hsl = [0] * 24
    hsl[8] = -30  # Red band chroma reduction.
    hsl[9] = 20
    hsl[16 + 5] = 15
    left, top, width, height = 1000, 2000, 128, 96
    geometry = [left, top, width, height, 0, 6]
    request(OUTPUT / "tiff-v4.bin", [4, 1, *controls, *geometry, *hsl])
    request(OUTPUT / "preview-v4.bin", [4, 1, *controls, width, height, *geometry, *hsl])
    tile_width, tile_height = 64, 48
    request(OUTPUT / "region-v4.bin", [4, 1, *controls, 0, 0,
        tile_width, tile_height, *geometry, *hsl])
    subprocess.run([str(BUILD / "lightcept-export-tiff"), str(SOURCE),
        str(ICC), str(OUTPUT / "tiff-v4.bin"), str(OUTPUT / "hsl.tiff")],
        check=True)
    subprocess.run([str(BUILD / "lightcept-fitted-preview"), str(SOURCE),
        str(OUTPUT / "preview-v4.bin"), str(OUTPUT / "hsl.rgba"),
        str(OUTPUT / "hsl.working")], check=True)
    subprocess.run([str(BUILD / "lightcept-source-region"), str(SOURCE),
        str(OUTPUT / "region-v4.bin"), str(OUTPUT / "hsl-tile.rgba")],
        check=True)
    invalid_hsl = hsl.copy()
    invalid_hsl[8] = 101
    request(OUTPUT / "invalid-v4.bin", [4, 1, *controls, *geometry,
        *invalid_hsl])
    invalid_output = OUTPUT / "invalid.tiff"
    invalid_output.unlink(missing_ok=True)
    rejected = subprocess.run([str(BUILD / "lightcept-export-tiff"),
        str(SOURCE), str(ICC), str(OUTPUT / "invalid-v4.bin"),
        str(invalid_output)], check=False)
    if rejected.returncode != 5 or invalid_output.exists():
        raise ValueError("out-of-range HSL request was not rejected before output")
    rgb16 = tiff_rgb(OUTPUT / "hsl.tiff", width, height)
    preview = (OUTPUT / "hsl.rgba").read_bytes()
    tile = (OUTPUT / "hsl-tile.rgba").read_bytes()
    if len(preview) != width * height * 4 or len(tile) != tile_width * tile_height * 4:
        raise ValueError("invalid preview or tile extent")
    differences = []
    for pixel in range(width * height):
        for channel in range(3):
            fine = struct.unpack_from("<H", rgb16, pixel * 6 + channel * 2)[0]
            differences.append(abs(preview[pixel * 4 + channel] - round(fine / 257)))
    tile_differences = []
    for row in range(tile_height):
        for column in range(tile_width):
            for channel in range(3):
                expected = preview[(row * width + column) * 4 + channel]
                actual = tile[(row * tile_width + column) * 4 + channel]
                tile_differences.append(abs(actual - expected))
    after = digest(SOURCE)
    report = {"source_sha256_before": before, "source_sha256_after": after,
        "preview_tiff_max_difference": max(differences),
        "tile_preview_max_difference": max(tile_differences),
        "channels_compared": len(differences),
        "tile_channels_compared": len(tile_differences),
        "invalid_hsl_exit": rejected.returncode}
    (OUTPUT / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    if before != after or max(differences) > 1 or max(tile_differences) > 1:
        raise ValueError(report)
    fixture = json.loads((ROOT / "target/geometry-export-check/neiv-quarter-turn-schema8-ui.lightcept").read_text())
    if fixture["schema"] != 8 or fixture["history"][-1][12:] != geometry:
        raise ValueError("schema 8 fixture no longer matches the HSL worker crop")
    fixture["schema"] = 9
    fixture["history"] = [entry + [0] * 24 for entry in fixture["history"]]
    fixture["history"].append(fixture["history"][-1][:18] + hsl)
    fixture["cursor"] = len(fixture["history"]) - 1
    fixture["editRevision"] += 1
    fixture["previewSHA256"] = digest(OUTPUT / "hsl.rgba")
    fixture["workingSHA256"] = digest(OUTPUT / "hsl.working")
    (OUTPUT / "neiv-hsl-schema9-open-check.lightcept").write_text(
        json.dumps(fixture, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
