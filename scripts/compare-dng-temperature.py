#!/usr/bin/env python3
"""Compare the pinned DNG ColorMatrix profile under two CCT estimators.

The SDK's published temperature table is read from a SHA-pinned upstream
source file kept outside Git. This diagnostic does not link or copy SDK code
into the product. The McCamy path matches the current Cyna method and is
independently checked against it by the Rust color_matrix_reference_tests.
"""

import argparse
import base64
import hashlib
import json
import math
import re
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SDK_URL = "https://android.googlesource.com/platform/external/dng_sdk/+/refs/heads/android14-prebuilt-test/source/dng_temperature.cpp?format=TEXT"
SDK_SHA256 = "39797f582384204dbe82bf37d17acc52073cc8db1da710d1f954fe7b37d16dc4"
SDK_PATH = ROOT / "target/dng-sdk-reference/dng_temperature.cpp"
D50 = (0.34567, 0.35850)
BRADFORD = ((0.8951, 0.2664, -0.1614), (-0.7502, 1.7135, 0.0367), (0.0389, -0.0685, 1.0296))


def inverse(matrix):
    rows = [list(row) + [float(index == column) for column in range(3)] for index, row in enumerate(matrix)]
    for column in range(3):
        pivot = max(range(column, 3), key=lambda row: abs(rows[row][column]))
        if abs(rows[pivot][column]) < 1e-10:
            raise ValueError("singular color matrix")
        rows[column], rows[pivot] = rows[pivot], rows[column]
        divisor = rows[column][column]
        rows[column] = [value / divisor for value in rows[column]]
        for row in range(3):
            if row != column:
                factor = rows[row][column]
                rows[row] = [value - factor * base for value, base in zip(rows[row], rows[column])]
    return tuple(tuple(row[3:]) for row in rows)


def product(left, right):
    return tuple(tuple(sum(left[row][k] * right[k][column] for k in range(3)) for column in range(3)) for row in range(3))


def apply(matrix, vector):
    return tuple(sum(a * b for a, b in zip(row, vector)) for row in matrix)


def xyz_from_xy(white):
    x, y = white
    return (x / y, 1.0, (1.0 - x - y) / y)


def xy_from_xyz(xyz):
    total = sum(xyz)
    if total <= 0:
        raise ValueError("invalid camera white")
    return (xyz[0] / total, xyz[1] / total)


def mccamy(white):
    n = (white[0] - 0.3320) / (white[1] - 0.1858)
    return ((-449.0 * n + 3525.0) * n - 6823.3) * n + 5520.33


def sdk_table(source):
    digest = hashlib.sha256(source).hexdigest()
    if digest != SDK_SHA256:
        raise ValueError(f"SDK source SHA-256 differs: {digest}")
    section = source.decode("utf-8").split("kTempTable [] =", 1)[1].split("};", 1)[0]
    rows = re.findall(r"\{\s*(\d+),\s*([\d.]+),\s*([\d.]+),\s*([-\d.]+)\s*\}", section)
    if len(rows) != 31:
        raise ValueError(f"expected 31 SDK temperature rows, found {len(rows)}")
    return [tuple(float(value) for value in row) for row in rows]


def robertson(white, table):
    x, y = white
    denominator = 1.5 - x + 6.0 * y
    u, v = 2.0 * x / denominator, 3.0 * y / denominator
    previous_distance = 0.0
    for index in range(1, len(table)):
        reciprocal, line_u, line_v, slope = table[index]
        norm = math.hypot(1.0, slope)
        direction_u, direction_v = 1.0 / norm, slope / norm
        distance = -(u - line_u) * direction_v + (v - line_v) * direction_u
        if distance <= 0.0 or index == len(table) - 1:
            distance = max(-distance, 0.0)
            fraction = 0.0 if index == 1 else distance / (previous_distance + distance)
            inverse_temperature = table[index - 1][0] * fraction + reciprocal * (1.0 - fraction)
            return 1_000_000.0 / inverse_temperature
        previous_distance = distance
    raise ValueError("temperature lookup did not converge")


def solve(profile, temperature):
    first = tuple(tuple(profile["expected_color_matrix1"][row * 3:row * 3 + 3]) for row in range(3))
    second = tuple(tuple(profile["expected_color_matrix2"][row * 3:row * 3 + 3]) for row in range(3))
    neutral = tuple(profile["expected_as_shot_neutral"])
    white = D50
    for _ in range(30):
        kelvin = temperature(white)
        weight = max(0.0, min(1.0, (1.0 / kelvin - 1.0 / 6504.0) / (1.0 / 2856.0 - 1.0 / 6504.0)))
        blended = tuple(tuple(weight * first[row][column] + (1.0 - weight) * second[row][column] for column in range(3)) for row in range(3))
        next_white = xy_from_xyz(apply(inverse(blended), neutral))
        if max(abs(a - b) for a, b in zip(next_white, white)) < 1e-7:
            white = next_white
            break
        white = next_white
    else:
        raise ValueError("camera-white solve did not converge")
    kelvin = temperature(white)
    weight = max(0.0, min(1.0, (1.0 / kelvin - 1.0 / 6504.0) / (1.0 / 2856.0 - 1.0 / 6504.0)))
    blended = tuple(tuple(weight * first[row][column] + (1.0 - weight) * second[row][column] for column in range(3)) for row in range(3))
    source = apply(BRADFORD, xyz_from_xy(white))
    target = apply(BRADFORD, xyz_from_xy(D50))
    diagonal = tuple(tuple(target[row] / source[row] if row == column else 0.0 for column in range(3)) for row in range(3))
    adapted = product(product(inverse(BRADFORD), diagonal), BRADFORD)
    matrix = product(adapted, inverse(blended))
    return {"white_xy": white, "cct_kelvin": kelvin, "first_matrix_weight": weight, "camera_to_xyz_d50": [value for row in matrix for value in row]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk-source", type=Path, default=SDK_PATH)
    parser.add_argument("--fetch-sdk", action="store_true", help="fetch the SHA-pinned upstream reference source")
    args = parser.parse_args()
    if args.fetch_sdk:
        encoded = urllib.request.urlopen(SDK_URL, timeout=30).read()
        source = base64.b64decode(encoded)
        sdk_table(source)
        args.sdk_source.parent.mkdir(parents=True, exist_ok=True)
        args.sdk_source.write_bytes(source)
    table = sdk_table(args.sdk_source.read_bytes())
    manifest = json.loads((ROOT / "qualification/native-sources.json").read_text())
    for profile in manifest["sources"]:
        if "expected_color_matrix1" not in profile:
            continue
        current = solve(profile, mccamy)
        reference = solve(profile, lambda xy: robertson(xy, table))
        print(json.dumps({
            "id": profile["id"],
            "current_mccamy": current,
            "sdk_table_reference": reference,
            "cct_delta_kelvin": reference["cct_kelvin"] - current["cct_kelvin"],
            "max_matrix_entry_delta": max(abs(a - b) for a, b in zip(reference["camera_to_xyz_d50"], current["camera_to_xyz_d50"])),
        }))


if __name__ == "__main__":
    main()
