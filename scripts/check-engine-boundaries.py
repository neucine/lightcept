#!/usr/bin/env python3
"""Enforce production Cyna engine dependencies and format ownership."""

from __future__ import annotations

import re
import sys
from pathlib import Path

COMPONENTS = {"core", "tiff", "raw", "color", "develop", "analysis", "render", "pipeline"}
FORMATS = {"dng", "nef"}
ALLOWED = {
    "core": set(),
    "tiff": {"core"},
    "raw": {"core", "tiff", "color"},
    "color": {"core", "raw"},
    "develop": {"core", "color"},
    "analysis": {"core", "develop"},
    "render": {"core", "raw", "color", "develop"},
    "pipeline": COMPONENTS - {"pipeline"},
}
IMPORT = re.compile(r"\.engine\.([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)")


def check(root: Path) -> list[str]:
    engine = root / "src" / "engine"
    failures: list[str] = []
    raw = engine / "raw"
    if raw.exists():
        for directory in sorted(path for path in raw.iterdir() if path.is_dir() and not path.name.startswith(".")):
            if directory.name not in FORMATS:
                failures.append(f"raw/{directory.name}: register new format in engine boundary checker")
    for source in sorted(engine.rglob("*.cy")):
        if source.name.endswith(".test.cy") or source == engine / "lib.cy":
            continue
        relative = source.relative_to(engine)
        parts = relative.parts
        if any(part.startswith(".") for part in parts):
            continue
        component = parts[0]
        if component not in COMPONENTS:
            failures.append(f"{relative}: unknown engine component {component}")
            continue
        source_format = parts[1] if len(parts) > 2 and parts[1] in FORMATS else None
        if source_format is None and any(source.stem.startswith(f"{name}_") for name in FORMATS):
            failures.append(f"{relative}: format-specific module belongs in its format folder")
        for number, line in enumerate(source.read_text().splitlines(), 1):
            if not line.lstrip().startswith("import "):
                continue
            match = IMPORT.search(line)
            if not match:
                continue
            target = match.group(1).split(".")
            target_component = target[0]
            target_format = target[1] if len(target) > 2 and target[1] in FORMATS else None
            location = f"{relative}:{number}"
            if target_component not in COMPONENTS:
                failures.append(f"{location}: unknown engine import {match.group(0)}")
                continue
            if target_component != component and target_component not in ALLOWED[component]:
                failures.append(f"{location}: {component} may not import {target_component}")
            if source_format is None and target_format is not None:
                failures.append(f"{location}: shared module may not import {target_format} module")
            elif source_format is not None and target_format is not None and source_format != target_format:
                failures.append(f"{location}: {source_format} module may not import {target_format} module")
            if component == "raw" and target_component == "color" and source_format is None:
                failures.append(f"{location}: shared RAW module may not import color characterization")
            if component == "color" and target_component == "raw" and (
                source_format != "dng" or target[:3] != ["raw", "dng", "dng_profile"]
            ):
                failures.append(f"{location}: color may consume only typed DNG profile values from RAW")
    return failures


def main() -> int:
    root = Path(sys.argv[1]).resolve() if len(sys.argv) == 2 else Path(__file__).resolve().parents[1]
    failures = check(root)
    for failure in failures:
        print(failure, file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
