#!/usr/bin/env python3
"""Measure decoded RGB16 differences between two retained product TIFF files."""
import argparse
import array
import hashlib
import json
import runpy
import subprocess
import sys
from pathlib import Path


def compare(first, second):
    root = Path(__file__).resolve().parents[1]
    verify = runpy.run_path(str(root / 'scripts/verify-native-camera-tiff.py'))['tiff_identity']
    profile = (root / 'src/engine/assets/sRGB2014.icc').read_bytes()
    identities = [verify(p, profile) for p in (first, second)]
    if identities[0] != identities[1]:
        raise ValueError('TIFF geometry or ICC differs')
    images = []
    for path in (first, second):
        decoded = subprocess.run(['magick', str(path), '-endian', 'LSB', '-depth', '16', 'RGB:-'], check=True, capture_output=True).stdout
        channels = array.array('H'); channels.frombytes(decoded)
        if sys.byteorder != 'little': channels.byteswap()
        if len(channels) != identities[0][0] * identities[0][1] * 3:
            raise ValueError('unexpected decoded channel count')
        images.append(channels)
    maximum = count = 0
    examples = []
    width = identities[0][0]
    for i, (a, b) in enumerate(zip(*images)):
        if a != b:
            count += 1
            maximum = max(maximum, abs(a-b))
            if len(examples) < 16:
                examples.append({'x': i//3 % width, 'y': i//3//width, 'channel': i%3, 'first': a, 'second': b})
    return {'schema_version':1, 'dimensions':list(identities[0][:2]), 'icc_sha256':identities[0][2],
            'tiff_sha256':[hashlib.sha256(p.read_bytes()).hexdigest() for p in (first, second)],
            'compared_channels':len(images[0]), 'different_channels':count, 'max_rgb16_channel_delta':maximum,
            'first_differences':examples}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('first', type=Path); parser.add_argument('second', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.write_text(json.dumps(compare(args.first, args.second), indent=2)+'\n')


if __name__ == '__main__': main()
