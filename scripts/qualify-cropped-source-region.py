#!/usr/bin/env python3
"""Compare a crop-relative source tile with the same geometry TIFF pixels."""

import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--format", choices=("dng", "nef"), required=True)
    parser.add_argument("--crop", type=int, nargs=4, metavar=("LEFT", "TOP", "WIDTH", "HEIGHT"), required=True)
    parser.add_argument("--tile", type=int, nargs=4, metavar=("LEFT", "TOP", "WIDTH", "HEIGHT"), required=True)
    parser.add_argument("--controls", default="0," * 11 + "0")
    parser.add_argument("--angle-millidegrees", type=int, default=0)
    parser.add_argument("--transform-code", type=int,
                        help="use v3 quarter-turn/mirror code 1..8")
    parser.add_argument("--region-worker", type=Path,
                        default=ROOT / "ui/neiv/build/lightcept-source-region")
    parser.add_argument("--exporter", type=Path,
                        default=ROOT / "ui/neiv/build/lightcept-export-tiff")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    controls = [int(value) for value in args.controls.split(",")]
    crop_left, crop_top, crop_width, crop_height = args.crop
    tile_left, tile_top, tile_width, tile_height = args.tile
    if len(controls) != 12 or min(args.crop) < 0 or min(args.tile) < 0 or min(crop_width, crop_height, tile_width, tile_height) == 0:
        parser.error("expected twelve controls and positive crop and tile extents")
    if tile_left + tile_width > crop_width or tile_top + tile_height > crop_height:
        parser.error("tile exceeds crop")
    if args.transform_code is not None and not 1 <= args.transform_code <= 8:
        parser.error("transform code must be 1..8")
    format_id = 1 if args.format == "dng" else 2
    before = digest(args.source)
    with tempfile.TemporaryDirectory(prefix="lightcept-crop-region-") as directory_name:
        directory = Path(directory_name)
        region_request = directory / "region.bin"
        export_request = directory / "export.bin"
        region_path = directory / "tile.rgba"
        tiff_path = directory / "crop.tiff"
        rgb_path = directory / "tile.rgb"
        version = 3 if args.transform_code is not None else 2
        transform = [args.transform_code] if args.transform_code is not None else []
        region_values = [version, format_id, *controls,
                         tile_left, tile_top, tile_width, tile_height,
                         crop_left, crop_top, crop_width, crop_height,
                         args.angle_millidegrees, *transform]
        export_values = [version, format_id, *controls,
                         crop_left, crop_top, crop_width, crop_height,
                         args.angle_millidegrees, *transform]
        region_request.write_bytes(struct.pack(f"<{len(region_values)}i", *region_values))
        export_request.write_bytes(struct.pack(f"<{len(export_values)}i", *export_values))
        subprocess.run([str(args.region_worker), str(args.source), str(region_request),
                        str(region_path)], check=True)
        subprocess.run([str(args.exporter), str(args.source),
                        str(ROOT / "src/engine/assets/sRGB2014.icc"),
                        str(export_request), str(tiff_path)], check=True)
        dimensions = subprocess.check_output(["magick", "identify", "-format", "%w %h %z",
                                               str(tiff_path)], text=True).split()
        if dimensions != [str(crop_width), str(crop_height), "16"]:
            raise ValueError("geometry TIFF dimensions or depth differ")
        subprocess.run(["magick", str(tiff_path), "-crop",
                        f"{tile_width}x{tile_height}+{tile_left}+{tile_top}",
                        "+repage", "-alpha", "off", "-depth", "8", f"RGB:{rgb_path}"],
                       check=True)
        rgba = region_path.read_bytes()
        rgb = rgb_path.read_bytes()
        if len(rgba) != tile_width * tile_height * 4 or len(rgb) != tile_width * tile_height * 3:
            raise ValueError("tile output has the wrong length")
        if any(rgba[index] != 255 for index in range(3, len(rgba), 4)):
            raise ValueError("tile alpha is not opaque")
        differences = [abs(rgba[(index // 3) * 4 + index % 3] - channel)
                       for index, channel in enumerate(rgb)]
        result = {
            "source": str(args.source.resolve()),
            "sourceSHA256": before,
            "format": args.format,
            "crop": args.crop,
            "tile": args.tile,
            "controls": controls,
            "angleMillidegrees": args.angle_millidegrees,
            "transformCode": args.transform_code,
            "regionSHA256": hashlib.sha256(rgba).hexdigest(),
            "tiffSHA256": digest(tiff_path),
            "maximumAbsoluteDifference8": max(differences),
            "meanAbsoluteDifference8": sum(differences) / len(differences),
        }
    if digest(args.source) != before:
        raise ValueError("source photograph changed during qualification")
    output = json.dumps(result, indent=2) + "\n"
    if args.report:
        args.report.write_text(output, encoding="utf-8")
    print(output, end="")
    if result["maximumAbsoluteDifference8"] > 1:
        raise SystemExit("crop-relative tile differs from geometry TIFF")


if __name__ == "__main__":
    main()
