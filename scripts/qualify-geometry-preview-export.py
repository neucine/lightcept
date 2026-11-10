#!/usr/bin/env python3
"""Compare headless geometry preview and TIFF pixels for one RAW source."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
COMPILER = ROOT / "target/cyna-toolchain/cyna/zig-out/bin/cyna"
ICC = ROOT / "src/engine/assets/sRGB2014.icc"


def digest(path: Path) -> str:
    sha = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            sha.update(block)
    return sha.hexdigest()


def build(manifest: str, destination: Path) -> None:
    environment = os.environ.copy()
    if sys.platform == "darwin":
        environment["SDKROOT"] = subprocess.check_output(
            ["xcrun", "--show-sdk-path"], text=True
        ).strip()
    subprocess.run(
        [str(COMPILER), "build", manifest, "--output", str(destination)],
        cwd=ROOT,
        env=environment,
        check=True,
    )


def tiff_pixels(path: Path, expected_width: int, expected_height: int) -> bytes:
    data = path.read_bytes()
    if len(data) < 164 or data[:4] != b"II*\x00":
        raise ValueError("output is not a supported little-endian TIFF")
    width, height, offset = (struct.unpack_from("<I", data, position)[0]
                             for position in (18, 30, 78))
    if (width, height) != (expected_width, expected_height):
        raise ValueError("TIFF dimensions do not match the selected crop")
    if len(data) != offset + width * height * 6:
        raise ValueError("TIFF pixel buffer has an invalid length")
    return data[offset:]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--left", type=int, required=True)
    parser.add_argument("--top", type=int, required=True)
    parser.add_argument("--width", type=int, required=True)
    parser.add_argument("--height", type=int, required=True)
    parser.add_argument("--angle-millidegrees", type=int, default=0)
    parser.add_argument("--transform-code", type=int,
                        help="use v3 quarter-turn/mirror code 1..8")
    parser.add_argument("--controls", type=int, nargs=12, default=[0] * 12)
    parser.add_argument("--exporter", type=Path)
    parser.add_argument("--preview-worker", type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    source = args.source.resolve(strict=True)
    format_id = {".dng": 1, ".nef": 2}.get(source.suffix.lower())
    if format_id is None:
        raise ValueError("source must be a supported DNG or NEF")
    if (not 1 <= args.width <= 2048 or not 1 <= args.height <= 2048 or
            args.width * args.height > 4194304 or
            not 0 <= args.left <= 10000 or not 0 <= args.top <= 10000 or
            not -17000 <= args.angle_millidegrees <= 17000 or
            (args.transform_code is not None and not 1 <= args.transform_code <= 8) or
            not -40 <= args.controls[0] <= 40 or
            any(not -100 <= value <= 100 for value in args.controls[1:])):
        raise ValueError("request geometry or controls are outside supported bounds")
    subprocess.run([str(ROOT / "scripts/check-cyna-toolchain.sh"), str(COMPILER)], check=True)
    before = digest(source)
    with tempfile.TemporaryDirectory(prefix="lightcept-geometry-qualify-") as location:
        directory = Path(location)
        exporter = args.exporter.resolve(strict=True) if args.exporter else directory / "export-tiff"
        preview_worker = (args.preview_worker.resolve(strict=True) if args.preview_worker
                          else directory / "render-preview")
        if args.exporter is None:
            build("src/tools/export_tiff.cyna.toml", exporter)
        if args.preview_worker is None:
            build("src/tools/render_fitted_preview.cyna.toml", preview_worker)
        export_request = directory / "export-request.bin"
        preview_request = directory / "preview-request.bin"
        version = 3 if args.transform_code is not None else 2
        transform = [args.transform_code] if args.transform_code is not None else []
        export_values = [version, format_id, *args.controls, args.left, args.top,
                         args.width, args.height, args.angle_millidegrees, *transform]
        preview_values = [version, format_id, *args.controls,
                          args.width, args.height, args.left, args.top,
                          args.width, args.height, args.angle_millidegrees, *transform]
        export_request.write_bytes(struct.pack(f"<{len(export_values)}i", *export_values))
        preview_request.write_bytes(struct.pack(f"<{len(preview_values)}i", *preview_values))
        tiff_path = directory / "geometry.tiff"
        rgba_path = directory / "preview.rgba"
        working_path = directory / "preview.working"
        subprocess.run([str(exporter), str(source), str(ICC),
                        str(export_request), str(tiff_path)], check=True)
        subprocess.run([str(preview_worker), str(source), str(preview_request),
                        str(rgba_path), str(working_path)], check=True)
        rgb16 = tiff_pixels(tiff_path, args.width, args.height)
        preview = rgba_path.read_bytes()
        if len(preview) != args.width * args.height * 4 or any(
                preview[index] != 255 for index in range(3, len(preview), 4)):
            raise ValueError("preview is not exact opaque RGBA8")
        if working_path.stat().st_size != args.width * args.height * 3 * 8:
            raise ValueError("fitted working frame has an invalid length")
        samples = struct.iter_unpack("<H", rgb16)
        differences = [abs(preview[(index // 3) * 4 + index % 3] - round(word / 257))
                       for index, (word,) in enumerate(samples)]
        report = {
            "source": str(source),
            "sourceSHA256": before,
            "crop": [args.left, args.top, args.width, args.height],
            "angleMillidegrees": args.angle_millidegrees,
            "transformCode": args.transform_code,
            "controls": args.controls,
            "channels": len(differences),
            "maximumAbsoluteRGB8Difference": max(differences),
            "meanAbsoluteRGB8Difference": sum(differences) / len(differences),
            "previewSHA256": hashlib.sha256(preview).hexdigest(),
            "tiffSHA256": digest(tiff_path),
        }
    if digest(source) != before:
        raise ValueError("source photograph changed during qualification")
    rendered = json.dumps(report, indent=2) + "\n"
    if args.report:
        args.report.write_text(rendered, encoding="utf-8")
    print(rendered, end="")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"Geometry qualification failed: {error}", file=sys.stderr)
        raise SystemExit(1) from error
