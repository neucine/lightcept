#!/usr/bin/env python3
"""Run native Cyna test roots in the static-library package."""

import re
import subprocess
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CYNA_ROOT = ROOT / "src"
COMPILER = ROOT / "target/cyna-toolchain/cyna/zig-out/bin/cyna"


def main() -> None:
    subprocess.run([str(ROOT / "scripts/check-cyna-toolchain.sh"), str(COMPILER)], check=True)
    environment = os.environ.copy()
    if sys.platform == "darwin":
        environment["SDKROOT"] = subprocess.check_output(["xcrun", "--show-sdk-path"], text=True).strip()
    result = subprocess.run([str(COMPILER), "test", str(CYNA_ROOT)], cwd=ROOT, env=environment, capture_output=True, text=True, check=False)
    output = result.stdout + result.stderr
    print(output, end="")
    passed = re.search(r"tests passed: ([1-9][0-9]*)\b", output)
    if result.returncode or "error:" in output or not passed or "tests failed: 0" not in output:
        raise RuntimeError("Cyna native test roots did not pass")


if __name__ == "__main__":
    main()
