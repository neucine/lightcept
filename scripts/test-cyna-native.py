#!/usr/bin/env python3
"""Run native Cyna test roots in the static-library package."""

import re
import shutil
import subprocess
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CYNA_ROOT = ROOT / "src"
STAGE = ROOT / "target/native-test-package"
COMPILER = ROOT / "target/cyna-toolchain/cyna/zig-out/bin/cyna"


def stage_package() -> Path:
    if STAGE.exists():
        shutil.rmtree(STAGE)
    (STAGE / "src").mkdir(parents=True)
    shutil.copy2(ROOT / "cyna.toml", STAGE / "cyna.toml")
    shutil.copy2(CYNA_ROOT / "lib.cy", STAGE / "src/lib.cy")
    shutil.copytree(
        CYNA_ROOT / "engine",
        STAGE / "src/engine",
        ignore=shutil.ignore_patterns(".cyna-cache"),
    )
    return STAGE


def main() -> None:
    subprocess.run([str(ROOT / "scripts/check-cyna-toolchain.sh"), str(COMPILER)], check=True)
    package = stage_package()
    environment = os.environ.copy()
    if sys.platform == "darwin":
        environment["SDKROOT"] = subprocess.check_output(["xcrun", "--show-sdk-path"], text=True).strip()
    result = subprocess.run([str(COMPILER), "test", str(package)], cwd=ROOT, env=environment, capture_output=True, text=True, check=False)
    output = result.stdout + result.stderr
    print(output, end="")
    passed = re.search(r"tests passed: ([1-9][0-9]*)\b", output)
    if result.returncode or "error:" in output or not passed or "tests failed: 0" not in output:
        raise RuntimeError("Cyna native test roots did not pass")


if __name__ == "__main__":
    main()
