#!/usr/bin/env python3
"""Exercise the engine import guard with representative boundary regressions."""

import subprocess
import tempfile
from pathlib import Path

CHECKER = Path(__file__).with_name("check-engine-boundaries.py")


def check(importing: str, source: str) -> subprocess.CompletedProcess[str]:
    with tempfile.TemporaryDirectory(prefix="lightcept-boundary-") as directory:
        root = Path(directory)
        target = root / "src" / "engine" / importing
        target.parent.mkdir(parents=True)
        target.write_text(source)
        return subprocess.run(
            ["python3", str(CHECKER), str(root)], capture_output=True, text=True
        )


assert check("raw/dng/dng_mosaic.cy", "import .engine.color.dng.dng_color_matrix;\n").returncode == 0
for path, source, diagnostic in [
    ("raw/bayer.cy", "import .engine.raw.dng.dng_source;\n", "shared module may not import dng"),
    ("raw/bayer.cy", "import { DngInfo } from .engine.raw.dng.dng_source;\n", "shared module may not import dng"),
    ("color/color_matrix.cy", "import .engine.raw.dng.dng_profile;\n", "shared module may not import dng"),
    ("color/dng/dng_color.cy", "import .engine.raw.dng.dng_source;\n", "typed DNG profile values"),
    ("develop/edit_plan.cy", "import .engine.pipeline.pipeline;\n", "develop may not import pipeline"),
    ("render/render.cy", "import .engine.pipeline.pipeline;\n", "render may not import pipeline"),
    ("pipeline/nef/nef_pipeline.cy", "import .engine.raw.dng.dng_source;\n", "nef module may not import dng"),
    ("render/dng_preview.cy", "pub fn preview(): void {}\n", "format-specific module belongs"),
    ("raw/cr3/cr3_source.cy", "pub fn inspect(): void {}\n", "register new format"),
]:
    result = check(path, source)
    assert result.returncode == 1 and diagnostic in result.stderr, (path, result.stderr)
print("engine boundary guard: passed")
