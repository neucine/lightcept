#!/usr/bin/env python3
"""Select and compare full-resolution camera-render regions against a matched reference.

Both inputs must represent the same sensor crop, exposure, and encoded sRGB
view. Tile selection uses only the native image; results are diagnostic.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
from pathlib import Path


def read_ppm(path: Path) -> tuple[int, int, bytes]:
    data = path.read_bytes()
    header = re.match(rb"P6\n(\d+) (\d+)\n255\n", data)
    if header is None:
        raise ValueError("expected a P6 RGB8 PPM from the native render")
    width, height = map(int, header.groups())
    rgb = data[header.end():]
    if len(rgb) != width * height * 3:
        raise ValueError("native PPM payload size differs from dimensions")
    return width, height, rgb


def reference_rgb(path: Path, width: int, height: int) -> bytes:
    size = subprocess.run(["magick", "identify", "-format", "%w %h", str(path)], check=True, capture_output=True, text=True).stdout
    if size != f"{width} {height}":
        raise ValueError(f"reference dimensions {size} differ from native {width} {height}")
    rgb = subprocess.run(["magick", str(path), "-depth", "8", "rgb:-"], check=True, capture_output=True).stdout
    if len(rgb) != width * height * 3:
        raise ValueError("reference RGB payload size differs from dimensions")
    return rgb


def origins(length: int, tile: int) -> list[int]:
    return sorted(set(range(0, length - tile + 1, tile)) | {length - tile})


def luminance(rgb: bytes, index: int) -> float:
    return 0.2126 * rgb[index] + 0.7152 * rgb[index + 1] + 0.0722 * rgb[index + 2]


def tile_scores(rgb: bytes, width: int, x: int, y: int, tile: int) -> dict[str, float]:
    light = chroma = detail = 0.0
    count = 0
    for row in range(y + 1, y + tile - 1, 16):
        for column in range(x + 1, x + tile - 1, 16):
            index = (row * width + column) * 3
            value = luminance(rgb, index)
            light += value
            chroma += max(rgb[index:index + 3]) - min(rgb[index:index + 3])
            detail += abs(value - luminance(rgb, index + 3)) + abs(value - luminance(rgb, index + width * 3))
            count += 1
    return {"light": light / count, "chroma": chroma / count, "detail": detail / count}


def selected_tiles(rgb: bytes, width: int, height: int, tile: int) -> dict[str, dict]:
    candidates = []
    for y in origins(height, tile):
        for x in origins(width, tile):
            candidates.append({"x": x, "y": y, **tile_scores(rgb, width, x, y, tile)})
    midtones = [tile for tile in candidates if 45 <= tile["light"] <= 190]
    if not midtones:
        raise ValueError("no midtone tiles for color and detail checks")
    selected = {
        "brightest_available": max(candidates, key=lambda item: item["light"]),
        "darkest_available": min(candidates, key=lambda item: item["light"]),
        "low_chroma_midtone": min(midtones, key=lambda item: item["chroma"]),
        "color_midtone": max(midtones, key=lambda item: item["chroma"]),
        "fine_detail": max(midtones, key=lambda item: item["detail"]),
    }
    clipped = [(pixel % width, pixel // width) for pixel, index in enumerate(range(0, len(rgb), 3)) if max(rgb[index:index + 3]) >= 254]
    if clipped:
        def clipped_in_tile(candidate: dict) -> int:
            return sum(candidate["x"] <= x < candidate["x"] + tile and candidate["y"] <= y < candidate["y"] + tile for x, y in clipped)

        selected["highlight_stress"] = max(candidates, key=clipped_in_tile)
    return selected


def percentile(histogram: list[int], count: int, fraction: float) -> int:
    target = count * fraction
    cumulative = 0
    for value, frequency in enumerate(histogram):
        cumulative += frequency
        if cumulative >= target:
            return value
    return 255


def analyze_tile(native: bytes, reference: bytes, width: int, x: int, y: int, tile: int) -> dict:
    channel_delta = [0, 0, 0]
    histogram = [0] * 256
    error = edge_error = 0
    edge_count = clipped_native = clipped_reference = 0
    count = tile * tile
    for row in range(y, y + tile):
        for column in range(x, x + tile):
            index = (row * width + column) * 3
            channel_error = 0
            for channel in range(3):
                delta = native[index + channel] - reference[index + channel]
                channel_delta[channel] += delta
                channel_error += abs(delta)
            error += channel_error
            histogram[max(abs(native[index + c] - reference[index + c]) for c in range(3))] += 1
            clipped_native += max(native[index:index + 3]) >= 254
            clipped_reference += max(reference[index:index + 3]) >= 254
            if row > y and column > x:
                value = luminance(native, index)
                gradient = abs(value - luminance(native, index - 3)) + abs(value - luminance(native, index - width * 3))
                if gradient >= 20:
                    edge_count += 1
                    edge_error += channel_error
    return {
        "mean_rgb_delta_8bit": [round(value / count, 3) for value in channel_delta],
        "mean_absolute_error_8bit": round(error / (count * 3), 3),
        "p95_max_channel_error_8bit": percentile(histogram, count, 0.95),
        "edge_pixels": edge_count,
        "edge_mean_absolute_error_8bit": round(edge_error / (edge_count * 3), 3) if edge_count else None,
        "clipped_pixels_native": clipped_native,
        "clipped_pixels_reference": clipped_reference,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("native", type=Path)
    parser.add_argument("reference", type=Path)
    parser.add_argument("--tile", type=int, default=512)
    parser.add_argument("--regions-from", type=Path, help="reuse tile coordinates from an earlier report for fair method comparisons")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    width, height, native = read_ppm(args.native)
    if args.tile < 32 or args.tile > min(width, height):
        raise ValueError("tile size must be between 32 and the image's smaller dimension")
    reference = reference_rgb(args.reference, width, height)
    selected = selected_tiles(native, width, height, args.tile)
    if args.regions_from:
        previous = json.loads(args.regions_from.read_text())
        if previous["dimensions"] != [width, height] or previous["tile_size"] != args.tile:
            raise ValueError("saved region dimensions or tile size differ")
        selected = {}
        for name, region in previous["regions"].items():
            x, y = region["x"], region["y"]
            if not (0 <= x <= width - args.tile and 0 <= y <= height - args.tile):
                raise ValueError(f"saved region {name} exceeds image bounds")
            selected[name] = {"x": x, "y": y, **tile_scores(native, width, x, y, args.tile)}
    report = {
        "native": str(args.native.resolve()),
        "reference": str(args.reference.resolve()),
        "dimensions": [width, height],
        "tile_size": args.tile,
        "regions_from": str(args.regions_from.resolve()) if args.regions_from else None,
        "selection": "Native RGB8 tile means and one-pixel gradients sampled every 16 pixels; highlight stress maximizes exact clipped-pixel count across candidate tiles. Low-chroma is not a calibrated neutral patch.",
        "global_clipped_pixels_native": sum(max(native[index:index + 3]) >= 254 for index in range(0, len(native), 3)),
        "global_clipped_pixels_reference": sum(max(reference[index:index + 3]) >= 254 for index in range(0, len(reference), 3)),
        "regions": {name: {**candidate, **analyze_tile(native, reference, width, candidate["x"], candidate["y"], args.tile)} for name, candidate in selected.items()},
    }
    result = json.dumps(report, indent=2) + "\n"
    if args.output:
        args.output.write_text(result)
    print(result, end="")


if __name__ == "__main__":
    main()
