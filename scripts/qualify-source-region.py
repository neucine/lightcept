#!/usr/bin/env python3
"""Compare a developed RAW source region with the same full-resolution TIFF pixels."""

import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--format", choices=("dng", "nef"), required=True)
    parser.add_argument("--left", type=int, required=True)
    parser.add_argument("--top", type=int, required=True)
    parser.add_argument("--width", type=int, required=True)
    parser.add_argument("--height", type=int, required=True)
    parser.add_argument("--tile-edge", type=int, default=0,
                        help="Render adjoining source tiles and compare their assembled pixels")
    parser.add_argument("--controls", default="0," * 11 + "0",
                        help="Twelve comma-separated signed integers in project entry order")
    parser.add_argument("--region-worker", type=Path,
                        default=ROOT / "ui/neiv/build/lightcept-source-region")
    parser.add_argument("--exporter", type=Path,
                        default=ROOT / "ui/neiv/build/lightcept-export-tiff")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    values = [int(value) for value in args.controls.split(",")]
    if len(values) != 12 or min(args.left, args.top) < 0 or min(args.width, args.height) < 1 or args.tile_edge < 0:
        parser.error("expected twelve controls and a positive source rectangle")
    format_id = 1 if args.format == "dng" else 2
    source_digest = digest(args.source)
    with tempfile.TemporaryDirectory(prefix="lightcept-region-") as directory_name:
        directory = Path(directory_name)
        region_request = directory / "region-request.bin"
        export_request = directory / "export-request.bin"
        rgba_path = directory / "region.rgba"
        tiff_path = directory / "full.tiff"
        rgb_path = directory / "export-region.rgb"
        export_request.write_bytes(struct.pack("<13i", format_id, *values))
        edge = args.tile_edge or max(args.width, args.height)
        rgba = bytearray(args.width * args.height * 4)
        for y in range(0, args.height, edge):
            for x in range(0, args.width, edge):
                tile_width = min(edge, args.width - x)
                tile_height = min(edge, args.height - y)
                region_request.write_bytes(struct.pack("<17i", format_id, *values,
                    args.left + x, args.top + y, tile_width, tile_height))
                subprocess.run([str(args.region_worker), str(args.source), str(region_request),
                                str(rgba_path)], check=True)
                tile = rgba_path.read_bytes()
                if len(tile) != tile_width * tile_height * 4:
                    raise ValueError("rendered tile has an incorrect shape")
                for row in range(tile_height):
                    destination = ((y + row) * args.width + x) * 4
                    source = row * tile_width * 4
                    rgba[destination:destination + tile_width * 4] = tile[source:source + tile_width * 4]
        subprocess.run([str(args.exporter), str(args.source),
                        str(ROOT / "src/engine/assets/sRGB2014.icc"),
                        str(export_request), str(tiff_path)], check=True)
        dimensions = subprocess.check_output(
            ["magick", "identify", "-format", "%w %h %[colorspace] %z", str(tiff_path)],
            text=True,
        ).split()
        if len(dimensions) != 4 or dimensions[2:] != ["sRGB", "16"]:
            raise ValueError("export is not a 16-bit sRGB TIFF")
        tiff_width, tiff_height = map(int, dimensions[:2])
        if args.left + args.width > tiff_width or args.top + args.height > tiff_height:
            raise ValueError("source rectangle exceeds exported TIFF")
        subprocess.run(["magick", str(tiff_path),
                        "-crop", f"{args.width}x{args.height}+{args.left}+{args.top}",
                        "+repage", "-alpha", "off", "-depth", "8", f"RGB:{rgb_path}"],
                       check=True)
        rgb = rgb_path.read_bytes()
        if len(rgba) != args.width * args.height * 4 or len(rgb) != args.width * args.height * 3:
            raise ValueError("rendered buffers have incorrect shapes")
        if any(rgba[index] != 255 for index in range(3, len(rgba), 4)):
            raise ValueError("source region is not opaque")
        differences = [abs(rgba[(index // 3) * 4 + index % 3] - value)
                       for index, value in enumerate(rgb)]
        result = {
            "source": str(args.source.resolve()),
            "sourceSHA256": source_digest,
            "format": args.format,
            "controls": values,
            "rectangle": [args.left, args.top, args.width, args.height],
            "tileEdge": args.tile_edge,
            "tiffDimensions": [tiff_width, tiff_height],
            "regionSHA256": hashlib.sha256(rgba).hexdigest(),
            "tiffSHA256": digest(tiff_path),
            "maximumAbsoluteDifference8": max(differences),
            "meanAbsoluteDifference8": sum(differences) / len(differences),
        }
    if digest(args.source) != source_digest:
        raise ValueError("source photograph changed during qualification")
    output = json.dumps(result, indent=2) + "\n"
    if args.report:
        args.report.write_text(output, encoding="utf-8")
    print(output, end="")
    if result["maximumAbsoluteDifference8"] > 1:
        raise SystemExit("source region and full-resolution export differ by more than one code")


if __name__ == "__main__":
    main()
