#!/usr/bin/env python3
"""Create a 1:1 preview/JPEG contact sheet from a saved region report.

Each row follows report['regions'] order: left is Cyna preview, right is decoded
JPEG. The tool uses ImageMagick only for cropping and lossless PNG assembly.
"""

import argparse
import json
import subprocess
import tempfile
from pathlib import Path


def dimensions(path: Path) -> tuple[int, int]:
    value = subprocess.run(["magick", "identify", "-format", "%w %h", str(path)], check=True, capture_output=True, text=True).stdout
    width, height = value.split()
    return int(width), int(height)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("preview_ppm", type=Path)
    parser.add_argument("jpeg", type=Path)
    parser.add_argument("output_png", type=Path)
    args = parser.parse_args()
    report = json.loads(args.report.read_text())
    width, height = report["dimensions"]
    tile = report["tile_size"]
    if dimensions(args.preview_ppm) != (width, height) or dimensions(args.jpeg) != (width, height):
        raise ValueError("input dimensions differ from saved region report")
    if not report["regions"]:
        raise ValueError("region report is empty")
    with tempfile.TemporaryDirectory(prefix="lightcept-export-review-") as temporary:
        rows = []
        for index, (name, region) in enumerate(report["regions"].items(), 1):
            x, y = region["x"], region["y"]
            if not (0 <= x <= width - tile and 0 <= y <= height - tile):
                raise ValueError(f"region {name} exceeds image bounds")
            crops = []
            for label, source in (("preview", args.preview_ppm), ("jpeg", args.jpeg)):
                crop = Path(temporary) / f"{index:02}-{label}.png"
                subprocess.run(["magick", str(source), "-crop", f"{tile}x{tile}+{x}+{y}", "+repage", str(crop)], check=True)
                crops.append(str(crop))
            row = Path(temporary) / f"{index:02}-pair.png"
            subprocess.run(["magick", *crops, "+append", str(row)], check=True)
            rows.append(str(row))
        args.output_png.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["magick", *rows, "-append", str(args.output_png)], check=True)
    print(json.dumps({"contact_sheet": str(args.output_png), "row_order": list(report["regions"]), "columns": ["Cyna preview", "decoded JPEG"]}))


if __name__ == "__main__":
    main()
