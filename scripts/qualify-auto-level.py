#!/usr/bin/env python3
"""Record auto-level v1 observations on the pinned RAW preview fixtures."""

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
PROBE = ROOT / "target/lightcept-auto-level-probe"
REPORT = ROOT / "target/geometry-export-check/auto-level-v1-raw-previews.json"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run_probe(request: Path, luma: Path) -> dict:
    values = subprocess.check_output([str(PROBE), str(request), str(luma)], text=True)
    version, status, angle, votes, edges = map(int, values.splitlines())
    return dict(version=version, status=status, angleMillidegrees=angle,
                votes=votes, edgePixels=edges)


def main() -> None:
    env = os.environ.copy()
    if sys.platform == "darwin":
        env["SDKROOT"] = subprocess.check_output(["xcrun", "--show-sdk-path"], text=True).strip()
    subprocess.run([str(ROOT / "scripts/check-cyna-toolchain.sh"), str(COMPILER)], check=True)
    subprocess.run([str(COMPILER), "build", str(ROOT / "src/tools/auto_level_probe.cyna.toml"),
                    "--output", str(PROBE)], cwd=ROOT, env=env, check=True)

    sources = {
        "ricoh": ROOT / "target/native-source-corpus/Ricoh-GR-IIIx.DNG",
        "nikon": ROOT / "target/nikon-reference/_Z8A8027.NEF",
    }
    previews = {
        "ricoh": ROOT / "target/neiv-ricoh-fitted.png",
        "nikon": ROOT / "target/neiv-nikon-fitted.rgba",
    }
    before = {name: digest(path) for name, path in sources.items()}
    observations = {}
    with tempfile.TemporaryDirectory(prefix="lightcept-auto-level-") as name:
        directory = Path(name)
        request = directory / "size.bin"
        request.write_bytes(struct.pack("<II", 2048, 1365))
        for photo, preview in previews.items():
            luma = directory / f"{photo}.u8"
            if photo == "ricoh":
                subprocess.run(["magick", str(preview), "-colorspace", "Gray",
                                "-depth", "8", f"gray:{luma}"], check=True)
            else:
                if preview.stat().st_size != 2048 * 1365 * 4:
                    raise ValueError("Nikon preview dimensions changed")
                subprocess.run(["magick", "-size", "2048x1365", "-depth", "8",
                                f"RGBA:{preview}", "-colorspace", "Gray", "-depth", "8",
                                f"gray:{luma}"], check=True)
            if luma.stat().st_size != 2048 * 1365:
                raise ValueError("luminance conversion dimensions changed")
            observations[photo] = {
                "source": str(sources[photo]),
                "sourceSHA256": before[photo],
                "preview": str(preview),
                "previewSHA256": digest(preview),
                "luminanceSHA256": digest(luma),
                "inputWidth": 2048,
                "inputHeight": 1365,
                "estimate": run_probe(request, luma),
            }
    if {name: digest(path) for name, path in sources.items()} != before:
        raise ValueError("RAW source changed")
    if observations["nikon"]["estimate"]["status"] != 2:
        raise ValueError("flower image unexpectedly reported a horizon")
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(observations, indent=2) + "\n")
    print(REPORT)


if __name__ == "__main__":
    main()
