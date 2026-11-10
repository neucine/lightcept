#!/usr/bin/env python3
"""Export the selected schema-6 RAW edit through the headless Cyna TIFF route."""

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
EXPORTER = ROOT / "target/lightcept-export-tiff"
ICC = ROOT / "src/engine/assets/sRGB2014.icc"
ROUTES = {
    ".dng": (1, "dng_spatial_preview_texture_v5"),
    ".nef": (2, "nef_z8_lossless_preview_texture_v5"),
}


def integer(value: object, low: int, high: int) -> int:
    if type(value) is not int or value < low or value > high:
        raise ValueError("project contains an invalid integer")
    return value


def selected_edit(project_path: Path) -> tuple[Path, int, list[int]]:
    if project_path.stat().st_size > 16384:
        raise ValueError("project exceeds the supported size")
    project = json.loads(project_path.read_text(encoding="utf-8"))
    if not isinstance(project, dict) or project.get("schema") != 6:
        raise ValueError("only schema 6 project recipes are supported")
    source_value = project.get("sourcePath")
    if not isinstance(source_value, str) or not source_value.startswith("/"):
        raise ValueError("project source path is invalid")
    source = Path(source_value)
    route = ROUTES.get(source.suffix.lower())
    if route is None or project.get("routeID") != route[1]:
        raise ValueError("project render route is unavailable")
    history = project.get("history")
    if not isinstance(history, list) or not 1 <= len(history) <= 32:
        raise ValueError("project history is invalid")
    cursor = integer(project.get("cursor"), 0, len(history) - 1)
    integer(project.get("editRevision"), cursor, 0xFFFFFFFF)
    for entry in history:
        if not isinstance(entry, list) or len(entry) != 12:
            raise ValueError("project history entry is invalid")
        integer(entry[0], -40, 40)
        for value in entry[1:]:
            integer(value, -100, 100)
    if any(history[0]):
        raise ValueError("project source state must be neutral")
    for key in ("sourceSHA256", "workingSHA256", "baselineSHA256", "previewSHA256"):
        digest = project.get(key)
        if not isinstance(digest, str) or len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest):
            raise ValueError(f"project {key} is invalid")
    if not source.is_file() or source.stat().st_size > 512 * 1024 * 1024:
        raise ValueError("source photograph is missing or too large")
    digest = hashlib.sha256()
    with source.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    if digest.hexdigest() != project["sourceSHA256"]:
        raise ValueError("source photograph changed since the project was saved")
    return source, route[0], history[cursor]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    source, format_id, controls = selected_edit(args.project)
    output = args.output.resolve()
    if output.suffix.lower() not in (".tif", ".tiff"):
        raise ValueError("output must have a .tif or .tiff extension")
    if output == source.resolve() or output == args.project.resolve() or output.exists():
        raise ValueError("output path already exists or is a source file")
    if not output.parent.is_dir():
        raise ValueError("output directory does not exist")
    subprocess.run([str(ROOT / "scripts/check-cyna-toolchain.sh"), str(COMPILER)], check=True)
    environment = os.environ.copy()
    if sys.platform == "darwin":
        environment["SDKROOT"] = subprocess.check_output(["xcrun", "--show-sdk-path"], text=True).strip()
    subprocess.run([str(COMPILER), "build", "src/tools/export_tiff.cyna.toml", "--output", str(EXPORTER)],
                   cwd=ROOT, env=environment, check=True)
    with tempfile.TemporaryDirectory(prefix="lightcept-export-", dir=output.parent) as temporary:
        directory = Path(temporary)
        request = directory / "request.bin"
        temporary_tiff = directory / "render.tiff"
        request.write_bytes(struct.pack("<13i", format_id, *controls))
        subprocess.run([str(EXPORTER), str(source), str(ICC), str(request), str(temporary_tiff)], check=True)
        if temporary_tiff.stat().st_size < 3188:
            raise ValueError("export returned an incomplete TIFF")
        os.link(temporary_tiff, output)
    print(output)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
        print(f"Export failed: {error}", file=sys.stderr)
        raise SystemExit(1) from error
