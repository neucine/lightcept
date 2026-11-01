#!/usr/bin/env python3
"""Trace magenta pixels in a 512x512 review panel to decoded Bayer clipping.

The panel is baseline left, diagnostic right. The sensor file is the u16le
output of the native decode_sensor example; DNG geometry is supplied explicitly.
"""

import argparse
import mmap
import struct
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("panel", type=Path)
    parser.add_argument("sensor_u16le", type=Path)
    parser.add_argument("--tile-origin", nargs=2, type=int, required=True, metavar=("X", "Y"))
    parser.add_argument("--stored-width", type=int, required=True)
    parser.add_argument("--crop-origin", nargs=2, type=int, required=True, metavar=("X", "Y"))
    parser.add_argument("--black", type=int, required=True)
    parser.add_argument("--white", type=int, required=True)
    parser.add_argument("--scan-tile", action="store_true", help="count every pixel newly flagged by a 3x3 sensor-neighbor rule")
    args = parser.parse_args()
    if args.stored_width <= 0 or not 0 <= args.black < args.white:
        parser.error("invalid sensor geometry or levels")

    pixels = subprocess.check_output([
        "magick", str(args.panel), "-crop", "512x512+512+0", "+repage", "RGB:-"
    ])
    if len(pixels) != 512 * 512 * 3:
        parser.error("the right panel must be 512x512 RGB8")
    residual = [i for i, (r, g, b) in enumerate(zip(pixels[0::3], pixels[1::3], pixels[2::3]))
                if r >= 180 and b >= 180 and min(r, b) - g >= 40]

    with args.sensor_u16le.open("rb") as file, mmap.mmap(file.fileno(), 0, access=mmap.ACCESS_READ) as sensor:
        if len(sensor) % (2 * args.stored_width):
            parser.error("sensor length is not a whole number of stored rows")
        stored_height = len(sensor) // (2 * args.stored_width)

        def code(x, y):
            sx, sy = x + args.crop_origin[0], y + args.crop_origin[1]
            if not 0 <= sx < args.stored_width or not 0 <= sy < stored_height:
                parser.error("tile neighborhood lies outside the stored sensor raster")
            return struct.unpack_from("<H", sensor, 2 * (sy * args.stored_width + sx))[0]

        def normalized(x, y):
            value = max(0.0, min(1.0, (code(x, y) - args.black) / (args.white - args.black)))
            return struct.unpack("<f", struct.pack("<f", value))[0]

        def channel(x, y, wanted):
            values = [normalized(xx, yy) for xx, yy in contributors(x, y, wanted)]
            return sum(values) / len(values)

        def contributors(x, y, wanted):
            cfa = (0, 1, 1, 2)  # RGGB, at crop origin
            if cfa[(y % 2) * 2 + x % 2] == wanted:
                return [(x, y)]
            return [(xx, yy) for yy in range(y - 1, y + 2)
                    for xx in range(x - 1, x + 2)
                    if cfa[(yy % 2) * 2 + xx % 2] == wanted]

        clipped_neighborhood = 0
        under_stage_threshold = 0
        under_threshold_with_clipped_contributor = 0
        for index in residual:
            x = args.tile_origin[0] + index % 512
            y = args.tile_origin[1] + index // 512
            if any(code(x + dx, y + dy) >= args.white
                   for dy in (-1, 0, 1) for dx in (-1, 0, 1)):
                clipped_neighborhood += 1
            if max(channel(x, y, c) for c in range(3)) < 0.99:
                under_stage_threshold += 1
                if any(code(xx, yy) >= args.white for c in range(3)
                       for xx, yy in contributors(x, y, c)):
                    under_threshold_with_clipped_contributor += 1

        newly_flagged = 0
        newly_flagged_from_contributors = 0
        if args.scan_tile:
            for index in range(512 * 512):
                x = args.tile_origin[0] + index % 512
                y = args.tile_origin[1] + index // 512
                if not any(code(x + dx, y + dy) >= args.white
                           for dy in (-1, 0, 1) for dx in (-1, 0, 1)):
                    continue
                if max(channel(x, y, c) for c in range(3)) < 0.99:
                    newly_flagged += 1
                    if any(code(xx, yy) >= args.white for c in range(3)
                           for xx, yy in contributors(x, y, c)):
                        newly_flagged_from_contributors += 1

    print(f"magenta pixels: {len(residual)}")
    print(f"with saturated sensor sample in 3x3: {clipped_neighborhood}")
    print(f"with all bilinear channels below 0.99: {under_stage_threshold}")
    print(f"below threshold with clipped demosaic contributor: {under_threshold_with_clipped_contributor}")
    print(f"at or above stage threshold: {len(residual) - under_stage_threshold}")
    if args.scan_tile:
        print(f"additional tile pixels flagged by 3x3 sensor-neighbor rule: {newly_flagged}")
        print(f"additional tile pixels flagged by demosaic-contributor rule: {newly_flagged_from_contributors}")


if __name__ == "__main__":
    main()
