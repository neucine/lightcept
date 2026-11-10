#!/usr/bin/env python3
"""Measure a saved Neiv preview against a TIFF rendered from the same edit."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import runpy
import struct
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
COMPILER = ROOT / "target/cyna-toolchain/cyna/zig-out/bin/cyna"
selected_edit = runpy.run_path(str(ROOT / "scripts/export-lightcept-project.py"))["selected_edit"]


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def compare(preview: bytes, resized: bytes) -> dict[str, object]:
    if len(preview) != len(resized) // 3 * 4 or len(resized) % 3:
        raise ValueError("comparison buffers have different dimensions")
    histogram = [0] * 256
    signed = 0
    for index, exported in enumerate(resized):
        pixel, channel = divmod(index, 3)
        difference = preview[pixel * 4 + channel] - exported
        histogram[abs(difference)] += 1
        signed += difference
    if any(preview[index] != 255 for index in range(3, len(preview), 4)):
        raise ValueError("saved preview contains nonopaque alpha")
    total = len(resized)
    cumulative = 0
    percentiles = {}
    for value, count in enumerate(histogram):
        cumulative += count
        for label, threshold in (("p95", 0.95), ("p99", 0.99)):
            if label not in percentiles and cumulative >= total * threshold:
                percentiles[label] = value
    return {
        "meanAbsoluteError8": sum(value * count for value, count in enumerate(histogram)) / total,
        "signedMeanError8": signed / total,
        "p95AbsoluteError8": percentiles["p95"],
        "p99AbsoluteError8": percentiles["p99"],
        "maximumAbsoluteError8": max(value for value, count in enumerate(histogram) if count),
        "fractionAbove8": sum(histogram[9:]) / total,
        "fractionAbove16": sum(histogram[17:]) / total,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=Path)
    parser.add_argument("tiff", type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    source, format_id, controls = selected_edit(args.project)
    project = json.loads(args.project.read_text(encoding="utf-8"))
    width, height = project["previewWidth"], project["previewHeight"]
    if not (1 <= width <= 2048 and 1 <= height <= 2048 and width * height <= 4194304):
        raise ValueError("project preview geometry is invalid")
    if not args.tiff.is_file():
        raise ValueError("TIFF does not exist")
    tiff_metadata = subprocess.check_output(
        ["magick", "identify", "-format", "%m|%w|%h|%[colorspace]|%z", str(args.tiff)],
        text=True,
    ).split("|")
    if len(tiff_metadata) != 5 or tiff_metadata[0] != "TIFF" or tiff_metadata[3] != "sRGB" or tiff_metadata[4] != "16":
        raise ValueError("export is not a 16-bit RGB TIFF")
    tiff_width, tiff_height = int(tiff_metadata[1]), int(tiff_metadata[2])
    if tiff_width < width or tiff_height < height:
        raise ValueError("export is smaller than the saved preview")
    environment = os.environ.copy()
    if sys.platform == "darwin":
        environment["SDKROOT"] = subprocess.check_output(["xcrun", "--show-sdk-path"], text=True).strip()
    with tempfile.TemporaryDirectory(prefix="lightcept-qualify-") as directory_value:
        directory = Path(directory_value)
        renderer = directory / "render-fitted-preview"
        request = directory / "request.bin"
        preview_path = directory / "preview.rgba"
        working_path = directory / "working.bin"
        subprocess.run([str(COMPILER), "build", "src/tools/render_fitted_preview.cyna.toml",
                        "--output", str(renderer)], cwd=ROOT, env=environment, check=True,
                       stdout=subprocess.DEVNULL)
        request.write_bytes(struct.pack("<15i", format_id, *controls, width, height))
        subprocess.run([str(renderer), str(source), str(request), str(preview_path),
                        str(working_path)], check=True)
        preview = preview_path.read_bytes()
        working = working_path.read_bytes()
        if len(preview) != width * height * 4 or digest(preview) != project["previewSHA256"]:
            raise ValueError("reconstructed preview does not match the saved project digest")
        if len(working) != width * height * 3 * 8 or digest(working) != project["workingSHA256"]:
            raise ValueError("reconstructed working frame does not match the saved project digest")
        results = {}
        for filter_name in ("Triangle", "Lanczos", "Box"):
            resized_path = directory / f"{filter_name.lower()}.rgb"
            subprocess.run(["magick", str(args.tiff), "-filter", filter_name,
                            "-resize", f"{width}x{height}!", "-alpha", "off", "-depth", "8",
                            f"RGB:{resized_path}"], check=True)
            results[filter_name] = compare(preview, resized_path.read_bytes())
    report = {
        "project": str(args.project.resolve()),
        "tiff": str(args.tiff.resolve()),
        "sourceSHA256": project["sourceSHA256"],
        "previewSHA256": project["previewSHA256"],
        "workingSHA256": project["workingSHA256"],
        "tiffSHA256": digest(args.tiff.read_bytes()),
        "previewWidth": width,
        "previewHeight": height,
        "tiffWidth": tiff_width,
        "tiffHeight": tiff_height,
        "comparison": results,
    }
    output = json.dumps(report, indent=2) + "\n"
    if args.report:
        args.report.write_text(output, encoding="utf-8")
    print(output, end="")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
        print(f"Qualification failed: {error}", file=sys.stderr)
        raise SystemExit(1) from error
